import SwiftUI

struct LibraryView: View {
    @ObservedObject var audioManager: AudioManager
    @Binding var isSearchFocused: Bool

    @State private var searchText = ""
    @State private var showsCollapsedSongCount = false
    @State private var showsCreatePlaylist = false
    @State private var playlistName = ""
    @State private var libraryScrollPosition: String?
    @FocusState private var isSearchFieldFocused: Bool

    private var songCountText: String {
        "\(audioManager.localSongs.count) \(audioManager.localSongs.count == 1 ? "song" : "songs")"
    }

    private var filteredSongs: [String] {
        guard !searchText.isEmpty else { return audioManager.localSongs }
        return audioManager.localSongs.filter {
            SearchMatcher.matches(
                searchText,
                in: [audioManager.displayTitle(for: $0), audioManager.artist(for: $0), audioManager.show(for: $0) ?? ""]
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                librarySearchBar

                List {
                    if filteredSongs.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "Your Library Is Empty",
                                systemImage: "music.note.list",
                                description: Text("Search for a song and save it to start your library.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ContentUnavailableView.search(text: searchText)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        if searchText.isEmpty {
                            Section {
                                LikedSongsLink(audioManager: audioManager)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .listSectionSpacing(4)
                        }

                        Section("Songs") {
                            ForEach(filteredSongs, id: \.self) { song in
                                LibrarySongRow(song: song, audioManager: audioManager)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollPosition(id: $libraryScrollPosition, anchor: .top)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 44
                } action: { _, isCollapsed in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsCollapsedSongCount = isCollapsed
                    }
                }
            }
            .background { AppGradientBackground() }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }

                ToolbarItem(placement: .principal) {
                    if showsCollapsedSongCount {
                        Text(songCountText)
                            .appFont(.subheadline, weight: .medium)
                            .transition(.opacity)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        guard let firstSong = audioManager.localSongs.first else { return }
                        audioManager.playSong(songName: firstSong, queue: audioManager.localSongs)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(audioManager.localSongs.isEmpty)

                    Menu {
                        Button {
                            playlistName = ""
                            showsCreatePlaylist = true
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                        }

                        Button(action: audioManager.toggleShuffleMode) {
                            Label(
                                audioManager.isShuffleMode ? "Turn Shuffle Off" : "Shuffle",
                                systemImage: "shuffle"
                            )
                        }
                        .disabled(audioManager.localSongs.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showsCreatePlaylist) {
                TextField("Playlist name", text: $playlistName)
                Button("Create") {
                    audioManager.createPlaylist(named: playlistName)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give your playlist a name. You can add songs from each song’s menu.")
            }
        }
        .onAppear(perform: audioManager.loadLocalSongs)
        .onChange(of: isSearchFocused) { _, shouldFocus in
            if shouldFocus {
                focusSearchField()
            } else {
                isSearchFieldFocused = false
            }
        }
        .onChange(of: isSearchFieldFocused) { _, isFocused in
            if isSearchFocused != isFocused {
                isSearchFocused = isFocused
            }
            if isFocused {
                revealFirstSearchResult()
            }
        }
        .onChange(of: searchText) {
            revealFirstSearchResult()
        }
    }

    private var librarySearchBar: some View {
        HStack(spacing: 10) {
            Button(action: focusSearchField) {
                Image(systemName: "magnifyingglass")
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus Library Search")

            TextField("Songs in your library", text: $searchText)
                .appFont(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier("librarySearchField")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Library Search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: focusSearchField)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(isSearchFieldFocused ? 0.55 : 0.12), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func focusSearchField() {
        isSearchFocused = true
        Task { @MainActor in
            await Task.yield()
            isSearchFieldFocused = true
            revealFirstSearchResult()
        }
    }

    private func revealFirstSearchResult() {
        Task { @MainActor in
            libraryScrollPosition = nil
            await Task.yield()
            libraryScrollPosition = filteredSongs.first
        }
    }
}

struct PlaylistsView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var showsCreatePlaylist = false
    @State private var playlistName = ""

    private var artistsSummary: String {
        let artistCount = audioManager.artists.count
        let showCount = audioManager.shows.count
        guard artistCount + showCount > 0 else { return "Browse by artist and show" }
        var parts: [String] = []
        if showCount > 0 { parts.append("\(showCount) \(showCount == 1 ? "show" : "shows")") }
        if artistCount > 0 { parts.append("\(artistCount) \(artistCount == 1 ? "artist" : "artists")") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ArtistsView(audioManager: audioManager)
                    } label: {
                        CollectionLabel(
                            title: "Artists",
                            subtitle: artistsSummary,
                            systemImage: "music.mic",
                            color: .orange
                        )
                    }
                } header: {
                    Text("Browse")
                }

                Section("Your Playlists") {
            ForEach(audioManager.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id, audioManager: audioManager)
                } label: {
                    CollectionLabel(
                        title: playlist.name,
                        subtitle: "\(playlist.songs.count) songs",
                        systemImage: "music.note.list",
                        color: .accentColor
                    )
                }
            }

            Button {
                playlistName = ""
                showsCreatePlaylist = true
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .appFont(.body, weight: .medium)
            }
                }

            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { AppGradientBackground() }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        playlistName = ""
                        showsCreatePlaylist = true
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showsCreatePlaylist) {
                TextField("Playlist name", text: $playlistName)
                Button("Create") {
                    audioManager.createPlaylist(named: playlistName)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give your playlist a name. You can add songs from each song’s menu.")
            }
        }
    }
}

/// The Liked Songs entry, shown under the Library search bar. Counts only
/// songs still in the library, so the number matches the list it opens.
struct LikedSongsLink: View {
    @ObservedObject var audioManager: AudioManager

    private var likedSongs: [String] {
        audioManager.localSongs.filter(audioManager.likedSongs.contains)
    }

    var body: some View {
        let songs = likedSongs
        NavigationLink {
            SongCollectionView(
                title: "Liked Songs",
                systemImage: "heart.fill",
                songs: songs,
                audioManager: audioManager
            )
        } label: {
            CollectionLabel(
                title: "Liked Songs",
                subtitle: "\(songs.count) \(songs.count == 1 ? "song" : "songs")",
                systemImage: "heart.fill",
                color: .pink,
                titleStyle: .title3,
                subtitleStyle: .footnote
            )
        }
    }
}

/// A "Share Song" button that opens the share sheet with the song's file.
struct ShareSongLink<Label: View>: View {
    let song: ShareableSong
    @ViewBuilder var label: Label

    var body: some View {
        ShareLink(
            item: song,
            preview: SharePreview(
                song.artist.isEmpty ? song.title : "\(song.title) — \(song.artist)",
                image: Image(systemName: "music.note")
            )
        ) {
            label
        }
    }
}

extension ShareSongLink where Label == SwiftUI.Label<Text, Image> {
    init(song: ShareableSong) {
        self.init(song: song) {
            SwiftUI.Label("Share Song", systemImage: "square.and.arrow.up")
        }
    }
}

struct CollectionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    var titleStyle: Font.TextStyle = .body
    var subtitleStyle: Font.TextStyle = .caption

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .appFont(.title3, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).appFont(titleStyle, weight: .medium)
                Text(subtitle).appFont(subtitleStyle).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct LibrarySongRow: View {
    let song: String
    @ObservedObject var audioManager: AudioManager
    var playbackContext: [String]? = nil
    @State private var showsSongInfo = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                audioManager.playSong(songName: song, queue: playbackContext)
            } label: {
                HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: audioManager.isCurrentSong(song) && audioManager.isPlaying
                          ? "waveform" : "music.note")
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(audioManager.displayTitle(for: song))
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(audioManager.isCurrentSong(song) ? "Now Playing" : audioManager.artist(for: song))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Menu {
                SongActionsMenu(song: song, audioManager: audioManager, showInfo: { showsSongInfo = true })
            } label: {
                Image(systemName: audioManager.isLiked(song) ? "heart.fill" : "ellipsis")
                    .foregroundStyle(audioManager.isLiked(song) ? Color.pink : Color.secondary)
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("More options for \(audioManager.displayTitle(for: song))")
        }
        .contextMenu {
            SongActionsMenu(song: song, audioManager: audioManager, showInfo: { showsSongInfo = true })
        }
        .swipeActions(edge: .leading) {
            Button { audioManager.toggleLiked(song) } label: {
                Label(audioManager.isLiked(song) ? "Unlike" : "Like", systemImage: "heart.fill")
            }
            .tint(.pink)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { audioManager.deleteSong(song: song) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityHint("Double-tap to play")
        .listRowBackground(Color.clear)
        .sheet(isPresented: $showsSongInfo) {
            SongInfoView(song: song, audioManager: audioManager)
        }
    }
}

private struct SongActionsMenu: View {
    let song: String
    @ObservedObject var audioManager: AudioManager
    let showInfo: () -> Void

    var body: some View {
        Button { audioManager.playNext(song) } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { audioManager.playLater(song) } label: {
            Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
        Button { audioManager.toggleLiked(song) } label: {
            Label(audioManager.isLiked(song) ? "Remove from Liked Songs" : "Like Song",
                  systemImage: audioManager.isLiked(song) ? "heart.slash" : "heart")
        }
        if !audioManager.playlists.isEmpty {
            Menu("Add to Playlist", systemImage: "music.note.list.badge.plus") {
                ForEach(audioManager.playlists) { playlist in
                    Button(playlist.name) { audioManager.add(song, to: playlist.id) }
                }
            }
        }
        if let shareable = audioManager.shareableSong(for: song) {
            ShareSongLink(song: shareable)
        }
        Button(action: showInfo) {
            Label("Song Info", systemImage: "info.circle")
        }
        Divider()
        Button(role: .destructive) { audioManager.deleteSong(song: song) } label: {
            Label {
                Text("Move to Recently Deleted")
            } icon: {
                // Menus draw icons in the app's accent tint, overriding the
                // destructive role's red, so the icon is pre-colored instead.
                Image(uiImage: Self.redTrashIcon)
            }
        }
    }

    private static let redTrashIcon: UIImage = {
        let icon = UIImage(systemName: "trash") ?? UIImage()
        return icon.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
    }()
}

struct SongCollectionView: View {
    let title: String
    let systemImage: String
    let songs: [String]
    @ObservedObject var audioManager: AudioManager
    var emptyMessage = "Use the heart button on a song to add it here."

    var body: some View {
        Group {
            if songs.isEmpty {
                ContentUnavailableView(
                    "No Songs Yet",
                    systemImage: systemImage,
                    description: Text(emptyMessage)
                )
            } else {
                List(songs, id: \.self) { song in
                    LibrarySongRow(song: song, audioManager: audioManager, playbackContext: songs)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background { AppGradientBackground() }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    guard let first = songs.first else { return }
                    audioManager.playSong(songName: first, queue: songs)
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(songs.isEmpty)
                Button {
                    guard let song = songs.randomElement() else { return }
                    audioManager.playSong(songName: song, queue: songs.shuffled())
                } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(songs.isEmpty)
            }
        }
    }
}

private struct PlaylistDetailView: View {
    let playlistID: UUID
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false

    private var playlist: MusicPlaylist? {
        audioManager.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        Group {
            if let playlist, !playlist.songs.isEmpty {
                List {
                    ForEach(playlist.songs, id: \.self) { song in
                        LibrarySongRow(song: song, audioManager: audioManager, playbackContext: playlist.songs)
                    }
                    .onDelete { audioManager.removeSongs(at: $0, from: playlistID) }
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView(
                    "Playlist Is Empty",
                    systemImage: "music.note.list",
                    description: Text("Open a song’s menu and choose Add to Playlist.")
                )
            }
        }
        .background { AppGradientBackground() }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            if let songs = playlist?.songs, !songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { audioManager.playSong(songName: songs[0], queue: songs) } label: {
                        Image(systemName: "play.fill")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmsDeletion) {
            Button("Delete Playlist", role: .destructive) {
                audioManager.deletePlaylist(id: playlistID)
                dismiss()
            }
        } message: {
            Text("The songs will remain in your library.")
        }
    }
}
