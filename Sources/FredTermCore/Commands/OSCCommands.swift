/// OSC (Operating System Command) sequence implementations.
///
/// Supports complete xterm OSC codes (addressing issue #108) plus
/// modern extensions like OSC 133 (semantic prompts, #458).
extension TerminalState {
    mutating func dispatchOSC(_ data: [UInt8]) {
        // Parse OSC code from the data: code ; payload
        guard !data.isEmpty else { return }

        var code = 0
        var payloadStart = 0

        for i in data.indices {
            if data[i] == 0x3B { // ';'
                payloadStart = i + 1
                break
            }
            if data[i] >= 0x30 && data[i] <= 0x39 {
                code = code * 10 + Int(data[i] - 0x30)
            }
            payloadStart = i + 1
        }

        let payload = payloadStart < data.count ? Array(data[payloadStart...]) : []

        switch code {
        case 0: // Set icon name and window title
            let text = String(bytes: payload, encoding: .utf8) ?? ""
            pendingActions.append(.setTitle(text))
            pendingActions.append(.setIconTitle(text))

        case 1: // Set icon name
            let text = String(bytes: payload, encoding: .utf8) ?? ""
            pendingActions.append(.setIconTitle(text))

        case 2: // Set window title
            let text = String(bytes: payload, encoding: .utf8) ?? ""
            pendingActions.append(.setTitle(text))

        case 4: // Change/query color palette
            handleOSC4(payload)

        case 7: // Set current working directory
            let text = String(bytes: payload, encoding: .utf8) ?? ""
            pendingActions.append(.setCurrentDirectory(text))

        case 8: // Hyperlinks: OSC 8 ; params ; url ST
            handleOSC8(payload)

        case 9: // Desktop notification / progress (iTerm2 / ConEmu)
            handleOSC9(payload)

        case 10: // Set/query foreground color
            handleOSCDynamicColor(payload, type: .foreground)

        case 11: // Set/query background color
            handleOSCDynamicColor(payload, type: .background)

        case 12: // Set/query cursor color
            handleOSCCursorColor(payload)

        case 52: // Clipboard operations
            handleOSC52(payload)

        case 104: // Reset color palette
            handleOSC104(payload)

        case 110: // Reset foreground color
            pendingActions.append(.defaultColorChanged(fg: .default, bg: nil))

        case 111: // Reset background color
            pendingActions.append(.defaultColorChanged(fg: nil, bg: .default))

        case 112: // Reset cursor color
            pendingActions.append(.setCursorColor(nil))

        case 133: // Semantic prompts (FinalTerm / iTerm2 shell integration)
            handleOSC133(payload)

        case 777: // rxvt-unicode notification: OSC 777 ; notify ; title ; body ST
            handleOSC777(payload)

        default:
            break
        }
    }

    // MARK: - OSC 4: Change Color

    private mutating func handleOSC4(_ payload: [UInt8]) {
        // Format: index;color_spec
        // Can have multiple: index1;color1;index2;color2
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)

        var i = 0
        while i + 1 < parts.count {
            if let index = Int(parts[i]),
               index >= 0 && index < 256 {
                let colorSpec = String(parts[i + 1])
                if colorSpec == "?" {
                    // Query: report current color
                    let c = palette.colors[index]
                    let response = "\u{1b}]4;\(index);rgb:\(hex2(c.r))/\(hex2(c.g))/\(hex2(c.b))\u{1b}\\"
                    sendResponse(response)
                } else if let entry = parseXColorSpec(colorSpec) {
                    palette.colors[index] = entry
                    pendingActions.append(.colorChanged(index: index))
                }
            }
            i += 2
        }
    }

    // MARK: - OSC 8: Hyperlinks

    private mutating func handleOSC8(_ payload: [UInt8]) {
        // Format: params;url
        // params can be id=xxx or empty
        // Empty URL closes the link
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return }

        let paramsStr = String(parts[0])
        let url = String(parts[1])

        var linkParams: [String: String] = [:]
        for param in paramsStr.split(separator: ":") {
            let kv = param.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                linkParams[String(kv[0])] = String(kv[1])
            }
        }

        if url.isEmpty {
            // Close link: stop tracking
            activeLinkTracking = nil
        } else {
            // Open link: insert into the link table and start tracking
            let linkId = links.insert(url: url, params: linkParams)
            let startPos = Position(col: buffer.cursorX, row: buffer.cursorY)
            activeLinkTracking = (start: startPos, linkId: linkId)
            pendingActions.append(.openLink(url: url, params: linkParams))
        }
    }

    // MARK: - OSC 9: Notification / Progress

    private mutating func handleOSC9(_ payload: [UInt8]) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        let parts = text.split(separator: ";", maxSplits: 2)

        if parts.isEmpty {
            pendingActions.append(.notify(title: "Terminal", body: text))
            return
        }

        // OSC 9;4;state;value - Progress reporting
        if parts.count >= 2 && parts[0] == "4" {
            let state = Int(parts[1]) ?? 0
            let value: Int? = parts.count >= 3 ? Int(parts[2]) : nil
            if let ps = ProgressState(rawValue: UInt8(state)) {
                pendingActions.append(.progressReport(state: ps, value: value))
            }
        } else {
            pendingActions.append(.notify(title: "Terminal", body: text))
        }
    }

    // MARK: - OSC 10/11: Dynamic Colors

    private enum DynamicColorType { case foreground, background }

    private mutating func handleOSCDynamicColor(_ payload: [UInt8], type: DynamicColorType) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        if text == "?" {
            // Query
            let idx: UInt8 = type == .foreground ? 15 : 0 // default colors
            let c = palette.colors[Int(idx)]
            let code = type == .foreground ? 10 : 11
            let response = "\u{1b}]\(code);rgb:\(hex2(c.r))/\(hex2(c.g))/\(hex2(c.b))\u{1b}\\"
            sendResponse(response)
        } else if let entry = parseXColorSpec(text) {
            let color = TerminalColor.rgb(entry.r, entry.g, entry.b)
            switch type {
            case .foreground:
                pendingActions.append(.defaultColorChanged(fg: color, bg: nil))
            case .background:
                pendingActions.append(.defaultColorChanged(fg: nil, bg: color))
            }
        }
    }

    // MARK: - OSC 12: Cursor Color

    private mutating func handleOSCCursorColor(_ payload: [UInt8]) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        if text == "?" {
            // Query - respond with current cursor color
            sendResponse("\u{1b}]12;rgb:ff/ff/ff\u{1b}\\")
        } else if let entry = parseXColorSpec(text) {
            pendingActions.append(.setCursorColor(.rgb(entry.r, entry.g, entry.b)))
        }
    }

    // MARK: - OSC 52: Clipboard

    private mutating func handleOSC52(_ payload: [UInt8]) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        let parts = text.split(separator: ";", maxSplits: 1)
        guard parts.count == 2 else { return }

        let content = String(parts[1])
        if content == "?" {
            // Query clipboard - not supported for security
            return
        }

        // Decode base64
        if let data = Data(base64Encoded: content),
           let str = String(data: data, encoding: .utf8) {
            pendingActions.append(.clipboardCopy(str))
        }
    }

    // MARK: - OSC 104: Reset Color

    private mutating func handleOSC104(_ payload: [UInt8]) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        if text.isEmpty {
            // Reset all colors
            palette = .xterm
            pendingActions.append(.colorChanged(index: nil))
        } else {
            // Reset specific colors
            for part in text.split(separator: ";") {
                if let index = Int(part), index >= 0 && index < 256 {
                    palette.colors[index] = ColorPalette.xterm.colors[index]
                    pendingActions.append(.colorChanged(index: index))
                }
            }
        }
    }

    // MARK: - OSC 133: Semantic Prompts

    private mutating func handleOSC133(_ payload: [UInt8]) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        guard let first = text.first else { return }

        var exitCode: Int? = nil
        if text.count > 2 && text.dropFirst().first == ";" {
            exitCode = Int(text.dropFirst(2))
        }

        promptState.handleOSC133(first, exitCode: exitCode)

        // Mark the current line with the prompt zone
        buffer.grid[lineMetadata: buffer.absoluteCursorY].promptZone = promptState.currentZone
        pendingActions.append(.promptStateChanged(promptState.currentZone))
    }

    // MARK: - OSC 777: Notification

    private mutating func handleOSC777(_ payload: [UInt8]) {
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        let parts = text.split(separator: ";", maxSplits: 2)
        if parts.count >= 3 && parts[0] == "notify" {
            pendingActions.append(.notify(
                title: String(parts[1]),
                body: String(parts[2])
            ))
        }
    }

    // MARK: - Color Parsing Helpers

    private func parseXColorSpec(_ spec: String) -> PaletteEntry? {
        // Handle rgb:RR/GG/BB or rgb:RRRR/GGGG/BBBB or #RRGGBB
        if spec.hasPrefix("rgb:") {
            let components = spec.dropFirst(4).split(separator: "/")
            guard components.count == 3 else { return nil }
            let r = parseHexComponent(String(components[0]))
            let g = parseHexComponent(String(components[1]))
            let b = parseHexComponent(String(components[2]))
            return PaletteEntry(r: r, g: g, b: b)
        } else if spec.hasPrefix("#") && spec.count == 7 {
            let hex = spec.dropFirst()
            guard let val = UInt32(hex, radix: 16) else { return nil }
            return PaletteEntry(hex: val)
        }
        return nil
    }

    private func parseHexComponent(_ str: String) -> UInt8 {
        guard let val = UInt32(str, radix: 16) else { return 0 }
        switch str.count {
        case 1: return UInt8(val << 4)
        case 2: return UInt8(val)
        case 4: return UInt8(val >> 8)
        default: return UInt8(val & 0xFF)
        }
    }

    private func hex2(_ v: UInt8) -> String {
        String(format: "%02x%02x", v, v)
    }
}

import Foundation
