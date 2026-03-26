/// Saved cursor state for DECSC/DECRC.
public struct SavedCursorState: Sendable {
    public var x: Int = 0
    public var y: Int = 0
    public var attribute: UInt32 = 0
    public var originMode: Bool = false
    public var wraparound: Bool = true
    public var charset: Int = 0
}

/// Per-buffer state (normal or alternate screen), owns a CellGrid.
public struct BufferState: @unchecked Sendable {
    public var grid: CellGrid
    public var cursorX: Int = 0
    public var cursorY: Int = 0
    public var scrollTop: Int = 0
    public var scrollBottom: Int
    public var marginLeft: Int = 0
    public var marginRight: Int
    public var yBase: Int = 0
    public var yDisp: Int = 0
    public var savedCursor: SavedCursorState = SavedCursorState()
    public var tabStops: TabStops
    public var linesTop: Int = 0
    public var hasScrollback: Bool

    public init(cols: Int, rows: Int, maxScrollback: Int, hasScrollback: Bool) {
        self.hasScrollback = hasScrollback
        let totalLines = rows + (hasScrollback ? maxScrollback : 0)
        grid = CellGrid(cols: cols, maxLines: totalLines)
        scrollBottom = rows - 1
        marginRight = cols - 1
        tabStops = TabStops(width: cols)

        // Initialize visible rows
        for _ in 0..<rows {
            grid.appendLine()
        }
    }

    /// The number of visible rows.
    public var rows: Int {
        scrollBottom + 1
    }

    /// The number of columns.
    public var cols: Int {
        grid.cols
    }

    // MARK: - Cursor movement

    /// Clamp cursor to valid range within the active margins.
    public mutating func clampCursor(modes: TerminalModes) {
        let top = modes.originMode ? scrollTop : 0
        let bottom = modes.originMode ? scrollBottom : (rows - 1)
        let left = modes.marginMode ? marginLeft : 0
        let right = modes.marginMode ? marginRight : (cols - 1)

        cursorX = max(left, min(right, cursorX))
        cursorY = max(top, min(bottom, cursorY))
    }

    /// The absolute line index for the cursor (accounting for yBase).
    public var absoluteCursorY: Int {
        yBase + cursorY
    }

    // MARK: - Character insertion (hot path)

    /// Insert a character at the current cursor position.
    /// This is the most performance-critical method in the terminal.
    @inline(__always)
    public mutating func insertCharacter(
        _ cell: Cell,
        modes: TerminalModes
    ) {
        let width = Int(cell.width)
        let lineIdx = yBase + cursorY
        let rightLimit = modes.marginMode ? marginRight + 1 : cols

        // Handle autowrap
        if cursorX >= rightLimit {
            if modes.wraparound {
                // Mark current line as wrapped
                grid[lineMetadata: lineIdx] = {
                    var m = grid[lineMetadata: lineIdx]
                    m.isWrapped = true
                    return m
                }()
                cursorX = modes.marginMode ? marginLeft : 0
                linefeed(modes: modes)
            } else {
                cursorX = rightLimit - 1
            }
        }

        let newLineIdx = yBase + cursorY

        // Insert mode: shift existing cells right
        if modes.insertMode {
            grid.insertCells(
                line: newLineIdx, at: cursorX, count: width,
                rightMargin: rightLimit, fillAttribute: cell.attribute)
        }

        // Write the cell
        grid[newLineIdx, cursorX] = cell

        // For wide characters, write a continuation cell
        if width == 2 && cursorX + 1 < cols {
            var cont = Cell.blank
            cont.attribute = cell.attribute
            cont.flags = .wideContinuation
            cont.width = 0
            grid[newLineIdx, cursorX + 1] = cont
        }

        cursorX += width
    }

    // MARK: - Scrolling

    /// Perform a linefeed: move cursor down, scrolling if needed.
    public mutating func linefeed(
        modes: TerminalModes
    ) {
        if cursorY == scrollBottom {
            scroll(up: 1, modes: modes)
        } else if cursorY < rows - 1 {
            cursorY += 1
        }
    }

    /// Scroll the scroll region up by `n` lines.
    public mutating func scroll(
        up n: Int,
        modes: TerminalModes
    ) {
        if hasScrollback && scrollTop == 0 && !modes.marginMode {
            // Add lines to scrollback
            for _ in 0..<n {
                grid.appendLine()
                yBase += 1
                yDisp += 1
                linesTop += 1
            }
        } else {
            // Scroll within the region
            let bottom = scrollBottom + yBase + 1
            let top = scrollTop + yBase
            grid.scrollRegionUp(top: top, bottom: bottom, count: n)
        }
    }

    /// Scroll the scroll region down by `n` lines.
    public mutating func scrollDown(
        _ n: Int,
        modes: TerminalModes
    ) {
        let bottom = scrollBottom + yBase + 1
        let top = scrollTop + yBase
        grid.scrollRegionDown(top: top, bottom: bottom, count: n)
    }

    /// Reverse index: scroll down if cursor is at scrollTop.
    public mutating func reverseIndex(
        modes: TerminalModes
    ) {
        if cursorY == scrollTop {
            scrollDown(1, modes: modes)
        } else if cursorY > 0 {
            cursorY -= 1
        }
    }

    // MARK: - Erase operations

    /// Erase in display.
    public mutating func eraseInDisplay(
        mode: Int,
        fillAttribute: UInt32
    ) {
        switch mode {
        case 0: // Erase below
            // Clear from cursor to end of current line
            grid.clearCells(
                line: absoluteCursorY, from: cursorX, to: cols,
                fillAttribute: fillAttribute)
            // Clear all lines below
            for line in (cursorY + 1)..<rows {
                grid.clearLine(yBase + line, fillAttribute: fillAttribute)
            }
        case 1: // Erase above
            // Clear from beginning of current line to cursor
            grid.clearCells(
                line: absoluteCursorY, from: 0, to: cursorX + 1,
                fillAttribute: fillAttribute)
            // Clear all lines above
            for line in 0..<cursorY {
                grid.clearLine(yBase + line, fillAttribute: fillAttribute)
            }
        case 2: // Erase all
            for line in 0..<rows {
                grid.clearLine(yBase + line, fillAttribute: fillAttribute)
            }
        case 3: // Erase scrollback
            yBase = 0
            yDisp = 0
            linesTop = 0
        default:
            break
        }
    }

    /// Erase in line.
    public mutating func eraseInLine(
        mode: Int,
        fillAttribute: UInt32
    ) {
        switch mode {
        case 0: // Erase to right
            grid.clearCells(
                line: absoluteCursorY, from: cursorX, to: cols,
                fillAttribute: fillAttribute)
        case 1: // Erase to left
            grid.clearCells(
                line: absoluteCursorY, from: 0, to: cursorX + 1,
                fillAttribute: fillAttribute)
        case 2: // Erase entire line
            grid.clearLine(absoluteCursorY, fillAttribute: fillAttribute)
        default:
            break
        }
    }

    // MARK: - Save/Restore cursor

    public mutating func saveCursor(attribute: UInt32, modes: TerminalModes) {
        savedCursor = SavedCursorState(
            x: cursorX,
            y: cursorY,
            attribute: attribute,
            originMode: modes.originMode,
            wraparound: modes.wraparound
        )
    }

    public func restoreCursor() -> SavedCursorState {
        return savedCursor
    }

    // MARK: - Deallocation

    public mutating func deallocate() {
        grid.deallocate()
    }
}
