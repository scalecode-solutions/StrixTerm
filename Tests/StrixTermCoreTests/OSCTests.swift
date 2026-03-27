import Testing
@testable import StrixTermCore

@Suite("OSC Tests")
struct OSCTests {
    // MARK: - Helpers

    private func makeState(cols: Int = 80, rows: Int = 24) -> TerminalState {
        TerminalState(cols: cols, rows: rows, maxScrollback: 0)
    }

    private func titles(_ state: TerminalState) -> [String] {
        state.pendingActions.compactMap { action in
            if case .setTitle(let title) = action {
                return title
            }
            return nil
        }
    }

    private func iconTitles(_ state: TerminalState) -> [String] {
        state.pendingActions.compactMap { action in
            if case .setIconTitle(let title) = action {
                return title
            }
            return nil
        }
    }

    private func sentResponses(_ state: TerminalState) -> [String] {
        state.pendingActions.compactMap { action in
            if case .sendData(let data) = action {
                return String(bytes: data, encoding: .utf8)
            }
            return nil
        }
    }

    // MARK: - Title Setting

    @Test("OSC 0 sets both window title and icon title (BEL terminator)")
    func testOsc0TitleBel() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]0;abc\u{07}")

        #expect(titles(state).last == "abc")
        #expect(iconTitles(state).last == "abc")
    }

    @Test("OSC 1 sets icon title")
    func testOsc1IconTitle() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]1;icon-name\u{07}")

        #expect(iconTitles(state).last == "icon-name")
    }

    @Test("OSC 2 sets window title (BEL terminator)")
    func testOsc2TitleBel() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]2;window-title\u{07}")

        #expect(titles(state).last == "window-title")
    }

    @Test("OSC 2 sets window title (ST terminator)")
    func testOsc2TitleSt() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]2;def\u{1b}\\")

        #expect(titles(state).last == "def")
    }

    @Test("OSC 0 combined title")
    func testOsc0CombinedTitle() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]0;combined-title\u{07}")

        #expect(titles(state).last == "combined-title")
    }

    // MARK: - OSC 7 (Current Working Directory)

    @Test("OSC 7 sets current directory")
    func testOsc7CurrentDirectory() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]7;file:///localhost/usr/bin\u{07}")

        let dirAction = state.pendingActions.first { action in
            if case .setCurrentDirectory = action { return true }
            return false
        }
        #expect(dirAction != nil)
        if case .setCurrentDirectory(let dir) = dirAction {
            #expect(dir == "file:///localhost/usr/bin")
        }
    }

    @Test("OSC 7 with various URL formats")
    func testOsc7VariousFormats() {
        var state = makeState()
        defer { state.deallocate() }

        // Standard file URL
        state.feed(text: "\u{1b}]7;file:///home/user/dir\u{07}")
        var dirActions = state.pendingActions.compactMap { action -> String? in
            if case .setCurrentDirectory(let d) = action { return d }
            return nil
        }
        #expect(dirActions.last == "file:///home/user/dir")

        state.pendingActions.removeAll()

        // URL with hostname
        state.feed(text: "\u{1b}]7;file://hostname/path/to/dir\u{07}")
        dirActions = state.pendingActions.compactMap { action -> String? in
            if case .setCurrentDirectory(let d) = action { return d }
            return nil
        }
        #expect(dirActions.last == "file://hostname/path/to/dir")

        state.pendingActions.removeAll()

        // URL with percent encoding
        state.feed(text: "\u{1b}]7;file:///path%20with%20spaces\u{07}")
        dirActions = state.pendingActions.compactMap { action -> String? in
            if case .setCurrentDirectory(let d) = action { return d }
            return nil
        }
        #expect(dirActions.last == "file:///path%20with%20spaces")
    }

    // MARK: - OSC 8 (Hyperlinks)

    @Test("OSC 8 hyperlink start and end does not crash")
    func testOsc8Hyperlinks() {
        var state = makeState()
        defer { state.deallocate() }

        // Start hyperlink
        state.feed(text: "\u{1b}]8;;https://example.com\u{07}")
        state.feed(text: "link text")
        // End hyperlink
        state.feed(text: "\u{1b}]8;;\u{07}")
        state.feed(text: " normal")

        // Should have produced an openLink action
        let linkAction = state.pendingActions.first { action in
            if case .openLink = action { return true }
            return false
        }
        #expect(linkAction != nil)
        if case .openLink(let url, _) = linkAction {
            #expect(url == "https://example.com")
        }
    }

    @Test("OSC 8 hyperlink with ID parameter does not crash")
    func testOsc8HyperlinkWithId() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]8;id=mylink;https://example.com\u{07}")
        state.feed(text: "click me")
        state.feed(text: "\u{1b}]8;;\u{07}")

        // Should not crash
    }

    // MARK: - OSC 52 (Clipboard)

    @Test("OSC 52 clipboard set")
    func testOsc52ClipboardSet() {
        var state = makeState()
        defer { state.deallocate() }

        // Set clipboard: "Hello" base64 = "SGVsbG8="
        state.feed(text: "\u{1b}]52;c;SGVsbG8=\u{07}")

        let clipAction = state.pendingActions.first { action in
            if case .clipboardCopy = action { return true }
            return false
        }
        #expect(clipAction != nil)
        if case .clipboardCopy(let text) = clipAction {
            #expect(text == "Hello")
        }
    }

    @Test("OSC 52 clipboard query does not crash")
    func testOsc52ClipboardQuery() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]52;c;?\u{07}")
        // Should not crash - query not supported for security
    }

    // MARK: - OSC 9 (Progress / Notification)

    @Test("OSC 9;4 progress report set and clamp")
    func testOsc9ProgressSetAndClamp() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]9;4;1;50\u{07}")

        let progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action {
                return (ps, val)
            }
            return nil
        }
        #expect(!progressActions.isEmpty)
        #expect(progressActions.last?.0 == .active)
        #expect(progressActions.last?.1 == 50)
    }

    @Test("OSC 9;4 progress states")
    func testOsc9ProgressAllStates() {
        var state = makeState()
        defer { state.deallocate() }

        // Remove (state 0)
        state.feed(text: "\u{1b}]9;4;0\u{07}")
        var progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action { return (ps, val) }
            return nil
        }
        #expect(progressActions.last?.0 == .hidden)

        state.pendingActions.removeAll()

        // Set (state 1)
        state.feed(text: "\u{1b}]9;4;1;75\u{07}")
        progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action { return (ps, val) }
            return nil
        }
        #expect(progressActions.last?.0 == .active)
        #expect(progressActions.last?.1 == 75)

        state.pendingActions.removeAll()

        // Error (state 2)
        state.feed(text: "\u{1b}]9;4;2\u{07}")
        progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action { return (ps, val) }
            return nil
        }
        #expect(progressActions.last?.0 == .error)

        state.pendingActions.removeAll()

        // Indeterminate (state 3)
        state.feed(text: "\u{1b}]9;4;3\u{07}")
        progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action { return (ps, val) }
            return nil
        }
        #expect(progressActions.last?.0 == .indeterminate)

        state.pendingActions.removeAll()

        // Pause (state 4)
        state.feed(text: "\u{1b}]9;4;4\u{07}")
        progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action { return (ps, val) }
            return nil
        }
        #expect(progressActions.last?.0 == .paused)
    }

    @Test("OSC 9;4 missing progress defaults to nil")
    func testOsc9ProgressMissingValue() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]9;4;1\u{07}")

        let progressActions = state.pendingActions.compactMap { action -> (ProgressState, Int?)? in
            if case .progressReport(let ps, let val) = action { return (ps, val) }
            return nil
        }
        #expect(progressActions.last?.0 == .active)
        #expect(progressActions.last?.1 == nil)
    }

    @Test("OSC 9 notification")
    func testOsc9Notification() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]9;some notification text\u{07}")

        let notifyAction = state.pendingActions.first { action in
            if case .notify = action { return true }
            return false
        }
        #expect(notifyAction != nil)
    }

    // MARK: - OSC 133 (Semantic Prompts)

    @Test("OSC 133 prompt start (A)")
    func testOsc133PromptStart() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;A\u{07}")
        #expect(state.promptState.currentZone == .promptStart)
    }

    @Test("OSC 133 command start (B)")
    func testOsc133CommandStart() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;A\u{07}")
        state.feed(text: "\u{1b}]133;B\u{07}")
        #expect(state.promptState.currentZone == .commandStart)
    }

    @Test("OSC 133 command executed (C)")
    func testOsc133CommandExecuted() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;C\u{07}")
        #expect(state.promptState.currentZone == .commandExecuted)
    }

    @Test("OSC 133 command finished (D) with exit code")
    func testOsc133CommandFinished() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;D;0\u{07}")
        #expect(state.promptState.currentZone == .commandFinished)
        #expect(state.promptState.lastExitCode == 0)
    }

    @Test("OSC 133 command finished with non-zero exit code")
    func testOsc133NonZeroExitCode() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;D;1\u{07}")
        #expect(state.promptState.currentZone == .commandFinished)
        #expect(state.promptState.lastExitCode == 1)
    }

    @Test("OSC 133 full lifecycle")
    func testOsc133FullLifecycle() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;A\u{07}")
        #expect(state.promptState.currentZone == .promptStart)

        state.feed(text: "$ ")
        state.feed(text: "\u{1b}]133;B\u{07}")
        #expect(state.promptState.currentZone == .commandStart)

        state.feed(text: "ls -la\n")
        state.feed(text: "\u{1b}]133;C\u{07}")
        #expect(state.promptState.currentZone == .commandExecuted)

        state.feed(text: "file1\nfile2\n")
        state.feed(text: "\u{1b}]133;D;0\u{07}")
        #expect(state.promptState.currentZone == .commandFinished)
        #expect(state.promptState.lastExitCode == 0)
    }

    @Test("OSC 133 emits promptStateChanged actions")
    func testOsc133EmitsActions() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]133;A\u{07}")

        let promptAction = state.pendingActions.first { action in
            if case .promptStateChanged = action { return true }
            return false
        }
        #expect(promptAction != nil)
        if case .promptStateChanged(let zone) = promptAction {
            #expect(zone == .promptStart)
        }
    }

    // MARK: - Edge Cases

    @Test("Empty OSC sequence handled gracefully")
    func testOscEmpty() {
        var state = makeState()
        defer { state.deallocate() }

        // Empty OSC - should not crash
        state.feed(text: "\u{1b}]\u{07}")

        // OSC with just number - should not crash
        state.feed(text: "\u{1b}]0\u{07}")
    }

    @Test("OSC with very long string")
    func testOscLongString() {
        var state = makeState()
        defer { state.deallocate() }

        let longTitle = String(repeating: "a", count: 5000)
        state.feed(text: "\u{1b}]0;\(longTitle)\u{07}")

        // Should not crash, title may be truncated
        #expect(!titles(state).isEmpty)
    }

    @Test("Multiple OSC title sets")
    func testMultipleTitleSets() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]0;first\u{07}")
        state.feed(text: "\u{1b}]0;second\u{07}")
        state.feed(text: "\u{1b}]0;third\u{07}")

        let allTitles = titles(state)
        #expect(allTitles.count == 3)
        #expect(allTitles[0] == "first")
        #expect(allTitles[1] == "second")
        #expect(allTitles[2] == "third")
    }

    // MARK: - OSC 777 (Notification)

    @Test("OSC 777 notification")
    func testOsc777Notification() {
        var state = makeState()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}]777;notify;Title;Body text\u{07}")

        let notifyAction = state.pendingActions.first { action in
            if case .notify = action { return true }
            return false
        }
        #expect(notifyAction != nil)
        if case .notify(let title, let body) = notifyAction {
            #expect(title == "Title")
            #expect(body == "Body text")
        }
    }
}
