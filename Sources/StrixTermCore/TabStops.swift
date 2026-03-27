/// Bitset-based tab stop tracking.
/// More efficient than SwiftTerm's `[Bool]` array.
public struct TabStops: Sendable {
    private var bits: [UInt64]
    public let width: Int

    public init(width: Int, tabWidth: Int = 8) {
        self.width = width
        let wordCount = (width + 63) / 64
        bits = [UInt64](repeating: 0, count: wordCount)

        // Set default tab stops
        for col in stride(from: tabWidth, to: width, by: tabWidth) {
            set(col)
        }
    }

    /// Check if a tab stop is set at the given column.
    @inline(__always)
    public func isSet(_ col: Int) -> Bool {
        guard col >= 0 && col < width else { return false }
        let word = col / 64
        let bit = col % 64
        return (bits[word] & (1 << bit)) != 0
    }

    /// Set a tab stop at the given column.
    public mutating func set(_ col: Int) {
        guard col >= 0 && col < width else { return }
        let word = col / 64
        let bit = col % 64
        bits[word] |= (1 << bit)
    }

    /// Clear a tab stop at the given column.
    public mutating func clear(_ col: Int) {
        guard col >= 0 && col < width else { return }
        let word = col / 64
        let bit = col % 64
        bits[word] &= ~(1 << bit)
    }

    /// Clear all tab stops.
    public mutating func clearAll() {
        for i in bits.indices {
            bits[i] = 0
        }
    }

    /// Find the next tab stop after the given column.
    /// Returns `width - 1` if no tab stop is found.
    public func nextStop(after col: Int) -> Int {
        guard col + 1 < width else { return max(width - 1, 0) }
        for c in (col + 1)..<width {
            if isSet(c) { return c }
        }
        return width - 1
    }

    /// Find the previous tab stop before the given column.
    /// Returns 0 if no tab stop is found.
    public func previousStop(before col: Int) -> Int {
        for c in stride(from: col - 1, through: 0, by: -1) {
            if isSet(c) { return c }
        }
        return 0
    }

    /// Resize to a new width, preserving existing tab stops.
    public mutating func resize(_ newWidth: Int, tabWidth: Int = 8) {
        let oldWidth = width
        let newWordCount = (newWidth + 63) / 64
        if newWordCount > bits.count {
            bits.append(contentsOf: [UInt64](repeating: 0, count: newWordCount - bits.count))
        }
        // Set default tab stops in the newly added range
        for col in stride(from: ((oldWidth / tabWidth) + 1) * tabWidth, to: newWidth, by: tabWidth) {
            if col >= oldWidth {
                let word = col / 64
                let bit = col % 64
                bits[word] |= (1 << bit)
            }
        }
    }
}
