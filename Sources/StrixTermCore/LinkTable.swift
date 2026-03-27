/// Per-terminal hyperlink storage.
/// Each link gets a UInt16 ID stored in the cell's `payload` field.
/// The cell's `.hasLink` flag indicates a payload is a link ID.
///
/// Follows the same pattern as GraphemeTable: instance-local, with insert/lookup/release
/// and a free list for reuse of IDs.
public struct LinkTable: Sendable {
    /// A stored hyperlink with URL and optional parameters.
    public struct LinkEntry: Sendable, Equatable {
        public var url: String
        public var params: [String: String]  // e.g., id=xxx

        public init(url: String, params: [String: String] = [:]) {
            self.url = url
            self.params = params
        }
    }

    private var entries: [LinkEntry?]
    private var freeList: [UInt16]
    private var urlToId: [String: UInt16]  // dedup same URLs (only when params are empty)

    public init() {
        entries = []
        freeList = []
        urlToId = [:]
    }

    /// Store a link, returning its ID (for cell payload).
    /// ID 0 is reserved (no link), so the first real ID is 1.
    public mutating func insert(url: String, params: [String: String] = [:]) -> UInt16 {
        // Dedup: if same URL with empty params, reuse existing ID
        if params.isEmpty, let existingId = urlToId[url] {
            return existingId
        }

        let id: UInt16
        if let free = freeList.popLast() {
            entries[Int(free) - 1] = LinkEntry(url: url, params: params)
            id = free
        } else {
            entries.append(LinkEntry(url: url, params: params))
            id = UInt16(entries.count)  // 1-based
        }

        if params.isEmpty {
            urlToId[url] = id
        }
        return id
    }

    /// Look up a link by ID. ID 0 means no link.
    public func lookup(_ id: UInt16) -> LinkEntry? {
        guard id > 0, Int(id) - 1 < entries.count else { return nil }
        return entries[Int(id) - 1]
    }

    /// Release a link ID (when cell is overwritten).
    public mutating func release(_ id: UInt16) {
        guard id > 0, Int(id) - 1 < entries.count else { return }
        let index = Int(id) - 1
        if let entry = entries[index], entry.params.isEmpty {
            urlToId.removeValue(forKey: entry.url)
        }
        entries[index] = nil
        freeList.append(id)
    }

    /// Number of active entries.
    public var count: Int {
        entries.compactMap({ $0 }).count
    }
}
