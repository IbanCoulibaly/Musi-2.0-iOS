//
//  SaucyMusiTests.swift
//  SaucyMusiTests
//
//  Created by IBAN COULIBALY on 2/8/25.
//

import Foundation
import Testing
@testable import SaucyMusi

struct SaucyMusiTests {

    @Test func songMatchingIgnoresCapitalizationAndExtension() {
        #expect(
            AppDesign.songMatchKey(for: "The Winner Takes It All.mp3")
                == AppDesign.songMatchKey(for: "THE WINNER TAKES IT ALL")
        )
    }

    @Test func songMatchingNormalizesSpacingPunctuationAndDiacritics() {
        #expect(
            AppDesign.songMatchKey(for: "Café—Del Mar.mp3")
                == AppDesign.songMatchKey(for: "cafe del   mar")
        )
    }

    @Test func displayTitleAndMatchingSupportM4A() {
        #expect(AppDesign.displayTitle(for: "New Song.m4a") == "New Song")
        #expect(
            AppDesign.songMatchKey(for: "New Song.m4a")
                == AppDesign.songMatchKey(for: "new song.mp3")
        )
    }

    @Test func repeatModeCyclesThroughStandardStates() {
        var mode = RepeatMode.off
        mode.advance()
        #expect(mode == .all)
        mode.advance()
        #expect(mode == .one)
        mode.advance()
        #expect(mode == .off)
    }

    @Test func playbackSessionRoundTripsQueueAndHistory() throws {
        let original = PlaybackSession(
            currentSong: "Current.m4a",
            elapsedTime: 42,
            playbackContext: ["Current.m4a", "Next.m4a"],
            upcomingSongs: ["Next.m4a"],
            history: ["Previous.m4a"],
            isShuffleEnabled: true,
            repeatMode: .all
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(PlaybackSession.self, from: data)

        #expect(restored.currentSong == original.currentSong)
        #expect(restored.elapsedTime == 42)
        #expect(restored.upcomingSongs == ["Next.m4a"])
        #expect(restored.history == ["Previous.m4a"])
        #expect(restored.isShuffleEnabled)
        #expect(restored.repeatMode == .all)
    }


    // MARK: - Show detection

    @Test func showDetectionFindsShowsFromTitlesAndAbbreviations() {
        #expect(ShowCatalog.show(in: "One Piece - We Are!.mp3")?.name == "One Piece")
        #expect(ShowCatalog.show(in: "BLEACH OP 1 Asterisk")?.name == "Bleach")
        #expect(ShowCatalog.show(in: "Naruto Shippuden Opening 16 Silhouette")?.name == "Naruto")
        #expect(ShowCatalog.show(in: "Steins;Gate - Hacking to the Gate")?.name == "Steins;Gate")
        #expect(ShowCatalog.show(in: "JJK OP - Kaikai Kitan")?.name == "Jujutsu Kaisen")
    }

    @Test func showDetectionFindsShowsFromCharacterNames() {
        #expect(ShowCatalog.show(in: "Luffy Gear 5 Theme")?.name == "One Piece")
    }

    @Test func showDetectionNeedsWholeWordsAndIgnoresAccents() {
        #expect(ShowCatalog.show(in: "Ade - Sao Paulo") == nil)
        #expect(ShowCatalog.show(in: "Sunbleached Summer") == nil)
        #expect(ShowCatalog.show(in: "Daft Punk - One More Time") == nil)
    }

    @Test func showLabelsAreNeverTreatedAsArtists() {
        #expect(ShowCatalog.isShowLabel("One Piece"))
        #expect(ShowCatalog.isShowLabel("BLEACH OP 1"))
        #expect(ShowCatalog.isShowLabel("Naruto Shippuden Ending"))
        #expect(!ShowCatalog.isShowLabel("Hiroshi Kitadani"))
        #expect(!ShowCatalog.isShowLabel("Orange Range"))
    }

    @Test func showTermsAreStrippedFromSearchTitles() {
        #expect(ShowCatalog.strippingShowTerms(from: "Bleach OP 1 Asterisk") == "asterisk")
        #expect(ShowCatalog.strippingShowTerms(from: "One Piece - We Are!") == "we are")
    }

    // MARK: - Artist names

    @Test func artistNamesDropChannelSuffixesAndFeaturedCredits() {
        #expect(SongMetadataParser.normalizedArtistName("Ado - Topic") == "Ado")
        #expect(SongMetadataParser.normalizedArtistName("DaftPunkVEVO") == "DaftPunk")
        #expect(SongMetadataParser.normalizedArtistName("Ado feat. Someone") == "Ado")
        #expect(SongMetadataParser.normalizedArtistName("Ado ft Someone") == "Ado")
        #expect(SongMetadataParser.normalizedArtistName("Simon & Garfunkel") == "Simon & Garfunkel")
    }

    @Test func nameParsingStripsNoiseAndSplitsArtistFromTitle() {
        let parsed = SongMetadataParser.parseArtistAndTitle(from: "Daft Punk - One More Time (Official Video)")
        #expect(parsed.artist == "Daft Punk")
        #expect(parsed.title == "One More Time")
        #expect(SongMetadataParser.parseArtistAndTitle(from: "Some Random Track").artist == nil)
    }

    // MARK: - Online lookup matching (using real iTunes Search responses)

    private typealias Item = OnlineArtistLookup.SearchResponse.Item

    private func item(_ track: String, _ artist: String, _ collection: String) -> Item {
        Item(trackName: track, artistName: artist, collectionName: collection)
    }

    @Test func onlineMatchPicksOriginalArtistForPlainTitles() {
        let results = [
            item("One More Time", "Daft Punk", "Discovery"),
            item("One More Time (Short Radio Edit)", "Daft Punk", "Musique, Vol. 1 (1993-2005)"),
            item("One More Time (12 Mix)", "Daft Punk", "One More Time - Single"),
        ]
        let match = OnlineArtistLookup.bestMatch(queryTitle: "one more time", show: nil, results: results)
        #expect(match.artist == "Daft Punk")
    }

    @Test func onlineMatchSkipsCoversAndPicksTheOriginalAnimeArtist() {
        let show = ShowCatalog.show(in: "One Piece")
        let results = [
            item("We Are!", "Kitadani Hiroshi", "We Are! (ONE PIECE Opening Theme) - Single"),
            item("We Are (From \"One Piece\") [Full English Cover]", "CyYu", "We Are (From \"One Piece\") [Full English Cover] - Single"),
            item("We Are! (From \"One Piece\")", "Geek Music", "We Are! (From \"One Piece\") - Single"),
            item("We Are (One Piece)", "Miura Jam", "We Are (One Piece) - Single"),
        ]
        let match = OnlineArtistLookup.bestMatch(queryTitle: "we are", show: show, results: results)
        #expect(match.artist == "Kitadani Hiroshi")
    }

    @Test func onlineMatchAcceptsOneWordTitlesOnlyWhenTheShowCorroboratesThem() {
        let results = [
            item("* -Asterisk (ep.1-25 OP)", "Mu-ray & Reiko Nakanishi",
                 "Netsuretsu! Anison Spirits the Best - Cover Music Selection - TV Anime Series \"Bleach\", Vol. 1"),
            item("*Asterisk", "Orange Range", "ALL the SINGLES"),
            item("*Asterisk", "Orange Range", "* Asterisk - EP"),
        ]
        let bleach = ShowCatalog.show(in: "Bleach")
        #expect(OnlineArtistLookup.bestMatch(queryTitle: "asterisk", show: bleach, results: results).artist == "Orange Range")
        #expect(OnlineArtistLookup.bestMatch(queryTitle: "asterisk", show: nil, results: results).artist == nil)
    }

    @Test func onlineMatchRejectsUnrelatedResults() {
        let results = [item("Completely Different Song", "Someone", "Album")]
        let match = OnlineArtistLookup.bestMatch(queryTitle: "some random track", show: nil, results: results)
        #expect(match.artist == nil)
    }

    @Test func onlineLookupResultsRoundTripThroughLibraryMetadata() throws {
        var metadata = LibraryMetadata()
        metadata.onlineLookups["A.mp3"] = OnlineArtistMatch(artist: "Orange Range", collection: "* Asterisk - EP")
        metadata.onlineLookups["B.mp3"] = OnlineArtistMatch(artist: nil, collection: nil)
        let restored = try JSONDecoder().decode(LibraryMetadata.self, from: JSONEncoder().encode(metadata))
        #expect(restored.onlineLookups["A.mp3"]?.artist == "Orange Range")
        #expect(restored.onlineLookups["B.mp3"] != nil)
    }

    @Test func oldLibraryMetadataWithoutNewFieldsStillDecodes() throws {
        let legacy = #"{"likedSongs":["A.mp3"],"playlists":[]}"#.data(using: .utf8)!
        let restored = try JSONDecoder().decode(LibraryMetadata.self, from: legacy)
        #expect(restored.likedSongs == ["A.mp3"])
        #expect(restored.onlineLookups.isEmpty)
    }

    // MARK: - Show detection robustness

    @Test func showDetectionToleratesRomanizationAndRunTogetherNames() {
        #expect(ShowCatalog.show(in: "Naruto Shippuuden OP 16")?.name == "Naruto")
        #expect(ShowCatalog.show(in: "Shingeki no Kyoujin - Guren no Yumiya")?.name == "Attack on Titan")
        #expect(ShowCatalog.show(in: "#attackontitan opening")?.name == "Attack on Titan")
        #expect(ShowCatalog.show(in: "Haikyuu!! OP 1 Imagination")?.name == "Haikyuu!!")
        #expect(ShowCatalog.show(in: "My-Hero-Academia Peace Sign")?.name == "My Hero Academia")
    }

    @Test func commonWordsNoLongerTriggerShows() {
        #expect(ShowCatalog.show(in: "Ichigo Milk") == nil)
        #expect(ShowCatalog.show(in: "Akatsuki no Kuruma") == nil)
        #expect(ShowCatalog.show(in: "Love is War") == nil)
        #expect(ShowCatalog.show(in: "Saitama Love Song") == nil)
    }

    @Test func showLabelsWithSoundtrackWordsAreRecognized() {
        #expect(ShowCatalog.isShowLabel("Naruto Soundtrack"))
        #expect(ShowCatalog.isShowLabel("One Piece Original Soundtrack"))
    }

    @Test func typedShowNamesUseTheCatalogSpelling() {
        #expect(ShowCatalog.canonicalName(for: "one piece") == "One Piece")
        #expect(ShowCatalog.canonicalName(for: "  jjk ") == "Jujutsu Kaisen")
        #expect(ShowCatalog.canonicalName(for: "My Custom Show") == "My Custom Show")
    }

    @Test func showSearchTermsIncludeAliases() {
        let terms = ShowCatalog.searchTerms(forShowNamed: "Jujutsu Kaisen")
        #expect(terms.contains("JJK"))
        #expect(ShowCatalog.searchTerms(forShowNamed: "Custom") == ["Custom"])
    }

    // MARK: - Online show evidence (real iTunes Search responses)

    @Test func onlineShowMatchUsesCompilationsForKnownArtists() {
        let results = [
            item("* -Asterisk (ep.1-25 OP)", "Mu-ray & Reiko Nakanishi",
                 "Netsuretsu! Anison Spirits the Best - Cover Music Selection - TV Anime Series \"Bleach\", Vol. 1"),
            item("*Asterisk", "Orange Range", "ALL the SINGLES"),
            item("Asterisk     (Opening Theme \"Bleach Series 1\")", "Anime Kei", "Soul Reapers - Themes from Bleach (Themes from Bleach)"),
            item("*Asterisk", "Orange Range", "* Asterisk - EP"),
            item("* -Asterisk (ep.1-25 OP)", "Mu-ray & Reiko Nakanishi",
                 "Netsuretsu! Anison Spirits the Best - Cover Music Selection - TV Anime Series \"Bleach\", Vol. 6"),
        ]
        let show = OnlineArtistLookup.showMatch(queryTitle: "asterisk", artist: "Orange Range", results: results)
        #expect(show?.name == "Bleach")
    }

    @Test func onlineShowMatchNeedsMoreEvidenceForOneWordTitles() {
        let results = [
            item("Memories", "Maroon 5", "Memories - Single"),
            item("Memories (One Piece)", "Some Cover Band", "Anime Covers"),
            item("Memories", "Another Artist", "One Piece Ending Collection"),
        ]
        #expect(OnlineArtistLookup.showMatch(queryTitle: "memories", artist: "Maroon 5", results: results) == nil)
    }

    @Test func onlineShowMatchRefusesTies() {
        let results = [
            item("Hero Song", "A", "Naruto Collection"),
            item("Hero Song", "B", "Bleach Collection"),
        ]
        #expect(OnlineArtistLookup.showMatch(queryTitle: "hero song", artist: nil, results: results) == nil)
    }

    @Test func onlineShowMatchIgnoresCharacterNamesInCatalogText() {
        let results = [
            item("Night Drive", "A", "Saitama Super Arena Live"),
            item("Night Drive", "B", "Live at Konoha Hall Goku"),
        ]
        #expect(OnlineArtistLookup.showMatch(queryTitle: "night drive", artist: nil, results: results) == nil)
    }

    @Test func onlineLookupVersionRoundTrips() throws {
        let match = OnlineArtistMatch(artist: nil, collection: nil, show: "Bleach", version: OnlineArtistLookup.currentVersion)
        let restored = try JSONDecoder().decode(OnlineArtistMatch.self, from: JSONEncoder().encode(match))
        #expect(restored == match)
        let legacy = try JSONDecoder().decode(OnlineArtistMatch.self, from: #"{"artist":"X"}"#.data(using: .utf8)!)
        #expect(legacy.version == nil)
    }

    // MARK: - Artist / Show labels

    @Test func artistAndShowLabel() {
        #expect(SongProfile(title: "T", artist: "Orange Range", artistSource: .title, show: "Bleach").artistAndShow
            == "Orange Range / Bleach")
        #expect(SongProfile(title: "T", artist: "Unknown Artist", artistSource: .unknown, show: "Bleach").artistAndShow
            == "Bleach")
        #expect(SongProfile(title: "T", artist: "Daft Punk", artistSource: .title, show: nil).artistAndShow
            == "Daft Punk")
    }

    // MARK: - Search

    @Test func searchMatchesWordStartsInAnyOrder() {
        #expect(SearchMatcher.matches("hiro kita", in: ["Kitadani Hiroshi"]))
        #expect(SearchMatcher.matches("KITADANI", in: ["Kitadani Hiroshi"]))
        #expect(!SearchMatcher.matches("hiro zzz", in: ["Kitadani Hiroshi"]))
    }

    @Test func searchIgnoresSpacingAccentsAndPunctuation() {
        #expect(SearchMatcher.matches("onepiece", in: ["One Piece"]))
        #expect(SearchMatcher.matches("pokemon", in: ["Pokémon"]))
        #expect(SearchMatcher.matches("steins gate", in: ["Steins;Gate"]))
    }

    @Test func searchToleratesOneTypoInLongerWords() {
        #expect(SearchMatcher.matches("kitadanni", in: ["Kitadani Hiroshi"]))
        #expect(SearchMatcher.matches("orage range", in: ["Orange Range"]))
        #expect(!SearchMatcher.matches("xyz", in: ["Ado"]))
        // Short words must match exactly, or "ado" would find "Ado", "Adi", "Odo"...
        #expect(!SearchMatcher.matches("adi", in: ["Ado"]))
    }

    @Test func oneEditDistance() {
        #expect(SearchMatcher.isWithinOneEdit("naruto", "naruto"))
        #expect(SearchMatcher.isWithinOneEdit("narto", "naruto"))
        #expect(SearchMatcher.isWithinOneEdit("narutoo", "naruto"))
        #expect(SearchMatcher.isWithinOneEdit("nbruto", "naruto"))
        #expect(!SearchMatcher.isWithinOneEdit("nrto", "naruto"))
    }

    @Test func weakShowEvidenceIsConfirmedByArtistAndShowSearch() {
        let titleSearch = [
            item("Silhouette", "KANA-BOON", "TIME"),
            item("Silhouette (from \"Naruto Shippuden\")", "AmaLee", "Nostalgia V"),
            item("Silhouette", "Aquilo", "Silhouettes"),
            item("Silhouette (From \"Naruto Shippuden\")", "Raon & PelleK", "Anime Favorites"),
        ]
        let evidence = OnlineArtistLookup.showEvidence(queryTitle: "silhouette", artist: "KANA-BOON", results: titleSearch)
        #expect(evidence?.show.name == "Naruto")
        #expect(evidence?.isConclusive == false)

        let kanaBoonNaruto = [
            item("Silhouette", "KANA-BOON", "Silhouette - Single"),
            item("Diver", "KANA-BOON", "Diver - Single"),
        ]
        #expect(OnlineArtistLookup.confirmsShow(queryTitle: "silhouette", artist: "KANA-BOON", results: kanaBoonNaruto))

        let maroon5OnePiece = [
            item("Sugar", "Maroon 5", "V (Deluxe)"),
            item("Payphone (feat. Wiz Khalifa)", "Maroon 5", "Overexposed (Deluxe Version)"),
            item("One More Night", "Maroon 5", "Overexposed (Deluxe Version)"),
            item("Memories", "Maroon 5", "JORDI"),
        ]
        #expect(!OnlineArtistLookup.confirmsShow(queryTitle: "memories", artist: "Maroon 5", results: maroon5OnePiece))
    }

    // MARK: - Artist name cleanup

    @Test func artistNamesLoseShowNamesAndOpeningNumbers() {
        #expect(ArtistNameFormatter.clean("Naruto Shippuden OP 16 KANA-BOON") == "KANA-BOON")
        #expect(ArtistNameFormatter.clean("One Piece Opening 1 Hiroshi Kitadani") == "Hiroshi Kitadani")
        #expect(ArtistNameFormatter.clean("KANA-BOON (Naruto OP 16)") == "KANA-BOON")
        #expect(ArtistNameFormatter.clean("Opening 16") == nil)
        #expect(ArtistNameFormatter.clean("Bleach OP 1") == nil)
    }

    @Test func artistCleanupLeavesOrdinaryNamesAlone() {
        #expect(ArtistNameFormatter.clean("The Weeknd") == "The Weeknd")
        #expect(ArtistNameFormatter.clean("Part Time Lover Band") == "Part Time Lover Band")
        #expect(ArtistNameFormatter.clean("Simon & Garfunkel") == "Simon & Garfunkel")
    }

    @Test func artistNamesDropChannelWordsAndVoiceCredits() {
        #expect(ArtistNameFormatter.clean("YOASOBI Official") == "YOASOBI")
        #expect(ArtistNameFormatter.clean("Ado - Topic") == "Ado")
        #expect(ArtistNameFormatter.clean("竈門炭治郎(CV:花江夏樹)") == "竈門炭治郎")
    }

    @Test func mixedScriptNamesKeepOnlyTheEnglishPart() {
        #expect(ArtistNameFormatter.clean("LiSA（織部里沙）") == "LiSA")
        #expect(ArtistNameFormatter.clean("米津玄師 Kenshi Yonezu") == "Kenshi Yonezu")
        #expect(ArtistNameFormatter.clean("北谷洋 / Hiroshi Kitadani") == "Hiroshi Kitadani")
    }

    @Test func japaneseNamesAreRomanized() {
        #expect(ArtistNameFormatter.display("いきものがかり") == "Ikimonogakari")
        #expect(ArtistNameFormatter.display("ヨルシカ") == "Yorushika")
        let utada = ArtistNameFormatter.display("宇多田ヒカル")
        #expect(!ArtistNameFormatter.containsJapanese(utada))
        #expect(utada.contains("Hikaru"))
        #expect(ArtistNameFormatter.display("LiSA") == "LiSA")
    }

    // MARK: - Artist guessing (one test per naming pattern)

    private func best(_ name: String, known: [String] = []) -> ArtistGuess? {
        ArtistGuesser.guesses(for: name, knownArtists: known).first
    }

    @Test func guessKnownArtistInName() {
        let guess = best("Gurenge LiSA Live", known: ["LiSA"])
        #expect(guess?.artist == "LiSA")
        #expect(guess?.method == .knownArtist)
    }

    @Test func knownArtistTitlesAreTidied() {
        #expect(best("Blue Bird (Ikimonogakari)", known: ["Ikimonogakari"])?.title == "Blue Bird")
        #expect(best("Idol _ YOASOBI", known: ["YOASOBI"])?.title == "Idol")
        #expect(best("Naruto Shippuden OP 16 - Silhouette - KANA-BOON", known: ["KANA-BOON"])?.title == "Silhouette")
        #expect(best("KANA-BOON - Silhouette | Lyrics", known: ["KANA-BOON"])?.title == "Silhouette")
    }

    @Test func guessJapaneseBrackets() {
        let guess = best("LiSA『紅蓮華』")
        #expect(guess?.artist == "LiSA")
        #expect(guess?.title == "紅蓮華")
        #expect(guess?.confidence == .high)
    }

    @Test func guessDashSeparator() {
        let guess = best("Daft Punk - One More Time (Official Video)")
        #expect(guess?.artist == "Daft Punk")
        #expect(guess?.title == "One More Time")
    }

    @Test func guessQuotedTitle() {
        let guess = best("YOASOBI \"Idol\"")
        #expect(guess?.artist == "YOASOBI")
        #expect(guess?.title == "Idol")
    }

    @Test func guessByline() {
        #expect(best("Gurenge (Cover by Raon)")?.artist == "Raon")
        // A bare "by" is only a low-confidence guess, never shown unconfirmed.
        #expect(ArtistGuesser.bestOfflineGuess(for: "Stand by Me") == nil)
    }

    @Test func guessSlashSeparator() {
        let guess = best("Idol / YOASOBI")
        #expect(guess?.artist == "YOASOBI")
        #expect(guess?.title == "Idol")
        // How the app saves that name, since filenames can't contain "/".
        #expect(best("Idol _ YOASOBI")?.artist == "YOASOBI")
        #expect(best("紅蓮華／LiSA")?.artist == "LiSA")
        // "AC/DC" has no spaces around the slash, so it isn't split.
        #expect(best("AC/DC - Back in Black")?.artist == "AC/DC")
    }

    @Test func guessPipeSeparator() {
        let guess = best("Ikimonogakari | Blue Bird | Lyrics")
        #expect(guess?.artist == "Ikimonogakari")
        #expect(guess?.title == "Blue Bird")
    }

    @Test func guessAnimeLabelSegments() {
        let guess = best("Naruto Shippuden OP 16 - Silhouette - KANA-BOON")
        #expect(guess?.artist == "KANA-BOON")
        #expect(guess?.title == "Silhouette")
        #expect(best("Daft Punk - Around the World - Remix")?.artist == "Daft Punk")
    }

    @Test func guessBracketPrefix() {
        #expect(best("[Kitadani Hiroshi] We Are!")?.artist == "Kitadani Hiroshi")
    }

    @Test func guessColonSeparator() {
        let guess = best("Ado: Usseewa")
        #expect(guess?.artist == "Ado")
        #expect(guess?.confidence == .low)
    }

    @Test func guessTrailingParenthetical() {
        #expect(best("Blue Bird (Ikimonogakari)")?.artist == "Ikimonogakari")
        #expect(ArtistGuesser.guesses(for: "Blue Bird (Live)").isEmpty)
    }

    @Test func guessFeaturedCredit() {
        let guess = best("Stay (feat. Justin Bieber)")
        #expect(guess?.artist == "Justin Bieber")
        #expect(guess?.confidence == .low)
    }

    @Test func guessWideSpace() {
        let guess = best("米津玄師\u{3000}Lemon")
        #expect(guess?.artist == "米津玄師")
        #expect(guess?.title == "Lemon")
    }

    @Test func showLabelsAndPlainTitlesAreNeverGuessedAsArtists() {
        #expect(ArtistGuesser.guesses(for: "Some Random Track").isEmpty)
        let labels = ArtistGuesser.guesses(for: "Naruto Shippuden OP 16 - Silhouette").map(\.artist)
        #expect(!labels.contains { $0.localizedCaseInsensitiveContains("naruto") || $0.localizedCaseInsensitiveContains("opening") })
    }

    // MARK: - Online confirmation of guesses

    @Test func confirmationCorrectsJapaneseNamesToTheCatalogSpelling() {
        let guess = ArtistGuess(artist: "米津玄師", title: "Lemon", method: .wideSpace, confidence: .low)
        let results = [item("Lemon", "Kenshi Yonezu", "Lemon - Single")]
        #expect(OnlineArtistLookup.confirmation(of: guess, in: results)?.artist == "Kenshi Yonezu")
    }

    @Test func confirmationFixesCapitalization() {
        let guess = ArtistGuess(artist: "DAFT PUNK", title: "Around the World", method: .dashSeparator, confidence: .high)
        let results = [item("Around the World", "Daft Punk", "Homework")]
        #expect(OnlineArtistLookup.confirmation(of: guess, in: results)?.artist == "Daft Punk")
    }

    @Test func confirmationRejectsGuessesTheCatalogContradicts() {
        let reversed = ArtistGuess(artist: "Silhouette", title: "KANA-BOON", method: .dashSeparator, confidence: .low)
        let results = [item("Silhouette", "KANA-BOON", "TIME")]
        #expect(OnlineArtistLookup.confirmation(of: reversed, in: results) == nil)
        let cover = ArtistGuess(artist: "Raon", title: "Gurenge", method: .byline, confidence: .medium)
        #expect(OnlineArtistLookup.confirmation(of: cover, in: [item("Gurenge (Cover)", "Raon", "Covers")]) == nil)
    }

    @Test func confirmedCollaborationsKeepThePrimaryArtist() {
        #expect(OnlineArtistLookup.primaryArtist(catalogName: "Imagine Dragons & JID", guess: "Imagine Dragons") == "Imagine Dragons")
        #expect(OnlineArtistLookup.primaryArtist(catalogName: "Simon & Garfunkel", guess: "Simon & Garfunkel") == "Simon & Garfunkel")
        #expect(OnlineArtistLookup.primaryArtist(catalogName: "Daft Punk", guess: "DAFT PUNK") == "Daft Punk")
        #expect(OnlineArtistLookup.primaryArtist(catalogName: "Kenshi Yonezu", guess: "米津玄師") == "Kenshi Yonezu")
    }

    @Test func japaneseNamesUseTheArtistIndexSpelling() {
        #expect(OnlineArtistLookup.englishArtistName(in: ["Kitadani Hiroshi"]) == "Kitadani Hiroshi")
        #expect(OnlineArtistLookup.englishArtistName(in: ["Kenshi Yonezu"]) == "Kenshi Yonezu")
        // The artist index answers a song title ("紅蓮華") with unrelated
        // Chinese-character artists, which must not be taken as a spelling.
        #expect(OnlineArtistLookup.englishArtistName(in: ["红莲花", "紅蓮花"]) == nil)
        #expect(OnlineArtistLookup.englishArtistName(in: []) == nil)
    }

    // MARK: - Artist/title mix-up regressions

    @Test func knownArtistInsideAPhraseIsOnlyAWeakGuess() {
        let queen = ArtistGuesser.guesses(for: "Dancing Queen - ABBA", knownArtists: ["Queen"])
        #expect(queen.first?.artist != "Queen")
        #expect(queen.first { $0.artist == "Queen" }?.confidence == .low)

        let eve = ArtistGuesser.guesses(for: "Christmas Eve - Tatsuro Yamashita", knownArtists: ["EVE"])
        #expect(eve.first?.artist != "EVE")
        #expect(!eve.contains { $0.title == "Christmas" && $0.confidence >= .medium })
    }

    @Test func knownArtistAsAWholePartIsStrong() {
        let guess = best("Silhouette - KANA-BOON", known: ["KANA-BOON"])
        #expect(guess?.artist == "KANA-BOON")
        #expect(guess?.title == "Silhouette")
        #expect(guess?.confidence == .high)
    }

    @Test func titleFirstNamesAreRecognizedFromClues() {
        let hige = best("Pretender - Official髭男dism")
        #expect(hige?.artist == "Official髭男dism")
        #expect(hige?.title == "Pretender")

        let feat = best("Stay (feat. Justin Bieber) - The Kid LAROI")
        #expect(feat?.artist == "The Kid LAROI")

        let anime = best("We Are! (One Piece OP 1) - Hiroshi Kitadani")
        #expect(anime?.artist == "Hiroshi Kitadani")
        #expect(anime?.title == "We Are! (One Piece OP 1)")

        let channel = best("Idol - YOASOBI Official")
        #expect(channel?.artist == "YOASOBI")
        #expect(channel?.title == "Idol")

        // Without clues, the usual Artist - Title order stands.
        #expect(best("Daft Punk - One More Time")?.artist == "Daft Punk")
    }

    @Test func bothReadingsOfANameAreCheckedOnline() {
        let order = ArtistGuesser.confirmationOrder(ArtistGuesser.guesses(for: "Silhouette - KANA-BOON"))
        #expect(order.count >= 2)
        #expect(order[0].artist == "Silhouette")
        #expect(order[1].artist == "KANA-BOON")
        #expect(order[1].title == "Silhouette")
    }

    @Test func confirmationOfAReversedReadingKeepsItsOwnTitle() {
        let reversed = ArtistGuess(artist: "LiSA", title: "紅蓮華", method: .dashSeparator, confidence: .low)
        let wrong = ArtistGuess(artist: "紅蓮華", title: "LiSA", method: .dashSeparator, confidence: .high)
        let results = [item("Gurenge", "LiSA", "Gurenge - EP"), item("Gurenge", "LiSA", "LEO-NiNE")]
        #expect(OnlineArtistLookup.confirmation(of: reversed, in: results)?.artist == "LiSA")
        // "LiSA" as a title doesn't match "Gurenge", so the wrong order fails.
        #expect(OnlineArtistLookup.confirmation(of: wrong, in: results) == nil)
    }

    @Test func coverCreditsConfirmSongsWhoseOriginalIsMissing() {
        let results = [
            item("Christmas Eve (Originally Performed by \"Tatsuro Yamashita\")", "Vega Orgel", "Music Box Collection 9028"),
            item("Christmas Eve", "CHEMISTRY", "Winter of Love"),
        ]
        let right = ArtistGuess(artist: "Tatsuro Yamashita", title: "Christmas Eve", method: .dashSeparator, confidence: .low)
        let swapped = ArtistGuess(artist: "Christmas Eve", title: "Tatsuro Yamashita", method: .dashSeparator, confidence: .high)
        // The credited original artist is used, not the music-box cover's.
        #expect(OnlineArtistLookup.confirmation(of: right, in: results)?.artist == "Tatsuro Yamashita")
        #expect(OnlineArtistLookup.confirmation(of: swapped, in: results) == nil)
    }

    @Test func featuredCreditsDontBlockConfirmation() {
        let guess = ArtistGuess(artist: "The Kid LAROI", title: "Stay (feat. Justin Bieber)", method: .dashSeparator, confidence: .high)
        let results = [item("Stay", "The Kid LAROI & Justin Bieber", "F*CK LOVE 3+: OVER YOU")]
        #expect(OnlineArtistLookup.confirmation(of: guess, in: results) != nil)
    }

    @Test func originalArtistCreditsAreRead() {
        #expect(OnlineArtistLookup.originalArtistCredit(in: "Memories (Originally Performed by Maroon 5) [Karaoke]") == "Maroon 5")
        #expect(OnlineArtistLookup.originalArtistCredit(in: "Hello [Made Famous by Adele]") == "Adele")
        #expect(OnlineArtistLookup.originalArtistCredit(in: "Just a Song") == nil)
    }

    // MARK: - Song files

    @Test func songFileNamesAreArtistDashTitle() {
        #expect(SongStorage.fileName(title: "Lemon", artist: "Kenshi Yonezu", fileExtension: "MP3") == "Kenshi Yonezu - Lemon.mp3")
        #expect(SongStorage.fileName(title: "Some Random Track", artist: nil, fileExtension: "m4a") == "Some Random Track.m4a")
        #expect(SongStorage.fileName(title: "Back in Black", artist: "AC/DC", fileExtension: "mp3") == "AC\u{2215}DC - Back in Black.mp3")
        #expect(SongStorage.fileName(title: ".hidden", artist: nil, fileExtension: "mp3") == "hidden.mp3")
        #expect(SongStorage.fileName(title: "  ", artist: nil, fileExtension: "mp3") == "Untitled.mp3")
        #expect(SongStorage.fileName(title: String(repeating: "a", count: 300), artist: nil, fileExtension: "mp3").count <= 154)
    }

    @Test func songFileNamesAvoidCollisions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent("A - B.mp3").path, contents: Data())
        FileManager.default.createFile(atPath: folder.appendingPathComponent("A - B (2).mp3").path, contents: Data())

        #expect(SongStorage.availableName("New.mp3", in: folder) == "New.mp3")
        #expect(SongStorage.availableName("A - B.mp3", in: folder) == "A - B (3).mp3")
        // Renaming a file to its own name (or a capitalization change) isn't a collision.
        #expect(SongStorage.availableName("a - b.mp3", in: folder, current: "A - B.mp3") == "a - b.mp3")
    }

    @Test func songFilesCanChangeCapitalization() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appendingPathComponent("daft punk - x.mp3").path, contents: Data("x".utf8))

        try SongStorage.rename("daft punk - x.mp3", to: "Daft Punk - X.mp3", in: folder)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["Daft Punk - X.mp3"])
    }

    /// Renames a real song file through AudioManager and checks that every
    /// place referring to it by name follows the new name.
    @MainActor
    @Test func renamingASongKeepsItsLikesPlaylistsQueueAndEdits() async throws {
        let defaults = UserDefaults.standard
        let savedLookupSetting = defaults.object(forKey: AudioManager.onlineLookupEnabledKey)
        defaults.set(false, forKey: AudioManager.onlineLookupEnabledKey)
        let tag = UUID().uuidString.prefix(6)
        let first = "zz \(tag) a.mp3"
        let second = "zz \(tag) b.mp3"
        let folder = SongStorage.songsDirectory
        for name in [first, second] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
        }

        let manager = AudioManager()
        defer {
            for name in manager.localSongs where name.contains(tag) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            for playlist in manager.playlists where playlist.name.contains(tag) {
                manager.deletePlaylist(id: playlist.id)
            }
            if let savedLookupSetting {
                defaults.set(savedLookupSetting, forKey: AudioManager.onlineLookupEnabledKey)
            } else {
                defaults.removeObject(forKey: AudioManager.onlineLookupEnabledKey)
            }
        }

        manager.loadLocalSongs()
        for _ in 0..<50 where manager.embeddedAlbums[second] == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(manager.embeddedAlbums[second] != nil, "file tags were checked")

        manager.toggleLiked(second)
        let playlist = try #require(manager.createPlaylist(named: "Test \(tag)"))
        manager.add(second, to: playlist.id)
        manager.playLater(second)

        // A manual artist makes the name reliable, which triggers the rename.
        manager.updateSongDetails(for: second, title: "Renamed \(tag)", artist: "Test Artist", show: "")
        let renamed = "Test Artist - Renamed \(tag).mp3"

        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(renamed).path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(second).path))
        #expect(manager.localSongs.contains(renamed))
        #expect(!manager.localSongs.contains(second))
        #expect(manager.isLiked(renamed))
        #expect(manager.playlists.first { $0.id == playlist.id }?.songs == [renamed])
        #expect(manager.upcomingSongs.contains(renamed))
        #expect(!manager.upcomingSongs.contains(second))
        #expect(manager.displayTitle(for: renamed) == "Renamed \(tag)")
        #expect(manager.artist(for: renamed) == "Test Artist")
        #expect(manager.artistSource(for: renamed) == .manualEdit)

        // Deleting moves the file out of the Songs folder; restoring brings it back.
        manager.deleteSong(song: renamed)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(renamed).path))
        #expect(FileManager.default.fileExists(atPath: SongStorage.recentlyDeletedDirectory.appendingPathComponent(renamed).path))
        manager.restoreSong(song: renamed)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(renamed).path))
        #expect(manager.localSongs.contains(renamed))
        #expect(manager.isLiked(renamed))
    }

}
