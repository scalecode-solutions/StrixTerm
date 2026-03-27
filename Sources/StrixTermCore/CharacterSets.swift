/// Character set designations for G0-G3.
public enum TerminalCharset: UInt8, Sendable {
    case usASCII = 0         // 'B'
    case decSpecialGraphics = 1 // '0'
    case uk = 2              // 'A'
    case dutch = 3           // '4'
    case finnish = 4         // 'C' or '5'
    case french = 5          // 'R'
    case frenchCanadian = 6  // 'Q'
    case german = 7          // 'K'
    case italian = 8         // 'Y'
    case norwegian = 9       // 'E' or '6'
    case spanish = 10        // 'Z'
    case swedish = 11        // 'H' or '7'
    case swiss = 12          // '='
    case decTechnical = 13   // '>'
}

/// Character set translation state.
public struct CharsetState: Sendable {
    /// The four character sets G0-G3.
    public var charsets: (TerminalCharset, TerminalCharset, TerminalCharset, TerminalCharset) =
        (.usASCII, .usASCII, .usASCII, .usASCII)
    /// Which GL set is active (0-3).
    public var activeGL: Int = 0
    /// Which GR set is active (0-3, usually 2).
    public var activeGR: Int = 2
    /// Single shift (SS2/SS3): -1 = none, 2 = SS2, 3 = SS3.
    public var singleShift: Int = -1

    /// Get the currently active charset for GL.
    public var currentCharset: TerminalCharset {
        if singleShift >= 0 {
            return charset(at: singleShift)
        }
        return charset(at: activeGL)
    }

    /// Get the charset at a given slot (0-3).
    public func charset(at slot: Int) -> TerminalCharset {
        switch slot {
        case 0: return charsets.0
        case 1: return charsets.1
        case 2: return charsets.2
        case 3: return charsets.3
        default: return .usASCII
        }
    }

    /// Set the charset at a given slot.
    public mutating func setCharset(at slot: Int, to charset: TerminalCharset) {
        switch slot {
        case 0: charsets.0 = charset
        case 1: charsets.1 = charset
        case 2: charsets.2 = charset
        case 3: charsets.3 = charset
        default: break
        }
    }

    /// Designate a charset from the escape sequence intermediate/final bytes.
    public static func from(final byte: UInt8) -> TerminalCharset {
        switch byte {
        case 0x30: return .decSpecialGraphics  // '0'
        case 0x41: return .uk                   // 'A'
        case 0x42: return .usASCII              // 'B'
        case 0x34: return .dutch                // '4'
        case 0x43, 0x35: return .finnish        // 'C' or '5'
        case 0x52: return .french               // 'R'
        case 0x51: return .frenchCanadian       // 'Q'
        case 0x4B: return .german               // 'K'
        case 0x59: return .italian              // 'Y'
        case 0x45, 0x36: return .norwegian      // 'E' or '6'
        case 0x5A: return .spanish              // 'Z'
        case 0x48, 0x37: return .swedish         // 'H' or '7'
        case 0x3D: return .swiss                // '='
        default: return .usASCII
        }
    }
}

/// DEC Special Graphics line drawing character mapping.
/// Maps ASCII 0x5F-0x7E to the corresponding box drawing Unicode characters.
public let decSpecialGraphicsMap: [UInt32] = {
    var map = [UInt32](repeating: 0, count: 128)
    // Initialize all to identity
    for i in 0..<128 { map[i] = UInt32(i) }
    // DEC Special Graphics replacements (0x60 - 0x7E)
    map[0x5F] = 0x00A0  // NO-BREAK SPACE
    map[0x60] = 0x25C6  // BLACK DIAMOND
    map[0x61] = 0x2592  // MEDIUM SHADE
    map[0x62] = 0x2409  // SYMBOL FOR HORIZONTAL TABULATION
    map[0x63] = 0x240C  // SYMBOL FOR FORM FEED
    map[0x64] = 0x240D  // SYMBOL FOR CARRIAGE RETURN
    map[0x65] = 0x240A  // SYMBOL FOR LINE FEED
    map[0x66] = 0x00B0  // DEGREE SIGN
    map[0x67] = 0x00B1  // PLUS-MINUS SIGN
    map[0x68] = 0x2424  // SYMBOL FOR NEWLINE
    map[0x69] = 0x240B  // SYMBOL FOR VERTICAL TABULATION
    map[0x6A] = 0x2518  // BOX DRAWINGS LIGHT UP AND LEFT
    map[0x6B] = 0x2510  // BOX DRAWINGS LIGHT DOWN AND LEFT
    map[0x6C] = 0x250C  // BOX DRAWINGS LIGHT DOWN AND RIGHT
    map[0x6D] = 0x2514  // BOX DRAWINGS LIGHT UP AND RIGHT
    map[0x6E] = 0x253C  // BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
    map[0x6F] = 0x23BA  // HORIZONTAL SCAN LINE-1
    map[0x70] = 0x23BB  // HORIZONTAL SCAN LINE-3
    map[0x71] = 0x2500  // BOX DRAWINGS LIGHT HORIZONTAL
    map[0x72] = 0x23BC  // HORIZONTAL SCAN LINE-7
    map[0x73] = 0x23BD  // HORIZONTAL SCAN LINE-9
    map[0x74] = 0x251C  // BOX DRAWINGS LIGHT VERTICAL AND RIGHT
    map[0x75] = 0x2524  // BOX DRAWINGS LIGHT VERTICAL AND LEFT
    map[0x76] = 0x2534  // BOX DRAWINGS LIGHT UP AND HORIZONTAL
    map[0x77] = 0x252C  // BOX DRAWINGS LIGHT DOWN AND HORIZONTAL
    map[0x78] = 0x2502  // BOX DRAWINGS LIGHT VERTICAL
    map[0x79] = 0x2264  // LESS-THAN OR EQUAL TO
    map[0x7A] = 0x2265  // GREATER-THAN OR EQUAL TO
    map[0x7B] = 0x03C0  // GREEK SMALL LETTER PI
    map[0x7C] = 0x2260  // NOT EQUAL TO
    map[0x7D] = 0x00A3  // POUND SIGN
    map[0x7E] = 0x00B7  // MIDDLE DOT
    return map
}()
