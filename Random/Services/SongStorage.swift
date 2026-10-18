import Foundation

/// Where song files live on disk.
///
/// Library songs are kept in Documents/Songs, which the Files app shows as
/// On My iPhone › saucyMusi › Songs (see `UIFileSharingEnabled` in
/// Info.plist). Songs moved to Recently Deleted go to a folder inside
/// Application Support, which the Files app can't see, so the Songs folder
/// only ever holds the library.
enum SongStorage {
    static let supportedExtensions: Set<String> = ["mp3", "m4a"]

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var songsDirectory: URL {
        existingDirectory(documentsDirectory.appendingPathComponent("Songs", isDirectory: true))
    }

    static var recentlyDeletedDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return existingDirectory(support.appendingPathComponent("Recently Deleted", isDirectory: true))
    }

    private static func existingDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func isSong(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// The names of the song files in the Songs folder.
    static func songFileNames() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: songsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return files.filter(isSong).map(\.lastPathComponent)
    }

    /// Moves audio files found loose in Documents into place: library songs
    /// into Songs, songs in Recently Deleted into the hidden folder. Older
    /// versions saved songs there, and people can drop files there in the
    /// Files app. Names are kept, so likes and playlists still match.
    static func moveLooseFiles(recentlyDeleted: Set<String>) {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(
            at: documentsDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        for file in files where isSong(file) {
            let name = file.lastPathComponent
            let folder = recentlyDeleted.contains(name) ? recentlyDeletedDirectory : songsDirectory
            let destination = folder.appendingPathComponent(availableName(name, in: folder))
            try? fileManager.moveItem(at: file, to: destination)
        }
    }

    /// A readable, safe file name: "Artist - Title.mp3", or "Title.mp3" when
    /// there's no artist. Slashes can't appear in file names, so they become
    /// a look-alike division slash ("AC∕DC").
    static func fileName(title: String, artist: String?, fileExtension: String) -> String {
        let parts = [artist, title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var base = parts.joined(separator: " - ")
            .replacingOccurrences(of: "/", with: "\u{2215}")
            .replacingOccurrences(of: "\u{0}", with: "")
            .components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.count > 150 {
            base = String(base.prefix(150)).trimmingCharacters(in: .whitespaces)
        }
        if base.isEmpty { base = "Untitled" }
        return "\(base).\(fileExtension.lowercased())"
    }

    /// `name` if it's free in `folder`, otherwise "Name (2).mp3",
    /// "Name (3).mp3"… A file named `current` (the one being renamed) doesn't
    /// count as taken, including when only the capitalization changes.
    static func availableName(_ name: String, in folder: URL, current: String? = nil) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var number = 2
        while candidate.lowercased() != current?.lowercased(),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(base) (\(number)).\(ext)"
            number += 1
        }
        return candidate
    }

    /// Renames a file in `folder`, handling changes of capitalization only,
    /// which some file systems treat as the same name.
    static func rename(_ name: String, to newName: String, in folder: URL) throws {
        let fileManager = FileManager.default
        let source = folder.appendingPathComponent(name)
        let destination = folder.appendingPathComponent(newName)
        if name.lowercased() == newName.lowercased() {
            let temporary = folder.appendingPathComponent(".renaming-\(UUID().uuidString)")
            try fileManager.moveItem(at: source, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }
}
