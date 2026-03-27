#if canImport(AppKit)
import AppKit
import StrixTermCore

/// Encodes NSEvent keyboard events into terminal escape sequences.
///
/// This handles the translation from macOS key events to the byte sequences
/// expected by terminal applications, including special keys, modifier
/// combinations, and application cursor/keypad modes.
public struct KeyEncoder: Sendable {

    public init() {}

    // MARK: - Public API

    /// Encode a key event into terminal escape sequence bytes.
    ///
    /// Returns `nil` if the event does not map to a terminal sequence (e.g.,
    /// modifier-only key presses).
    public func encodeKey(
        event: NSEvent,
        applicationCursor: Bool,
        applicationKeypad: Bool,
        kittyFlags: KittyKeyboardFlags
    ) -> [UInt8]? {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        // Check for special keys first (arrows, function keys, etc.)
        if let specialBytes = encodeSpecialKey(
            keyCode: keyCode,
            modifiers: modifiers,
            applicationCursor: applicationCursor,
            applicationKeypad: applicationKeypad
        ) {
            return specialBytes
        }

        // Handle character-producing keys
        guard let characters = event.characters, !characters.isEmpty else {
            return nil
        }

        let hasControl = modifiers.contains(.control)
        let hasOption = modifiers.contains(.option)

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
            // Use charactersIgnoringModifiers so we get the base character
            // rather than the composed character (e.g., Option+a = a, not a)
            if let baseChars = event.charactersIgnoringModifiers {
                let bytes = Array(baseChars.utf8)
                if !bytes.isEmpty {
                    return [0x1B] + bytes
                }
            }
        }

        // Plain text input
        let bytes = Array(characters.utf8)
        if !bytes.isEmpty {
            return bytes
        }

        return nil
    }

    // MARK: - Special Keys

    /// Encode special (non-character) keys like arrows, function keys, etc.
    private func encodeSpecialKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        applicationCursor: Bool,
        applicationKeypad: Bool
    ) -> [UInt8]? {
        let modParam = modifierParameter(modifiers)

        switch keyCode {
        // Arrow keys
        case kVK_UpArrow:
            return cursorKeySequence("A", modifiers: modParam, applicationMode: applicationCursor)
        case kVK_DownArrow:
            return cursorKeySequence("B", modifiers: modParam, applicationMode: applicationCursor)
        case kVK_RightArrow:
            return cursorKeySequence("C", modifiers: modParam, applicationMode: applicationCursor)
        case kVK_LeftArrow:
            return cursorKeySequence("D", modifiers: modParam, applicationMode: applicationCursor)

        // Home / End
        case kVK_Home:
            if modParam > 0 {
                return csiSequence(1, "~", modifiers: modParam)
            }
            return applicationCursor ? esc("OH") : esc("[H")
        case kVK_End:
            if modParam > 0 {
                return csiSequence(4, "~", modifiers: modParam)
            }
            return applicationCursor ? esc("OF") : esc("[F")

        // Page Up / Page Down
        case kVK_PageUp:
            return csiSequence(5, "~", modifiers: modParam)
        case kVK_PageDown:
            return csiSequence(6, "~", modifiers: modParam)

        // Insert / Delete (Forward Delete)
        case kVK_Help: // Insert key on extended keyboards
            return csiSequence(2, "~", modifiers: modParam)
        case kVK_ForwardDelete:
            return csiSequence(3, "~", modifiers: modParam)

        // Function keys F1-F12
        case kVK_F1:  return functionKeySequence(11, modifiers: modParam)
        case kVK_F2:  return functionKeySequence(12, modifiers: modParam)
        case kVK_F3:  return functionKeySequence(13, modifiers: modParam)
        case kVK_F4:  return functionKeySequence(14, modifiers: modParam)
        case kVK_F5:  return functionKeySequence(15, modifiers: modParam)
        case kVK_F6:  return functionKeySequence(17, modifiers: modParam)
        case kVK_F7:  return functionKeySequence(18, modifiers: modParam)
        case kVK_F8:  return functionKeySequence(19, modifiers: modParam)
        case kVK_F9:  return functionKeySequence(20, modifiers: modParam)
        case kVK_F10: return functionKeySequence(21, modifiers: modParam)
        case kVK_F11: return functionKeySequence(23, modifiers: modParam)
        case kVK_F12: return functionKeySequence(24, modifiers: modParam)

        // Enter / Return
        case kVK_Return:
            if modifiers.contains(.control) {
                return [0x0D] // CR even with Ctrl
            }
            return [0x0D] // CR

        // Tab
        case kVK_Tab:
            if modifiers.contains(.shift) {
                return esc("[Z") // Backtab / Shift-Tab
            }
            return [0x09]

        // Backspace
        case kVK_Delete: // This is the Backspace key on Mac
            if modifiers.contains(.control) {
                return [0x08] // BS
            }
            if modifiers.contains(.option) {
                return [0x1B, 0x7F] // ESC + DEL
            }
            return [0x7F] // DEL

        // Escape
        case kVK_Escape:
            return [0x1B]

        // Space with Ctrl
        case kVK_Space:
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
    /// - Bit 3 (8): Meta (not used on Mac, but included for completeness)
    ///
    /// Returns 0 if no modifiers are active (meaning no modifier parameter is needed).
    private func modifierParameter(_ flags: NSEvent.ModifierFlags) -> Int {
        var param = 0
        if flags.contains(.shift)   { param |= 1 }
        if flags.contains(.option)  { param |= 2 }
        if flags.contains(.control) { param |= 4 }
        if flags.contains(.command) { param |= 8 }
        return param
    }
}

// MARK: - Virtual Key Codes

// macOS virtual key codes used for special key identification.
// These are Carbon constants that are stable across macOS versions.
private let kVK_Return: UInt16        = 0x24
private let kVK_Tab: UInt16           = 0x30
private let kVK_Space: UInt16         = 0x31
private let kVK_Delete: UInt16        = 0x33  // Backspace
private let kVK_Escape: UInt16        = 0x35
private let kVK_F1: UInt16            = 0x7A
private let kVK_F2: UInt16            = 0x78
private let kVK_F3: UInt16            = 0x63
private let kVK_F4: UInt16            = 0x76
private let kVK_F5: UInt16            = 0x60
private let kVK_F6: UInt16            = 0x61
private let kVK_F7: UInt16            = 0x62
private let kVK_F8: UInt16            = 0x64
private let kVK_F9: UInt16            = 0x65
private let kVK_F10: UInt16           = 0x6D
private let kVK_F11: UInt16           = 0x67
private let kVK_F12: UInt16           = 0x6F
private let kVK_Home: UInt16          = 0x73
private let kVK_End: UInt16           = 0x77
private let kVK_PageUp: UInt16        = 0x74
private let kVK_PageDown: UInt16      = 0x79
private let kVK_UpArrow: UInt16       = 0x7E
private let kVK_DownArrow: UInt16     = 0x7D
private let kVK_LeftArrow: UInt16     = 0x7B
private let kVK_RightArrow: UInt16    = 0x7C
private let kVK_ForwardDelete: UInt16 = 0x75
private let kVK_Help: UInt16          = 0x72

#endif
