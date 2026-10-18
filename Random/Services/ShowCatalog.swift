import Foundation

/// A popular show whose songs should be grouped together instead of being
/// scattered across a dozen individual artists (openings, endings and OSTs are
/// usually performed by different artists each season).
struct ShowDefinition: Hashable {
    let name: String
    /// The show's title and common abbreviations. A hit is strong evidence.
    let keywords: [String]
    /// Distinctive character or theme names. A hit is weaker but still counts,
    /// so "Zoro's Theme" lands in One Piece without the title being mentioned.
    let characters: [String]

    init(_ name: String, keywords: [String], characters: [String] = []) {
        self.name = name
        self.keywords = keywords
        self.characters = characters
    }
}

/// Detects which show a song belongs to from its name, using whole-word phrase
/// matching on text folded for case, accents, width and punctuation (so
/// "Steins;Gate" and "steins gate" are the same, and "São" can't hit "sao").
enum ShowCatalog {
    static let shows: [ShowDefinition] = [
        ShowDefinition("One Piece",
                       keywords: ["One Piece", "OnePiece", "ワンピース"],
                       characters: ["Luffy", "Roronoa Zoro", "Straw Hat Pirates", "Thousand Sunny", "Binks Sake", "Gear 5"]),
        ShowDefinition("Bleach",
                       keywords: ["Bleach", "ブリーチ", "Thousand Year Blood War", "TYBW"],
                       characters: ["Kurosaki Ichigo", "Zanpakuto", "Soul Society", "Aizen", "Bankai", "Hollow Ichigo"]),
        ShowDefinition("Naruto",
                       keywords: ["Naruto", "Naruto Shippuden", "Shippuden", "Boruto", "ナルト"],
                       characters: ["Uchiha Sasuke", "Uchiha Itachi", "Hokage", "Kakashi", "Rasengan", "Sharingan", "Hidden Leaf"]),
        ShowDefinition("Dragon Ball",
                       keywords: ["Dragon Ball", "DragonBall", "DBZ", "Dragon Ball Z", "Dragon Ball Super", "Dragon Ball GT", "ドラゴンボール"],
                       characters: ["Goku", "Vegeta", "Saiyan", "Super Saiyan", "Kamehameha", "Shenron"]),
        ShowDefinition("Attack on Titan",
                       keywords: ["Attack on Titan", "Shingeki no Kyojin", "AOT", "進撃の巨人"],
                       characters: ["Eren Yeager", "Levi Ackerman", "Survey Corps", "Wall Maria"]),
        ShowDefinition("Demon Slayer",
                       keywords: ["Demon Slayer", "Kimetsu no Yaiba", "鬼滅の刃"],
                       characters: ["Tanjiro", "Nezuko", "Zenitsu", "Inosuke", "Hashira"]),
        ShowDefinition("Jujutsu Kaisen",
                       keywords: ["Jujutsu Kaisen", "Jujutsu", "JJK", "呪術廻戦"],
                       characters: ["Gojo Satoru", "Sukuna", "Itadori", "Yuji Itadori", "Cursed Energy"]),
        ShowDefinition("My Hero Academia",
                       keywords: ["My Hero Academia", "Boku no Hero Academia", "Boku no Hero", "BNHA", "MHA", "僕のヒーローアカデミア"],
                       characters: ["Deku", "All Might", "Bakugo", "Plus Ultra", "Midoriya"]),
        ShowDefinition("Hunter x Hunter",
                       keywords: ["Hunter x Hunter", "Hunter Hunter", "HxH"],
                       characters: ["Gon Freecss", "Killua", "Hisoka"]),
        ShowDefinition("Fullmetal Alchemist",
                       keywords: ["Fullmetal Alchemist", "Full Metal Alchemist", "FMAB", "Hagane no Renkinjutsushi"],
                       characters: ["Edward Elric", "Alphonse Elric"]),
        ShowDefinition("Death Note",
                       keywords: ["Death Note"],
                       characters: ["Light Yagami", "Ryuk", "Misa Amane"]),
        ShowDefinition("Chainsaw Man",
                       keywords: ["Chainsaw Man", "チェンソーマン"],
                       characters: ["Denji", "Pochita", "Makima"]),
        ShowDefinition("Spy x Family",
                       keywords: ["Spy x Family", "Spy Family", "SpyxFamily"],
                       characters: ["Anya Forger", "Loid Forger", "Yor Forger"]),
        ShowDefinition("One Punch Man",
                       keywords: ["One Punch Man", "OnePunchMan", "ワンパンマン"],
                       characters: ["Genos"]),
        ShowDefinition("Tokyo Ghoul",
                       keywords: ["Tokyo Ghoul"],
                       characters: ["Kaneki"]),
        ShowDefinition("Sword Art Online",
                       keywords: ["Sword Art Online"],
                       characters: ["Kirito", "Asuna"]),
        ShowDefinition("Fairy Tail",
                       keywords: ["Fairy Tail"],
                       characters: ["Natsu Dragneel", "Erza Scarlet"]),
        ShowDefinition("Black Clover",
                       keywords: ["Black Clover"],
                       characters: ["Magic Knights"]),
        ShowDefinition("Haikyuu!!",
                       keywords: ["Haikyuu", "Haikyu", "ハイキュー"],
                       characters: ["Karasuno", "Hinata Shoyo"]),
        ShowDefinition("Neon Genesis Evangelion",
                       keywords: ["Evangelion", "Neon Genesis"],
                       characters: ["Shinji Ikari", "Rei Ayanami", "Asuka Langley"]),
        ShowDefinition("Cowboy Bebop",
                       keywords: ["Cowboy Bebop"],
                       characters: ["Spike Spiegel", "Faye Valentine"]),
        ShowDefinition("JoJo's Bizarre Adventure",
                       keywords: ["JoJo's Bizarre Adventure", "JoJo Bizarre Adventure", "JoJo no Kimyou na Bouken", "ジョジョ"],
                       characters: ["Jotaro", "Dio Brando", "Giorno Giovanna", "Stand Proud", "Sono Chi no Sadame"]),
        ShowDefinition("Steins;Gate",
                       keywords: ["Steins;Gate", "SteinsGate"],
                       characters: ["Okabe Rintarou", "El Psy Kongroo"]),
        ShowDefinition("Code Geass",
                       keywords: ["Code Geass"],
                       characters: ["Lelouch"]),
        ShowDefinition("Re:Zero",
                       keywords: ["Re:Zero", "ReZero"],
                       characters: ["Subaru Natsuki"]),
        ShowDefinition("Mob Psycho 100",
                       keywords: ["Mob Psycho"]),
        ShowDefinition("Dr. Stone",
                       keywords: ["Dr. Stone"],
                       characters: ["Senku"]),
        ShowDefinition("Vinland Saga",
                       keywords: ["Vinland Saga"],
                       characters: ["Thorfinn"]),
        ShowDefinition("Blue Lock",
                       keywords: ["Blue Lock"],
                       characters: ["Isagi"]),
        ShowDefinition("Bocchi the Rock!",
                       keywords: ["Bocchi the Rock", "Bocchi"],
                       characters: ["Kessoku Band"]),
        ShowDefinition("Frieren",
                       keywords: ["Frieren", "Sousou no Frieren", "Frieren Beyond Journey's End"]),
        ShowDefinition("Solo Leveling",
                       keywords: ["Solo Leveling"],
                       characters: ["Sung Jin Woo"]),
        ShowDefinition("Oshi no Ko",
                       keywords: ["Oshi no Ko"]),
        ShowDefinition("Kaguya-sama",
                       keywords: ["Kaguya-sama", "Kaguya sama"]),
        ShowDefinition("Fire Force",
                       keywords: ["Fire Force", "Enen no Shouboutai"]),
        ShowDefinition("The Seven Deadly Sins",
                       keywords: ["Seven Deadly Sins", "Nanatsu no Taizai"],
                       characters: ["Meliodas"]),
        ShowDefinition("Fate",
                       keywords: ["Fate Stay Night", "Fate Zero", "Fate Grand Order", "Fate Apocrypha"]),
        ShowDefinition("Pokémon",
                       keywords: ["Pokemon"],
                       characters: ["Pikachu", "Ash Ketchum"]),
        ShowDefinition("Digimon",
                       keywords: ["Digimon"]),
        ShowDefinition("Yu-Gi-Oh!",
                       keywords: ["Yu-Gi-Oh", "YuGiOh"]),
        ShowDefinition("Sailor Moon",
                       keywords: ["Sailor Moon"]),
        ShowDefinition("Gintama",
                       keywords: ["Gintama"]),
        ShowDefinition("Dandadan",
                       keywords: ["Dandadan"]),
        ShowDefinition("Tokyo Revengers",
                       keywords: ["Tokyo Revengers"]),
        ShowDefinition("Mushoku Tensei",
                       keywords: ["Mushoku Tensei"]),
        ShowDefinition("Violet Evergarden",
                       keywords: ["Violet Evergarden"]),
        ShowDefinition("Angel Beats!",
                       keywords: ["Angel Beats"]),
        ShowDefinition("Clannad",
                       keywords: ["Clannad"]),
        ShowDefinition("Kill la Kill",
                       keywords: ["Kill la Kill"]),
        ShowDefinition("Kaiju No. 8",
                       keywords: ["Kaiju No. 8", "Kaiju No 8"]),
        ShowDefinition("Cyberpunk: Edgerunners",
                       keywords: ["Cyberpunk Edgerunners"]),
        ShowDefinition("Your Name",
                       keywords: ["Kimi no Na wa"]),
        ShowDefinition("Studio Ghibli",
                       keywords: ["Studio Ghibli", "Ghibli", "Spirited Away", "Howl's Moving Castle", "Princess Mononoke"],
                       characters: ["Totoro"]),
        ShowDefinition("Rurouni Kenshin",
                       keywords: ["Rurouni Kenshin", "Samurai X"]),
        ShowDefinition("Inuyasha",
                       keywords: ["Inuyasha"]),
        ShowDefinition("Hellsing",
                       keywords: ["Hellsing"]),
        ShowDefinition("Samurai Champloo",
                       keywords: ["Samurai Champloo"]),
        ShowDefinition("Darling in the Franxx",
                       keywords: ["Darling in the Franxx", "Franxx"],
                       characters: ["Zero Two"]),
        ShowDefinition("Gurren Lagann",
                       keywords: ["Gurren Lagann", "Tengen Toppa"]),
        ShowDefinition("Gundam",
                       keywords: ["Gundam"]),
        ShowDefinition("Macross",
                       keywords: ["Macross"]),
        ShowDefinition("Made in Abyss",
                       keywords: ["Made in Abyss"]),
        ShowDefinition("The Promised Neverland",
                       keywords: ["Promised Neverland", "Yakusoku no Neverland"]),
        ShowDefinition("KonoSuba",
                       keywords: ["KonoSuba", "Kono Subarashii"]),
        ShowDefinition("That Time I Got Reincarnated as a Slime",
                       keywords: ["Tensura", "Tensei Shitara Slime", "Reincarnated as a Slime"],
                       characters: ["Rimuru"]),
        ShowDefinition("Your Lie in April",
                       keywords: ["Your Lie in April", "Shigatsu wa Kimi no Uso"]),
        ShowDefinition("Anohana",
                       keywords: ["Anohana"]),
        ShowDefinition("Toradora!",
                       keywords: ["Toradora"]),
        ShowDefinition("Weathering with You",
                       keywords: ["Weathering with You", "Tenki no Ko"]),
        ShowDefinition("Suzume",
                       keywords: ["Suzume no Tojimari"]),
        ShowDefinition("Mashle",
                       keywords: ["Mashle"]),
        ShowDefinition("Sakamoto Days",
                       keywords: ["Sakamoto Days"]),
        ShowDefinition("Hell's Paradise",
                       keywords: ["Hell's Paradise", "Jigokuraku"]),
        ShowDefinition("The Apothecary Diaries",
                       keywords: ["Apothecary Diaries", "Kusuriya no Hitorigoto"]),
        ShowDefinition("Zom 100",
                       keywords: ["Zom 100"]),
        ShowDefinition("Beastars",
                       keywords: ["Beastars"]),
        ShowDefinition("Wind Breaker",
                       keywords: ["Wind Breaker Anime", "WIND BREAKER OP"]),
        ShowDefinition("Undead Unluck",
                       keywords: ["Undead Unluck"]),
        ShowDefinition("Avatar: The Last Airbender",
                       keywords: ["Last Airbender", "Legend of Korra"]),
        ShowDefinition("House of the Dragon",
                       keywords: ["House of the Dragon"]),
        ShowDefinition("The Mandalorian",
                       keywords: ["Mandalorian"]),
        ShowDefinition("The Walking Dead",
                       keywords: ["The Walking Dead"]),
        ShowDefinition("Money Heist",
                       keywords: ["Money Heist", "La Casa de Papel"]),
        ShowDefinition("Twin Peaks",
                       keywords: ["Twin Peaks"]),
        ShowDefinition("Westworld",
                       keywords: ["Westworld"]),
        ShowDefinition("Narcos",
                       keywords: ["Narcos"]),
        ShowDefinition("Arcane",
                       keywords: ["Arcane League of Legends", "Arcane Season"]),
        ShowDefinition("Game of Thrones",
                       keywords: ["Game of Thrones"]),
        ShowDefinition("Stranger Things",
                       keywords: ["Stranger Things"]),
        ShowDefinition("Breaking Bad",
                       keywords: ["Breaking Bad"]),
        ShowDefinition("Peaky Blinders",
                       keywords: ["Peaky Blinders"]),
        ShowDefinition("Squid Game",
                       keywords: ["Squid Game"]),
        ShowDefinition("The Witcher",
                       keywords: ["The Witcher"]),
        ShowDefinition("Rick and Morty",
                       keywords: ["Rick and Morty"]),
        ShowDefinition("The Simpsons",
                       keywords: ["The Simpsons"]),
    ]

    /// Words that only label a song's role within a show ("OP 1", "Ending",
    /// "OST"). They are ignored when deciding whether a name is *just* a show
    /// label and dropped from online search terms.
    private static let labelFillerWords: Set<String> = [
        "op", "ed", "opening", "ending", "ost", "theme", "themes", "soundtrack",
        "song", "songs", "music", "season", "part", "the", "anime", "tv", "full",
        "movie", "ova", "original", "bgm", "insert", "intro", "outro", "cour",
        "version", "ver", "and", "of", "a"
    ]

    private static let foldedFillerWords = Set(labelFillerWords.map(fold))

    private struct Phrase {
        /// Folded form used for detection (see `fold`).
        let folded: String
        /// Plain normalized form used when removing a show's name from text.
        let plain: String
        let weight: Int
        let isKeyword: Bool
        /// Latin phrases must match whole words; Japanese text has no spaces,
        /// so those match as plain substrings.
        let needsWordBoundary: Bool

        func pattern(_ text: String) -> String { needsWordBoundary ? " \(text) " : text }
        var foldedPattern: String { pattern(folded) }
        var plainPattern: String { pattern(plain) }
    }

    private struct Entry {
        let show: ShowDefinition
        let phrases: [Phrase]
    }

    private static func phrases(for texts: [String], isKeyword: Bool) -> [Phrase] {
        var result: [Phrase] = []
        for text in texts {
            let plain = normalize(text)
            guard !plain.isEmpty else { continue }
            var variants = [plain]
            // Also accept multi-word names run together, as in hashtags and
            // filenames ("#onepiece", "AttackOnTitan").
            let joined = plain.replacingOccurrences(of: " ", with: "")
            if joined != plain, joined.count >= 7 { variants.append(joined) }
            for variant in variants {
                let isLatin = variant.unicodeScalars.allSatisfy(\.isASCII)
                result.append(Phrase(
                    folded: fold(variant),
                    plain: variant,
                    weight: (isKeyword ? 1000 : 0) + variant.count,
                    isKeyword: isKeyword,
                    needsWordBoundary: isLatin
                ))
            }
        }
        return result
    }

    private static let entries: [Entry] = shows.map { show in
        Entry(
            show: show,
            phrases: phrases(for: [show.name] + show.keywords, isKeyword: true)
                + phrases(for: show.characters, isKeyword: false)
        )
    }

    private static func normalize(_ text: String) -> String {
        AppDesign.songMatchKey(for: text)
    }

    /// Folds romanization differences so "Shippuuden"/"Shippuden",
    /// "Kyoujin"/"Kyojin" and "Toukyou"/"Tokyo" compare equal. It is applied
    /// to both the show names and the text being searched, so it stays
    /// symmetric.
    private static func fold(_ normalized: String) -> String {
        normalized
            .replacingOccurrences(of: "ou", with: "o")
            .replacingOccurrences(of: #"([aeiou])\1+"#, with: "$1", options: .regularExpression)
    }

    /// The strongest phrase found in text, preferring show names over
    /// character names and longer phrases over shorter ones.
    private static func bestMatch(in text: String, keywordsOnly: Bool = false) -> (entry: Entry, phrase: Phrase)? {
        let haystack = " \(fold(normalize(text))) "
        var best: (entry: Entry, phrase: Phrase)?
        for entry in entries {
            for phrase in entry.phrases where (!keywordsOnly || phrase.isKeyword)
                && haystack.contains(phrase.foldedPattern) {
                if phrase.weight > (best?.phrase.weight ?? -1) {
                    best = (entry, phrase)
                }
            }
        }
        return best
    }

    /// The show a piece of text (a song name, an album title) belongs to.
    /// `keywordsOnly` ignores character names; used for catalog text from the
    /// internet, where a word like a character's name is weaker evidence.
    static func show(in text: String, keywordsOnly: Bool = false) -> ShowDefinition? {
        bestMatch(in: text, keywordsOnly: keywordsOnly)?.entry.show
    }

    /// The catalog's spelling of a show name someone typed ("one piece" ->
    /// "One Piece"), or the text as typed for a show that isn't in the catalog.
    static func canonicalName(for typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isShowLabel(trimmed), let show = show(in: trimmed) else { return trimmed }
        return show.name
    }

    /// Every name a show is known by, for search ("JJK" finds Jujutsu Kaisen).
    static func searchTerms(forShowNamed name: String) -> [String] {
        guard let show = shows.first(where: { $0.name == name }) else { return [name] }
        return [show.name] + show.keywords + show.characters
    }

    /// `true` when a would-be artist name is really just a show label such as
    /// "One Piece" or "Bleach OP 1", which must never be treated as an artist.
    static func isShowLabel(_ candidate: String) -> Bool {
        guard let match = bestMatch(in: candidate) else { return false }
        // Remove every term of the matched show, longest first, so
        // "Naruto Shippuden" is fully consumed rather than leaving "naruto".
        var remainderText = " \(fold(normalize(candidate))) "
        for phrase in match.entry.phrases.sorted(by: { $0.folded.count > $1.folded.count }) {
            remainderText = remainderText.replacingOccurrences(of: phrase.foldedPattern, with: " ")
        }
        let remainder = remainderText.split(separator: " ").map(String.init)
        return remainder.allSatisfy { foldedFillerWords.contains($0) || $0.allSatisfy(\.isNumber) }
    }

    /// Words that label a song's role in a show. Only removed from an artist
    /// name when a show name or an opening/ending marker is also present, so
    /// real names containing "The" or "Part" are left alone.
    private static let roleWords: Set<String> = [
        "op", "ed", "opening", "ending", "ost", "theme", "full", "tv", "size",
        "season", "cour", "part", "ver", "version", "insert", "song", "anime",
        "movie", "ova", "soundtrack", "original", "bgm", "intro", "outro", "from",
        "short", "long", "official", "series", "arc"
    ]

    private static let keywordKeys: Set<String> = Set(entries.flatMap { entry in
        entry.phrases.filter(\.isKeyword).map(\.folded)
    })

    /// Removes show names and role labels ("Naruto Shippuden OP 16") from an
    /// artist name while keeping the rest exactly as written, so
    /// "Naruto Shippuden OP 16 KANA-BOON" becomes "KANA-BOON" and
    /// "Opening 16" becomes empty.
    static func removingShowLabels(from text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{3000}" }).map(String.init)
        guard !words.isEmpty else { return text }
        let keys = words.map(normalize)

        var remove = Array(repeating: false, count: words.count)
        var foundShow = false
        var start = 0
        while start < words.count {
            var matchedLength = 0
            for length in stride(from: min(6, words.count - start), through: 1, by: -1) {
                let joined = keys[start..<(start + length)].filter { !$0.isEmpty }.joined(separator: " ")
                guard !joined.isEmpty else { continue }
                if keywordKeys.contains(fold(joined))
                    || keywordKeys.contains(fold(joined.replacingOccurrences(of: " ", with: ""))) {
                    matchedLength = length
                    break
                }
            }
            if matchedLength > 0 {
                for index in start..<(start + matchedLength) { remove[index] = true }
                foundShow = true
                start += matchedLength
            } else {
                start += 1
            }
        }

        let hasRoleMarker = text.range(
            of: #"(?i)(\b(op|ed|opening|ending|ost)\b|\b(op|ed)\d+\b|オープニング|エンディング|主題歌)"#,
            options: .regularExpression
        ) != nil
        guard foundShow || hasRoleMarker else { return text }

        for (index, key) in keys.enumerated() where !remove[index] {
            let parts = key.split(separator: " ").map(String.init)
            guard !parts.isEmpty else { continue }
            let isLabel = parts.allSatisfy { part in
                roleWords.contains(part)
                    || part.allSatisfy(\.isNumber)
                    || part.range(of: #"^(op|ed|s|season|ep)\d+$"#, options: .regularExpression) != nil
            }
            if isLabel { remove[index] = true }
        }
        let jpRole = #"(オープニング|エンディング|主題歌|挿入歌)\d*"#
        return zip(words, remove)
            .filter { !$0.1 }
            .map { $0.0.replacingOccurrences(of: jpRole, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// A song title with show names and role labels ("Bleach OP 1") removed,
    /// leaving just the words worth searching for. Uses the unfolded text so
    /// the result stays spelled the way a search engine expects.
    static func strippingShowTerms(from text: String) -> String {
        var key = " \(normalize(text)) "
        for entry in entries {
            for phrase in entry.phrases.sorted(by: { $0.plain.count > $1.plain.count }) where phrase.isKeyword {
                key = key.replacingOccurrences(of: phrase.plainPattern, with: " ")
            }
        }
        key = key.replacingOccurrences(
            of: #"\b(op|ed|opening|ending|ost)\s*\d+\b"#,
            with: " ",
            options: .regularExpression
        )
        return key.split(separator: " ")
            .map(String.init)
            .filter { !labelFillerWords.contains($0) }
            .joined(separator: " ")
    }
}
