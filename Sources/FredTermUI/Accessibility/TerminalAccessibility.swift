#if canImport(AppKit)
import AppKit
import FredTermCore

// MARK: - TerminalAccessibilityService (macOS)

/// Provides accessibility support for the terminal view on macOS.
///
/// This addresses SwiftTerm issue #12 by implementing NSAccessibility methods
/// that expose terminal content to VoiceOver and other assistive technologies.
@MainActor
public class TerminalAccessibilityService {

    private weak var terminal: Terminal?
    private weak var view: NSView?

    /// Cell dimensions for computing screen rects.
    public var cellWidth: CGFloat = 8.0
    public var cellHeight: CGFloat = 16.0

    public init(terminal: Terminal, view: NSView) {
        self.terminal = terminal
        self.view = view
    }

    // MARK: - Role and Description

    public func accessibilityRole() -> NSAccessibility.Role {
        .textArea
    }

    public func accessibilityRoleDescription() -> String {
        "terminal"
    }

    public func accessibilityLabel() -> String {
        "Terminal"
    }

    public func isAccessibilityElement() -> Bool {
        true
    }

    // MARK: - Text Content

    /// Returns all visible terminal text.
    public func accessibilityValue() -> String {
        guard let terminal = terminal else { return "" }
        return terminal.visibleText()
    }

    /// Returns the total number of characters in the visible buffer.
    public func accessibilityNumberOfCharacters() -> Int {
        let text = accessibilityValue()
        return text.count
    }

    /// Returns the text within the given character range.
    public func accessibilityString(for range: NSRange) -> String? {
        let text = accessibilityValue()
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    // MARK: - Line Information

    /// Returns the visible text split into lines.
    private func visibleLines() -> [String] {
        guard let terminal = terminal else { return [] }
        let size = terminal.size
        var lines: [String] = []
        for row in 0..<size.rows {
            lines.append(terminal.lineText(row))
        }
        return lines
    }

    /// Returns the line number (row) for the character at the given index.
    public func accessibilityLine(for index: Int) -> Int {
        let lines = visibleLines()
        var offset = 0
        for (lineNumber, line) in lines.enumerated() {
            let lineLength = line.count + 1 // +1 for the newline
            if index < offset + lineLength {
                return lineNumber
            }
            offset += lineLength
        }
        return max(0, lines.count - 1)
    }

    /// Returns the character range for the given line number.
    public func accessibilityRange(forLine line: Int) -> NSRange {
        let lines = visibleLines()
        guard line >= 0 && line < lines.count else {
            return NSRange(location: 0, length: 0)
        }
        var offset = 0
        for i in 0..<line {
            offset += lines[i].count + 1 // +1 for newline
        }
        return NSRange(location: offset, length: lines[line].count)
    }

    /// Returns the word range at the given character index.
    public func accessibilityRange(for index: Int) -> NSRange {
        let text = accessibilityValue()
        let nsText = text as NSString
        guard index >= 0 && index < nsText.length else {
            return NSRange(location: 0, length: 0)
        }
        // Use NSString word boundary detection
        let wordRange = nsText.rangeOfComposedCharacterSequence(at: index)
        return wordRange
    }

    /// Returns the screen rect for the given character range.
    public func accessibilityFrame(for range: NSRange) -> NSRect {
        guard let view = view else { return .zero }
        let lines = visibleLines()
        var offset = 0
        for (row, line) in lines.enumerated() {
            let lineLength = line.count + 1
            if range.location < offset + lineLength {
                let col = range.location - offset
                let x = CGFloat(col) * cellWidth
                let y = CGFloat(row) * cellHeight
                let width = CGFloat(range.length) * cellWidth
                let rectInView = NSRect(x: x, y: y, width: width, height: cellHeight)
                let rectInWindow = view.convert(rectInView, to: nil)
                return view.window?.convertToScreen(rectInWindow) ?? rectInWindow
            }
            offset += lineLength
        }
        return .zero
    }

    // MARK: - Cursor

    /// Returns the line number where the insertion point (cursor) is.
    public func accessibilityInsertionPointLineNumber() -> Int {
        guard let terminal = terminal else { return 0 }
        return terminal.cursorPosition.row
    }

    /// Returns the character range of all visible text.
    public func accessibilityVisibleCharacterRange() -> NSRange {
        let count = accessibilityNumberOfCharacters()
        return NSRange(location: 0, length: count)
    }

    // MARK: - VoiceOver Announcements

    /// Post a value-changed notification when new terminal output arrives.
    public func announceOutputChanged() {
        guard let view = view else { return }
        NSAccessibility.post(element: view, notification: .valueChanged)
    }

    /// Post a notification when the cursor moves.
    public func announceCursorMoved() {
        guard let view = view else { return }
        NSAccessibility.post(element: view, notification: .selectedTextChanged)
    }

    /// Post an announcement when the terminal bell sounds.
    public func announceBell() {
        guard let view = view else { return }
        let announcement: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: "Bell",
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ]
        NSAccessibility.post(
            element: view,
            notification: .announcementRequested,
            userInfo: announcement
        )
    }
}

// MARK: - NSAccessibility Extension for MacTerminalBackingView

extension MacTerminalBackingView {

    // MARK: - NSAccessibility Protocol

    public override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    public override func accessibilityRoleDescription() -> String? {
        "terminal"
    }

    public override func accessibilityLabel() -> String? {
        "Terminal"
    }

    public override func isAccessibilityElement() -> Bool {
        true
    }

    public override func accessibilityValue() -> Any? {
        terminal.visibleText()
    }

    public override func accessibilityNumberOfCharacters() -> Int {
        let text = terminal.visibleText()
        return text.count
    }

    public override func accessibilityString(for range: NSRange) -> String? {
        let text = terminal.visibleText()
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    public override func accessibilityLine(for index: Int) -> Int {
        var offset = 0
        let size = terminal.size
        for row in 0..<size.rows {
            let line = terminal.lineText(row)
            let lineLength = line.count + 1
            if index < offset + lineLength {
                return row
            }
            offset += lineLength
        }
        return max(0, size.rows - 1)
    }

    public override func accessibilityRange(forLine line: Int) -> NSRange {
        let size = terminal.size
        guard line >= 0 && line < size.rows else {
            return NSRange(location: 0, length: 0)
        }
        var offset = 0
        for i in 0..<line {
            offset += terminal.lineText(i).count + 1
        }
        return NSRange(location: offset, length: terminal.lineText(line).count)
    }

    public override func accessibilityRange(for index: Int) -> NSRange {
        let text = terminal.visibleText()
        let nsText = text as NSString
        guard index >= 0 && index < nsText.length else {
            return NSRange(location: 0, length: 0)
        }
        return nsText.rangeOfComposedCharacterSequence(at: index)
    }

    public override func accessibilityFrame(for range: NSRange) -> NSRect {
        var offset = 0
        let size = terminal.size
        for row in 0..<size.rows {
            let line = terminal.lineText(row)
            let lineLength = line.count + 1
            if range.location < offset + lineLength {
                let col = range.location - offset
                let x = CGFloat(col) * cellWidth
                let y = CGFloat(row) * cellHeight
                let width = CGFloat(range.length) * cellWidth
                let rectInView = NSRect(x: x, y: y, width: width, height: cellHeight)
                let rectInWindow = convert(rectInView, to: nil)
                return window?.convertToScreen(rectInWindow) ?? rectInWindow
            }
            offset += lineLength
        }
        return .zero
    }

    public override func accessibilityInsertionPointLineNumber() -> Int {
        terminal.cursorPosition.row
    }

    public override func accessibilityVisibleCharacterRange() -> NSRange {
        let count = accessibilityNumberOfCharacters()
        return NSRange(location: 0, length: count)
    }
}

#elseif canImport(UIKit)
import UIKit
import FredTermCore

// MARK: - TerminalAccessibilityService (iOS/visionOS)

/// Provides accessibility support for the terminal view on iOS and visionOS.
///
/// This addresses SwiftTerm issue #12 by exposing terminal content
/// to VoiceOver on Apple's non-macOS platforms.
public class TerminalAccessibilityService {

    private weak var terminal: Terminal?
    private weak var view: UIView?

    public init(terminal: Terminal, view: UIView) {
        self.terminal = terminal
        self.view = view
    }

    /// Configure accessibility properties on the given UIView.
    public func configureAccessibility() {
        guard let view = view else { return }
        view.isAccessibilityElement = true
        view.accessibilityTraits = .staticText
        view.accessibilityLabel = "Terminal"
        updateAccessibilityValue()
    }

    /// Update the accessibility value with current visible text.
    public func updateAccessibilityValue() {
        guard let view = view, let terminal = terminal else { return }
        view.accessibilityValue = terminal.visibleText()
    }

    /// Post a notification when terminal output changes.
    public func announceOutputChanged() {
        guard let view = view else { return }
        updateAccessibilityValue()
        UIAccessibility.post(notification: .screenChanged, argument: view)
    }

    /// Post a notification when the cursor moves.
    public func announceCursorMoved() {
        guard let view = view else { return }
        UIAccessibility.post(notification: .layoutChanged, argument: view)
    }

    /// Post an announcement when the terminal bell sounds.
    public func announceBell() {
        UIAccessibility.post(
            notification: .announcement,
            argument: "Bell"
        )
    }
}

#endif
