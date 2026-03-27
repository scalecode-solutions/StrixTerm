import Testing
@testable import StrixTermCore

@Suite("Link Tests")
struct LinkTests {
    // MARK: - LinkTable Tests

    @Test("LinkTable insert and lookup")
    func testLinkTableInsertLookup() {
        var table = LinkTable()

        let id = table.insert(url: "https://example.com")
        #expect(id > 0)

        let entry = table.lookup(id)
        #expect(entry != nil)
        #expect(entry?.url == "https://example.com")
        #expect(entry?.params.isEmpty == true)
    }

    @Test("LinkTable insert with params")
    func testLinkTableInsertWithParams() {
        var table = LinkTable()

        let id = table.insert(url: "https://example.com", params: ["id": "abc"])
        let entry = table.lookup(id)
        #expect(entry != nil)
        #expect(entry?.url == "https://example.com")
        #expect(entry?.params["id"] == "abc")
    }

    @Test("LinkTable release")
    func testLinkTableRelease() {
        var table = LinkTable()

        let id = table.insert(url: "https://example.com")
        #expect(table.lookup(id) != nil)

        table.release(id)
        #expect(table.lookup(id) == nil)
    }

    @Test("LinkTable deduplication for same URLs")
    func testLinkTableDedup() {
        var table = LinkTable()

        let id1 = table.insert(url: "https://example.com")
        let id2 = table.insert(url: "https://example.com")
        #expect(id1 == id2, "Same URL with no params should return same ID")

        // Different URLs should get different IDs
        let id3 = table.insert(url: "https://other.com")
        #expect(id3 != id1)
    }

    @Test("LinkTable dedup does not apply when params differ")
    func testLinkTableNoDedupWithParams() {
        var table = LinkTable()

        let id1 = table.insert(url: "https://example.com", params: ["id": "a"])
        let id2 = table.insert(url: "https://example.com", params: ["id": "b"])
        #expect(id1 != id2, "Same URL with different params should get different IDs")
    }

    @Test("LinkTable reuses released IDs")
    func testLinkTableFreeListReuse() {
        var table = LinkTable()

        let id1 = table.insert(url: "https://first.com")
        table.release(id1)

        let id2 = table.insert(url: "https://second.com")
        #expect(id2 == id1, "Should reuse released ID")
    }

    @Test("LinkTable lookup invalid ID returns nil")
    func testLinkTableLookupInvalid() {
        let table = LinkTable()
        #expect(table.lookup(0) == nil)
        #expect(table.lookup(999) == nil)
    }

    @Test("LinkTable count tracks active entries")
    func testLinkTableCount() {
        var table = LinkTable()
        #expect(table.count == 0)

        let id1 = table.insert(url: "https://a.com")
        let id2 = table.insert(url: "https://b.com")
        #expect(table.count == 2)

        table.release(id1)
        #expect(table.count == 1)

        table.release(id2)
        #expect(table.count == 0)
    }

    // MARK: - OSC 8 Explicit Link Tests

    @Test("OSC 8 explicit link tags cells with .hasLink flag")
    func testOsc8ExplicitLinkCells() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }

        // Feed: ESC]8;;https://example.com BEL text ESC]8;; BEL
        state.feed(text: "\u{1b}]8;;https://example.com\u{07}")
        state.feed(text: "text")
        state.feed(text: "\u{1b}]8;;\u{07}")

        // Verify the 4 cells of "text" have .hasLink flag
        for col in 0..<4 {
            let cell = TestHarness.cell(state, row: 0, col: col)
            #expect(cell.flags.contains(.hasLink),
                    "Cell at col \(col) should have .hasLink flag")
            #expect(cell.payload > 0, "Cell at col \(col) should have non-zero payload")
        }

        // Verify the link ID resolves to the correct URL
        let firstCell = TestHarness.cell(state, row: 0, col: 0)
        let entry = state.links.lookup(firstCell.payload)
        #expect(entry != nil)
        #expect(entry?.url == "https://example.com")
    }

    @Test("OSC 8 link followed by normal text")
    func testOsc8LinkFollowedByNormalText() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]8;;https://example.com\u{07}")
        state.feed(text: "link")
        state.feed(text: "\u{1b}]8;;\u{07}")
        state.feed(text: " normal")

        // "link" cells should have .hasLink
        for col in 0..<4 {
            let cell = TestHarness.cell(state, row: 0, col: col)
            #expect(cell.flags.contains(.hasLink))
        }

        // " normal" cells should NOT have .hasLink
        for col in 4..<11 {
            let cell = TestHarness.cell(state, row: 0, col: col)
            #expect(!cell.flags.contains(.hasLink),
                    "Cell at col \(col) should NOT have .hasLink flag")
        }
    }

    @Test("OSC 8 with id parameter")
    func testOsc8WithIdParam() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]8;id=abc;https://example.com\u{07}")
        state.feed(text: "click me")
        state.feed(text: "\u{1b}]8;;\u{07}")

        let cell = TestHarness.cell(state, row: 0, col: 0)
        #expect(cell.flags.contains(.hasLink))
        let entry = state.links.lookup(cell.payload)
        #expect(entry?.url == "https://example.com")
        #expect(entry?.params["id"] == "abc")
    }

    @Test("OSC 8 emits openLink action")
    func testOsc8EmitsAction() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]8;;https://example.com\u{07}")
        state.feed(text: "text")
        state.feed(text: "\u{1b}]8;;\u{07}")

        let linkAction = state.pendingActions.first { action in
            if case .openLink = action { return true }
            return false
        }
        #expect(linkAction != nil)
        if case .openLink(let url, _) = linkAction {
            #expect(url == "https://example.com")
        }
    }

    @Test("All linked cells share the same link ID")
    func testOsc8SharedLinkId() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]8;;https://example.com\u{07}")
        state.feed(text: "hello")
        state.feed(text: "\u{1b}]8;;\u{07}")

        let firstPayload = TestHarness.cell(state, row: 0, col: 0).payload
        for col in 1..<5 {
            let cell = TestHarness.cell(state, row: 0, col: col)
            #expect(cell.payload == firstPayload,
                    "All cells in the link should share the same link ID")
        }
    }

    // MARK: - LinkDetector: Implicit URL Detection Tests

    @Test("Detect https URL in text")
    func testDetectHttpsUrl() {
        let matches = LinkDetector.detectLinks(in: "Visit https://example.com for more info", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
        #expect(matches[0].startCol == 6)
        #expect(matches[0].endCol == 25)  // exclusive: 6 + 19 chars
    }

    @Test("Detect http URL in text")
    func testDetectHttpUrl() {
        let matches = LinkDetector.detectLinks(in: "See http://example.com/page", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "http://example.com/page")
    }

    @Test("Detect ftp URL")
    func testDetectFtpUrl() {
        let matches = LinkDetector.detectLinks(in: "Download from ftp://files.example.com/pub", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "ftp://files.example.com/pub")
    }

    @Test("Detect ssh URL")
    func testDetectSshUrl() {
        let matches = LinkDetector.detectLinks(in: "Connect via ssh://user@host.com", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "ssh://user@host.com")
    }

    @Test("Detect git URL")
    func testDetectGitUrl() {
        let matches = LinkDetector.detectLinks(in: "Clone git://github.com/user/repo.git", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "git://github.com/user/repo.git")
    }

    @Test("Detect mailto URL")
    func testDetectMailtoUrl() {
        let matches = LinkDetector.detectLinks(in: "Email mailto:user@example.com", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "mailto:user@example.com")
    }

    @Test("Detect tel URL")
    func testDetectTelUrl() {
        let matches = LinkDetector.detectLinks(in: "Call tel:+1-555-0100", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "tel:+1-555-0100")
    }

    @Test("URL with query params and fragments")
    func testUrlWithQueryAndFragment() {
        let matches = LinkDetector.detectLinks(
            in: "Go to https://example.com/path?key=value&foo=bar#section", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com/path?key=value&foo=bar#section")
    }

    @Test("URL with balanced parentheses (Wikipedia)")
    func testUrlWithBalancedParens() {
        let matches = LinkDetector.detectLinks(
            in: "See https://en.wikipedia.org/wiki/Rust_(programming_language) for details", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://en.wikipedia.org/wiki/Rust_(programming_language)")
    }

    @Test("Trailing period is stripped from URL")
    func testTrailingPeriodStripped() {
        let matches = LinkDetector.detectLinks(in: "Visit https://example.com.", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Trailing comma is stripped from URL")
    func testTrailingCommaStripped() {
        let matches = LinkDetector.detectLinks(in: "See https://example.com, then continue", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Trailing exclamation is stripped from URL")
    func testTrailingExclamationStripped() {
        let matches = LinkDetector.detectLinks(in: "Check https://example.com!", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Trailing question mark is stripped from URL")
    func testTrailingQuestionMarkStripped() {
        let matches = LinkDetector.detectLinks(in: "Is it https://example.com?", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Trailing colon is stripped from URL")
    func testTrailingColonStripped() {
        let matches = LinkDetector.detectLinks(in: "Link: https://example.com:", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Trailing semicolon is stripped from URL")
    func testTrailingSemicolonStripped() {
        let matches = LinkDetector.detectLinks(in: "See https://example.com;", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Trailing unbalanced paren is stripped")
    func testTrailingUnbalancedParenStripped() {
        let matches = LinkDetector.detectLinks(in: "(https://example.com)", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com")
    }

    @Test("Multiple links on same line")
    func testMultipleLinks() {
        let matches = LinkDetector.detectLinks(
            in: "Visit https://one.com and https://two.com for info", row: 0)
        #expect(matches.count == 2)
        #expect(matches[0].url == "https://one.com")
        #expect(matches[1].url == "https://two.com")
    }

    @Test("No URLs in plain text")
    func testNoUrls() {
        let matches = LinkDetector.detectLinks(in: "This is just normal text", row: 0)
        #expect(matches.isEmpty)
    }

    @Test("linkAt finds link at specific column")
    func testLinkAtColumn() {
        let text = "Visit https://example.com for info"
        let match = LinkDetector.linkAt(col: 10, in: text, row: 0)
        #expect(match != nil)
        #expect(match?.url == "https://example.com")
    }

    @Test("linkAt returns nil outside link")
    func testLinkAtColumnOutside() {
        let text = "Visit https://example.com for info"
        let match = LinkDetector.linkAt(col: 0, in: text, row: 0)
        #expect(match == nil)
    }

    @Test("URL with percent-encoded characters")
    func testUrlWithPercentEncoding() {
        let matches = LinkDetector.detectLinks(
            in: "See https://example.com/path%20with%20spaces", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "https://example.com/path%20with%20spaces")
    }

    @Test("file:// URL detection")
    func testFileUrl() {
        let matches = LinkDetector.detectLinks(
            in: "Open file:///home/user/document.txt", row: 0)
        #expect(matches.count == 1)
        #expect(matches[0].url == "file:///home/user/document.txt")
    }

    // MARK: - Link spanning behavior

    @Test("Two separate OSC 8 links on the same line")
    func testTwoSeparateLinks() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 24)
        defer { state.deallocate() }

        // First link
        state.feed(text: "\u{1b}]8;;https://first.com\u{07}")
        state.feed(text: "AAA")
        state.feed(text: "\u{1b}]8;;\u{07}")

        state.feed(text: " ")

        // Second link
        state.feed(text: "\u{1b}]8;;https://second.com\u{07}")
        state.feed(text: "BBB")
        state.feed(text: "\u{1b}]8;;\u{07}")

        // Verify first link cells
        let firstEntry = state.links.lookup(TestHarness.cell(state, row: 0, col: 0).payload)
        #expect(firstEntry?.url == "https://first.com")

        // Space cell should not have link
        let spaceCell = TestHarness.cell(state, row: 0, col: 3)
        #expect(!spaceCell.flags.contains(.hasLink))

        // Verify second link cells
        let secondEntry = state.links.lookup(TestHarness.cell(state, row: 0, col: 4).payload)
        #expect(secondEntry?.url == "https://second.com")
    }
}
