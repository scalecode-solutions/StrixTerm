import Testing
@testable import FredTermCore

@Suite("Color Query Tests")
struct ColorQueryTests {
    // MARK: - Helpers

    private func makeState(cols: Int = 80, rows: Int = 24) -> TerminalState {
        TerminalState(cols: cols, rows: rows, maxScrollback: 0)
    }

    /// Extract all `.sendData` actions from pending actions as strings.
    private func sentResponses(_ state: TerminalState) -> [String] {
        state.pendingActions.compactMap { action in
            if case .sendData(let data) = action {
                return String(bytes: data, encoding: .utf8)
            }
            return nil
        }
    }

    /// Extract all `.colorChanged` actions from pending actions.
    private func colorChanges(_ state: TerminalState) -> [Int?] {
        state.pendingActions.compactMap { action in
            if case .colorChanged(let index) = action {
                return .some(index)
            }
            return nil
        }
    }

    // MARK: - OSC 10 (Foreground Color Query)

    @Test("OSC 10 query replies with foreground color")
    func testOsc10Query() {
        var state = makeState()
        defer { state.deallocate() }

        // Query foreground color
        state.feed(text: "\u{1b}]10;?\u{07}")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        // Response format: ESC ] 10 ; rgb:XX/XX/XX ESC \
        let response = responses.first!
        #expect(response.hasPrefix("\u{1b}]10;rgb:"))
        #expect(response.hasSuffix("\u{1b}\\"))
    }

    // MARK: - OSC 11 (Background Color Query)

    @Test("OSC 11 query replies with background color")
    func testOsc11Query() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]11;?\u{07}")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.first!
        #expect(response.hasPrefix("\u{1b}]11;rgb:"))
        #expect(response.hasSuffix("\u{1b}\\"))
    }

    @Test("OSC 10 and 11 queries both reply")
    func testOsc10And11Queries() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]10;?\u{07}")
        state.feed(text: "\u{1b}]11;?\u{07}")

        let responses = sentResponses(state)
        #expect(responses.count == 2)
        #expect(responses[0].contains("10;rgb:"))
        #expect(responses[1].contains("11;rgb:"))
    }

    // MARK: - OSC 4 (Palette Color Query)

    @Test("OSC 4 query replies with palette color")
    func testOsc4Query() {
        var state = makeState()
        defer { state.deallocate() }

        // Query color 1 (red)
        state.feed(text: "\u{1b}]4;1;?\u{07}")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.first!
        #expect(response.hasPrefix("\u{1b}]4;1;rgb:"))
        #expect(response.hasSuffix("\u{1b}\\"))
    }

    @Test("OSC 4 set color changes palette")
    func testOsc4SetColor() {
        var state = makeState()
        defer { state.deallocate() }

        // Set color 1 to a specific value
        state.feed(text: "\u{1b}]4;1;rgb:ff/00/ff\u{07}")

        let changes = colorChanges(state)
        #expect(changes.contains(where: { $0 == 1 }))
        #expect(state.palette.colors[1].r == 255)
        #expect(state.palette.colors[1].g == 0)
        #expect(state.palette.colors[1].b == 255)
    }

    // MARK: - OSC 104 (Reset Color)

    @Test("OSC 104 with no args resets all colors")
    func testOsc104ResetAll() {
        var state = makeState()
        defer { state.deallocate() }

        // Modify a color first
        state.feed(text: "\u{1b}]4;1;rgb:ff/ff/ff\u{07}")
        state.pendingActions.removeAll()

        // Reset all
        state.feed(text: "\u{1b}]104\u{07}")

        let changes = colorChanges(state)
        // nil index means all colors reset
        #expect(changes.contains(where: { $0 == nil }))
    }

    @Test("OSC 104 with index resets specific color")
    func testOsc104ResetSpecific() {
        var state = makeState()
        defer { state.deallocate() }

        // Modify color 5
        state.feed(text: "\u{1b}]4;5;rgb:ff/ff/ff\u{07}")
        state.pendingActions.removeAll()

        // Reset color 5
        state.feed(text: "\u{1b}]104;5\u{07}")

        let changes = colorChanges(state)
        #expect(changes.contains(where: { $0 == 5 }))
        // Should be back to xterm default
        let defaultColor = ColorPalette.xterm.colors[5]
        #expect(state.palette.colors[5] == defaultColor)
    }

    // MARK: - OSC 112 (Reset Cursor Color)

    @Test("OSC 112 resets cursor color")
    func testOsc112ResetCursorColor() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]112\u{07}")

        let cursorColorAction = state.pendingActions.first { action in
            if case .setCursorColor(nil) = action { return true }
            return false
        }
        #expect(cursorColorAction != nil)
    }

    // MARK: - OSC 10/11 Set Color

    @Test("OSC 10 set foreground color")
    func testOsc10SetColor() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]10;rgb:ff/00/ff\u{07}")

        let colorAction = state.pendingActions.first { action in
            if case .defaultColorChanged(let fg, _) = action, fg != nil {
                return true
            }
            return false
        }
        #expect(colorAction != nil)
        if case .defaultColorChanged(let fg, _) = colorAction {
            #expect(fg == .rgb(255, 0, 255))
        }
    }

    @Test("OSC 11 set background color")
    func testOsc11SetColor() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]11;rgb:00/ff/00\u{07}")

        let colorAction = state.pendingActions.first { action in
            if case .defaultColorChanged(_, let bg) = action, bg != nil {
                return true
            }
            return false
        }
        #expect(colorAction != nil)
        if case .defaultColorChanged(_, let bg) = colorAction {
            #expect(bg == .rgb(0, 255, 0))
        }
    }

    // MARK: - OSC 12 (Cursor Color)

    @Test("OSC 12 query replies with cursor color")
    func testOsc12Query() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]12;?\u{07}")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.first!
        #expect(response.hasPrefix("\u{1b}]12;rgb:"))
    }

    @Test("OSC 12 set cursor color")
    func testOsc12SetColor() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]12;rgb:aa/bb/cc\u{07}")

        let cursorColorAction = state.pendingActions.first { action in
            if case .setCursorColor = action { return true }
            return false
        }
        #expect(cursorColorAction != nil)
        if case .setCursorColor(let color) = cursorColorAction {
            #expect(color == .rgb(0xAA, 0xBB, 0xCC))
        }
    }

    // MARK: - Response Format

    @Test("Color query response uses 4-digit hex format")
    func testResponseFormat() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]10;?\u{07}")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        // The response should contain hex values in format XX/XX/XX (4-digit xterm style)
        let response = responses.first!
        // Extract the rgb part
        let rgbStart = response.range(of: "rgb:")!.upperBound
        let rgbEnd = response.range(of: "\u{1b}\\")!.lowerBound
        let rgb = String(response[rgbStart..<rgbEnd])
        let components = rgb.split(separator: "/")
        #expect(components.count == 3)
        // Each component should be a valid hex string
        for comp in components {
            #expect(UInt32(comp, radix: 16) != nil)
        }
    }

    // MARK: - OSC 110/111 Reset Default Colors

    @Test("OSC 110 resets foreground color")
    func testOsc110ResetForeground() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]110\u{07}")

        let action = state.pendingActions.first { action in
            if case .defaultColorChanged(let fg, let bg) = action,
               fg != nil && bg == nil {
                return true
            }
            return false
        }
        #expect(action != nil)
    }

    @Test("OSC 111 resets background color")
    func testOsc111ResetBackground() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]111\u{07}")

        let action = state.pendingActions.first { action in
            if case .defaultColorChanged(let fg, let bg) = action,
               fg == nil && bg != nil {
                return true
            }
            return false
        }
        #expect(action != nil)
    }
}
