import Foundation

struct MusicPlaylist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var songs: [String]
    let dateCreated: Date

    init(id: UUID = UUID(), name: String, songs: [String] = [], dateCreated: Date = .now) {
        self.id = id
        self.name = name
        self.songs = songs
        self.dateCreated = dateCreated
    }
}

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one

    var systemImage: String {
        self == .one ? "repeat.1" : "repeat"
    }

    var accessibilityLabel: String {
        switch self {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    mutating func advance() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }
}

struct PlaybackSession: Codable {
    var currentSong: String?
    var elapsedTime: Double = 0
    var playbackContext: [String] = []
    var upcomingSongs: [String] = []
    var history: [String] = []
    var isShuffleEnabled = false
    var repeatMode: RepeatMode = .off
}

/// A user-entered correction for a song's displayed title and/or artist.
/// Either field left `nil` means "keep using the automatically detected value".
struct SongEdit: Codable, Equatable {
    var title: String?
    var artist: String?
    /// A show set by hand. An empty string means "this song isn't from any
    /// show", overriding automatic detection.
    var show: String?
}

/// The outcome of the one-time online artist search for a song. A `nil`
/// artist means the song was searched but nothing confident came back, which
/// is remembered so it is never searched again.
struct OnlineArtistMatch: Codable, Equatable {
    var artist: String?
    /// Album/collection the match came from; an extra signal for show detection.
    var collection: String?
    /// The show the catalog ties this song to, if the evidence was strong enough.
    var show: String?
    /// The locally guessed (or tagged) artist this result confirmed. When set,
    /// `artist` is that same artist in the catalog's official spelling (for
    /// example 米津玄師 -> "Kenshi Yonezu"); when `nil`, `artist` was found
    /// from the title alone.
    var confirmedGuess: String?
    /// Which version of the matching rules produced this result. Results from
    /// older rules are searched once more so improvements reach existing songs.
    var version: Int?
}

/// Where a song's displayed artist came from, most trusted first.
enum ArtistSource: String {
    case manualEdit
    case fileTags
    case title
    case onlineConfirmed
    case onlineLookup
    case unknown

    var label: String {
        switch self {
        case .manualEdit: "Edited by you"
        case .fileTags: "File tags"
        case .title: "Song name"
        case .onlineConfirmed: "Song name, confirmed online"
        case .onlineLookup: "Online search"
        case .unknown: "Not found"
        }
    }
}

/// Everything derived about a song for display and grouping, cached by
/// `AudioManager` until an input (edits, tags, lookups) changes.
struct SongProfile {
    let title: String
    let artist: String
    let artistSource: ArtistSource
    let show: String?
    /// The naming pattern the artist was read from, when it came from the name.
    var guessMethod: ArtistGuess.Method? = nil

    /// Where the artist came from, for Song Info.
    var sourceDescription: String {
        guard let guessMethod, artistSource == .title || artistSource == .onlineConfirmed else {
            return artistSource.label
        }
        return "\(artistSource.label) (\(guessMethod.label))"
    }

    /// "Artist / Show" for songs from a show, or whichever of the two is known.
    var artistAndShow: String {
        guard let show else { return artist }
        return artistSource == .unknown ? show : "\(artist) / \(show)"
    }
}

struct LibraryMetadata: Codable {
    var likedSongs: Set<String> = []
    var playlists: [MusicPlaylist] = []
    var songEdits: [String: SongEdit] = [:]
    /// One-time online search results, keyed by filename.
    var onlineLookups: [String: OnlineArtistMatch] = [:]
    /// Cache of artists read from each file's own embedded metadata, keyed by
    /// filename. An empty string means "already checked, nothing embedded" so
    /// it isn't re-read on every launch.
    var embeddedArtists: [String: String] = [:]
    /// Album names read from each file's embedded metadata (same empty-string
    /// convention); a soundtrack album name is strong evidence of a show.
    var embeddedAlbums: [String: String] = [:]

    init(
        likedSongs: Set<String> = [],
        playlists: [MusicPlaylist] = [],
        songEdits: [String: SongEdit] = [:],
        onlineLookups: [String: OnlineArtistMatch] = [:],
        embeddedArtists: [String: String] = [:],
        embeddedAlbums: [String: String] = [:]
    ) {
        self.likedSongs = likedSongs
        self.playlists = playlists
        self.songEdits = songEdits
        self.onlineLookups = onlineLookups
        self.embeddedArtists = embeddedArtists
        self.embeddedAlbums = embeddedAlbums
    }

    /// Every field is optional on disk so data saved by an older version of
    /// the app (which lacks newer fields) still loads instead of being
    /// discarded, which would wipe likes and playlists.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        likedSongs = try container.decodeIfPresent(Set<String>.self, forKey: .likedSongs) ?? []
        playlists = try container.decodeIfPresent([MusicPlaylist].self, forKey: .playlists) ?? []
        songEdits = try container.decodeIfPresent([String: SongEdit].self, forKey: .songEdits) ?? [:]
        onlineLookups = try container.decodeIfPresent([String: OnlineArtistMatch].self, forKey: .onlineLookups) ?? [:]
        embeddedArtists = try container.decodeIfPresent([String: String].self, forKey: .embeddedArtists) ?? [:]
        embeddedAlbums = try container.decodeIfPresent([String: String].self, forKey: .embeddedAlbums) ?? [:]
    }
}
