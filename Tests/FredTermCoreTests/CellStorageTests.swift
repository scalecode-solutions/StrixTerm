import Testing
@testable import FredTermCore

@Suite("CellGrid Tests")
struct CellStorageTests {
    @Test("Cell is 16 bytes")
    func cellSize() {
        #expect(MemoryLayout<Cell>.size == 16)
        #expect(MemoryLayout<Cell>.stride == 16)
    }

    @Test("CellGrid initializes with blank cells")
    func gridInit() {
        var grid = CellGrid(cols: 80, maxLines: 100)
        defer { grid.deallocate() }

        grid.appendLine()
        let cell = grid[0, 0]
        #expect(cell.codePoint == 0x20)
        #expect(cell.isBlank)
        #expect(cell.width == 1)
    }

    @Test("CellGrid subscript read/write")
    func gridReadWrite() {
        var grid = CellGrid(cols: 80, maxLines: 100)
        defer { grid.deallocate() }

        grid.appendLine()
        var cell = Cell.blank
        cell.codePoint = 0x41 // 'A'
        cell.attribute = 1
        grid[0, 5] = cell

        let read = grid[0, 5]
        #expect(read.codePoint == 0x41)
        #expect(read.attribute == 1)
    }

    @Test("CellGrid appendLine grows count")
    func gridAppendLine() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        for _ in 0..<3 {
            grid.appendLine()
        }
        #expect(grid.count == 3)
    }

    @Test("CellGrid ring wraps correctly")
    func gridRingWrap() {
        var grid = CellGrid(cols: 5, maxLines: 3)
        defer { grid.deallocate() }

        // Fill 3 lines
        for i in 0..<3 {
            grid.appendLine()
            grid[i, 0] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }
        #expect(grid.count == 3)
        #expect(grid[0, 0].codePoint == 0x41) // 'A'
        #expect(grid[1, 0].codePoint == 0x42) // 'B'
        #expect(grid[2, 0].codePoint == 0x43) // 'C'

        // Append one more, should evict 'A'
        let evicted = grid.appendLine()
        #expect(evicted)
        grid[2, 0] = Cell(codePoint: 0x44, attribute: 0, width: 1, flags: [], payload: 0) // 'D'

        // Oldest should now be 'B'
        #expect(grid[0, 0].codePoint == 0x42) // 'B'
        #expect(grid[1, 0].codePoint == 0x43) // 'C'
        #expect(grid[2, 0].codePoint == 0x44) // 'D'
    }

    @Test("CellGrid clearLine")
    func gridClearLine() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        grid[0, 3] = Cell(codePoint: 0x58, attribute: 0, width: 1, flags: [], payload: 0)
        #expect(grid[0, 3].codePoint == 0x58)

        grid.clearLine(0)
        #expect(grid[0, 3].codePoint == 0x20)
    }

    @Test("CellGrid scrollRegionUp")
    func gridScrollUp() {
        var grid = CellGrid(cols: 5, maxLines: 10)
        defer { grid.deallocate() }

        // Create 5 lines with distinct content
        for i in 0..<5 {
            grid.appendLine()
            grid[i, 0] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Scroll lines 1-3 up by 1
        grid.scrollRegionUp(top: 1, bottom: 4, count: 1)

        #expect(grid[0, 0].codePoint == 0x41) // 'A' unchanged
        #expect(grid[1, 0].codePoint == 0x43) // Was 'C' (shifted up from row 2)
        #expect(grid[2, 0].codePoint == 0x44) // Was 'D'
        #expect(grid[3, 0].isBlank)           // New blank line
        #expect(grid[4, 0].codePoint == 0x45) // 'E' unchanged
    }

    @Test("CellGrid insertCells")
    func gridInsertCells() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        // Write "ABCDE" at positions 0-4
        for i in 0..<5 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Insert 2 cells at position 2
        grid.insertCells(line: 0, at: 2, count: 2, rightMargin: 10)

        #expect(grid[0, 0].codePoint == 0x41) // 'A'
        #expect(grid[0, 1].codePoint == 0x42) // 'B'
        #expect(grid[0, 2].isBlank)           // Inserted blank
        #expect(grid[0, 3].isBlank)           // Inserted blank
        #expect(grid[0, 4].codePoint == 0x43) // 'C' shifted right
        #expect(grid[0, 5].codePoint == 0x44) // 'D' shifted right
    }

    @Test("CellGrid deleteCells")
    func gridDeleteCells() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        for i in 0..<5 {
            grid[0, i] = Cell(codePoint: UInt32(0x41 + i), attribute: 0, width: 1, flags: [], payload: 0)
        }

        // Delete 2 cells at position 1
        grid.deleteCells(line: 0, at: 1, count: 2, rightMargin: 10)

        #expect(grid[0, 0].codePoint == 0x41) // 'A'
        #expect(grid[0, 1].codePoint == 0x44) // 'D' shifted left
        #expect(grid[0, 2].codePoint == 0x45) // 'E' shifted left
        #expect(grid[0, 3].isBlank)           // Filled blank
    }

    @Test("CellGrid lineText")
    func gridLineText() {
        var grid = CellGrid(cols: 10, maxLines: 5)
        defer { grid.deallocate() }

        grid.appendLine()
        let hello = "Hello"
        for (i, ch) in hello.unicodeScalars.enumerated() {
            grid[0, i] = Cell(codePoint: ch.value, attribute: 0, width: 1, flags: [], payload: 0)
        }

        #expect(grid.lineText(0) == "Hello")
        #expect(grid.lineText(0, trimTrailing: false) == "Hello     ")
    }

    @Test("LineMetadata defaults")
    func lineMetadata() {
        let meta = LineMetadata.blank
        #expect(!meta.isWrapped)
        #expect(meta.renderMode == .normal)
        #expect(!meta.hasImages)
        #expect(meta.promptZone == .none)
    }
}

@Suite("AttributeTable Tests")
struct AttributeTableTests {
    @Test("Default attribute at index 0")
    func defaultAttribute() {
        let table = AttributeTable()
        let attr = table[0]
        #expect(attr.fg == .default)
        #expect(attr.bg == .default)
        #expect(attr.style.isEmpty)
    }

    @Test("Interning returns consistent indices")
    func interning() {
        var table = AttributeTable()
        let bold = AttributeEntry(style: .bold)
        let idx1 = table.intern(bold)
        let idx2 = table.intern(bold)
        #expect(idx1 == idx2)
        #expect(table.count == 2) // default + bold
    }

    @Test("Different attributes get different indices")
    func uniqueAttributes() {
        var table = AttributeTable()
        let bold = AttributeEntry(style: .bold)
        let italic = AttributeEntry(style: .italic)
        let idx1 = table.intern(bold)
        let idx2 = table.intern(italic)
        #expect(idx1 != idx2)
    }
}

@Suite("GraphemeTable Tests")
struct GraphemeTableTests {
    @Test("Insert and lookup")
    func insertLookup() {
        var table = GraphemeTable()
        let encoded = table.insert("e\u{0301}") // e + combining acute
        #expect(GraphemeTable.isGraphemeRef(encoded))
        #expect(table.lookup(encoded) == "e\u{0301}")
    }

    @Test("Release and reuse")
    func releaseReuse() {
        var table = GraphemeTable()
        let e1 = table.insert("abc")
        table.release(e1)
        let e2 = table.insert("xyz")
        // Should reuse the released slot
        #expect(table.count == 1)
        #expect(table.lookup(e2) == "xyz")
    }

    @Test("Threshold check")
    func threshold() {
        #expect(!GraphemeTable.isGraphemeRef(0x41))      // 'A' is not a ref
        #expect(!GraphemeTable.isGraphemeRef(0x10FFFF))   // Last valid Unicode
        #expect(GraphemeTable.isGraphemeRef(0x110000))     // First ref value
    }
}

@Suite("TabStops Tests")
struct TabStopsTests {
    @Test("Default tab stops every 8 columns")
    func defaultStops() {
        let tabs = TabStops(width: 80)
        #expect(!tabs.isSet(0))
        #expect(tabs.isSet(8))
        #expect(tabs.isSet(16))
        #expect(tabs.isSet(24))
        #expect(!tabs.isSet(7))
    }

    @Test("Next tab stop")
    func nextStop() {
        let tabs = TabStops(width: 80)
        #expect(tabs.nextStop(after: 0) == 8)
        #expect(tabs.nextStop(after: 7) == 8)
        #expect(tabs.nextStop(after: 8) == 16)
    }

    @Test("Clear and set")
    func clearSet() {
        var tabs = TabStops(width: 80)
        tabs.clear(8)
        #expect(!tabs.isSet(8))
        #expect(tabs.nextStop(after: 0) == 16)

        tabs.set(4)
        #expect(tabs.isSet(4))
        #expect(tabs.nextStop(after: 0) == 4)
    }

    @Test("Clear all")
    func clearAll() {
        var tabs = TabStops(width: 80)
        tabs.clearAll()
        #expect(tabs.nextStop(after: 0) == 79) // Falls through to width-1
    }
}
