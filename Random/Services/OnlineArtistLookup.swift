import Foundation

/// One-time online artist search, backed by Apple's public iTunes Search API
/// (no account or key). Only the song's title is sent.
enum OnlineArtistLookup {
    struct SearchResponse: Decodable {
        struct Item: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionName: String?
        }
        let results: [Item]
    }

    enum LookupError: Error {
        /// Rate limited, offline, or a server error. The song is not marked
        /// as searched, so it is retried on a later run.
        case unavailable
    }

    /// Marks a result as someone else's version of the song. The catalog is
    /// full of covers, karaoke and tribute albums, and for anime songs they
    /// often outrank the original. Whole words only, so "Discovery" is fine.
    private static let versionMarkerPattern =
        #"(?i)\b(covers?|covered|karaoke|tribute|originally performed|made famous|in the style of|lullaby|music box|piano version|8[- ]?bit|instrumental|remix|arrange\w*)\b|\(from [\"“]"#

    /// Bumped whenever the matching rules improve, so songs searched under
    /// older rules get one more search.
    static let currentVersion = 4

    /// Searches once for a song's artist and the show it belongs to.
    ///
    /// 1. Confirm: each guess read from the song's name (up to three, best
    ///    first), or the artist from its file tags, is searched as
    ///    "<artist> <title>". The first one the catalog confirms wins, and its
    ///    catalog spelling replaces the guess, which fixes capitalization and
    ///    turns Japanese names into their official English form.
    /// 2. Find: with no confirmed artist and no reasonable guess, the title is
    ///    searched on its own and the most likely original artist is picked.
    /// 3. Show: if the show isn't known, the title search's soundtrack and
    ///    compilation albums are used as evidence (see `showEvidence`).
    ///
    /// Returns a result with `nil` fields when searching worked but nothing
    /// was confident. Throws `LookupError.unavailable` when a search failed,
    /// so the song is retried later.
    static func lookup(
        rawTitle: String,
        guesses: [ArtistGuess],
        taggedArtist: String?,
        needsShow: Bool
    ) async throws -> OnlineArtistMatch {
        var match = OnlineArtistMatch(version: currentVersion)
        let show = ShowCatalog.show(in: rawTitle)
        let fallbackTitle = guesses.first?.title ?? SongMetadataParser.parseArtistAndTitle(from: rawTitle).title
        var requestCount = 0

        func search(_ term: String, limit: Int) async throws -> [SearchResponse.Item] {
            if requestCount > 0 { try await Task.sleep(for: .seconds(3)) }
            requestCount += 1
            return try await Self.search(term: term, limit: limit)
        }

        // 1. Confirm the tagged artist (for its English spelling) or the guesses.
        //    Up to 50 results are fetched because the covers and soundtrack
        //    albums among them are also the evidence for which show it's from.
        let toConfirm: [ArtistGuess] = taggedArtist.map {
            [ArtistGuess(artist: $0, title: fallbackTitle, method: .knownArtist, confidence: .high)]
        } ?? ArtistGuesser.confirmationOrder(guesses)
        var evidence: (results: [SearchResponse.Item], title: String)?
        var confirmedTitle = fallbackTitle
        for guess in toConfirm {
            let title = searchableTitle(guess.title)
            guard !title.isEmpty else { continue }
            let results = try await search("\(guess.artist) \(title)", limit: 50)
            if let confirmed = confirmation(of: guess, in: results) {
                match.artist = primaryArtist(catalogName: confirmed.artist, guess: guess.artist)
                match.confirmedGuess = guess.artist
                match.collection = confirmed.collection
                confirmedTitle = guess.title
                // The catalog's English title ("Gurenge" for 紅蓮華) is what
                // covers and compilations use.
                let catalogTitle = searchableTitle(strippingBrackets(confirmed.track))
                evidence = (results, catalogTitle.isEmpty ? title : catalogTitle)
                break
            }
        }

        // A Japanese name the title search didn't confirm: look it up in the
        // catalog's *artist* index for its official English spelling
        // (北谷洋 -> "Kitadani Hiroshi"), then check that spelling with the
        // song's title. Searching songs instead would mistake a Japanese song
        // title for an artist: "紅蓮華" finds mostly LiSA songs, but it's
        // LiSA's song, not LiSA's name.
        let bestGuess = guesses.first { $0.confidence >= .medium }
        if match.confirmedGuess == nil,
           let japaneseName = taggedArtist ?? bestGuess?.artist,
           ArtistNameFormatter.containsJapanese(japaneseName) {
            let artists = try await searchArtists(japaneseName)
            if let official = englishArtistName(in: artists) {
                let title = taggedArtist == nil ? (bestGuess?.title ?? fallbackTitle) : fallbackTitle
                let searchTitle = searchableTitle(title)
                let results = try await search("\(official) \(searchTitle)", limit: 50)
                let check = ArtistGuess(artist: official, title: title, method: .knownArtist, confidence: .high)
                if confirmation(of: check, in: results) != nil {
                    match.artist = official
                    match.confirmedGuess = japaneseName
                    confirmedTitle = title
                    evidence = (results, searchTitle)
                }
            }
        }

        let hasUsableGuess = taggedArtist != nil || bestGuess != nil
        let needsArtist = match.confirmedGuess == nil && !hasUsableGuess

        // 2. Search the title on its own to find the artist, or to gather show
        //    evidence when no confirmation search ran.
        if needsArtist || (needsShow && evidence == nil) {
            let title = searchableTitle(confirmedTitle)
            guard !title.isEmpty else { return match }
            let term = [show.map { AppDesign.songMatchKey(for: $0.name) }, title]
                .compactMap { $0 }
                .joined(separator: " ")
            let results = try await search(term, limit: 25)
            if needsArtist {
                let corroboratingShow = show ?? showMatch(queryTitle: title, artist: nil, results: results)
                let found = bestMatch(queryTitle: title, show: corroboratingShow, results: results)
                match.artist = found.artist
                match.collection = found.collection
            }
            evidence = evidence ?? (results, title)
        }

        // 3. Which show it's from.
        guard needsShow, let evidence else { return match }
        let artist = match.artist ?? taggedArtist ?? bestGuess?.artist
        match.show = showMatch(queryTitle: evidence.title, artist: artist, results: evidence.results)?.name

        // Weak show evidence (a common title such as "Silhouette" where only a
        // couple of covers name the show) is confirmed with a second search
        // for "<artist> <show>": the catalog ranks an artist's tie-in songs
        // first for such searches, but not songs unrelated to the show.
        if match.show == nil,
           let artist,
           let weak = showEvidence(queryTitle: evidence.title, artist: artist, results: evidence.results),
           !weak.isConclusive {
            let confirmation = try await search("\(artist) \(weak.show.name)", limit: 5)
            if confirmsShow(queryTitle: evidence.title, artist: artist, results: confirmation) {
                match.show = weak.show.name
            }
        }
        return match
    }

    /// The catalog's spelling of just the guessed artist when the catalog
    /// credits a collaboration ("Imagine Dragons & JID" for a guess of
    /// "Imagine Dragons"), so one artist doesn't split into several entries.
    /// A guess naming the whole group ("Simon & Garfunkel") is kept whole.
    static func primaryArtist(catalogName: String, guess: String) -> String {
        let full = SongMetadataParser.normalizedArtistName(catalogName)
        let guessTokens = tokens(guess)
        guard !guessTokens.isEmpty, tokens(full).subtracting(guessTokens).count > 0 else { return full }
        let parts = full
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .flatMap { $0.components(separatedBy: " x ") }
            .flatMap { $0.components(separatedBy: " X ") }
            .flatMap { $0.components(separatedBy: " with ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.first { jaccard(tokens($0), guessTokens) >= 0.8 } ?? full
    }

    /// The catalog's top artist match when it's written in English letters,
    /// which is the official English spelling of a Japanese name. A result
    /// still in Japanese or Chinese characters means no spelling is known.
    static func englishArtistName(in artists: [String]) -> String? {
        guard let top = artists.first else { return nil }
        let name = SongMetadataParser.normalizedArtistName(top)
        guard !ArtistNameFormatter.containsJapanese(name),
              name.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }) else { return nil }
        return name
    }

    private struct ArtistResponse: Decodable {
        struct Item: Decodable { let artistName: String? }
        let results: [Item]
    }

    private static func searchArtists(_ name: String) async throws -> [String] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { throw LookupError.unavailable }
        try await Task.sleep(for: .seconds(3))
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LookupError.unavailable }
            return try JSONDecoder().decode(ArtistResponse.self, from: data).results.compactMap(\.artistName)
        } catch {
            throw LookupError.unavailable
        }
    }

    private static func isOtherVersion(_ item: SearchResponse.Item) -> Bool {
        let text = [item.trackName, item.collectionName, item.artistName].compactMap { $0 }.joined(separator: " ")
        return text.range(of: versionMarkerPattern, options: .regularExpression) != nil
    }

    /// A title as search terms: show names and "OP 16" style labels removed.
    private static func searchableTitle(_ title: String) -> String {
        ShowCatalog.strippingShowTerms(from: title)
    }

    /// A catalog result that confirms a guessed artist and title.
    struct Confirmation {
        /// The artist as the catalog writes it.
        let artist: String
        let track: String
        let collection: String?
    }

    /// Confirms a guess from search results, either way:
    ///
    /// - An original release among the first few results whose title and
    ///   artist both match the guess. Japanese text can't be compared with
    ///   the catalog's English spellings, so for a Japanese title or artist
    ///   the catalog's own ranking stands in (it indexes both scripts); when
    ///   both are Japanese, only the top result counts.
    /// - A cover whose credits name the guessed artist as the original
    ///   ("Christmas Eve (Originally Performed by Tatsuro Yamashita)"), for
    ///   songs whose original isn't in the catalog. The credited name is used,
    ///   never the cover artist's.
    static func confirmation(of guess: ArtistGuess, in results: [SearchResponse.Item]) -> Confirmation? {
        let titleTokens = tokens(searchableTitle(creditFree(guess.title)))
        let artistTokens = tokens(guess.artist)
        let japaneseTitle = ArtistNameFormatter.containsJapanese(guess.title)
        let japaneseArtist = ArtistNameFormatter.containsJapanese(guess.artist)

        // Covers, live and karaoke versions are skipped before ranking.
        for (index, item) in results.filter({ !isOtherVersion($0) }).prefix(5).enumerated() {
            guard let track = item.trackName, let artist = item.artistName else { continue }
            if japaneseTitle && japaneseArtist && index > 0 { break }

            let titleMatches = japaneseTitle
                ? index < 3
                : !titleTokens.isEmpty && jaccard(titleTokens, tokens(creditFree(track))) >= 0.6
            let artistMatches = japaneseArtist
                ? index < 3
                : overlap(artistTokens, tokens(SongMetadataParser.normalizedArtistName(artist))) >= 0.5
            if titleMatches && artistMatches {
                return Confirmation(artist: artist, track: track, collection: item.collectionName)
            }
        }

        guard !japaneseTitle, !titleTokens.isEmpty, !artistTokens.isEmpty else { return nil }
        for item in results.prefix(25) {
            guard let track = item.trackName,
                  let credited = originalArtistCredit(in: track + " " + (item.collectionName ?? "")),
                  overlap(artistTokens, tokens(credited)) >= 0.8,
                  jaccard(titleTokens, tokens(creditFree(track))) >= 0.6 else { continue }
            return Confirmation(artist: credited, track: creditFree(track), collection: nil)
        }
        return nil
    }

    /// The original artist a cover credits, as in "(Originally Performed by
    /// X)", "[Made Famous by X]" or "(In the Style of X)".
    static func originalArtistCredit(in text: String) -> String? {
        let pattern = #"(?i)(?:originally\s+performed\s+by|made\s+famous\s+by|in\s+the\s+style\s+of)\s*["“]?([^"”\)\]]+?)["”]?\s*[\)\]]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let name = text[range].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : SongMetadataParser.normalizedArtistName(name)
    }

    /// A title without bracketed extras and featured-artist credits, for
    /// comparing "Stay (feat. Justin Bieber)" with the catalog's "Stay".
    private static func creditFree(_ title: String) -> String {
        strippingBrackets(title)
            .replacingOccurrences(of: #"(?i)\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: .regularExpression)
    }


    private static func search(term: String, limit: Int) async throws -> [SearchResponse.Item] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { throw LookupError.unavailable }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LookupError.unavailable
            }
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            throw LookupError.unavailable
        }
    }

    /// Combines artist identification and show identification for one search.
    static func evaluate(
        queryTitle: String,
        knownArtist: String?,
        show: ShowDefinition?,
        results: [SearchResponse.Item]
    ) -> OnlineArtistMatch {
        var match = OnlineArtistMatch(version: currentVersion)
        if knownArtist == nil {
            // A show the results clearly point to also corroborates one-word
            // titles ("Gurenge") when the song's name doesn't mention it.
            let corroboratingShow = show ?? showMatch(queryTitle: queryTitle, artist: nil, results: results)
            let artistMatch = bestMatch(queryTitle: queryTitle, show: corroboratingShow, results: results)
            match.artist = artistMatch.artist
            match.collection = artistMatch.collection
        }
        match.show = showMatch(queryTitle: queryTitle, artist: knownArtist ?? match.artist, results: results)?.name
        return match
    }

    /// Works out which show a song belongs to from search results: soundtrack
    /// albums ("ONE PIECE Opening Theme") and anime-song compilations ("TV
    /// Anime Series 'Bleach'") name the show next to the song.
    ///
    /// Each result whose track name matches the title and whose track or album
    /// names a show casts a vote for it: 2 points from the song's own artist,
    /// 1 from anyone else (covers and compilations still show which show a song
    /// is from). The top show wins if it has 2+ points, or 3+ for one-word
    /// titles unless the artist's own release backs it, and isn't tied.
    static func showMatch(queryTitle: String, artist: String?, results: [SearchResponse.Item]) -> ShowDefinition? {
        guard let evidence = showEvidence(queryTitle: queryTitle, artist: artist, results: results),
              evidence.isConclusive else { return nil }
        return evidence.show
    }

    struct ShowEvidence {
        let show: ShowDefinition
        let points: Int
        /// Enough on its own; otherwise it needs `confirmsShow`.
        let isConclusive: Bool
    }

    /// The best-supported show in the results (see `showMatch`), or `nil` if
    /// none or two shows are tied.
    static func showEvidence(queryTitle: String, artist: String?, results: [SearchResponse.Item]) -> ShowEvidence? {
        let queryTokens = tokens(queryTitle)
        guard !queryTokens.isEmpty else { return nil }
        let artistTokens = artist.map(tokens) ?? []

        var votes: [String: (show: ShowDefinition, points: Int, artistBacked: Bool)] = [:]
        for item in results {
            guard let track = item.trackName,
                  jaccard(queryTokens, tokens(strippingBrackets(track))) >= 0.8 else { continue }
            let context = [track, item.collectionName].compactMap { $0 }.joined(separator: " ")
            guard let show = ShowCatalog.show(in: context, keywordsOnly: true) else { continue }

            let byArtist = !artistTokens.isEmpty && overlap(artistTokens, tokens(item.artistName ?? "")) >= 0.5
            var entry = votes[show.name] ?? (show, 0, false)
            entry.points += byArtist ? 2 : 1
            entry.artistBacked = entry.artistBacked || byArtist
            votes[show.name] = entry
        }

        let ranked = votes.values.sorted { $0.points > $1.points }
        guard let top = ranked.first else { return nil }
        if ranked.count > 1, ranked[1].points == top.points { return nil }
        let required = (top.artistBacked || queryTokens.count >= 2) ? 2 : 3
        return ShowEvidence(show: top.show, points: top.points, isConclusive: top.points >= required)
    }

    /// Whether a search for "<artist> <show>" ranks this artist's song with
    /// this title among its first three results.
    static func confirmsShow(queryTitle: String, artist: String, results: [SearchResponse.Item]) -> Bool {
        let queryTokens = tokens(queryTitle)
        let artistTokens = tokens(artist)
        guard !queryTokens.isEmpty, !artistTokens.isEmpty else { return false }
        return results.prefix(3).contains { item in
            guard let track = item.trackName else { return false }
            return jaccard(queryTokens, tokens(strippingBrackets(track))) >= 0.8
                && overlap(artistTokens, tokens(item.artistName ?? "")) >= 0.5
        }
    }

    /// Picks the most likely original artist from search results.
    ///
    /// 1. Keep results whose track name matches the queried title (word-set
    ///    similarity), ignoring bracketed extras like "(Radio Edit)".
    /// 2. Drop covers, karaoke, remixes and "(From "…")" re-recordings.
    /// 3. Score what's left: exact titles beat titles with extras, and earlier
    ///    results (the API's own relevance order) get a small bonus.
    /// 4. Sum scores per artist so an artist with several matching releases
    ///    beats a one-off, and return the top artist.
    ///
    /// One-word titles ("Memories") match far too many unrelated songs, so
    /// they are only accepted when the results themselves tie that title to
    /// the detected show (e.g. a "Bleach" album containing a track of the
    /// same name), which also proves the song really is from that show.
    static func bestMatch(queryTitle: String, show: ShowDefinition?, results: [SearchResponse.Item]) -> OnlineArtistMatch {
        let queryTokens = tokens(queryTitle)
        guard !queryTokens.isEmpty else { return OnlineArtistMatch() }

        struct Candidate {
            var name: String
            var score: Double
            var collection: String?
        }
        var candidates: [String: Candidate] = [:]

        let showCorroborated: Bool = {
            guard let show else { return false }
            return results.contains { item in
                guard let track = item.trackName else { return false }
                let context = [item.collectionName, item.trackName].compactMap { $0 }.joined(separator: " ")
                return ShowCatalog.show(in: context)?.name == show.name
                    && jaccard(queryTokens, tokens(strippingBrackets(track))) >= 0.7
            }
        }()

        for (index, item) in results.enumerated() {
            guard let track = item.trackName, let rawArtist = item.artistName else { continue }
            let artist = SongMetadataParser.normalizedArtistName(rawArtist)
            guard !artist.isEmpty else { continue }

            let haystack = [track, item.collectionName, rawArtist]
                .compactMap { $0 }
                .joined(separator: " ")
            if haystack.range(of: versionMarkerPattern, options: .regularExpression) != nil { continue }

            let similarity = jaccard(queryTokens, tokens(strippingBrackets(track)))
            guard similarity >= 0.7 else { continue }
            guard queryTokens.count >= 2 || showCorroborated else { continue }

            let isExact = track.rangeOfCharacter(from: CharacterSet(charactersIn: "([")) == nil
            let score = similarity + (isExact ? 0.5 : 0) + max(0, 0.3 - 0.03 * Double(index))
            let key = AppDesign.songMatchKey(for: artist)
            var candidate = candidates[key] ?? Candidate(name: artist, score: 0, collection: item.collectionName)
            candidate.score += score
            candidates[key] = candidate
        }

        guard let winner = candidates.values.max(by: { $0.score < $1.score }) else {
            return OnlineArtistMatch()
        }
        return OnlineArtistMatch(artist: winner.name, collection: winner.collection)
    }

    private static func strippingBrackets(_ text: String) -> String {
        text.replacingOccurrences(of: #"[\(\[][^)\]]*[\)\]]"#, with: " ", options: .regularExpression)
    }

    private static let ignoredWords: Set<String> = ["the", "a", "and", "of"]

    private static func tokens(_ text: String) -> Set<String> {
        Set(AppDesign.songMatchKey(for: text).split(separator: " ").map(String.init))
            .subtracting(ignoredWords)
    }

    /// Share of the smaller name's words found in the other, so
    /// "Hiroshi Kitadani" and "Kitadani Hiroshi" (name order differs between
    /// sources) count as the same artist.
    private static func overlap(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let smaller = min(lhs.count, rhs.count)
        return smaller == 0 ? 0 : Double(lhs.intersection(rhs).count) / Double(smaller)
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs).count
        return union == 0 ? 0 : Double(lhs.intersection(rhs).count) / Double(union)
    }
}
