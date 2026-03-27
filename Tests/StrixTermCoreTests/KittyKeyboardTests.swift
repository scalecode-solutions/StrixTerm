import Testing
@testable import StrixTermCore

@Suite("Kitty Keyboard Protocol Tests")
struct KittyKeyboardTests {
    private let esc = "\u{1b}"

    private func makeState(cols: Int = 20, rows: Int = 10) -> TerminalState {
        TerminalState(cols: cols, rows: rows)
    }

    // MARK: - Push / Pop / Query

    @Test("Push keyboard mode sets flags")
    func testPushSetsFlags() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[>1u") // Push disambiguate
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Pop keyboard mode restores previous flags")
    func testPopRestoresPrevious() {
        var s = makeState()
        defer { s.deallocate() }

        // Set initial flags
        s.feed(text: "\(esc)[=1;1u") // Set disambiguate
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])

        s.feed(text: "\(esc)[>8u") // Push reportAllKeys
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[<u") // Pop
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Query returns current flags")
    func testQueryReturnsFlags() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=5;1u") // disambiguate + reportAlternate = 1 + 4 = 5
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes, .reportAlternateKeys])

        s.feed(text: "\(esc)[?u") // Query

        let sendAction = s.pendingActions.compactMap { action -> [UInt8]? in
            if case .sendData(let data) = action { return data }
            return nil
        }.last

        let response = sendAction.map { String(decoding: $0, as: UTF8.self) }
        #expect(response == "\(esc)[?5u")
    }

    // MARK: - Set mode (CSI = flags ; mode u)

    @Test("Set mode replaces current flags")
    func testSetModeReplace() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u") // mode 1 = set
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Set mode invalid is ignored")
    func testSetModeInvalid() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u")
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])

        // Invalid mode (9)
        s.feed(text: "\(esc)[=2;9u")
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    // MARK: - Pop semantics

    @Test("Pop with no params defaults to 1")
    func testPopNoParamsDefaultsToOne() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u")
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])

        s.feed(text: "\(esc)[>8u") // Push reportAllKeys
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[<u") // Pop 1
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Pop zero also defaults to 1")
    func testPopZeroDefaultsToOne() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u")
        s.feed(text: "\(esc)[>8u")
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[<0u") // Pop 0 = defaults to 1
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Push pop restores previous state")
    func testPushPopRestores() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u")
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])

        s.feed(text: "\(esc)[>8u") // Push reportAllKeys
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[>4u") // Push reportAlternates
        #expect(s.keyboard.currentFlags == [.reportAlternateKeys])

        s.feed(text: "\(esc)[<2u") // Pop 2
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Pop too many clears state")
    func testPopTooManyClearsState() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u")
        s.feed(text: "\(esc)[>8u")
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[<3u") // More pops than stack entries
        #expect(s.keyboard.currentFlags.isEmpty)
    }

    @Test("Push beyond stack limit drops oldest")
    func testPushBeyondStackLimit() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[=1;1u")
        s.feed(text: "\(esc)[>4u") // Push reportAlternates

        for _ in 0..<15 {
            s.feed(text: "\(esc)[>8u")
        }

        s.feed(text: "\(esc)[>8u")
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[<16u")
        #expect(s.keyboard.currentFlags == [.reportAlternateKeys])
    }

    // MARK: - Cursor interaction (CSI u without prefix = cursor restore)

    @Test("Plain CSI u restores cursor")
    func testPlainCsiURestoresCursor() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[3;3H")  // Move to (2,2)
        s.feed(text: "\(esc)7")       // DECSC
        s.feed(text: "\(esc)[8;8H")  // Move to (7,7)
        #expect(s.buffer.cursorX == 7)
        #expect(s.buffer.cursorY == 7)

        s.feed(text: "\(esc)[u") // Plain CSI u = cursor restore
        #expect(s.buffer.cursorX == 2)
        #expect(s.buffer.cursorY == 2)
    }

    @Test("Kitty push does not restore cursor")
    func testKittyPushDoesNotRestoreCursor() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[3;3H")
        s.feed(text: "\(esc)7")
        s.feed(text: "\(esc)[8;8H")
        #expect(s.buffer.cursorX == 7)
        #expect(s.buffer.cursorY == 7)

        s.feed(text: "\(esc)[>1u") // Push
        #expect(s.buffer.cursorX == 7) // Cursor should not move
        #expect(s.buffer.cursorY == 7)
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])
    }

    @Test("Kitty pop does not restore cursor")
    func testKittyPopDoesNotRestoreCursor() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[3;3H")
        s.feed(text: "\(esc)7")
        s.feed(text: "\(esc)[8;8H")

        s.feed(text: "\(esc)[>1u")
        s.feed(text: "\(esc)[<u")
        #expect(s.buffer.cursorX == 7)
        #expect(s.buffer.cursorY == 7)
        #expect(s.keyboard.currentFlags.isEmpty)
    }

    // MARK: - Normal / Alternate screen separation

    @Test("Normal and alternate screens keep separate keyboard modes")
    func testSeparateScreenKeyboards() {
        var s = makeState()
        defer { s.deallocate() }

        // Set normal to disambiguate
        s.feed(text: "\(esc)[=1;1u")
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes])

        // Enter alt screen
        s.feed(text: "\(esc)[?1049h")
        #expect(s.keyboard.currentFlags.isEmpty) // Alt starts empty

        // Set alt to reportAllKeys
        s.feed(text: "\(esc)[=8;1u")
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])

        // Leave alt screen
        s.feed(text: "\(esc)[?1049l")
        #expect(s.keyboard.currentFlags == [.disambiguateEscapeCodes]) // Normal restored

        // Enter alt screen again - should preserve alt state
        s.feed(text: "\(esc)[?1049h")
        #expect(s.keyboard.currentFlags == [.reportAllKeysAsEscapeCodes])
    }

    @Test("Full reset clears alternate screen keyboard state")
    func testFullResetClearsAltState() {
        var s = makeState()
        defer { s.deallocate() }

        s.feed(text: "\(esc)[?1049h") // Enter alt
        s.feed(text: "\(esc)[=12;1u") // reportAlternates + reportAllKeys
        #expect(s.keyboard.currentFlags == [.reportAlternateKeys, .reportAllKeysAsEscapeCodes])

        s.feed(text: "\(esc)[?1049l") // Leave alt
        s.resetToInitialState()

        s.feed(text: "\(esc)[?1049h") // Enter alt again
        #expect(s.keyboard.currentFlags.isEmpty) // Should be cleared
    }

    // MARK: - KeyboardState unit tests

    @Test("KeyboardState push and pop")
    func testKeyboardStatePushPop() {
        var ks = KeyboardState()
        #expect(ks.currentFlags.isEmpty)

        ks.push([.disambiguateEscapeCodes])
        #expect(ks.currentFlags == [.disambiguateEscapeCodes])

        ks.push([.reportEventTypes])
        #expect(ks.currentFlags == [.reportEventTypes])

        ks.pop()
        #expect(ks.currentFlags == [.disambiguateEscapeCodes])

        ks.pop()
        #expect(ks.currentFlags.isEmpty)
    }

    @Test("KeyboardState set flags")
    func testKeyboardStateSetFlags() {
        var ks = KeyboardState()

        ks.setFlags([.disambiguateEscapeCodes], mode: 1)
        #expect(ks.currentFlags == [.disambiguateEscapeCodes])

        // Union
        ks.setFlags([.reportEventTypes], mode: 2)
        #expect(ks.currentFlags == [.disambiguateEscapeCodes, .reportEventTypes])

        // Subtract
        ks.setFlags([.disambiguateEscapeCodes], mode: 3)
        #expect(ks.currentFlags == [.reportEventTypes])
    }

    @Test("KeyboardState reset")
    func testKeyboardStateReset() {
        var ks = KeyboardState()
        ks.push([.disambiguateEscapeCodes])
        ks.push([.reportEventTypes])

        ks.reset()
        #expect(ks.currentFlags.isEmpty)
        #expect(ks.depth == 0)
    }
}
