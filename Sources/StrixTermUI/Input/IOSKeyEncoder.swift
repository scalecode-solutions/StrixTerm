#if canImport(UIKit) && canImport(MetalKit)
import UIKit
import StrixTermCore

/// Encodes UIPress/UIKey keyboard events into terminal escape sequences on iOS/visionOS.
///
/// This handles the translation from hardware keyboard events (UIKey) to the byte
/// sequences expected by terminal applications, including special keys, modifier
/// combinations, and application cursor/keypad modes.
public struct IOSKeyEncoder: Sendable {

    public init() {}

    // MARK: - Public API

    /// Encode a UIPress key event into terminal escape sequence bytes.
    ///
    /// Returns `nil` if the press does not map to a terminal sequence (e.g.,
    /// modifier-only key presses or keys without a UIKey).
    @MainActor
    public func encodePress(
        _ press: UIPress,
        applicationCursor: Bool,
        applicationKeypad: Bool,
        kittyFlags: KittyKeyboardFlags
    ) -> [UInt8]? {
        guard let key = press.key else { return nil }

        let modifiers = key.modifierFlags

        // Check for special keys first (arrows, function keys, etc.)
        if let specialBytes = encodeSpecialKey(
            key: key,
            modifiers: modifiers,
            applicationCursor: applicationCursor,
            applicationKeypad: applicationKeypad
        ) {
            return specialBytes
        }

        // Handle character-producing keys
        let characters = key.charactersIgnoringModifiers
        guard !characters.isEmpty else { return nil }

        let hasControl = modifiers.contains(.control)
        let hasOption = modifiers.contains(.alternate)

        // Ctrl+letter combinations
        if hasControl {
            if let ctrlBytes = encodeControlKey(characters: characters) {
                if hasOption {
                    // ESC prefix for Alt/Option + Ctrl combos
                    return [0x1B] + ctrlBytes
                }
                return ctrlBytes
            }
        }

        // Option/Alt as meta prefix (ESC + character)
        if hasOption {
            let bytes = Array(characters.utf8)
            if !bytes.isEmpty {
                return [0x1B] + bytes
            }
        }

        return nil
    }

    // MARK: - Special Keys

    /// Encode special (non-character) keys like arrows, function keys, etc.
    @MainActor
    private func encodeSpecialKey(
        key: UIKey,
        modifiers: UIKeyModifierFlags,
        applicationCursor: Bool,
        applicationKeypad: Bool
    ) -> [UInt8]? {
        let modParam = modifierParameter(modifiers)
        let hid = key.keyCode

        switch hid {
        // Arrow keys
        case .keyboardUpArrow:
            return cursorKeySequence("A", modifiers: modParam, applicationMode: applicationCursor)
        case .keyboardDownArrow:
            return cursorKeySequence("B", modifiers: modParam, applicationMode: applicationCursor)
        case .keyboardRightArrow:
            return cursorKeySequence("C", modifiers: modParam, applicationMode: applicationCursor)
        case .keyboardLeftArrow:
            return cursorKeySequence("D", modifiers: modParam, applicationMode: applicationCursor)

        // Home / End
        case .keyboardHome:
            if modParam > 0 {
                return csiSequence(1, "~", modifiers: modParam)
            }
            return applicationCursor ? esc("OH") : esc("[H")
        case .keyboardEnd:
            if modParam > 0 {
                return csiSequence(4, "~", modifiers: modParam)
            }
            return applicationCursor ? esc("OF") : esc("[F")

        // Page Up / Page Down
        case .keyboardPageUp:
            return csiSequence(5, "~", modifiers: modParam)
        case .keyboardPageDown:
            return csiSequence(6, "~", modifiers: modParam)

        // Insert / Delete (Forward Delete)
        case .keyboardInsert:
            return csiSequence(2, "~", modifiers: modParam)
        case .keyboardDeleteForward:
            return csiSequence(3, "~", modifiers: modParam)

        // Function keys F1-F12
        case .keyboardF1:  return functionKeySequence(11, modifiers: modParam)
        case .keyboardF2:  return functionKeySequence(12, modifiers: modParam)
        case .keyboardF3:  return functionKeySequence(13, modifiers: modParam)
        case .keyboardF4:  return functionKeySequence(14, modifiers: modParam)
        case .keyboardF5:  return functionKeySequence(15, modifiers: modParam)
        case .keyboardF6:  return functionKeySequence(17, modifiers: modParam)
        case .keyboardF7:  return functionKeySequence(18, modifiers: modParam)
        case .keyboardF8:  return functionKeySequence(19, modifiers: modParam)
        case .keyboardF9:  return functionKeySequence(20, modifiers: modParam)
        case .keyboardF10: return functionKeySequence(21, modifiers: modParam)
        case .keyboardF11: return functionKeySequence(23, modifiers: modParam)
        case .keyboardF12: return functionKeySequence(24, modifiers: modParam)

        // Enter / Return
        case .keyboardReturnOrEnter:
            return [0x0D] // CR

        // Tab
        case .keyboardTab:
            if modifiers.contains(.shift) {
                return esc("[Z") // Backtab / Shift-Tab
            }
            return [0x09]

        // Backspace (Delete key on Mac keyboards)
        case .keyboardDeleteOrBackspace:
            if modifiers.contains(.control) {
                return [0x08] // BS
            }
            if modifiers.contains(.alternate) {
                return [0x1B, 0x7F] // ESC + DEL
            }
            return [0x7F] // DEL

        // Escape
        case .keyboardEscape:
            return [0x1B]

        // Space with Ctrl
        case .keyboardSpacebar:
            if modifiers.contains(.control) {
                return [0x00] // NUL
            }
            return nil // Let normal character handling deal with it

        default:
            return nil
        }
    }

    // MARK: - Control Characters

    /// Encode Ctrl+letter as the corresponding control character.
    private func encodeControlKey(characters: String) -> [UInt8]? {
        guard let baseChar = characters.lowercased().unicodeScalars.first else {
            return nil
        }

        let value = baseChar.value

        // Ctrl+A through Ctrl+Z -> 0x01 through 0x1A
        if value >= UInt32(Character("a").asciiValue!),
           value <= UInt32(Character("z").asciiValue!) {
            let ctrl = UInt8(value - UInt32(Character("a").asciiValue!) + 1)
            return [ctrl]
        }

        // Ctrl+[ -> ESC (0x1B)
        if value == UInt32(Character("[").asciiValue!) {
            return [0x1B]
        }
        // Ctrl+\ -> FS (0x1C)
        if value == UInt32(Character("\\").asciiValue!) {
            return [0x1C]
        }
        // Ctrl+] -> GS (0x1D)
        if value == UInt32(Character("]").asciiValue!) {
            return [0x1D]
        }
        // Ctrl+^ -> RS (0x1E)
        if value == UInt32(Character("^").asciiValue!) {
            return [0x1E]
        }
        // Ctrl+_ -> US (0x1F)
        if value == UInt32(Character("_").asciiValue!) {
            return [0x1F]
        }
        // Ctrl+Space or Ctrl+@ -> NUL (0x00)
        if value == UInt32(Character("@").asciiValue!) || value == UInt32(Character(" ").asciiValue!) {
            return [0x00]
        }

        return nil
    }

    // MARK: - Sequence Builders

    /// Build a cursor key sequence (arrows, etc.).
    /// In application mode: ESC O <letter>
    /// In normal mode: ESC [ <letter>
    /// With modifiers: ESC [ 1 ; <mod> <letter>
    private func cursorKeySequence(
        _ letter: Character,
        modifiers: Int,
        applicationMode: Bool
    ) -> [UInt8] {
        if modifiers > 0 {
            // Modified arrows always use CSI format
            return esc("[1;\(modifiers + 1)\(letter)")
        }
        if applicationMode {
            return esc("O\(letter)")
        }
        return esc("[\(letter)")
    }

    /// Build a CSI sequence with a numeric parameter: ESC [ <num> ~ or ESC [ <num> ; <mod> ~
    private func csiSequence(_ num: Int, _ suffix: Character, modifiers: Int) -> [UInt8] {
        if modifiers > 0 {
            return esc("[\(num);\(modifiers + 1)\(suffix)")
        }
        return esc("[\(num)\(suffix)")
    }

    /// Build a function key sequence: ESC [ <num> ~ or ESC [ <num> ; <mod> ~
    private func functionKeySequence(_ num: Int, modifiers: Int) -> [UInt8] {
        return csiSequence(num, "~", modifiers: modifiers)
    }

    /// Build an escape sequence from a string.
    private func esc(_ s: String) -> [UInt8] {
        return [0x1B] + Array(s.utf8)
    }

    /// Compute the modifier parameter for CSI sequences.
    ///
    /// The modifier parameter is encoded as `1 + (bitfield)` where:
    /// - Bit 0 (1): Shift
    /// - Bit 1 (2): Alt/Option
    /// - Bit 2 (4): Ctrl
    /// - Bit 3 (8): Meta (Cmd on Apple keyboards)
    ///
    /// Returns 0 if no modifiers are active (meaning no modifier parameter is needed).
    private func modifierParameter(_ flags: UIKeyModifierFlags) -> Int {
        var param = 0
        if flags.contains(.shift)     { param |= 1 }
        if flags.contains(.alternate) { param |= 2 }
        if flags.contains(.control)   { param |= 4 }
        if flags.contains(.command)   { param |= 8 }
        return param
    }
}

#endif
