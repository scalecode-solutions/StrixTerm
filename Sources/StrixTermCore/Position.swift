/// A (col, row) position in the terminal grid.
public struct Position: Hashable, Sendable, Comparable {
    public var col: Int
    public var row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }

    public static func < (lhs: Position, rhs: Position) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.col < rhs.col
    }
}

/// Terminal dimensions.
public struct TerminalSize: Hashable, Sendable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}
