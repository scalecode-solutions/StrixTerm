# StrixTerm

A modern terminal emulator library for Apple platforms (macOS, iOS, visionOS), written in Swift 6.

## Features

### Terminal Emulation
- Full xterm-256color terminal emulation
- 24-bit true color support
- Alternate buffer (for vim, less, etc.)
- Configurable scrollback buffer (default 10,000 lines)
- Bracketed paste mode
- Synchronized output mode (DCS-based batched rendering)
- Reverse video (DECSCNM)
- Application cursor keys and application keypad modes

### Keyboard
- Kitty keyboard protocol support
- Focus event reporting

### Mouse
- Mouse tracking modes (click, drag, any-event)
- SGR, UTF-8, and X10 mouse encodings

### Rendering
- Metal-based GPU renderer with custom shaders
- SwiftUI views for macOS (NSViewRepresentable) and iOS/visionOS (UIViewRepresentable)
- Cursor styles: block, underline, bar (blinking and steady variants)
- Configurable font family, font size, line spacing, and letter spacing
- Window opacity control

### Links
- OSC 8 explicit hyperlinks with parameter support
- Implicit URL detection (auto-detected from terminal text)
- Configurable highlight modes: always, hover, hover-with-modifier, never

### Search
- Full-text search across visible area and scrollback
- Case-sensitive and case-insensitive matching
- Regex search
- Whole-word matching
- Built-in find bar overlay (Cmd+F on macOS)

### Text Selection
- Character, word, and line selection modes
- Selected text extraction

### Images
- Sixel graphics support
- Kitty graphics protocol (image placement and caching)

### Shell Integration
- OSC 7 current working directory tracking
- OSC 9 / OSC 777 desktop notifications
- OSC 133 semantic prompt zones
- OSC 9;4 progress reporting
- Window manipulation commands (CSI t)
- Clipboard integration (OSC 52)

### Configuration
- Codable profiles with appearance, shell, and terminal settings
- 9 built-in color palettes
- Per-profile shell command, arguments, environment, and working directory

### Process Management
- PTY-based child process hosting
- Proper data draining after process exit (no lost output)
- DispatchSource-based I/O (no RunLoop mode issues)
- Window size (SIGWINCH) propagation

### Architecture
- Swift 6 strict concurrency throughout
- Thread-safe Terminal class with NSLock-based synchronization
- Value-type terminal state (TerminalState) wrapped by reference-type API (Terminal)
- Action-based output model instead of large delegate protocols
- Immutable snapshots for rendering

## Requirements

- Swift 6
- macOS 15+
- iOS 18+
- visionOS 2+

## Installation

### Swift Package Manager

Add StrixTerm to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/StrixTerm.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "StrixTerm", package: "StrixTerm"),
        ]
    ),
]
```

The `StrixTerm` product is an umbrella that re-exports `StrixTermCore`, `StrixTermConfig`, and `StrixTermProcess`. Import `StrixTermUI` separately for the SwiftUI views:

```swift
import StrixTerm
import StrixTermUI
```

Or import individual modules if you only need a subset:

```swift
import StrixTermCore    // Terminal emulation only, no UI
import StrixTermConfig  // Profiles and palettes
import StrixTermProcess // PTY child process
import StrixTermUI      // Metal renderer, SwiftUI views
```

## Quick Start

### SwiftUI (simplest)

A minimal working terminal in a SwiftUI app:

```swift
import SwiftUI
import StrixTermCore
import StrixTermUI
import StrixTermProcess
import StrixTermConfig

struct ContentView: View {
    @StateObject private var session = TerminalSession()

    var body: some View {
        TerminalView(
            terminal: session.terminal,
            configuration: TerminalViewConfiguration(
                fontFamily: "Menlo",
                fontSize: 14
            ),
            onSendData: { data in
                session.process.send(data)
            },
            onSizeChanged: { size in
                session.terminal.resize(cols: size.cols, rows: size.rows)
                session.process.setWindowSize(size)
            }
        )
        .onAppear { session.start() }
    }
}

@MainActor
final class TerminalSession: ObservableObject {
    let terminal = Terminal(cols: 80, rows: 25, maxScrollback: 10_000)
    let process = ProcessHost()

    func start() {
        process.delegate = self
        terminal.delegate = self
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        try? process.start(
            command: shell,
            arguments: ["--login"],
            environment: ["TERM": "xterm-256color", "COLORTERM": "truecolor"],
            currentDirectory: NSHomeDirectory(),
            windowSize: terminal.size
        )
    }
}

extension TerminalSession: ProcessHostDelegate {
    nonisolated func processHost(_ host: ProcessHost, didReceiveData data: [UInt8]) {
        DispatchQueue.main.async { [weak self] in
            self?.terminal.feed(data)
        }
    }

    nonisolated func processHostDidTerminate(_ host: ProcessHost, exitCode: Int32) {
        DispatchQueue.main.async { [weak self] in
            self?.terminal.feed(text: "\r\n[Process exited with code \(exitCode)]\r\n")
        }
    }
}

extension TerminalSession: TerminalDelegate {
    nonisolated func terminal(_ terminal: Terminal, produced actions: [TerminalAction]) {
        // Handle actions like .bell, .setTitle, .clipboardCopy, etc.
    }

    nonisolated func terminal(_ terminal: Terminal, sendData data: [UInt8]) {
        DispatchQueue.main.async { [weak self] in
            self?.process.send(data)
        }
    }

    nonisolated func terminalNeedsDisplay(_ terminal: Terminal) {
        // Display updates are driven by the Metal renderer's draw loop.
    }
}
```

Use `TerminalSearchableView` instead of `TerminalView` to get a built-in Cmd+F find bar:

```swift
TerminalSearchableView(
    terminal: session.terminal,
    onSendData: { data in session.process.send(data) },
    onSizeChanged: { size in
        session.terminal.resize(cols: size.cols, rows: size.rows)
        session.process.setWindowSize(size)
    }
)
```

### Headless (no UI)

Use `Terminal` directly for screen scraping, automation, or testing:

```swift
import StrixTermCore

let terminal = Terminal(cols: 80, rows: 25)

// Feed raw output as if it came from a process
terminal.feed(text: "Hello, world!\r\n")
terminal.feed(text: "\u{1b}[31mRed text\u{1b}[0m")

// Read back the visible screen content
let screen = terminal.visibleText()

// Inspect individual cells
let cell = terminal.cell(at: Position(col: 0, row: 0))

// Take an immutable snapshot for batch inspection
let snapshot = terminal.snapshot()
print("Cursor at: \(snapshot.cursorPosition)")
print("Cols: \(snapshot.cols), Rows: \(snapshot.rows)")

// Search the buffer
let results = terminal.search(query: "Hello")
for result in results {
    print("Match at line \(result.lineIndex): \(result.startPosition) - \(result.endPosition)")
}
```

## Architecture

StrixTerm is split into five modules with clear dependency boundaries:

```
StrixTerm (umbrella)
  |-- StrixTermCore     (no dependencies)
  |-- StrixTermConfig   (depends on StrixTermCore)
  |-- StrixTermProcess  (depends on StrixTermCore)
  |-- StrixTermUI       (depends on StrixTermCore, StrixTermConfig)
```

- **StrixTermCore** -- Pure terminal emulation logic. No UI, no platform frameworks beyond Foundation. This module can be used on any platform for headless terminal emulation.
- **StrixTermConfig** -- Profiles, color palettes, and configuration types. All types are `Codable` and `Sendable` for easy persistence.
- **StrixTermProcess** -- PTY child process management. Darwin-only (uses `forkpty`).
- **StrixTermUI** -- Metal-based GPU renderer, SwiftUI views, keyboard/mouse input handling, accessibility, and the find bar. Apple platforms only.
- **StrixTerm** -- Umbrella module that re-exports `StrixTermCore`, `StrixTermConfig`, and `StrixTermProcess`.

## Modules

### StrixTermCore

The core terminal emulation engine. All types are `Sendable`.

| Type | Description |
|------|-------------|
| `Terminal` | Thread-safe terminal emulation API. Feed data in, query state out. |
| `TerminalDelegate` | Minimal delegate: action dispatch, data sending, display requests. |
| `TerminalAction` | Enum of all terminal-produced actions (title changes, bell, clipboard, links, etc.). |
| `TerminalSnapshot` | Immutable snapshot of terminal state for rendering or inspection. |
| `Cell` | A single terminal cell: code point, attribute index, width, flags, payload. |
| `CellFlags` | Option set: wide continuation, has-link. |
| `CellGrid` | The underlying cell storage with line metadata. |
| `AttributeEntry` | Resolved text attributes (colors, bold, italic, underline, etc.). |
| `Selection` | Text selection state with character, word, and line modes. |
| `SearchEngine` | Text search across the cell grid with regex, case, and whole-word options. |
| `SearchOptions` | Search configuration: case sensitive, regex, whole word, wrap around. |
| `SearchResult` | A single search match with start/end positions and line index. |
| `Position` | A (col, row) position in the terminal grid. |
| `TerminalSize` | A (cols, rows) size. |
| `CursorStyle` | Block, underline, or bar -- blinking or steady. |
| `MouseMode` | Off, click, drag, any-event. |
| `MouseEncoding` | X10, UTF-8, SGR. |
| `MouseEncoder` | Encodes mouse events for the current mode and encoding. |
| `KittyKeyboardFlags` | Flags for the Kitty keyboard protocol. |
| `SemanticPromptState` | OSC 133 prompt zone tracking. |
| `ColorPalette` | A 256-color palette. |
| `LinkTable` | Storage for OSC 8 hyperlinks with URL and parameters. |
| `LinkDetector` | Implicit URL detection in terminal text. |

### StrixTermUI

SwiftUI views and the Metal rendering layer. Apple platforms only.

| Type | Description |
|------|-------------|
| `TerminalView` | SwiftUI view wrapping the platform-native Metal terminal view. On macOS, uses `NSViewRepresentable`; on iOS/visionOS, uses `UIViewRepresentable`. |
| `TerminalViewConfiguration` | Font family, font size, blink settings, link highlight mode. |
| `TerminalSearchableView` | `TerminalView` with an integrated floating find bar (macOS). |
| `LinkHighlightMode` | How hyperlinks are visually highlighted: `always`, `hover`, `hoverWithModifier`, `never`. |
| `FindBarView` | The search overlay UI. |

Callbacks on `TerminalView`:

- `onSendData` -- user keyboard input bytes
- `onSizeChanged` -- terminal resized (cols/rows changed)
- `onTitleChanged` -- window title changed (OSC 2)
- `onOpenURL` -- user activated a hyperlink
- `onBell` -- terminal bell rang

### StrixTermConfig

Profile and configuration types. All `Codable` and `Sendable`.

| Type | Description |
|------|-------------|
| `Profile` | A named bundle of terminal, appearance, and shell settings. Identifiable by UUID. |
| `TerminalConfiguration` | Terminal dimensions, scrollback limit, TERM name, cursor style, tab width, Sixel/Kitty image settings. Includes `makeTerminal()` factory method. |
| `AppearanceSettings` | Font family, font size, color palette name, cursor style, blink, opacity, line/letter spacing. |
| `ShellSettings` | Shell command, arguments, environment variables, working directory, login shell flag. |
| `BuiltinPalette` | Enum of 9 built-in color palettes (see below). |
| `ColorPalette` | Full 256-color palette built from ANSI 16 base colors. |

### StrixTermProcess

PTY child process management. Darwin-only.

| Type | Description |
|------|-------------|
| `ProcessHost` | Manages a child process connected via PTY. Handles fork, exec, I/O, window resize, and termination. |
| `ProcessHostDelegate` | Callbacks for received data and process termination. |
| `ProcessHostError` | Error cases: `forkFailed`, `processNotRunning`. |

`ProcessHost` API:

- `start(command:arguments:environment:currentDirectory:windowSize:)` -- fork and exec
- `send(_:)` / `send(text:)` -- write to the child process
- `setWindowSize(_:)` -- update PTY window size and send SIGWINCH
- `terminate()` -- send SIGTERM
- `kill()` -- send SIGKILL
- `pid` -- the child process PID

## Color Palettes

StrixTerm includes 9 built-in color palettes via `BuiltinPalette`:

| Palette | Enum case |
|---------|-----------|
| Xterm (default) | `.xterm` |
| Solarized Dark | `.solarizedDark` |
| Solarized Light | `.solarizedLight` |
| Dracula | `.dracula` |
| Gruvbox Dark | `.gruvboxDark` |
| Nord | `.nord` |
| Tokyo Night | `.tokyoNight` |
| Catppuccin Mocha | `.catppuccinMocha` |
| One Dark | `.oneDark` |

Each palette defines the ANSI 16 base colors and extends them to the full 256-color xterm palette. Access a palette via:

```swift
let palette = BuiltinPalette.dracula.palette
```

Set a palette by name in a profile:

```swift
var appearance = AppearanceSettings()
appearance.colorPalette = "dracula"
```

## Migration from SwiftTerm

StrixTerm is a ground-up rewrite, not a fork. Key differences:

| SwiftTerm | StrixTerm | Notes |
|-----------|-----------|-------|
| `Terminal` (class, mutable) | `Terminal` (class, thread-safe) | StrixTerm's Terminal wraps a value-type `TerminalState` with lock-based synchronization. |
| `TerminalDelegate` (25+ methods) | `TerminalDelegate` (3 methods) + `TerminalAction` enum | Actions are delivered as an enum instead of individual delegate callbacks. |
| `LocalProcess` | `ProcessHost` | Drains PTY data after process exit. Uses DispatchSource instead of RunLoop. |
| `TerminalView` (AppKit/UIKit) | `TerminalView` (SwiftUI) | SwiftUI-first API. The backing AppKit/UIKit views are wrapped automatically. |
| No built-in search | `SearchEngine` + `TerminalSearchableView` | Built-in text search with find bar. |
| No profiles | `Profile` + `TerminalConfiguration` + `AppearanceSettings` | Full Codable profile system. |
| No color palettes | `BuiltinPalette` (9 palettes) | Built-in palette support. |
| No snapshots | `TerminalSnapshot` | Immutable snapshots for safe rendering and screen scraping. |
| Swift 5 | Swift 6 | Full strict concurrency compliance. All public types are `Sendable`. |
| CoreText renderer | Metal renderer | GPU-accelerated rendering with custom shaders. |

### Porting checklist

1. Replace `import SwiftTerm` with `import StrixTerm` and `import StrixTermUI`.
2. Replace `LocalProcess` with `ProcessHost`. The `start()` signature is similar but uses `TerminalSize` instead of separate width/height parameters.
3. Replace your `TerminalDelegate` implementation. Instead of individual callbacks like `sizeChanged()`, `setTerminalTitle()`, etc., handle `TerminalAction` cases in the `terminal(_:produced:)` method.
4. Replace AppKit/UIKit `TerminalView` usage with the SwiftUI `TerminalView` or `TerminalSearchableView`.
5. If you were subclassing `Terminal` -- you cannot. Use composition and the delegate/action pattern instead.

## License

MIT License. See [LICENSE](LICENSE).
