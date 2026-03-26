/// Instance-local grapheme cluster storage.
///
/// Replaces SwiftTerm's global `TinyAtom` static dictionary.
/// When a cell needs to store a multi-scalar grapheme cluster (combining characters,
/// emoji sequences), the cluster is stored here and the cell's `codePoint` field
/// holds `threshold + index`.
///
/// This fixes issue #172 (TinyAtom global state) and #312 (combining characters broken)
/// by making grapheme storage per-terminal-instance.
public struct GraphemeTable: Sendable {
    /// Code points at or above this value are grapheme table indices.
    /// 0x11_0000 is one past the maximum valid Unicode scalar.
    public static let threshold: UInt32 = 0x11_0000

    private var clusters: [String]
    private var freeList: [Int]

    public init() {
        clusters = []
        freeList = []
    }

    /// Store a grapheme cluster and return its encoded codePoint value.
    public mutating func insert(_ cluster: String) -> UInt32 {
        let index: Int
        if let free = freeList.popLast() {
            clusters[free] = cluster
            index = free
        } else {
            index = clusters.count
            clusters.append(cluster)
        }
        return Self.threshold + UInt32(index)
    }

    /// Look up a grapheme cluster by its encoded codePoint.
    public func lookup(_ encoded: UInt32) -> String {
        let index = Int(encoded - Self.threshold)
        guard index >= 0 && index < clusters.count else { return " " }
        return clusters[index]
    }

    /// Release a grapheme cluster when its cell is overwritten.
    public mutating func release(_ encoded: UInt32) {
        let index = Int(encoded - Self.threshold)
        guard index >= 0 && index < clusters.count else { return }
        clusters[index] = ""
        freeList.append(index)
    }

    /// Check whether a codePoint is a grapheme table reference.
    @inline(__always)
    public static func isGraphemeRef(_ codePoint: UInt32) -> Bool {
        codePoint >= threshold
    }

    /// Number of active entries.
    public var count: Int {
        clusters.count - freeList.count
    }
}
