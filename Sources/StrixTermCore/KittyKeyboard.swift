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

    /// Mask of all known flag bits.
    public static let knownMask = KittyKeyboardFlags(rawValue: 0x1F)
}

/// Stack of keyboard enhancement flag sets.
/// The Kitty protocol uses a push/pop model.
///
/// Mirrors the SwiftTerm model: `flags` holds the current flags, and `stack`
/// is a LIFO of saved flag sets. `push` saves current to stack and sets new;
/// `pop` restores from stack.
public struct KeyboardState: Sendable {
    /// The currently active flags.
    public var flags: KittyKeyboardFlags = []
    /// Saved flag sets (push/pop stack).
    private var stack: [KittyKeyboardFlags] = []
    public var modifyOtherKeys: Int = 0  // XTMODKEYS level

    /// Stack depth limit to prevent unbounded growth.
    public static let stackLimit = 16

    public init() {}

    /// The currently active flags.
    public var currentFlags: KittyKeyboardFlags {
        flags
    }

    /// Whether any keyboard enhancement is active.
    public var isActive: Bool {
        !flags.isEmpty
    }

    /// Push current flags onto stack and set new flags.
    /// CSI > flags u
    public mutating func push(_ newFlags: KittyKeyboardFlags) {
        if stack.count >= Self.stackLimit {
            stack.removeFirst()
        }
        stack.append(flags)
        flags = newFlags
    }

    /// Pop `count` entries from the stack, restoring the last-popped value as current.
    /// CSI < count u
    public mutating func pop(_ count: Int = 1) {
        let n = max(count, 1)
        if n > stack.count {
            stack.removeAll()
            flags = []
            return
        }
        for _ in 0..<n {
            flags = stack.removeLast()
        }
    }

    /// Set the current flags directly (CSI = flags ; mode u).
    /// mode 1 = set, mode 2 = union, mode 3 = subtract.
    public mutating func setFlags(_ newFlags: KittyKeyboardFlags, mode: Int) {
        switch mode {
        case 1:
            flags = newFlags
        case 2:
            flags.formUnion(newFlags)
        case 3:
            flags.subtract(newFlags)
        default:
            break
        }
    }

    /// Set the flags at the current level (replace).
    public mutating func setCurrentFlags(_ newFlags: KittyKeyboardFlags) {
        flags = newFlags
    }

    /// Query the current keyboard mode for reporting.
    public var queryResponse: [UInt8] {
        let value = flags.rawValue
        return Array("?\(value)u".utf8)
    }

    /// Reset all keyboard state (e.g., on RMCUP/alternate screen exit).
    public mutating func reset() {
        flags = []
        stack.removeAll()
        modifyOtherKeys = 0
    }

    /// The depth of the flag stack.
    public var depth: Int { stack.count }
}
