import Testing
@testable import StrixTermCore

/// Port of SwiftTerm's TerminalCoreTests: tests for wraparound, reverse wraparound,
/// origin mode with scroll regions, left/right margins, line insert/delete in
/// scroll regions, and cursor save/restore.
@Suite("Terminal Core Tests")
struct CoreTests {
    private let esc = "\u{1b}"

    @Test("Wraparound enabled (default)")
    func testWraparoundEnabled() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 2)
        defer { state.deallocate() }

        state.feed(text: "helloX")

        TestHarness.assertLineText(state, row: 0, equals: "hello")
        TestHarness.assertLineText(state, row: 1, equals: "X")
        TestHarness.assertCursor(state, col: 1, row: 1)
    }

    @Test("Wraparound disabled")
    func testWraparoundDisabled() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 2)
        defer { state.deallocate() }

        state.feed(text: "\(esc)[?7l")
        state.feed(text: "helloX")

        TestHarness.assertLineText(state, row: 0, equals: "hellX")
        TestHarness.assertLineText(state, row: 1, equals: "")
    }

    @Test("Reverse wraparound backspace")
    func testReverseWraparoundBackspace() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 2)
        defer { state.deallocate() }

        state.feed(text: "\(esc)[?45h")
        state.feed(text: "helloX")
        state.feed(text: "\u{8}\u{8}")

        TestHarness.assertCursor(state, col: 4, row: 0)
    }

    @Test("Origin mode with scroll region")
    func testOriginModeWithScrollRegion() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 4)
        defer { state.deallocate() }

        state.feed(text: "\(esc)[2;3r")
        state.feed(text: "\(esc)[?6h")
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "X")

        let cell = TestHarness.cell(state, row: 1, col: 0)
        let ch = Character(cell.character)
        #expect(ch == "X")
    }

    @Test("Left/right margins with origin mode")
    func testLeftRightMarginsWithOriginMode() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 2)
        defer { state.deallocate() }

        state.feed(text: "\(esc)[?6h")
        state.feed(text: "\(esc)[?69h")
        state.feed(text: "\(esc)[2;4s")
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "ABC")

        let aCell = TestHarness.cell(state, row: 0, col: 1)
        let bCell = TestHarness.cell(state, row: 0, col: 2)
        let cCell = TestHarness.cell(state, row: 0, col: 3)
        #expect(Character(aCell.character) == "A")
        #expect(Character(bCell.character) == "B")
        #expect(Character(cCell.character) == "C")
    }

    @Test("Insert lines in scroll region")
    func testInsertLinesInScrollRegion() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 4)
        defer { state.deallocate() }

        state.feed(text: "AAAAA\r\nBBBBB\r\nCCCCC\r\nDDDDD")
        state.feed(text: "\(esc)[2;3r")
        state.feed(text: "\(esc)[2;1H")
        state.feed(text: "\(esc)[L")

        TestHarness.assertLineText(state, row: 0, equals: "AAAAA")
        TestHarness.assertLineText(state, row: 1, equals: "")
        TestHarness.assertLineText(state, row: 2, equals: "BBBBB")
        TestHarness.assertLineText(state, row: 3, equals: "DDDDD")
    }

    @Test("Delete lines in scroll region")
    func testDeleteLinesInScrollRegion() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 4)
        defer { state.deallocate() }

        state.feed(text: "AAAAA\r\nBBBBB\r\nCCCCC\r\nDDDDD")
        state.feed(text: "\(esc)[2;3r")
        state.feed(text: "\(esc)[2;1H")
        state.feed(text: "\(esc)[M")

        TestHarness.assertLineText(state, row: 0, equals: "AAAAA")
        TestHarness.assertLineText(state, row: 1, equals: "CCCCC")
        TestHarness.assertLineText(state, row: 2, equals: "")
        TestHarness.assertLineText(state, row: 3, equals: "DDDDD")
    }

    @Test("Cursor save and restore (DECSC/DECRC)")
    func testCursorSaveRestore() {
        var state = TestHarness.makeTerminal(cols: 5, rows: 3)
        defer { state.deallocate() }

        state.feed(text: "\(esc)[2;4H")
        state.feed(text: "\(esc)7")
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)8")

        TestHarness.assertCursor(state, col: 3, row: 1)
    }
}
