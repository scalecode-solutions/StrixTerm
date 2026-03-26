/// Terminal color representation.
public enum TerminalColor: Hashable, Sendable {
    /// ANSI 256-color palette index (0-255).
    case indexed(UInt8)
    /// 24-bit true color.
    case rgb(UInt8, UInt8, UInt8)
    /// The default foreground or background color (theme-dependent).
    case `default`

    /// Returns the RGB values for an indexed color using the given palette.
    public func resolve(with palette: ColorPalette) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .indexed(let idx):
            let c = palette.colors[Int(idx)]
            return (c.r, c.g, c.b)
        case .rgb(let r, let g, let b):
            return (r, g, b)
        case .default:
            return (0, 0, 0)
        }
    }
}

/// An RGBA color entry.
public struct PaletteEntry: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: UInt32) {
        self.r = UInt8((hex >> 16) & 0xFF)
        self.g = UInt8((hex >> 8) & 0xFF)
        self.b = UInt8(hex & 0xFF)
        self.a = 255
    }
}

/// The 256-color palette used by the terminal.
public struct ColorPalette: Sendable {
    public var colors: [PaletteEntry]

    public init(colors: [PaletteEntry]) {
        precondition(colors.count == 256)
        self.colors = colors
    }

    /// Standard xterm 256-color palette.
    public static let xterm = ColorPalette(colors: Self.buildXterm256())

    private static func buildXterm256() -> [PaletteEntry] {
        var c = [PaletteEntry](repeating: PaletteEntry(r: 0, g: 0, b: 0), count: 256)
        // Standard 16 ANSI colors (xterm defaults)
        let ansi16: [UInt32] = [
            0x000000, 0xCD0000, 0x00CD00, 0xCDCD00,
            0x0000EE, 0xCD00CD, 0x00CDCD, 0xE5E5E5,
            0x7F7F7F, 0xFF0000, 0x00FF00, 0xFFFF00,
            0x5C5CFF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
        ]
        for i in 0..<16 {
            c[i] = PaletteEntry(hex: ansi16[i])
        }
        // 216-color cube (indices 16-231)
        let intensities: [UInt8] = [0, 0x5F, 0x87, 0xAF, 0xD7, 0xFF]
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    c[16 + 36 * r + 6 * g + b] = PaletteEntry(
                        r: intensities[r], g: intensities[g], b: intensities[b])
                }
            }
        }
        // Grayscale ramp (indices 232-255)
        for i in 0..<24 {
            let v = UInt8(8 + 10 * i)
            c[232 + i] = PaletteEntry(r: v, g: v, b: v)
        }
        return c
    }
}
