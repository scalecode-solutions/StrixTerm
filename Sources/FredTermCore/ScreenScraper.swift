/// An immutable snapshot of the terminal state for rendering or screen scraping.
///
/// Addresses issue #93 by providing a public API for reading terminal state
/// without requiring mutable access.
public struct TerminalSnapshot: Sendable {
    public let cols: Int
    public let rows: Int
    public let cursorPosition: Position
    public let cursorVisible: Bool
    public let cursorStyle: CursorStyle
    public let isAlternateBuffer: Bool

    /// Visible cells: a flat array of rows * cols cells.
    public let cells: [Cell]
    /// Line metadata for visible lines.
    public let lineMetadata: [LineMetadata]
    /// The attribute table for resolving cell attributes.
    public let attributes: AttributeTable
    /// The color palette.
    public let palette: ColorPalette
    /// Scroll offset.
    public let scrollOffset: Int
    /// Total scrollback lines.
    public let totalScrollback: Int
    /// The link table for resolving cell hyperlinks.
    public let linkTable: LinkTable

    init(state: TerminalState) {
        cols = state.cols
        rows = state.rows
        cursorPosition = Position(col: state.buffer.cursorX, row: state.buffer.cursorY)
        cursorVisible = state.modes.cursorVisible
        cursorStyle = state.cursorStyle
        isAlternateBuffer = state.activeBufferIsAlt
        attributes = state.attributes
        palette = state.palette
        linkTable = state.links

        let yBase = state.buffer.yBase
        let yDisp = state.buffer.yDisp
        scrollOffset = yBase - yDisp
        totalScrollback = state.buffer.linesTop

        // Copy visible cells
        var visibleCells: [Cell] = []
        visibleCells.reserveCapacity(rows * cols)
        var lineMeta: [LineMetadata] = []
        lineMeta.reserveCapacity(rows)

        for row in 0..<rows {
            let lineIdx = yDisp + row
            for col in 0..<cols {
                visibleCells.append(state.buffer.grid[lineIdx, col])
            }
            lineMeta.append(state.buffer.grid[lineMetadata: lineIdx])
        }

        cells = visibleCells
        lineMetadata = lineMeta
    }

    /// Get a cell at a visible position.
    public func cell(at position: Position) -> Cell {
        guard position.row >= 0 && position.row < rows &&
              position.col >= 0 && position.col < cols else {
            return .blank
        }
        return cells[position.row * cols + position.col]
    }

    /// Get the attribute for a cell.
    public func attribute(for cell: Cell) -> AttributeEntry {
        attributes[cell.attribute]
    }

    /// Get the text of a visible line.
    public func lineText(_ row: Int, trimTrailing: Bool = true) -> String {
        guard row >= 0 && row < rows else { return "" }
        var result = ""
        var lastNonBlank = -1

        for col in 0..<cols {
            let c = cells[row * cols + col]
            if c.flags.contains(.wideContinuation) { continue }
            if !c.isBlank { lastNonBlank = col }
        }

        let endCol = trimTrailing ? lastNonBlank + 1 : cols
        for col in 0..<endCol {
            let c = cells[row * cols + col]
            if c.flags.contains(.wideContinuation) { continue }
            result.append(Character(c.character))
        }
        return result
    }

    /// Get all visible text as a single string.
    public func allText(trimTrailing: Bool = true) -> String {
        var lines: [String] = []
        for row in 0..<rows {
            let text = lineText(row, trimTrailing: trimTrailing)
            let meta = lineMetadata[row]
            lines.append(text)
            if row < rows - 1 && !meta.isWrapped {
                lines.append("\n")
            }
        }
        return lines.joined()
    }

    /// Get the text content in a given row range.
    public func text(rows range: Range<Int>, trimTrailing: Bool = true) -> String {
        let clamped = range.clamped(to: 0..<rows)
        var result = ""
        for row in clamped {
            if row > clamped.lowerBound { result += "\n" }
            result += lineText(row, trimTrailing: trimTrailing)
        }
        return result
    }
}
