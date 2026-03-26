#if canImport(SwiftUI) && canImport(MetalKit)
import SwiftUI
import FredTermCore
import FredTermConfig

/// Configuration for the TerminalView presentation.
public struct TerminalViewConfiguration: Sendable {
    public var fontFamily: String
    public var fontSize: CGFloat
    public var blinkEnabled: Bool
    public var blinkInterval: TimeInterval
    public var linkHighlightMode: LinkHighlightMode

    public init(
        fontFamily: String = "SF Mono",
        fontSize: CGFloat = 13,
        blinkEnabled: Bool = true,
        blinkInterval: TimeInterval = 0.5,
        linkHighlightMode: LinkHighlightMode = .hoverWithModifier
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.blinkEnabled = blinkEnabled
        self.blinkInterval = blinkInterval
        self.linkHighlightMode = linkHighlightMode
    }

    public static let `default` = TerminalViewConfiguration()
}

/// How hyperlinks are highlighted in the terminal.
public enum LinkHighlightMode: Sendable {
    case always
    case hover
    case hoverWithModifier
    case never
}

#if os(macOS)
/// The primary SwiftUI terminal view for macOS.
///
/// Wraps a `MacTerminalBackingView` (the AppKit NSView hosting the Metal
/// renderer and keyboard input) for use in SwiftUI view hierarchies.
public struct TerminalView: NSViewRepresentable {
    public let terminal: Terminal
    public var configuration: TerminalViewConfiguration
    /// Optional callback invoked when the terminal needs to send data to the host.
    public var onSendData: (([UInt8]) -> Void)?
    /// Optional callback invoked when the terminal size changes.
    public var onSizeChanged: ((TerminalSize) -> Void)?
    /// Optional callback invoked when the terminal title changes.
    public var onTitleChanged: ((String) -> Void)?

    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        onSendData: (([UInt8]) -> Void)? = nil,
        onSizeChanged: ((TerminalSize) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self.onSendData = onSendData
        self.onSizeChanged = onSizeChanged
        self.onTitleChanged = onTitleChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> MacTerminalBackingView {
        let view = MacTerminalBackingView(
            terminal: terminal,
            configuration: configuration
        )
        view.delegate = context.coordinator
        context.coordinator.parent = self
        return view
    }

    public func updateNSView(_ nsView: MacTerminalBackingView, context: Context) {
        context.coordinator.parent = self
        nsView.configuration = configuration
    }

    // MARK: - Coordinator

    /// Coordinator that bridges MacTerminalViewDelegate callbacks to SwiftUI closures.
    @MainActor
    public class Coordinator: MacTerminalViewDelegate {
        var parent: TerminalView

        init(_ parent: TerminalView) {
            self.parent = parent
        }

        public func terminalView(_ view: MacTerminalBackingView, sendData data: [UInt8]) {
            parent.onSendData?(data)
        }

        public func terminalView(_ view: MacTerminalBackingView, sizeChanged newSize: TerminalSize) {
            parent.onSizeChanged?(newSize)
        }

        public func terminalViewTitleChanged(_ view: MacTerminalBackingView, title: String) {
            parent.onTitleChanged?(title)
        }
    }
}
#elseif os(iOS) || os(visionOS)
/// The primary SwiftUI terminal view for iOS/visionOS.
public struct TerminalView: UIViewRepresentable {
    public let terminal: Terminal
    public var configuration: TerminalViewConfiguration

    public init(terminal: Terminal, configuration: TerminalViewConfiguration = .default) {
        self.terminal = terminal
        self.configuration = configuration
    }

    public func makeUIView(context: Context) -> UIView {
        // Placeholder - full Metal-backed view implementation in Phase 6
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        // Update view when configuration changes
    }
}
#endif

#endif
