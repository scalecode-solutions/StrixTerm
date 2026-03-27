/// Character style flags.
public struct CharacterStyle: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let bold          = CharacterStyle(rawValue: 1 << 0)
    public static let dim           = CharacterStyle(rawValue: 1 << 1)
    public static let italic        = CharacterStyle(rawValue: 1 << 2)
    public static let underline     = CharacterStyle(rawValue: 1 << 3)
    public static let blink         = CharacterStyle(rawValue: 1 << 4)
    public static let inverse       = CharacterStyle(rawValue: 1 << 5)
    public static let invisible     = CharacterStyle(rawValue: 1 << 6)
    public static let strikethrough = CharacterStyle(rawValue: 1 << 7)
    public static let overline      = CharacterStyle(rawValue: 1 << 8)
}

/// Underline visual style.
public enum UnderlineStyle: UInt8, Hashable, Sendable {
    case none = 0
    case single = 1
    case double = 2
    case curly = 3
    case dotted = 4
    case dashed = 5
}

/// A complete attribute entry describing a cell's appearance.
/// Deduplicated: most terminals use < 100 unique combinations.
public struct AttributeEntry: Hashable, Sendable {
    public var fg: TerminalColor
    public var bg: TerminalColor
    public var style: CharacterStyle
    public var underlineStyle: UnderlineStyle
    public var underlineColor: TerminalColor?

    public init(
        fg: TerminalColor = .default,
        bg: TerminalColor = .default,
        style: CharacterStyle = [],
        underlineStyle: UnderlineStyle = .none,
        underlineColor: TerminalColor? = nil
    ) {
        self.fg = fg
        self.bg = bg
        self.style = style
        self.underlineStyle = underlineStyle
        self.underlineColor = underlineColor
    }

    /// The default attribute (default fg/bg, no styling).
    public static let `default` = AttributeEntry()
}

/// Deduplicated attribute storage.
///
/// Cells store a `UInt32` index into this table rather than a full attribute
/// inline. This saves memory (4 bytes vs ~20+ bytes per cell) and allows
/// efficient attribute comparison by comparing indices.
public struct AttributeTable: Sendable {
    private var entries: [AttributeEntry]
    private var lookup: [AttributeEntry: UInt32]

    public init() {
        entries = [.default]
        lookup = [.default: 0]
    }

    /// Get or insert an attribute, returning its index.
    /// Thread safety: caller must ensure exclusive access.
    @inline(__always)
    public mutating func intern(_ entry: AttributeEntry) -> UInt32 {
        if let existing = lookup[entry] {
            return existing
        }
        let idx = UInt32(entries.count)
        entries.append(entry)
        lookup[entry] = idx
        return idx
    }

    /// Look up an attribute by index.
    @inline(__always)
    public subscript(index: UInt32) -> AttributeEntry {
        entries[Int(index)]
    }

    /// The number of unique attributes stored.
    public var count: Int { entries.count }
}
