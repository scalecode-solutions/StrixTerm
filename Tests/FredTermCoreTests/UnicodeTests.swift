import Testing
@testable import FredTermCore

@Suite("Unicode Width Tests")
struct UnicodeWidthTests {
    @Test("ASCII is single width")
    func asciiWidth() {
        #expect(UnicodeWidth.width(of: 0x41) == 1) // 'A'
        #expect(UnicodeWidth.width(of: 0x7E) == 1) // '~'
    }

    @Test("CJK is double width")
    func cjkWidth() {
        #expect(UnicodeWidth.width(of: 0x4E2D) == 2) // 中
        #expect(UnicodeWidth.width(of: 0x56FD) == 2) // 国
        #expect(UnicodeWidth.width(of: 0x3042) == 2) // あ (Hiragana)
    }

    @Test("Emoji is double width")
    func emojiWidth() {
        #expect(UnicodeWidth.width(of: 0x1F600) == 2) // 😀
        #expect(UnicodeWidth.width(of: 0x1F4A9) == 2) // 💩
    }

    @Test("Combining marks are zero width")
    func combiningWidth() {
        #expect(UnicodeWidth.isZeroWidth(0x0301)) // Combining acute accent
        #expect(UnicodeWidth.isZeroWidth(0x0300)) // Combining grave accent
    }

    @Test("ZWJ is zero width")
    func zwjWidth() {
        #expect(UnicodeWidth.isZeroWidth(0x200D)) // Zero Width Joiner
    }

    @Test("Hangul is wide")
    func hangulWidth() {
        #expect(UnicodeWidth.width(of: 0xAC00) == 2) // 가
        #expect(UnicodeWidth.width(of: 0xD7A3) == 2) // Last Hangul syllable
    }

    @Test("Latin is single width")
    func latinWidth() {
        #expect(UnicodeWidth.width(of: 0x00E9) == 1) // é
        #expect(UnicodeWidth.width(of: 0x00FC) == 1) // ü
    }
}

@Suite("Character Set Tests")
struct CharacterSetTests {
    @Test("DEC Special Graphics mapping")
    func decSpecialGraphics() {
        // 'q' (0x71) -> BOX DRAWINGS LIGHT HORIZONTAL (0x2500)
        #expect(decSpecialGraphicsMap[0x71] == 0x2500)
        // 'j' (0x6A) -> BOX DRAWINGS LIGHT UP AND LEFT (0x2518)
        #expect(decSpecialGraphicsMap[0x6A] == 0x2518)
        // 'l' (0x6C) -> BOX DRAWINGS LIGHT DOWN AND RIGHT (0x250C)
        #expect(decSpecialGraphicsMap[0x6C] == 0x250C)
    }

    @Test("Charset designation from byte")
    func charsetDesignation() {
        #expect(CharsetState.from(final: 0x30) == .decSpecialGraphics)
        #expect(CharsetState.from(final: 0x42) == .usASCII)
        #expect(CharsetState.from(final: 0x41) == .uk)
    }

    @Test("Charset state switching")
    func charsetSwitching() {
        var cs = CharsetState()
        #expect(cs.currentCharset == .usASCII)

        cs.setCharset(at: 0, to: .decSpecialGraphics)
        #expect(cs.currentCharset == .decSpecialGraphics)

        cs.activeGL = 1
        #expect(cs.currentCharset == .usASCII) // G1 is still default

        cs.setCharset(at: 1, to: .uk)
        #expect(cs.currentCharset == .uk)
    }
}
