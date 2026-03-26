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
    public var attributes: AttributeTable = AttributeTable()
    public var charsets: CharsetState = CharsetState()

    public var cursorAttribute: UInt32 = 0
    public var cursorStyle: CursorStyle = .blinkBlock
    public var modes: TerminalModes = TerminalModes()
    public var keyboard: KeyboardState = KeyboardState()
    public var palette: ColorPalette = .xterm
    public var promptState: SemanticPromptState = SemanticPromptState()

    public var cols: Int
    public var rows: Int
    public var maxScrollback: Int

    /// Pending actions to be delivered to the delegate.
    public var pendingActions: [TerminalAction] = []

    /// The conformance URL reported by XTVERSION.
    public var terminalID: String = "FredTerm"
    public var termName: String = "xterm-256color"

    // MARK: - Initialization

    public init(cols: Int, rows: Int, maxScrollback: Int = 10_000) {
        self.cols = cols
        self.rows = rows
        self.maxScrollback = maxScrollback
        normalBuffer = BufferState(cols: cols, rows: rows, maxScrollback: maxScrollback, hasScrollback: true)
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
        let oldRows = rows
        cols = newCols
        rows = newRows

        // Resize both buffers
        normalBuffer.grid.resize(newCols: newCols, newRows: newRows,
                                  newMaxLines: newRows + maxScrollback)
        normalBuffer.scrollBottom = newRows - 1
        normalBuffer.marginRight = newCols - 1
        normalBuffer.tabStops.resize(newCols)

        altBuffer.grid.resize(newCols: newCols, newRows: newRows,
                               newMaxLines: newRows)
        altBuffer.scrollBottom = newRows - 1
        altBuffer.marginRight = newCols - 1
        altBuffer.tabStops.resize(newCols)

        // Clamp cursors
        normalBuffer.clampCursor(modes: modes)
        altBuffer.clampCursor(modes: modes)

        _ = oldCols
        _ = oldRows
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
        // Restore normal buffer cursor
        let saved = normalBuffer.restoreCursor()
        normalBuffer.cursorX = saved.x
        normalBuffer.cursorY = saved.y
        cursorAttribute = saved.attribute
        // Reset Kitty keyboard state on RMCUP
        keyboard.reset()
        pendingActions.append(.bufferActivated(isAlternate: false))
    }

    // MARK: - Cleanup

    public mutating func deallocate() {
        normalBuffer.deallocate()
        altBuffer.deallocate()
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

        let cell = Cell(
            codePoint: cp,
            attribute: cursorAttribute,
            width: 1,
            flags: [],
            payload: 0
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

        let width = UnicodeWidth.width(of: scalar)
        let cell = Cell(
            codePoint: scalar,
            attribute: cursorAttribute,
            width: UInt8(width),
            flags: [],
            payload: 0
        )
        buffer.insertCharacter(cell, modes: modes)
    }

    /// Handle a combining character by appending to the previous cell.
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
            }
        case 0x09: // HT - horizontal tab
            let nextTab = buffer.tabStops.nextStop(after: buffer.cursorX)
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
}
