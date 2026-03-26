/// DCS (Device Control String) sequence implementations.
///
/// Handles Sixel graphics, XTVERSION, DECRQSS, and other DCS sequences.
extension TerminalState {
    mutating func dispatchDCS(
        params: ParamBuffer, intermediates: IntermediateBuffer,
        final: UInt8, data: [UInt8]
    ) {
        switch final {
        case 0x71 where intermediates.count == 0: // 'q' - Sixel graphics
            handleSixel(params: params, data: data)

        case 0x71 where intermediates.first == 0x24: // DCS $ q - DECRQSS
            handleDECRQSS(data)

        case 0x71 where intermediates.first == 0x2B: // DCS + q - XTGETTCAP
            handleXTGETTCAP(data)

        case 0x7C: // '|' - XTVERSION response or DECUDK
            if intermediates.count > 0 && intermediates[0] == 0x3E {
                // XTVERSION: DCS > | text ST
                // This is a response, not a command we generate
            }

        default:
            break
        }
    }

    // MARK: - Sixel Graphics

    private mutating func handleSixel(params: ParamBuffer, data: [UInt8]) {
        // Sixel graphics support - placeholder for full implementation
        // The data contains the sixel bitmap data
    }

    // MARK: - DECRQSS (Request Status String)

    private mutating func handleDECRQSS(_ data: [UInt8]) {
        let request = String(bytes: data, encoding: .utf8) ?? ""

        switch request {
        case "m": // SGR
            let attr = attributes[cursorAttribute]
            var sgr = "0"
            if attr.style.contains(.bold) { sgr += ";1" }
            if attr.style.contains(.dim) { sgr += ";2" }
            if attr.style.contains(.italic) { sgr += ";3" }
            if attr.style.contains(.underline) { sgr += ";4" }
            if attr.style.contains(.blink) { sgr += ";5" }
            if attr.style.contains(.inverse) { sgr += ";7" }
            if attr.style.contains(.invisible) { sgr += ";8" }
            if attr.style.contains(.strikethrough) { sgr += ";9" }
            sendResponse("\u{1b}P1$r\(sgr)m\u{1b}\\")

        case "r": // DECSTBM
            let top = buffer.scrollTop + 1
            let bottom = buffer.scrollBottom + 1
            sendResponse("\u{1b}P1$r\(top);\(bottom)r\u{1b}\\")

        case "s": // DECSLRM
            let left = buffer.marginLeft + 1
            let right = buffer.marginRight + 1
            sendResponse("\u{1b}P1$r\(left);\(right)s\u{1b}\\")

        case " q": // DECSCUSR
            sendResponse("\u{1b}P1$r\(cursorStyle.rawValue) q\u{1b}\\")

        default:
            // Invalid request
            sendResponse("\u{1b}P0$r\u{1b}\\")
        }
    }

    // MARK: - XTGETTCAP (Get Terminal Capability)

    private mutating func handleXTGETTCAP(_ data: [UInt8]) {
        let request = String(bytes: data, encoding: .utf8) ?? ""

        // Decode hex-encoded capability name
        var capName = ""
        var i = 0
        let chars = Array(request)
        while i + 1 < chars.count {
            if let byte = UInt8(String(chars[i...i+1]), radix: 16) {
                capName.append(Character(Unicode.Scalar(byte)))
            }
            i += 2
        }

        switch capName {
        case "TN": // Terminal name
            let hexName = termName.utf8.map { String(format: "%02X", $0) }.joined()
            sendResponse("\u{1b}P1+r544E=\(hexName)\u{1b}\\")
        case "Co", "colors": // Number of colors
            sendResponse("\u{1b}P1+r\(request)=323536\u{1b}\\") // "256"
        case "RGB": // Direct color support
            sendResponse("\u{1b}P1+r5247423D383B383B38\u{1b}\\") // "8;8;8"
        default:
            sendResponse("\u{1b}P0+r\(request)\u{1b}\\")
        }
    }
}
