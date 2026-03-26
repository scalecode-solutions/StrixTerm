/// CSI (Control Sequence Introducer) command implementations.
///
/// Each CSI command is a focused method on TerminalState, split from
/// SwiftTerm's monolithic Terminal.swift.
extension TerminalState {
    mutating func dispatchCSI(
        params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8
    ) {
        let priv = intermediates.first

        switch (final, priv) {
        // Cursor movement
        case (0x41, 0): csiCursorUp(params)          // CUU
        case (0x42, 0): csiCursorDown(params)        // CUD
        case (0x43, 0): csiCursorForward(params)     // CUF
        case (0x44, 0): csiCursorBackward(params)    // CUB
        case (0x45, 0): csiCursorNextLine(params)    // CNL
        case (0x46, 0): csiCursorPreviousLine(params) // CPL
        case (0x47, 0): csiCursorCharAbsolute(params) // CHA
        case (0x48, 0): csiCursorPosition(params)    // CUP
        case (0x49, 0): csiCursorForwardTab(params)  // CHT
        case (0x5A, 0): csiCursorBackwardTab(params) // CBT
        case (0x60, 0): csiCursorCharAbsolute(params) // HPA
        case (0x64, 0): csiLinePositionAbsolute(params) // VPA
        case (0x66, 0): csiCursorPosition(params)    // HVP

        // Erase
        case (0x4A, 0): csiEraseInDisplay(params)    // ED
        case (0x4A, 0x3F): csiEraseInDisplay(params) // DECSED
        case (0x4B, 0): csiEraseInLine(params)       // EL
        case (0x4B, 0x3F): csiEraseInLine(params)    // DECSEL

        // Insert/Delete
        case (0x40, 0): csiInsertChars(params)       // ICH
        case (0x4C, 0): csiInsertLines(params)       // IL
        case (0x4D, 0): csiDeleteLines(params)       // DL
        case (0x50, 0): csiDeleteChars(params)       // DCH
        case (0x58, 0): csiEraseChars(params)        // ECH

        // Scroll
        case (0x53, 0): csiScrollUp(params)          // SU
        case (0x54, 0): csiScrollDown(params)        // SD

        // SGR (Select Graphic Rendition)
        case (0x6D, 0): csiSGR(params)               // SGR

        // Mode set/reset
        case (0x68, 0): csiSetMode(params)           // SM
        case (0x68, 0x3F): csiSetDecMode(params)     // DECSET
        case (0x6C, 0): csiResetMode(params)         // RM
        case (0x6C, 0x3F): csiResetDecMode(params)   // DECRST

        // Scroll region
        case (0x72, 0): csiSetScrollRegion(params)   // DECSTBM
        case (0x73, 0): csiSetLeftRightMargin(params) // DECSLRM (if margin mode)

        // Device status
        case (0x6E, 0): csiDeviceStatus(params)      // DSR
        case (0x6E, 0x3F): csiDecDeviceStatus(params) // DECDSR
        case (0x63, 0): csiDeviceAttributes(params)  // DA1
        case (0x63, 0x3E): csiSecondaryDA(params)    // DA2
        case (0x63, 0x3D): csiTertiaryDA()           // DA3

        // Tabulation
        case (0x67, 0): csiTabClear(params)          // TBC

        // Repeat
        case (0x62, 0): csiRepeatChar(params)        // REP

        // Window manipulation
        case (0x74, 0): csiWindowManipulation(params) // XTWINOPS

        // Soft terminal reset
        case (0x70, 0x21): csiSoftReset()            // DECSTR

        // Cursor style (DECSCUSR)
        case (0x71, 0x20): csiSetCursorStyle(params) // DECSCUSR

        // Kitty keyboard protocol
        case (0x75, 0x3E): csiPushKeyboardMode(params)    // CSI > flags u
        case (0x75, 0x3C): csiPopKeyboardMode(params)     // CSI < count u
        case (0x75, 0x3F): csiQueryKeyboardMode()         // CSI ? u
        case (0x75, 0x3D): csiSetKeyboardMode(params)     // CSI = flags ; mode u
        case (0x75, 0): csiRestoreCursor()                  // SCORC (CSI u = restore cursor)

        // Modify Other Keys (XTMODKEYS)
        case (0x6D, 0x3E): csiSetModifyOtherKeys(params)  // CSI > Pm m

        default:
            break
        }
    }

    // MARK: - Cursor Movement

    private mutating func csiCursorUp(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.cursorY = max(buffer.scrollTop, buffer.cursorY - n)
    }

    private mutating func csiCursorDown(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.cursorY = min(buffer.scrollBottom, buffer.cursorY + n)
    }

    private mutating func csiCursorForward(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        let right = modes.marginMode ? buffer.marginRight : cols - 1
        buffer.cursorX = min(right, buffer.cursorX + n)
    }

    private mutating func csiCursorBackward(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        let left = modes.marginMode ? buffer.marginLeft : 0
        buffer.cursorX = max(left, buffer.cursorX - n)
    }

    private mutating func csiCursorNextLine(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.cursorY = min(buffer.scrollBottom, buffer.cursorY + n)
        buffer.cursorX = modes.marginMode ? buffer.marginLeft : 0
    }

    private mutating func csiCursorPreviousLine(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.cursorY = max(buffer.scrollTop, buffer.cursorY - n)
        buffer.cursorX = modes.marginMode ? buffer.marginLeft : 0
    }

    private mutating func csiCursorCharAbsolute(_ params: ParamBuffer) {
        let col = max(1, Int(params.value(0, default: 1))) - 1
        buffer.cursorX = min(col, cols - 1)
    }

    private mutating func csiCursorPosition(_ params: ParamBuffer) {
        let row = max(1, Int(params.value(0, default: 1))) - 1
        let col = max(1, Int(params.value(1, default: 1))) - 1

        let top = modes.originMode ? buffer.scrollTop : 0
        let left = (modes.originMode && modes.marginMode) ? buffer.marginLeft : 0
        let right = (modes.originMode && modes.marginMode) ? buffer.marginRight : cols - 1
        buffer.cursorY = min(top + row, buffer.scrollBottom)
        buffer.cursorX = min(left + col, right)
    }

    private mutating func csiLinePositionAbsolute(_ params: ParamBuffer) {
        let row = max(1, Int(params.value(0, default: 1))) - 1
        let top = modes.originMode ? buffer.scrollTop : 0
        buffer.cursorY = min(top + row, buffer.scrollBottom)
    }

    private mutating func csiCursorForwardTab(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        for _ in 0..<n {
            buffer.cursorX = buffer.tabStops.nextStop(after: buffer.cursorX)
        }
    }

    private mutating func csiCursorBackwardTab(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        for _ in 0..<n {
            buffer.cursorX = buffer.tabStops.previousStop(before: buffer.cursorX)
        }
    }

    // MARK: - Erase

    private mutating func csiEraseInDisplay(_ params: ParamBuffer) {
        let mode = Int(params.value(0, default: 0))
        buffer.eraseInDisplay(mode: mode, fillAttribute: cursorAttribute)
    }

    private mutating func csiEraseInLine(_ params: ParamBuffer) {
        let mode = Int(params.value(0, default: 0))
        buffer.eraseInLine(mode: mode, fillAttribute: cursorAttribute)
    }

    // MARK: - Insert/Delete

    private mutating func csiInsertChars(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        let right = modes.marginMode ? buffer.marginRight + 1 : cols
        buffer.grid.insertCells(
            line: buffer.absoluteCursorY, at: buffer.cursorX, count: n,
            rightMargin: right, fillAttribute: cursorAttribute)
    }

    private mutating func csiDeleteChars(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        let right = modes.marginMode ? buffer.marginRight + 1 : cols
        buffer.grid.deleteCells(
            line: buffer.absoluteCursorY, at: buffer.cursorX, count: n,
            rightMargin: right, fillAttribute: cursorAttribute)
    }

    private mutating func csiEraseChars(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.grid.clearCells(
            line: buffer.absoluteCursorY, from: buffer.cursorX,
            to: buffer.cursorX + n, fillAttribute: cursorAttribute)
    }

    private mutating func csiInsertLines(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        // Only works if cursor is in scroll region
        if buffer.cursorY >= buffer.scrollTop && buffer.cursorY <= buffer.scrollBottom {
            let bottom = buffer.scrollBottom + buffer.yBase + 1
            let top = buffer.cursorY + buffer.yBase
            buffer.grid.scrollRegionDown(
                top: top, bottom: bottom, count: n, fillAttribute: cursorAttribute)
        }
    }

    private mutating func csiDeleteLines(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        if buffer.cursorY >= buffer.scrollTop && buffer.cursorY <= buffer.scrollBottom {
            let bottom = buffer.scrollBottom + buffer.yBase + 1
            let top = buffer.cursorY + buffer.yBase
            buffer.grid.scrollRegionUp(
                top: top, bottom: bottom, count: n, fillAttribute: cursorAttribute)
        }
    }

    // MARK: - Scroll

    private mutating func csiScrollUp(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.scroll(up: n, modes: modes)
    }

    private mutating func csiScrollDown(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        buffer.scrollDown(n, modes: modes)
    }

    // MARK: - Scroll Region

    private mutating func csiSetScrollRegion(_ params: ParamBuffer) {
        let top = max(0, Int(params.value(0, default: 1)) - 1)
        let bottom = min(rows - 1, Int(params.value(1, default: Int32(rows))) - 1)
        if top < bottom {
            buffer.scrollTop = top
            buffer.scrollBottom = bottom
            // DECOM: cursor moves to home
            buffer.cursorX = modes.originMode ? buffer.marginLeft : 0
            buffer.cursorY = modes.originMode ? buffer.scrollTop : 0
        }
    }

    private mutating func csiSetLeftRightMargin(_ params: ParamBuffer) {
        guard modes.marginMode else {
            // If margin mode is not set, CSI s is "save cursor"
            buffer.saveCursor(attribute: cursorAttribute, modes: modes)
            return
        }
        let left = max(0, Int(params.value(0, default: 1)) - 1)
        let right = min(cols - 1, Int(params.value(1, default: Int32(cols))) - 1)
        if left < right {
            buffer.marginLeft = left
            buffer.marginRight = right
            buffer.cursorX = modes.originMode ? left : 0
            buffer.cursorY = modes.originMode ? buffer.scrollTop : 0
        }
    }

    // MARK: - Mode Set/Reset

    private mutating func csiSetMode(_ params: ParamBuffer) {
        for i in 0..<params.count {
            let p = params.value(i)
            switch p {
            case 4: modes.insertMode = true      // IRM
            case 20: modes.autoNewline = true     // LNM
            default: break
            }
        }
    }

    private mutating func csiResetMode(_ params: ParamBuffer) {
        for i in 0..<params.count {
            let p = params.value(i)
            switch p {
            case 4: modes.insertMode = false
            case 20: modes.autoNewline = false
            default: break
            }
        }
    }

    private mutating func csiSetDecMode(_ params: ParamBuffer) {
        for i in 0..<params.count {
            setDecMode(Int(params.value(i)), value: true)
        }
    }

    private mutating func csiResetDecMode(_ params: ParamBuffer) {
        for i in 0..<params.count {
            setDecMode(Int(params.value(i)), value: false)
        }
    }

    private mutating func setDecMode(_ mode: Int, value: Bool) {
        switch mode {
        case 1: modes.applicationCursor = value       // DECCKM
        case 3: // DECCOLM
            if value {
                pendingActions.append(.requestResize(cols: 132, rows: rows))
            } else {
                pendingActions.append(.requestResize(cols: 80, rows: rows))
            }
        case 5: modes.reverseVideo = value             // DECSCNM
        case 6: // DECOM
            modes.originMode = value
            buffer.cursorX = modes.originMode ? buffer.marginLeft : 0
            buffer.cursorY = modes.originMode ? buffer.scrollTop : 0
        case 7: modes.wraparound = value               // DECAWM
        case 8: modes.autoRepeat = value               // DECARM
        case 25: modes.cursorVisible = value           // DECTCEM
            pendingActions.append(value ? .showCursor : .hideCursor)
        case 45: modes.reverseWraparound = value       // Reverse wraparound
        case 47: // Switch normal/alt buffer (no clear)
            if value { activateAltBuffer() } else { deactivateAltBuffer() }
        case 66: modes.applicationKeypad = value       // DECNKM
        case 69: // DECLRMM
            modes.marginMode = value
            if !value {
                buffer.marginLeft = 0
                buffer.marginRight = cols - 1
            }
        case 1000: modes.mouseMode = value ? .vt200 : .off
            pendingActions.append(.mouseModeChanged(modes.mouseMode))
        case 1002: modes.mouseMode = value ? .buttonEvent : .off
            pendingActions.append(.mouseModeChanged(modes.mouseMode))
        case 1003: modes.mouseMode = value ? .anyEvent : .off
            pendingActions.append(.mouseModeChanged(modes.mouseMode))
        case 1004: modes.sendFocus = value
            pendingActions.append(.focusModeChanged(value))
        case 1005: modes.mouseEncoding = value ? .utf8 : .x10
        case 1006: modes.mouseEncoding = value ? .sgr : .x10
        case 1015: modes.mouseEncoding = value ? .urxvt : .x10
        case 1016: modes.mouseEncoding = value ? .sgrPixels : .x10
        case 1047: // Switch buffer (with clear on switch to alt)
            if value { activateAltBuffer() } else { deactivateAltBuffer() }
        case 1048: // Save/restore cursor
            if value {
                buffer.saveCursor(attribute: cursorAttribute, modes: modes)
            } else {
                let saved = buffer.restoreCursor()
                buffer.cursorX = saved.x
                buffer.cursorY = saved.y
                cursorAttribute = saved.attribute
            }
        case 1049: // Combined 1047 + 1048
            if value {
                buffer.saveCursor(attribute: cursorAttribute, modes: modes)
                activateAltBuffer()
            } else {
                deactivateAltBuffer()
                let saved = normalBuffer.restoreCursor()
                normalBuffer.cursorX = saved.x
                normalBuffer.cursorY = saved.y
                cursorAttribute = saved.attribute
            }
        case 2004: modes.bracketedPaste = value
            pendingActions.append(.bracketedPasteModeChanged(value))
        case 2026: modes.synchronizedOutput = value
        case 9: modes.mouseMode = value ? .x10 : .off
            pendingActions.append(.mouseModeChanged(modes.mouseMode))
        default:
            break
        }
    }

    // MARK: - Device Status

    private mutating func csiDeviceStatus(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        switch p {
        case 5: // Status report
            sendResponse("\u{1b}[0n")
        case 6: // Cursor position report
            let row = buffer.cursorY + 1
            let col = buffer.cursorX + 1
            sendResponse("\u{1b}[\(row);\(col)R")
        default:
            break
        }
    }

    private mutating func csiDecDeviceStatus(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        switch p {
        case 6: // Extended cursor position
            let row = buffer.cursorY + 1
            let col = buffer.cursorX + 1
            sendResponse("\u{1b}[?\(row);\(col)R")
        case 15: // Printer status
            sendResponse("\u{1b}[?13n") // No printer
        case 25: // User-defined key status
            sendResponse("\u{1b}[?20n") // UDK unlocked
        case 26: // Keyboard language
            sendResponse("\u{1b}[?27;1n") // North American
        default:
            break
        }
    }

    private mutating func csiDeviceAttributes(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        if p == 0 {
            // Report as VT520 with lots of capabilities
            sendResponse("\u{1b}[?62;22c")
        }
    }

    private mutating func csiSecondaryDA(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        if p == 0 {
            sendResponse("\u{1b}[>0;100;0c")
        }
    }

    private mutating func csiTertiaryDA() {
        sendResponse("\u{1b}P!|00000000\u{1b}\\")
    }

    // MARK: - Tab Clear

    private mutating func csiTabClear(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        switch p {
        case 0: buffer.tabStops.clear(buffer.cursorX)
        case 3: buffer.tabStops.clearAll()
        default: break
        }
    }

    // MARK: - Repeat

    private mutating func csiRepeatChar(_ params: ParamBuffer) {
        let n = max(1, Int(params.value(0, default: 1)))
        // Repeat the last printed character
        let lineIdx = buffer.absoluteCursorY
        let col = max(0, buffer.cursorX - 1)
        let cell = buffer.grid[lineIdx, col]
        for _ in 0..<n {
            buffer.insertCharacter(cell, modes: modes)
        }
    }

    // MARK: - Window Manipulation

    private mutating func csiWindowManipulation(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        switch p {
        case 1: pendingActions.append(.windowCommand(.deiconify))
        case 2: pendingActions.append(.windowCommand(.iconify))
        case 3:
            let x = Int(params.value(1, default: 0))
            let y = Int(params.value(2, default: 0))
            pendingActions.append(.windowCommand(.moveWindow(x: x, y: y)))
        case 4:
            let h = Int(params.value(1, default: 0))
            let w = Int(params.value(2, default: 0))
            pendingActions.append(.windowCommand(.resizePixels(width: w, height: h)))
        case 5: pendingActions.append(.windowCommand(.raise))
        case 6: pendingActions.append(.windowCommand(.lower))
        case 8:
            let r = Int(params.value(1, default: 0))
            let c = Int(params.value(2, default: 0))
            pendingActions.append(.windowCommand(.resizeChars(cols: c, rows: r)))
        case 11: pendingActions.append(.windowCommand(.reportState))
        case 13: pendingActions.append(.windowCommand(.reportPosition))
        case 14: pendingActions.append(.windowCommand(.reportPixelSize))
        case 18: // Report terminal size in chars
            sendResponse("\u{1b}[8;\(rows);\(cols)t")
        case 19: pendingActions.append(.windowCommand(.reportScreenSize))
        case 20: pendingActions.append(.windowCommand(.reportIconTitle))
        case 21: pendingActions.append(.windowCommand(.reportTitle))
        default:
            break
        }
    }

    // MARK: - Soft Reset

    private mutating func csiSoftReset() {
        modes = TerminalModes()
        cursorAttribute = 0
        buffer.scrollTop = 0
        buffer.scrollBottom = rows - 1
        buffer.marginLeft = 0
        buffer.marginRight = cols - 1
        buffer.cursorX = 0
        buffer.cursorY = 0
        charsets = CharsetState()
        keyboard.reset()
    }

    // MARK: - Cursor Style

    private mutating func csiSetCursorStyle(_ params: ParamBuffer) {
        let p = Int(params.value(0, default: 0))
        switch p {
        case 0, 1: cursorStyle = .blinkBlock
        case 2: cursorStyle = .steadyBlock
        case 3: cursorStyle = .blinkUnderline
        case 4: cursorStyle = .steadyUnderline
        case 5: cursorStyle = .blinkBar
        case 6: cursorStyle = .steadyBar
        default: break
        }
        pendingActions.append(.cursorStyleChanged(cursorStyle))
    }

    // MARK: - Kitty Keyboard Protocol

    private mutating func csiPushKeyboardMode(_ params: ParamBuffer) {
        let rawFlags = UInt32(params.value(0, default: 0))
        let flags = KittyKeyboardFlags(rawValue: rawFlags).intersection(.knownMask)
        keyboard.push(flags)
    }

    private mutating func csiPopKeyboardMode(_ params: ParamBuffer) {
        let count = max(1, Int(params.value(0, default: 1)))
        keyboard.pop(count)
    }

    private mutating func csiQueryKeyboardMode() {
        sendResponse("\u{1b}[?\(keyboard.currentFlags.rawValue)u")
    }

    private mutating func csiSetKeyboardMode(_ params: ParamBuffer) {
        let rawFlags = UInt32(params.value(0, default: 0))
        let mode = Int(params.value(1, default: 1))
        let newFlags = KittyKeyboardFlags(rawValue: rawFlags).intersection(.knownMask)

        // Only modes 1 (set), 2 (union), 3 (subtract) are valid
        guard mode >= 1 && mode <= 3 else { return }
        keyboard.setFlags(newFlags, mode: mode)
    }

    private mutating func csiKittyKeyResponse(_ params: ParamBuffer) {
        // Key event in Kitty protocol format - handled at the input layer
    }

    /// SCORC - Save Cursor (CSI s when not in margin mode) / Restore Cursor (CSI u)
    private mutating func csiRestoreCursor() {
        let saved = buffer.restoreCursor()
        buffer.cursorX = saved.x
        buffer.cursorY = saved.y
        cursorAttribute = saved.attribute
    }

    // MARK: - XTMODKEYS

    private mutating func csiSetModifyOtherKeys(_ params: ParamBuffer) {
        let mode = Int(params.value(0, default: 0))
        let value = Int(params.value(1, default: 0))
        if mode == 4 {
            keyboard.modifyOtherKeys = value
        }
    }

    // MARK: - Response helper

    mutating func sendResponse(_ text: String) {
        pendingActions.append(.sendData(Array(text.utf8)))
    }
}
