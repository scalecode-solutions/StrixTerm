/// The core terminal state. This is a value type that owns all terminal state
/// and implements the TerminalEmulator protocol for parser dispatch.
///
/// Splitting from SwiftTerm's monolithic 6,748-line Terminal class into
/// focused components while keeping the hot path (character insertion)
/// free of ARC overhead and swift_beginAccess exclusivity checks.
public struct TerminalState: @unchecked Sendable {
    public var normalBuffer: BufferState
    public var altBuffer: BufferState
    public var activeBufferIsAlt: Bool = false

    public var parser: VTParser = VTParser()
    public var graphemes: GraphemeTable = GraphemeTable()
    public var links: LinkTable = LinkTable()
    public var attributes: AttributeTable = AttributeTable()
    public var charsets: CharsetState = CharsetState()

    public var cursorAttribute: UInt32 = 0
    public var cursorStyle: CursorStyle = .blinkBlock
    public var modes: TerminalModes = TerminalModes()
    public var keyboardNormal: KeyboardState = KeyboardState()
    public var keyboardAlt: KeyboardState = KeyboardState()

    /// The keyboard state for the currently active screen buffer.
    public var keyboard: KeyboardState {
        get { activeBufferIsAlt ? keyboardAlt : keyboardNormal }
        set {
            if activeBufferIsAlt {
                keyboardAlt = newValue
            } else {
                keyboardNormal = newValue
            }
        }
    }
    public var palette: ColorPalette = .xterm
    public var promptState: SemanticPromptState = SemanticPromptState()
    public var kittyGraphics: KittyGraphicsState = KittyGraphicsState()

    /// Text selection state.
    public var selection: Selection = Selection()

    /// Active OSC 8 link tracking: when non-nil, all characters written
    /// will be tagged with this link ID until the link is closed.
    public var activeLinkTracking: (start: Position, linkId: UInt16)? = nil

    public var cols: Int
    public var rows: Int
    public var maxScrollback: Int

    /// Pending actions to be delivered to the delegate.
    public var pendingActions: [TerminalAction] = []

    /// The conformance URL reported by XTVERSION.
    public var terminalID: String = "StrixTerm"
    public var termName: String = "xterm-256color"

    // MARK: - Initialization

    public init(cols: Int, rows: Int, maxScrollback: Int = 10_000) {
        self.cols = cols
        self.rows = rows
        self.maxScrollback = maxScrollback
        normalBuffer = BufferState(cols: cols, rows: rows, maxScrollback: maxScrollback, hasScrollback: maxScrollback > 0)
        altBuffer = BufferState(cols: cols, rows: rows, maxScrollback: 0, hasScrollback: false)
    }

    /// The currently active buffer.
    public var buffer: BufferState {
        get { activeBufferIsAlt ? altBuffer : normalBuffer }
        set {
            if activeBufferIsAlt {
                altBuffer = newValue
            } else {
                normalBuffer = newValue
            }
        }
    }

    // MARK: - Feed data

    /// Feed raw bytes from the host process into the terminal.
    public mutating func feed(_ data: [UInt8]) {
        var p = parser
        p.parse(data, handler: &self)
        parser = p
    }

    /// Feed a string from the host process.
    public mutating func feed(text: String) {
        feed(Array(text.utf8))
    }

    // MARK: - Resize

    /// Resize the terminal to new dimensions.
    public mutating func resize(cols newCols: Int, rows newRows: Int) {
        guard newCols != cols || newRows != rows else { return }
        let oldCols = cols
        cols = newCols
        rows = newRows

        // Normal buffer: use reflow when column count changes and scrollback is available
        if newCols != oldCols && maxScrollback > 0 {
            ReflowEngine.reflow(
                grid: &normalBuffer.grid,
                oldCols: oldCols,
                newCols: newCols,
                newMaxLines: newRows + maxScrollback,
                cursorX: &normalBuffer.cursorX,
                cursorY: &normalBuffer.cursorY,
                yBase: &normalBuffer.yBase,
                yDisp: &normalBuffer.yDisp
            )
        } else {
            normalBuffer.grid.resize(newCols: newCols, newRows: newRows,
                                      newMaxLines: newRows + maxScrollback)
        }
        normalBuffer.scrollTop = 0
        normalBuffer.scrollBottom = newRows - 1
        normalBuffer.marginLeft = 0
        normalBuffer.marginRight = newCols - 1
        normalBuffer.tabStops.resize(newCols)

        // Alt buffer: never reflow, just simple resize and clear
        altBuffer.grid.resize(newCols: newCols, newRows: newRows,
                               newMaxLines: newRows)
        altBuffer.scrollTop = 0
        altBuffer.scrollBottom = newRows - 1
        altBuffer.marginLeft = 0
        altBuffer.marginRight = newCols - 1
        altBuffer.tabStops.resize(newCols)
        if activeBufferIsAlt {
            // Clear alt buffer content on resize (standard behavior)
            for line in 0..<min(newRows, altBuffer.grid.count) {
                altBuffer.grid.clearLine(line)
            }
        }

        // Clamp cursors
        normalBuffer.clampCursor(modes: modes)
        altBuffer.clampCursor(modes: modes)
    }

    // MARK: - Buffer switching

    /// Switch to the alternate screen buffer.
    public mutating func activateAltBuffer() {
        guard !activeBufferIsAlt else { return }
        activeBufferIsAlt = true
        // Save normal buffer cursor
        normalBuffer.saveCursor(attribute: cursorAttribute, modes: modes)
        // Clear alt buffer
        for line in 0..<rows {
            altBuffer.grid.clearLine(line)
        }
        altBuffer.cursorX = 0
        altBuffer.cursorY = 0
        pendingActions.append(.bufferActivated(isAlternate: true))
    }

    /// Switch back to the normal screen buffer.
    public mutating func deactivateAltBuffer() {
        guard activeBufferIsAlt else { return }
        activeBufferIsAlt = false
        // Clear the alt buffer
        altBuffer.clearBuffer(rows: rows, cols: cols)
        // Restore normal buffer cursor
        let saved = normalBuffer.restoreCursor()
        normalBuffer.cursorX = saved.x
        normalBuffer.cursorY = saved.y
        cursorAttribute = saved.attribute
        // Note: Do NOT reset keyboard state on RMCUP.
        // Normal and alt screens maintain separate keyboard state.
        pendingActions.append(.bufferActivated(isAlternate: false))
    }

    // MARK: - Reset

    /// Full reset to initial state (RIS equivalent, callable from tests).
    public mutating func resetToInitialState() {
        // Trigger the same path as ESC c (full reset)
        feed(Array("\u{1b}c".utf8))
    }

    // MARK: - Cleanup

    public mutating func deallocate() {
        normalBuffer.deallocate()
        altBuffer.deallocate()
    }

    // MARK: - Cell text helpers (for testing and inspection)

    /// Get the character/grapheme cluster for a cell, resolving grapheme table refs.
    public func cellText(col: Int, row: Int) -> String {
        let lineIdx = buffer.yBase + row
        let cell = buffer.grid[lineIdx, col]
        if GraphemeTable.isGraphemeRef(cell.codePoint) {
            return graphemes.lookup(cell.codePoint)
        }
        return String(cell.character)
    }

    /// Get the cell at a visible position.
    public func getCell(col: Int, row: Int) -> Cell {
        let lineIdx = buffer.yBase + row
        return buffer.grid[lineIdx, col]
    }

    /// Get the text of a visible line, resolving grapheme refs.
    public func lineText(_ row: Int) -> String {
        let lineIdx = buffer.yBase + row
        return buffer.grid.lineText(lineIdx, graphemes: graphemes)
    }
}

// MARK: - TerminalEmulator conformance

extension TerminalState: TerminalEmulator {
    /// Handle a printable ASCII byte.
    @inline(__always)
    public mutating func handlePrint(_ byte: UInt8) {
        var cp = UInt32(byte)

        // Apply character set mapping
        let charset = charsets.currentCharset
        if charset == .decSpecialGraphics && byte >= 0x5F && byte <= 0x7E {
            cp = decSpecialGraphicsMap[Int(byte)]
        }

        // Clear single shift after use
        if charsets.singleShift >= 0 {
            charsets.singleShift = -1
        }

        let linkPayload: UInt16
        let linkFlags: CellFlags
        if let tracking = activeLinkTracking {
            linkPayload = tracking.linkId
            linkFlags = .hasLink
        } else {
            linkPayload = 0
            linkFlags = []
        }

        let cell = Cell(
            codePoint: cp,
            attribute: cursorAttribute,
            width: 1,
            flags: linkFlags,
            payload: linkPayload
        )
        buffer.insertCharacter(cell, modes: modes)
    }

    /// Handle a Unicode scalar (multi-byte characters).
    public mutating func handlePrintScalar(_ scalar: UInt32) {
        // Check for zero-width / combining
        if UnicodeWidth.isZeroWidth(scalar) {
            handleCombiningCharacter(scalar)
            return
        }

        // Skin tone modifiers (Fitzpatrick scale) combine with previous emoji
        if scalar >= 0x1F3FB && scalar <= 0x1F3FF {
            handleCombiningCharacter(scalar)
            return
        }

        // Regional indicators: if previous cell is also a regional indicator, combine to form a flag
        if scalar >= 0x1F1E6 && scalar <= 0x1F1FF {
            let lineIdx = buffer.absoluteCursorY
            let prevCol = buffer.cursorX > 0 ? buffer.cursorX - 1 : 0
            // Skip over wide continuation cells to find the base cell
            var col = prevCol
            while col > 0 && buffer.grid[lineIdx, col].flags.contains(.wideContinuation) {
                col -= 1
            }
            let prevCell = buffer.grid[lineIdx, col]
            let prevCP = prevCell.codePoint
            // Check if previous cell is a single (unpaired) regional indicator
            let prevIsRI: Bool
            if GraphemeTable.isGraphemeRef(prevCP) {
                let str = graphemes.lookup(prevCP)
                let scalars = Array(str.unicodeScalars)
                // Already paired (2 regional indicators) - don't combine further
                prevIsRI = scalars.count == 1 && scalars[0].value >= 0x1F1E6 && scalars[0].value <= 0x1F1FF
            } else {
                prevIsRI = prevCP >= 0x1F1E6 && prevCP <= 0x1F1FF
            }
            if prevIsRI && buffer.cursorX > 0 {
                handleCombiningCharacter(scalar)
                return
            }
        }

        // After a ZWJ, the next character should combine with the previous cell
        if buffer.cursorX > 0 {
            let lineIdx = buffer.absoluteCursorY
            var col = buffer.cursorX - 1
            while col > 0 && buffer.grid[lineIdx, col].flags.contains(.wideContinuation) {
                col -= 1
            }
            let prevCell = buffer.grid[lineIdx, col]
            let prevCP = prevCell.codePoint
            if GraphemeTable.isGraphemeRef(prevCP) {
                let str = graphemes.lookup(prevCP)
                if let lastScalar = str.unicodeScalars.last, lastScalar.value == 0x200D {
                    handleCombiningCharacter(scalar)
                    return
                }
            } else if prevCP == 0x200D {
                handleCombiningCharacter(scalar)
                return
            }
        }

        let width = UnicodeWidth.width(of: scalar)

        let linkPayload: UInt16
        let linkFlags: CellFlags
        if let tracking = activeLinkTracking {
            linkPayload = tracking.linkId
            linkFlags = .hasLink
        } else {
            linkPayload = 0
            linkFlags = []
        }

        let cell = Cell(
            codePoint: scalar,
            attribute: cursorAttribute,
            width: UInt8(width),
            flags: linkFlags,
            payload: linkPayload
        )
        buffer.insertCharacter(cell, modes: modes)
    }

    /// Handle a combining character by appending to the previous cell.
    /// Also handles VS16 (U+FE0F) which upgrades width to 2,
    /// and VS15 (U+FE0E) which downgrades width to 1.
    private mutating func handleCombiningCharacter(_ scalar: UInt32) {
        let lineIdx = buffer.absoluteCursorY
        var col = buffer.cursorX > 0 ? buffer.cursorX - 1 : 0

        // Skip over wide continuation cells
        while col > 0 && buffer.grid[lineIdx, col].flags.contains(.wideContinuation) {
            col -= 1
        }

        var cell = buffer.grid[lineIdx, col]
        let existingCP = cell.codePoint

        // Build the combined string
        let existingStr: String
        if GraphemeTable.isGraphemeRef(existingCP) {
            existingStr = graphemes.lookup(existingCP)
            graphemes.release(existingCP)
        } else if let s = Unicode.Scalar(existingCP) {
            existingStr = String(s)
        } else {
            existingStr = " "
        }

        let combinedStr: String
        if let s = Unicode.Scalar(scalar) {
            combinedStr = existingStr + String(s)
        } else {
            combinedStr = existingStr
        }

        cell.codePoint = graphemes.insert(combinedStr)

        // Handle variation selectors that change width
        let oldWidth = cell.width
        if scalar == 0xFE0F {
            // VS16 (emoji presentation) - upgrade to width 2 if currently 1
            if oldWidth == 1 {
                cell.width = 2
                buffer.grid[lineIdx, col] = cell
                // Insert continuation cell
                if col + 1 < cols {
                    var cont = Cell.blank
                    cont.attribute = cell.attribute
                    cont.flags = .wideContinuation
                    cont.width = 0
                    buffer.grid[lineIdx, col + 1] = cont
                    // Shift cursor to account for the new width
                    buffer.cursorX = col + 2
                }
                return
            }
        } else if scalar == 0xFE0E {
            // VS15 (text presentation) - downgrade to width 1 if currently 2
            if oldWidth == 2 {
                cell.width = 1
                buffer.grid[lineIdx, col] = cell
                // Clear the old continuation cell
                if col + 1 < cols {
                    buffer.grid[lineIdx, col + 1] = Cell.blank
                }
                // Adjust cursor position
                buffer.cursorX = col + 1
                return
            }
        }

        buffer.grid[lineIdx, col] = cell
    }

    /// Handle a C0 control character.
    public mutating func handleExecute(_ byte: UInt8) {
        switch byte {
        case 0x00: // NUL - ignore
            break
        case 0x07: // BEL
            pendingActions.append(.bell)
        case 0x08: // BS - backspace
            if buffer.cursorX > 0 {
                buffer.cursorX -= 1
            } else if modes.reverseWraparound && modes.wraparound && buffer.cursorY > 0 {
                buffer.cursorY -= 1
                buffer.cursorX = cols - 1
            }
        case 0x09: // HT - horizontal tab
            let col = min(buffer.cursorX, cols - 1)
            let nextTab = buffer.tabStops.nextStop(after: col)
            buffer.cursorX = min(nextTab, cols - 1)
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            buffer.linefeed(modes: modes)
            if modes.autoNewline {
                buffer.cursorX = 0
            }
        case 0x0D: // CR
            buffer.cursorX = modes.marginMode ? buffer.marginLeft : 0
        case 0x0E: // SO - shift out (activate G1)
            charsets.activeGL = 1
        case 0x0F: // SI - shift in (activate G0)
            charsets.activeGL = 0
        default:
            break
        }
    }

    /// Handle a CSI dispatch.
    public mutating func handleCSIDispatch(
        params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8
    ) {
        dispatchCSI(params: params, intermediates: intermediates, final: final)
    }

    /// Handle an ESC dispatch.
    public mutating func handleESCDispatch(
        intermediates: IntermediateBuffer, final: UInt8
    ) {
        dispatchESC(intermediates: intermediates, final: final)
    }

    /// Handle an OSC sequence.
    public mutating func handleOSC(_ data: [UInt8]) {
        dispatchOSC(data)
    }

    /// Handle a DCS sequence.
    public mutating func handleDCS(
        params: ParamBuffer, intermediates: IntermediateBuffer,
        final: UInt8, data: [UInt8]
    ) {
        dispatchDCS(params: params, intermediates: intermediates, final: final, data: data)
    }

    /// Handle an APC sequence.
    public mutating func handleAPC(_ data: [UInt8]) {
        guard !data.isEmpty else { return }
        // Kitty graphics: APC starts with 'G'
        if data[0] == UInt8(ascii: "G") {
            let content = data.dropFirst() // skip the 'G'
            if let semicolonIdx = content.firstIndex(of: UInt8(ascii: ";")) {
                let control = content[content.startIndex..<semicolonIdx]
                let payload = content[content.index(after: semicolonIdx)..<content.endIndex]
                handleKittyGraphics(control: control, payload: payload)
            } else {
                // No payload
                let control = content[content.startIndex..<content.endIndex]
                let emptyPayload = content[content.endIndex..<content.endIndex]
                handleKittyGraphics(control: control, payload: emptyPayload)
            }
        }
    }
}
