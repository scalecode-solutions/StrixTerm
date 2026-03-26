/// ESC (Escape) sequence command implementations.
extension TerminalState {
    mutating func dispatchESC(intermediates: IntermediateBuffer, final: UInt8) {
        let inter = intermediates.first

        switch (final, inter) {
        // Index / Reverse Index
        case (0x44, 0): // IND - Index (move down, scroll if needed)
            buffer.linefeed(modes: modes, actions: &pendingActions)
        case (0x45, 0): // NEL - Next Line
            buffer.cursorX = 0
            buffer.linefeed(modes: modes, actions: &pendingActions)
        case (0x4D, 0): // RI - Reverse Index
            buffer.reverseIndex(modes: modes, actions: &pendingActions)

        // Tab set
        case (0x48, 0): // HTS - Horizontal Tab Set
            buffer.tabStops.set(buffer.cursorX)

        // Cursor save/restore
        case (0x37, 0): // DECSC - Save Cursor
            buffer.saveCursor(attribute: cursorAttribute, modes: modes)
        case (0x38, 0): // DECRC - Restore Cursor
            let saved = buffer.restoreCursor()
            buffer.cursorX = saved.x
            buffer.cursorY = saved.y
            cursorAttribute = saved.attribute
            modes.originMode = saved.originMode
            modes.wraparound = saved.wraparound

        // Character set designation
        case (_, 0x28): // G0 designation: ESC ( <final>
            charsets.setCharset(at: 0, to: CharsetState.from(final: final))
        case (_, 0x29): // G1 designation: ESC ) <final>
            charsets.setCharset(at: 1, to: CharsetState.from(final: final))
        case (_, 0x2A): // G2 designation: ESC * <final>
            charsets.setCharset(at: 2, to: CharsetState.from(final: final))
        case (_, 0x2B): // G3 designation: ESC + <final>
            charsets.setCharset(at: 3, to: CharsetState.from(final: final))

        // Single shifts
        case (0x4E, 0): // SS2 - Single Shift 2
            charsets.singleShift = 2
        case (0x4F, 0): // SS3 - Single Shift 3
            charsets.singleShift = 3

        // Locking shifts
        case (0x6E, 0): // LS2 - Locking Shift 2
            charsets.activeGL = 2
        case (0x6F, 0): // LS3 - Locking Shift 3
            charsets.activeGL = 3
        case (0x7E, 0): // LS1R - Locking Shift 1 Right
            charsets.activeGR = 1
        case (0x7D, 0): // LS2R - Locking Shift 2 Right
            charsets.activeGR = 2
        case (0x7C, 0): // LS3R - Locking Shift 3 Right
            charsets.activeGR = 3

        // Keypad modes
        case (0x3D, 0): // DECKPAM - Application Keypad
            modes.applicationKeypad = true
        case (0x3E, 0): // DECKPNM - Normal Keypad
            modes.applicationKeypad = false

        // Full reset
        case (0x63, 0): // RIS - Reset Initial State
            fullReset()

        // DECALN - Screen Alignment Display
        case (0x38, 0x23): // ESC # 8
            decAlignmentTest()

        // Double-width/height line modes
        case (0x33, 0x23): // ESC # 3 - DECDHL top half
            buffer.grid[lineMetadata: buffer.absoluteCursorY].renderMode = .doubleHeightTop
        case (0x34, 0x23): // ESC # 4 - DECDHL bottom half
            buffer.grid[lineMetadata: buffer.absoluteCursorY].renderMode = .doubleHeightBottom
        case (0x35, 0x23): // ESC # 5 - DECSWL single width
            buffer.grid[lineMetadata: buffer.absoluteCursorY].renderMode = .normal
        case (0x36, 0x23): // ESC # 6 - DECDWL double width
            buffer.grid[lineMetadata: buffer.absoluteCursorY].renderMode = .doubleWidth

        default:
            break
        }
    }

    // MARK: - Full Reset

    private mutating func fullReset() {
        modes = TerminalModes()
        cursorAttribute = 0
        cursorStyle = .blinkBlock
        charsets = CharsetState()
        keyboard.reset()
        promptState = SemanticPromptState()

        // Reset normal buffer
        normalBuffer.scrollTop = 0
        normalBuffer.scrollBottom = rows - 1
        normalBuffer.marginLeft = 0
        normalBuffer.marginRight = cols - 1
        normalBuffer.cursorX = 0
        normalBuffer.cursorY = 0
        normalBuffer.yBase = 0
        normalBuffer.yDisp = 0
        normalBuffer.linesTop = 0
        normalBuffer.tabStops = TabStops(width: cols)
        normalBuffer.savedCursor = SavedCursorState()

        // Clear visible area
        for line in 0..<rows {
            normalBuffer.grid.clearLine(normalBuffer.yBase + line)
        }

        // Switch to normal buffer
        activeBufferIsAlt = false

        // Reset alt buffer
        altBuffer.scrollTop = 0
        altBuffer.scrollBottom = rows - 1
        altBuffer.marginLeft = 0
        altBuffer.marginRight = cols - 1
        altBuffer.cursorX = 0
        altBuffer.cursorY = 0
        altBuffer.tabStops = TabStops(width: cols)
        altBuffer.savedCursor = SavedCursorState()

        pendingActions.append(.cursorStyleChanged(cursorStyle))
        pendingActions.append(.showCursor)
    }

    // MARK: - DECALN

    private mutating func decAlignmentTest() {
        // Fill screen with 'E' characters
        let attr = attributes.intern(.default)
        let eCell = Cell(
            codePoint: 0x45, // 'E'
            attribute: attr,
            width: 1,
            flags: [],
            payload: 0
        )
        for line in 0..<rows {
            for col in 0..<cols {
                buffer.grid[buffer.yBase + line, col] = eCell
            }
        }
        buffer.cursorX = 0
        buffer.cursorY = 0
    }
}
