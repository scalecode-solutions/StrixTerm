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
}
