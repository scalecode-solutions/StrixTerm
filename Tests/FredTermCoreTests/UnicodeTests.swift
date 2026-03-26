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

// MARK: - Unicode Terminal Tests (ported from SwiftTerm)

@Suite("Unicode Terminal Tests")
struct UnicodeTerminalTests {
    private func makeState(cols: Int = 80, rows: Int = 25) -> TerminalState {
        TerminalState(cols: cols, rows: rows)
    }

    @Test("Combining characters")
    func testCombiningCharacters() {
        var s = makeState()
        defer { s.deallocate() }

        // Feed combining characters
        s.feed(text: "\u{39b}\u{30a}\r\nv\u{307}\r\nr\u{308}\r\na\u{20d1}\r\nb\u{20d1}")

        #expect(s.cellText(col: 0, row: 0) == "Λ̊")
        #expect(s.cellText(col: 0, row: 1) == "v̇")
        #expect(s.cellText(col: 0, row: 2) == "r̈")
        #expect(s.cellText(col: 0, row: 3) == "a⃑")
        #expect(s.cellText(col: 0, row: 4) == "b⃑")
    }

    @Test("Variation selector VS16 makes wide")
    func testVariationSelectorVS16() {
        var s = makeState()
        defer { s.deallocate() }

        // U+26E9 (Shinto shrine) + VS16 = wide
        s.feed(text: "\u{026e9}\u{0fe0f}\n\r\u{026e9}\u{0fe0e}\n\r\u{026e9}")

        // First line should have 2 columns (VS16)
        let cell0 = s.getCell(col: 0, row: 0)
        #expect(cell0.width == 2)

        // Second line should have 1 column (VS15)
        let cell1 = s.getCell(col: 0, row: 1)
        #expect(cell1.width == 1)

        // Third line: default width (1 for this character)
        let cell2 = s.getCell(col: 0, row: 2)
        #expect(cell2.width == 1)
    }

    @Test("Combined positioning after VS16 upgrade")
    func testCombinedPositioning() {
        var s = makeState()
        defer { s.deallocate() }

        // Baseline: 2-column hangul + 'x'
        s.feed(text: "\u{1100}x\n\r")
        #expect(s.cellText(col: 0, row: 0) == "\u{1100}")
        #expect(s.getCell(col: 1, row: 0).flags.contains(.wideContinuation))
        #expect(s.cellText(col: 2, row: 0) == "x")

        // VS16 upgrade: char goes from 1 col to 2 cols, 'x' should be at col 2
        s.feed(text: "\u{026e9}\u{0fe0f}x")
        let text0 = s.cellText(col: 0, row: 1)
        #expect(text0.unicodeScalars.contains { $0.value == 0x26e9 })
        #expect(s.cellText(col: 2, row: 1) == "x")
    }

    @Test("Emoji with skin tone modifiers")
    func testEmoji() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "👦🏻x\r\n👦🏿x\r\n")

        #expect(s.cellText(col: 0, row: 0) == "👦🏻")
        #expect(s.getCell(col: 1, row: 0).flags.contains(.wideContinuation))
        #expect(s.cellText(col: 2, row: 0) == "x")
        #expect(s.cellText(col: 0, row: 1) == "👦🏿")
        #expect(s.getCell(col: 1, row: 1).flags.contains(.wideContinuation))
        #expect(s.cellText(col: 2, row: 1) == "x")
    }

    @Test("Emoji with modifier base (hand with skin tone)")
    func testEmojiWithModifierBase() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "🖐🏾\r\n")
        #expect(s.cellText(col: 0, row: 0) == "🖐🏾")
    }

    @Test("Emoji ZWJ sequence (family)")
    func testEmojiZWJSequence() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "👩‍👩‍👦‍👦\r\n")
        #expect(s.cellText(col: 0, row: 0) == "👩‍👩‍👦‍👦")
    }

    @Test("Emoji ZWJ sequence simple (couple with heart)")
    func testEmojiZWJSequenceSimple() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "👩‍❤️‍👨\r\n")
        #expect(s.cellText(col: 0, row: 0) == "👩‍❤️‍👨")
    }

    @Test("CJK character positioning")
    func testCJKCharacterPositioning() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "あいう")

        #expect(s.cellText(col: 0, row: 0) == "あ")
        #expect(s.getCell(col: 1, row: 0).flags.contains(.wideContinuation))
        #expect(s.cellText(col: 2, row: 0) == "い")
        #expect(s.getCell(col: 3, row: 0).flags.contains(.wideContinuation))
        #expect(s.cellText(col: 4, row: 0) == "う")
        #expect(s.getCell(col: 5, row: 0).flags.contains(.wideContinuation))

        // Widths
        #expect(s.getCell(col: 0, row: 0).width == 2)
        #expect(s.getCell(col: 2, row: 0).width == 2)
        #expect(s.getCell(col: 4, row: 0).width == 2)

        // Cursor should be at column 6
        #expect(s.buffer.cursorX == 6)
    }

    @Test("CJK mixed with ASCII")
    func testCJKMixedWithAscii() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "aあbいc")

        #expect(s.cellText(col: 0, row: 0) == "a")
        #expect(s.getCell(col: 0, row: 0).width == 1)
        #expect(s.cellText(col: 1, row: 0) == "あ")
        #expect(s.getCell(col: 1, row: 0).width == 2)
        #expect(s.cellText(col: 3, row: 0) == "b")
        #expect(s.getCell(col: 3, row: 0).width == 1)
        #expect(s.cellText(col: 4, row: 0) == "い")
        #expect(s.getCell(col: 4, row: 0).width == 2)
        #expect(s.cellText(col: 6, row: 0) == "c")
        #expect(s.getCell(col: 6, row: 0).width == 1)
        #expect(s.buffer.cursorX == 7)
    }

    @Test("Chinese character positioning")
    func testChineseCharacterPositioning() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "中文字")

        #expect(s.cellText(col: 0, row: 0) == "中")
        #expect(s.cellText(col: 2, row: 0) == "文")
        #expect(s.cellText(col: 4, row: 0) == "字")

        #expect(s.getCell(col: 0, row: 0).width == 2)
        #expect(s.getCell(col: 2, row: 0).width == 2)
        #expect(s.getCell(col: 4, row: 0).width == 2)
        #expect(s.buffer.cursorX == 6)
    }

    @Test("ZWJ sequence preserves VS16")
    func testZwJSequencePreservesVS16() {
        var s = makeState()
        defer { s.deallocate() }

        let sequence = "👩‍❤\u{FE0F}"
        s.feed(text: "\(sequence)\r\n")

        let text = s.cellText(col: 0, row: 0)
        #expect(text.unicodeScalars.contains { $0.value == 0xFE0F })
    }

    @Test("ZWJ sequence preserves VS15")
    func testZwJSequencePreservesVS15() {
        var s = makeState()
        defer { s.deallocate() }

        let sequence = "👩‍❤\u{FE0E}"
        s.feed(text: "\(sequence)\r\n")

        let text = s.cellText(col: 0, row: 0)
        #expect(text.unicodeScalars.contains { $0.value == 0xFE0E })
    }

    @Test("VS15 makes wide char narrow")
    func testVS15MakesWideCharNarrow() {
        var s = makeState()
        defer { s.deallocate() }

        // Umbrella with rain drops (0x2614) is typically width 2
        // VS15 (FE0E) should make it width 1
        s.feed(text: "\u{2614}\u{FE0E}x")

        let cell = s.getCell(col: 0, row: 0)
        #expect(cell.width == 1)
        #expect(s.cellText(col: 1, row: 0) == "x")
    }

    @Test("VS16 makes narrow char wide")
    func testVS16MakesNarrowCharWide() {
        var s = makeState()
        defer { s.deallocate() }

        // Heart (0x2764) + VS16 should be width 2
        s.feed(text: "\u{2764}\u{FE0F}x")

        let cell = s.getCell(col: 0, row: 0)
        #expect(cell.width == 2)
        #expect(s.cellText(col: 2, row: 0) == "x")
    }

    @Test("Fitzpatrick skin tone modifiers")
    func testFitzpatrickModifiers() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "👍🏻\r\n👍🏼\r\n👍🏽\r\n👍🏾\r\n👍🏿\r\n")

        #expect(s.cellText(col: 0, row: 0) == "👍🏻")
        #expect(s.cellText(col: 0, row: 1) == "👍🏼")
        #expect(s.cellText(col: 0, row: 2) == "👍🏽")
        #expect(s.cellText(col: 0, row: 3) == "👍🏾")
        #expect(s.cellText(col: 0, row: 4) == "👍🏿")

        for row in 0..<5 {
            #expect(s.getCell(col: 0, row: row).width == 2)
        }
    }

    @Test("Flag emoji (regional indicators)")
    func testFlagEmoji() {
        var s = makeState()
        defer { s.deallocate() }

        // US flag: U+1F1FA + U+1F1F8
        s.feed(text: "\u{1F1FA}\u{1F1F8}x")

        let cell = s.getCell(col: 0, row: 0)
        #expect(cell.width == 2)
        #expect(s.cellText(col: 0, row: 0) == "🇺🇸")
        #expect(s.cellText(col: 2, row: 0) == "x")
    }

    @Test("Multiple flag emoji")
    func testMultipleFlagEmoji() {
        var s = makeState()
        defer { s.deallocate() }

        // US + GB flags
        s.feed(text: "\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}x")

        #expect(s.cellText(col: 0, row: 0) == "🇺🇸")
        #expect(s.getCell(col: 0, row: 0).width == 2)
        #expect(s.cellText(col: 2, row: 0) == "🇬🇧")
        #expect(s.getCell(col: 2, row: 0).width == 2)
        #expect(s.cellText(col: 4, row: 0) == "x")
    }

    @Test("Keycap emoji sequences")
    func testKeycapEmoji() {
        var s = makeState()
        defer { s.deallocate() }

        // Keycap 1: '1' + VS16 + U+20E3
        s.feed(text: "1\u{FE0F}\u{20E3}x")

        let text = s.cellText(col: 0, row: 0)
        #expect(text.unicodeScalars.contains { $0 == "1" })
        // Keycap with VS16 should be width 2
        #expect(s.getCell(col: 0, row: 0).width == 2)
    }

    @Test("Multiple combining characters on single base")
    func testMultipleCombiningCharacters() {
        var s = makeState()
        defer { s.deallocate() }

        // e + acute + tilde
        s.feed(text: "e\u{0301}\u{0303}x")

        let text = s.cellText(col: 0, row: 0)
        #expect(text.unicodeScalars.count == 3)
        #expect(s.getCell(col: 0, row: 0).width == 1)
        #expect(s.cellText(col: 1, row: 0) == "x")
    }

    @Test("Complex emoji ZWJ with modifiers")
    func testComplexEmojiZWJWithModifiers() {
        var s = makeState()
        defer { s.deallocate() }

        // Woman technologist with skin tone
        s.feed(text: "👩🏻‍💻x")

        #expect(s.cellText(col: 0, row: 0) == "👩🏻‍💻")
        #expect(s.getCell(col: 0, row: 0).width == 2)
        #expect(s.cellText(col: 2, row: 0) == "x")
    }

    @Test("Korean Hangul")
    func testKoreanHangul() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "한글x")

        #expect(s.cellText(col: 0, row: 0) == "한")
        #expect(s.getCell(col: 0, row: 0).width == 2)
        #expect(s.cellText(col: 2, row: 0) == "글")
        #expect(s.getCell(col: 2, row: 0).width == 2)
        #expect(s.cellText(col: 4, row: 0) == "x")
    }

    @Test("Overwrite wide character clears spacer")
    func testOverwriteWideCharacter() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "あ")
        #expect(s.getCell(col: 0, row: 0).width == 2)

        // Move cursor back and overwrite with narrow character
        s.feed(text: "\u{1b}[1Gx")
        #expect(s.cellText(col: 0, row: 0) == "x")
        #expect(s.getCell(col: 0, row: 0).width == 1)
    }

    @Test("Wide character wrapping at end of line")
    func testWideCharacterWrapping() {
        var s = makeState(cols: 10, rows: 5)
        defer { s.deallocate() }

        // Fill line to leave only 1 cell, then insert wide character
        let fill = String(repeating: "x", count: 9)
        s.feed(text: fill)
        s.feed(text: "あ")

        // Wide character should wrap to next line
        #expect(s.cellText(col: 0, row: 1) == "あ")
        #expect(s.buffer.cursorY == 1)
    }

    @Test("No-break space width")
    func testNoBreakSpaceWidth() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: ">\u{00A0}x")

        #expect(s.cellText(col: 0, row: 0) == ">")
        #expect(s.getCell(col: 0, row: 0).width == 1)
        // NBSP at col 1 should be width 1
        #expect(s.getCell(col: 1, row: 0).width == 1)
        #expect(s.cellText(col: 2, row: 0) == "x")
        #expect(s.buffer.cursorX == 3)
    }

    @Test("Line text resolves grapheme refs")
    func testLineTextWithGraphemes() {
        var s = makeState()
        defer { s.deallocate() }

        let sequence = "👩‍👩‍👦‍👦"
        s.feed(text: "\(sequence)X")

        let line = s.lineText(0)
        #expect(line.contains(sequence))
        #expect(line.hasSuffix("X"))
    }
}
