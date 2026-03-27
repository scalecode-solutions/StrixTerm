/// Actions produced by terminal state mutations, consumed by the UI layer or host.
///
/// Instead of the large delegate protocol pattern used by SwiftTerm (25+ callback methods),
/// StrixTerm emits actions. This makes the terminal state machine pure and testable.
public enum TerminalAction: Sendable {
    /// Data to send back to the host process (terminal responses).
    case sendData([UInt8])
    /// Set the window title.
    case setTitle(String)
    /// Set the icon title.
    case setIconTitle(String)
    /// Terminal bell.
    case bell
    /// Scroll position changed.
    case scrolled(yDisp: Int)
    /// Show the cursor.
    case showCursor
    /// Hide the cursor.
    case hideCursor
    /// Change the cursor style.
    case cursorStyleChanged(CursorStyle)
    /// A color in the palette changed (nil = all changed).
    case colorChanged(index: Int?)
    /// Foreground/background color changed.
    case defaultColorChanged(fg: TerminalColor?, bg: TerminalColor?)
    /// Mouse mode changed.
    case mouseModeChanged(MouseMode)
    /// Selection changed.
    case selectionChanged
    /// Copy to clipboard.
    case clipboardCopy(String)
    /// Open a URL.
    case openLink(url: String, params: [String: String])
    /// Desktop notification (OSC 9 / OSC 777).
    case notify(title: String, body: String)
    /// Request terminal resize (e.g. from DECCOLM).
    case requestResize(cols: Int, rows: Int)
    /// Semantic prompt state changed (OSC 133).
    case promptStateChanged(PromptZone)
    /// Progress report (OSC 9;4).
    case progressReport(state: ProgressState, value: Int?)
    /// Buffer switched (normal <-> alternate).
    case bufferActivated(isAlternate: Bool)
    /// Focus mode changed.
    case focusModeChanged(Bool)
    /// Bracketed paste mode changed.
    case bracketedPasteModeChanged(Bool)
    /// Set the cursor color.
    case setCursorColor(TerminalColor?)
    /// Request the window to perform an action.
    case windowCommand(WindowCommand)
    /// Terminal needs redisplay.
    case needsDisplay
    /// Set the current working directory (OSC 7).
    case setCurrentDirectory(String)
    /// A Kitty graphics image has been placed.
    case imagePlaced(placement: KittyPlacement)
    /// A Kitty graphics image has been deleted (nil = all).
    case imageDeleted(imageId: UInt32?)
}

/// Progress reporting state (OSC 9;4).
public enum ProgressState: UInt8, Sendable {
    case hidden = 0
    case active = 1
    case error = 2
    case indeterminate = 3
    case paused = 4
}

/// Window manipulation commands (CSI t).
public enum WindowCommand: Sendable {
    case deiconify
    case iconify
    case moveWindow(x: Int, y: Int)
    case resizePixels(width: Int, height: Int)
    case raise
    case lower
    case resizeChars(cols: Int, rows: Int)
    case maximize
    case restore
    case reportState
    case reportPosition
    case reportPixelSize
    case reportCharSize
    case reportScreenSize
    case reportIconTitle
    case reportTitle
}
