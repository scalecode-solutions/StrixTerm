#if canImport(AppKit) && canImport(MetalKit)
import AppKit
import MetalKit
import FredTermCore
import FredTermConfig

// MARK: - Delegate Protocol

/// Delegate for MacTerminalBackingView events.
@MainActor
public protocol MacTerminalViewDelegate: AnyObject {
    /// Called when the terminal view needs to send data to the host process.
    func terminalView(_ view: MacTerminalBackingView, sendData data: [UInt8])
    /// Called when the terminal dimensions change due to a resize.
    func terminalView(_ view: MacTerminalBackingView, sizeChanged newSize: TerminalSize)
    /// Called when the terminal title changes.
    func terminalViewTitleChanged(_ view: MacTerminalBackingView, title: String)
    /// Called when the user Command-clicks a hyperlink.
    func terminalView(_ view: MacTerminalBackingView, openURL url: String)
}

/// Default implementations for optional delegate methods.
public extension MacTerminalViewDelegate {
    func terminalView(_ view: MacTerminalBackingView, openURL url: String) {}
}

// MARK: - MacTerminalBackingView

/// The NSView subclass that hosts the Metal renderer and handles keyboard input.
///
/// This view is the core macOS terminal surface. It manages:
/// - A child MTKView for Metal-based rendering
/// - Keyboard input via NSTextInputClient for full IME support
/// - Basic mouse handling for text selection and scrollback
/// - Terminal size calculation based on cell dimensions
@MainActor
public class MacTerminalBackingView: NSView, @preconcurrency NSTextInputClient {

    // MARK: - Properties

    /// The terminal model driving this view.
    public let terminal: Terminal

    /// The Metal view used for rendering terminal content.
    public private(set) var metalView: MTKView!

    /// The key encoder for translating NSEvents to terminal sequences.
    public let keyEncoder = KeyEncoder()

    /// Delegate for communicating events to the host.
    public weak var delegate: MacTerminalViewDelegate?

    /// The view configuration (font, colors, etc.).
    public var configuration: TerminalViewConfiguration

    /// Cell dimensions in points, used for grid size calculations.
    public var cellWidth: CGFloat = 8.0
    public var cellHeight: CGFloat = 16.0

    /// The current terminal size in columns and rows.
    public private(set) var terminalSize: TerminalSize

    // IME state
    private var markedTextValue: NSAttributedString?
    private var markedRangeValue: NSRange = NSRange(location: NSNotFound, length: 0)
    private var selectedRangeValue: NSRange = NSRange(location: 0, length: 0)

    // Mouse state
    private var mouseDownPosition: Position?
    private var selectionStart: Position?
    private var selectionEnd: Position?

    // Link hover state
    private var isHoveringLink: Bool = false
    private var hoveredLinkURL: String?

    /// The Metal renderer, if available. Set by the view layer for link highlighting.
    public var renderer: MetalRenderer?

    // MARK: - Initialization

    /// Create a new terminal backing view.
    ///
    /// - Parameters:
    ///   - terminal: The terminal model to display and interact with.
    ///   - configuration: Visual configuration for the terminal.
    ///   - frame: The initial frame rectangle.
    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        frame: NSRect = .zero
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self.terminalSize = terminal.size
        super.init(frame: frame)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MacTerminalBackingView does not support NSCoder initialization")
    }

    // MARK: - View Setup

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Create the Metal view
        let device = MTLCreateSystemDefaultDevice()
        let mtkView = MTKView(frame: bounds, device: device)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.layer?.isOpaque = true
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        addSubview(mtkView)
        self.metalView = mtkView

        // Compute initial cell dimensions from the configured font
        updateCellDimensions()
    }

    /// Recompute cell dimensions from the current font configuration.
    private func updateCellDimensions() {
        let font = NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        let sampleString = NSAttributedString(
            string: "M",
            attributes: [.font: font]
        )
        let size = sampleString.size()
        cellWidth = ceil(size.width)
        cellHeight = ceil(size.height)
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        metalView?.frame = bounds
        recalculateTerminalSize()
    }

    /// Recalculate terminal columns and rows based on the current view bounds
    /// and cell dimensions.
    private func recalculateTerminalSize() {
        guard cellWidth > 0, cellHeight > 0 else { return }
        let newCols = max(1, Int(bounds.width / cellWidth))
        let newRows = max(1, Int(bounds.height / cellHeight))
        let newSize = TerminalSize(cols: newCols, rows: newRows)
        if newSize != terminalSize {
            terminalSize = newSize
            terminal.resize(cols: newCols, rows: newRows)
            delegate?.terminalView(self, sizeChanged: newSize)
        }
    }

    // MARK: - First Responder

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && terminal.sendsFocusEvents {
            delegate?.terminalView(self, sendData: Array("\u{1b}[I".utf8))
        }
        return result
    }

    public override func resignFirstResponder() -> Bool {
        if terminal.sendsFocusEvents {
            delegate?.terminalView(self, sendData: Array("\u{1b}[O".utf8))
        }
        return super.resignFirstResponder()
    }

    // MARK: - Keyboard Input

    public override func keyDown(with event: NSEvent) {
        // Let the input context handle it first for IME
        interpretKeyEvents([event])
    }

    public override func doCommand(by selector: Selector) {
        // Fallback for system-bound selectors. We handle these by checking
        // if the current event encodes to a terminal sequence.
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return }

        if let bytes = keyEncoder.encodeKey(
            event: event,
            applicationCursor: terminal.applicationCursorKeys,
            applicationKeypad: terminal.applicationKeypad,
            kittyFlags: terminal.kittyKeyboardFlags
        ) {
            sendToTerminal(bytes)
        }
    }

    // MARK: - NSTextInputClient

    public func insertText(_ string: Any, replacementRange: NSRange) {
        // Clear any marked text
        unmarkText()

        let text: String
        if let attrString = string as? NSAttributedString {
            text = attrString.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        // Check if we should encode the current event as a special key
        if let event = NSApp.currentEvent, event.type == .keyDown {
            let modifiers = event.modifierFlags
            let hasControl = modifiers.contains(.control)
            let hasOption = modifiers.contains(.option)

            // For modifier combinations, try the key encoder first
            if hasControl || hasOption {
                if let bytes = keyEncoder.encodeKey(
                    event: event,
                    applicationCursor: terminal.applicationCursorKeys,
                    applicationKeypad: terminal.applicationKeypad,
                    kittyFlags: terminal.kittyKeyboardFlags
                ) {
                    sendToTerminal(bytes)
                    return
                }
            }
        }

        // Plain text - send UTF-8 bytes
        let bytes = Array(text.utf8)
        if !bytes.isEmpty {
            sendToTerminal(bytes)
        }
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attrString = string as? NSAttributedString {
            markedTextValue = attrString
        } else if let str = string as? String {
            markedTextValue = NSAttributedString(string: str)
        }
        markedRangeValue = NSRange(location: 0, length: markedTextValue?.length ?? 0)
        selectedRangeValue = selectedRange
        needsDisplay = true
    }

    public func unmarkText() {
        markedTextValue = nil
        markedRangeValue = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }

    public func hasMarkedText() -> Bool {
        return markedTextValue != nil
    }

    public func markedRange() -> NSRange {
        return markedRangeValue
    }

    public func selectedRange() -> NSRange {
        return selectedRangeValue
    }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Position the IME candidate window near the cursor.
        let cursorPos = terminal.cursorPosition
        let x = CGFloat(cursorPos.col) * cellWidth
        let y = CGFloat(cursorPos.row) * cellHeight
        let rectInView = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
        let rectInWindow = convert(rectInView, to: nil)
        let rectInScreen = window?.convertToScreen(rectInWindow) ?? rectInWindow
        return rectInScreen
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    public func characterIndex(for point: NSPoint) -> Int {
        return 0
    }

    // MARK: - Mouse Handling

    /// Track the last button used for drag/release tracking.
    private var lastMouseButton: MouseButton = .left

    public override func mouseDown(with event: NSEvent) {
        let pos = terminalPosition(from: event)
        if terminal.isTrackingMouse {
            lastMouseButton = .left
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .left, action: .press, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        mouseDownPosition = pos
        selectionStart = pos
        selectionEnd = pos
        terminal.startSelection(at: pos)
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let pos = terminalPosition(from: event)
        if terminal.isTrackingMouse {
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: lastMouseButton, action: .motion, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        selectionEnd = pos
        terminal.extendSelection(to: pos)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        let pos = terminalPosition(from: event)
        if terminal.isTrackingMouse {
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .left, action: .release, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }

        // Check for Command-click on a link
        if event.modifierFlags.contains(.command),
           let linkInfo = terminal.link(at: pos) {
            delegate?.terminalView(self, openURL: linkInfo.url)
            return
        }

        selectionEnd = pos
        mouseDownPosition = nil
        terminal.extendSelection(to: pos)
        // Selection is now finalized between selectionStart and selectionEnd
        needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .none, action: .motion, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }

        // Link hover detection
        let pos = terminalPosition(from: event)
        let shouldHighlight: Bool
        switch configuration.linkHighlightMode {
        case .always:
            shouldHighlight = true
        case .hover:
            shouldHighlight = true
        case .hoverWithModifier:
            shouldHighlight = event.modifierFlags.contains(.command)
        case .never:
            shouldHighlight = false
        }

        if shouldHighlight, let linkInfo = terminal.link(at: pos) {
            if let linkRange = terminal.linkRange(at: pos) {
                renderer?.setHoveredLink(range: linkRange)
            }
            hoveredLinkURL = linkInfo.url
            if !isHoveringLink {
                isHoveringLink = true
                NSCursor.pointingHand.set()
            }
            // Show tooltip with the URL
            toolTip = linkInfo.url
            metalView?.needsDisplay = true
        } else {
            if isHoveringLink {
                isHoveringLink = false
                hoveredLinkURL = nil
                renderer?.setHoveredLink(range: nil)
                NSCursor.iBeam.set()
                toolTip = nil
                metalView?.needsDisplay = true
            }
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            lastMouseButton = .right
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .right, action: .press, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        super.rightMouseDown(with: event)
    }

    public override func rightMouseUp(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .right, action: .release, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        super.rightMouseUp(with: event)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .right, action: .motion, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        super.rightMouseDragged(with: event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            lastMouseButton = .middle
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .middle, action: .press, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        super.otherMouseDown(with: event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .middle, action: .release, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        super.otherMouseUp(with: event)
    }

    public override func otherMouseDragged(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            let mods = mouseModifiers(from: event)
            if let data = terminal.encodeMouseEvent(
                button: .middle, action: .motion, position: pos,
                pixelPosition: pixelPosition(for: event),
                modifiers: mods
            ) {
                sendToTerminal(data)
            }
            return
        }
        super.otherMouseDragged(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        if terminal.isTrackingMouse {
            let pos = terminalPosition(from: event)
            let mods = mouseModifiers(from: event)
            let deltaY = event.scrollingDeltaY
            if deltaY != 0 {
                let button: MouseButton = deltaY > 0 ? .scrollUp : .scrollDown
                if let data = terminal.encodeMouseEvent(
                    button: button, action: .press, position: pos,
                    pixelPosition: pixelPosition(for: event),
                    modifiers: mods
                ) {
                    sendToTerminal(data)
                }
            }
            let deltaX = event.scrollingDeltaX
            if deltaX != 0 {
                let button: MouseButton = deltaX > 0 ? .scrollLeft : .scrollRight
                if let data = terminal.encodeMouseEvent(
                    button: button, action: .press, position: pos,
                    pixelPosition: pixelPosition(for: event),
                    modifiers: mods
                ) {
                    sendToTerminal(data)
                }
            }
            return
        }
        let delta = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            // Trackpad - accumulate fractional lines
            let lines = Int(delta / cellHeight)
            if lines != 0 {
                terminal.scroll(delta: -lines)
            }
        } else {
            // Mouse wheel - each notch is 3 lines
            let lines = delta > 0 ? 3 : (delta < 0 ? -3 : 0)
            if lines != 0 {
                terminal.scroll(delta: -lines)
            }
        }
    }

    /// Update cursor rects: show pointing hand over hovered links, iBeam elsewhere.
    public override func resetCursorRects() {
        if isHoveringLink, let linkRange = renderer?.hoveredLinkRange {
            // Compute the rect for the link range
            let linkX = CGFloat(linkRange.start.col) * cellWidth
            let linkWidth = CGFloat(linkRange.end.col - linkRange.start.col + 1) * cellWidth
            let flippedY = bounds.height - CGFloat(linkRange.start.row + 1) * cellHeight
            let linkRect = NSRect(x: linkX, y: flippedY, width: linkWidth, height: cellHeight)
            addCursorRect(linkRect, cursor: .pointingHand)
        }
        addCursorRect(bounds, cursor: .iBeam)
    }

    /// Request mouse-moved events so anyEvent mode can track cursor motion.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    // MARK: - Copy / Paste

    /// Copy the current selection to the pasteboard (Cmd+C).
    @objc public func copy(_ sender: Any?) {
        guard let text = terminal.selectedText(), !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Paste from the pasteboard into the terminal (Cmd+V).
    @objc public func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        terminal.paste(text)
    }

    // MARK: - Bell

    /// Callback invoked when the terminal rings the bell.
    public var onBell: (() -> Void)?

    /// Flash the view background briefly for a visual bell effect.
    public func visualBell() {
        let flashLayer = CALayer()
        flashLayer.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        flashLayer.frame = bounds
        layer?.addSublayer(flashLayer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            flashLayer.removeFromSuperlayer()
        }
    }

    // MARK: - Find Panel

    /// Callback invoked when the user triggers Cmd+F (or Edit > Find).
    /// Set by the SwiftUI TerminalView to toggle the find bar.
    public var onPerformFindPanelAction: (() -> Void)?

    /// Handle standard find panel actions (Cmd+F, Cmd+G, etc.).
    @objc public func performFindPanelAction(_ sender: Any?) {
        onPerformFindPanelAction?()
    }

    /// Override to include find, copy, and paste in the responder chain.
    public override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(performFindPanelAction(_:)) {
            return true
        }
        if aSelector == #selector(copy(_:)) || aSelector == #selector(paste(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }

    // MARK: - Helpers

    /// Convert a mouse event location to a terminal grid position.
    private func terminalPosition(from event: NSEvent) -> Position {
        let localPoint = convert(event.locationInWindow, from: nil)
        let col = max(0, min(terminalSize.cols - 1, Int(localPoint.x / cellWidth)))
        // NSView coordinates have origin at bottom-left; terminal rows go top-down
        let flippedY = bounds.height - localPoint.y
        let row = max(0, min(terminalSize.rows - 1, Int(flippedY / cellHeight)))
        return Position(col: col, row: row)
    }

    /// Convert a mouse event to pixel coordinates (relative to the terminal view).
    private func pixelPosition(for event: NSEvent) -> (x: Int, y: Int) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - localPoint.y
        return (x: max(0, Int(localPoint.x)), y: max(0, Int(flippedY)))
    }

    /// Extract mouse modifier flags from an NSEvent.
    private func mouseModifiers(from event: NSEvent) -> MouseModifiers {
        var mods = MouseModifiers()
        if event.modifierFlags.contains(.shift) {
            mods.insert(.shift)
        }
        if event.modifierFlags.contains(.option) {
            mods.insert(.alt)
        }
        if event.modifierFlags.contains(.control) {
            mods.insert(.control)
        }
        return mods
    }

    /// Send encoded bytes to the terminal and notify the delegate.
    private func sendToTerminal(_ data: [UInt8]) {
        terminal.scrollToBottom()
        terminal.sendInput(data)
        delegate?.terminalView(self, sendData: data)
    }

    // MARK: - Scrollbar

    /// The overlay scroller for navigating scrollback.
    private lazy var scroller: NSScroller = {
        let s = NSScroller(frame: .zero)
        s.scrollerStyle = .overlay
        s.alphaValue = 0.0
        s.target = self
        s.action = #selector(scrollerAction(_:))
        addSubview(s)
        return s
    }()

    /// Update the scroller's position and visibility based on scrollback state.
    public func updateScroller() {
        let snapshot = terminal.snapshot()
        let totalScrollback = snapshot.totalScrollback
        let scrollOffset = snapshot.scrollOffset

        if totalScrollback <= 0 {
            scroller.isHidden = true
            return
        }

        scroller.isHidden = false

        let scrollerWidth: CGFloat = 14.0
        scroller.frame = NSRect(
            x: bounds.width - scrollerWidth,
            y: 0,
            width: scrollerWidth,
            height: bounds.height
        )

        let totalLines = CGFloat(totalScrollback + terminalSize.rows)
        let proportion = CGFloat(terminalSize.rows) / totalLines
        let position = 1.0 - CGFloat(scrollOffset) / CGFloat(totalScrollback)

        scroller.doubleValue = Double(position)
        scroller.knobProportion = proportion

        // Fade in/out based on whether user has scrolled
        let targetAlpha: CGFloat = scrollOffset > 0 ? 0.7 : 0.0
        if scroller.alphaValue != targetAlpha {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                scroller.animator().alphaValue = targetAlpha
            }
        }
    }

    /// Handle scroller action (user dragged the scroller knob).
    @objc private func scrollerAction(_ sender: NSScroller) {
        switch sender.hitPart {
        case .knob, .knobSlot:
            let snapshot = terminal.snapshot()
            let totalScrollback = snapshot.totalScrollback
            let scrollPos = 1.0 - sender.doubleValue
            let targetOffset = Int(scrollPos * Double(totalScrollback))
            let currentOffset = snapshot.scrollOffset
            let delta = targetOffset - currentOffset
            if delta != 0 {
                terminal.scroll(delta: delta)
            }
        case .decrementLine:
            terminal.scroll(delta: 1)
        case .incrementLine:
            terminal.scroll(delta: -1)
        case .decrementPage:
            terminal.scroll(delta: terminalSize.rows)
        case .incrementPage:
            terminal.scroll(delta: -terminalSize.rows)
        default:
            break
        }
        metalView?.needsDisplay = true
    }
}

#endif
