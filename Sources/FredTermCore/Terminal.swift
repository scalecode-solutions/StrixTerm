import Foundation

/// Delegate protocol for the Terminal.
/// Intentionally minimal: most output goes through TerminalAction.
public protocol TerminalDelegate: AnyObject, Sendable {
    /// Called when the terminal has produced actions that need processing.
    func terminal(_ terminal: Terminal, produced actions: [TerminalAction])
    /// Called when data needs to be sent to the host process.
    func terminal(_ terminal: Terminal, sendData data: [UInt8])
    /// Called when the terminal needs to be redrawn.
    func terminalNeedsDisplay(_ terminal: Terminal)
}

/// The public-facing terminal type.
///
/// Wraps `TerminalState` (a value type) and provides thread-safe access.
/// This is the primary API consumers interact with.
public final class Terminal: @unchecked Sendable {
    private var state: TerminalState
    private let lock = NSLock()

    public weak var delegate: (any TerminalDelegate)?

    /// Create a terminal with the given dimensions.
    public init(cols: Int = 80, rows: Int = 25, maxScrollback: Int = 10_000) {
        state = TerminalState(cols: cols, rows: rows, maxScrollback: maxScrollback)
    }

    deinit {
        state.deallocate()
    }

    // MARK: - Feed data from host

    /// Feed raw bytes from the host process.
    public func feed(_ data: [UInt8]) {
        let actions: [TerminalAction]
        lock.lock()
        state.feed(data)
        actions = state.pendingActions
        state.pendingActions.removeAll(keepingCapacity: true)
        lock.unlock()
        dispatchActions(actions)
    }

    /// Feed a convenience string.
    public func feed(text: String) {
        feed(Array(text.utf8))
    }

    // MARK: - User input

    /// Send user keyboard input as bytes.
    public func sendInput(_ data: [UInt8]) {
        delegate?.terminal(self, sendData: data)
    }

    /// Send user keyboard input as a string.
    public func sendInput(text: String) {
        sendInput(Array(text.utf8))
    }

    // MARK: - Resize

    /// Resize the terminal to new dimensions.
    public func resize(cols: Int, rows: Int) {
        lock.lock()
        state.resize(cols: cols, rows: rows)
        lock.unlock()
        delegate?.terminalNeedsDisplay(self)
    }

    // MARK: - Query state

    /// Get the current terminal size.
    public var size: TerminalSize {
        lock.lock()
        defer { lock.unlock() }
        return TerminalSize(cols: state.cols, rows: state.rows)
    }

    /// Get the cursor position.
    public var cursorPosition: Position {
        lock.lock()
        defer { lock.unlock() }
        return Position(col: state.buffer.cursorX, row: state.buffer.cursorY)
    }

    /// Whether the cursor is visible.
    public var cursorVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.cursorVisible
    }

    /// The current cursor style.
    public var cursorStyle: CursorStyle {
        lock.lock()
        defer { lock.unlock() }
        return state.cursorStyle
    }

    /// Whether the alternate buffer is active.
    public var isAlternateBuffer: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.activeBufferIsAlt
    }

    /// The current mouse mode.
    public var mouseMode: MouseMode {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.mouseMode
    }

    /// The current mouse encoding.
    public var mouseEncoding: MouseEncoding {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.mouseEncoding
    }

    /// Whether the terminal is currently tracking mouse events.
    public var isTrackingMouse: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.mouseMode != .off
    }

    /// Encode and return mouse event data for sending to the host process.
    /// Returns nil if the current mouse mode doesn't report this event type.
    public func encodeMouseEvent(
        button: MouseButton,
        action: MouseAction,
        position: Position,
        pixelPosition: (x: Int, y: Int)? = nil,
        modifiers: MouseModifiers = []
    ) -> [UInt8]? {
        lock.lock()
        let mode = state.modes.mouseMode
        let encoding = state.modes.mouseEncoding
        lock.unlock()

        return MouseEncoder.encode(
            button: button,
            action: action,
            position: position,
            pixelPosition: pixelPosition,
            modifiers: modifiers,
            mode: mode,
            encoding: encoding
        )
    }

    /// Whether bracketed paste mode is active.
    public var bracketedPasteMode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.bracketedPaste
    }

    /// The Kitty keyboard flags currently active.
    public var kittyKeyboardFlags: KittyKeyboardFlags {
        lock.lock()
        defer { lock.unlock() }
        return state.keyboard.currentFlags
    }

    /// The semantic prompt state.
    public var promptState: SemanticPromptState {
        lock.lock()
        defer { lock.unlock() }
        return state.promptState
    }

    /// Whether application cursor keys mode is active.
    public var applicationCursorKeys: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.applicationCursor
    }

    /// Whether application keypad mode is active.
    public var applicationKeypad: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.modes.applicationKeypad
    }

    // MARK: - Buffer access

    /// Get the text content of a visible line.
    public func lineText(_ row: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        let lineIdx = state.buffer.yBase + row
        return state.buffer.grid.lineText(lineIdx)
    }

    /// Get a cell at a position in the visible area.
    public func cell(at position: Position) -> Cell {
        lock.lock()
        defer { lock.unlock() }
        let lineIdx = state.buffer.yBase + position.row
        return state.buffer.grid[lineIdx, position.col]
    }

    /// Get the attribute entry for a given index.
    public func attribute(at index: UInt32) -> AttributeEntry {
        lock.lock()
        defer { lock.unlock() }
        return state.attributes[index]
    }

    /// Create an immutable snapshot of the terminal state for rendering.
    public func snapshot() -> TerminalSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return TerminalSnapshot(state: state)
    }

    /// Get the text content of all visible lines.
    public func visibleText() -> String {
        lock.lock()
        defer { lock.unlock() }
        var result = ""
        for row in 0..<state.rows {
            let lineIdx = state.buffer.yBase + row
            let line = state.buffer.grid.lineText(lineIdx)
            result += line
            if row < state.rows - 1 {
                let meta = state.buffer.grid[lineMetadata: lineIdx]
                if !meta.isWrapped {
                    result += "\n"
                }
            }
        }
        return result
    }

    /// Perform a bracketed paste of text.
    public func paste(_ text: String) {
        if bracketedPasteMode {
            sendInput(text: "\u{1b}[200~")
        }
        sendInput(text: text)
        if bracketedPasteMode {
            sendInput(text: "\u{1b}[201~")
        }
    }

    // MARK: - Search

    /// Search the terminal buffer for matches of the given query.
    public func search(query: String, options: SearchOptions = SearchOptions()) -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }
        return SearchEngine.search(
            query: query,
            in: state.buffer.grid,
            graphemes: state.graphemes,
            options: options
        )
    }

    /// Scroll the display so that the given absolute line index is visible.
    public func scrollToLine(_ lineIndex: Int) {
        lock.lock()
        let rows = state.rows
        let yBase = state.buffer.yBase
        let linesTop = state.buffer.linesTop
        // The lineIndex is an absolute index in the grid.
        // yDisp is the first visible line. We want lineIndex to be visible.
        let targetYDisp = max(yBase - linesTop, min(yBase, lineIndex))
        if targetYDisp != state.buffer.yDisp {
            state.buffer.yDisp = targetYDisp
        }
        _ = rows
        lock.unlock()
        delegate?.terminalNeedsDisplay(self)
    }

    // MARK: - Scroll position

    /// The current scroll offset (0 = showing most recent output).
    public var scrollOffset: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.buffer.linesTop - (state.buffer.yDisp - state.buffer.yBase + state.buffer.linesTop)
    }

    /// Scroll the display by a delta (positive = scroll back, negative = scroll forward).
    public func scroll(delta: Int) {
        lock.lock()
        let newYDisp = max(state.buffer.yBase - state.buffer.linesTop,
                          min(state.buffer.yBase,
                              state.buffer.yDisp + delta))
        state.buffer.yDisp = newYDisp
        lock.unlock()
        delegate?.terminalNeedsDisplay(self)
    }

    /// Scroll to the bottom (most recent output).
    public func scrollToBottom() {
        lock.lock()
        state.buffer.yDisp = state.buffer.yBase
        lock.unlock()
        delegate?.terminalNeedsDisplay(self)
    }

    // MARK: - Private

    private func dispatchActions(_ actions: [TerminalAction]) {
        guard !actions.isEmpty else { return }

        var hasSendData = false
        var hasDisplay = false

        for action in actions {
            switch action {
            case .sendData(let data):
                delegate?.terminal(self, sendData: data)
                hasSendData = true
            case .needsDisplay:
                hasDisplay = true
            default:
                break
            }
        }

        _ = hasSendData

        // Notify delegate of all actions
        delegate?.terminal(self, produced: actions)

        // Always request display after processing
        if !hasDisplay {
            delegate?.terminalNeedsDisplay(self)
        }
    }
}
