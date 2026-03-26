import Testing
@testable import FredTermCore

@Suite("Synchronized Output Tests")
struct SyncOutputTests {
    private func makeState(cols: Int = 20, rows: Int = 5) -> TerminalState {
        TerminalState(cols: cols, rows: rows, maxScrollback: 0)
    }

    @Test("Mode 2026 set enables synchronized output")
    func testSyncOutputSet() {
        var state = makeState()
        defer { state.deallocate() }

        #expect(!state.modes.synchronizedOutput)
        state.feed(text: "\u{1b}[?2026h")
        #expect(state.modes.synchronizedOutput)
    }

    @Test("Mode 2026 reset disables synchronized output")
    func testSyncOutputReset() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}[?2026h")
        #expect(state.modes.synchronizedOutput)
        state.feed(text: "\u{1b}[?2026l")
        #expect(!state.modes.synchronizedOutput)
    }

    @Test("Synchronized output toggle sequence")
    func testSyncOutputToggle() {
        var state = makeState()
        defer { state.deallocate() }

        // Enable
        state.feed(text: "\u{1b}[?2026h")
        #expect(state.modes.synchronizedOutput)

        // Write while synced
        state.feed(text: "\u{1b}[2J\u{1b}[HNEW")

        // Disable
        state.feed(text: "\u{1b}[?2026l")
        #expect(!state.modes.synchronizedOutput)

        // Content should be visible
        let line = state.buffer.yBase
        #expect(state.buffer.grid[line, 0].codePoint == 0x4E) // N
        #expect(state.buffer.grid[line, 1].codePoint == 0x45) // E
        #expect(state.buffer.grid[line, 2].codePoint == 0x57) // W
    }

    @Test("State tracking persists across multiple feeds")
    func testStateTracking() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}[?2026h")
        state.feed(text: "A")
        state.feed(text: "B")
        state.feed(text: "C")
        #expect(state.modes.synchronizedOutput)

        state.feed(text: "\u{1b}[?2026l")
        #expect(!state.modes.synchronizedOutput)

        // Content should have been written
        let line = state.buffer.yBase
        #expect(state.buffer.grid[line, 0].codePoint == 0x41) // A
        #expect(state.buffer.grid[line, 1].codePoint == 0x42) // B
        #expect(state.buffer.grid[line, 2].codePoint == 0x43) // C
    }

    @Test("Multiple synchronized output sessions")
    func testMultipleSessions() {
        var state = makeState()
        defer { state.deallocate() }

        // First session
        state.feed(text: "\u{1b}[?2026h")
        #expect(state.modes.synchronizedOutput)
        state.feed(text: "\u{1b}[?2026l")
        #expect(!state.modes.synchronizedOutput)

        // Second session
        state.feed(text: "\u{1b}[?2026h")
        #expect(state.modes.synchronizedOutput)
        state.feed(text: "\u{1b}[?2026l")
        #expect(!state.modes.synchronizedOutput)
    }
}
