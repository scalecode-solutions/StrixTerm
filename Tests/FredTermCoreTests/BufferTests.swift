import Testing
@testable import FredTermCore

/// Port of SwiftTerm's BufferTests: tests for buffer management, alternate buffer
/// switching, yBase behavior, cursor clamping on resize, and rapid buffer switches.
@Suite("Buffer Tests")
struct BufferTests {
    private let esc = "\u{1b}"

    @Test("Alt buffer yBase reset on deactivate")
    func testYBaseResetOnClear() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Switch to alternate buffer
        state.feed(text: "\(esc)[?1049h")
        #expect(state.activeBufferIsAlt, "Should be in alt buffer")

        // Fill the buffer and scroll to increase yBase
        for i in 0..<50 {
            state.feed(text: "Line \(i)\r\n")
        }

        // Switch back to normal buffer
        state.feed(text: "\(esc)[?1049l")
        #expect(!state.activeBufferIsAlt, "Should be in normal buffer")

        // Switch back to alt buffer
        state.feed(text: "\(esc)[?1049h")
        #expect(state.activeBufferIsAlt, "Should be in alt buffer again")

        // yBase should be 0 for the fresh alt buffer
        #expect(state.buffer.yBase == 0, "yBase should be 0 for fresh alt buffer")

        // reverseIndex should not crash
        state.feed(text: "\(esc)[5;20r")  // Set scroll region lines 5-20
        state.feed(text: "\(esc)[5;1H")   // Move cursor to line 5, column 1 (scrollTop)
        state.feed(text: "\(esc)M")
    }

    @Test("Alt buffer reverse index with valid yBase")
    func testReverseIndexWithValidYBase() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Switch to alternate buffer
        state.feed(text: "\(esc)[?1049h")

        // Verify initial state
        #expect(state.buffer.yBase == 0, "yBase should start at 0")

        // Set up scroll region
        state.feed(text: "\(esc)[1;25r")  // Full screen scroll region
        state.feed(text: "\(esc)[1;1H")   // Move to top-left

        #expect(state.buffer.cursorY == 0, "Cursor should be at row 0")
        #expect(state.buffer.scrollTop == 0, "scrollTop should be 0")

        // Perform reverseIndex - should not crash
        state.feed(text: "\(esc)M")
    }

    @Test("Buffer clear resets yBase")
    func testBufferClearResetsYBase() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Switch to alt buffer and do some scrolling
        state.feed(text: "\(esc)[?1049h")

        // Fill buffer
        for _ in 0..<30 {
            state.feed(text: "test line\r\n")
        }

        // Switch back, which should clear alt buffer
        state.feed(text: "\(esc)[?1049l")

        // Verify alt buffer state is clean
        #expect(state.altBuffer.cursorX == 0, "cursorX should be 0 after clear")
        #expect(state.altBuffer.cursorY == 0, "cursorY should be 0 after clear")
    }

    @Test("Restore cursor clamps invalid saved Y")
    func testRestoreCursorClampsInvalidSavedY() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Save cursor at a valid position
        state.feed(text: "\(esc)[10;10H")  // Move to row 10, col 10
        state.feed(text: "\(esc)7")         // Save cursor (DECSC)

        // Corrupt savedY to simulate post-resize invalid state
        state.buffer.savedCursor.y = 100  // Way beyond rows (25)

        // Restore cursor - should clamp, not crash
        state.feed(text: "\(esc)8")  // Restore cursor (DECRC)

        // Verify y was clamped to valid range
        #expect(state.buffer.cursorY >= 0, "y should be >= 0")
        #expect(state.buffer.cursorY < state.rows, "y should be < rows")
    }

    @Test("Restore cursor clamps negative saved Y")
    func testRestoreCursorClampsNegativeSavedY() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Corrupt savedY to negative value
        state.buffer.savedCursor.y = -10

        // Restore cursor - should clamp, not crash
        state.feed(text: "\(esc)8")

        // Verify y was clamped to 0
        #expect(state.buffer.cursorY >= 0, "y should be clamped to >= 0")
    }

    @Test("Restore cursor clamps invalid saved X")
    func testRestoreCursorClampsInvalidSavedX() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Corrupt savedX to invalid values
        state.buffer.savedCursor.x = 200  // Beyond cols (80)

        // Restore cursor - should clamp, not crash
        state.feed(text: "\(esc)8")

        // Verify x was clamped to valid range
        #expect(state.buffer.cursorX >= 0, "x should be >= 0")
        #expect(state.buffer.cursorX < state.cols, "x should be < cols")
    }

    @Test("Rapid buffer switches don't corrupt state")
    func testRapidBufferSwitches() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Perform many rapid switches between normal and alt buffer
        for i in 0..<20 {
            // Switch to alt buffer
            state.feed(text: "\(esc)[?1049h")
            #expect(state.activeBufferIsAlt, "Iteration \(i): Should be in alt buffer")

            // Do some work in alt buffer
            state.feed(text: "Alt buffer line \(i)\r\n")

            // Switch back to normal buffer
            state.feed(text: "\(esc)[?1049l")
            #expect(!state.activeBufferIsAlt, "Iteration \(i): Should be in normal buffer")

            // Do some work in normal buffer
            state.feed(text: "Normal buffer line \(i)\r\n")
        }

        // Final verification: switch to alt buffer and perform operations
        state.feed(text: "\(esc)[?1049h")
        #expect(state.buffer.yBase == 0, "yBase should be 0 after all switches")

        // reverseIndex should work without crashing
        state.feed(text: "\(esc)[1;1H")  // Move to top
        state.feed(text: "\(esc)M")       // Reverse index
    }

    @Test("Direct clear resets yBase")
    func testDirectClearResetsYBase() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Switch to alt buffer and do some scrolling
        state.feed(text: "\(esc)[?1049h")

        // Fill buffer to potentially increase yBase
        for _ in 0..<30 {
            state.feed(text: "test line\r\n")
        }

        // Clear the buffer directly
        state.altBuffer.clearBuffer(rows: 25, cols: 80)

        // All state should be reset
        #expect(state.altBuffer.yBase == 0, "yBase should be 0 after clear")
        #expect(state.altBuffer.yDisp == 0, "yDisp should be 0 after clear")
        #expect(state.altBuffer.cursorX == 0, "cursorX should be 0 after clear")
        #expect(state.altBuffer.cursorY == 0, "cursorY should be 0 after clear")
        #expect(state.altBuffer.linesTop == 0, "linesTop should be 0 after clear")
        #expect(state.altBuffer.scrollTop == 0, "scrollTop should be 0 after clear")
        #expect(state.altBuffer.scrollBottom == 24, "scrollBottom should be rows-1 after clear")
    }

    @Test("Crash condition prevented with invalid yBase")
    func testCrashConditionPrevented() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Switch to alt buffer
        state.feed(text: "\(esc)[?1049h")

        // Set up scroll region and position cursor at scrollTop
        state.feed(text: "\(esc)[1;25r")
        state.feed(text: "\(esc)[1;1H")

        // The reverseIndex should not crash
        state.feed(text: "\(esc)M")

        // Verify buffer state is still sane
        #expect(state.buffer.grid.count >= 0, "Buffer should still have lines")
    }

    @Test("Scroll with scroll region doesn't corrupt state")
    func testScrollWithScrollRegion() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Switch to alt buffer
        state.feed(text: "\(esc)[?1049h")

        // Set up a non-zero scroll region
        state.feed(text: "\(esc)[5;20r")

        // Position cursor in scroll region
        state.feed(text: "\(esc)[20;1H")

        // Trigger scroll by adding a newline at bottom of scroll region
        state.feed(text: "\r\n")

        // Should not crash - if we get here, the test passes
        #expect(state.buffer.cursorY >= 0)
    }

    @Test("Buffer switch during active scrolling with scroll region")
    func testBufferSwitchDuringScrolling() {
        var state = TestHarness.makeTerminal(cols: 80, rows: 25)
        defer { state.deallocate() }

        // Set up scroll region in normal buffer
        state.feed(text: "\(esc)[5;20r")  // Scroll region lines 5-20

        // Add content that causes scrolling
        for i in 0..<30 {
            state.feed(text: "Normal line \(i)\r\n")
        }

        // Switch to alt buffer mid-scroll
        state.feed(text: "\(esc)[?1049h")

        // Set up scroll region in alt buffer
        state.feed(text: "\(esc)[3;15r")  // Different scroll region

        // Add content that causes scrolling in alt buffer
        for i in 0..<20 {
            state.feed(text: "Alt line \(i)\r\n")
        }

        // Switch back to normal buffer
        state.feed(text: "\(esc)[?1049l")

        // Switch back to alt and verify it works
        state.feed(text: "\(esc)[?1049h")
        #expect(state.buffer.yBase == 0, "Fresh alt buffer should have yBase=0")

        // Operations should work without crashing
        state.feed(text: "\(esc)[3;1H")   // Move to scroll region top
        state.feed(text: "\(esc)M")        // Reverse index
    }
}
