/// Select Graphic Rendition (SGR) parsing.
///
/// Handles CSI m sequences for setting text attributes (colors, bold, italic, etc.).
extension TerminalState {
    mutating func csiSGR(_ params: ParamBuffer) {
        if params.count == 0 {
            // CSI m with no params = reset
            cursorAttribute = attributes.intern(.default)
            return
        }

        var current = attributes[cursorAttribute]
        var i = 0

        while i < params.count {
            let p = Int(params.value(i, default: 0))
            switch p {
            case 0: // Reset
                current = .default

            // Bold / Dim / Italic
            case 1: current.style.insert(.bold)
            case 2: current.style.insert(.dim)
            case 3: current.style.insert(.italic)

            // Underline styles
            case 4:
                // Check for colon sub-parameter: CSI 4:Ps m
                if params.hasSubParams && i + 1 < params.count {
                    let sub = Int(params.value(i + 1, default: 1))
                    i += 1
                    switch sub {
                    case 0: current.underlineStyle = .none; current.style.remove(.underline)
                    case 1: current.underlineStyle = .single; current.style.insert(.underline)
                    case 2: current.underlineStyle = .double; current.style.insert(.underline)
                    case 3: current.underlineStyle = .curly; current.style.insert(.underline)
                    case 4: current.underlineStyle = .dotted; current.style.insert(.underline)
                    case 5: current.underlineStyle = .dashed; current.style.insert(.underline)
                    default: current.underlineStyle = .single; current.style.insert(.underline)
                    }
                } else {
                    current.underlineStyle = .single
                    current.style.insert(.underline)
                }

            // Blink
            case 5, 6: current.style.insert(.blink)

            // Inverse
            case 7: current.style.insert(.inverse)

            // Invisible
            case 8: current.style.insert(.invisible)

            // Strikethrough
            case 9: current.style.insert(.strikethrough)

            // Reset individual attributes
            case 21: // Double underline (or bold off in some terminals)
                current.underlineStyle = .double
                current.style.insert(.underline)
            case 22: // Normal intensity (no bold, no dim)
                current.style.remove(.bold)
                current.style.remove(.dim)
            case 23: current.style.remove(.italic)
            case 24:
                current.style.remove(.underline)
                current.underlineStyle = .none
            case 25: current.style.remove(.blink)
            case 27: current.style.remove(.inverse)
            case 28: current.style.remove(.invisible)
            case 29: current.style.remove(.strikethrough)

            // Foreground colors (standard 8)
            case 30...37:
                current.fg = .indexed(UInt8(p - 30))
            case 38:
                if let (color, advance) = parseExtendedColor(params, startIndex: i + 1) {
                    current.fg = color
                    i += advance
                }
            case 39: current.fg = .default

            // Background colors (standard 8)
            case 40...47:
                current.bg = .indexed(UInt8(p - 40))
            case 48:
                if let (color, advance) = parseExtendedColor(params, startIndex: i + 1) {
                    current.bg = color
                    i += advance
                }
            case 49: current.bg = .default

            // Overline
            case 53: current.style.insert(.overline)
            case 55: current.style.remove(.overline)

            // Underline color
            case 58:
                if let (color, advance) = parseExtendedColor(params, startIndex: i + 1) {
                    current.underlineColor = color
                    i += advance
                }
            case 59: current.underlineColor = nil

            // Bright foreground
            case 90...97:
                current.fg = .indexed(UInt8(p - 90 + 8))

            // Bright background
            case 100...107:
                current.bg = .indexed(UInt8(p - 100 + 8))

            default:
                break
            }
            i += 1
        }

        cursorAttribute = attributes.intern(current)
    }

    /// Parse an extended color specification (256-color or truecolor).
    /// Returns the color and the number of additional params consumed.
    private func parseExtendedColor(
        _ params: ParamBuffer, startIndex: Int
    ) -> (TerminalColor, Int)? {
        guard startIndex < params.count else { return nil }
        let type = Int(params.value(startIndex, default: 0))
        switch type {
        case 5: // 256-color: 38;5;Ps
            guard startIndex + 1 < params.count else { return nil }
            let idx = UInt8(clamping: Int(params.value(startIndex + 1, default: 0)))
            return (.indexed(idx), 2)
        case 2: // Truecolor: 38;2;R;G;B
            guard startIndex + 3 < params.count else { return nil }
            let r = UInt8(clamping: Int(params.value(startIndex + 1, default: 0)))
            let g = UInt8(clamping: Int(params.value(startIndex + 2, default: 0)))
            let b = UInt8(clamping: Int(params.value(startIndex + 3, default: 0)))
            return (.rgb(r, g, b), 4)
        default:
            return nil
        }
    }
}
