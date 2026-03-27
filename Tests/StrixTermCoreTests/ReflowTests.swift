import Testing
@testable import StrixTermCore

@Suite("Reflow Tests")
struct ReflowTests {
    @Test("Reflow narrowing wraps lines")
    func reflowNarrow() {
        var grid = CellGrid(cols: 10, maxLines: 20)
        defer { grid.deallocate() }

        // Create a line "ABCDEFGHIJ" (exactly 10 cols)
        grid.appendLine()
        for i in 0..<10 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        var cursorX = 9
        var cursorY = 0
        var yBase = 0
        var yDisp = 0

        ReflowEngine.reflow(
            grid: &grid, oldCols: 10, newCols: 5, newMaxLines: 20,
            cursorX: &cursorX, cursorY: &cursorY, yBase: &yBase, yDisp: &yDisp)

        // Should now be 2 physical lines
        #expect(grid.count == 2)
        // First line should be wrapped
        #expect(grid[lineMetadata: 0].isWrapped)
        // First 5 chars on line 0
        #expect(grid[0, 0].codePoint == 0x41) // A
        #expect(grid[0, 4].codePoint == 0x45) // E
        // Next 5 chars on line 1
        #expect(grid[1, 0].codePoint == 0x46) // F
        #expect(grid[1, 4].codePoint == 0x4A) // J
    }

    @Test("Reflow widening unwraps lines")
    func reflowWiden() {
        var grid = CellGrid(cols: 5, maxLines: 20)
        defer { grid.deallocate() }

        // Create two wrapped lines: "ABCDE" + "FGHIJ"
        grid.appendLine()
        for i in 0..<5 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }
        grid[lineMetadata: 0] = LineMetadata(isWrapped: true)

        grid.appendLine()
        for i in 0..<5 {
            grid[1, i] = Cell(codePoint: UInt32(0x46 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        var cursorX = 4
        var cursorY = 1
        var yBase = 0
        var yDisp = 0

        ReflowEngine.reflow(
            grid: &grid, oldCols: 5, newCols: 10, newMaxLines: 20,
            cursorX: &cursorX, cursorY: &cursorY, yBase: &yBase, yDisp: &yDisp)

        // Should now be 1 physical line with all 10 chars
        #expect(grid.count == 1)
        #expect(!grid[lineMetadata: 0].isWrapped)
        #expect(grid[0, 0].codePoint == 0x41) // A
        #expect(grid[0, 9].codePoint == 0x4A) // J
    }

    @Test("Reflow preserves hard line breaks")
    func reflowHardBreaks() {
        var grid = CellGrid(cols: 10, maxLines: 20)
        defer { grid.deallocate() }

        // Two separate (non-wrapped) lines
        grid.appendLine()
        for i in 0..<3 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }
        // Not wrapped (hard break)

        grid.appendLine()
        for i in 0..<3 {
            grid[1, i] = Cell(codePoint: UInt32(0x58 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        var cursorX = 2
        var cursorY = 1
        var yBase = 0
        var yDisp = 0

        ReflowEngine.reflow(
            grid: &grid, oldCols: 10, newCols: 5, newMaxLines: 20,
            cursorX: &cursorX, cursorY: &cursorY, yBase: &yBase, yDisp: &yDisp)

        // Should still be 2 lines (hard break preserved)
        #expect(grid.count == 2)
        #expect(!grid[lineMetadata: 0].isWrapped)
        #expect(grid[0, 0].codePoint == 0x41) // A
        #expect(grid[1, 0].codePoint == 0x58) // X
    }

    @Test("Reflow same width is no-op")
    func reflowSameWidth() {
        var grid = CellGrid(cols: 10, maxLines: 20)
        defer { grid.deallocate() }

        grid.appendLine()
        grid[0, 0] = Cell(codePoint: 0x41, attribute: 0, width: 1, flags: [], payload: 0)

        var cursorX = 1
        var cursorY = 0
        var yBase = 0
        var yDisp = 0

        ReflowEngine.reflow(
            grid: &grid, oldCols: 10, newCols: 10, newMaxLines: 20,
            cursorX: &cursorX, cursorY: &cursorY, yBase: &yBase, yDisp: &yDisp)

        // Nothing should change
        #expect(grid[0, 0].codePoint == 0x41)
        #expect(cursorX == 1)
    }
}
