//
//  PerformanceBenchmarks.swift
//  SaucyMusiTests
//
//  Timing and accuracy checks for the code that runs on every keystroke and
//  every new song. Each test prints a `BENCH|name|value|unit` line (collected
//  into docs/PERFORMANCE.md) and fails only on a large regression, so the
//  limits are deliberately generous.
//

import Foundation
import Testing
@testable import SaucyMusi

@Suite(.serialized)
struct PerformanceBenchmarks {

    // MARK: Harness

    /// Median wall-clock time of `runs` executions, after one warm-up run.
    private func median(runs: Int = 15, _ body: () -> Void) -> Duration {
        body()
        let clock = ContinuousClock()
        let samples = (0..<runs).map { _ in clock.measure(body) }.sorted()
        return samples[samples.count / 2]
    }

    private func report(_ name: String, _ value: Double, _ unit: String) {
        emit("BENCH|\(name)|\(String(format: "%.3f", value))|\(unit)")
    }

    /// Prints a result line and, when `BENCH_OUTPUT` names a file (pass it as
    /// `TEST_RUNNER_BENCH_OUTPUT=/path` to xcodebuild), appends it there too.
    private func emit(_ line: String) {
        print(line)
        guard let path = ProcessInfo.processInfo.environment["BENCH_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: path)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    /// A deterministic library of `count` songs built from real artist names
    /// and title words, shaped like `[title, artist, show]` as the Library
    /// search sees them.
    private func syntheticLibrary(count: Int) -> [[String]] {
        let artists = Array(Set(YouTubeTitleFixtures.all.map(\.expectedArtist))).sorted()
        let words = ["Midnight", "Lucky", "Dreams", "Fishes", "Summer", "Lights", "Money", "Trees",
                     "Feather", "Idol", "Gurenge", "Kick", "Back", "Rolling", "Deep", "Super",
                     "Shy", "Weird", "Pink", "White", "Cruel", "Passion", "Fruit", "Despechá"]
        let shows = ["", "", "", "One Piece", "Naruto", "Attack on Titan"]
        return (0..<count).map { index in
            let title = "\(words[index % words.count]) \(words[(index / 7) % words.count]) \(index)"
            return [title, artists[index % artists.count], shows[index % shows.count]]
        }
    }

    // MARK: Library search

    /// One Library search keystroke filters every song, so this times a full
    /// pass at several library sizes with typical, typo'd and no-hit queries.
    @Test func librarySearchScalesWithLibrarySize() {
        let queries = ["frank", "kendrik lamar", "onepiece", "weird fishs", "zzzz"]
        var worstAtLargest = Duration.zero

        for size in [100, 500, 1_000, 5_000] {
            let library = syntheticLibrary(count: size)
            let perQuery = queries.map { query in
                median(runs: size >= 5_000 ? 7 : 15) {
                    _ = library.filter { SearchMatcher.matches(query, in: $0) }
                }
            }
            let average = perQuery.map(milliseconds).reduce(0, +) / Double(perQuery.count)
            report("library_search_\(size)_avg", average, "ms")
            report("library_search_\(size)_worst", milliseconds(perQuery.max()!), "ms")
            worstAtLargest = perQuery.max()!
        }

        #expect(worstAtLargest < .milliseconds(500))
    }

    @Test func matchKeyNormalizationThroughput() {
        let titles = YouTubeTitleFixtures.all.map(\.rawTitle)
        let elapsed = median(runs: 9) {
            for _ in 0..<10 { for title in titles { _ = AppDesign.songMatchKey(for: title) } }
        }
        let perTitle = milliseconds(elapsed) * 1_000 / Double(titles.count * 10)
        report("match_key_per_title", perTitle, "µs")
        #expect(perTitle < 2_000)
    }

    // MARK: Artist detection

    @Test func offlineArtistGuessThroughput() {
        let titles = YouTubeTitleFixtures.all.map(\.rawTitle)
        let elapsed = median(runs: 9) {
            for title in titles { _ = ArtistGuesser.bestOfflineGuess(for: title) }
        }
        let perTitle = milliseconds(elapsed) * 1_000 / Double(titles.count)
        report("artist_guess_per_title", perTitle, "µs")
        #expect(perTitle < 20_000)
    }

    @Test func showDetectionThroughput() {
        let titles = YouTubeTitleFixtures.all.map(\.rawTitle)
        let elapsed = median(runs: 9) {
            for title in titles { _ = ShowCatalog.show(in: title) }
        }
        let perTitle = milliseconds(elapsed) * 1_000 / Double(titles.count)
        report("show_detection_per_title", perTitle, "µs")
        #expect(perTitle < 20_000)
    }

    /// Reads the artist from 120 real YouTube titles with no network help,
    /// the same way a freshly downloaded song is labelled offline.
    @Test func offlineArtistDetectionAccuracyOnRealTitles() {
        func words(_ text: String) -> Set<String> { Set(SearchMatcher.words(text)) }

        var correct = 0, wrong = 0, noGuess = 0
        var misses: [String] = []
        for fixture in YouTubeTitleFixtures.all {
            guard let guess = ArtistGuesser.bestOfflineGuess(for: fixture.rawTitle) else {
                noGuess += 1
                misses.append("none  | \(fixture.rawTitle)")
                continue
            }
            let shown = ArtistNameFormatter.display(guess.artist)
            let expected = words(fixture.expectedArtist)
            let got = words(shown)
            if got == expected || got.isSuperset(of: expected) || (!got.isEmpty && expected.isSuperset(of: got)) {
                correct += 1
            } else {
                wrong += 1
                misses.append("wrong | \(fixture.rawTitle) -> \(shown)")
            }
        }

        let total = Double(YouTubeTitleFixtures.all.count)
        let guessed = Double(correct + wrong)
        report("artist_detection_titles", total, "titles")
        report("artist_detection_correct", Double(correct), "titles")
        report("artist_detection_wrong", Double(wrong), "titles")
        report("artist_detection_no_guess", Double(noGuess), "titles")
        report("artist_detection_accuracy", Double(correct) / total * 100, "%")
        report("artist_detection_precision", guessed > 0 ? Double(correct) / guessed * 100 : 0, "%")
        misses.forEach { emit("MISS|\($0)") }

        #expect(Double(correct) / total >= 0.6)
    }
}
