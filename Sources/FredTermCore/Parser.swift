/// VT500 parser state machine states.
public enum VTState: UInt8, Sendable {
    case ground = 0
    case escape = 1
    case escapeIntermediate = 2
    case csiEntry = 3
    case csiParam = 4
    case csiIntermediate = 5
    case csiIgnore = 6
    case dcsEntry = 7
    case dcsParam = 8
    case dcsIntermediate = 9
    case dcsPassthrough = 10
    case dcsIgnore = 11
    case oscString = 12
    case sosPmApcString = 13
}

/// Parser action that triggers on state transitions.
enum ParserAction: UInt8 {
    case none = 0
    case print = 1
    case execute = 2
    case hook = 3
    case put = 4
    case unhook = 5
    case oscStart = 6
    case oscPut = 7
    case oscEnd = 8
    case csiDispatch = 9
    case escDispatch = 10
    case collect = 11
    case param = 12
    case clear = 13
    case ignore = 14
}

/// A packed transition: state + action in a single byte pair.
struct Transition {
    let state: VTState
    let action: ParserAction

    static let none = Transition(state: .ground, action: .none)
}

/// Fixed-capacity inline parameter buffer. No heap allocation in the hot path.
/// Supports up to 16 parameters with sub-parameter separation.
public struct ParamBuffer: Sendable {
    // Inline storage for up to 16 parameters
    private var p0: Int32 = -1, p1: Int32 = -1, p2: Int32 = -1, p3: Int32 = -1
    private var p4: Int32 = -1, p5: Int32 = -1, p6: Int32 = -1, p7: Int32 = -1
    private var p8: Int32 = -1, p9: Int32 = -1, p10: Int32 = -1, p11: Int32 = -1
    private var p12: Int32 = -1, p13: Int32 = -1, p14: Int32 = -1, p15: Int32 = -1
    public private(set) var count: Int = 0

    /// Whether the current parameter uses ':' (colon) as sub-separator
    /// (used for SGR colon-separated color parameters).
    public var hasSubParams: Bool = false

    public subscript(index: Int) -> Int32 {
        get {
            switch index {
            case 0: return p0;  case 1: return p1;  case 2: return p2;  case 3: return p3
            case 4: return p4;  case 5: return p5;  case 6: return p6;  case 7: return p7
            case 8: return p8;  case 9: return p9;  case 10: return p10; case 11: return p11
            case 12: return p12; case 13: return p13; case 14: return p14; case 15: return p15
            default: return -1
            }
        }
        set {
            switch index {
            case 0: p0 = newValue;  case 1: p1 = newValue;  case 2: p2 = newValue;  case 3: p3 = newValue
            case 4: p4 = newValue;  case 5: p5 = newValue;  case 6: p6 = newValue;  case 7: p7 = newValue
            case 8: p8 = newValue;  case 9: p9 = newValue;  case 10: p10 = newValue; case 11: p11 = newValue
            case 12: p12 = newValue; case 13: p13 = newValue; case 14: p14 = newValue; case 15: p15 = newValue
            default: break
            }
        }
    }

    /// Get a parameter with a default value if unset (-1).
    @inline(__always)
    public func value(_ index: Int, default defaultValue: Int32 = 0) -> Int32 {
        let v = self[index]
        return v < 0 ? defaultValue : v
    }

    public mutating func push(_ value: Int32) {
        guard count < 16 else { return }
        self[count] = value
        count += 1
    }

    public mutating func reset() {
        p0 = -1; p1 = -1; p2 = -1; p3 = -1
        p4 = -1; p5 = -1; p6 = -1; p7 = -1
        p8 = -1; p9 = -1; p10 = -1; p11 = -1
        p12 = -1; p13 = -1; p14 = -1; p15 = -1
        count = 0
        hasSubParams = false
    }
}

/// Buffer for collecting intermediate characters (e.g., '?', '>', '!').
public struct IntermediateBuffer: Sendable {
    private var bytes: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    public private(set) var count: Int = 0

    public mutating func append(_ byte: UInt8) {
        guard count < 4 else { return }
        switch count {
        case 0: bytes.0 = byte
        case 1: bytes.1 = byte
        case 2: bytes.2 = byte
        case 3: bytes.3 = byte
        default: break
        }
        count += 1
    }

    public subscript(index: Int) -> UInt8 {
        switch index {
        case 0: return bytes.0
        case 1: return bytes.1
        case 2: return bytes.2
        case 3: return bytes.3
        default: return 0
        }
    }

    public mutating func reset() {
        bytes = (0, 0, 0, 0)
        count = 0
    }

    /// The first intermediate byte (commonly '?', '>', '!', or 0 if none).
    public var first: UInt8 { count > 0 ? bytes.0 : 0 }
}

/// The inline VT500 parser.
///
/// Unlike SwiftTerm's `EscapeSequenceParser` which uses closures for handlers
/// and a protocol for DCS, this parser calls methods on `TerminalState` directly.
/// Combined with `@inlinable`, the compiler can inline the dispatch and eliminate
/// all virtual call overhead.
public struct VTParser: Sendable {
    public var currentState: VTState = .ground
    public var params: ParamBuffer = ParamBuffer()
    public var intermediates: IntermediateBuffer = IntermediateBuffer()
    public var oscData: [UInt8] = []
    public var dcsData: [UInt8] = []

    /// The current collecting character code for CSI/ESC.
    var collectingFinalByte: UInt8 = 0

    /// UTF-8 decoder state.
    var utf8State: UTF8Decoder = UTF8Decoder()

    public init() {}

    /// Parse a buffer of raw bytes, dispatching actions into the terminal state.
    @inlinable
    public mutating func parse<H: TerminalEmulator>(_ data: [UInt8], handler: inout H) {
        parse(data[...], handler: &handler)
    }

    /// Parse a slice of raw bytes.
    public mutating func parse<H: TerminalEmulator>(_ data: ArraySlice<UInt8>, handler: inout H) {
        var i = data.startIndex
        while i < data.endIndex {
            let byte = data[i]
            i += 1

            // Fast path: printable ASCII in ground state
            if currentState == .ground && byte >= 0x20 && byte < 0x7F {
                handler.handlePrint(byte)
                continue
            }

            // UTF-8 multi-byte handling in ground state
            if currentState == .ground && byte >= 0x80 {
                if let scalar = utf8State.decode(byte) {
                    handler.handlePrintScalar(scalar)
                }
                continue
            }

            // C0 control characters (0x00-0x1F) are handled in any state
            if byte < 0x20 {
                switch byte {
                case 0x1B: // ESC
                    if currentState == .oscString {
                        handleOSCEnd(handler: &handler)
                    } else if currentState == .dcsPassthrough {
                        handleDCSEnd(handler: &handler)
                    }
                    transition(to: .escape)
                    continue
                case 0x18, 0x1A: // CAN, SUB
                    transition(to: .ground)
                    continue
                case 0x07: // BEL
                    if currentState == .oscString {
                        handleOSCEnd(handler: &handler)
                        transition(to: .ground)
                    } else {
                        handler.handleExecute(byte)
                    }
                    continue
                default:
                    if currentState == .ground || currentState == .oscString || currentState == .dcsPassthrough {
                        handler.handleExecute(byte)
                    }
                    continue
                }
            }

            // State-specific handling
            switch currentState {
            case .ground:
                if byte == 0x7F { // DEL
                    continue // ignored in ground
                }

            case .escape:
                handleEscape(byte, handler: &handler)

            case .escapeIntermediate:
                if byte >= 0x20 && byte <= 0x2F {
                    intermediates.append(byte)
                } else if byte >= 0x30 && byte <= 0x7E {
                    handler.handleESCDispatch(intermediates: intermediates, final: byte)
                    transition(to: .ground)
                } else {
                    transition(to: .ground)
                }

            case .csiEntry:
                handleCSIEntry(byte, handler: &handler)

            case .csiParam:
                handleCSIParam(byte, handler: &handler)

            case .csiIntermediate:
                if byte >= 0x20 && byte <= 0x2F {
                    intermediates.append(byte)
                } else if byte >= 0x40 && byte <= 0x7E {
                    handler.handleCSIDispatch(
                        params: params, intermediates: intermediates, final: byte)
                    transition(to: .ground)
                } else {
                    transition(to: .csiIgnore)
                }

            case .csiIgnore:
                if byte >= 0x40 && byte <= 0x7E {
                    transition(to: .ground)
                }

            case .oscString:
                if byte >= 0x20 && byte <= 0x7F {
                    oscData.append(byte)
                }

            case .dcsEntry:
                handleDCSEntry(byte)

            case .dcsParam:
                handleDCSParam(byte)

            case .dcsIntermediate:
                if byte >= 0x20 && byte <= 0x2F {
                    intermediates.append(byte)
                } else if byte >= 0x30 && byte <= 0x7E {
                    collectingFinalByte = byte
                    dcsData.removeAll(keepingCapacity: true)
                    handleDCSStart(handler: &handler)
                    transition(to: .dcsPassthrough)
                } else {
                    transition(to: .dcsIgnore)
                }

            case .dcsPassthrough:
                if byte >= 0x20 || byte == 0x1B {
                    dcsData.append(byte)
                }

            case .dcsIgnore:
                // Stay in dcsIgnore until ST
                break

            case .sosPmApcString:
                // Consume and ignore until ST
                break
            }
        }
    }

    // MARK: - State transition helpers

    private mutating func transition(to state: VTState) {
        currentState = state
        if state == .escape || state == .csiEntry || state == .dcsEntry {
            params.reset()
            intermediates.reset()
            collectingFinalByte = 0
        }
    }

    private mutating func handleEscape<H: TerminalEmulator>(_ byte: UInt8, handler: inout H) {
        switch byte {
        case 0x5B: // '['
            transition(to: .csiEntry)
        case 0x5D: // ']'
            oscData.removeAll(keepingCapacity: true)
            currentState = .oscString
        case 0x50: // 'P'
            transition(to: .dcsEntry)
        case 0x58, 0x5E, 0x5F: // 'X', '^', '_' (SOS, PM, APC)
            currentState = .sosPmApcString
        case 0x20...0x2F: // intermediates
            intermediates.append(byte)
            currentState = .escapeIntermediate
        case 0x30...0x4F, 0x51...0x57, 0x59...0x5A, 0x5C, 0x60...0x7E:
            handler.handleESCDispatch(intermediates: intermediates, final: byte)
            transition(to: .ground)
        default:
            transition(to: .ground)
        }
    }

    private mutating func handleCSIEntry<H: TerminalEmulator>(_ byte: UInt8, handler: inout H) {
        switch byte {
        case 0x30...0x39: // '0'-'9'
            params.push(Int32(byte - 0x30))
            currentState = .csiParam
        case 0x3B: // ';'
            params.push(-1) // empty param
            currentState = .csiParam
        case 0x3A: // ':'
            params.hasSubParams = true
            params.push(-1)
            currentState = .csiParam
        case 0x3C...0x3F: // '<', '=', '>', '?'
            intermediates.append(byte)
            currentState = .csiParam
        case 0x20...0x2F: // intermediates
            intermediates.append(byte)
            currentState = .csiIntermediate
        case 0x40...0x7E: // final byte
            handler.handleCSIDispatch(
                params: params, intermediates: intermediates, final: byte)
            transition(to: .ground)
        default:
            transition(to: .csiIgnore)
        }
    }

    private mutating func handleCSIParam<H: TerminalEmulator>(_ byte: UInt8, handler: inout H) {
        switch byte {
        case 0x30...0x39: // '0'-'9'
            if params.count == 0 {
                params.push(Int32(byte - 0x30))
            } else {
                let idx = params.count - 1
                let current = params[idx]
                if current < 0 {
                    params[idx] = Int32(byte - 0x30)
                } else {
                    params[idx] = current * 10 + Int32(byte - 0x30)
                }
            }
        case 0x3B: // ';'
            params.push(-1) // new param
        case 0x3A: // ':'
            params.hasSubParams = true
            params.push(-1)
        case 0x20...0x2F: // intermediate
            intermediates.append(byte)
            currentState = .csiIntermediate
        case 0x40...0x7E: // final byte
            handler.handleCSIDispatch(
                params: params, intermediates: intermediates, final: byte)
            transition(to: .ground)
        case 0x3C...0x3F: // extra leading byte (invalid but handle gracefully)
            transition(to: .csiIgnore)
        default:
            transition(to: .csiIgnore)
        }
    }

    private mutating func handleDCSEntry(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39, 0x3B:
            currentState = .dcsParam
            handleDCSParam(byte)
        case 0x20...0x2F:
            intermediates.append(byte)
            currentState = .dcsIntermediate
        case 0x3C...0x3F:
            intermediates.append(byte)
            currentState = .dcsParam
        case 0x40...0x7E:
            collectingFinalByte = byte
            currentState = .dcsPassthrough
            dcsData.removeAll(keepingCapacity: true)
        default:
            currentState = .dcsIgnore
        }
    }

    private mutating func handleDCSParam(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39:
            if params.count == 0 {
                params.push(Int32(byte - 0x30))
            } else {
                let idx = params.count - 1
                let current = params[idx]
                if current < 0 {
                    params[idx] = Int32(byte - 0x30)
                } else {
                    params[idx] = current * 10 + Int32(byte - 0x30)
                }
            }
        case 0x3B:
            params.push(-1)
        case 0x20...0x2F:
            intermediates.append(byte)
            currentState = .dcsIntermediate
        case 0x40...0x7E:
            collectingFinalByte = byte
            currentState = .dcsPassthrough
            dcsData.removeAll(keepingCapacity: true)
        default:
            currentState = .dcsIgnore
        }
    }

    private mutating func handleOSCEnd<H: TerminalEmulator>(handler: inout H) {
        handler.handleOSC(oscData)
        oscData.removeAll(keepingCapacity: true)
    }

    private mutating func handleDCSStart<H: TerminalEmulator>(handler: inout H) {
        dcsData.removeAll(keepingCapacity: true)
    }

    private mutating func handleDCSEnd<H: TerminalEmulator>(handler: inout H) {
        handler.handleDCS(params: params, intermediates: intermediates,
                          final: collectingFinalByte, data: dcsData)
        dcsData.removeAll(keepingCapacity: true)
    }
}

/// UTF-8 incremental decoder.
struct UTF8Decoder: Sendable {
    private var codePoint: UInt32 = 0
    private var remaining: Int = 0

    /// Feed a byte. Returns the decoded scalar when complete, or nil if more bytes needed.
    mutating func decode(_ byte: UInt8) -> UInt32? {
        if remaining > 0 {
            if byte & 0xC0 == 0x80 {
                codePoint = (codePoint << 6) | UInt32(byte & 0x3F)
                remaining -= 1
                if remaining == 0 {
                    return codePoint
                }
                return nil
            } else {
                // Invalid continuation: reset and try this byte as a new start
                remaining = 0
                return decode(byte)
            }
        }

        if byte & 0x80 == 0 {
            return UInt32(byte)
        } else if byte & 0xE0 == 0xC0 {
            codePoint = UInt32(byte & 0x1F)
            remaining = 1
        } else if byte & 0xF0 == 0xE0 {
            codePoint = UInt32(byte & 0x0F)
            remaining = 2
        } else if byte & 0xF8 == 0xF0 {
            codePoint = UInt32(byte & 0x07)
            remaining = 3
        } else {
            return 0xFFFD // replacement character
        }
        return nil
    }
}
