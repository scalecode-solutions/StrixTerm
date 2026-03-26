import FredTermCore

/// Configuration for a terminal instance.
/// Codable for persistence in user preferences.
public struct TerminalConfiguration: Codable, Sendable {
    public var cols: Int
    public var rows: Int
    public var scrollbackLines: Int
    public var termName: String
    public var cursorStyle: String  // Stored as string for Codable
    public var tabStopWidth: Int
    public var convertEol: Bool
    public var sixelEnabled: Bool
    public var kittyImageCacheLimit: Int

    public init(
        cols: Int = 80,
        rows: Int = 25,
        scrollbackLines: Int = 10_000,
        termName: String = "xterm-256color",
        cursorStyle: String = "blinkBlock",
        tabStopWidth: Int = 8,
        convertEol: Bool = false,
        sixelEnabled: Bool = true,
        kittyImageCacheLimit: Int = 320 * 1024 * 1024
    ) {
        self.cols = cols
        self.rows = rows
        self.scrollbackLines = scrollbackLines
        self.termName = termName
        self.cursorStyle = cursorStyle
        self.tabStopWidth = tabStopWidth
        self.convertEol = convertEol
        self.sixelEnabled = sixelEnabled
        self.kittyImageCacheLimit = kittyImageCacheLimit
    }

    public static let `default` = TerminalConfiguration()

    /// Create a Terminal from this configuration.
    public func makeTerminal() -> Terminal {
        Terminal(cols: cols, rows: rows, maxScrollback: scrollbackLines)
    }
}
