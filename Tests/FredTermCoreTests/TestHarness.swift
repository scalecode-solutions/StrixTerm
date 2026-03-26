import Testing
@testable import FredTermCore

/// Shared test helpers for FredTerm tests, modeled after SwiftTerm's TerminalTestHarness.
enum TestHarness {
    /// Create a TerminalState for testing.
    /// The caller is responsible for calling `state.deallocate()` when done.
    static func makeTerminal(cols: Int = 80, rows: Int = 24, scrollback: Int = 0) -> TerminalState {
        return TerminalState(cols: cols, rows: rows, maxScrollback: scrollback)
    }

    /// Get the text content of a visible line (by 0-based row in the viewport).
    static func lineText(_ state: TerminalState, row: Int, trimRight: Bool = true) -> String {
        let lineIdx = state.buffer.yBase + row
        guard lineIdx >= 0 && lineIdx < state.buffer.grid.count else { return "" }
        return state.buffer.grid.lineText(lineIdx, trimTrailing: trimRight)
    }

    /// Assert that the cursor is at the expected position.
    static func assertCursor(
        _ state: TerminalState, col: Int, row: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(state.buffer.cursorX == col, "Expected cursor col \(col) but got \(state.buffer.cursorX)",
                sourceLocation: sourceLocation)
        #expect(state.buffer.cursorY == row, "Expected cursor row \(row) but got \(state.buffer.cursorY)",
                sourceLocation: sourceLocation)
    }

    /// Assert that a visible line has the expected text content.
    static func assertLineText(
        _ state: TerminalState, row: Int, equals expected: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = lineText(state, row: row)
        #expect(actual == expected,
                "Row \(row): expected \"\(expected)\" but got \"\(actual)\"",
                sourceLocation: sourceLocation)
    }

    /// Get a cell at a position in the visible area (0-based row, col).
    static func cell(_ state: TerminalState, row: Int, col: Int) -> Cell {
        let lineIdx = state.buffer.yBase + row
        return state.buffer.grid[lineIdx, col]
    }

    /// Get the attribute entry for a cell at the given position.
    static func attribute(_ state: TerminalState, row: Int, col: Int) -> AttributeEntry {
        let c = cell(state, row: row, col: col)
        return state.attributes[c.attribute]
    }

    /// Collect sendData actions from the terminal state.
    static func collectResponses(_ state: inout TerminalState) -> [[UInt8]] {
        let responses = state.pendingActions.compactMap { action -> [UInt8]? in
            if case .sendData(let data) = action {
                return data
            }
            return nil
        }
        state.pendingActions.removeAll()
        return responses
    }

    /// Get text from a specific line index (absolute, not relative to viewport).
    static func lineTextAbsolute(_ state: TerminalState, lineIndex: Int, trimRight: Bool = true) -> String {
        guard lineIndex >= 0 && lineIndex < state.buffer.grid.count else { return "" }
        return state.buffer.grid.lineText(lineIndex, trimTrailing: trimRight)
    }

    /// Check if a line is marked as wrapped.
    static func isWrapped(_ state: TerminalState, row: Int) -> Bool {
        let lineIdx = state.buffer.yBase + row
        return state.buffer.grid[lineMetadata: lineIdx].isWrapped
    }
}
