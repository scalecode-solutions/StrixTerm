#if canImport(AppKit) && canImport(SwiftUI)
import SwiftUI
import FredTermCore
import FredTermUI
import FredTermProcess
import FredTermConfig

@main
struct FredTermApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 500)
    }
}

struct ContentView: View {
    @StateObject private var session = TerminalSession()

    var body: some View {
        TerminalView(
            terminal: session.terminal,
            configuration: TerminalViewConfiguration(
                fontFamily: "Menlo",
                fontSize: 14
            ),
            onSendData: { data in
                session.process.send(data)
            },
            onSizeChanged: { size in
                session.terminal.resize(cols: size.cols, rows: size.rows)
                session.process.setWindowSize(size)
            },
            onTitleChanged: { title in
                // Window title updates handled by SwiftUI
            }
        )
        .background(Color.black)
        .onAppear {
            session.start()
        }
    }
}

/// Manages the terminal + child process lifecycle.
@MainActor
final class TerminalSession: ObservableObject {
    let terminal: Terminal
    let process: ProcessHost

    init() {
        terminal = Terminal(cols: 80, rows: 25, maxScrollback: 10_000)
        process = ProcessHost()
    }

    func start() {
        // Wire process output to terminal
        process.delegate = self

        // Wire terminal responses back to process
        terminal.delegate = self

        // Find the user's shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        do {
            try process.start(
                command: shell,
                arguments: ["--login"],
                environment: [
                    "TERM": "xterm-256color",
                    "COLORTERM": "truecolor",
                    "TERM_PROGRAM": "FredTerm",
                    "LANG": "en_US.UTF-8",
                ],
                currentDirectory: NSHomeDirectory(),
                windowSize: terminal.size
            )
        } catch {
            terminal.feed(text: "\r\nFailed to start shell: \(error)\r\n")
        }
    }
}

// MARK: - ProcessHostDelegate

extension TerminalSession: ProcessHostDelegate {
    nonisolated func processHost(_ host: ProcessHost, didReceiveData data: [UInt8]) {
        DispatchQueue.main.async { [weak self] in
            self?.terminal.feed(data)
        }
    }

    nonisolated func processHostDidTerminate(_ host: ProcessHost, exitCode: Int32) {
        DispatchQueue.main.async { [weak self] in
            self?.terminal.feed(text: "\r\n[Process exited with code \(exitCode)]\r\n")
        }
    }
}

// MARK: - TerminalDelegate

extension TerminalSession: TerminalDelegate {
    nonisolated func terminal(_ terminal: Terminal, produced actions: [TerminalAction]) {
        // Actions like title changes, bell, etc. handled here
    }

    nonisolated func terminal(_ terminal: Terminal, sendData data: [UInt8]) {
        // Terminal responses (e.g., DA, DSR) sent back to process
        DispatchQueue.main.async { [weak self] in
            self?.process.send(data)
        }
    }

    nonisolated func terminalNeedsDisplay(_ terminal: Terminal) {
        // Display updates handled by MTKView's draw loop
    }
}
#endif
