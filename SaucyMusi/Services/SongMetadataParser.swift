import AVFoundation
import Foundation

/// Identifies a song's artist using a layered strategy, most trustworthy source
/// first:
///   1. A manual edit the person made in Song Info (handled by `AudioManager`).
///   2. The artist embedded in the audio file's own metadata (ID3 `TPE1`,
///      M4A `©ART`, etc.), when the source provided one.
///   3. A parse of the "Artist - Title" convention that YouTube uploads (and
///      most other audio sources) use for their titles.
///   4. "Unknown Artist", when nothing above found a match.
enum SongMetadataParser {
    /// Separators conventionally placed between an artist and a track title,
    /// tried in order. Dashes are checked first since they're the most common
    /// and least ambiguous; a colon is deliberately excluded because it shows
    /// up inside ordinary titles too often ("Song Title: Extended Mix").
    private static let artistTitleSeparators = [" - ", " – ", " — ", " | "]

    /// Bracketed uploader noise like "(Official Video)" or "[HQ Audio]" that
    /// should be stripped before the title is parsed or displayed.
    private static let noiseAnnotationPattern =
        #"[\(\[【（][^)\]】）]*(\b(official|video|audio|lyrics?|visualizer|music\s*video|mv|pv|hd|hq|4k|explicit|clean|remaster\w*|full\s*album|prod\.?)\b|公式|歌詞)[^)\]】）]*[\)\]】）]"#

    /// Strips bracketed uploader noise and collapses the leftover whitespace.
    static func cleanedTitle(_ rawTitle: String) -> String {
        let stripped = rawTitle.replacingOccurrences(
            of: noiseAnnotationPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return stripped
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits a "Artist - Title" style name. Returns a `nil` artist when no
    /// separator is found, so callers know to fall back further.
    static func parseArtistAndTitle(from displayTitle: String) -> (artist: String?, title: String) {
        let cleaned = cleanedTitle(displayTitle)
        for separator in artistTitleSeparators {
            guard let range = cleaned.range(of: separator) else { continue }
            let artist = cleaned[cleaned.startIndex..<range.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let title = cleaned[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            // Require a plausible artist name on the left so we don't split
            // titles that merely happen to contain a dash further along.
            if artist.count >= 2, !title.isEmpty {
                return (artist, title)
            }
        }
        return (nil, cleaned)
    }

    /// Tidies a raw artist string so the same artist always groups together:
    /// drops YouTube's auto-generated "- Topic" and "VEVO" channel suffixes and
    /// keeps only the primary artist ("Ado feat. Someone" becomes "Ado").
    static func normalizedArtistName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: #"(?i)\s*[-–—]\s*topic$"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"(?i)(?<=\S)vevo$"#, with: "", options: .regularExpression)
        if let credit = name.range(of: #"(?i)\s+(feat\.?|ft\.?|featuring)\s+"#, options: .regularExpression) {
            name = String(name[..<credit.lowerBound])
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads the artist and album embedded in the audio file's own metadata
    /// (ID3 `TPE1`/`TALB`, M4A `©ART`/`©alb`, …), when the source provided them.
    static func embeddedTags(from url: URL) async -> (artist: String?, album: String?) {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return (nil, nil) }

        func value(for key: AVMetadataKey) async -> String? {
            let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: .common)
            guard let raw = try? await items.first?.load(.stringValue) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return (await value(for: .commonKeyArtist), await value(for: .commonKeyAlbumName))
    }
}
