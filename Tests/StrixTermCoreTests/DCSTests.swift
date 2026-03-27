import Testing
@testable import StrixTermCore

@Suite("DCS Tests")
struct DCSTests {
    // MARK: - Helpers

    private func makeState(cols: Int = 80, rows: Int = 24) -> TerminalState {
        TerminalState(cols: cols, rows: rows, maxScrollback: 0)
    }

    private func sentResponses(_ state: TerminalState) -> [String] {
        state.pendingActions.compactMap { action in
            if case .sendData(let data) = action {
                return String(bytes: data, encoding: .utf8)
            }
            return nil
        }
    }

    // MARK: - DECRQSS (Request Status String)

    @Test("DECRQSS for SGR responds with current attributes")
    func testDecrqssSgr() {
        var state = makeState()
        defer { state.deallocate() }

        // Set some attributes first
        state.feed(text: "\u{1b}[1;3m") // bold + italic

        // Request SGR status: DCS $ q m ST
        state.feed(text: "\u{1b}P$qm\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        // Response format: DCS 1 $ r <SGR params> m ST
        #expect(response.hasPrefix("\u{1b}P1$r"))
        #expect(response.hasSuffix("m\u{1b}\\"))
        // Should contain bold (;1) and italic (;3)
        #expect(response.contains(";1"))
        #expect(response.contains(";3"))
    }

    @Test("DECRQSS for SGR with no attributes")
    func testDecrqssSgrDefault() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}P$qm\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        // Should respond with default (0m)
        #expect(response == "\u{1b}P1$r0m\u{1b}\\")
    }

    @Test("DECRQSS for DECSTBM responds with scroll region")
    func testDecrqssDecstbm() {
        var state = makeState()
        defer { state.deallocate() }

        // Set scroll region
        state.feed(text: "\u{1b}[5;20r")

        // Request DECSTBM status: DCS $ q r ST
        state.feed(text: "\u{1b}P$qr\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        #expect(response.hasPrefix("\u{1b}P1$r"))
        #expect(response.hasSuffix("r\u{1b}\\"))
        #expect(response.contains("5;20"))
    }

    @Test("DECRQSS for DECSCUSR responds with cursor style")
    func testDecrqssDecscusr() {
        var state = makeState()
        defer { state.deallocate() }

        // Set cursor style to blinking bar
        state.feed(text: "\u{1b}[5 q")

        // Request cursor style: DCS $ q SP q ST
        state.feed(text: "\u{1b}P$q q\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        #expect(response.hasPrefix("\u{1b}P1$r"))
        #expect(response.hasSuffix(" q\u{1b}\\"))
    }

    @Test("DECRQSS for unknown request returns error response")
    func testDecrqssUnknown() {
        var state = makeState()
        defer { state.deallocate() }

        // Unknown request
        state.feed(text: "\u{1b}P$qz\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        // Error response: DCS 0 $ r ST
        #expect(response == "\u{1b}P0$r\u{1b}\\")
    }

    // MARK: - XTGETTCAP

    @Test("XTGETTCAP for terminal name (TN)")
    func testXtgettcapTN() {
        var state = makeState()
        defer { state.deallocate() }

        // Query 'TN' (terminal name) - hex: 544E
        state.feed(text: "\u{1b}P+q544E\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        // Valid response starts with DCS 1 + r
        #expect(response.hasPrefix("\u{1b}P1+r544E="))
    }

    @Test("XTGETTCAP for unknown capability returns error")
    func testXtgettcapUnknown() {
        var state = makeState()
        defer { state.deallocate() }

        // Query unknown cap 'ZZ' - hex: 5A5A
        state.feed(text: "\u{1b}P+q5A5A\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        // Error response: DCS 0 + r
        #expect(response.hasPrefix("\u{1b}P0+r"))
    }

    @Test("XTGETTCAP for colors (Co)")
    func testXtgettcapColors() {
        var state = makeState()
        defer { state.deallocate() }

        // Query 'Co' (colors) - hex: 436F
        state.feed(text: "\u{1b}P+q436F\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        #expect(response.hasPrefix("\u{1b}P1+r"))
    }

    @Test("XTGETTCAP for RGB")
    func testXtgettcapRGB() {
        var state = makeState()
        defer { state.deallocate() }

        // Query 'RGB' - hex: 524742
        state.feed(text: "\u{1b}P+q524742\u{1b}\\")

        let responses = sentResponses(state)
        #expect(!responses.isEmpty)
        let response = responses.last!
        #expect(response.hasPrefix("\u{1b}P1+r"))
    }

    // MARK: - DCS Parameter Parsing

    @Test("DCS with numeric parameters does not crash")
    func testDcsWithParams() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}P1000p\u{1b}\\")
        // Should not crash
    }

    @Test("Unknown DCS command handled gracefully")
    func testDcsUnknownCommand() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}P999z\u{1b}\\")
        // Should not crash
    }

    @Test("DCS with very long payload does not crash")
    func testDcsLongPayload() {
        var state = makeState()
        defer { state.deallocate() }

        let longQuery = String(repeating: "54", count: 500) // Hex for 'T'
        state.feed(text: "\u{1b}P+q\(longQuery)\u{1b}\\")
        // Should not crash
    }

    @Test("Multiple DCS sequences in succession")
    func testMultipleDcsSequences() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}P$qm\u{1b}\\")
        state.feed(text: "\u{1b}P$qr\u{1b}\\")
        state.feed(text: "\u{1b}P+q544E\u{1b}\\")

        let responses = sentResponses(state)
        #expect(responses.count == 3)
    }

    // MARK: - DCS Interrupted by ESC

    @Test("DCS interrupted by new escape sequence")
    func testDcsInterruptedByEscape() {
        var state = makeState()
        defer { state.deallocate() }

        // Start DCS, then interrupt with cursor home
        state.feed(text: "\u{1b}P+q")
        state.feed(text: "\u{1b}[H")

        // Should abort DCS and process cursor home
        #expect(state.buffer.cursorX == 0)
        #expect(state.buffer.cursorY == 0)
    }

    // MARK: - Sixel

    @Test("Basic sixel does not crash")
    func testDcsSixelBasic() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}Pq#0;2;0;0;0~\u{1b}\\")
        // Should not crash
    }

    @Test("Sixel with parameters does not crash")
    func testDcsSixelWithParams() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}P0;1;q#0;2;100;100;100~\u{1b}\\")
        // Should not crash
    }
}
