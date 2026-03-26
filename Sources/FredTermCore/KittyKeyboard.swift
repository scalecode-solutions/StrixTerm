/// Kitty keyboard protocol enhancement flags.
/// See: https://sw.kovidgoyal.net/kitty/keyboard-protocol/
public struct KittyKeyboardFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Report disambiguated key events.
    public static let disambiguateEscapeCodes = KittyKeyboardFlags(rawValue: 1 << 0)
    /// Report event types (press, repeat, release).
    public static let reportEventTypes = KittyKeyboardFlags(rawValue: 1 << 1)
    /// Report alternate keys (e.g., shifted key).
    public static let reportAlternateKeys = KittyKeyboardFlags(rawValue: 1 << 2)
    /// Report all keys as escape codes (including plain text).
    public static let reportAllKeysAsEscapeCodes = KittyKeyboardFlags(rawValue: 1 << 3)
    /// Report the text associated with the key event.
    public static let reportAssociatedText = KittyKeyboardFlags(rawValue: 1 << 4)
}

/// Stack of keyboard enhancement flag sets.
/// The Kitty protocol uses a push/pop model.
public struct KeyboardState: Sendable {
    private var stack: [KittyKeyboardFlags]
    public var modifyOtherKeys: Int = 0  // XTMODKEYS level

    public init() {
        stack = []
    }

    /// The currently active flags (top of stack, or empty).
    public var currentFlags: KittyKeyboardFlags {
        stack.last ?? []
    }

    /// Whether any keyboard enhancement is active.
    public var isActive: Bool {
        !stack.isEmpty && !currentFlags.isEmpty
    }

    /// Push a new set of flags onto the stack.
    public mutating func push(_ flags: KittyKeyboardFlags) {
        stack.append(flags)
    }

    /// Pop the top flags from the stack.
    @discardableResult
    public mutating func pop(_ count: Int = 1) -> KittyKeyboardFlags? {
        guard !stack.isEmpty else { return nil }
        let n = min(count, stack.count)
        let result = stack.last
        stack.removeLast(n)
        return result
    }

    /// Set the flags at the current level (replace top).
    public mutating func setCurrentFlags(_ flags: KittyKeyboardFlags) {
        if stack.isEmpty {
            stack.append(flags)
        } else {
            stack[stack.count - 1] = flags
        }
    }

    /// Query the current keyboard mode for reporting.
    public var queryResponse: [UInt8] {
        let value = currentFlags.rawValue
        return Array("?\(value)u".utf8)
    }

    /// Reset all keyboard state (e.g., on RMCUP/alternate screen exit).
    public mutating func reset() {
        stack.removeAll()
        modifyOtherKeys = 0
    }

    /// The depth of the flag stack.
    public var depth: Int { stack.count }
}
