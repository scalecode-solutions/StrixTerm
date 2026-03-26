import Testing
@testable import FredTermCore

/// Mock terminal emulator that records parser callbacks.
struct MockEmulator: TerminalEmulator {
    var printedBytes: [UInt8] = []
    var printedScalars: [UInt32] = []
    var executedBytes: [UInt8] = []
    var csiDispatches: [(params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8)] = []
    var escDispatches: [(intermediates: IntermediateBuffer, final: UInt8)] = []
    var oscData: [[UInt8]] = []
    var dcsData: [(params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8, data: [UInt8])] = []
    var apcData: [[UInt8]] = []

    mutating func handlePrint(_ byte: UInt8) {
        printedBytes.append(byte)
    }

    mutating func handlePrintScalar(_ scalar: UInt32) {
        printedScalars.append(scalar)
    }

    mutating func handleExecute(_ byte: UInt8) {
        executedBytes.append(byte)
    }

    mutating func handleCSIDispatch(params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8) {
        csiDispatches.append((params, intermediates, final))
    }

    mutating func handleESCDispatch(intermediates: IntermediateBuffer, final: UInt8) {
        escDispatches.append((intermediates, final))
    }

    mutating func handleOSC(_ data: [UInt8]) {
        oscData.append(data)
    }

    mutating func handleDCS(params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8, data: [UInt8]) {
        dcsData.append((params, intermediates, final, data))
    }

    mutating func handleAPC(_ data: [UInt8]) {
        apcData.append(data)
    }
}

@Suite("VTParser Tests")
struct ParserTests {
    @Test("Parse printable ASCII")
    func parsePrintable() {
        var parser = VTParser()
        var emulator = MockEmulator()
        parser.parse(Array("Hello".utf8), handler: &emulator)

        #expect(emulator.printedBytes == [0x48, 0x65, 0x6C, 0x6C, 0x6F])
    }

    @Test("Parse control characters")
    func parseControls() {
        var parser = VTParser()
        var emulator = MockEmulator()
        parser.parse([0x07, 0x08, 0x0A, 0x0D], handler: &emulator)

        #expect(emulator.executedBytes == [0x07, 0x08, 0x0A, 0x0D])
    }

    @Test("Parse CSI cursor up")
    func parseCSICursorUp() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC [ 5 A = cursor up 5
        parser.parse([0x1B, 0x5B, 0x35, 0x41], handler: &emulator)

        #expect(emulator.csiDispatches.count == 1)
        let dispatch = emulator.csiDispatches[0]
        #expect(dispatch.final == 0x41) // 'A'
        #expect(dispatch.params.count == 1)
        #expect(dispatch.params.value(0) == 5)
    }

    @Test("Parse CSI with multiple params")
    func parseCSIMultiParam() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC [ 10 ; 20 H = cursor position (10, 20)
        parser.parse(Array("\u{1b}[10;20H".utf8), handler: &emulator)

        #expect(emulator.csiDispatches.count == 1)
        let dispatch = emulator.csiDispatches[0]
        #expect(dispatch.final == 0x48) // 'H'
        #expect(dispatch.params.value(0) == 10)
        #expect(dispatch.params.value(1) == 20)
    }

    @Test("Parse CSI with private marker")
    func parseCSIPrivate() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC [ ? 25 h = DECTCEM show cursor
        parser.parse(Array("\u{1b}[?25h".utf8), handler: &emulator)

        #expect(emulator.csiDispatches.count == 1)
        let dispatch = emulator.csiDispatches[0]
        #expect(dispatch.intermediates.first == 0x3F) // '?'
        #expect(dispatch.params.value(0) == 25)
        #expect(dispatch.final == 0x68) // 'h'
    }

    @Test("Parse ESC sequence")
    func parseESC() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC M = reverse index
        parser.parse([0x1B, 0x4D], handler: &emulator)

        #expect(emulator.escDispatches.count == 1)
        #expect(emulator.escDispatches[0].final == 0x4D)
    }

    @Test("Parse ESC with intermediate")
    func parseESCIntermediate() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC ( 0 = designate G0 as DEC Special Graphics
        parser.parse([0x1B, 0x28, 0x30], handler: &emulator)

        #expect(emulator.escDispatches.count == 1)
        #expect(emulator.escDispatches[0].intermediates.first == 0x28) // '('
        #expect(emulator.escDispatches[0].final == 0x30) // '0'
    }

    @Test("Parse OSC with BEL terminator")
    func parseOSCBel() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC ] 0 ; Hello BEL = set title to "Hello"
        parser.parse(Array("\u{1b}]0;Hello\u{07}".utf8), handler: &emulator)

        #expect(emulator.oscData.count == 1)
        #expect(String(bytes: emulator.oscData[0], encoding: .utf8) == "0;Hello")
    }

    @Test("Parse OSC with ST terminator")
    func parseOSCST() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC ] 2 ; Title ESC \ = set window title
        parser.parse(Array("\u{1b}]2;Title\u{1b}\\".utf8), handler: &emulator)

        #expect(emulator.oscData.count == 1)
        let text = String(bytes: emulator.oscData[0], encoding: .utf8) ?? ""
        #expect(text.hasPrefix("2;Title"))
    }

    @Test("Parse SGR reset")
    func parseSGRReset() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // ESC [ m = SGR reset
        parser.parse(Array("\u{1b}[m".utf8), handler: &emulator)

        #expect(emulator.csiDispatches.count == 1)
        #expect(emulator.csiDispatches[0].final == 0x6D) // 'm'
        #expect(emulator.csiDispatches[0].params.count == 0)
    }

    @Test("Parse UTF-8 multi-byte")
    func parseUTF8() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // "你好" = E4 BD A0 E5 A5 BD
        parser.parse(Array("你好".utf8), handler: &emulator)

        #expect(emulator.printedScalars.count == 2)
        #expect(emulator.printedScalars[0] == 0x4F60) // 你
        #expect(emulator.printedScalars[1] == 0x597D) // 好
    }

    @Test("Parse mixed content")
    func parseMixed() {
        var parser = VTParser()
        var emulator = MockEmulator()
        // "AB" + ESC[1m + "CD" + BEL
        parser.parse(Array("AB\u{1b}[1mCD\u{07}".utf8), handler: &emulator)

        #expect(emulator.printedBytes == [0x41, 0x42, 0x43, 0x44]) // A B C D
        #expect(emulator.csiDispatches.count == 1) // SGR bold
        #expect(emulator.executedBytes == [0x07]) // BEL
    }

    @Test("ParamBuffer default values")
    func paramBufferDefaults() {
        let params = ParamBuffer()
        #expect(params.count == 0)
        #expect(params.value(0, default: 1) == 1) // unset -> default
        #expect(params.value(0, default: 42) == 42)
    }

    @Test("IntermediateBuffer")
    func intermediateBuffer() {
        var buf = IntermediateBuffer()
        buf.append(0x3F) // '?'
        #expect(buf.count == 1)
        #expect(buf.first == 0x3F)
        #expect(buf[0] == 0x3F)

        buf.reset()
        #expect(buf.count == 0)
        #expect(buf.first == 0)
    }
}
