import AVFoundation
import SwiftUI
import UIKit

enum Wallpaper: String, CaseIterable, Identifiable {
    case ink

    static let storageKey = "wallpaper"
    static let `default`: Wallpaper = .ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: "Ink"
        }
    }

    var previewImageName: String {
        switch self {
        case .ink: "WallpaperInk"
        }
    }

    var videoURL: URL? {
        Bundle.main.url(forResource: "wallpaper-\(rawValue)", withExtension: "mp4")
    }

    static var saved: Wallpaper {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Wallpaper.init) ?? .default
    }
}

/// One muted, looping player shared by every background so screens stay in sync
/// and only a single decoder runs. It restarts itself whenever the system pauses it
/// (backgrounding, audio interruptions, layers re-attaching), so the wallpaper never freezes.
@MainActor
final class BackgroundVideoPlayer {
    static let shared = BackgroundVideoPlayer()

    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var current: Wallpaper?
    private var observers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var looperObservation: NSKeyValueObservation?

    private init() {
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .paused else { return }
            Task { @MainActor in self?.resume() }
        }

        let center = NotificationCenter.default
        let wakeUps: [(Notification.Name, AnyObject?)] = [
            (UIApplication.didBecomeActiveNotification, nil),
            (UIApplication.willEnterForegroundNotification, nil),
            (AVAudioSession.interruptionNotification, nil),
            (AVAudioSession.routeChangeNotification, nil),
            (AVPlayerItem.playbackStalledNotification, nil)
        ]
        for (name, object) in wakeUps {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            })
        }
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })

        select(Wallpaper.saved)
    }

    func select(_ wallpaper: Wallpaper) {
        guard wallpaper != current else { return }
        current = wallpaper
        reload()
    }

    private func reload() {
        guard let wallpaper = current, let url = wallpaper.videoURL else { return }

        looper?.disableLooping()
        player.removeAllItems()
        let newLooper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        looper = newLooper
        looperObservation = newLooper.observe(\.status, options: [.new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            Task { @MainActor in self?.reload() }
        }
        player.play()
    }

    func resume() {
        guard looper != nil, UIApplication.shared.applicationState != .background else { return }
        if player.timeControlStatus == .paused {
            player.play()
        }
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            BackgroundVideoPlayer.shared.resume()
        }
    }
}

struct BackgroundVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = PlayerLayerView()
        view.playerLayer.player = BackgroundVideoPlayer.shared.player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
