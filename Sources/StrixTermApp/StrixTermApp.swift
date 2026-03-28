#if canImport(AppKit) && canImport(SwiftUI)
import SwiftUI
import StrixTermCore
import StrixTermUI
import StrixTermProcess
import StrixTermConfig

@main
struct StrixTermApp: App {
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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.13, blue: 0.16),
                    Color(red: 0.09, green: 0.10, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 28, height: 28)
                            Image(systemName: "terminal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.78))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.windowTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.9))
                                .lineLimit(1)
                            Text(session.currentDirectory)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.5))
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            HeaderBadge(label: session.shellName, tint: Color.white.opacity(0.62))
                            HeaderBadge(label: "fred-dark", tint: Color(red: 0.42, green: 0.59, blue: 0.82))
                            HeaderBadge(label: "\(session.terminalSize.cols)x\(session.terminalSize.rows)", tint: Color.white.opacity(0.58))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Divider()
                        .overlay(Color.white.opacity(0.06))
                }
                .background(Color.white.opacity(0.03))

                TerminalView(
                    terminal: session.terminal,
                    configuration: TerminalViewConfiguration(
                        fontFamily: "Menlo",
                        fontSize: 13,
                        lineSpacing: 1.08,
                        letterSpacing: 0.25,
                        opacity: 0.98,
                        palette: .fredDark,
                        theme: .fred
                    ),
                    onSendData: { data in
                        session.process.send(data)
                    },
                    onSizeChanged: { size in
                        session.terminalSize = size
                        session.terminal.resize(cols: size.cols, rows: size.rows)
                        session.process.setWindowSize(size)
                    },
                    onTitleChanged: { title in
                        session.windowTitle = title.isEmpty ? "Shell" : title
                    },
                    onOpenURL: { urlString in
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 24, y: 14)
            .padding(18)
        }
        .onAppear {
            session.start()
        }
    }
}

private struct HeaderBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

/// Manages the terminal + child process lifecycle.
@MainActor
final class TerminalSession: ObservableObject {
    @Published var windowTitle = "Shell"
    @Published var currentDirectory = NSHomeDirectory()
    @Published var shellName = "zsh"
    @Published var terminalSize = TerminalSize(cols: 80, rows: 25)

    let terminal: Terminal
    let process: ProcessHost

    init() {
        terminal = Terminal(cols: 80, rows: 25, maxScrollback: 10_000)
        process = ProcessHost()
        terminalSize = terminal.size
    }

    func start() {
        // Wire process output to terminal
        process.delegate = self

        // Wire terminal responses back to process
        terminal.delegate = self

        // Find the user's shell
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        shellName = URL(fileURLWithPath: shell).lastPathComponent

        do {
            try process.start(
                command: shell,
                arguments: ["--login"],
                environment: [
                    "TERM": "xterm-256color",
                    "COLORTERM": "truecolor",
                    "TERM_PROGRAM": "StrixTerm",
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
        for action in actions {
            switch action {
            case .bell:
                DispatchQueue.main.async {
                    NSSound.beep()
                }
            case .clipboardCopy(let str):
                DispatchQueue.main.async {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(str, forType: .string)
                }
            case .setTitle(let title):
                DispatchQueue.main.async { [weak self] in
                    self?.windowTitle = title.isEmpty ? "Shell" : title
                }
            default:
                break
            }
        }
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
