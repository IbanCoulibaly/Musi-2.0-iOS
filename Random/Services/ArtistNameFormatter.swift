import Foundation

/// Cleans artist names for display: removes show names and opening numbers
/// that uploaders glue onto names ("Naruto OP 16 KANA-BOON"), channel suffixes
/// and credits, and turns Japanese-script names into readable English letters.
enum ArtistNameFormatter {
    // MARK: Script detection

    static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: true   // kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true                  // kanji
        default: false
        }
    }

    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
        default: false
        }
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isJapanese)
    }

    private static func hasLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
    }

    // MARK: Cleanup

    /// Full cleanup for an automatically detected artist. Returns `nil` when
    /// nothing name-like is left, such as when the "artist" was only
    /// "Opening 16" or a show's name.
    static func clean(_ raw: String) -> String? {
        var name = SongMetadataParser.normalizedArtistName(raw)
        name = name.replacingOccurrences(
            of: #"[\(（\[]\s*(CV|cv|Cv|VO|vo)\s*[:：.][^\)）\]]*[\)）\]]"#,
            with: " ",
            options: .regularExpression
        )
        name = ShowCatalog.removingShowLabels(from: name)
        name = strippingChannelWords(name)
        name = preferringReadablePart(name)
        name = tidied(name)
        guard name.contains(where: \.isLetter), name.count >= 2 || containsJapanese(name) else { return nil }
        return name
    }

    /// How a cleaned name is shown: Japanese-script names are romanized.
    static func display(_ name: String) -> String {
        containsJapanese(name) ? romanized(name) : name
    }

    /// Drops "Official", "Official Channel", "公式" and the like that channel
    /// names add after the artist.
    private static func strippingChannelWords(_ name: String) -> String {
        var result = name
        let patterns = [
            #"(?i)\s*[\(\[【]?\s*official\s*(youtube\s*)?(channel)?\s*[\)\]】]?\s*$"#,
            #"(?i)\s+(youtube\s+)?channel\s*$"#,
            #"\s*[\(\[【]?\s*(公式|オフィシャル)(チャンネル)?\s*[\)\]】]?\s*$"#,
            #"^\s*[\[【]\s*(公式|official)\s*[\]】]\s*"#
        ]
        for pattern in patterns {
            let trimmed = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            if !trimmed.trimmingCharacters(in: .whitespaces).isEmpty { result = trimmed }
        }
        return result
    }

    /// For names given in two scripts ("LiSA（織部里沙）", "米津玄師 Kenshi
    /// Yonezu", "北谷洋 / Hiroshi Kitadani"), keeps just the English-letter
    /// part. For Japanese-only names that include a kana reading
    /// ("米津玄師（よねづけんし）"), keeps the reading, which romanizes exactly.
    private static func preferringReadablePart(_ name: String) -> String {
        guard containsJapanese(name) else { return name }

        let segments = name
            .components(separatedBy: CharacterSet(charactersIn: "()（）[]【】「」『』/／|｜"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Group runs of words by script within each segment.
        var latinGroups: [String] = []
        var japaneseGroups: [String] = []
        for segment in segments {
            var current: [String] = []
            var currentIsJapanese: Bool?
            func flush() {
                guard let isJapanese = currentIsJapanese, !current.isEmpty else { return }
                let text = current.joined(separator: " ")
                if isJapanese { japaneseGroups.append(text) } else { latinGroups.append(text) }
                current = []
            }
            for word in segment.split(whereSeparator: { $0.isWhitespace || $0 == "\u{3000}" }).map(String.init) {
                let wordIsJapanese = containsJapanese(word)
                if currentIsJapanese != wordIsJapanese { flush() }
                currentIsJapanese = wordIsJapanese
                current.append(word)
            }
            flush()
        }

        let readableLatin = latinGroups.filter { hasLatinLetters($0) && $0.filter(\.isLetter).count >= 2 }
        if !japaneseGroups.isEmpty, let latin = readableLatin.max(by: { $0.count < $1.count }) {
            return latin
        }
        if let kanaReading = japaneseGroups.first(where: { !$0.unicodeScalars.contains(where: isKanji) }),
           japaneseGroups.count > 1 {
            return kanaReading
        }
        return japaneseGroups.first ?? name
    }

    private static func tidied(_ name: String) -> String {
        name
            .replacingOccurrences(of: #"[\(\[（【「『]\s*[\)\]）】」』]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|:/,.·・~")))
    }

    // MARK: Romanization

    /// Romanizes a Japanese-script name on the device. Kana converts exactly;
    /// kanji use the system's Japanese reading, which can differ from how a
    /// person's name is actually read, so the online lookup replaces these
    /// with official English spellings when it can.
    static func romanized(_ text: String) -> String {
        var words: [String] = []
        for word in text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{3000}" }).map(String.init) {
            if !containsJapanese(word) {
                words.append(word)
            } else if !word.unicodeScalars.contains(where: isKanji) {
                words.append(capitalized(kanaToLatin(word)))
            } else {
                words.append(contentsOf: kanjiReadings(word).map(capitalized))
            }
        }
        return words.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func kanaToLatin(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return plain.replacingOccurrences(of: "~", with: "").replacingOccurrences(of: "'", with: "")
    }

    /// Reads kanji with the system's Japanese tokenizer. Consecutive
    /// single-character pieces are joined, since a given name like "玄師" is
    /// one word even when read character by character.
    private static func kanjiReadings(_ text: String) -> [String] {
        let nsText = text as NSString
        guard let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: nsText.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale
        ) else { return [kanaToLatin(text)] }

        var pieces: [(reading: String, sourceLength: Int)] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let source = nsText.substring(with: NSRange(location: range.location, length: range.length))
            let reading: String
            if !containsJapanese(source) {
                reading = source
            } else if !source.unicodeScalars.contains(where: isKanji) {
                reading = kanaToLatin(source)
            } else if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String {
                reading = kanaToLatin(latin)
            } else {
                reading = kanaToLatin(source)
            }
            pieces.append((reading.replacingOccurrences(of: " ", with: ""), range.length))
        }

        var words: [String] = []
        var previousWasSingle = false
        for piece in pieces where !piece.reading.isEmpty {
            let isSingle = piece.sourceLength == 1
            if isSingle && previousWasSingle, let last = words.popLast() {
                words.append(last + piece.reading)
            } else {
                words.append(piece.reading)
            }
            previousWasSingle = isSingle
        }
        return words
    }

    private static func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }
}
