import Foundation

/// Detects URLs in terminal text for implicit hyperlink highlighting.
public struct LinkDetector: Sendable {
    /// A detected link in terminal text.
    public struct LinkMatch: Sendable {
        public var url: String
        public var startCol: Int
        public var endCol: Int   // exclusive
        public var row: Int
    }

    // The regex pattern for URL detection:
    // Schemes: https?, ftp, file, ssh, git (with ://), mailto: and tel: (without //)
    // URL body: valid URL characters including balanced parentheses
    private static let urlPattern: String = {
        let schemes = "(?:https?://|ftp://|file://|ssh://|git://|mailto:|tel:)"
        // URL characters: word chars, common URL punctuation, balanced parens
        let urlChars = "[\\w\\-.~:/?#\\[\\]@!$&'*+,;=%]"
        // Allow parenthesized groups (for Wikipedia-style URLs)
        let parenGroup = "(?:\\(\(urlChars)*\\))"
        // The URL body: a mix of url chars and paren groups, at least one char
        let urlBody = "(?:\(parenGroup)|\(urlChars))+"
        return "\(schemes)\(urlBody)"
    }()

    private static let compiledRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: urlPattern, options: [])
    }()

    /// Detect all links in a line of text.
    public static func detectLinks(in text: String, row: Int) -> [LinkMatch] {
        guard let regex = compiledRegex else { return [] }
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> LinkMatch? in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            var url = String(text[swiftRange])

            // Strip trailing punctuation that is not balanced
            url = stripTrailingPunctuation(url)
            guard !url.isEmpty else { return nil }

            // Recalculate the end column after stripping
            let startCol = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let endCol = startCol + url.count

            return LinkMatch(url: url, startCol: startCol, endCol: endCol, row: row)
        }
    }

    /// Detect a link at a specific column position.
    public static func linkAt(col: Int, in text: String, row: Int) -> LinkMatch? {
        let links = detectLinks(in: text, row: row)
        return links.first { col >= $0.startCol && col < $0.endCol }
    }

    /// Strip trailing punctuation that is unlikely to be part of the URL.
    /// Keeps balanced parentheses and does not strip if it would break the URL.
    private static func stripTrailingPunctuation(_ url: String) -> String {
        let trailingChars: Set<Character> = [".", ",", ":", ";", "!", "?", "\"", "'", ")"]
        var result = url

        while let last = result.last, trailingChars.contains(last) {
            // Special case for closing paren: only strip if unbalanced
            if last == ")" {
                let openCount = result.filter({ $0 == "(" }).count
                let closeCount = result.filter({ $0 == ")" }).count
                if closeCount <= openCount {
                    break  // parens are balanced, keep the closing paren
                }
            }
            result = String(result.dropLast())
        }
        return result
    }
}
