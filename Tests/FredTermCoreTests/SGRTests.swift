import Testing
@testable import FredTermCore

@Suite("SGR Tests")
struct SGRTests {
    // MARK: - Helpers

    /// Create a terminal, feed text, and return the state for inspection.
    private func makeState(cols: Int = 10, rows: Int = 5) -> TerminalState {
        TerminalState(cols: cols, rows: rows, maxScrollback: 0)
    }

    /// Get the attribute entry for a cell at the given position.
    private func attr(_ state: TerminalState, row: Int = 0, col: Int = 0) -> AttributeEntry {
        let line = state.buffer.yBase + row
        let cell = state.buffer.grid[line, col]
        return state.attributes[cell.attribute]
    }

    // MARK: - Bold, Italic, Underline

    @Test("Bold, italic, underline combined")
    func testBoldItalicUnderline() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[1;3;4mX")

        let a = attr(state)
        #expect(a.style.contains(.bold))
        #expect(a.style.contains(.italic))
        #expect(a.style.contains(.underline))
    }

    @Test("Reset bold with SGR 22")
    func testResetBold() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[1mX\u{1b}[22mY")

        let boldAttr = attr(state, col: 0)
        let resetAttr = attr(state, col: 1)
        #expect(boldAttr.style.contains(.bold))
        #expect(!resetAttr.style.contains(.bold))
    }

    @Test("Dim attribute (SGR 2)")
    func testDim() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[2mX\u{1b}[22mY")

        let dimAttr = attr(state, col: 0)
        let normalAttr = attr(state, col: 1)
        #expect(dimAttr.style.contains(.dim))
        #expect(!normalAttr.style.contains(.dim))
    }

    @Test("Reset italic with SGR 23")
    func testResetItalic() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[3mX\u{1b}[23mY")

        #expect(attr(state, col: 0).style.contains(.italic))
        #expect(!attr(state, col: 1).style.contains(.italic))
    }

    @Test("Underline set and reset (SGR 4 / 24)")
    func testUnderlineSetReset() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4mX\u{1b}[24mY")

        #expect(attr(state, col: 0).style.contains(.underline))
        #expect(!attr(state, col: 1).style.contains(.underline))
    }

    @Test("Blink attribute (SGR 5 / 25)")
    func testBlink() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[5mX\u{1b}[25mY")

        #expect(attr(state, col: 0).style.contains(.blink))
        #expect(!attr(state, col: 1).style.contains(.blink))
    }

    @Test("Inverse attribute (SGR 7 / 27)")
    func testInverse() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[7mX\u{1b}[27mY")

        #expect(attr(state, col: 0).style.contains(.inverse))
        #expect(!attr(state, col: 1).style.contains(.inverse))
    }

    @Test("Invisible attribute (SGR 8 / 28)")
    func testInvisible() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[8mX\u{1b}[28mY")

        #expect(attr(state, col: 0).style.contains(.invisible))
        #expect(!attr(state, col: 1).style.contains(.invisible))
    }

    @Test("Strikethrough attribute (SGR 9 / 29)")
    func testStrikethrough() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[9mX\u{1b}[29mY")

        #expect(attr(state, col: 0).style.contains(.strikethrough))
        #expect(!attr(state, col: 1).style.contains(.strikethrough))
    }

    @Test("Overline attribute (SGR 53 / 55)")
    func testOverline() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[53mX\u{1b}[55mY")

        #expect(attr(state, col: 0).style.contains(.overline))
        #expect(!attr(state, col: 1).style.contains(.overline))
    }

    @Test("SGR 21 sets double underline")
    func testDoubleUnderline() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[21mX")

        let a = attr(state)
        #expect(a.style.contains(.underline))
        #expect(a.underlineStyle == .double)
    }

    // MARK: - SGR Reset

    @Test("SGR 0 resets all attributes")
    func testSgrResetAll() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[1;3;4;31mX\u{1b}[0mY")

        let styledAttr = attr(state, col: 0)
        let resetAttr = attr(state, col: 1)

        #expect(styledAttr.style.contains(.bold))
        #expect(styledAttr.style.contains(.italic))
        #expect(styledAttr.style.contains(.underline))
        #expect(styledAttr.fg == .indexed(1))

        #expect(!resetAttr.style.contains(.bold))
        #expect(!resetAttr.style.contains(.italic))
        #expect(!resetAttr.style.contains(.underline))
        #expect(resetAttr.fg == .default)
    }

    @Test("SGR m (no params) resets all attributes")
    func testSgrImplicitReset() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[1;31mA\u{1b}[mB")

        let attrA = attr(state, col: 0)
        let attrB = attr(state, col: 1)
        #expect(attrA.style.contains(.bold))
        #expect(!attrB.style.contains(.bold))
        #expect(attrB.fg == .default)
    }

    // MARK: - 8-Color Foreground / Background

    @Test("8-color foreground (SGR 30-37)")
    func testEightColorFg() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[31mX")

        #expect(attr(state).fg == .indexed(1)) // Red
    }

    @Test("8-color background (SGR 40-47)")
    func testEightColorBg() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[44mX")

        #expect(attr(state).bg == .indexed(4)) // Blue
    }

    @Test("8-color foreground and background combined")
    func testEightColorFgBg() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[31;44mX")

        #expect(attr(state).fg == .indexed(1))
        #expect(attr(state).bg == .indexed(4))
    }

    // MARK: - Bright Colors

    @Test("Bright foreground colors (SGR 90-97)")
    func testBrightForeground() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[91mX") // Bright red

        #expect(attr(state).fg == .indexed(9))
    }

    @Test("Bright background colors (SGR 100-107)")
    func testBrightBackground() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[104mX") // Bright blue

        #expect(attr(state).bg == .indexed(12))
    }

    // MARK: - 256-Color

    @Test("256-color foreground (SGR 38;5;N)")
    func test256ColorFg() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38;5;200mX")

        #expect(attr(state).fg == .indexed(200))
    }

    @Test("256-color background (SGR 48;5;N)")
    func test256ColorBg() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[48;5;100mX")

        #expect(attr(state).bg == .indexed(100))
    }

    @Test("256-color foreground and background combined")
    func test256ColorFgBg() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38;5;200;48;5;100mX")

        #expect(attr(state).fg == .indexed(200))
        #expect(attr(state).bg == .indexed(100))
    }

    // MARK: - True Color (Semicolon Syntax)

    @Test("True color foreground semicolon (SGR 38;2;R;G;B)")
    func testTrueColorFgSemicolon() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38;2;1;2;3mX")

        #expect(attr(state).fg == .rgb(1, 2, 3))
    }

    @Test("True color background semicolon (SGR 48;2;R;G;B)")
    func testTrueColorBgSemicolon() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[48;2;4;5;6mX")

        #expect(attr(state).bg == .rgb(4, 5, 6))
    }

    @Test("True color foreground and background semicolon combined")
    func testTrueColorFgBgSemicolon() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38;2;1;2;3;48;2;4;5;6mX")

        #expect(attr(state).fg == .rgb(1, 2, 3))
        #expect(attr(state).bg == .rgb(4, 5, 6))
    }

    @Test("True color with specific values from SwiftTerm ColorTests")
    func testTrueColorSpecificValues() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38;2;19;49;174;48;2;23;56;179mX")

        #expect(attr(state).fg == .rgb(19, 49, 174))
        #expect(attr(state).bg == .rgb(23, 56, 179))
    }

    // MARK: - True Color (Colon Syntax)

    @Test("True color foreground colon with colorspace (38:2:CS:R:G:B)")
    func testTrueColorFgColonWithColorspace() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38:2:0:10:20:30mX")

        #expect(attr(state).fg == .rgb(10, 20, 30))
    }

    @Test("True color foreground colon with empty colorspace (38:2::R:G:B)")
    func testTrueColorFgColonEmptyColorspace() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[38:2::255:10:255mX")

        #expect(attr(state).fg == .rgb(255, 10, 255))
    }

    @Test("Partial colon color sequence - remaining params processed as SGR")
    func testPartialColonColorProcessed() {
        var state = makeState()
        defer { state.deallocate() }
        // Set a known color first
        state.feed(text: "\u{1b}[38:2::255:10:255mA")
        // Now feed a partial sequence (missing G and B)
        // 38:2::255 -> params [38, 2, -1, 255] with hasSubParams
        // parseExtendedColor fails (not enough params for truecolor)
        // Remaining params [2, -1, 255] processed as SGR:
        //   2 = dim, -1 defaults to 0 = reset, 255 = unknown
        // So all attributes get reset by the implicit SGR 0.
        state.feed(text: "\u{1b}[38:2::255mB")

        let attrA = attr(state, col: 0)
        let attrB = attr(state, col: 1)
        // A should have the truecolor
        #expect(attrA.fg == .rgb(255, 10, 255))
        // B gets reset because the empty sub-param becomes SGR 0
        #expect(attrB.fg == .default)
    }

    // MARK: - Default Colors

    @Test("Default foreground color (SGR 39)")
    func testDefaultForeground() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[31mX\u{1b}[39mY")

        #expect(attr(state, col: 0).fg == .indexed(1))
        #expect(attr(state, col: 1).fg == .default)
    }

    @Test("Default background color (SGR 49)")
    func testDefaultBackground() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[44mX\u{1b}[49mY")

        #expect(attr(state, col: 0).bg == .indexed(4))
        #expect(attr(state, col: 1).bg == .default)
    }

    // MARK: - Underline Styles (Colon Sub-params)

    @Test("Underline style none (4:0)")
    func testUnderlineStyleNone() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4mA\u{1b}[4:0mB")

        #expect(attr(state, col: 0).style.contains(.underline))
        #expect(!attr(state, col: 1).style.contains(.underline))
        #expect(attr(state, col: 1).underlineStyle == .none)
    }

    @Test("Underline style single (4:1)")
    func testUnderlineStyleSingle() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4:1mX")

        #expect(attr(state).style.contains(.underline))
        #expect(attr(state).underlineStyle == .single)
    }

    @Test("Underline style double (4:2)")
    func testUnderlineStyleDouble() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4:2mX")

        #expect(attr(state).style.contains(.underline))
        #expect(attr(state).underlineStyle == .double)
    }

    @Test("Underline style curly (4:3)")
    func testUnderlineStyleCurly() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4:3mX")

        #expect(attr(state).style.contains(.underline))
        #expect(attr(state).underlineStyle == .curly)
    }

    @Test("Underline style dotted (4:4)")
    func testUnderlineStyleDotted() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4:4mX")

        #expect(attr(state).style.contains(.underline))
        #expect(attr(state).underlineStyle == .dotted)
    }

    @Test("Underline style dashed (4:5)")
    func testUnderlineStyleDashed() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4:5mX")

        #expect(attr(state).style.contains(.underline))
        #expect(attr(state).underlineStyle == .dashed)
    }

    // MARK: - Underline Colors

    @Test("Underline color set and reset (SGR 58;2;R;G;B / 59)")
    func testUnderlineColorSetReset() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4;58;2;9;8;7mX\u{1b}[59mY")

        #expect(attr(state, col: 0).underlineColor == .rgb(9, 8, 7))
        #expect(attr(state, col: 1).underlineColor == nil)
    }

    @Test("Underline color with colon syntax and colorspace (58:2::R:G:B)")
    func testUnderlineColorColonWithColorspace() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[58:2::240:143:104mX")

        #expect(attr(state).underlineColor == .rgb(240, 143, 104))
    }

    @Test("256-color underline (58:5:N)")
    func testUnderlineColor256() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[4;58:5:200mX")

        #expect(attr(state).style.contains(.underline))
        #expect(attr(state).underlineColor == .indexed(200))
    }

    // MARK: - Combined Attributes

    @Test("Multiple attributes combined in one sequence")
    func testMultipleCombined() {
        var state = makeState(cols: 20)
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[1;2;3;4;5;7;9;38;5;196;48;5;21mX")

        let a = attr(state)
        #expect(a.style.contains(.bold))
        #expect(a.style.contains(.dim))
        #expect(a.style.contains(.italic))
        #expect(a.style.contains(.underline))
        #expect(a.style.contains(.blink))
        #expect(a.style.contains(.inverse))
        #expect(a.style.contains(.strikethrough))
        #expect(a.fg == .indexed(196))
        #expect(a.bg == .indexed(21))
    }

    @Test("Bold and dim both reset by SGR 22")
    func testBoldDimBothResetBy22() {
        var state = makeState()
        defer { state.deallocate() }
        state.feed(text: "\u{1b}[1;2mX\u{1b}[22mY")

        let styled = attr(state, col: 0)
        let reset = attr(state, col: 1)
        #expect(styled.style.contains(.bold))
        #expect(styled.style.contains(.dim))
        #expect(!reset.style.contains(.bold))
        #expect(!reset.style.contains(.dim))
    }

    @Test("All 8 standard foreground colors")
    func testAllStandardForegroundColors() {
        var state = makeState(cols: 20)
        defer { state.deallocate() }
        for i in 0..<8 {
            state.feed(text: "\u{1b}[\(30 + i)m\(i)")
        }
        for i in 0..<8 {
            #expect(attr(state, col: i).fg == .indexed(UInt8(i)))
        }
    }

    @Test("All 8 standard background colors")
    func testAllStandardBackgroundColors() {
        var state = makeState(cols: 20)
        defer { state.deallocate() }
        for i in 0..<8 {
            state.feed(text: "\u{1b}[\(40 + i)m\(i)")
        }
        for i in 0..<8 {
            #expect(attr(state, col: i).bg == .indexed(UInt8(i)))
        }
    }

    @Test("All 8 bright foreground colors")
    func testAllBrightForegroundColors() {
        var state = makeState(cols: 20)
        defer { state.deallocate() }
        for i in 0..<8 {
            state.feed(text: "\u{1b}[\(90 + i)m\(i)")
        }
        for i in 0..<8 {
            #expect(attr(state, col: i).fg == .indexed(UInt8(8 + i)))
        }
    }

    @Test("All 8 bright background colors")
    func testAllBrightBackgroundColors() {
        var state = makeState(cols: 20)
        defer { state.deallocate() }
        for i in 0..<8 {
            state.feed(text: "\u{1b}[\(100 + i)m\(i)")
        }
        for i in 0..<8 {
            #expect(attr(state, col: i).bg == .indexed(UInt8(8 + i)))
        }
    }
}
