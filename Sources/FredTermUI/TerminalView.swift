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
    /// Binding to toggle the find bar visibility from the backing view.
    @Binding var showFindBar: Bool

    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        showFindBar: Binding<Bool> = .constant(false),
        onSendData: (([UInt8]) -> Void)? = nil,
        onSizeChanged: ((TerminalSize) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self._showFindBar = showFindBar
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
        view.onPerformFindPanelAction = {
            context.coordinator.toggleFindBar()
        }
        return view
    }

    public func updateNSView(_ nsView: MacTerminalBackingView, context: Context) {
        context.coordinator.parent = self
        nsView.configuration = configuration
        nsView.onPerformFindPanelAction = {
            context.coordinator.toggleFindBar()
        }
    }

    // MARK: - Coordinator

    /// Coordinator that bridges MacTerminalViewDelegate callbacks to SwiftUI closures.
    @MainActor
    public class Coordinator: MacTerminalViewDelegate {
        var parent: TerminalView

        init(_ parent: TerminalView) {
            self.parent = parent
        }

        func toggleFindBar() {
            parent.showFindBar.toggle()
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

/// A SwiftUI view that wraps `TerminalView` with an integrated find bar overlay.
///
/// Use this view when you want built-in Cmd+F search support. The find bar
/// appears as a floating overlay at the top of the terminal, similar to
/// browser find bars.
///
/// Usage:
/// ```swift
/// TerminalSearchableView(terminal: myTerminal)
/// ```
public struct TerminalSearchableView: View {
    public let terminal: Terminal
    public var configuration: TerminalViewConfiguration
    public var onSendData: (([UInt8]) -> Void)?
    public var onSizeChanged: ((TerminalSize) -> Void)?
    public var onTitleChanged: ((String) -> Void)?
    public var onHighlight: ((SearchResult?) -> Void)?

    @State private var showFindBar: Bool = false

    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        onSendData: (([UInt8]) -> Void)? = nil,
        onSizeChanged: ((TerminalSize) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil,
        onHighlight: ((SearchResult?) -> Void)? = nil
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self.onSendData = onSendData
        self.onSizeChanged = onSizeChanged
        self.onTitleChanged = onTitleChanged
        self.onHighlight = onHighlight
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TerminalView(
                terminal: terminal,
                configuration: configuration,
                showFindBar: $showFindBar,
                onSendData: onSendData,
                onSizeChanged: onSizeChanged,
                onTitleChanged: onTitleChanged
            )

            if showFindBar {
                FindBarView(
                    isVisible: $showFindBar,
                    terminal: terminal,
                    onHighlight: onHighlight
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showFindBar)
    }
}
#elseif os(iOS) || os(visionOS)
/// The primary SwiftUI terminal view for iOS/visionOS.
///
/// Wraps an `IOSTerminalBackingView` (the UIKit UIView hosting the Metal
/// renderer and keyboard/touch input) for use in SwiftUI view hierarchies.
public struct TerminalView: UIViewRepresentable {
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

    public func makeUIView(context: Context) -> IOSTerminalBackingView {
        let view = IOSTerminalBackingView(
            terminal: terminal,
            configuration: configuration
        )
        view.delegate = context.coordinator
        context.coordinator.parent = self
        return view
    }

    public func updateUIView(_ uiView: IOSTerminalBackingView, context: Context) {
        context.coordinator.parent = self
        uiView.configuration = configuration
    }

    // MARK: - Coordinator

    /// Coordinator that bridges IOSTerminalViewDelegate callbacks to SwiftUI closures.
    @MainActor
    public class Coordinator: IOSTerminalViewDelegate {
        var parent: TerminalView

        init(_ parent: TerminalView) {
            self.parent = parent
        }

        public func terminalView(_ view: IOSTerminalBackingView, sendData data: [UInt8]) {
            parent.onSendData?(data)
        }

        public func terminalView(_ view: IOSTerminalBackingView, sizeChanged newSize: TerminalSize) {
            parent.onSizeChanged?(newSize)
        }

        public func terminalViewTitleChanged(_ view: IOSTerminalBackingView, title: String) {
            parent.onTitleChanged?(title)
        }
    }
}
#endif

#endif
