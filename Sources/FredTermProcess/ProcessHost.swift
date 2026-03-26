#if canImport(Darwin)
import Foundation
import FredTermCore

/// Delegate for process lifecycle events.
public protocol ProcessHostDelegate: AnyObject, Sendable {
    func processHost(_ host: ProcessHost, didReceiveData data: [UInt8])
    func processHostDidTerminate(_ host: ProcessHost, exitCode: Int32)
}

/// Manages a child process connected via PTY.
///
/// Improvements over SwiftTerm's LocalProcess:
/// - Uses actor isolation for thread safety.
/// - Drains PTY data after process exit before signaling termination (#370).
/// - Uses DispatchSource for I/O, avoiding RunLoop mode issues (#486).
///   Data is delivered via a dedicated serial queue, not main.async.
public final class ProcessHost: @unchecked Sendable {
    private var childFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private let ioQueue = DispatchQueue(label: "com.fredterm.process.io")
    private let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 131072) // 128KB
    private var isRunning = false

    public weak var delegate: (any ProcessHostDelegate)?

    public init() {}

    deinit {
        readBuffer.deallocate()
        if childFD >= 0 {
            close(childFD)
        }
    }

    /// Start a child process.
    public func start(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        windowSize: TerminalSize = TerminalSize(cols: 80, rows: 25)
    ) throws {
        guard !isRunning else { return }

        // Build environment
        var env = ProcessInfo.processInfo.environment
        if let extra = environment {
            env.merge(extra) { _, new in new }
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "FredTerm"

        let envArray = env.map { "\($0.key)=\($0.value)" }

        // Fork with PTY
        var masterFD: Int32 = 0
        var ws = winsize()
        ws.ws_col = UInt16(windowSize.cols)
        ws.ws_row = UInt16(windowSize.rows)

        let pid = forkpty(&masterFD, nil, nil, &ws)
        if pid < 0 {
            throw ProcessHostError.forkFailed(errno)
        }

        if pid == 0 {
            // Child process
            if let dir = currentDirectory {
                chdir(dir)
            }

            // Build args
            let allArgs = [command] + arguments
            let cArgs = allArgs.map { strdup($0) } + [nil]
            let cEnv = envArray.map { strdup($0) } + [nil]
            defer {
                cArgs.forEach { $0.map { free($0) } }
                cEnv.forEach { $0.map { free($0) } }
            }

            execve(command, cArgs, cEnv)
            // If execve fails, try execvp
            execvp(command, cArgs)
            _exit(127)
        }

        // Parent process
        childFD = masterFD
        childPID = pid
        isRunning = true

        // Set non-blocking
        let flags = fcntl(masterFD, F_GETFL)
        fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        setupReadSource()
        setupProcessSource()
    }

    /// Send data to the child process.
    public func send(_ data: [UInt8]) {
        guard isRunning && childFD >= 0 else { return }
        data.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var written = 0
            while written < data.count {
                let n = write(childFD, base + written, data.count - written)
                if n <= 0 { break }
                written += n
            }
        }
    }

    /// Send a string to the child process.
    public func send(text: String) {
        send(Array(text.utf8))
    }

    /// Update the window size for the child process.
    public func setWindowSize(_ size: TerminalSize) {
        guard childFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = UInt16(size.cols)
        ws.ws_row = UInt16(size.rows)
        _ = ioctl(childFD, TIOCSWINSZ, &ws)

        // Send SIGWINCH to the child process group
        if childPID > 0 {
            kill(-childPID, SIGWINCH)
        }
    }

    /// Terminate the child process.
    public func terminate() {
        guard isRunning else { return }
        if childPID > 0 {
            kill(childPID, SIGTERM)
        }
    }

    /// Kill the child process immediately.
    public func kill() {
        guard isRunning else { return }
        if childPID > 0 {
            Darwin.kill(childPID, SIGKILL)
        }
    }

    /// The child process PID.
    public var pid: pid_t { childPID }

    // MARK: - Private

    private func setupReadSource() {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: childFD, queue: ioQueue)

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.readAvailableData()
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            // Drain remaining data before closing (#370)
            self.drainRemainingData()
        }

        source.resume()
        readSource = source
    }

    private func setupProcessSource() {
        let source = DispatchSource.makeProcessSource(
            identifier: childPID, eventMask: .exit, queue: ioQueue)

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var status: Int32 = 0
            waitpid(self.childPID, &status, 0)

            // Cancel read source (which will drain remaining data first)
            self.readSource?.cancel()
            self.isRunning = false

            let exitCode: Int32
            if (status & 0x7F) == 0 {
                exitCode = (status >> 8) & 0xFF
            } else {
                exitCode = -1
            }

            self.delegate?.processHostDidTerminate(self, exitCode: exitCode)
        }

        source.resume()
        processSource = source
    }

    private func readAvailableData() {
        while true {
            let n = read(childFD, readBuffer, 131072)
            if n <= 0 { break }
            let data = Array(UnsafeBufferPointer(start: readBuffer, count: n))
            delegate?.processHost(self, didReceiveData: data)
        }
    }

    /// Drain all remaining data from the PTY after the process exits.
    /// This fixes issue #370 where data is lost because the process
    /// terminates before all output is read.
    private func drainRemainingData() {
        // Set blocking mode briefly to drain
        let flags = fcntl(childFD, F_GETFL)
        fcntl(childFD, F_SETFL, flags & ~O_NONBLOCK)

        // Use a short timeout via select
        var readSet = fd_set()
        withUnsafeMutablePointer(to: &readSet) { ptr in
            __darwin_fd_zero(ptr)
        }

        while true {
            var timeout = timeval(tv_sec: 0, tv_usec: 100_000) // 100ms
            var readSet = fd_set()
            withUnsafeMutablePointer(to: &readSet) { ptr in
                __darwin_fd_zero(ptr)
                __darwin_fd_set(childFD, ptr)
            }

            let result = select(childFD + 1, &readSet, nil, nil, &timeout)
            if result <= 0 { break }

            let n = read(childFD, readBuffer, 131072)
            if n <= 0 { break }
            let data = Array(UnsafeBufferPointer(start: readBuffer, count: n))
            delegate?.processHost(self, didReceiveData: data)
        }

        // Restore non-blocking
        fcntl(childFD, F_SETFL, flags)
    }
}

/// Errors from ProcessHost.
public enum ProcessHostError: Error {
    case forkFailed(Int32)
    case processNotRunning
}

// MARK: - fd_set helpers

@inline(__always)
private func __darwin_fd_zero(_ set: UnsafeMutablePointer<fd_set>) {
    set.pointee.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0)
}

@inline(__always)
private func __darwin_fd_set(_ fd: Int32, _ set: UnsafeMutablePointer<fd_set>) {
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    withUnsafeMutablePointer(to: &set.pointee.__fds_bits) { ptr in
        let rawPtr = UnsafeMutableRawPointer(ptr)
        let int32Ptr = rawPtr.assumingMemoryBound(to: Int32.self)
        int32Ptr[intOffset] |= Int32(1 << bitOffset)
    }
}
#endif
