/// Reflow engine that operates on the contiguous CellGrid.
///
/// Because storage is flat, reflow can be done as bulk memory operations
/// rather than per-BufferLine object manipulation. This fixes issue #494
/// (duplicate/orphan lines on narrowing) by tracking logical line boundaries
/// correctly through a single forward pass.
public struct ReflowEngine {
    /// Reflow a grid from oldCols to newCols.
    /// Returns adjusted cursor and scroll positions.
    public static func reflow(
        grid: inout CellGrid,
        oldCols: Int,
        newCols: Int,
        newMaxLines: Int,
        cursorX: inout Int,
        cursorY: inout Int,
        yBase: inout Int,
        yDisp: inout Int
    ) {
        guard oldCols != newCols && grid.count > 0 else { return }

        // Phase 1: Collect all logical lines (unwrapping soft wraps)
        var logicalLines: [LogicalLine] = []
        var currentLogical = LogicalLine()
        let cursorAbsLine = yBase + cursorY

        for lineIdx in 0..<grid.count {
            let meta = grid[lineMetadata: lineIdx]

            // Collect cells from this physical line
            var lastNonBlank = -1
            for col in 0..<oldCols {
                let cell = grid[lineIdx, col]
                if !cell.isBlank || cell.flags.contains(.wideContinuation) {
                    lastNonBlank = col
                }
            }

            let cellCount = lastNonBlank + 1
            for col in 0..<max(cellCount, 0) {
                currentLogical.cells.append(grid[lineIdx, col])
            }

            // Track cursor position within logical lines
            if lineIdx == cursorAbsLine {
                currentLogical.cursorOffset = currentLogical.cells.count - cellCount + cursorX
                currentLogical.hasCursor = true
            }

            // If not wrapped, this is the end of a logical line
            if !meta.isWrapped || lineIdx == grid.count - 1 {
                currentLogical.promptZone = meta.promptZone
                currentLogical.renderMode = meta.renderMode
                logicalLines.append(currentLogical)
                currentLogical = LogicalLine()
            }
        }

        // Phase 2: Re-wrap logical lines at the new column width
        var newGrid = CellGrid(cols: newCols, maxLines: newMaxLines)
        var newCursorX = cursorX
        var newCursorY = 0
        var newYBase = 0
        var totalPhysLines = 0

        for logical in logicalLines {
            let physLines = rewrapLogicalLine(
                logical, into: &newGrid, cols: newCols)

            if logical.hasCursor {
                // Find where the cursor ended up
                let cursorPhysLine = logical.cursorOffset / newCols
                newCursorX = logical.cursorOffset % newCols
                newCursorY = totalPhysLines + cursorPhysLine
            }

            totalPhysLines += physLines
        }

        // Phase 3: Calculate new yBase and yDisp
        let visibleRows = min(totalPhysLines, newGrid.maxLines)
        newYBase = max(0, totalPhysLines - visibleRows)

        // Adjust cursor to be relative to yBase
        newCursorY = max(0, newCursorY - newYBase)

        // Replace the old grid
        grid.deallocate()
        grid = newGrid
        cursorX = min(newCursorX, newCols - 1)
        cursorY = min(newCursorY, visibleRows - 1)
        yBase = newYBase
        yDisp = newYBase
    }

    /// Re-wrap a logical line into the grid at the given column width.
    /// Returns the number of physical lines written.
    private static func rewrapLogicalLine(
        _ logical: LogicalLine, into grid: inout CellGrid, cols: Int
    ) -> Int {
        if logical.cells.isEmpty {
            grid.appendLine()
            return 1
        }

        var physLines = 0
        var cellIdx = 0

        while cellIdx < logical.cells.count {
            grid.appendLine()
            physLines += 1

            // Fill this physical line
            var col = 0
            while col < cols && cellIdx < logical.cells.count {
                let cell = logical.cells[cellIdx]
                let width = Int(cell.width)

                // If a wide char doesn't fit at the end of the line, wrap
                if width == 2 && col + 1 >= cols {
                    break
                }

                grid[grid.count - 1, col] = cell
                col += 1
                cellIdx += 1

                // Copy continuation cell for wide chars
                if width == 2 && cellIdx < logical.cells.count {
                    grid[grid.count - 1, col] = logical.cells[cellIdx]
                    col += 1
                    cellIdx += 1
                }
            }

            // Set wrap flag if there's more content
            if cellIdx < logical.cells.count {
                grid[lineMetadata: grid.count - 1] = LineMetadata(
                    isWrapped: true,
                    renderMode: logical.renderMode,
                    promptZone: logical.promptZone
                )
            } else {
                grid[lineMetadata: grid.count - 1] = LineMetadata(
                    isWrapped: false,
                    renderMode: logical.renderMode,
                    promptZone: logical.promptZone
                )
            }
        }

        return physLines
    }
}

/// A logical line: the unwrapped content of one or more physical lines
/// that were connected by soft wraps.
private struct LogicalLine {
    var cells: [Cell] = []
    var cursorOffset: Int = 0
    var hasCursor: Bool = false
    var promptZone: PromptZone = .none
    var renderMode: RenderLineMode = .normal
}
