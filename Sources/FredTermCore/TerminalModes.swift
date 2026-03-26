/// Mouse tracking mode.
public enum MouseMode: UInt16, Sendable {
    case off = 0
    case x10 = 9
    case vt200 = 1000
    case buttonEvent = 1002
    case anyEvent = 1003
}

/// Mouse encoding format.
public enum MouseEncoding: UInt16, Sendable {
    case x10 = 0
    case utf8 = 1005
    case sgr = 1006
    case urxvt = 1015
    case sgrPixels = 1016
}

/// All terminal mode flags, packed into a single struct.
/// Replaces scattered booleans across the original Terminal class.
public struct TerminalModes: Sendable {
    // DEC Private Modes
    public var applicationCursor: Bool = false       // DECCKM
    public var column132: Bool = false                // DECCOLM
    public var reverseVideo: Bool = false             // DECSCNM
    public var originMode: Bool = false               // DECOM
    public var wraparound: Bool = true                // DECAWM
    public var reverseWraparound: Bool = false        // xterm reverse wraparound
    public var autoRepeat: Bool = true                // DECARM

    // Scrolling
    public var smoothScroll: Bool = false             // DECSCLM

    // Cursor
    public var cursorVisible: Bool = true             // DECTCEM
    public var blinkCursor: Bool = true

    // Mouse
    public var mouseMode: MouseMode = .off
    public var mouseEncoding: MouseEncoding = .x10

    // Keyboard
    public var applicationKeypad: Bool = false        // DECKPAM/DECKPNM
    public var bracketedPaste: Bool = false
    public var sendFocus: Bool = false                // Focus in/out events

    // Line modes
    public var insertMode: Bool = false               // IRM
    public var autoNewline: Bool = false               // LNM (line feed/new line mode)

    // Margin mode (DECLRMM)
    public var marginMode: Bool = false

    // Alternate screen
    public var alternateScreen: Bool = false

    // Synchronized output (DEC mode 2026)
    public var synchronizedOutput: Bool = false
}
