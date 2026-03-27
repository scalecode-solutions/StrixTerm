#if canImport(UIKit) && canImport(MetalKit)
import UIKit
import MetalKit
import StrixTermCore
import StrixTermConfig

// MARK: - Delegate Protocol

/// Delegate for IOSTerminalBackingView events.
@MainActor
public protocol IOSTerminalViewDelegate: AnyObject {
    /// Called when the terminal view needs to send data to the host process.
    func terminalView(_ view: IOSTerminalBackingView, sendData data: [UInt8])
    /// Called when the terminal dimensions change due to a resize.
    func terminalView(_ view: IOSTerminalBackingView, sizeChanged newSize: TerminalSize)
    /// Called when the terminal title changes.
    func terminalViewTitleChanged(_ view: IOSTerminalBackingView, title: String)
    /// Called when the user taps a hyperlink.
    func terminalView(_ view: IOSTerminalBackingView, openURL url: String)
}

/// Default implementations for optional delegate methods.
public extension IOSTerminalViewDelegate {
    func terminalView(_ view: IOSTerminalBackingView, openURL url: String) {}
}

// MARK: - IOSTerminalBackingView

/// The UIView subclass that hosts the Metal renderer and handles input on iOS/visionOS.
///
/// This view is the core iOS/visionOS terminal surface. It manages:
/// - A child MTKView for Metal-based rendering
/// - Software keyboard input via UIKeyInput
/// - Hardware keyboard input via pressesBegan/pressesEnded
/// - Touch gestures for selection (tap, double-tap, triple-tap, long press, pan, pinch)
/// - A keyboard accessory toolbar with Esc, Tab, Ctrl, Alt, arrows, and pipe keys
/// - Two-finger pan for scrollback navigation
@MainActor
public class IOSTerminalBackingView: UIView, UIKeyInput, UITextInputTraits {

    // MARK: - Properties

    /// The terminal model driving this view.
    public let terminal: Terminal

    /// The Metal view used for rendering terminal content.
    public private(set) var metalView: MTKView!

    /// The Metal renderer (reuses the same MetalRenderer as macOS).
    public private(set) var renderer: MetalRenderer?

    /// The key encoder for translating UIPress events to terminal sequences.
    public let keyEncoder = IOSKeyEncoder()

    /// Delegate for communicating events to the host.
    public weak var delegate: IOSTerminalViewDelegate?

    /// The view configuration (font, colors, etc.).
    public var configuration: TerminalViewConfiguration

    /// Cell dimensions in points, used for grid size calculations.
    public var cellWidth: CGFloat = 8.0
    public var cellHeight: CGFloat = 16.0

    /// The current terminal size in columns and rows.
    public private(set) var terminalSize: TerminalSize

    // Modifier state for the accessory bar virtual modifier keys
    private var accessoryCtrlActive: Bool = false
    private var accessoryAltActive: Bool = false

    // Touch/selection state
    private var selectionStart: Position?
    private var selectionEnd: Position?
    private var isLongPressActive: Bool = false

    // Mouse tracking gesture
    private var mouseTrackingPan: UIPanGestureRecognizer?
    private var mouseTrackingSingleTap: UITapGestureRecognizer?

    // Scroll state
    private var isUserScrolling: Bool = false
    private var scrollAccumulator: CGFloat = 0.0

    // Pinch state
    private var initialFontSize: CGFloat = 0.0

    // MARK: - Initialization

    /// Create a new iOS terminal backing view.
    ///
    /// - Parameters:
    ///   - terminal: The terminal model to display and interact with.
    ///   - configuration: Visual configuration for the terminal.
    ///   - frame: The initial frame rectangle.
    public init(
        terminal: Terminal,
        configuration: TerminalViewConfiguration = .default,
        frame: CGRect = .zero
    ) {
        self.terminal = terminal
        self.configuration = configuration
        self.terminalSize = terminal.size
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IOSTerminalBackingView does not support NSCoder initialization")
    }

    // MARK: - View Setup

    private func setupView() {
        backgroundColor = .black

        // Create the Metal view
        let device = MTLCreateSystemDefaultDevice()
        let mtkView = MTKView(frame: bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.isOpaque = true
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        addSubview(mtkView)
        self.metalView = mtkView

        // Create the renderer
        if let device = device {
            renderer = MetalRenderer(
                device: device,
                terminal: terminal,
                fontFamily: configuration.fontFamily,
                fontSize: configuration.fontSize
            )
            if let renderer = renderer {
                mtkView.delegate = renderer
                cellWidth = renderer.cellSize.width
                cellHeight = renderer.cellSize.height
            }
        }

        // Compute initial cell dimensions from the configured font if renderer
        // failed to initialize
        if renderer == nil {
            updateCellDimensions()
        }
    }

    /// Recompute cell dimensions from the current font configuration.
    private func updateCellDimensions() {
        let font = UIFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        let sampleString = NSAttributedString(
            string: "M",
            attributes: [.font: font]
        )
        let size = sampleString.size()
        cellWidth = ceil(size.width)
        cellHeight = ceil(size.height)
    }

    // MARK: - Gesture Setup

    private func setupGestures() {
        // Single tap: become first responder (show keyboard), or mouse click when tracking.
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        addGestureRecognizer(singleTap)

        // Double tap: select word at tap location
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)

        // Triple tap: select line (addresses SwiftTerm issue #282)
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(handleTripleTap(_:)))
        tripleTap.numberOfTapsRequired = 3
        addGestureRecognizer(tripleTap)
        doubleTap.require(toFail: tripleTap)

        // Long press: start selection at press location
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPress)

        // Single-finger pan for mouse drag tracking.
        let mouseTrackPan = UIPanGestureRecognizer(target: self, action: #selector(handleMouseTrackingPan(_:)))
        mouseTrackPan.minimumNumberOfTouches = 1
        mouseTrackPan.maximumNumberOfTouches = 1
        addGestureRecognizer(mouseTrackPan)
        self.mouseTrackingPan = mouseTrackPan

        // Two-finger pan: scroll through scrollback buffer
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)

        // Pinch: font size adjustment (addresses SwiftTerm issue #272/#495)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
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

    public override var canBecomeFirstResponder: Bool { true }

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

    // MARK: - Copy / Paste

    /// Copy the current selection to the system pasteboard.
    public func copySelection() {
        guard let text = terminal.selectedText(), !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    /// Paste from the system pasteboard into the terminal.
    public func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        terminal.paste(text)
    }

    // MARK: - Bell

    /// Callback invoked when the terminal rings the bell.
    public var onBell: (() -> Void)?

    /// Flash the view background briefly for a visual bell effect.
    public func visualBell() {
        let flashView = UIView(frame: bounds)
        flashView.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        flashView.isUserInteractionEnabled = false
        addSubview(flashView)
        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 0.0
        }) { _ in
            flashView.removeFromSuperview()
        }
    }

    // MARK: - UIKeyInput

    public var hasText: Bool { true }

    public func insertText(_ text: String) {
        // If accessory modifiers are active, encode with them
        if accessoryCtrlActive || accessoryAltActive {
            if accessoryCtrlActive {
                if let ctrlBytes = encodeControlCharacter(text) {
                    if accessoryAltActive {
                        sendToTerminal([0x1B] + ctrlBytes)
                    } else {
                        sendToTerminal(ctrlBytes)
                    }
                    clearAccessoryModifiers()
                    return
                }
            }
            if accessoryAltActive {
                let bytes = Array(text.utf8)
                if !bytes.isEmpty {
                    sendToTerminal([0x1B] + bytes)
                    clearAccessoryModifiers()
                    return
                }
            }
            clearAccessoryModifiers()
        }

        // Plain text - send UTF-8 bytes
        let bytes = Array(text.utf8)
        if !bytes.isEmpty {
            sendToTerminal(bytes)
        }
    }

    public func deleteBackward() {
        sendToTerminal([0x7F])
    }

    // MARK: - UITextInputTraits

    public var autocorrectionType: UITextAutocorrectionType {
        get { .no }
        set { }
    }

    public var autocapitalizationType: UITextAutocapitalizationType {
        get { .none }
        set { }
    }

    public var spellCheckingType: UITextSpellCheckingType {
        get { .no }
        set { }
    }

    public var smartQuotesType: UITextSmartQuotesType {
        get { .no }
        set { }
    }

    public var smartDashesType: UITextSmartDashesType {
        get { .no }
        set { }
    }

    public var smartInsertDeleteType: UITextSmartInsertDeleteType {
        get { .no }
        set { }
    }

    public var keyboardType: UIKeyboardType {
        get { .default }
        set { }
    }

    // MARK: - Hardware Keyboard Support (pressesBegan/pressesEnded)

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        for press in presses {
            if let bytes = keyEncoder.encodePress(
                press,
                applicationCursor: terminal.applicationCursorKeys,
                applicationKeypad: terminal.applicationKeypad,
                kittyFlags: terminal.kittyKeyboardFlags
            ) {
                sendToTerminal(bytes)
                handled = true
            }
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
    }

    // MARK: - Touch Gesture Handlers

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            if terminal.isTrackingMouse {
                let point = gesture.location(in: self)
                let pos = terminalPosition(from: point)
                // Send press + release for a tap.
                if let pressData = terminal.encodeMouseEvent(
                    button: .left, action: .press, position: pos
                ) {
                    sendToTerminal(pressData)
                }
                if let releaseData = terminal.encodeMouseEvent(
                    button: .left, action: .release, position: pos
                ) {
                    sendToTerminal(releaseData)
                }
            } else {
                // Check if the tap is on a hyperlink
                let point = gesture.location(in: self)
                let pos = terminalPosition(from: point)
                if let linkInfo = terminal.link(at: pos) {
                    delegate?.terminalView(self, openURL: linkInfo.url)
                    return
                }
            }
            becomeFirstResponder()
        }
    }

    @objc private func handleMouseTrackingPan(_ gesture: UIPanGestureRecognizer) {
        guard terminal.isTrackingMouse else { return }
        let point = gesture.location(in: self)
        let pos = terminalPosition(from: point)
        switch gesture.state {
        case .began:
            if let data = terminal.encodeMouseEvent(
                button: .left, action: .press, position: pos
            ) {
                sendToTerminal(data)
            }
        case .changed:
            if let data = terminal.encodeMouseEvent(
                button: .left, action: .motion, position: pos
            ) {
                sendToTerminal(data)
            }
        case .ended, .cancelled:
            if let data = terminal.encodeMouseEvent(
                button: .left, action: .release, position: pos
            ) {
                sendToTerminal(data)
            }
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // When mouse tracking is active, ignore selection gestures.
        guard !terminal.isTrackingMouse else { return }
        let point = gesture.location(in: self)
        let pos = terminalPosition(from: point)

        // Select word at tap location
        let boundaries = Selection.wordBoundaries(
            at: pos,
            in: terminal.snapshot().cells,
            cols: terminalSize.cols,
            yBase: 0
        )
        selectionStart = boundaries.start
        selectionEnd = boundaries.end
        terminal.startSelection(at: boundaries.start, mode: .word)
        terminal.extendSelection(to: boundaries.end)
        setNeedsDisplay()
    }

    @objc private func handleTripleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // When mouse tracking is active, ignore selection gestures.
        guard !terminal.isTrackingMouse else { return }
        let point = gesture.location(in: self)
        let pos = terminalPosition(from: point)

        // Select entire line (addresses SwiftTerm issue #282)
        selectionStart = Position(col: 0, row: pos.row)
        selectionEnd = Position(col: terminalSize.cols - 1, row: pos.row)
        terminal.startSelection(at: Position(col: 0, row: pos.row), mode: .line)
        terminal.extendSelection(to: Position(col: terminalSize.cols - 1, row: pos.row))
        setNeedsDisplay()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // When mouse tracking is active, ignore selection gestures.
        guard !terminal.isTrackingMouse else { return }
        let point = gesture.location(in: self)
        let pos = terminalPosition(from: point)

        switch gesture.state {
        case .began:
            // Check for link under the long press
            if let linkInfo = terminal.link(at: pos) {
                showLinkContextMenu(url: linkInfo.url, at: point)
                return
            }
            isLongPressActive = true
            selectionStart = pos
            selectionEnd = pos
            terminal.startSelection(at: pos)
            setNeedsDisplay()
        case .changed:
            if isLongPressActive {
                selectionEnd = pos
                terminal.extendSelection(to: pos)
                setNeedsDisplay()
            }
        case .ended, .cancelled:
            if isLongPressActive {
                selectionEnd = pos
                terminal.extendSelection(to: pos)
                isLongPressActive = false
                setNeedsDisplay()
            }
        default:
            break
        }
    }

    /// Show a context menu for a link at the given point.
    private func showLinkContextMenu(url: String, at point: CGPoint) {
        let alert = UIAlertController(title: url, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Open Link", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.terminalView(self, openURL: url)
        })
        alert.addAction(UIAlertAction(title: "Copy Link", style: .default) { _ in
            UIPasteboard.general.string = url
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // For iPad: set popover anchor
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }

        // Find the nearest view controller to present the alert
        if let viewController = findViewController() {
            viewController.present(alert, animated: true)
        }
    }

    /// Walk the responder chain to find a UIViewController.
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController {
                return vc
            }
            responder = r.next
        }
        return nil
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        if terminal.isTrackingMouse {
            // When mouse tracking is active, two-finger scroll sends scroll button events.
            guard gesture.state == .changed else { return }
            let delta = gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            scrollAccumulator += delta
            let lines = Int(scrollAccumulator / cellHeight)
            if lines != 0 {
                let point = gesture.location(in: self)
                let pos = terminalPosition(from: point)
                let button: MouseButton = lines > 0 ? .scrollUp : .scrollDown
                let count = abs(lines)
                for _ in 0..<count {
                    if let data = terminal.encodeMouseEvent(
                        button: button, action: .press, position: pos
                    ) {
                        sendToTerminal(data)
                    }
                }
                scrollAccumulator -= CGFloat(lines) * cellHeight
            }
            return
        }
        switch gesture.state {
        case .began:
            isUserScrolling = true
            scrollAccumulator = 0.0
        case .changed:
            let delta = gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            scrollAccumulator += delta
            let lines = Int(scrollAccumulator / cellHeight)
            if lines != 0 {
                terminal.scroll(delta: -lines)
                scrollAccumulator -= CGFloat(lines) * cellHeight
                metalView?.setNeedsDisplay()
            }
        case .ended, .cancelled:
            isUserScrolling = false
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialFontSize = configuration.fontSize
        case .changed:
            let newSize = max(8.0, min(36.0, initialFontSize * gesture.scale))
            configuration.fontSize = newSize
            updateCellDimensions()
            recalculateTerminalSize()
            metalView?.setNeedsDisplay()
        case .ended:
            break
        default:
            break
        }
    }

    // MARK: - Keyboard Accessory View

    public override var inputAccessoryView: UIView? {
        return makeAccessoryToolbar()
    }

    private func makeAccessoryToolbar() -> UIView {
        let toolbar = UIToolbar()
        toolbar.barStyle = .default
        toolbar.isTranslucent = true
        toolbar.sizeToFit()

        let escButton = UIBarButtonItem(title: "Esc", style: .plain, target: self, action: #selector(accessoryEsc))
        let tabButton = UIBarButtonItem(title: "Tab", style: .plain, target: self, action: #selector(accessoryTab))
        let ctrlButton = UIBarButtonItem(title: "Ctrl", style: .plain, target: self, action: #selector(accessoryCtrl))
        let altButton = UIBarButtonItem(title: "Alt", style: .plain, target: self, action: #selector(accessoryAlt))
        let upButton = UIBarButtonItem(title: "\u{25B2}", style: .plain, target: self, action: #selector(accessoryUp))
        let downButton = UIBarButtonItem(title: "\u{25BC}", style: .plain, target: self, action: #selector(accessoryDown))
        let leftButton = UIBarButtonItem(title: "\u{25C0}", style: .plain, target: self, action: #selector(accessoryLeft))
        let rightButton = UIBarButtonItem(title: "\u{25B6}", style: .plain, target: self, action: #selector(accessoryRight))
        let pipeButton = UIBarButtonItem(title: "|", style: .plain, target: self, action: #selector(accessoryPipe))

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [
            escButton, flexSpace,
            tabButton, flexSpace,
            ctrlButton, flexSpace,
            altButton, flexSpace,
            upButton, flexSpace,
            downButton, flexSpace,
            leftButton, flexSpace,
            rightButton, flexSpace,
            pipeButton
        ]

        return toolbar
    }

    // MARK: - Accessory Button Actions

    @objc private func accessoryEsc() {
        sendToTerminal([0x1B])
    }

    @objc private func accessoryTab() {
        sendToTerminal([0x09])
    }

    @objc private func accessoryCtrl() {
        accessoryCtrlActive.toggle()
    }

    @objc private func accessoryAlt() {
        accessoryAltActive.toggle()
    }

    @objc private func accessoryUp() {
        let seq: [UInt8] = terminal.applicationCursorKeys
            ? [0x1B, 0x4F, 0x41]  // ESC O A
            : [0x1B, 0x5B, 0x41]  // ESC [ A
        sendToTerminal(seq)
    }

    @objc private func accessoryDown() {
        let seq: [UInt8] = terminal.applicationCursorKeys
            ? [0x1B, 0x4F, 0x42]  // ESC O B
            : [0x1B, 0x5B, 0x42]  // ESC [ B
        sendToTerminal(seq)
    }

    @objc private func accessoryLeft() {
        let seq: [UInt8] = terminal.applicationCursorKeys
            ? [0x1B, 0x4F, 0x44]  // ESC O D
            : [0x1B, 0x5B, 0x44]  // ESC [ D
        sendToTerminal(seq)
    }

    @objc private func accessoryRight() {
        let seq: [UInt8] = terminal.applicationCursorKeys
            ? [0x1B, 0x4F, 0x43]  // ESC O C
            : [0x1B, 0x5B, 0x43]  // ESC [ C
        sendToTerminal(seq)
    }

    @objc private func accessoryPipe() {
        sendToTerminal(Array("|".utf8))
    }

    private func clearAccessoryModifiers() {
        accessoryCtrlActive = false
        accessoryAltActive = false
    }

    // MARK: - Helpers

    /// Convert a touch point to a terminal grid position.
    private func terminalPosition(from point: CGPoint) -> Position {
        let col = max(0, min(terminalSize.cols - 1, Int(point.x / cellWidth)))
        let row = max(0, min(terminalSize.rows - 1, Int(point.y / cellHeight)))
        return Position(col: col, row: row)
    }

    /// Encode a single character as a Ctrl+key control character.
    private func encodeControlCharacter(_ text: String) -> [UInt8]? {
        guard let baseChar = text.lowercased().unicodeScalars.first else {
            return nil
        }
        let value = baseChar.value
        // Ctrl+A through Ctrl+Z -> 0x01 through 0x1A
        if value >= UInt32(Character("a").asciiValue!),
           value <= UInt32(Character("z").asciiValue!) {
            let ctrl = UInt8(value - UInt32(Character("a").asciiValue!) + 1)
            return [ctrl]
        }
        return nil
    }

    /// Send encoded bytes to the terminal and notify the delegate.
    private func sendToTerminal(_ data: [UInt8]) {
        if !isUserScrolling {
            terminal.scrollToBottom()
        }
        terminal.sendInput(data)
        delegate?.terminalView(self, sendData: data)
    }

    /// Request a display update. Call this when scrollback changes or new output arrives.
    /// Auto-scrolls to bottom on new output unless the user is actively scrolling
    /// (fixes SwiftTerm issue #486).
    public func terminalDidProduceOutput() {
        if !isUserScrolling {
            terminal.scrollToBottom()
        }
        metalView?.setNeedsDisplay()
    }
}

// MARK: - Selection Helpers (word boundaries from flat cell array)

private extension Selection {
    /// Compute word boundaries from a flat cell array and column count.
    static func wordBoundaries(
        at position: Position,
        in cells: [Cell],
        cols: Int,
        yBase: Int
    ) -> (start: Position, end: Position) {
        let row = position.row
        let lineStart = row * cols

        guard lineStart >= 0, lineStart + cols <= cells.count else {
            return (position, position)
        }

        // Find word start
        var startCol = position.col
        while startCol > 0 {
            let cell = cells[lineStart + startCol - 1]
            if isWordSeparator(cell.codePoint) { break }
            startCol -= 1
        }

        // Find word end
        var endCol = position.col
        while endCol < cols - 1 {
            let cell = cells[lineStart + endCol + 1]
            if isWordSeparator(cell.codePoint) { break }
            endCol += 1
        }

        return (Position(col: startCol, row: row),
                Position(col: endCol, row: row))
    }

    private static func isWordSeparator(_ cp: UInt32) -> Bool {
        switch cp {
        case 0x20, 0x09, 0x0A, 0x0D: return true  // whitespace
        case 0x22, 0x27, 0x28, 0x29: return true  // quotes, parens
        case 0x5B, 0x5D, 0x7B, 0x7D: return true  // brackets, braces
        case 0x3C, 0x3E: return true               // angle brackets
        case 0x2C, 0x2E, 0x3B, 0x3A: return true  // punctuation
        default: return false
        }
    }
}

#endif
