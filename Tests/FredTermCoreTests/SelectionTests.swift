import Testing
@testable import FredTermCore

@Suite("Selection Tests")
struct SelectionTests {
    @Test("Empty selection")
    func emptySelection() {
        let sel = Selection()
        #expect(!sel.active)
        #expect(!sel.contains(Position(col: 0, row: 0)))
    }

    @Test("Active selection contains points")
    func activeSelection() {
        let sel = Selection(
            from: Position(col: 2, row: 1),
            to: Position(col: 5, row: 3)
        )
        #expect(sel.active)
        #expect(sel.contains(Position(col: 3, row: 2))) // Inside
        #expect(!sel.contains(Position(col: 1, row: 1))) // Before start col
        #expect(!sel.contains(Position(col: 6, row: 3))) // After end col
        #expect(!sel.contains(Position(col: 0, row: 0))) // Before start row
        #expect(!sel.contains(Position(col: 0, row: 4))) // After end row
    }

    @Test("Selection with reversed start/end")
    func reversedSelection() {
        let sel = Selection(
            from: Position(col: 5, row: 3),
            to: Position(col: 2, row: 1)
        )
        let (s, e) = sel.normalizedRange
        #expect(s == Position(col: 2, row: 1))
        #expect(e == Position(col: 5, row: 3))
    }

    @Test("Block selection")
    func blockSelection() {
        let sel = Selection(
            from: Position(col: 2, row: 1),
            to: Position(col: 5, row: 3),
            mode: .block
        )
        // Inside the block
        #expect(sel.contains(Position(col: 3, row: 2)))
        // Outside the block columns
        #expect(!sel.contains(Position(col: 1, row: 2)))
        #expect(!sel.contains(Position(col: 6, row: 2)))
    }

    @Test("Selection text extraction")
    func textExtraction() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }
        let graphemes = GraphemeTable()

        // Create 3 lines
        for _ in 0..<3 { grid.appendLine() }

        let hello = "Hello"
        for (i, ch) in hello.unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }
        let world = "World"
        for (i, ch) in world.unicodeScalars.enumerated() {
            grid[1, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        let sel = Selection(
            from: Position(col: 0, row: 0),
            to: Position(col: 4, row: 1)
        )

        let text = sel.getText(from: grid, yBase: 0, graphemes: graphemes)
        #expect(text.contains("Hello"))
        #expect(text.contains("World"))
    }

    @Test("Clear selection")
    func clearSelection() {
        var sel = Selection(
            from: Position(col: 0, row: 0),
            to: Position(col: 5, row: 5)
        )
        #expect(sel.active)
        sel.clear()
        #expect(!sel.active)
    }

    @Test("Word boundary detection")
    func wordBoundaries() {
        var grid = CellGrid(cols: 20, maxLines: 5)
        defer { grid.deallocate() }
        grid.appendLine()

        // Write "hello world"
        for (i, ch) in "hello world".unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Click in "world" at col 8
        let (start, end) = Selection.wordBoundaries(
            at: Position(col: 8, row: 0), in: grid, yBase: 0)
        #expect(start.col == 6) // 'w' in "world"
        #expect(end.col == 10)  // 'd' in "world"
    }

    // MARK: - Ported from SwiftTerm

    @Test("Selection ordering with reversed positions")
    func testSelectionOrdering() {
        var grid = CellGrid(cols: 10, maxLines: 10)
        defer { grid.deallocate() }
        for _ in 0..<10 { grid.appendLine() }

        // Write content
        for (i, ch) in "ABCDE".unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Selection from higher to lower position
        let sel = Selection(
            from: Position(col: 5, row: 2),
            to: Position(col: 2, row: 0)
        )

        let (s, e) = sel.normalizedRange
        #expect(s.row == 0)
        #expect(e.row == 2)
    }

    @Test("Selection active state management")
    func testSelectionActiveState() {
        var sel = Selection()
        #expect(!sel.active)

        sel.active = true
        sel.start = Position(col: 0, row: 0)
        sel.end = Position(col: 5, row: 0)
        #expect(sel.active)

        sel.active = false
        #expect(!sel.active)
    }

    @Test("Selection text with newlines across multiple rows")
    func testSelectionTextWithNewlines() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }
        let graphemes = GraphemeTable()

        for _ in 0..<3 { grid.appendLine() }

        for (i, ch) in "AAA".unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }
        for (i, ch) in "BBB".unicodeScalars.enumerated() {
            grid[1, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }
        for (i, ch) in "CCC".unicodeScalars.enumerated() {
            grid[2, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        let sel = Selection(
            from: Position(col: 0, row: 0),
            to: Position(col: 9, row: 2)
        )

        let text = sel.getText(from: grid, yBase: 0, graphemes: graphemes)
        #expect(text.contains("AAA"))
        #expect(text.contains("BBB"))
        #expect(text.contains("CCC"))
    }

    @Test("Word selection at word boundary start")
    func testWordSelectionAtBoundaryStart() {
        var grid = CellGrid(cols: 20, maxLines: 5)
        defer { grid.deallocate() }
        grid.appendLine()

        for (i, ch) in "hello world test".unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Select word at start of "world"
        let (s, e) = Selection.wordBoundaries(
            at: Position(col: 6, row: 0), in: grid, yBase: 0)
        #expect(s.col == 6)
        #expect(e.col == 10)
    }

    @Test("Word selection at word boundary end")
    func testWordSelectionAtBoundaryEnd() {
        var grid = CellGrid(cols: 20, maxLines: 5)
        defer { grid.deallocate() }
        grid.appendLine()

        for (i, ch) in "hello world test".unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Select word at end of "world"
        let (s, e) = Selection.wordBoundaries(
            at: Position(col: 10, row: 0), in: grid, yBase: 0)
        #expect(s.col == 6)
        #expect(e.col == 10)
    }

    @Test("Selection mode persistence")
    func testSelectionModePersistence() {
        var sel = Selection()
        #expect(sel.mode == .character) // Default

        sel.mode = .line
        #expect(sel.mode == .line)

        sel.mode = .word
        #expect(sel.mode == .word)
    }

    @Test("Selection with empty content does not crash")
    func testSelectionWithEmptyContent() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }
        let graphemes = GraphemeTable()

        for _ in 0..<3 { grid.appendLine() }

        let sel = Selection(
            from: Position(col: 0, row: 0),
            to: Position(col: 5, row: 0)
        )

        // Should not crash, text may be empty or spaces
        let text = sel.getText(from: grid, yBase: 0, graphemes: graphemes)
        #expect(text.count >= 0)
    }

    @Test("Multiline selection contains")
    func testMultilineSelectionContains() {
        let sel = Selection(
            from: Position(col: 2, row: 0),
            to: Position(col: 7, row: 2)
        )

        // Should contain points in between
        #expect(sel.contains(Position(col: 0, row: 1))) // Full line 1
        #expect(sel.contains(Position(col: 9, row: 1))) // Full line 1
        #expect(!sel.contains(Position(col: 1, row: 0))) // Before start col on start row
        #expect(sel.contains(Position(col: 3, row: 0))) // After start col on start row
        #expect(sel.contains(Position(col: 5, row: 2))) // Before end col on end row
        #expect(!sel.contains(Position(col: 8, row: 2))) // After end col on end row
    }

    @Test("Wide character in selection text")
    func testWideCharacterSelection() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }
        let graphemes = GraphemeTable()

        grid.appendLine()
        // Write "Aあx"
        grid[0, 0] = Cell(codePoint: 0x41, attribute: 0, width: 1, flags: [], payload: 0) // A
        grid[0, 1] = Cell(codePoint: 0x3042, attribute: 0, width: 2, flags: [], payload: 0) // あ
        grid[0, 2] = Cell(codePoint: 0, attribute: 0, width: 0, flags: .wideContinuation, payload: 0)
        grid[0, 3] = Cell(codePoint: 0x78, attribute: 0, width: 1, flags: [], payload: 0) // x

        let sel = Selection(from: Position(col: 0, row: 0), to: Position(col: 3, row: 0))
        let text = sel.getText(from: grid, yBase: 0, graphemes: graphemes)
        #expect(text.contains("A"))
        #expect(text.contains("あ"))
        #expect(text.contains("x"))
    }
}
