/// Per-cell flags packed into a single byte.
public struct CellFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// This cell is the trailing part of a wide character (width == 0).
    public static let wideContinuation = CellFlags(rawValue: 1 << 0)
    /// This cell has a hyperlink attached (payload is link ID).
    public static let hasLink        = CellFlags(rawValue: 1 << 1)
    /// This cell has an image (payload is image ID).
    public static let hasImage       = CellFlags(rawValue: 1 << 2)
    /// This cell was produced by a tab character (for copy preservation).
    public static let isTab          = CellFlags(rawValue: 1 << 3)
}

/// A single terminal cell. 16 bytes, stored inline in contiguous memory.
/// No heap pointers, no reference counting.
public struct Cell: Sendable {
    /// Unicode scalar value, or an index into the GraphemeTable when >= 0x11_0000.
    public var codePoint: UInt32
    /// Index into the AttributeTable for this cell's styling.
    public var attribute: UInt32
    /// Display width: 0 = continuation of wide char, 1 = normal, 2 = wide.
    public var width: UInt8
    /// Per-cell flags.
    public var flags: CellFlags
    /// Payload: link ID, image reference, or other per-cell data.
    public var payload: UInt16
    /// Padding for alignment (16 bytes total).
    var _pad: UInt32

    /// An empty/blank cell with default attribute.
    public static let blank = Cell(
        codePoint: 0x20,
        attribute: 0,
        width: 1,
        flags: [],
        payload: 0,
        _pad: 0
    )

    public init(
        codePoint: UInt32,
        attribute: UInt32,
        width: UInt8,
        flags: CellFlags,
        payload: UInt16,
        _pad: UInt32 = 0
    ) {
        self.codePoint = codePoint
        self.attribute = attribute
        self.width = width
        self.flags = flags
        self.payload = payload
        self._pad = _pad
    }

    /// The character this cell represents, as a Unicode scalar (or space if zero).
    public var character: Unicode.Scalar {
        Unicode.Scalar(codePoint) ?? Unicode.Scalar(0x20)
    }

    /// Whether this cell is blank (space with no special flags).
    public var isBlank: Bool {
        codePoint == 0x20 && flags.isEmpty
    }
}

/// Render mode for an entire line (DEC double-width/double-height).
public enum RenderLineMode: UInt8, Sendable {
    case normal = 0
    case doubleWidth = 1
    case doubleHeightTop = 2
    case doubleHeightBottom = 3
}

/// Semantic prompt zone for OSC 133 support.
public enum PromptZone: UInt8, Sendable {
    case none = 0
    case promptStart = 1       // OSC 133;A
    case commandStart = 2      // OSC 133;B
    case commandExecuted = 3   // OSC 133;C
    case commandFinished = 4   // OSC 133;D
}

/// Line-level metadata stored in a parallel array, one entry per row in the ring.
public struct LineMetadata: Sendable {
    public var isWrapped: Bool = false
    public var renderMode: RenderLineMode = .normal
    public var hasImages: Bool = false
    public var promptZone: PromptZone = .none

    public static let blank = LineMetadata()
}

/// Contiguous ring buffer storing `maxLines x cols` cells.
///
/// This replaces SwiftTerm's `CircularList<BufferLine>` where each BufferLine
/// was a separate heap-allocated class. By using a flat contiguous array,
/// we eliminate per-line ARC overhead, swift_beginAccess exclusivity checks,
/// and retain/release in the hot `insertCharacter` path.
public struct CellGrid: @unchecked Sendable {
    private var storage: UnsafeMutableBufferPointer<Cell>
    private var metadata: UnsafeMutableBufferPointer<LineMetadata>

    public private(set) var cols: Int
    public private(set) var maxLines: Int
    private var ringStart: Int = 0
    public private(set) var count: Int = 0

    public init(cols: Int, maxLines: Int) {
        precondition(cols > 0 && maxLines > 0)
        self.cols = cols
        self.maxLines = maxLines

        let totalCells = cols * maxLines
        storage = .allocate(capacity: totalCells)
        storage.initialize(repeating: .blank)

        metadata = .allocate(capacity: maxLines)
        metadata.initialize(repeating: .blank)
    }

    /// Deallocate the backing storage.
    public mutating func deallocate() {
        storage.deinitialize()
        storage.deallocate()
        metadata.deinitialize()
        metadata.deallocate()
    }

    // MARK: - Indexing

    /// Map a logical line index (0 = oldest line in the ring) to the physical storage index.
    @inline(__always)
    private func physicalIndex(forLogical logical: Int) -> Int {
        (ringStart + logical) % maxLines
    }

    /// Access a cell at (logicalLine, col).
    @inline(__always)
    public subscript(line: Int, col: Int) -> Cell {
        get {
            let phys = physicalIndex(forLogical: line)
            return storage[phys * cols + col]
        }
        set {
            let phys = physicalIndex(forLogical: line)
            storage[phys * cols + col] = newValue
        }
    }

    /// Access the metadata for a logical line.
    @inline(__always)
    public subscript(lineMetadata line: Int) -> LineMetadata {
        get {
            metadata[physicalIndex(forLogical: line)]
        }
        set {
            metadata[physicalIndex(forLogical: line)] = newValue
        }
    }

    /// Get a pointer to the raw cells in a row for bulk operations.
    public func rowPointer(_ line: Int) -> UnsafeMutableBufferPointer<Cell> {
        let phys = physicalIndex(forLogical: line)
        let start = storage.baseAddress! + phys * cols
        return UnsafeMutableBufferPointer(start: start, count: cols)
    }

    // MARK: - Ring operations

    /// Add a new blank line at the bottom of the ring.
    /// If the ring is full, the oldest line is overwritten.
    /// Returns `true` if a line was evicted from the top.
    @discardableResult
    public mutating func appendLine(fillAttribute: UInt32 = 0) -> Bool {
        let evicted: Bool
        if count < maxLines {
            count += 1
            evicted = false
        } else {
            ringStart = (ringStart + 1) % maxLines
            evicted = true
        }
        // Clear the new line
        let lineIdx = count - 1
        clearLine(lineIdx, fillAttribute: fillAttribute)
        self[lineMetadata: lineIdx] = .blank
        return evicted
    }

    /// Clear a logical line to blanks with the given attribute.
    public mutating func clearLine(_ line: Int, fillAttribute: UInt32 = 0) {
        let phys = physicalIndex(forLogical: line)
        let start = phys * cols
        var blank = Cell.blank
        blank.attribute = fillAttribute
        for i in start..<(start + cols) {
            storage[i] = blank
        }
    }

    /// Clear a range of cells within a line.
    public mutating func clearCells(line: Int, from startCol: Int, to endCol: Int, fillAttribute: UInt32 = 0) {
        let phys = physicalIndex(forLogical: line)
        let base = phys * cols
        var blank = Cell.blank
        blank.attribute = fillAttribute
        let start = max(0, startCol)
        let end = min(cols, endCol)
        for i in start..<end {
            storage[base + i] = blank
        }
    }

    /// Scroll the region [top, bottom) up by `count` lines within the visible area.
    /// New lines at the bottom of the region are blanked.
    public mutating func scrollRegionUp(
        top: Int, bottom: Int, count scrollCount: Int,
        fillAttribute: UInt32 = 0
    ) {
        let n = min(scrollCount, bottom - top)
        if n <= 0 { return }

        // Copy lines up
        for dst in top..<(bottom - n) {
            let src = dst + n
            copyLine(from: src, to: dst)
        }
        // Blank the new bottom lines
        for line in (bottom - n)..<bottom {
            clearLine(line, fillAttribute: fillAttribute)
            self[lineMetadata: line] = .blank
        }
    }

    /// Scroll the region [top, bottom) down by `count` lines.
    /// New lines at the top of the region are blanked.
    public mutating func scrollRegionDown(
        top: Int, bottom: Int, count scrollCount: Int,
        fillAttribute: UInt32 = 0
    ) {
        let n = min(scrollCount, bottom - top)
        if n <= 0 { return }

        // Copy lines down (iterate in reverse to avoid overwriting)
        for dst in stride(from: bottom - 1, through: top + n, by: -1) {
            let src = dst - n
            copyLine(from: src, to: dst)
        }
        // Blank the new top lines
        for line in top..<(top + n) {
            clearLine(line, fillAttribute: fillAttribute)
            self[lineMetadata: line] = .blank
        }
    }

    /// Copy all cells from one logical line to another.
    private mutating func copyLine(from src: Int, to dst: Int) {
        let srcPhys = physicalIndex(forLogical: src)
        let dstPhys = physicalIndex(forLogical: dst)
        let srcStart = srcPhys * cols
        let dstStart = dstPhys * cols
        for i in 0..<cols {
            storage[dstStart + i] = storage[srcStart + i]
        }
        metadata[dstPhys] = metadata[srcPhys]
    }

    /// Insert `n` blank cells at the given position, shifting cells right.
    /// Cells that fall off the right edge of the margin are lost.
    public mutating func insertCells(
        line: Int, at col: Int, count n: Int,
        rightMargin: Int, fillAttribute: UInt32 = 0
    ) {
        let phys = physicalIndex(forLogical: line)
        let base = phys * cols
        let right = min(rightMargin, cols)
        let insertCount = min(n, right - col)
        if insertCount <= 0 { return }

        // Shift cells right
        var i = right - 1
        while i >= col + insertCount {
            storage[base + i] = storage[base + i - insertCount]
            i -= 1
        }
        // Fill inserted cells with blanks
        var blank = Cell.blank
        blank.attribute = fillAttribute
        for i in col..<(col + insertCount) {
            storage[base + i] = blank
        }
    }

    /// Delete `n` cells at the given position, shifting cells left.
    /// New cells at the right margin are blanked.
    public mutating func deleteCells(
        line: Int, at col: Int, count n: Int,
        rightMargin: Int, fillAttribute: UInt32 = 0
    ) {
        let phys = physicalIndex(forLogical: line)
        let base = phys * cols
        let right = min(rightMargin, cols)
        let deleteCount = min(n, right - col)
        if deleteCount <= 0 { return }

        // Shift cells left
        for i in col..<(right - deleteCount) {
            storage[base + i] = storage[base + i + deleteCount]
        }
        // Fill right edge with blanks
        var blank = Cell.blank
        blank.attribute = fillAttribute
        for i in (right - deleteCount)..<right {
            storage[base + i] = blank
        }
    }

    /// Get the text content of a line as a String.
    public func lineText(_ line: Int, trimTrailing: Bool = true) -> String {
        lineText(line, trimTrailing: trimTrailing, graphemes: nil)
    }

    /// Get the text content of a line, resolving grapheme refs if a table is provided.
    public func lineText(_ line: Int, trimTrailing: Bool = true, graphemes: GraphemeTable?) -> String {
        var result = ""
        var lastNonBlank = -1

        for col in 0..<cols {
            let cell = self[line, col]
            if cell.flags.contains(.wideContinuation) { continue }
            if !cell.isBlank { lastNonBlank = col }
        }

        let endCol = trimTrailing ? lastNonBlank + 1 : cols
        for col in 0..<endCol {
            let cell = self[line, col]
            if cell.flags.contains(.wideContinuation) { continue }
            if let g = graphemes, GraphemeTable.isGraphemeRef(cell.codePoint) {
                result += g.lookup(cell.codePoint)
            } else {
                result.append(Character(cell.character))
            }
        }
        return result
    }

    // MARK: - Resize

    /// Resize the grid to new dimensions. Performs reflow if column count changes.
    /// This is a simplified resize; full reflow is in Reflow.swift.
    public mutating func resize(newCols: Int, newRows: Int, newMaxLines: Int) {
        let newGrid = CellGrid(cols: newCols, maxLines: newMaxLines)
        var dest = newGrid

        // Copy existing lines
        let linesToCopy = min(count, newMaxLines)
        let srcStart = max(0, count - linesToCopy)
        for i in 0..<linesToCopy {
            let srcLine = srcStart + i
            let colsToCopy = min(cols, newCols)
            for col in 0..<colsToCopy {
                dest[i, col] = self[srcLine, col]
            }
            dest[lineMetadata: i] = self[lineMetadata: srcLine]
        }
        dest.count = linesToCopy

        // Replace storage
        self.storage.deinitialize()
        self.storage.deallocate()
        self.metadata.deinitialize()
        self.metadata.deallocate()

        self.storage = dest.storage
        self.metadata = dest.metadata
        self.cols = newCols
        self.maxLines = newMaxLines
        self.ringStart = dest.ringStart
        self.count = dest.count
    }
}
