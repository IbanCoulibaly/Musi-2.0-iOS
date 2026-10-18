import SwiftUI
import UIKit

enum AppFontWeight {
    case regular
    case medium
    case bold

    var weight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
    }
}

/// The typeface the whole app uses, chosen in Settings.
enum AppFont: String, CaseIterable, Identifiable {
    case sfPro
    case sfRounded
    case newYork
    case sfMono
    case ubuntu

    static let storageKey = "appFont"
    static let `default`: AppFont = .sfPro

    /// Multiplies every text style's size, on top of the system Dynamic Type size.
    static let scaleStorageKey = "appFontScale"
    static let defaultScale: Double = 1
    static let scaleRange: ClosedRange<Double> = 0.85...1.3

    static var savedScale: Double {
        let scale = UserDefaults.standard.object(forKey: scaleStorageKey) as? Double ?? defaultScale
        return min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfPro: "SF Pro"
        case .sfRounded: "SF Rounded"
        case .newYork: "New York"
        case .sfMono: "SF Mono"
        case .ubuntu: "Ubuntu"
        }
    }

    static var saved: AppFont {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppFont.init) ?? .default
    }

    private var systemDesign: Font.Design? {
        switch self {
        case .sfPro: .default
        case .sfRounded: .rounded
        case .newYork: .serif
        case .sfMono: .monospaced
        case .ubuntu: nil
        }
    }

    private func ubuntuName(for weight: AppFontWeight) -> String {
        switch weight {
        case .regular: "Ubuntu-Regular"
        case .medium: "Ubuntu-Medium"
        case .bold: "Ubuntu-Bold"
        }
    }

    func font(
        _ style: Font.TextStyle,
        weight: AppFontWeight = .regular,
        scale: Double = 1,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> Font {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let size = UIFontMetrics(forTextStyle: style.uiTextStyle)
            .scaledValue(for: style.defaultPointSize * scale, compatibleWith: traits)
        return font(size: size, weight: weight)
    }

    func font(size: CGFloat, weight: AppFontWeight = .regular) -> Font {
        guard let systemDesign else {
            return .custom(ubuntuName(for: weight), fixedSize: size)
        }
        return .system(size: size, weight: weight.weight, design: systemDesign)
    }

    func uiFont(size: CGFloat, weight: AppFontWeight = .regular) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .sfPro: return systemFont
        case .sfRounded: design = .rounded
        case .newYork: design = .serif
        case .sfMono: design = .monospaced
        case .ubuntu: return UIFont(name: ubuntuName(for: weight), size: size) ?? systemFont
        }
        guard let descriptor = systemFont.fontDescriptor.withDesign(design) else { return systemFont }
        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }

    var defaultPointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

/// Applies the font and text size chosen in Settings and updates as soon as
/// either changes. Fixed sizes (used for icons) ignore the text size.
private struct AppFontModifier: ViewModifier {
    @AppStorage(AppFont.storageKey) private var appFont = AppFont.default
    @AppStorage(AppFont.scaleStorageKey) private var scale = AppFont.defaultScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let style: Font.TextStyle?
    let size: CGFloat
    let weight: AppFontWeight

    func body(content: Content) -> some View {
        if let style {
            content.font(appFont.font(style, weight: weight, scale: scale, dynamicTypeSize: dynamicTypeSize))
        } else {
            content.font(appFont.font(size: size, weight: weight))
        }
    }
}

extension View {
    func appFont(_ style: Font.TextStyle, weight: AppFontWeight = .regular) -> some View {
        modifier(AppFontModifier(style: style, size: 0, weight: weight))
    }

    func appFont(size: CGFloat, weight: AppFontWeight = .regular) -> some View {
        modifier(AppFontModifier(style: nil, size: size, weight: weight))
    }
}

enum AppTypography {
    /// Styles UIKit bars. Bars that are already on screen keep their old font
    /// until they are shown again.
    static func configureNavigationAppearance(font: AppFont = .saved, scale: Double = AppFont.savedScale) {
        let regular = font.uiFont(size: 17 * scale)
        let medium = font.uiFont(size: 15 * scale, weight: .medium)
        let bold = font.uiFont(size: 34 * scale, weight: .bold)

        let navigationBar = UINavigationBar.appearance()
        navigationBar.titleTextAttributes = [.font: font.uiFont(size: 17 * scale, weight: .medium)]
        navigationBar.largeTitleTextAttributes = [.font: bold]

        UITabBarItem.appearance().setTitleTextAttributes([.font: medium], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: regular], for: .normal)
    }
}

enum AppDesign {
    static let artworkCornerRadius: CGFloat = 28
    static let cardCornerRadius: CGFloat = 24
    static let horizontalPadding: CGFloat = 20

    static func displayTitle(for filename: String) -> String {
        let title = filename.replacingOccurrences(
            of: "\\.(mp3|m4a|caf)$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return title.isEmpty || title == "Untitled" ? "Nothing Playing" : title
    }

    static func songMatchKey(for title: String) -> String {
        let titleWithoutExtension = title.replacingOccurrences(
            of: "\\.(mp3|m4a|caf)$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let foldedTitle = titleWithoutExtension.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let words = foldedTitle
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return words.joined(separator: " ")
    }
}

struct AppGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private static let gradientOpacity = 0.72

    private var gradientColors: [Color] {
        if colorScheme == .light {
            return [
                Color.accentColor.opacity(0.30),
                Color(red: 0.94, green: 0.90, blue: 1.0).opacity(0.94),
                .white
            ]
        }

        return [
            Color.accentColor.opacity(0.42),
            Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.94),
            Color(red: 0.035, green: 0.05, blue: 0.09)
        ]
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            BackgroundVideoView()

            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(Self.gradientOpacity)
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                BackgroundVideoPlayer.shared.resume()
            }
        }
    }
}

enum RotatingArtwork {
    static let imageNames = (1...15).map { String(format: "Artwork%02d", $0) }
    static let interval: TimeInterval = 15

    /// Ticks land on absolute multiples of `interval`, so every ArtworkView
    /// (mini player, Now Playing) switches images at the same instant.
    static let schedule = PeriodicTimelineSchedule(
        from: Date(timeIntervalSinceReferenceDate: 0),
        by: interval
    )

    static func imageName(at date: Date) -> String {
        let tick = Int(date.timeIntervalSinceReferenceDate / interval)
        let index = ((tick % imageNames.count) + imageNames.count) % imageNames.count
        return imageNames[index]
    }
}

struct ArtworkView: View {
    var cornerRadius: CGFloat = AppDesign.artworkCornerRadius

    var body: some View {
        TimelineView(RotatingArtwork.schedule) { context in
            let imageName = RotatingArtwork.imageName(at: context.date)

            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .id(imageName)
                        .transition(.opacity)
                        .overlay {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.14)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }
                }
                .animation(.easeInOut(duration: 0.6), value: imageName)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var audioManager: AudioManager
    let showNowPlaying: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: showNowPlaying) {
                HStack(spacing: 12) {
                    if audioManager.hasSelectedSong {
                        ArtworkView(cornerRadius: 8)
                            .frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "music.note")
                            .appFont(.body, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            audioManager.hasSelectedSong
                                ? audioManager.displayVideoTitle
                                : "Welcome to Saucy Musi"
                        )
                            .appFont(.subheadline, weight: .medium)
                            .lineLimit(1)
                        Text(
                            audioManager.isLoading
                                ? "Loading…"
                                : audioManager.hasSelectedSong
                                    ? (audioManager.currentArtistAndShow ?? "Saucy Musi")
                                    : "Add a song to start listening"
                        )
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(audioManager.hasSelectedSong)

            Button(action: audioManager.togglePlayback) {
                Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                    .appFont(.headline, weight: .medium)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!audioManager.hasSelectedSong)
            .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")

            Button { audioManager.playNextSongInQueue() } label: {
                Image(systemName: "forward.fill")
                    .appFont(.body)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!audioManager.hasSelectedSong)
            .accessibilityLabel("Next Track")
        }
        .padding(.horizontal, 12)
    }
}
