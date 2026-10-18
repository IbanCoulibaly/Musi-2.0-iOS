import Foundation
import AVFoundation
import MediaPlayer
import Network
import SwiftUI

private struct AudioEndpointResponse: Decodable {
    let audioURL: URL
    let title: String

    enum CodingKeys: String, CodingKey {
        case audioURL = "audio_url"
        case title
    }
}

class AudioManager: ObservableObject {

    @Published var videoTitle: String = ""
    @Published var localSongs: [String] = []
    @Published var query: String = ""
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading: Bool = false
    @Published var audioURL: URL?
    @Published var videoResults: [YouTubeVideo] = []
    @Published var hasJustSaved: Bool = false
    @Published private(set) var isShuffleMode: Bool = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var upcomingSongs: [String] = []
    @Published private(set) var playbackHistory: [String] = []
    @Published private(set) var likedSongs: Set<String> = []
    @Published private(set) var playlists: [MusicPlaylist] = []
    @Published var recentlyDeleted: [String] = []
    @Published private(set) var songEdits: [String: SongEdit] = [:] {
        didSet { profileCache.removeAll() }
    }
    @Published private(set) var embeddedArtists: [String: String] = [:] {
        didSet { profileCache.removeAll() }
    }
    @Published private(set) var embeddedAlbums: [String: String] = [:] {
        didSet { profileCache.removeAll() }
    }
    @Published private(set) var onlineLookups: [String: OnlineArtistMatch] = [:] {
        didSet { profileCache.removeAll() }
    }
    @Published private(set) var isLookingUpArtists = false
    
    private(set) var player: AVPlayer?
    private var currentLocalSongName: String?
    private var playbackContext: [String] = []
    private var unshuffledUpcomingSongs: [String] = []
    private var restoredSession = PlaybackSession()
    private var timeObserver: Any?
    private var trackEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var durationObservation: NSKeyValueObservation?
    private var didConfigureAudioSession = false
    private var didConfigureRemoteControls = false

    private let playbackSessionKey = "playbackSession.v2"
    private let libraryMetadataKey = "libraryMetadata.v1"
    private let recentlyDeletedKey = "recentlyDeleted.v1"

    private var profileCache: [String: SongProfile] = [:] {
        didSet { if profileCache.isEmpty { knownArtistCache = nil } }
    }
    private var knownArtistCache: [String]?
    private let pathMonitor = NWPathMonitor()
    private var isOnline = false
    private var isRunningOnlineLookup = false
    static let onlineLookupEnabledKey = "onlineArtistLookup"

    private let supportedAudioExtensions: Set<String> = ["mp3", "m4a"]
    private lazy var audioDownloadSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.networkServiceType = .responsiveData
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    var hasSelectedSong: Bool {
        player != nil && !videoTitle.isEmpty && videoTitle != "Untitled"
    }

    var currentSongName: String? {
        currentLocalSongName
    }

    init() {
        restoreLibraryMetadata()
        restorePlaybackPreferences()
        recentlyDeleted = UserDefaults.standard.stringArray(forKey: recentlyDeletedKey) ?? []
        startMonitoringConnectivity()
    }

    deinit {
        pathMonitor.cancel()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    func librarySong(matching title: String) -> String? {
        let requestedKey = AppDesign.songMatchKey(for: title)
        guard !requestedKey.isEmpty else { return nil }

        return localSongs.first {
            AppDesign.songMatchKey(for: $0) == requestedKey
        }
    }

    func isSongInLibrary(_ title: String) -> Bool {
        librarySong(matching: title) != nil
    }

    func isCurrentSong(_ song: String) -> Bool {
        let currentKey = AppDesign.songMatchKey(for: videoTitle)
        return !currentKey.isEmpty && currentKey == AppDesign.songMatchKey(for: song)
    }
    
    func fetchAudioURL(
        from query: String,
        completion: @escaping (URL?, String?) -> Void
    ) {
        let savedServerURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://192.168.1.155:5000"
        guard var components = URLComponents(string: savedServerURL) else {
            print("❌ Invalid URL")
            completion(nil, nil)
            return
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "get_audio_url"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "url", value: query)]

        guard let url = components.url else {
            print("❌ Invalid URL")
            completion(nil, nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Error fetching audio URL: \(error)")
                completion(nil, nil)
                return
            }
            
            guard let data = data else {
                print("❌ No data received.")
                completion(nil, nil)
                return
            }
            
            do {
                let endpointResponse = try JSONDecoder().decode(AudioEndpointResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(
                        endpointResponse.audioURL,
                        endpointResponse.title
                    )
                }
            } catch {
                print("❌ Failed to decode response: \(error)")
                DispatchQueue.main.async {
                    completion(nil, nil)
                }
            }
        }
        task.resume()
    }
    
    func saveAudio() {
        guard let audioURL = audioURL else { return }
        
        let fileManager = FileManager.default
        let sourceExtension = audioURL.pathExtension.lowercased()
        let audioExtension = supportedAudioExtensions.contains(sourceExtension) ? sourceExtension : "m4a"
        // Saved under the video's title for now; once its artist is confirmed
        // the file is renamed to "Artist - Title" (see organizeSongFiles).
        let savedSongName = SongStorage.fileName(title: videoTitle, artist: nil, fileExtension: audioExtension)
        let destinationURL = SongStorage.songsDirectory.appendingPathComponent(savedSongName)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            loadLocalSongs()
            return
        }

        let request = URLRequest(
            url: audioURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 300
        )
        let task = audioDownloadSession.downloadTask(with: request) { localURL, _, _ in
            if let localURL = localURL {
                do {
                    try fileManager.moveItem(at: localURL, to: destinationURL)
                    DispatchQueue.main.async {
                        self.loadLocalSongs()
                        self.currentLocalSongName = savedSongName
                        self.buildQueue(startingAfter: savedSongName)
                        self.updateRemoteCommandAvailability()
                    }
                } catch {
                    print("❌ Error saving audio: \(error)")
                }
            }
        }
        task.resume()
    }
    
    func sendURL(query: String) {
        guard !query.isEmpty else {
            print("❌ Please enter a URL first")
            return
        }
        playAudio(query: query)
    }
    
    func loadLocalSongs() {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        do {
            removeLegacyDefaultNoise(from: documentsDirectory)
            SongStorage.moveLooseFiles(recentlyDeleted: Set(recentlyDeleted))
            moveDeletedSongFilesAside()
            self.localSongs = SongStorage.songFileNames()
                .filter { !recentlyDeleted.contains($0) }
                .sorted()

            reconcileLibraryMetadata()
            refreshEmbeddedTagsIfNeeded()
            organizeSongFiles()

            if player == nil {
                let savedSong = restoredSession.currentSong.flatMap { saved in
                    localSongs.first { $0 == saved }
                }
                let firstPlaylistSong = playlists
                    .flatMap(\.songs)
                    .first(where: localSongs.contains)
                if let launchSong = savedSong ?? firstPlaylistSong ?? localSongs.first {
                    prepareSong(songName: launchSong, restoreQueue: true)
                }
            }
        }
    }

    private func removeLegacyDefaultNoise(from documentsDirectory: URL) {
        let filename = "Default Noise.caf"
        let legacyURL = documentsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.removeItem(at: legacyURL)
        }

        recentlyDeleted.removeAll { $0 == filename }
        likedSongs.remove(filename)
        songEdits.removeValue(forKey: filename)
        embeddedArtists.removeValue(forKey: filename)
        embeddedAlbums.removeValue(forKey: filename)
        onlineLookups.removeValue(forKey: filename)
        for index in playlists.indices {
            playlists[index].songs.removeAll { $0 == filename }
        }
        restoredSession.currentSong = restoredSession.currentSong == filename
            ? nil : restoredSession.currentSong
        restoredSession.playbackContext.removeAll { $0 == filename }
        restoredSession.upcomingSongs.removeAll { $0 == filename }
        restoredSession.history.removeAll { $0 == filename }

        persistRecentlyDeleted()
        persistLibraryMetadata()
        if let data = try? JSONEncoder().encode(restoredSession) {
            UserDefaults.standard.set(data, forKey: playbackSessionKey)
        }
        UserDefaults.standard.removeObject(forKey: "didCreateDefaultNoise.v1")
    }
    
    func stopAudio() {
        player?.pause()
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let trackEndObserver {
            NotificationCenter.default.removeObserver(trackEndObserver)
            self.trackEndObserver = nil
        }
        durationObservation?.invalidate()
        durationObservation = nil
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        videoTitle = "Untitled"
        audioURL = nil
    }
    
    func replayAudio() {
        seek(to: 0)
        player?.play()
        isPlaying = true
        updateNowPlayingInfo(title: videoTitle)
    }
    
    func playAudio(query: String) {
        guard !query.isEmpty else {
            print("❌ Please enter a URL")
            return
        }

        isLoading = true
        setupAudioSession()

        fetchAudioURL(from: query) { [weak self] audioURL, title in
            guard let self, let audioURL else {
                print("❌ Failed to get audio URL")
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                return
            }

            self.installPlayer(
                url: audioURL,
                title: title ?? "Untitled",
                remoteAudioURL: audioURL,
                localSongName: nil,
                autoPlay: true
            )
            self.isLoading = false
        }
    }
    
    func prepareSong(songName: String, restoreQueue: Bool = false) {
        guard let songURL = localSongURL(for: songName) else { return }

        installPlayer(
            url: songURL,
            title: songName,
            remoteAudioURL: nil,
            localSongName: songName,
            autoPlay: false
        )
        if restoreQueue {
            let restoredElapsedTime = restoredSession.elapsedTime
            restoreQueueForLaunch(currentSong: songName)
            if restoredElapsedTime > 0 {
                seek(to: restoredElapsedTime)
            }
        } else {
            buildQueue(startingAfter: songName)
        }
    }

    func playSong(songName: String, queue songs: [String]? = nil) {
        guard let songURL = localSongURL(for: songName) else { return }
        installPlayer(
            url: songURL,
            title: songName,
            remoteAudioURL: nil,
            localSongName: songName,
            autoPlay: true
        )
        playbackHistory = []
        playbackContext = (songs ?? localSongs).filter(localSongs.contains)
        buildQueue(startingAfter: songName, in: playbackContext)
        persistPlaybackSession()
    }

    private func localSongURL(for songName: String) -> URL? {
        SongStorage.songsDirectory.appendingPathComponent(songName)
    }

    /// Public accessor for a saved song's file, used by the Song Info screen
    /// to read its size, dates, and audio properties.
    func songFileURL(for song: String) -> URL? {
        localSongURL(for: song)
    }
    
    func togglePlayback() {
        if let player = player {

            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            updateNowPlayingInfo(title: videoTitle)
        }
    }

    private func installPlayer(
        url: URL,
        title: String,
        remoteAudioURL: URL?,
        localSongName: String?,
        autoPlay: Bool
    ) {
        stopAudio()

        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        videoTitle = title
        audioURL = remoteAudioURL
        currentLocalSongName = localSongName
        hasJustSaved = false

        if let item = newPlayer.currentItem {
            observeDuration(of: item)
            trackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.handleTrackFinished()
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard time.seconds.isFinite else { return }
            self?.currentTime = time.seconds
        }

        if autoPlay {
            newPlayer.play()
            isPlaying = true
        }
        updateNowPlayingInfo(title: title)
        updateRemoteCommandAvailability()
    }

    func seek(to seconds: Double, completion: ((Bool) -> Void)? = nil) {
        guard let player else {
            completion?(false)
            return
        }

        let upperBound = duration.isFinite && duration > 0 ? duration : seconds
        let targetSeconds = min(max(0, seconds), upperBound)
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        player.currentItem?.cancelPendingSeeks()
        currentTime = targetSeconds
        player.seek(
            to: targetTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] finished in
            DispatchQueue.main.async {
                if finished {
                    self?.currentTime = targetSeconds
                    self?.updateNowPlayingInfo(title: self?.videoTitle ?? "Untitled")
                }
                completion?(finished)
            }
        }
    }
    
    func setupAudioSession() {
        guard !didConfigureAudioSession else { return }
        didConfigureAudioSession = true
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            
            // Add observer for audio session interruptions
            interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: audioSession, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt {
                    if type == AVAudioSession.InterruptionType.began.rawValue {
                        // Audio was interrupted (paused by external app)
                        self.isPlaying = false
                        self.updateNowPlayingInfo(title: self.videoTitle)
                    } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                        // Interruption ended
                        if let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                                // Should resume playback
                                self.player?.play()
                                self.isPlaying = true
                                self.updateNowPlayingInfo(title: self.videoTitle)
                            }
                        }
                    }
                }
            }
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable else { return }
                self?.player?.pause()
                self?.isPlaying = false
                self?.updateNowPlayingInfo(title: self?.videoTitle ?? "")
            }
        } catch {
            didConfigureAudioSession = false
            print("❌ Failed to set up audio session: \(error)")
        }
    }
    
    func setupRemoteTransportControls() {
        guard !didConfigureRemoteControls else { return }
        didConfigureRemoteControls = true
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.player?.play()
            self.isPlaying = true
            self.updateNowPlayingInfo(title: self.videoTitle)
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.player?.pause()
            self.isPlaying = false
            self.updateNowPlayingInfo(title: self.videoTitle)
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.player != nil else { return .noActionableNowPlayingItem }
            self.togglePlayback()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNextSongInQueue()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPreviousSongInQueue()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self]
            event in if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
            }
            return .success
        }

        // Keep Control Center in track-navigation mode. Enabling skip interval
        // commands makes iOS replace the previous/next arrows with 15-second buttons.
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false

        commandCenter.likeCommand.localizedTitle = "Like Song"
        commandCenter.likeCommand.addTarget { [weak self] _ in
            guard let self, let song = self.currentLocalSongName else {
                return .noActionableNowPlayingItem
            }
            self.toggleLiked(song)
            self.updateRemoteCommandAvailability()
            return .success
        }
        updateRemoteCommandAvailability()
    }
    
    func updateNowPlayingInfo(title: String) {
        let resolvedTitle = currentLocalSongName.map(displayTitle(for:)) ?? AppDesign.displayTitle(for: title)
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: resolvedTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let currentLocalSongName {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist(for: currentLocalSongName)
            if let show = show(for: currentLocalSongName) {
                nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = show
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func updateRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = player != nil
        commandCenter.previousTrackCommand.isEnabled = player != nil
        commandCenter.changePlaybackPositionCommand.isEnabled = player != nil
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = currentLocalSongName != nil
        commandCenter.likeCommand.isActive = currentLocalSongName.map(isLiked) ?? false
    }
    
    func formattedTime(_ time: Double) -> String {
        guard !time.isNaN, !time.isInfinite else { return "--:--" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func observeDuration(of item: AVPlayerItem) {
        durationObservation = item.observe(\.duration, options: [.initial, .new]) { [weak self] item, _ in
            let duration = item.duration.seconds
            guard duration.isFinite, duration > 0 else { return }

            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item else { return }
                self.duration = duration
                self.updateNowPlayingInfo(title: self.videoTitle)
            }
        }
    }
    
    func toggleShuffleMode() {
        isShuffleMode.toggle()
        if isShuffleMode {
            unshuffledUpcomingSongs = upcomingSongs
            upcomingSongs.shuffle()
        } else if !unshuffledUpcomingSongs.isEmpty {
            let stillQueued = Set(upcomingSongs)
            upcomingSongs = unshuffledUpcomingSongs.filter(stillQueued.contains)
            unshuffledUpcomingSongs = []
        }
        persistPlaybackSession()
    }

    func cycleRepeatMode() {
        repeatMode.advance()
        persistPlaybackSession()
        updateRemoteCommandAvailability()
    }

    private func handleTrackFinished() {
        if repeatMode == .one {
            replayAudio()
        } else {
            playNextSongInQueue(automatic: true)
        }
    }

    func playNextSongInQueue(automatic: Bool = false) {
        if upcomingSongs.isEmpty, repeatMode == .all {
            let context = playbackContext.isEmpty ? localSongs : playbackContext
            if isShuffleMode {
                upcomingSongs = context.filter { $0 != currentLocalSongName }.shuffled()
            } else if let currentLocalSongName,
                      let currentIndex = context.firstIndex(of: currentLocalSongName) {
                upcomingSongs = Array(context.dropFirst(currentIndex + 1))
                    + Array(context.prefix(currentIndex))
            } else {
                upcomingSongs = context
            }
        }

        guard let nextSong = upcomingSongs.first else {
            if automatic {
                player?.pause()
                isPlaying = false
                seek(to: 0)
                updateNowPlayingInfo(title: videoTitle)
            }
            updateRemoteCommandAvailability()
            return
        }

        upcomingSongs.removeFirst()
        if let currentLocalSongName {
            playbackHistory.append(currentLocalSongName)
        }
        playQueuedSong(nextSong)
    }

    func playPreviousSongInQueue() {
        if currentTime > 3 {
            replayAudio()
            return
        }
        guard let previousSong = playbackHistory.popLast() else {
            replayAudio()
            return
        }
        if let currentLocalSongName {
            upcomingSongs.insert(currentLocalSongName, at: 0)
        }
        playQueuedSong(previousSong)
    }

    func playSongFromQueue(_ song: String) {
        guard let index = upcomingSongs.firstIndex(of: song) else { return }
        let skippedSongs = Array(upcomingSongs.prefix(index))
        if let currentLocalSongName {
            playbackHistory.append(currentLocalSongName)
        }
        playbackHistory.append(contentsOf: skippedSongs)
        upcomingSongs.removeFirst(index + 1)
        playQueuedSong(song)
    }

    func playNext(_ song: String) {
        upcomingSongs.removeAll { $0 == song }
        upcomingSongs.insert(song, at: 0)
        persistPlaybackSession()
        updateRemoteCommandAvailability()
    }

    func playLater(_ song: String) {
        upcomingSongs.removeAll { $0 == song }
        upcomingSongs.append(song)
        persistPlaybackSession()
        updateRemoteCommandAvailability()
    }

    func moveQueueSongs(from offsets: IndexSet, to destination: Int) {
        upcomingSongs.move(fromOffsets: offsets, toOffset: destination)
        persistPlaybackSession()
    }

    func moveQueueSong(_ movingSong: String, before targetSong: String) {
        guard movingSong != targetSong,
              let sourceIndex = upcomingSongs.firstIndex(of: movingSong),
              let originalTargetIndex = upcomingSongs.firstIndex(of: targetSong) else { return }

        upcomingSongs.remove(at: sourceIndex)
        let destination = sourceIndex < originalTargetIndex
            ? max(0, originalTargetIndex - 1)
            : originalTargetIndex
        upcomingSongs.insert(movingSong, at: min(destination, upcomingSongs.count))
        persistPlaybackSession()
    }

    func removeQueueSongs(at offsets: IndexSet) {
        upcomingSongs.remove(atOffsets: offsets)
        persistPlaybackSession()
        updateRemoteCommandAvailability()
    }

    func clearQueue() {
        upcomingSongs.removeAll()
        unshuffledUpcomingSongs.removeAll()
        persistPlaybackSession()
        updateRemoteCommandAvailability()
    }

    private func playQueuedSong(_ song: String) {
        guard let songURL = localSongURL(for: song) else { return }
        installPlayer(
            url: songURL,
            title: song,
            remoteAudioURL: nil,
            localSongName: song,
            autoPlay: true
        )
        persistPlaybackSession()
    }

    private func buildQueue(startingAfter song: String, in context: [String]? = nil) {
        let context = context ?? localSongs
        playbackContext = context
        guard let index = context.firstIndex(of: song) else {
            upcomingSongs = isShuffleMode ? context.shuffled() : context
            persistPlaybackSession()
            return
        }
        let following = Array(context.dropFirst(index + 1))
        upcomingSongs = following
        if isShuffleMode { upcomingSongs.shuffle() }
        unshuffledUpcomingSongs = isShuffleMode ? following : []
        persistPlaybackSession()
        updateRemoteCommandAvailability()
    }

    private func restoreQueueForLaunch(currentSong: String) {
        let validSongs = Set(localSongs)
        playbackContext = restoredSession.playbackContext.filter(validSongs.contains)
        if playbackContext.isEmpty { playbackContext = localSongs }
        upcomingSongs = restoredSession.upcomingSongs.filter(validSongs.contains)
        playbackHistory = restoredSession.history.filter(validSongs.contains)
        if upcomingSongs.isEmpty {
            buildQueue(startingAfter: currentSong)
        }
        updateRemoteCommandAvailability()
    }
    
    func deleteSong(song: String) {
        if !recentlyDeleted.contains(song) {
            recentlyDeleted.append(song)
        }
        // Remove from local songs
        localSongs.removeAll { $0 == song }
        upcomingSongs.removeAll { $0 == song }
        playbackHistory.removeAll { $0 == song }
        persistRecentlyDeleted()
        persistPlaybackSession()
        moveDeletedSongFilesAside()
    }

    /// Moves files of songs in Recently Deleted out of the Songs folder, so
    /// the Files app only shows the library. The song loaded in the player is
    /// left in place until it's swapped out, so playback isn't cut off.
    private func moveDeletedSongFilesAside() {
        let fileManager = FileManager.default
        let songs = SongStorage.songsDirectory
        let deleted = SongStorage.recentlyDeletedDirectory
        for song in recentlyDeleted where song != currentLocalSongName {
            let source = songs.appendingPathComponent(song)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = deleted.appendingPathComponent(song)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.moveItem(at: source, to: destination)
        }
    }

    /// The file of a song in Recently Deleted, wherever it currently is.
    private func deletedSongURL(_ song: String) -> URL? {
        [SongStorage.recentlyDeletedDirectory, SongStorage.songsDirectory]
            .map { $0.appendingPathComponent(song) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func restoreSong(song: String) {
        guard let file = deletedSongURL(song) else { return }
        var name = song
        if file.deletingLastPathComponent().standardizedFileURL != SongStorage.songsDirectory.standardizedFileURL {
            // A song with the same name may have been saved again meanwhile.
            name = SongStorage.availableName(song, in: SongStorage.songsDirectory)
            do {
                try FileManager.default.moveItem(at: file, to: SongStorage.songsDirectory.appendingPathComponent(name))
            } catch {
                print("❌ Error restoring song: \(error)")
                return
            }
        }
        recentlyDeleted.removeAll { $0 == song }
        if name != song { replaceSongName(song, with: name) }
        localSongs.append(name)
        localSongs.sort()
        persistRecentlyDeleted()
    }

    func permanentlyDeleteSong(song: String) {
        if let file = deletedSongURL(song) {
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                print("❌ Error permanently deleting song: \(error)")
            }
        }
        recentlyDeleted.removeAll { $0 == song }
        removeSongFromLibraryMetadata(song)
        persistRecentlyDeleted()
    }

    func emptyRecentlyDeleted() {
        for song in recentlyDeleted {
            if let file = deletedSongURL(song) {
                do {
                    try FileManager.default.removeItem(at: file)
                } catch {
                    print("❌ Error deleting song: \(error)")
                }
            }
            removeSongFromLibraryMetadata(song)
        }
        recentlyDeleted.removeAll()
        persistRecentlyDeleted()
    }

    // MARK: - Song file names

    /// The name a song's file should have: "Artist - Title.mp3" once its
    /// artist is reliable (your edit, the file's tags, or confirmed online),
    /// or just "Title.mp3" once a search found no artist. `nil` while the
    /// artist is only a guess, so a wrong guess never gets written into the
    /// file name.
    private func organizedFileName(for song: String) -> String? {
        guard embeddedAlbums[song] != nil else { return nil }
        let profile = profile(for: song)
        let ext = (song as NSString).pathExtension
        switch profile.artistSource {
        case .manualEdit, .fileTags, .onlineConfirmed, .onlineLookup:
            return SongStorage.fileName(title: profile.title, artist: profile.artist, fileExtension: ext)
        case .unknown:
            guard onlineLookups[song]?.version == OnlineArtistLookup.currentVersion else { return nil }
            return SongStorage.fileName(title: profile.title, artist: nil, fileExtension: ext)
        case .title:
            return nil
        }
    }

    /// Renames song files to their organized names, so they're properly
    /// titled in the Files app and when shared. The song loaded in the player
    /// is skipped until it's swapped out, so playback isn't disturbed.
    func organizeSongFiles() {
        for song in localSongs where song != currentLocalSongName {
            guard let desired = organizedFileName(for: song), desired != song else { continue }
            let name = SongStorage.availableName(desired, in: SongStorage.songsDirectory, current: song)
            guard name != song else { continue }
            do {
                try SongStorage.rename(song, to: name, in: SongStorage.songsDirectory)
            } catch {
                print("❌ Error renaming song: \(error)")
                continue
            }
            replaceSongName(song, with: name)
        }
    }

    /// Points everything that refers to a song by its file name (the library,
    /// likes, playlists, the queue, history, the saved session, edits, tags
    /// and online results) at its new name.
    private func replaceSongName(_ old: String, with new: String) {
        func swap(_ name: String) -> String { name == old ? new : name }
        func moveKey<Value>(_ dictionary: inout [String: Value]) {
            if let value = dictionary.removeValue(forKey: old) { dictionary[new] = value }
        }

        localSongs = localSongs.map(swap).sorted()
        recentlyDeleted = recentlyDeleted.map(swap)
        if likedSongs.remove(old) != nil { likedSongs.insert(new) }
        for index in playlists.indices {
            playlists[index].songs = playlists[index].songs.map(swap)
        }
        upcomingSongs = upcomingSongs.map(swap)
        unshuffledUpcomingSongs = unshuffledUpcomingSongs.map(swap)
        playbackHistory = playbackHistory.map(swap)
        playbackContext = playbackContext.map(swap)
        restoredSession.currentSong = restoredSession.currentSong.map(swap)
        restoredSession.playbackContext = restoredSession.playbackContext.map(swap)
        restoredSession.upcomingSongs = restoredSession.upcomingSongs.map(swap)
        restoredSession.history = restoredSession.history.map(swap)

        moveKey(&songEdits)
        moveKey(&onlineLookups)
        moveKey(&embeddedArtists)
        moveKey(&embeddedAlbums)
        profileCache.removeAll()

        persistLibraryMetadata()
        persistRecentlyDeleted()
        persistPlaybackSession()
    }

    // MARK: - Likes and playlists

    func isLiked(_ song: String) -> Bool {
        likedSongs.contains(song)
    }

    func toggleLiked(_ song: String) {
        if likedSongs.contains(song) {
            likedSongs.remove(song)
        } else {
            likedSongs.insert(song)
        }
        persistLibraryMetadata()
        updateRemoteCommandAvailability()
    }

    @discardableResult
    func createPlaylist(named rawName: String) -> MusicPlaylist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let playlist = MusicPlaylist(name: name)
        playlists.append(playlist)
        persistLibraryMetadata()
        return playlist
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        persistLibraryMetadata()
    }

    func add(_ song: String, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].songs.contains(song) else { return }
        playlists[index].songs.append(song)
        persistLibraryMetadata()
    }

    func removeSongs(at offsets: IndexSet, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songs.remove(atOffsets: offsets)
        persistLibraryMetadata()
    }

    // MARK: - Song titles, artists & info

    /// Everything derived about a song, computed once and cached until an
    /// input (an edit, file tags, an online result) changes.
    private func profile(for song: String) -> SongProfile {
        if let cached = profileCache[song] { return cached }

        let rawTitle = AppDesign.displayTitle(for: song)
        let lookup = onlineLookups[song]
        let edit = songEdits[song]
        let guesses = ArtistGuesser.guesses(for: rawTitle, knownArtists: knownArtistNames)
        let bestGuess = guesses.first { $0.confidence >= .medium }
        let confirmedGuess = lookup?.confirmedGuess.flatMap { confirmed in
            guesses.first { artistKey($0.artist) == artistKey(confirmed) }
        }

        // The artist is decided first; the title then comes from the reading
        // of the name that has that same artist, so the two always come from
        // one consistent split and the artist's half never shows as the title.
        var artist: String
        var source: ArtistSource
        var method: ArtistGuess.Method?
        var artistAsWritten: String?
        if let manual = nonEmpty(edit?.artist) {
            (artist, source, artistAsWritten) = (manual, .manualEdit, manual)
        } else if let tagged = taggedArtist(for: song) {
            // The catalog's spelling of a tagged name, when it confirmed it.
            let official = lookup?.confirmedGuess.map(artistKey) == artistKey(tagged) ? nonEmpty(lookup?.artist) : nil
            (artist, source, artistAsWritten) = (official ?? ArtistNameFormatter.display(tagged), .fileTags, tagged)
        } else if let confirmed = lookup?.confirmedGuess, let official = nonEmpty(lookup?.artist) {
            (artist, source, method, artistAsWritten) = (official, .onlineConfirmed, confirmedGuess?.method, confirmed)
        } else if let bestGuess {
            (artist, source, method, artistAsWritten) = (ArtistNameFormatter.display(bestGuess.artist), .title, bestGuess.method, bestGuess.artist)
        } else if let online = nonEmpty(lookup?.artist) {
            (artist, source) = (ArtistNameFormatter.display(online), .onlineLookup)
        } else {
            (artist, source) = (Self.unknownArtist, .unknown)
        }

        // The artist as written in the name, or as displayed: after a file is
        // renamed to "Kenshi Yonezu - Lemon", the name shows the English
        // spelling rather than the original 米津玄師.
        let title = nonEmpty(edit?.title)
            ?? [artistAsWritten, source == .unknown ? nil : artist]
                .compactMap { $0 }
                .lazy
                .compactMap { self.titleMatching(artist: $0, in: rawTitle, among: guesses) }
                .first
            ?? plainTitle(rawTitle)

        if source != .manualEdit, let cleaned = ArtistNameFormatter.clean(artist) {
            artist = ArtistNameFormatter.display(cleaned)
        }

        // Show: a manual choice (including "none") wins, then anything in the
        // song's own name or tags, then the catalog evidence found online.
        let show: String?
        if let manualShow = edit?.show {
            show = nonEmpty(manualShow)
        } else {
            show = localShow(for: song)
                ?? nonEmpty(lookup?.show)
                ?? lookup?.collection.flatMap { ShowCatalog.show(in: $0, keywordsOnly: true)?.name }
        }

        let result = SongProfile(title: title, artist: artist, artistSource: source, show: show, guessMethod: method)
        profileCache[song] = result
        return result
    }

    /// The title from the reading of the name whose artist is `artist`. When
    /// no reading has that artist (it came from tags or a manual edit and
    /// isn't the usual half of the name), the artist's name is cut out of
    /// the name and what's left is the title. `nil` if the name doesn't
    /// mention the artist at all, in which case the whole name is the title.
    private func titleMatching(artist: String, in rawTitle: String, among guesses: [ArtistGuess]) -> String? {
        let key = artistKey(artist)
        if let match = guesses.first(where: { artistKey($0.artist) == key }) {
            return match.title
        }
        if let known = ArtistGuesser.guesses(for: rawTitle, knownArtists: [artist])
            .first(where: { $0.method == .knownArtist && artistKey($0.artist) == key }) {
            return known.title
        }
        // The artist as the first or last " - " part, even where the written
        // form differs slightly ("AC∕DC" in a file name for "AC/DC").
        let parts = rawTitle.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        if artistKey(parts[0]) == key { return parts.dropFirst().joined(separator: " - ") }
        if artistKey(parts[parts.count - 1]) == key { return parts.dropLast().joined(separator: " - ") }
        return nil
    }

    /// A name's title when no artist is known: uploader noise and show-label
    /// segments ("Naruto OP 16 - ") removed, but otherwise the whole name, so
    /// an unconfirmed half of it is never shown as the title alone.
    private func plainTitle(_ rawTitle: String) -> String {
        let cleaned = SongMetadataParser.cleanedTitle(rawTitle)
        let parts = cleaned
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !ShowCatalog.isShowLabel($0) }
        let title = parts.joined(separator: " - ")
        return title.isEmpty ? (cleaned.isEmpty ? rawTitle : cleaned) : title
    }

    /// The artist from the file's tags, unless the tag is really a show label
    /// (some rips tag every track's artist as "ONE PIECE").
    private func taggedArtist(for song: String) -> String? {
        guard let tag = nonEmpty(embeddedArtists[song]), !ShowCatalog.isShowLabel(tag) else { return nil }
        return ArtistNameFormatter.clean(tag)
    }

    /// Artists known for certain (edited, tagged, or confirmed online), used
    /// to spot the same artists inside other songs' names.
    private var knownArtistNames: [String] {
        if let knownArtistCache { return knownArtistCache }
        var names = Set<String>()
        for song in localSongs {
            if let manual = nonEmpty(songEdits[song]?.artist) { names.insert(manual) }
            if let tagged = taggedArtist(for: song), !ArtistNameFormatter.containsJapanese(tagged) { names.insert(tagged) }
            if onlineLookups[song]?.confirmedGuess != nil, let official = nonEmpty(onlineLookups[song]?.artist) {
                names.insert(official)
            }
        }
        let result = names.filter { $0 != Self.unknownArtist }.sorted()
        knownArtistCache = result
        return result
    }

    /// A show detected from the song's own information, checking each field
    /// separately so words from two fields can't combine into a false match.
    private func localShow(for song: String) -> String? {
        let edit = songEdits[song]
        let fields = [
            AppDesign.displayTitle(for: song),
            edit?.title,
            edit?.artist,
            embeddedAlbums[song],
            embeddedArtists[song]
        ]
        for field in fields.compactMap(nonEmpty) {
            if let show = ShowCatalog.show(in: field) { return show.name }
        }
        return nil
    }

    /// The artist if it can be found without going online.
    private func localArtist(for song: String) -> String? {
        nonEmpty(songEdits[song]?.artist)
            ?? taggedArtist(for: song)
            ?? ArtistGuesser.bestOfflineGuess(for: AppDesign.displayTitle(for: song), knownArtists: knownArtistNames)?.artist
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static let unknownArtist = "Unknown Artist"

    /// The song's title as shown throughout the app: a manual edit if there
    /// is one, otherwise its filename with any "Artist - " prefix and
    /// uploader noise like "(Official Video)" parsed away.
    func displayTitle(for song: String) -> String {
        profile(for: song).title
    }

    /// Resolves a song's artist. Order: manual edit, embedded file tags, the
    /// "Artist - Title" pattern in the name, the one-time online lookup, then
    /// "Unknown Artist".
    func artist(for song: String) -> String {
        profile(for: song).artist
    }

    func artistSource(for song: String) -> ArtistSource {
        profile(for: song).artistSource
    }

    /// Where a song's artist came from, including the naming pattern used.
    func artistSourceDescription(for song: String) -> String {
        profile(for: song).sourceDescription
    }

    /// The show a song belongs to (One Piece, Bleach…), if one is recognized.
    func show(for song: String) -> String? {
        profile(for: song).show
    }

    /// "Artist / Show" for songs from a show, otherwise just the artist.
    func artistAndShow(for song: String) -> String {
        profile(for: song).artistAndShow
    }

    /// The currently playing song's title, honoring any manual edit.
    var displayVideoTitle: String {
        currentSongName.map(displayTitle(for:)) ?? AppDesign.displayTitle(for: videoTitle)
    }

    /// The currently playing song's artist, or `nil` before anything local is loaded.
    var currentArtist: String? {
        currentSongName.map(artist(for:))
    }

    /// The currently playing song as "Artist / Show", or `nil` before anything
    /// local is loaded.
    var currentArtistAndShow: String? {
        currentSongName.map(artistAndShow(for:))
    }

    /// Saves manual corrections from Song Info. A field left as it was keeps
    /// whatever it had (automatic or an earlier edit). A cleared title or
    /// artist goes back to automatic detection; a cleared show means "not
    /// from any show".
    func updateSongDetails(for song: String, title: String, artist: String, show: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShow = show.trimmingCharacters(in: .whitespacesAndNewlines)

        var edit = songEdits[song] ?? SongEdit()
        if trimmedTitle != displayTitle(for: song) {
            edit.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        }
        if trimmedArtist != self.artist(for: song) {
            edit.artist = trimmedArtist.isEmpty ? nil : trimmedArtist
        }
        if trimmedShow != (self.show(for: song) ?? "") {
            edit.show = trimmedShow.isEmpty ? "" : ShowCatalog.canonicalName(for: trimmedShow)
        }
        applyEdit(edit, to: song)
    }

    /// Drops every manual correction for a song, returning it to automatic
    /// detection.
    func resetSongDetails(for song: String) {
        applyEdit(SongEdit(), to: song)
    }

    func hasManualEdits(for song: String) -> Bool {
        songEdits[song] != nil
    }

    private func applyEdit(_ edit: SongEdit, to song: String) {
        if edit == SongEdit() {
            songEdits.removeValue(forKey: song)
        } else {
            songEdits[song] = edit
        }
        persistLibraryMetadata()
        if isCurrentSong(song) {
            updateNowPlayingInfo(title: videoTitle)
        }
        organizeSongFiles()
        // A cleared artist may need the online search it previously skipped.
        startOnlineLookupIfNeeded()
    }

    // MARK: Artists and shows

    private func artistKey(_ name: String) -> String {
        AppDesign.songMatchKey(for: name)
    }

    /// Every artist in the library with duplicates merged ("DAFT PUNK" and
    /// "Daft Punk" are one artist), preferring the mixed-case spelling.
    private func canonicalArtistNames(for songs: [String]) -> [String: String] {
        var names: [String: String] = [:]
        for song in songs {
            let name = artist(for: song)
            let key = artistKey(name)
            guard !key.isEmpty else { continue }
            if let existing = names[key] {
                let existingIsShouting = existing == existing.uppercased() || existing == existing.lowercased()
                let candidateIsShouting = name == name.uppercased() || name == name.lowercased()
                if existingIsShouting && !candidateIsShouting { names[key] = name }
            } else {
                names[key] = name
            }
        }
        return names
    }

    private func sortedArtistNames(_ names: some Sequence<String>) -> [String] {
        names.sorted { lhs, rhs in
            if lhs == Self.unknownArtist { return false }
            if rhs == Self.unknownArtist { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    /// Every artist in the library, including those who perform songs from a
    /// show (they appear under both their own name and the show).
    var artists: [String] {
        sortedArtistNames(canonicalArtistNames(for: localSongs).values)
    }

    /// The shows an artist has songs in, for showing "Artist / Show".
    func shows(forArtist name: String) -> [String] {
        Set(songs(byArtist: name).compactMap { show(for: $0) })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// All library songs attributed to a given artist, forming that artist's
    /// automatic playlist.
    func songs(byArtist name: String) -> [String] {
        let key = artistKey(name)
        return localSongs.filter { artistKey(artist(for: $0)) == key }
    }

    /// The shows present in the library, alphabetical.
    var shows: [String] {
        Set(localSongs.compactMap { show(for: $0) })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func songs(inShow name: String) -> [String] {
        localSongs.filter { show(for: $0) == name }
    }

    /// Artists who have songs in a show, for showing who performs there.
    func artists(inShow name: String) -> [String] {
        let showSongs = songs(inShow: name)
        return sortedArtistNames(canonicalArtistNames(for: showSongs).values)
    }

    /// The song as a shareable file named "Artist - Title", or `nil` if its
    /// file is missing.
    func shareableSong(for song: String) -> ShareableSong? {
        guard let url = songFileURL(for: song), FileManager.default.fileExists(atPath: url.path) else { return nil }
        let profile = profile(for: song)
        let artist = profile.artistSource == .unknown ? nil : profile.artist
        return ShareableSong(
            fileURL: url,
            fileName: SongStorage.fileName(title: profile.title, artist: artist, fileExtension: url.pathExtension),
            title: profile.title,
            artist: artist ?? ""
        )
    }

    func fileSize(for song: String) -> Int64? {
        guard let url = songFileURL(for: song),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.size] as? Int64
    }

    /// The date the song's file was added to the device.
    func dateAdded(for song: String) -> Date? {
        guard let url = songFileURL(for: song),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.creationDate] as? Date) ?? (attributes[.modificationDate] as? Date)
    }

    /// Reads each not-yet-checked song's embedded artist and album tags, one
    /// file at a time in the background, so the UI updates progressively
    /// without blocking on disk I/O.
    private func refreshEmbeddedTagsIfNeeded() {
        let songsNeedingScan = localSongs.filter { embeddedArtists[$0] == nil || embeddedAlbums[$0] == nil }
        guard !songsNeedingScan.isEmpty else {
            startOnlineLookupIfNeeded()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            for song in songsNeedingScan {
                guard let url = self.songFileURL(for: song) else { continue }
                let tags = await SongMetadataParser.embeddedTags(from: url)
                await MainActor.run {
                    self.embeddedArtists[song] = tags.artist ?? ""
                    self.embeddedAlbums[song] = tags.album ?? ""
                }
            }
            await MainActor.run {
                self.persistLibraryMetadata()
                self.organizeSongFiles()
                self.startOnlineLookupIfNeeded()
            }
        }
    }

    // MARK: One-time online artist lookup

    private var onlineLookupEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.onlineLookupEnabledKey) as? Bool ?? true
    }

    private func startMonitoringConnectivity() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                if self.isOnline { self.startOnlineLookupIfNeeded() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "artist-lookup.connectivity"))
    }

    /// A song is searched online when its artist or its show can't be found
    /// locally, it hasn't been searched under the current rules, and its file
    /// tags were already checked (so a tag isn't missed by searching too early).
    private func needsOnlineLookup(_ song: String) -> Bool {
        guard embeddedAlbums[song] != nil,
              onlineLookups[song]?.version != OnlineArtistLookup.currentVersion else { return false }
        let showKnown = songEdits[song]?.show != nil || localShow(for: song) != nil
        // A manual or English-letter tagged artist is trusted as-is; only
        // the show might still need finding.
        if nonEmpty(songEdits[song]?.artist) != nil { return !showKnown }
        if let tagged = taggedArtist(for: song), !ArtistNameFormatter.containsJapanese(tagged) { return !showKnown }
        // Otherwise the name-based guess gets confirmed or corrected, a
        // Japanese name gets its English spelling, or the artist gets found.
        return true
    }

    /// Searches for the artist of every eligible song, once per song, whenever
    /// the device is online. Results are saved as they arrive, so a song is
    /// never searched twice, even across launches. Requests are spaced out to
    /// stay under the API's rate limit.
    func startOnlineLookupIfNeeded() {
        guard onlineLookupEnabled, isOnline, !isRunningOnlineLookup else { return }
        let queue = localSongs.filter(needsOnlineLookup)
        guard !queue.isEmpty else { return }

        isRunningOnlineLookup = true
        isLookingUpArtists = true

        Task { @MainActor [weak self] in
            for song in queue {
                guard let self, self.isOnline, self.onlineLookupEnabled else { break }
                guard self.needsOnlineLookup(song) else { continue }
                do {
                    // The network request runs off the main actor; everything
                    // touching library state stays on it.
                    let rawTitle = AppDesign.displayTitle(for: song)
                    let fixedArtist = self.nonEmpty(self.songEdits[song]?.artist) ?? self.taggedArtist(for: song)
                    let match = try await OnlineArtistLookup.lookup(
                        rawTitle: rawTitle,
                        guesses: fixedArtist == nil
                            ? ArtistGuesser.guesses(for: rawTitle, knownArtists: self.knownArtistNames)
                            : [],
                        taggedArtist: fixedArtist,
                        needsShow: self.songEdits[song]?.show == nil && self.localShow(for: song) == nil
                    )
                    self.onlineLookups[song] = match
                    self.persistLibraryMetadata()
                    self.organizeSongFiles()
                } catch {
                    break
                }
                try? await Task.sleep(for: .seconds(3))
            }
            self?.isRunningOnlineLookup = false
            self?.isLookingUpArtists = false
        }
    }

    private func restoreLibraryMetadata() {
        guard let data = UserDefaults.standard.data(forKey: libraryMetadataKey),
              let metadata = try? JSONDecoder().decode(LibraryMetadata.self, from: data) else { return }
        likedSongs = metadata.likedSongs
        playlists = metadata.playlists
        songEdits = metadata.songEdits
        onlineLookups = metadata.onlineLookups
        embeddedArtists = metadata.embeddedArtists
        embeddedAlbums = metadata.embeddedAlbums
    }

    private func persistLibraryMetadata() {
        let metadata = LibraryMetadata(
            likedSongs: likedSongs,
            playlists: playlists,
            songEdits: songEdits,
            onlineLookups: onlineLookups,
            embeddedArtists: embeddedArtists,
            embeddedAlbums: embeddedAlbums
        )
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        UserDefaults.standard.set(data, forKey: libraryMetadataKey)
    }

    private func reconcileLibraryMetadata() {
        let availableSongs = Set(localSongs + recentlyDeleted)
        likedSongs.formIntersection(availableSongs)
        for index in playlists.indices {
            playlists[index].songs = playlists[index].songs.filter(availableSongs.contains)
        }
        songEdits = songEdits.filter { availableSongs.contains($0.key) }
        onlineLookups = onlineLookups.filter { availableSongs.contains($0.key) }
        embeddedArtists = embeddedArtists.filter { availableSongs.contains($0.key) }
        embeddedAlbums = embeddedAlbums.filter { availableSongs.contains($0.key) }
        persistLibraryMetadata()
    }

    private func removeSongFromLibraryMetadata(_ song: String) {
        likedSongs.remove(song)
        songEdits.removeValue(forKey: song)
        onlineLookups.removeValue(forKey: song)
        embeddedArtists.removeValue(forKey: song)
        embeddedAlbums.removeValue(forKey: song)
        for index in playlists.indices {
            playlists[index].songs.removeAll { $0 == song }
        }
        persistLibraryMetadata()
    }

    private func persistRecentlyDeleted() {
        UserDefaults.standard.set(recentlyDeleted, forKey: recentlyDeletedKey)
    }

    private func restorePlaybackPreferences() {
        guard let data = UserDefaults.standard.data(forKey: playbackSessionKey),
              let session = try? JSONDecoder().decode(PlaybackSession.self, from: data) else { return }
        restoredSession = session
        isShuffleMode = session.isShuffleEnabled
        repeatMode = session.repeatMode
    }

    private func persistPlaybackSession() {
        var session = PlaybackSession()
        session.currentSong = currentLocalSongName ?? restoredSession.currentSong
        session.elapsedTime = currentLocalSongName == nil ? restoredSession.elapsedTime : currentTime
        session.playbackContext = playbackContext
        session.upcomingSongs = upcomingSongs
        session.history = playbackHistory
        session.isShuffleEnabled = isShuffleMode
        session.repeatMode = repeatMode
        restoredSession = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: playbackSessionKey)
    }

    func savePlaybackState() {
        persistPlaybackSession()
    }
}
