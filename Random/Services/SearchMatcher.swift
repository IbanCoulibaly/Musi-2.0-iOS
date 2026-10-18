import Foundation

/// Forgiving search used by the Library and Artists pages. It ignores case,
/// accents and punctuation; matches the start of words in any order ("hiro
/// kita" finds "Kitadani Hiroshi"); tolerates one typo in words of five or
/// more letters ("kitadanni"); and ignores spacing ("onepiece" finds "One
/// Piece").
enum SearchMatcher {
    static func words(_ text: String) -> [String] {
        AppDesign.songMatchKey(for: text).split(separator: " ").map(String.init)
    }

    /// `true` when every word of the query matches a word in any candidate.
    static func matches(_ query: String, in candidates: [String]) -> Bool {
        let queryWords = words(query)
        guard !queryWords.isEmpty else { return true }
        let candidateWords = candidates.map(words)

        let joinedQuery = queryWords.joined()
        if joinedQuery.count >= 3,
           candidateWords.contains(where: { $0.joined().contains(joinedQuery) }) {
            return true
        }

        let allWords = candidateWords.flatMap { $0 }
        return queryWords.allSatisfy { queryWord in
            allWords.contains { wordMatches(queryWord, $0) }
        }
    }

    private static func wordMatches(_ query: String, _ word: String) -> Bool {
        if word.hasPrefix(query) { return true }
        guard query.count >= 5 else { return false }
        if isWithinOneEdit(query, word) { return true }
        // Still typing a longer word, with a typo in what's typed so far.
        return word.count > query.count && isWithinOneEdit(query, String(word.prefix(query.count)))
    }

    /// Whether two words differ by at most one inserted, deleted or changed letter.
    static func isWithinOneEdit(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count {
                i += 1
            } else if a.count < b.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }
}
