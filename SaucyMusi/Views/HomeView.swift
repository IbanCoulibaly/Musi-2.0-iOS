import AVKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQueue = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @State private var availableWidth: CGFloat = 390
    @State private var availableHeight: CGFloat = 844
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    private var isSongInLibrary: Bool {
        audioManager.isSongInLibrary(audioManager.videoTitle)
    }

    private var queueSongs: [String] {
        audioManager.upcomingSongs
    }

    private var canSaveSong: Bool {
        audioManager.audioURL != nil && !isSongInLibrary && !audioManager.hasJustSaved
    }

    private var playerContentWidth: CGFloat {
        min(max(0, availableWidth - 48), 620)
    }

    private var artworkWidth: CGFloat {
        min(playerContentWidth, 430, max(190, availableHeight - 440))
    }

    var body: some View {
        ZStack {
            playerBackground

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 12)

                ArtworkView(cornerRadius: 20)
                    .frame(width: artworkWidth, height: artworkWidth)
                    .shadow(color: .black.opacity(0.32), radius: 28, y: 18)

                Spacer(minLength: 20)
                trackInformation
                Spacer(minLength: 12)
                playbackProgress
                Spacer(minLength: 10)
                playbackControls
            }
            .padding(.top, 6)
            .padding(.bottom, 44)
            .frame(width: playerContentWidth)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .containerRelativeFrame([.horizontal, .vertical])
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { size in
            availableWidth = size.width
            availableHeight = size.height
        }
        .ignoresSafeArea(edges: .bottom)
        .shadow(
            color: .black.opacity(dragOffset > 0 ? 0.22 : 0),
            radius: 20,
            y: 8
        )
        .offset(y: dragOffset)
        .simultaneousGesture(dismissalGesture)
        .sheet(isPresented: $showQueue) {
            QueueView(audioManager: audioManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var playerBackground: some View {
        AppGradientBackground()
            .ignoresSafeArea()
    }

    private var topBar: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.secondary.opacity(0.65))
                .frame(width: 76, height: 6)
                .accessibilityHidden(true)

            HStack {
                Button(action: closeNowPlaying) {
                    Image(systemName: "chevron.down")
                        .appFont(.title3, weight: .medium)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Now Playing")
                .accessibilityHint("You can also swipe down to close.")

                Spacer()

                if let song = audioManager.currentSongName,
                   let shareable = audioManager.shareableSong(for: song) {
                    ShareSongLink(song: shareable) {
                        Image(systemName: "square.and.arrow.up")
                            .appFont(.title3, weight: .medium)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share Song")
                }

                Button {
                    showQueue = true
                } label: {
                    Image(systemName: "list.bullet")
                        .appFont(.title3, weight: .medium)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Up Next Queue")
            }
        }
        .frame(height: 44)
        .contentShape(.rect)
    }

    /// Slides Now Playing off the bottom of the screen, matching the swipe.
    private func closeNowPlaying() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(.smooth(duration: 0.30)) {
            dragOffset = availableHeight + 80
        }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            dismiss()
        }
    }

    private var dismissalGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }
                let verticalDistance = value.translation.height
                guard abs(verticalDistance) > abs(value.translation.width) else { return }
                dragOffset = max(0, verticalDistance)
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let isDownwardDrag = value.translation.height > 0
                    && abs(value.translation.height) > abs(value.translation.width)
                if isDownwardDrag
                    && (value.translation.height > 90 || value.predictedEndTranslation.height > 180) {
                    closeNowPlaying()
                } else {
                    withAnimation(.smooth(duration: 0.25)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var trackInformation: some View {
        VStack(alignment: .leading, spacing: 5) {
            LoopingMarqueeText(
                text: audioManager.displayVideoTitle
            )
            .frame(height: 32)
            .contentTransition(.numericText())

            if let currentArtist = audioManager.currentArtistAndShow {
                Text(currentArtist)
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                if isSongInLibrary || audioManager.hasJustSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .appFont(.subheadline, weight: .bold)
                        .imageScale(.large)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Saved in Library")
                }

                Spacer(minLength: 0)

                if let song = audioManager.librarySong(matching: audioManager.videoTitle) {
                    Button {
                        audioManager.toggleLiked(song)
                    } label: {
                        Label(
                            audioManager.isLiked(song) ? "Liked" : "Like",
                            systemImage: audioManager.isLiked(song) ? "heart.fill" : "heart"
                        )
                        .appFont(.subheadline, weight: .bold)
                        .foregroundStyle(audioManager.isLiked(song) ? Color.pink : Color.secondary)
                    }
                    .buttonStyle(.plain)
                } else if canSaveSong {
                    Button(action: saveCurrentSong) {
                        Image(systemName: "arrow.down.circle")
                            .appFont(size: 34, weight: .medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save to Library")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var playbackProgress: some View {
        VStack(spacing: 5) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : audioManager.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(1, audioManager.duration),
                onEditingChanged: { editing in
                    if editing {
                        scrubTime = audioManager.currentTime
                        isScrubbing = true
                    } else {
                        let targetTime = scrubTime
                        audioManager.seek(to: targetTime) { finished in
                            guard finished, abs(scrubTime - targetTime) < 0.01 else { return }
                            isScrubbing = false
                        }
                    }
                }
            )
            .tint(colorScheme == .dark ? .white : .accentColor)
            .accessibilityLabel("Playback Position")

            HStack {
                Text(audioManager.formattedTime(displayedPlaybackTime))
                Spacer()
                Text("−" + audioManager.formattedTime(max(0, audioManager.duration - displayedPlaybackTime)))
            }
            .appFont(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var displayedPlaybackTime: Double {
        isScrubbing ? scrubTime : audioManager.currentTime
    }

    private var playbackControls: some View {
        HStack {
            AirPlayButton(tintColor: colorScheme == .dark ? .white : .black)
                .frame(width: 40, height: 56)
                .accessibilityLabel("AirPlay")

            Spacer(minLength: 4)

            Button(action: audioManager.playPreviousSongInQueue) {
                Image(systemName: "backward.end.fill")
                    .appFont(.title2, weight: .medium)
                    .foregroundStyle(playerControlGradient)
                    .frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous Track")

            Spacer()

            Button(action: togglePlayback) {
                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .appFont(size: 28, weight: .bold)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .background(
                        colorScheme == .dark ? Color.white : Color.black.opacity(0.08),
                        in: .circle
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")

            Spacer()

            Button { audioManager.playNextSongInQueue() } label: {
                Image(systemName: "forward.end.fill")
                    .appFont(.title2, weight: .medium)
                    .foregroundStyle(playerControlGradient)
                    .frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next Track")

            Spacer(minLength: 4)

            Button(action: audioManager.toggleShuffleMode) {
                Image(systemName: "shuffle")
                    .appFont(.title3, weight: .medium)
                    .frame(width: 40, height: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(audioManager.isShuffleMode ? Color.green : Color.primary)
            .accessibilityLabel(audioManager.isShuffleMode ? "Turn Shuffle Off" : "Turn Shuffle On")
        }
    }

    private var playerControlGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color(red: 0.72, green: 0.48, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func saveCurrentSong() {
        audioManager.saveAudio()
        audioManager.hasJustSaved = true
    }

    private func togglePlayback() {
        if audioManager.player == nil {
            if let firstSong = queueSongs.first ?? audioManager.localSongs.first {
                audioManager.playSong(songName: firstSong)
            }
        } else {
            audioManager.togglePlayback()
        }
    }
}

private struct LoopingMarqueeText: View {
    let text: String

    @AppStorage(AppFont.storageKey) private var appFont = AppFont.default
    @AppStorage(AppFont.scaleStorageKey) private var fontScale = AppFont.defaultScale
    @State private var horizontalOffset: CGFloat = 0

    private var textWidth: CGFloat {
        let baseFont = appFont.uiFont(size: 22 * fontScale, weight: .bold)
        let font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: baseFont)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private var segmentWidth: CGFloat {
        textWidth + 48
    }

    private var loopDuration: Double {
        max(6, Double(segmentWidth) / 30)
    }

    private var titleLabel: some View {
        Text(text)
            .appFont(.title2, weight: .bold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if textWidth > geometry.size.width {
                    HStack(spacing: 0) {
                        titleLabel
                            .frame(width: segmentWidth, alignment: .leading)
                        titleLabel
                            .frame(width: segmentWidth, alignment: .leading)
                    }
                    .offset(x: horizontalOffset)
                    .accessibilityHidden(true)
                } else {
                    titleLabel
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .task(id: "\(text)|\(geometry.size.width)") {
                horizontalOffset = 0
                guard geometry.size.width > 0, textWidth > geometry.size.width else { return }

                while !Task.isCancelled {
                    withAnimation(.linear(duration: loopDuration)) {
                        horizontalOffset = -segmentWidth
                    }
                    try? await Task.sleep(for: .seconds(loopDuration))
                    guard !Task.isCancelled else { return }

                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        horizontalOffset = 0
                    }
                    await Task.yield()
                }
            }
        }
        .accessibilityLabel(text)
    }
}

private struct AirPlayButton: UIViewRepresentable {
    let tintColor: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = tintColor
        picker.activeTintColor = .systemGreen
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}

struct QueueView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if audioManager.upcomingSongs.isEmpty {
                    ContentUnavailableView(
                        "Queue Is Empty",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        description: Text("Add songs from your library or turn on shuffle.")
                    )
                } else {
                    List {
                        if let currentSong = audioManager.currentSongName {
                            Section("Now Playing") {
                                Text(audioManager.displayTitle(for: currentSong))
                                    .foregroundStyle(.tint)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        Section("Up Next") {
                            ForEach(audioManager.upcomingSongs, id: \.self) { song in
                                Button {
                                    audioManager.playSongFromQueue(song)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(audioManager.displayTitle(for: song))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Spacer()
                                        Image(systemName: "line.3.horizontal")
                                            .appFont(.body, weight: .medium)
                                            .foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(.rect)
                                }
                                .draggable(song)
                                .dropDestination(for: String.self) { draggedSongs, _ in
                                    guard let draggedSong = draggedSongs.first else { return false }
                                    audioManager.moveQueueSong(draggedSong, before: song)
                                    return true
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete(perform: audioManager.removeQueueSongs)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppGradientBackground() }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: audioManager.cycleRepeatMode) {
                        Label(
                            audioManager.repeatMode.accessibilityLabel,
                            systemImage: audioManager.repeatMode.systemImage
                        )
                    }
                    .tint(audioManager.repeatMode == .off ? nil : .accentColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        audioManager.clearQueue()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(audioManager.upcomingSongs.isEmpty)
                    .accessibilityLabel("Clear Queue")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
