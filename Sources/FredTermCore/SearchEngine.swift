import Foundation

/// Search options for terminal text search.
public struct SearchOptions: Sendable {
    public var caseSensitive: Bool
    public var regex: Bool
    public var wholeWord: Bool
    public var wrapAround: Bool

    public init(
        caseSensitive: Bool = false,
        regex: Bool = false,
        wholeWord: Bool = false,
        wrapAround: Bool = true
    ) {
        self.caseSensitive = caseSensitive
        self.regex = regex
        self.wholeWord = wholeWord
        self.wrapAround = wrapAround
    }
}

/// A single search result.
public struct SearchResult: Sendable {
    public var startPosition: Position
    public var endPosition: Position
    public var lineIndex: Int

    public init(startPosition: Position, endPosition: Position, lineIndex: Int) {
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.lineIndex = lineIndex
    }
}

/// Terminal text search engine.
///
/// Searches across the cell grid (visible and scrollback) for text matches.
public struct SearchEngine: Sendable {
    /// Search the grid for matches of the given query.
    public static func search(
        query: String,
        in grid: CellGrid,
        graphemes: GraphemeTable,
        options: SearchOptions = SearchOptions(),
        maxResults: Int = 1000
    ) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []
        let pattern: String
        if options.regex {
            pattern = query
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }

        let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return []
        }

        for lineIdx in 0..<grid.count {
            let lineText = grid.lineText(lineIdx, trimTrailing: false)
            let nsString = lineText as NSString
            let matches = regex.matches(
                in: lineText,
                range: NSRange(location: 0, length: nsString.length)
            )

            for match in matches {
                let startCol = match.range.location
                let endCol = match.range.location + match.range.length - 1

                results.append(SearchResult(
                    startPosition: Position(col: startCol, row: lineIdx),
                    endPosition: Position(col: endCol, row: lineIdx),
                    lineIndex: lineIdx
                ))

                if results.count >= maxResults { return results }
            }
        }

        return results
    }

    /// Find the next result after a given position.
    public static func findNext(
        query: String,
        after position: Position,
        in grid: CellGrid,
        graphemes: GraphemeTable,
        options: SearchOptions = SearchOptions()
    ) -> SearchResult? {
        let allResults = search(query: query, in: grid, graphemes: graphemes, options: options)
        if let next = allResults.first(where: { $0.startPosition > position }) {
            return next
        }
        // Wrap around
        if options.wrapAround {
            return allResults.first
        }
        return nil
    }

    /// Find the previous result before a given position.
    public static func findPrevious(
        query: String,
        before position: Position,
        in grid: CellGrid,
        graphemes: GraphemeTable,
        options: SearchOptions = SearchOptions()
    ) -> SearchResult? {
        let allResults = search(query: query, in: grid, graphemes: graphemes, options: options)
        if let prev = allResults.last(where: { $0.startPosition < position }) {
            return prev
        }
        if options.wrapAround {
            return allResults.last
        }
        return nil
    }
}
