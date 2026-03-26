import Testing
@testable import FredTermCore

@Suite("TerminalState Tests")
struct TerminalStateTests {
    @Test("Initial state")
    func initialState() {
        let state = TerminalState(cols: 80, rows: 25)
        #expect(state.cols == 80)
        #expect(state.rows == 25)
        #expect(!state.activeBufferIsAlt)
        #expect(state.buffer.cursorX == 0)
        #expect(state.buffer.cursorY == 0)
    }

    @Test("Feed printable text")
    func feedText() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "Hello")
        #expect(state.buffer.cursorX == 5)
        #expect(state.buffer.cursorY == 0)

        // Check cell contents
        let line = state.buffer.yBase
        #expect(state.buffer.grid[line, 0].codePoint == 0x48) // H
        #expect(state.buffer.grid[line, 1].codePoint == 0x65) // e
        #expect(state.buffer.grid[line, 2].codePoint == 0x6C) // l
        #expect(state.buffer.grid[line, 3].codePoint == 0x6C) // l
        #expect(state.buffer.grid[line, 4].codePoint == 0x6F) // o
    }

    @Test("Cursor movement CSI sequences")
    func cursorMovement() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Move cursor to (10, 5) with CUP
        state.feed(text: "\u{1b}[6;11H") // 1-based
        #expect(state.buffer.cursorX == 10)
        #expect(state.buffer.cursorY == 5)

        // CUU (cursor up) 3
        state.feed(text: "\u{1b}[3A")
        #expect(state.buffer.cursorY == 2)

        // CUF (cursor forward) 5
        state.feed(text: "\u{1b}[5C")
        #expect(state.buffer.cursorX == 15)
    }

    @Test("Line feed and scrolling")
    func linefeedScroll() {
        var state = TerminalState(cols: 10, rows: 3, maxScrollback: 100)
        defer { state.deallocate() }

        // Write lines that fill the screen
        state.feed(text: "Line1\n")
        state.feed(text: "Line2\n")
        state.feed(text: "Line3\n") // Should scroll

        // Cursor should be on line 2 (0-based), last visible
        #expect(state.buffer.cursorY == 2)
    }

    @Test("Erase in display")
    func eraseInDisplay() {
        var state = TerminalState(cols: 10, rows: 5)
        defer { state.deallocate() }

        // Fill first line
        state.feed(text: "ABCDEFGHIJ")
        // Move cursor to column 5
        state.feed(text: "\u{1b}[1;6H")

        // Erase from cursor to end (ED 0)
        state.feed(text: "\u{1b}[0J")

        let line = state.buffer.yBase
        #expect(state.buffer.grid[line, 0].codePoint == 0x41) // 'A' preserved
        #expect(state.buffer.grid[line, 4].codePoint == 0x45) // 'E' preserved
        #expect(state.buffer.grid[line, 5].isBlank)           // Erased
    }

    @Test("Erase in line")
    func eraseInLine() {
        var state = TerminalState(cols: 10, rows: 5)
        defer { state.deallocate() }

        state.feed(text: "ABCDEFGHIJ")
        state.feed(text: "\u{1b}[1;6H") // Move to col 5

        // Erase to left (EL 1)
        state.feed(text: "\u{1b}[1K")

        let line = state.buffer.yBase
        #expect(state.buffer.grid[line, 0].isBlank)           // Erased
        #expect(state.buffer.grid[line, 5].isBlank)           // Erased (inclusive)
        #expect(state.buffer.grid[line, 6].codePoint == 0x47) // 'G' preserved
    }

    @Test("SGR bold and colors")
    func sgrBoldColors() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Set bold + red foreground
        state.feed(text: "\u{1b}[1;31mX")

        let attr = state.attributes[state.buffer.grid[state.buffer.yBase, 0].attribute]
        #expect(attr.style.contains(.bold))
        #expect(attr.fg == .indexed(1)) // Red
    }

    @Test("SGR 256-color")
    func sgr256Color() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Set fg to color 200
        state.feed(text: "\u{1b}[38;5;200mX")

        let attr = state.attributes[state.buffer.grid[state.buffer.yBase, 0].attribute]
        #expect(attr.fg == .indexed(200))
    }

    @Test("SGR truecolor")
    func sgrTruecolor() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Set fg to RGB(100, 150, 200)
        state.feed(text: "\u{1b}[38;2;100;150;200mX")

        let attr = state.attributes[state.buffer.grid[state.buffer.yBase, 0].attribute]
        #expect(attr.fg == .rgb(100, 150, 200))
    }

    @Test("SGR reset")
    func sgrReset() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}[1;31mA\u{1b}[mB")

        let attrA = state.attributes[state.buffer.grid[state.buffer.yBase, 0].attribute]
        let attrB = state.attributes[state.buffer.grid[state.buffer.yBase, 1].attribute]

        #expect(attrA.style.contains(.bold))
        #expect(!attrB.style.contains(.bold))
        #expect(attrB.fg == .default)
    }

    @Test("Alternate buffer switch")
    func altBuffer() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "Normal")
        #expect(!state.activeBufferIsAlt)

        // Switch to alt buffer (DECSET 1049)
        state.feed(text: "\u{1b}[?1049h")
        #expect(state.activeBufferIsAlt)
        #expect(state.buffer.cursorX == 0)

        // Write to alt buffer
        state.feed(text: "Alt")
        #expect(state.buffer.cursorX == 3)

        // Switch back (DECRST 1049)
        state.feed(text: "\u{1b}[?1049l")
        #expect(!state.activeBufferIsAlt)
    }

    @Test("Scroll region")
    func scrollRegion() {
        var state = TerminalState(cols: 10, rows: 10)
        defer { state.deallocate() }

        // Set scroll region to lines 3-7 (1-based)
        state.feed(text: "\u{1b}[3;7r")
        #expect(state.buffer.scrollTop == 2)
        #expect(state.buffer.scrollBottom == 6)
    }

    @Test("OSC set title")
    func oscTitle() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]0;My Terminal\u{07}")

        let titleAction = state.pendingActions.first { action in
            if case .setTitle = action { return true }
            return false
        }
        #expect(titleAction != nil)
        if case .setTitle(let title) = titleAction {
            #expect(title == "My Terminal")
        }
    }

    @Test("OSC 133 semantic prompt")
    func osc133() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;A\u{07}")
        #expect(state.promptState.currentZone == .promptStart)

        state.feed(text: "\u{1b}]133;B\u{07}")
        #expect(state.promptState.currentZone == .commandStart)

        state.feed(text: "\u{1b}]133;C\u{07}")
        #expect(state.promptState.currentZone == .commandExecuted)

        state.feed(text: "\u{1b}]133;D;0\u{07}")
        #expect(state.promptState.currentZone == .commandFinished)
        #expect(state.promptState.lastExitCode == 0)
    }

    @Test("Tab handling")
    func tabHandling() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "AB\tCD")
        #expect(state.buffer.cursorX == 10) // Tab to col 8, then C at 8, D at 9
    }

    @Test("Backspace")
    func backspace() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "ABC\u{08}")
        #expect(state.buffer.cursorX == 2)
    }

    @Test("Carriage return")
    func carriageReturn() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "ABCDE\r")
        #expect(state.buffer.cursorX == 0)
    }

    @Test("DECALN fills with E")
    func decaln() {
        var state = TerminalState(cols: 5, rows: 3)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}#8") // DECALN
        for row in 0..<3 {
            for col in 0..<5 {
                let cell = state.buffer.grid[state.buffer.yBase + row, col]
                #expect(cell.codePoint == 0x45) // 'E'
            }
        }
    }

    @Test("Cursor save and restore")
    func cursorSaveRestore() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}[10;20H") // Move to (19, 9)
        state.feed(text: "\u{1b}7")        // DECSC
        state.feed(text: "\u{1b}[1;1H")   // Move to (0, 0)
        state.feed(text: "\u{1b}8")        // DECRC

        #expect(state.buffer.cursorX == 19)
        #expect(state.buffer.cursorY == 9)
    }

    @Test("Kitty keyboard push/pop/query")
    func kittyKeyboard() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Push flags
        state.feed(text: "\u{1b}[>1u") // Push disambiguate
        #expect(state.keyboard.isActive)
        #expect(state.keyboard.currentFlags.contains(.disambiguateEscapeCodes))

        // Query
        state.feed(text: "\u{1b}[?u")
        let queryAction = state.pendingActions.first { action in
            if case .sendData = action { return true }
            return false
        }
        #expect(queryAction != nil)

        // Pop
        state.feed(text: "\u{1b}[<u")
        #expect(!state.keyboard.isActive)
    }

    @Test("Cursor style change")
    func cursorStyleChange() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}[5 q") // Blinking bar
        #expect(state.cursorStyle == .blinkBar)

        state.feed(text: "\u{1b}[2 q") // Steady block
        #expect(state.cursorStyle == .steadyBlock)
    }

    @Test("Wide character handling")
    func wideCharacters() {
        var state = TerminalState(cols: 10, rows: 5)
        defer { state.deallocate() }

        state.feed(text: "你") // Wide CJK character
        #expect(state.buffer.cursorX == 2)

        let line = state.buffer.yBase
        let cell = state.buffer.grid[line, 0]
        #expect(cell.codePoint == 0x4F60) // 你
        #expect(cell.width == 2)

        // Continuation cell
        let cont = state.buffer.grid[line, 1]
        #expect(cont.flags.contains(.wideContinuation))
        #expect(cont.width == 0)
    }

    @Test("Insert/Delete characters")
    func insertDeleteChars() {
        var state = TerminalState(cols: 10, rows: 5)
        defer { state.deallocate() }

        state.feed(text: "ABCDE")
        state.feed(text: "\u{1b}[1;3H")  // Move to col 2
        state.feed(text: "\u{1b}[2@")    // Insert 2 chars

        let line = state.buffer.yBase
        #expect(state.buffer.grid[line, 0].codePoint == 0x41) // A
        #expect(state.buffer.grid[line, 1].codePoint == 0x42) // B
        #expect(state.buffer.grid[line, 2].isBlank)            // Inserted
        #expect(state.buffer.grid[line, 3].isBlank)            // Inserted
        #expect(state.buffer.grid[line, 4].codePoint == 0x43) // C shifted
    }

    @Test("Device status report")
    func deviceStatusReport() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}[10;20H") // Move to row 10, col 20
        state.pendingActions.removeAll()
        state.feed(text: "\u{1b}[6n")     // DSR cursor position

        let sendAction = state.pendingActions.first { action in
            if case .sendData = action { return true }
            return false
        }
        #expect(sendAction != nil)
        if case .sendData(let data) = sendAction {
            let response = String(bytes: data, encoding: .utf8) ?? ""
            #expect(response == "\u{1b}[10;20R")
        }
    }

    @Test("Soft reset")
    func softReset() {
        var state = TerminalState(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Set some modes
        state.feed(text: "\u{1b}[?7l")    // Disable wraparound
        state.feed(text: "\u{1b}[4h")     // Enable insert mode
        #expect(!state.modes.wraparound)
        #expect(state.modes.insertMode)

        // Soft reset
        state.feed(text: "\u{1b}[!p")
        #expect(state.modes.wraparound)    // Back to default
        #expect(!state.modes.insertMode)   // Back to default
    }
}

@Suite("Terminal Public API Tests")
struct TerminalPublicTests {
    @Test("Terminal creation and feed")
    func terminalCreation() {
        let terminal = Terminal(cols: 80, rows: 25)
        terminal.feed(text: "Hello, World!")

        let pos = terminal.cursorPosition
        #expect(pos.col == 13)
        #expect(pos.row == 0)
    }

    @Test("Terminal line text")
    func lineText() {
        let terminal = Terminal(cols: 80, rows: 25)
        terminal.feed(text: "FredTerm")

        let text = terminal.lineText(0)
        #expect(text == "FredTerm")
    }

    @Test("Terminal snapshot")
    func snapshot() {
        let terminal = Terminal(cols: 10, rows: 3)
        terminal.feed(text: "ABC")

        let snap = terminal.snapshot()
        #expect(snap.cols == 10)
        #expect(snap.rows == 3)
        #expect(snap.cursorPosition.col == 3)
        #expect(snap.cell(at: Position(col: 0, row: 0)).codePoint == 0x41) // A
    }

    @Test("Terminal visible text")
    func visibleText() {
        let terminal = Terminal(cols: 10, rows: 3)
        terminal.feed(text: "Line1\nLine2\nLine3")

        let text = terminal.visibleText()
        #expect(text.contains("Line1"))
        #expect(text.contains("Line2"))
        #expect(text.contains("Line3"))
    }

    @Test("Terminal resize")
    func resize() {
        let terminal = Terminal(cols: 80, rows: 25)
        terminal.resize(cols: 40, rows: 10)
        #expect(terminal.size.cols == 40)
        #expect(terminal.size.rows == 10)
    }
}
