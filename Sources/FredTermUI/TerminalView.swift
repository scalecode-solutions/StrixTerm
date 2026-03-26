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
public struct TerminalView: NSViewRepresentable {
    public let terminal: Terminal
    public var configuration: TerminalViewConfiguration

    public init(terminal: Terminal, configuration: TerminalViewConfiguration = .default) {
        self.terminal = terminal
        self.configuration = configuration
    }

    public func makeNSView(context: Context) -> NSView {
        // Placeholder - full Metal-backed view implementation in Phase 6
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // Update view when configuration changes
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
