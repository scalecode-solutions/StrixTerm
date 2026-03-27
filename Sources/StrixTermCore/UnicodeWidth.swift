/// Unicode East Asian Width determination.
/// Used to decide whether a character occupies 1 or 2 cells.
public enum UnicodeWidth {
    /// Returns the display width of a Unicode scalar (1 or 2).
    @inline(__always)
    public static func width(of scalar: UInt32) -> Int {
        if scalar < 0x1100 { return 1 }
        return isWide(scalar) ? 2 : 1
    }

    /// Check if a scalar is a wide (fullwidth/wide) character.
    public static func isWide(_ cp: UInt32) -> Bool {
        // Hangul Jamo
        if cp >= 0x1100 && cp <= 0x115F { return true }
        // CJK and other wide ranges
        if cp >= 0x2E80 && cp <= 0x303E { return true }
        if cp >= 0x3041 && cp <= 0x33BF { return true }
        if cp >= 0x3400 && cp <= 0x4DBF { return true }
        // CJK Unified Ideographs
        if cp >= 0x4E00 && cp <= 0x9FFF { return true }
        // CJK Compatibility Ideographs
        if cp >= 0xF900 && cp <= 0xFAFF { return true }
        // Fullwidth Forms
        if cp >= 0xFF01 && cp <= 0xFF60 { return true }
        if cp >= 0xFFE0 && cp <= 0xFFE6 { return true }
        // Hangul Syllables
        if cp >= 0xAC00 && cp <= 0xD7A3 { return true }
        // CJK Unified Ideographs Extension B-H
        if cp >= 0x20000 && cp <= 0x323AF { return true }
        // CJK Compatibility Ideographs Supplement
        if cp >= 0x2F800 && cp <= 0x2FA1F { return true }
        // Emoji that are typically rendered as wide
        if isWideEmoji(cp) { return true }
        return false
    }

    /// Check if a scalar is a wide emoji.
    private static func isWideEmoji(_ cp: UInt32) -> Bool {
        // Miscellaneous Symbols and Pictographs
        if cp >= 0x1F300 && cp <= 0x1F5FF { return true }
        // Emoticons
        if cp >= 0x1F600 && cp <= 0x1F64F { return true }
        // Transport and Map Symbols
        if cp >= 0x1F680 && cp <= 0x1F6FF { return true }
        // Supplemental Symbols and Pictographs
        if cp >= 0x1F900 && cp <= 0x1F9FF { return true }
        // Symbols and Pictographs Extended-A
        if cp >= 0x1FA00 && cp <= 0x1FA6F { return true }
        if cp >= 0x1FA70 && cp <= 0x1FAFF { return true }
        // Regional Indicators
        if cp >= 0x1F1E0 && cp <= 0x1F1FF { return true }
        // Misc individual wide emoji
        if cp == 0x200D { return false } // ZWJ is zero-width
        if cp == 0xFE0F { return false } // VS16 is zero-width
        if cp >= 0x231A && cp <= 0x231B { return true }
        if cp >= 0x23E9 && cp <= 0x23F3 { return true }
        if cp >= 0x25AA && cp <= 0x25AB { return true }
        if cp >= 0x25FB && cp <= 0x25FE { return true }
        if cp >= 0x2600 && cp <= 0x2604 { return true }
        if cp >= 0x2614 && cp <= 0x2615 { return true }
        if cp == 0x2648 { return true }
        if cp >= 0x2660 && cp <= 0x2668 { return true }
        if cp == 0x267F { return true }
        if cp >= 0x2693 && cp <= 0x2696 { return true }
        if cp >= 0x26A0 && cp <= 0x26A1 { return true }
        if cp >= 0x26AA && cp <= 0x26AB { return true }
        if cp >= 0x26BD && cp <= 0x26BE { return true }
        if cp >= 0x26C4 && cp <= 0x26C5 { return true }
        if cp >= 0x26CE && cp <= 0x26CF { return true }
        if cp >= 0x26D4 && cp <= 0x26E1 { return true }
        if cp >= 0x26EA && cp <= 0x26FA { return true }
        if cp >= 0x2702 && cp <= 0x2764 { return true }
        return false
    }

    /// Check if a scalar is a zero-width character.
    @inline(__always)
    public static func isZeroWidth(_ cp: UInt32) -> Bool {
        // Combining marks
        if cp >= 0x0300 && cp <= 0x036F { return true }
        // General combining
        if cp >= 0x1AB0 && cp <= 0x1AFF { return true }
        if cp >= 0x1DC0 && cp <= 0x1DFF { return true }
        if cp >= 0x20D0 && cp <= 0x20FF { return true }
        if cp >= 0xFE20 && cp <= 0xFE2F { return true }
        // Zero-width characters
        if cp == 0x200B || cp == 0x200C || cp == 0x200D { return true }
        if cp == 0xFEFF { return true } // BOM / ZWNBSP
        if cp == 0xFE0E || cp == 0xFE0F { return true } // Variation selectors
        // Variation selectors supplement
        if cp >= 0xE0100 && cp <= 0xE01EF { return true }
        return false
    }
}
