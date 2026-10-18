import SwiftUI

/// The dedicated Artists page. Songs from popular shows are grouped under
/// their show, and every artist also has their own entry (labelled with the
/// shows they perform in). Search matches artists, shows, a show's other
/// names ("JJK"), and song titles.
struct ArtistsView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shows: [String] {
        let all = audioManager.shows
        guard !query.isEmpty else { return all }
        return all.filter { show in
            let songs = audioManager.songs(inShow: show)
            return SearchMatcher.matches(
                query,
                in: ShowCatalog.searchTerms(forShowNamed: show)
                    + audioManager.artists(inShow: show)
                    + songs.map(audioManager.displayTitle(for:))
            )
        }
    }

    private var artists: [String] {
        let all = audioManager.artists
        guard !query.isEmpty else { return all }
        return all.filter { artist in
            let songs = audioManager.songs(byArtist: artist)
            return SearchMatcher.matches(
                query,
                in: [artist]
                    + audioManager.shows(forArtist: artist)
                    + songs.map(audioManager.displayTitle(for:))
            )
        }
    }

    var body: some View {
        let shows = shows
        let artists = artists

        VStack(spacing: 0) {
            searchBar

            List {
                if audioManager.isLookingUpArtists {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Finding missing artists online…")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }

                if shows.isEmpty && artists.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(
                            "No Artists Yet",
                            systemImage: "music.mic",
                            description: Text("Save songs to your library and their artists will appear here.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    }
                }

                if !shows.isEmpty {
                    Section("Shows") {
                        ForEach(shows, id: \.self) { show in
                            let songs = audioManager.songs(inShow: show)
                            NavigationLink {
                                SongCollectionView(
                                    title: show,
                                    systemImage: "play.tv",
                                    songs: songs,
                                    audioManager: audioManager,
                                    emptyMessage: "Songs from this show will appear here."
                                )
                            } label: {
                                CollectionLabel(
                                    title: show,
                                    subtitle: Self.subtitle(count: songs.count, names: audioManager.artists(inShow: show)
                                        .filter { $0 != AudioManager.unknownArtist }),
                                    systemImage: "play.tv",
                                    color: .purple
                                )
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }

                if !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists, id: \.self) { artist in
                            let songs = audioManager.songs(byArtist: artist)
                            NavigationLink {
                                SongCollectionView(
                                    title: artist,
                                    systemImage: "music.mic",
                                    songs: songs,
                                    audioManager: audioManager,
                                    emptyMessage: "Songs by this artist will appear here."
                                )
                            } label: {
                                CollectionLabel(
                                    title: artist,
                                    subtitle: Self.subtitle(count: songs.count, names: audioManager.shows(forArtist: artist)),
                                    systemImage: "music.mic",
                                    color: .orange
                                )
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background { AppGradientBackground() }
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.large)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(.body, weight: .medium)
                .foregroundStyle(.secondary)

            TextField("Search artists, shows or songs", text: $searchText)
                .appFont(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .accessibilityIdentifier("artistSearchField")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { isSearchFocused = true }
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(isSearchFocused ? 0.55 : 0.12), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// "Bleach · 2 songs" for an artist, "Orange Range · 2 songs" for a show.
    private static func subtitle(count: Int, names: [String]) -> String {
        let songs = "\(count) \(count == 1 ? "song" : "songs")"
        return names.isEmpty ? songs : "\(names.joined(separator: ", ")) · \(songs)"
    }
}
