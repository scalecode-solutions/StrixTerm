/// Text selection state and modes.
public struct Selection: Sendable {
    public var active: Bool = false
    public var start: Position = Position(col: 0, row: 0)
    public var end: Position = Position(col: 0, row: 0)
    public var mode: SelectionMode = .character

    /// Selection mode determines how selection extends.
    public enum SelectionMode: Sendable {
        /// Character-by-character selection (single click + drag).
        case character
        /// Word selection (double-click).
        case word
        /// Line selection (triple-click, addresses issue #282).
        case line
        /// Block/rectangular selection (Alt+drag).
        case block
    }

    public init() {}

    /// Create an active selection between two positions.
    public init(from start: Position, to end: Position, mode: SelectionMode = .character) {
        self.active = true
        self.start = start
        self.end = end
        self.mode = mode
    }

    /// The normalized range (start <= end).
    public var normalizedRange: (start: Position, end: Position) {
        if start <= end {
            return (start, end)
        }
        return (end, start)
    }

    /// Check if a position is within the selection.
    public func contains(_ position: Position) -> Bool {
        guard active else { return false }
        let (s, e) = normalizedRange

        if mode == .block {
            let minCol = min(s.col, e.col)
            let maxCol = max(s.col, e.col)
            return position.row >= s.row && position.row <= e.row &&
                   position.col >= minCol && position.col <= maxCol
        }

        if position.row < s.row || position.row > e.row { return false }
        if position.row == s.row && position.col < s.col { return false }
        if position.row == e.row && position.col > e.col { return false }
        return true
    }

    /// Extract selected text from a CellGrid.
    /// When `preserveTabs` is true, cells marked with `.isTab` are emitted as
    /// tab characters instead of spaces (addresses issue #60).
    public func getText(
        from grid: CellGrid, yBase: Int, graphemes: GraphemeTable,
        preserveTabs: Bool = true
    ) -> String {
        guard active else { return "" }
        let (s, e) = normalizedRange
        var result = ""

        for row in s.row...e.row {
            let lineIdx = yBase + row
            let startCol = (row == s.row) ? s.col : 0
            let endCol = (row == e.row) ? e.col : grid.cols - 1

            if mode == .block {
                let minCol = min(s.col, e.col)
                let maxCol = max(s.col, e.col)
                result += extractLineText(
                    grid: grid, lineIdx: lineIdx, from: minCol, to: maxCol,
                    graphemes: graphemes, preserveTabs: preserveTabs)
            } else {
                result += extractLineText(
                    grid: grid, lineIdx: lineIdx, from: startCol, to: endCol,
                    graphemes: graphemes, preserveTabs: preserveTabs)
            }

            // Add newline between rows (but not for wrapped lines in non-block mode)
            if row < e.row {
                if mode == .block || !grid[lineMetadata: lineIdx].isWrapped {
                    result += "\n"
                }
            }
        }

        return result
    }

    private func extractLineText(
        grid: CellGrid, lineIdx: Int, from startCol: Int, to endCol: Int,
        graphemes: GraphemeTable, preserveTabs: Bool
    ) -> String {
        var text = ""
        var col = startCol
        while col <= endCol && col < grid.cols {
            let cell = grid[lineIdx, col]
            if cell.flags.contains(.wideContinuation) {
                col += 1
                continue
            }
            if preserveTabs && cell.flags.contains(.isTab) {
                text += "\t"
            } else if GraphemeTable.isGraphemeRef(cell.codePoint) {
                text += graphemes.lookup(cell.codePoint)
            } else {
                text += String(cell.character)
            }
            col += 1
        }
        // Trim trailing spaces
        while text.hasSuffix(" ") { text.removeLast() }
        return text
    }

    /// Clear the selection.
    public mutating func clear() {
        active = false
    }

    /// Extend selection to a new position using word boundaries.
    public static func wordBoundaries(
        at position: Position, in grid: CellGrid, yBase: Int
    ) -> (start: Position, end: Position) {
        let lineIdx = yBase + position.row
        let cols = grid.cols

        // Find word start
        var startCol = position.col
        while startCol > 0 {
            let cell = grid[lineIdx, startCol - 1]
            if isWordSeparator(cell.codePoint) { break }
            startCol -= 1
        }

        // Find word end
        var endCol = position.col
        while endCol < cols - 1 {
            let cell = grid[lineIdx, endCol + 1]
            if isWordSeparator(cell.codePoint) { break }
            endCol += 1
        }

        return (Position(col: startCol, row: position.row),
                Position(col: endCol, row: position.row))
    }

    private static func isWordSeparator(_ cp: UInt32) -> Bool {
        switch cp {
        case 0x20, 0x09, 0x0A, 0x0D: return true  // whitespace
        case 0x22, 0x27, 0x28, 0x29: return true  // quotes, parens
        case 0x5B, 0x5D, 0x7B, 0x7D: return true  // brackets, braces
        case 0x3C, 0x3E: return true               // angle brackets
        case 0x2C, 0x2E, 0x3B, 0x3A: return true  // punctuation
        default: return false
        }
    }
}
