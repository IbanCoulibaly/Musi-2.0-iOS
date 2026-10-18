import Foundation

/// A guess at a song's artist and title, read from how the song is named.
struct ArtistGuess: Equatable {
    enum Confidence: Int, Comparable {
        /// Plausible, but only used once confirmed online.
        case low = 1
        /// Used when offline; confirmed or corrected online.
        case medium
        /// A strong naming convention; still confirmed online for spelling.
        case high

        static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The naming pattern a guess came from, in the order they're tried.
    enum Method: String, CaseIterable {
        case knownArtist
        case japaneseBrackets
        case dashSeparator
        case quotedTitle
        case byline
        case slashSeparator
        case pipeSeparator
        case animeLabelSegments
        case bracketPrefix
        case colonSeparator
        case trailingParenthetical
        case featuredCredit
        case wideSpace

        var label: String {
            switch self {
            case .knownArtist: "an artist already in your library"
            case .japaneseBrackets: "Artist「Title」"
            case .dashSeparator: "Artist - Title"
            case .quotedTitle: "Artist \"Title\""
            case .byline: "Title by Artist"
            case .slashSeparator: "Title / Artist"
            case .pipeSeparator: "Artist | Title"
            case .animeLabelSegments: "Show OP - Title - Artist"
            case .bracketPrefix: "[Artist] Title"
            case .colonSeparator: "Artist: Title"
            case .trailingParenthetical: "Title (Artist)"
            case .featuredCredit: "Title (feat. Artist)"
            case .wideSpace: "Artist　Title"
            }
        }
    }

    let artist: String
    let title: String
    let method: Method
    let confidence: Confidence
}

/// Reads a song's name with 13 independent pattern detectors and returns every
/// plausible artist/title split, best first. Offline, the best medium-or-high
/// guess is shown; online, guesses are checked against the music catalog in
/// this order until one is confirmed, which also corrects its spelling.
enum ArtistGuesser {
    /// Words that are never an artist: bracketed labels, version tags, and
    /// generic words uploaders put around titles.
    private static let notArtistWords: Set<String> = [
        "mv", "pv", "official", "lyrics", "lyric", "audio", "video", "music video",
        "hd", "hq", "4k", "live", "remix", "acoustic", "instrumental", "karaoke",
        "cover", "nightcore", "slowed", "reverb", "sped up", "tv size", "full",
        "full version", "short version", "english", "romaji", "english cover",
        "english lyrics", "romaji lyrics", "amv", "ost", "remastered", "extended",
        "radio edit", "edit", "mix", "version", "ver", "new", "single", "demo",
        "lofi", "lo fi", "piano", "piano version", "8d audio", "topic", "vevo",
        "visualizer", "clean", "explicit", "bass boosted", "original", "animation",
        "anime", "opening", "ending", "op", "ed", "theme", "soundtrack", "song",
        "feat", "ft", "featuring", "prod", "unknown", "various artists"
    ]

    private static func isNotArtist(_ text: String) -> Bool {
        let key = AppDesign.songMatchKey(for: text)
        if key.isEmpty || notArtistWords.contains(key) { return true }
        let words = key.split(separator: " ").map(String.init)
        return words.allSatisfy { notArtistWords.contains($0) || $0.allSatisfy(\.isNumber) }
    }

    static func guesses(for rawTitle: String, knownArtists: [String] = []) -> [ArtistGuess] {
        let text = SongMetadataParser.cleanedTitle(rawTitle)
        var results: [ArtistGuess] = []

        func add(_ artist: some StringProtocol, _ title: some StringProtocol,
                 _ method: ArtistGuess.Method, _ confidence: ArtistGuess.Confidence) {
            let rawArtist = String(artist).trimmingCharacters(in: .whitespaces)
            var cleanTitle = String(title).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|:/")))
            cleanTitle = cleanTitle.replacingOccurrences(of: #"^[「『"“]|[」』"”]$"#, with: "", options: .regularExpression)
            guard !cleanTitle.isEmpty,
                  !ShowCatalog.isShowLabel(rawArtist),
                  !isNotArtist(rawArtist),
                  !ShowCatalog.isShowLabel(cleanTitle),
                  let name = ArtistNameFormatter.clean(rawArtist),
                  !isNotArtist(name),
                  AppDesign.songMatchKey(for: name) != AppDesign.songMatchKey(for: cleanTitle),
                  name.split(separator: " ").count <= 6 else { return }
            let guess = ArtistGuess(artist: name, title: cleanTitle, method: method, confidence: confidence)
            if let index = results.firstIndex(where: {
                AppDesign.songMatchKey(for: $0.artist) == AppDesign.songMatchKey(for: name)
                    && AppDesign.songMatchKey(for: $0.title) == AppDesign.songMatchKey(for: cleanTitle)
            }) {
                if results[index].confidence < confidence { results[index] = guess }
            } else {
                results.append(guess)
            }
        }

        /// Adds both readings of a two-part name. The order that the name's
        /// own clues point to (or the convention's usual order) is the strong
        /// guess; the other is kept as a weak guess for online checking.
        func addPair(_ first: String, _ second: String, artistFirstByDefault: Bool,
                     _ method: ArtistGuess.Method, strong: ArtistGuess.Confidence) {
            let artistFirst = pairOrderClue(first: first, second: second) ?? artistFirstByDefault
            if artistFirst {
                add(first, second, method, strong)
                add(second, first, method, .low)
            } else {
                add(second, first, method, strong)
                add(first, second, method, .low)
            }
        }

        // 1. An artist already known from other songs appears in the name.
        //    Only a whole part of the name counts as strong evidence ("Blue
        //    Bird (Ikimonogakari)", "Silhouette - KANA-BOON"). The name merely
        //    appearing inside a phrase is a weak guess: "Dancing Queen - ABBA"
        //    isn't by Queen, and "Christmas Eve" isn't by Eve.
        let segmentKeys = Set(nameSegments(text).map { AppDesign.songMatchKey(for: $0) })
        let paddedKey = " \(AppDesign.songMatchKey(for: text)) "
        for known in knownArtists.sorted(by: { $0.count > $1.count }) {
            let knownKey = AppDesign.songMatchKey(for: known)
            guard knownKey.count >= 2, paddedKey.contains(" \(knownKey) ") else { continue }
            guard let range = text.range(of: known, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            var remainder = text
            remainder.removeSubrange(range)
            let isWholePart = segmentKeys.contains(knownKey)
            add(known, titleLeftOver(remainder), .knownArtist, isWholePart ? .high : .low)
            if isWholePart { break }
        }

        // 2. Artist「Title」 or Artist『Title』, the usual Japanese convention.
        if let match = firstMatch(#"^(.+?)\s*[「『](.+?)[」』]"#, in: text) {
            add(match[0], match[1], .japaneseBrackets, .high)
        } else if let match = firstMatch(#"^[「『](.+?)[」』]\s*(.+)$"#, in: text) {
            add(match[1], match[0], .japaneseBrackets, .medium)
        }

        // 3. Artist - Title (the most common convention), or Title - Artist
        //    when the name shows signs of that order.
        let dashParts = split(text, on: #"\s+[-–—]\s+"#)
        if dashParts.count == 2 {
            addPair(dashParts[0], dashParts[1], artistFirstByDefault: true, .dashSeparator, strong: .high)
        }

        // 4. Artist "Title" / Artist 'Title', or "Title" Artist.
        if let match = firstMatch(#"^([^"“]+?)\s+["“]([^"”]+)["”]\s*$"#, in: text) {
            add(match[0], match[1], .quotedTitle, .medium)
        } else if let match = firstMatch(#"^["“]([^"”]+)["”]\s*(?:by\s+)?(.+)$"#, in: text) {
            add(match[1], match[0], .quotedTitle, .medium)
        }

        // 5. Title (by Artist) / Title (Cover by Artist) / Title by Artist.
        //    A bare "by" is low confidence: "Stand by Me" isn't by "Me".
        if let match = firstMatch(#"(?i)^(.+?)\s*[\(\[]\s*(?:(?:cover(?:ed)?|sung|performed)\s+)?by\s+([^\)\]]+)[\)\]]\s*$"#, in: text) {
            add(match[1], match[0], .byline, .medium)
        } else if let match = firstMatch(#"(?i)^(.+?)\s+(?:cover(?:ed)?|sung|performed)\s+by\s+(.+)$"#, in: text) {
            add(match[1], match[0], .byline, .medium)
        } else if let match = firstMatch(#"(?i)^(.+?)(?<!prod\.)(?<!prod)(?<!produced)(?<!remix)(?<!mixed)\s+by\s+(.+)$"#, in: text) {
            add(match[1], match[0], .byline, .low)
        }

        // 6. Title / Artist, common for Japanese uploads, or Artist / Title.
        //    Saved files can't contain "/", so the app stores it as " _ ".
        let slashParts = split(text, on: #"\s+[/／_]\s+|／"#)
        if slashParts.count == 2 {
            addPair(slashParts[0], slashParts[1], artistFirstByDefault: false, .slashSeparator, strong: .medium)
        }

        // 7. Artist | Title, after dropping segments like "Lyrics".
        let pipeParts = split(text, on: #"\s*[|｜]\s*"#).filter { !isNotArtist($0) || $0.count > 12 }
        if pipeParts.count == 2 {
            addPair(pipeParts[0], pipeParts[1], artistFirstByDefault: true, .pipeSeparator, strong: .medium)
        }

        // 8. Show OP 16 - Title - Artist: drop show-label segments, then try
        //    both orders of what remains.
        let segments = split(text, on: #"\s+[-–—|｜/／_]\s+|[|｜／]"#)
        if segments.count >= 2 {
            let meaningful = segments.filter { !ShowCatalog.isShowLabel($0) && !isNotArtist($0) }
            if meaningful.count == 2, meaningful.count < segments.count {
                // After a leading show label the usual order is Title - Artist;
                // with only trailing noise ("- Remix") it's Artist - Title.
                if ShowCatalog.isShowLabel(segments[0]) {
                    add(meaningful[1], meaningful[0], .animeLabelSegments, .medium)
                    add(meaningful[0], meaningful[1], .animeLabelSegments, .low)
                } else {
                    add(meaningful[0], meaningful[1], .animeLabelSegments, .medium)
                    add(meaningful[1], meaningful[0], .animeLabelSegments, .low)
                }
            }
        }

        // 9. [Artist] Title or 【Artist】Title.
        if let match = firstMatch(#"^[\[【]([^\]】]+)[\]】]\s*(.+)$"#, in: text) {
            add(match[0], match[1], .bracketPrefix, .medium)
        }

        // 10. Artist: Title. Colons also appear inside titles, so low.
        if let match = firstMatch(#"^([^:：]{2,40}?)\s*[:：]\s+(.+)$"#, in: text) {
            add(match[0], match[1], .colonSeparator, .low)
        }

        // 11. Title (Artist), when the parenthetical isn't a version label.
        if let match = firstMatch(#"^(.+?)\s*[\(\[（]([^\)\]）]+)[\)\]）]\s*$"#, in: text),
           match[1].range(of: #"(?i)\b(feat|ft|from|remix|mix|edit|version|ver|live|cover|op|ed|opening|ending|season|part|tv|acoustic|instrumental)\b"#,
                          options: .regularExpression) == nil {
            add(match[1], match[0], .trailingParenthetical, .low)
        }

        // 12. Title (feat. Artist). The featured artist is only a fallback.
        if let match = firstMatch(#"(?i)^(.+?)\s*[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\s+([^\)\]]+?)[\)\]]?\s*$"#, in: text) {
            add(match[1], match[0], .featuredCredit, .low)
        }

        // 13. Artist　Title, separated by a full-width space or wide gap.
        let spaced = split(text, on: #"\x{3000}+|\s{3,}"#)
        if spaced.count == 2 {
            add(spaced[0], spaced[1], .wideSpace, .low)
        }

        let order = Dictionary(uniqueKeysWithValues: ArtistGuess.Method.allCases.enumerated().map { ($1, $0) })
        return results.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return order[$0.method, default: 0] < order[$1.method, default: 0]
        }
    }

    /// Guesses in the order to check them online: each guess followed by its
    /// reverse reading (artist and title swapped), so a name in the less
    /// common "Title - Artist" order is always checked both ways.
    static func confirmationOrder(_ guesses: [ArtistGuess], limit: Int = 4) -> [ArtistGuess] {
        var ordered: [ArtistGuess] = []
        func key(_ text: String) -> String { AppDesign.songMatchKey(for: text) }
        func contains(_ guess: ArtistGuess) -> Bool {
            ordered.contains { key($0.artist) == key(guess.artist) && key($0.title) == key(guess.title) }
        }
        for guess in guesses where !contains(guess) {
            ordered.append(guess)
            if let reverse = guesses.first(where: {
                key($0.artist) == key(guess.title) && key($0.title) == key(guess.artist)
            }), !contains(reverse) {
                ordered.append(reverse)
            }
        }
        return Array(ordered.prefix(limit))
    }

    /// The best guess worth showing without online confirmation.
    static func bestOfflineGuess(for rawTitle: String, knownArtists: [String] = []) -> ArtistGuess? {
        guesses(for: rawTitle, knownArtists: knownArtists).first { $0.confidence >= .medium }
    }

    // MARK: Helpers

    /// Clues to which half of a two-part name is the artist. Returns `true`
    /// for artist-first, `false` for title-first, `nil` without a clue.
    ///
    /// Artist-side clues: channel words ("Official", "VEVO", "- Topic",
    /// "公式"). Title-side clues: Japanese title brackets or quotes, a
    /// "(feat. …)" credit, or a show label ("(Naruto OP 16)").
    static func pairOrderClue(first: String, second: String) -> Bool? {
        func artistScore(_ text: String) -> Int {
            text.range(of: #"(?i)(\bofficial\b|\bofficial(?=\p{Han}|\p{Hiragana}|\p{Katakana})|vevo\b|\btopic$|公式|オフィシャル)"#,
                       options: .regularExpression) != nil ? 1 : 0
        }
        func titleScore(_ text: String) -> Int {
            var score = 0
            if text.range(of: #"[「『"“].+[」』"”]"#, options: .regularExpression) != nil { score += 1 }
            if text.range(of: #"(?i)[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s"#, options: .regularExpression) != nil { score += 1 }
            if let paren = text.range(of: #"[\(\[（][^\)\]）]+[\)\]）]"#, options: .regularExpression),
               ShowCatalog.show(in: String(text[paren])) != nil { score += 1 }
            return score
        }
        let firstLooksLikeArtist = artistScore(first) + titleScore(second)
        let secondLooksLikeArtist = artistScore(second) + titleScore(first)
        if firstLooksLikeArtist == secondLooksLikeArtist { return nil }
        return firstLooksLikeArtist > secondLooksLikeArtist
    }

    /// The parts of a name: text inside brackets, and the pieces between
    /// separators outside them.
    private static func nameSegments(_ text: String) -> [String] {
        let bracketPattern = #"[\(\[（【「『]([^\)\]）】」』]+)[\)\]）】」』]"#
        var segments: [String] = []
        if let regex = try? NSRegularExpression(pattern: bracketPattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { segments.append(String(text[range])) }
            }
        }
        let outside = text.replacingOccurrences(of: bracketPattern, with: " | ", options: .regularExpression)
        segments += split(outside, on: #"\s+[-–—|｜/／_:：]\s+|[|｜／]|\x{3000}+|\s{3,}"#)
        return segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// What's left of a name once the artist is cut out ("Blue Bird ()",
    /// "Naruto OP 16 - Silhouette - "), tidied into just the title: empty
    /// brackets and dangling separators go, and so do segments that are only
    /// a show label or noise like "Lyrics".
    private static func titleLeftOver(_ remainder: String) -> String {
        let withoutEmptyBrackets = remainder.replacingOccurrences(
            of: #"[\(\[（【「『]\s*[\)\]）】」』]"#, with: " ", options: .regularExpression
        )
        let segments = split(withoutEmptyBrackets, on: #"\s+[-–—|｜/／_]\s+|[|｜／]|^\s*[-–—_]\s*|\s*[-–—_]\s*$"#)
            .filter { !ShowCatalog.isShowLabel($0) && !isNotArtist($0) }
        let title = (segments.isEmpty ? [withoutEmptyBrackets] : segments).joined(separator: " - ")
        return title
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|:/_,")))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[range]).trimmingCharacters(in: .whitespaces))
        }
        return groups.contains(where: \.isEmpty) ? nil : groups
    }

    private static func split(_ text: String, on pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        var parts: [String] = []
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(text[cursor...]))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
