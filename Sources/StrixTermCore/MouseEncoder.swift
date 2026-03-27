/// Mouse button identifiers for terminal mouse reporting.
public enum MouseButton: Int, Sendable {
    case left = 0
    case middle = 1
    case right = 2
    case none = 3        // for motion without button
    case scrollUp = 4
    case scrollDown = 5
    case scrollLeft = 6
    case scrollRight = 7
}

/// Mouse event action type.
public enum MouseAction: Sendable {
    case press
    case release
    case motion
}

/// Modifier keys held during a mouse event.
public struct MouseModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift   = MouseModifiers(rawValue: 1 << 0)
    public static let alt     = MouseModifiers(rawValue: 1 << 1)
    public static let control = MouseModifiers(rawValue: 1 << 2)
}

/// Encodes mouse events into terminal escape sequences according to the
/// active mouse mode and encoding format.
public struct MouseEncoder: Sendable {

    /// Encode a mouse button press/release/motion into terminal escape sequence bytes.
    ///
    /// Returns `nil` if the current mouse mode does not report this event type.
    ///
    /// - Parameters:
    ///   - button: The mouse button involved.
    ///   - action: Whether this is a press, release, or motion event.
    ///   - position: 0-based character cell coordinates (col, row).
    ///   - pixelPosition: Pixel coordinates for `sgrPixels` encoding. Ignored otherwise.
    ///   - modifiers: Modifier keys held during the event.
    ///   - mode: The active mouse tracking mode.
    ///   - encoding: The active mouse encoding format.
    /// - Returns: The encoded escape sequence bytes, or `nil` if the event should not be reported.
    public static func encode(
        button: MouseButton,
        action: MouseAction,
        position: Position,
        pixelPosition: (x: Int, y: Int)? = nil,
        modifiers: MouseModifiers = [],
        mode: MouseMode,
        encoding: MouseEncoding
    ) -> [UInt8]? {
        // Off mode never reports anything.
        guard mode != .off else { return nil }

        // Filter events based on mode.
        switch mode {
        case .off:
            return nil

        case .x10:
            // x10 only reports button presses (no release, no motion).
            guard action == .press else { return nil }

        case .vt200:
            // vt200 reports press and release, but not motion.
            guard action != .motion else { return nil }

        case .buttonEvent:
            // buttonEvent reports press, release, and motion-with-button-held.
            // Motion without a button is not reported.
            if action == .motion && button == .none { return nil }

        case .anyEvent:
            // anyEvent reports everything: press, release, and all motion.
            break
        }

        // Compute the button value.
        let buttonValue = computeButtonValue(button: button, action: action, modifiers: modifiers, mode: mode)

        // Encode using the selected format.
        switch encoding {
        case .x10:
            return encodeX10(buttonValue: buttonValue, col: position.col, row: position.row)
        case .utf8:
            return encodeUTF8(buttonValue: buttonValue, col: position.col, row: position.row)
        case .sgr:
            return encodeSGR(buttonValue: buttonValue, col: position.col, row: position.row, action: action)
        case .urxvt:
            return encodeURxvt(buttonValue: buttonValue, col: position.col, row: position.row)
        case .sgrPixels:
            let px = pixelPosition ?? (x: position.col, y: position.row)
            return encodeSGRPixels(buttonValue: buttonValue, px: px.x, py: px.y, action: action)
        }
    }

    // MARK: - Button Value Computation

    /// Compute the protocol-level button value from the logical button, action, and modifiers.
    ///
    /// Button encoding:
    /// - left=0, middle=1, right=2, release=3
    /// - scrollUp=64, scrollDown=65, scrollLeft=66, scrollRight=67
    /// - motion adds 32
    /// - shift adds 4, alt/meta adds 8, control adds 16
    static func computeButtonValue(
        button: MouseButton,
        action: MouseAction,
        modifiers: MouseModifiers,
        mode: MouseMode
    ) -> Int {
        var value: Int

        // For x10 mode, no modifiers and release is not reported.
        if mode == .x10 {
            switch button {
            case .left:        value = 0
            case .middle:      value = 1
            case .right:       value = 2
            case .none:        value = 3
            case .scrollUp:    value = 64
            case .scrollDown:  value = 65
            case .scrollLeft:  value = 66
            case .scrollRight: value = 67
            }
            return value
        }

        // For release in X10/UTF-8/URxvt encodings, the button value is 3 (unless scroll).
        // For SGR/SGR-pixels, release preserves the actual button number (the 'm' suffix
        // indicates release).
        switch button {
        case .left:        value = 0
        case .middle:      value = 1
        case .right:       value = 2
        case .none:        value = 3
        case .scrollUp:    value = 64
        case .scrollDown:  value = 65
        case .scrollLeft:  value = 66
        case .scrollRight: value = 67
        }

        // For release in non-SGR encodings, use button value 3.
        if action == .release && button.rawValue <= 2 {
            // SGR and sgrPixels keep the actual button; others use 3.
            // We handle this at the encoding level for SGR. For the base value,
            // we encode release as 3 here; SGR encoders will use the original value.
            // Actually, SGR encoders need the real button, so we only set 3 for non-SGR.
            // This is handled by passing the raw value to SGR and adjusting here for others.
            // We'll pass the real button value through and let the X10/UTF8/URxvt encoders
            // override to 3 on release.
        }

        // Add motion flag.
        if action == .motion {
            value += 32
        }

        // Add modifier flags (not in x10 mode, already handled above).
        if modifiers.contains(.shift) {
            value += 4
        }
        if modifiers.contains(.alt) {
            value += 8
        }
        if modifiers.contains(.control) {
            value += 16
        }

        return value
    }

    // MARK: - X10 Encoding

    /// X10 encoding: `ESC [ M <button+32> <x+1+32> <y+1+32>`
    ///
    /// Each value is a single byte. Coordinates are limited to 223 (255 - 32).
    private static func encodeX10(buttonValue: Int, col: Int, row: Int) -> [UInt8]? {
        let cb = UInt8(clamping: buttonValue + 32)
        let cx = col + 1 + 32
        let cy = row + 1 + 32

        // Coordinates must fit in a single byte.
        guard cx <= 255 && cy <= 255 else { return nil }

        return [0x1B, 0x5B, 0x4D, cb, UInt8(cx), UInt8(cy)]
    }

    // MARK: - UTF-8 Encoding

    /// UTF-8 encoding: `ESC [ M <utf8(button+32)> <utf8(x+33)> <utf8(y+33)>`
    ///
    /// Values < 128 are a single byte; 128-2047 use two-byte UTF-8.
    private static func encodeUTF8(buttonValue: Int, col: Int, row: Int) -> [UInt8]? {
        var result: [UInt8] = [0x1B, 0x5B, 0x4D]
        result += utf8Encode(buttonValue + 32)
        result += utf8Encode(col + 1 + 32)
        result += utf8Encode(row + 1 + 32)
        return result
    }

    /// Encode a value as UTF-8 (single byte for < 128, two bytes for 128-2047).
    private static func utf8Encode(_ value: Int) -> [UInt8] {
        if value < 128 {
            return [UInt8(value)]
        } else if value <= 2047 {
            let byte1 = UInt8(0xC0 | ((value >> 6) & 0x1F))
            let byte2 = UInt8(0x80 | (value & 0x3F))
            return [byte1, byte2]
        } else {
            // Values > 2047 are out of range for this encoding.
            return [UInt8(clamping: value)]
        }
    }

    // MARK: - SGR Encoding

    /// SGR encoding: `ESC [ < buttonValue ; x+1 ; y+1 M` (press/motion) or `m` (release).
    ///
    /// Decimal ASCII, semicolon-delimited. Release uses lowercase 'm'.
    private static func encodeSGR(buttonValue: Int, col: Int, row: Int, action: MouseAction) -> [UInt8]? {
        let suffix: UInt8 = (action == .release) ? 0x6D : 0x4D  // 'm' or 'M'

        // For SGR release, strip the motion flag and use the actual button number
        // (the 'm' suffix already indicates release).
        var bv = buttonValue
        if action == .release {
            // Remove motion bit if present -- release in SGR just uses the button bits.
            bv = bv & ~32
        }

        let s = "\u{1B}[<\(bv);\(col + 1);\(row + 1)"
        var result = Array(s.utf8)
        result.append(suffix)
        return result
    }

    // MARK: - URxvt Encoding

    /// URxvt encoding: `ESC [ <button+32> ; x+1 ; y+1 M`
    private static func encodeURxvt(buttonValue: Int, col: Int, row: Int) -> [UInt8]? {
        let s = "\u{1B}[\(buttonValue + 32);\(col + 1);\(row + 1)M"
        return Array(s.utf8)
    }

    // MARK: - SGR Pixels Encoding

    /// SGR Pixels encoding: same as SGR but with pixel coordinates.
    ///
    /// `ESC [ < buttonValue ; px ; py M` or `m` (release).
    private static func encodeSGRPixels(buttonValue: Int, px: Int, py: Int, action: MouseAction) -> [UInt8]? {
        let suffix: UInt8 = (action == .release) ? 0x6D : 0x4D  // 'm' or 'M'

        var bv = buttonValue
        if action == .release {
            bv = bv & ~32
        }

        let s = "\u{1B}[<\(bv);\(px);\(py)"
        var result = Array(s.utf8)
        result.append(suffix)
        return result
    }
}
