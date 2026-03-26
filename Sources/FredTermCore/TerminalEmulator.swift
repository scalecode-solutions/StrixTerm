/// Protocol for handling parsed terminal escape sequences.
///
/// The parser calls these methods directly on the concrete implementation
/// (TerminalState), allowing the compiler to devirtualize and inline.
public protocol TerminalEmulator {
    /// Handle a printable ASCII byte (0x20-0x7E) in the ground state.
    mutating func handlePrint(_ byte: UInt8)

    /// Handle a printable Unicode scalar (for multi-byte characters).
    mutating func handlePrintScalar(_ scalar: UInt32)

    /// Handle a C0 control character (0x00-0x1F).
    mutating func handleExecute(_ byte: UInt8)

    /// Handle a CSI (Control Sequence Introducer) dispatch.
    mutating func handleCSIDispatch(
        params: ParamBuffer, intermediates: IntermediateBuffer, final: UInt8)

    /// Handle an ESC (Escape) dispatch.
    mutating func handleESCDispatch(
        intermediates: IntermediateBuffer, final: UInt8)

    /// Handle an OSC (Operating System Command) sequence.
    mutating func handleOSC(_ data: [UInt8])

    /// Handle a DCS (Device Control String) sequence.
    mutating func handleDCS(
        params: ParamBuffer, intermediates: IntermediateBuffer,
        final: UInt8, data: [UInt8])
}
