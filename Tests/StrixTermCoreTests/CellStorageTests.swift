import Testing
@testable import StrixTermCore

@Suite("CellGrid Tests")
struct CellStorageTests {
    @Test("Cell is 16 bytes")
    func cellSize() {
        #expect(MemoryLayout<Cell>.size == 16)
        #expect(MemoryLayout<Cell>.stride == 16)
    }

    @Test("CellGrid initializes with blank cells")
    func gridInit() {
        var grid = CellGrid(cols: 80, maxLines: 100)
        defer { grid.deallocate() }

        grid.appendLine()
        let cell = grid[0, 0]
        #expect(cell.codePoint == 0x20)
        #expect(cell.isBlank)
        #expect(cell.width == 1)
    }

    @Test("CellGrid subscript read/write")
    func gridReadWrite() {
        var grid = CellGrid(cols: 80, maxLines: 100)
        defer { grid.deallocate() }

        grid.appendLine()
        var cell = Cell.blank
        cell.codePoint = 0x41 // 'A'
        cell.attribute = 1
        grid[0, 5] = cell

        let read = grid[0, 5]
        #expect(read.codePoint == 0x41)
        #expect(read.attribute == 1)
    }

    @Test("CellGrid appendLine grows count")
    func gridAppendLine() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        for _ in 0..<3 {
            grid.appendLine()
        }
        #expect(grid.count == 3)
    }

    @Test("CellGrid ring wraps correctly")
    func gridRingWrap() {
        var grid = CellGrid(cols: 5, maxLines: 3)
        defer { grid.deallocate() }

        // Fill 3 lines
        for i in 0..<3 {
            grid.appendLine()
            grid[i, 0] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }
        #expect(grid.count == 3)
        #expect(grid[0, 0].codePoint == 0x41) // 'A'
        #expect(grid[1, 0].codePoint == 0x42) // 'B'
        #expect(grid[2, 0].codePoint == 0x43) // 'C'

        // Append one more, should evict 'A'
        let evicted = grid.appendLine()
        #expect(evicted)
        grid[2, 0] = Cell(codePoint: 0x44, attribute: 0, width: 1, flags: [], payload: 0) // 'D'

        // Oldest should now be 'B'
        #expect(grid[0, 0].codePoint == 0x42) // 'B'
        #expect(grid[1, 0].codePoint == 0x43) // 'C'
        #expect(grid[2, 0].codePoint == 0x44) // 'D'
    }

    @Test("CellGrid clearLine")
    func gridClearLine() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        grid[0, 3] = Cell(codePoint: 0x58, attribute: 0, width: 1, flags: [], payload: 0)
        #expect(grid[0, 3].codePoint == 0x58)

        grid.clearLine(0)
        #expect(grid[0, 3].codePoint == 0x20)
    }

    @Test("CellGrid scrollRegionUp")
    func gridScrollUp() {
        var grid = CellGrid(cols: 5, maxLines: 10)
        defer { grid.deallocate() }

        // Create 5 lines with distinct content
        for i in 0..<5 {
            grid.appendLine()
            grid[i, 0] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Scroll lines 1-3 up by 1
        grid.scrollRegionUp(top: 1, bottom: 4, count: 1)

        #expect(grid[0, 0].codePoint == 0x41) // 'A' unchanged
        #expect(grid[1, 0].codePoint == 0x43) // Was 'C' (shifted up from row 2)
        #expect(grid[2, 0].codePoint == 0x44) // Was 'D'
        #expect(grid[3, 0].isBlank)           // New blank line
        #expect(grid[4, 0].codePoint == 0x45) // 'E' unchanged
    }

    @Test("CellGrid insertCells")
    func gridInsertCells() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        // Write "ABCDE" at positions 0-4
        for i in 0..<5 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Insert 2 cells at position 2
        grid.insertCells(line: 0, at: 2, count: 2, rightMargin: 10)

        #expect(grid[0, 0].codePoint == 0x41) // 'A'
        #expect(grid[0, 1].codePoint == 0x42) // 'B'
        #expect(grid[0, 2].isBlank)           // Inserted blank
        #expect(grid[0, 3].isBlank)           // Inserted blank
        #expect(grid[0, 4].codePoint == 0x43) // 'C' shifted right
        #expect(grid[0, 5].codePoint == 0x44) // 'D' shifted right
    }

    @Test("CellGrid deleteCells")
    func gridDeleteCells() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        for i in 0..<5 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Delete 2 cells at position 1
        grid.deleteCells(line: 0, at: 1, count: 2, rightMargin: 10)

        #expect(grid[0, 0].codePoint == 0x41) // 'A'
        #expect(grid[0, 1].codePoint == 0x44) // 'D' shifted left
        #expect(grid[0, 2].codePoint == 0x45) // 'E' shifted left
        #expect(grid[0, 3].isBlank)           // Filled blank
    }

    @Test("CellGrid lineText")
    func gridLineText() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        let hello = "Hello"
        for (i, ch) in hello.unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        #expect(grid.lineText(0) == "Hello")
        #expect(grid.lineText(0, trimTrailing: false) == "Hello     ")
    }

    @Test("LineMetadata defaults")
    func lineMetadata() {
        let meta = LineMetadata.blank
        #expect(!meta.isWrapped)
        #expect(meta.renderMode == .normal)
        #expect(!meta.hasImages)
        #expect(meta.promptZone == .none)
    }
}

@Suite("AttributeTable Tests")
struct AttributeTableTests {
    @Test("Default attribute at index 0")
    func defaultAttribute() {
        let table = AttributeTable()
        let attr = table[0]
        #expect(attr.fg == .default)
        #expect(attr.bg == .default)
        #expect(attr.style.isEmpty)
    }

    @Test("Interning returns consistent indices")
    func interning() {
        var table = AttributeTable()
        let bold = AttributeEntry(style: .bold)
        let idx1 = table.intern(bold)
        let idx2 = table.intern(bold)
        #expect(idx1 == idx2)
        #expect(table.count == 2) // default + bold
    }

    @Test("Different attributes get different indices")
    func uniqueAttributes() {
        var table = AttributeTable()
        let bold = AttributeEntry(style: .bold)
        let italic = AttributeEntry(style: .italic)
        let idx1 = table.intern(bold)
        let idx2 = table.intern(italic)
        #expect(idx1 != idx2)
    }
}

@Suite("GraphemeTable Tests")
struct GraphemeTableTests {
    @Test("Insert and lookup")
    func insertLookup() {
        var table = GraphemeTable()
        let encoded = table.insert("e\u{0301}") // e + combining acute
        #expect(GraphemeTable.isGraphemeRef(encoded))
        #expect(table.lookup(encoded) == "e\u{0301}")
    }

    @Test("Release and reuse")
    func releaseReuse() {
        var table = GraphemeTable()
        let e1 = table.insert("abc")
        table.release(e1)
        let e2 = table.insert("xyz")
        // Should reuse the released slot
        #expect(table.count == 1)
        #expect(table.lookup(e2) == "xyz")
    }

    @Test("Threshold check")
    func threshold() {
        #expect(!GraphemeTable.isGraphemeRef(0x41))      // 'A' is not a ref
        #expect(!GraphemeTable.isGraphemeRef(0x10FFFF))   // Last valid Unicode
        #expect(GraphemeTable.isGraphemeRef(0x110000))     // First ref value
    }
}

@Suite("TabStops Tests")
struct TabStopsTests {
    @Test("Default tab stops every 8 columns")
    func defaultStops() {
        let tabs = TabStops(width: 80)
        #expect(!tabs.isSet(0))
        #expect(tabs.isSet(8))
        #expect(tabs.isSet(16))
        #expect(tabs.isSet(24))
        #expect(!tabs.isSet(7))
    }

    @Test("Next tab stop")
    func nextStop() {
        let tabs = TabStops(width: 80)
        #expect(tabs.nextStop(after: 0) == 8)
        #expect(tabs.nextStop(after: 7) == 8)
        #expect(tabs.nextStop(after: 8) == 16)
    }

    @Test("Clear and set")
    func clearSet() {
        var tabs = TabStops(width: 80)
        tabs.clear(8)
        #expect(!tabs.isSet(8))
        #expect(tabs.nextStop(after: 0) == 16)

        tabs.set(4)
        #expect(tabs.isSet(4))
        #expect(tabs.nextStop(after: 0) == 4)
    }

    @Test("Clear all")
    func clearAll() {
        var tabs = TabStops(width: 80)
        tabs.clearAll()
        #expect(tabs.nextStop(after: 0) == 79) // Falls through to width-1
    }
}

// MARK: - CSI Parameter Parsing Tests
// Port of SwiftTerm's CsiParameterParsingTests: tests that CSI sequences correctly
// parse their numeric parameters and drive the expected terminal behaviour.

@Suite("CSI Parameter Parsing Tests")
struct CsiParameterParsingTests {
    private let esc = "\u{1b}"

    // MARK: - CUU (Cursor Up) -- ESC [ Ps A

    @Test("CUU default param")
    func testCursorUpDefaultParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[10;1H")   // row 10, col 1
        state.feed(text: "\(esc)[A")        // default = 1
        TestHarness.assertCursor(state, col: 0, row: 8) // 10-1-1 = 8
    }

    @Test("CUU explicit param")
    func testCursorUpExplicitParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[10;1H")
        state.feed(text: "\(esc)[4A")       // up 4
        TestHarness.assertCursor(state, col: 0, row: 5) // 10-1-4 = 5
    }

    @Test("CUU clamped to top")
    func testCursorUpClampedToTop() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[3;1H")     // row 3
        state.feed(text: "\(esc)[99A")      // way past top
        TestHarness.assertCursor(state, col: 0, row: 0)
    }

    // MARK: - CUD (Cursor Down) -- ESC [ Ps B

    @Test("CUD default param")
    func testCursorDownDefaultParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[B")        // default = 1
        TestHarness.assertCursor(state, col: 0, row: 1)
    }

    @Test("CUD explicit param")
    func testCursorDownExplicitParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[7B")       // down 7
        TestHarness.assertCursor(state, col: 0, row: 7)
    }

    @Test("CUD clamped to bottom")
    func testCursorDownClampedToBottom() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[999B")
        TestHarness.assertCursor(state, col: 0, row: 23)
    }

    // MARK: - CUF (Cursor Forward) -- ESC [ Ps C

    @Test("CUF default param")
    func testCursorForwardDefaultParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[C")        // default = 1
        TestHarness.assertCursor(state, col: 1, row: 0)
    }

    @Test("CUF explicit param")
    func testCursorForwardExplicitParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[15C")
        TestHarness.assertCursor(state, col: 15, row: 0)
    }

    @Test("CUF clamped to right")
    func testCursorForwardClampedToRight() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[500C")
        TestHarness.assertCursor(state, col: 79, row: 0)
    }

    // MARK: - CUB (Cursor Backward) -- ESC [ Ps D

    @Test("CUB default param")
    func testCursorBackwardDefaultParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;20H")    // col 20
        state.feed(text: "\(esc)[D")        // default = 1
        TestHarness.assertCursor(state, col: 18, row: 0)
    }

    @Test("CUB explicit param")
    func testCursorBackwardExplicitParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;20H")
        state.feed(text: "\(esc)[5D")
        TestHarness.assertCursor(state, col: 14, row: 0)
    }

    @Test("CUB clamped to left")
    func testCursorBackwardClampedToLeft() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[1;5H")
        state.feed(text: "\(esc)[999D")
        TestHarness.assertCursor(state, col: 0, row: 0)
    }

    // MARK: - CUP (Cursor Position) -- ESC [ Ps ; Ps H

    @Test("CUP both params")
    func testCursorPositionBothParams() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[12;34H")
        TestHarness.assertCursor(state, col: 33, row: 11)
    }

    @Test("CUP row only")
    func testCursorPositionRowOnly() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[8H")       // only row, col defaults to 1
        TestHarness.assertCursor(state, col: 0, row: 7)
    }

    @Test("CUP no params")
    func testCursorPositionNoParams() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[5;10H")    // move away first
        state.feed(text: "\(esc)[H")        // home
        TestHarness.assertCursor(state, col: 0, row: 0)
    }

    @Test("CUP zero params treated as 1")
    func testCursorPositionZeroParamsTreatedAsOne() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[0;0H")     // 0 -> treated as 1
        TestHarness.assertCursor(state, col: 0, row: 0)
    }

    // MARK: - EL (Erase In Line) -- ESC [ Ps K

    @Test("EL 0 - erase from cursor to end")
    func testEraseInLineFromCursorToEnd() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;4H")     // col 4
        state.feed(text: "\(esc)[0K")       // erase from cursor to end
        TestHarness.assertLineText(state, row: 0, equals: "ABC")
    }

    @Test("EL 1 - erase from start to cursor")
    func testEraseInLineFromStartToCursor() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;4H")     // col 4 (0-based: 3)
        state.feed(text: "\(esc)[1K")       // erase from start to cursor
        TestHarness.assertLineText(state, row: 0, equals: "    EFGHIJ")
    }

    @Test("EL 2 - erase entire line")
    func testEraseInLineEntire() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[2K")       // erase entire line
        TestHarness.assertLineText(state, row: 0, equals: "")
    }

    @Test("EL default param")
    func testEraseInLineDefaultParam() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;4H")
        state.feed(text: "\(esc)[K")        // no param -> same as 0
        TestHarness.assertLineText(state, row: 0, equals: "ABC")
    }

    // MARK: - ECH (Erase Characters) -- ESC [ Ps X

    @Test("ECH default")
    func testEraseCharsDefault() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[X")        // default = 1, erase 1 char
        TestHarness.assertLineText(state, row: 0, equals: " BCDEFGHIJ")
    }

    @Test("ECH explicit")
    func testEraseCharsExplicit() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;1H")
        state.feed(text: "\(esc)[5X")       // erase 5 chars
        TestHarness.assertLineText(state, row: 0, equals: "     FGHIJ")
    }

    // MARK: - REP (Repeat Preceding Character) -- ESC [ Ps b

    @Test("REP default")
    func testRepeatCharDefault() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "X")               // preceding char
        state.feed(text: "\(esc)[b")        // default = 1
        TestHarness.assertLineText(state, row: 0, equals: "XX")
    }

    @Test("REP explicit")
    func testRepeatCharExplicit() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "Z")
        state.feed(text: "\(esc)[4b")       // repeat 4 times
        TestHarness.assertLineText(state, row: 0, equals: "ZZZZZ")
    }

    // MARK: - DECSTBM (Set Scroll Region) -- ESC [ Ps ; Ps r

    @Test("DECSTBM both params")
    func testSetScrollRegionBothParams() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[5;20r")    // top=5, bottom=20
        #expect(state.buffer.scrollTop == 4)    // 1-based -> 0-based
        #expect(state.buffer.scrollBottom == 19)
    }

    @Test("DECSTBM no params resets")
    func testSetScrollRegionNoParams() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[5;20r")    // set first
        state.feed(text: "\(esc)[r")        // reset to full screen
        #expect(state.buffer.scrollTop == 0)
        #expect(state.buffer.scrollBottom == 23)
    }

    // MARK: - ICH (Insert Characters) -- ESC [ Ps @

    @Test("ICH default")
    func testInsertCharsDefault() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;3H")     // col 3 (0-based: 2)
        state.feed(text: "\(esc)[@")        // default = 1 blank inserted
        TestHarness.assertLineText(state, row: 0, equals: "AB CDEFGHI")
    }

    @Test("ICH explicit")
    func testInsertCharsExplicit() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;3H")
        state.feed(text: "\(esc)[3@")       // insert 3 blanks
        TestHarness.assertLineText(state, row: 0, equals: "AB   CDEFG")
    }

    // MARK: - DCH (Delete Characters) -- ESC [ Ps P

    @Test("DCH default")
    func testDeleteCharsDefault() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;3H")     // col 3 (0-based: 2)
        state.feed(text: "\(esc)[P")        // default = 1
        TestHarness.assertLineText(state, row: 0, equals: "ABDEFGHIJ")
    }

    @Test("DCH explicit")
    func testDeleteCharsExplicit() {
        var state = TestHarness.makeTerminal(cols: 10, rows: 1)
        defer { state.deallocate() }
        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\(esc)[1;3H")
        state.feed(text: "\(esc)[4P")       // delete 4
        TestHarness.assertLineText(state, row: 0, equals: "ABGHIJ")
    }

    // MARK: - Multi-digit and multi-parameter parsing

    @Test("Multi-digit param")
    func testMultiDigitParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 50)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[42;17H")   // row 42, col 17
        TestHarness.assertCursor(state, col: 16, row: 41)
    }

    @Test("Large param")
    func testLargeParam() {
        var state = TestHarness.makeTerminal(cols: 200, rows: 100)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[100;150H")
        TestHarness.assertCursor(state, col: 149, row: 99)
    }

    @Test("Zero param treated as default")
    func testZeroParamTreatedAsDefault() {
        // For most CSI commands, 0 is treated the same as 1 (the default)
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[5;5H")     // start at row 5, col 5
        state.feed(text: "\(esc)[0A")       // CUU with 0 -> treated as 1
        TestHarness.assertCursor(state, col: 4, row: 3)
    }

    @Test("Semicolon-only params default to zero")
    func testSemicolonOnlyParamsDefaultToZero() {
        // ESC [ ; H -- both params default to 0, treated as 1;1
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }
        state.feed(text: "\(esc)[10;10H")
        state.feed(text: "\(esc)[;H")
        TestHarness.assertCursor(state, col: 0, row: 0)
    }
}
