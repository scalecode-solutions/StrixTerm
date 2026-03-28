#if canImport(SwiftUI) && canImport(MetalKit)
import SwiftUI
import StrixTermCore
import StrixTermConfig

/// Configuration for the TerminalView presentation.
public struct TerminalThemeColor: Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct TerminalTheme: Sendable {
    public var foreground: TerminalThemeColor
    public var background: TerminalThemeColor
    public var cursor: TerminalThemeColor
    public var selection: TerminalThemeColor
    public var link: TerminalThemeColor

    public init(
        foreground: TerminalThemeColor,
        background: TerminalThemeColor,
        cursor: TerminalThemeColor,
        selection: TerminalThemeColor,
        link: TerminalThemeColor
    ) {
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.link = link
    }

    public static let fred = TerminalTheme(
        foreground: TerminalThemeColor(red: 0.84, green: 0.87, blue: 0.92),
        background: TerminalThemeColor(red: 0.09, green: 0.10, blue: 0.13),
        cursor: TerminalThemeColor(red: 0.29, green: 0.48, blue: 0.69),
        selection: TerminalThemeColor(red: 0.12, green: 0.35, blue: 0.56, alpha: 0.34),
        link: TerminalThemeColor(red: 0.42, green: 0.59, blue: 0.82)
    )
}

public struct TerminalViewConfiguration: Sendable {
    public var fontFamily: String
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var letterSpacing: CGFloat
    public var opacity: CGFloat
    public var blinkEnabled: Bool
    public var blinkInterval: TimeInterval
    public var linkHighlightMode: LinkHighlightMode
    public var palette: BuiltinPalette
    public var theme: TerminalTheme

    public init(
        fontFamily: String = "SF Mono",
        fontSize: CGFloat = 13,
        lineSpacing: CGFloat = 1.0,
        letterSpacing: CGFloat = 0,
        opacity: CGFloat = 1.0,
        blinkEnabled: Bool = true,
        blinkInterval: TimeInterval = 0.5,
        linkHighlightMode: LinkHighlightMode = .hoverWithModifier,
        palette: BuiltinPalette = .fredDark,
        theme: TerminalTheme = .fred
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.opacity = opacity
        self.blinkEnabled = blinkEnabled
        self.blinkInterval = blinkInterval
        self.linkHighlightMode = linkHighlightMode
        self.palette = palette
        self.theme = theme
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
    /// Optional callback invoked when the user opens a hyperlink (Command-click or tap).
    public var onOpenURL: ((String) -> Void)?
    /// Optional callback invoked when the terminal bell rings.
    public var onBell: (() -> Void)?
    /// Binding to toggle the find bar visibility from the backing view.
    @Binding var showFindBar: Bool

    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        showFindBar: Binding<Bool> = .constant(false),
        onSendData: (([UInt8]) -> Void)? = nil,
        onSizeChanged: ((TerminalSize) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil,
        onOpenURL: ((String) -> Void)? = nil,
        onBell: (() -> Void)? = nil
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self._showFindBar = showFindBar
        self.onSendData = onSendData
        self.onSizeChanged = onSizeChanged
        self.onTitleChanged = onTitleChanged
        self.onOpenURL = onOpenURL
        self.onBell = onBell
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
        view.onBell = { [weak view] in
            context.coordinator.parent.onBell?()
            view?.visualBell()
        }
        return view
    }

    public func updateNSView(_ nsView: MacTerminalBackingView, context: Context) {
        context.coordinator.parent = self
        nsView.configuration = configuration
        nsView.onPerformFindPanelAction = {
            context.coordinator.toggleFindBar()
        }
        nsView.onBell = { [weak nsView] in
            context.coordinator.parent.onBell?()
            nsView?.visualBell()
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

        public func terminalView(_ view: MacTerminalBackingView, openURL url: String) {
            if let callback = parent.onOpenURL {
                callback(url)
            } else {
                // Default: open URL with the system handler
                if let nsURL = URL(string: url) {
                    NSWorkspace.shared.open(nsURL)
                }
            }
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
    public var onOpenURL: ((String) -> Void)?
    public var onHighlight: ((SearchResult?) -> Void)?

    @State private var showFindBar: Bool = false

    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        onSendData: (([UInt8]) -> Void)? = nil,
        onSizeChanged: ((TerminalSize) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil,
        onOpenURL: ((String) -> Void)? = nil,
        onHighlight: ((SearchResult?) -> Void)? = nil
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self.onSendData = onSendData
        self.onSizeChanged = onSizeChanged
        self.onTitleChanged = onTitleChanged
        self.onOpenURL = onOpenURL
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
                onTitleChanged: onTitleChanged,
                onOpenURL: onOpenURL
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
    /// Optional callback invoked when the user taps a hyperlink.
    public var onOpenURL: ((String) -> Void)?
    /// Optional callback invoked when the terminal bell rings.
    public var onBell: (() -> Void)?

    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        onSendData: (([UInt8]) -> Void)? = nil,
        onSizeChanged: ((TerminalSize) -> Void)? = nil,
        onTitleChanged: ((String) -> Void)? = nil,
        onOpenURL: ((String) -> Void)? = nil,
        onBell: (() -> Void)? = nil
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self.onSendData = onSendData
        self.onSizeChanged = onSizeChanged
        self.onTitleChanged = onTitleChanged
        self.onOpenURL = onOpenURL
        self.onBell = onBell
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
        view.onBell = { [weak view] in
            context.coordinator.parent.onBell?()
            view?.visualBell()
        }
        return view
    }

    public func updateUIView(_ uiView: IOSTerminalBackingView, context: Context) {
        context.coordinator.parent = self
        uiView.configuration = configuration
        uiView.onBell = { [weak uiView] in
            context.coordinator.parent.onBell?()
            uiView?.visualBell()
        }
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

        public func terminalView(_ view: IOSTerminalBackingView, openURL url: String) {
            if let callback = parent.onOpenURL {
                callback(url)
            } else {
                // Default: open URL with the system handler
                if let nsURL = URL(string: url) {
                    UIApplication.shared.open(nsURL)
                }
            }
        }
    }
}
#endif

#endif
