import FredTermCore

/// Built-in color palettes.
/// Addresses issue #391 (add support for picking built-in color palettes).
public enum BuiltinPalette: String, CaseIterable, Sendable {
    case xterm
    case solarizedDark = "solarized-dark"
    case solarizedLight = "solarized-light"
    case dracula
    case gruvboxDark = "gruvbox-dark"
    case nord
    case tokyoNight = "tokyo-night"
    case catppuccinMocha = "catppuccin-mocha"
    case oneDark = "one-dark"

    /// Build a full 256-color palette using these ANSI 16 colors.
    public var palette: ColorPalette {
        var colors = ColorPalette.xterm.colors
        let ansi = ansi16Colors
        for i in 0..<min(16, ansi.count) {
            colors[i] = ansi[i]
        }
        return ColorPalette(colors: colors)
    }

    private var ansi16Colors: [PaletteEntry] {
        switch self {
        case .xterm:
            return ColorPalette.xterm.colors

        case .solarizedDark:
            return [
                PaletteEntry(hex: 0x073642), // black
                PaletteEntry(hex: 0xDC322F), // red
                PaletteEntry(hex: 0x859900), // green
                PaletteEntry(hex: 0xB58900), // yellow
                PaletteEntry(hex: 0x268BD2), // blue
                PaletteEntry(hex: 0xD33682), // magenta
                PaletteEntry(hex: 0x2AA198), // cyan
                PaletteEntry(hex: 0xEEE8D5), // white
                PaletteEntry(hex: 0x002B36), // bright black
                PaletteEntry(hex: 0xCB4B16), // bright red
                PaletteEntry(hex: 0x586E75), // bright green
                PaletteEntry(hex: 0x657B83), // bright yellow
                PaletteEntry(hex: 0x839496), // bright blue
                PaletteEntry(hex: 0x6C71C4), // bright magenta
                PaletteEntry(hex: 0x93A1A1), // bright cyan
                PaletteEntry(hex: 0xFDF6E3), // bright white
            ]

        case .solarizedLight:
            return [
                PaletteEntry(hex: 0xEEE8D5), // black
                PaletteEntry(hex: 0xDC322F), // red
                PaletteEntry(hex: 0x859900), // green
                PaletteEntry(hex: 0xB58900), // yellow
                PaletteEntry(hex: 0x268BD2), // blue
                PaletteEntry(hex: 0xD33682), // magenta
                PaletteEntry(hex: 0x2AA198), // cyan
                PaletteEntry(hex: 0x073642), // white
                PaletteEntry(hex: 0xFDF6E3), // bright black
                PaletteEntry(hex: 0xCB4B16), // bright red
                PaletteEntry(hex: 0x93A1A1), // bright green
                PaletteEntry(hex: 0x839496), // bright yellow
                PaletteEntry(hex: 0x657B83), // bright blue
                PaletteEntry(hex: 0x6C71C4), // bright magenta
                PaletteEntry(hex: 0x586E75), // bright cyan
                PaletteEntry(hex: 0x002B36), // bright white
            ]

        case .dracula:
            return [
                PaletteEntry(hex: 0x21222C), PaletteEntry(hex: 0xFF5555),
                PaletteEntry(hex: 0x50FA7B), PaletteEntry(hex: 0xF1FA8C),
                PaletteEntry(hex: 0xBD93F9), PaletteEntry(hex: 0xFF79C6),
                PaletteEntry(hex: 0x8BE9FD), PaletteEntry(hex: 0xF8F8F2),
                PaletteEntry(hex: 0x6272A4), PaletteEntry(hex: 0xFF6E6E),
                PaletteEntry(hex: 0x69FF94), PaletteEntry(hex: 0xFFFFA5),
                PaletteEntry(hex: 0xD6ACFF), PaletteEntry(hex: 0xFF92DF),
                PaletteEntry(hex: 0xA4FFFF), PaletteEntry(hex: 0xFFFFFF),
            ]

        case .gruvboxDark:
            return [
                PaletteEntry(hex: 0x282828), PaletteEntry(hex: 0xCC241D),
                PaletteEntry(hex: 0x98971A), PaletteEntry(hex: 0xD79921),
                PaletteEntry(hex: 0x458588), PaletteEntry(hex: 0xB16286),
                PaletteEntry(hex: 0x689D6A), PaletteEntry(hex: 0xA89984),
                PaletteEntry(hex: 0x928374), PaletteEntry(hex: 0xFB4934),
                PaletteEntry(hex: 0xB8BB26), PaletteEntry(hex: 0xFABD2F),
                PaletteEntry(hex: 0x83A598), PaletteEntry(hex: 0xD3869B),
                PaletteEntry(hex: 0x8EC07C), PaletteEntry(hex: 0xEBDBB2),
            ]

        case .nord:
            return [
                PaletteEntry(hex: 0x3B4252), PaletteEntry(hex: 0xBF616A),
                PaletteEntry(hex: 0xA3BE8C), PaletteEntry(hex: 0xEBCB8B),
                PaletteEntry(hex: 0x81A1C1), PaletteEntry(hex: 0xB48EAD),
                PaletteEntry(hex: 0x88C0D0), PaletteEntry(hex: 0xE5E9F0),
                PaletteEntry(hex: 0x4C566A), PaletteEntry(hex: 0xBF616A),
                PaletteEntry(hex: 0xA3BE8C), PaletteEntry(hex: 0xEBCB8B),
                PaletteEntry(hex: 0x81A1C1), PaletteEntry(hex: 0xB48EAD),
                PaletteEntry(hex: 0x8FBCBB), PaletteEntry(hex: 0xECEFF4),
            ]

        case .tokyoNight:
            return [
                PaletteEntry(hex: 0x15161E), PaletteEntry(hex: 0xF7768E),
                PaletteEntry(hex: 0x9ECE6A), PaletteEntry(hex: 0xE0AF68),
                PaletteEntry(hex: 0x7AA2F7), PaletteEntry(hex: 0xBB9AF7),
                PaletteEntry(hex: 0x7DCFFF), PaletteEntry(hex: 0xA9B1D6),
                PaletteEntry(hex: 0x414868), PaletteEntry(hex: 0xF7768E),
                PaletteEntry(hex: 0x9ECE6A), PaletteEntry(hex: 0xE0AF68),
                PaletteEntry(hex: 0x7AA2F7), PaletteEntry(hex: 0xBB9AF7),
                PaletteEntry(hex: 0x7DCFFF), PaletteEntry(hex: 0xC0CAF5),
            ]

        case .catppuccinMocha:
            return [
                PaletteEntry(hex: 0x45475A), PaletteEntry(hex: 0xF38BA8),
                PaletteEntry(hex: 0xA6E3A1), PaletteEntry(hex: 0xF9E2AF),
                PaletteEntry(hex: 0x89B4FA), PaletteEntry(hex: 0xF5C2E7),
                PaletteEntry(hex: 0x94E2D5), PaletteEntry(hex: 0xBAC2DE),
                PaletteEntry(hex: 0x585B70), PaletteEntry(hex: 0xF38BA8),
                PaletteEntry(hex: 0xA6E3A1), PaletteEntry(hex: 0xF9E2AF),
                PaletteEntry(hex: 0x89B4FA), PaletteEntry(hex: 0xF5C2E7),
                PaletteEntry(hex: 0x94E2D5), PaletteEntry(hex: 0xA6ADC8),
            ]

        case .oneDark:
            return [
                PaletteEntry(hex: 0x282C34), PaletteEntry(hex: 0xE06C75),
                PaletteEntry(hex: 0x98C379), PaletteEntry(hex: 0xE5C07B),
                PaletteEntry(hex: 0x61AFEF), PaletteEntry(hex: 0xC678DD),
                PaletteEntry(hex: 0x56B6C2), PaletteEntry(hex: 0xABB2BF),
                PaletteEntry(hex: 0x545862), PaletteEntry(hex: 0xE06C75),
                PaletteEntry(hex: 0x98C379), PaletteEntry(hex: 0xE5C07B),
                PaletteEntry(hex: 0x61AFEF), PaletteEntry(hex: 0xC678DD),
                PaletteEntry(hex: 0x56B6C2), PaletteEntry(hex: 0xC8CCD4),
            ]
        }
    }
}
