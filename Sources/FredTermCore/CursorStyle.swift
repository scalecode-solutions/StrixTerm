/// The visual style of the terminal cursor.
public enum CursorStyle: UInt8, Sendable {
    case blinkBlock = 0
    case steadyBlock = 2
    case blinkUnderline = 3
    case steadyUnderline = 4
    case blinkBar = 5
    case steadyBar = 6

    /// Whether this style should blink.
    public var blinks: Bool {
        switch self {
        case .blinkBlock, .blinkUnderline, .blinkBar: return true
        case .steadyBlock, .steadyUnderline, .steadyBar: return false
        }
    }

    /// The shape independent of blink state.
    public var shape: CursorShape {
        switch self {
        case .blinkBlock, .steadyBlock: return .block
        case .blinkUnderline, .steadyUnderline: return .underline
        case .blinkBar, .steadyBar: return .bar
        }
    }
}

/// Cursor shape without blink information.
public enum CursorShape: Sendable {
    case block
    case underline
    case bar
}
