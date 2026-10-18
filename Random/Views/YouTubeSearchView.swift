import SwiftUI

struct YouTubeSearchView: View {
    @ObservedObject var audioManager: AudioManager

    @State private var isSearching = false
    @State private var searchError: String?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                ZStack {
                    Group {
                        if let searchError {
                            ContentUnavailableView {
                                Label("Couldn’t Search", systemImage: "wifi.exclamationmark")
                            } description: {
                                Text(searchError)
                            } actions: {
                                Button("Try Again", action: submitSearch)
                                    .buttonStyle(.glassProminent)
                            }
                        } else if audioManager.videoResults.isEmpty {
                            searchWelcome
                        } else {
                            resultsList
                        }
                    }

                    if isSearching {
                        ProgressView("Searching…")
                            .appFont(.subheadline, weight: .medium)
                            .controlSize(.large)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 16)
                            .background(.regularMaterial, in: .rect(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppGradientBackground() }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(.body, weight: .medium)
                .foregroundStyle(.secondary)

            TextField("Search YouTube or paste a link", text: $audioManager.query)
                .appFont(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit(submitSearch)

            if !audioManager.query.isEmpty {
                Button {
                    audioManager.query = ""
                    isSearchFieldFocused = true
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
        .frame(height: 52)
        .background(.regularMaterial, in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(isSearchFieldFocused ? 0.55 : 0.18), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var searchWelcome: some View {
        ContentUnavailableView {
            Label("Find Your Next Song", systemImage: "sparkles")
        } description: {
            Text("Search by title or artist, or paste a YouTube link to start listening.")
        } actions: {
            if !audioManager.query.isEmpty {
                Button("Search", action: submitSearch)
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var resultsList: some View {
        List(Array(audioManager.videoResults.enumerated()), id: \.element.videoId) { index, video in
            Button {
                play(video)
            } label: {
                HStack(spacing: 14) {
                    AsyncImage(url: video.thumbnailURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "music.note")
                                .appFont(.title2, weight: .medium)
                                .foregroundStyle(.tint)
                        }
                    }
                    .frame(width: 88, height: 56)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .appFont(.body, weight: .medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Label(
                            isSaved(video) ? "In your library" : "Stream audio",
                            systemImage: isSaved(video) ? "checkmark.circle.fill" : "play.circle"
                        )
                        .appFont(.caption)
                        .foregroundStyle(isSaved(video) ? Color.green : Color.secondary)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .appFont(.caption, weight: .medium)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .id(index)
            .accessibilityHint(isSaved(video) ? "Plays the saved song" : "Streams this song")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func submitSearch() {
        let query = audioManager.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        searchError = nil
        if isWebURL(query) {
            audioManager.sendURL(query: query)
            return
        }

        isSearching = true
        searchYouTube(query: query) { results in
            audioManager.videoResults = results
            isSearching = false
            if results.isEmpty {
                searchError = "No results were returned. Check the server connection and try again."
            }
        }
    }

    private func play(_ video: YouTubeVideo) {
        if let savedSong = audioManager.librarySong(matching: video.title) {
            audioManager.playSong(songName: savedSong)
        } else if let url = URL(string: "https://www.youtube.com/watch?v=\(video.videoId)") {
            audioManager.sendURL(query: url.absoluteString)
        }
    }

    private func isSaved(_ video: YouTubeVideo) -> Bool {
        audioManager.isSongInLibrary(video.title)
    }

    private func isWebURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }
}
