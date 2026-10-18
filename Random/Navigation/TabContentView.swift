import SwiftUI

struct TabContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab: TabModel = .library
    @State private var isLibrarySearchFocused = false
    @State private var showNowPlaying = false
    @State private var showSettings = false
    @StateObject private var audioManager = AudioManager()

    var body: some View {
        TabView(selection: $activeTab) {
            Tab(TabModel.library.title, systemImage: TabModel.library.systemImage, value: .library) {
                LibraryView(
                    audioManager: audioManager,
                    isSearchFocused: $isLibrarySearchFocused
                )
            }

            Tab(TabModel.playlists.title, systemImage: TabModel.playlists.systemImage, value: .playlists) {
                PlaylistsView(audioManager: audioManager)
            }

            Tab(TabModel.youtube.title, systemImage: TabModel.youtube.systemImage, value: .youtube) {
                YouTubeSearchView(audioManager: audioManager)
            }

            Tab(
                TabModel.search.title,
                systemImage: TabModel.search.systemImage,
                value: .search,
                role: .search
            ) {
                Color.clear
            }
        }
        .environment(\.openSettings) { showSettings = true }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background { AppGradientBackground() }
        .tabViewBottomAccessory {
            MiniPlayerView(audioManager: audioManager) {
                if audioManager.hasSelectedSong {
                    showNowPlaying = true
                }
            }
        }
        .tint(.accentColor)
        .fullScreenCover(isPresented: $showNowPlaying) {
            HomeView(audioManager: audioManager)
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(audioManager: audioManager)
                .presentationDragIndicator(.visible)
        }
        .task {
            audioManager.setupAudioSession()
            audioManager.loadLocalSongs()
            audioManager.setupRemoteTransportControls()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                audioManager.savePlaybackState()
            }
        }
        .onChange(of: activeTab) { _, newTab in
            if newTab == .search {
                openLibrarySearch()
            } else if newTab != .library {
                isLibrarySearchFocused = false
            }
        }
    }

    private func openLibrarySearch() {
        isLibrarySearchFocused = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeTab = .library
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard activeTab == .library else { return }
            isLibrarySearchFocused = true
        }
    }
}
