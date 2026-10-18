import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage("serverURL") private var savedServerURL = "http://192.168.1.155:5000"
    @AppStorage(Wallpaper.storageKey) private var wallpaper = Wallpaper.default
    @AppStorage(AppFont.storageKey) private var appFont = AppFont.default
    @AppStorage(AppFont.scaleStorageKey) private var fontScale = AppFont.defaultScale
    @AppStorage(AudioManager.onlineLookupEnabledKey) private var onlineLookupEnabled = true
    @State private var serverURL = ""
    @State private var showSavedConfirmation = false
    @State private var confirmEmptyTrash = false

    private var normalizedServerURL: String {
        serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var isValidServerURL: Bool {
        guard let components = URLComponents(string: normalizedServerURL),
              let scheme = components.scheme?.lowercased(),
              components.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    var body: some View {
        NavigationStack {
            Form {
                if Wallpaper.allCases.count > 1 {
                    Section("Wallpaper") {
                        HStack(spacing: 12) {
                            ForEach(Wallpaper.allCases) { option in
                                wallpaperOption(option)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }

                Section {
                    ForEach(AppFont.allCases) { option in
                        fontOption(option)
                    }
                } header: {
                    Text("Font")
                } footer: {
                    Text("Changes the typeface used throughout the app.")
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $fontScale, in: AppFont.scaleRange, step: 0.05)
                            .accessibilityLabel("Text Size")
                            .accessibilityValue("\(Int((fontScale * 100).rounded())) percent")
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }

                    Button("Reset to Default Size") {
                        fontScale = AppFont.defaultScale
                    }
                    .disabled(fontScale == AppFont.defaultScale)
                } header: {
                    HStack {
                        Text("Text Size")
                        Spacer()
                        Text("\(Int((fontScale * 100).rounded()))%")
                    }
                } footer: {
                    Text("Adjusts text throughout the app. It also follows the Text Size you set in iOS Settings.")
                }

                Section {
                    Toggle("Find Missing Artists Online", isOn: $onlineLookupEnabled)

                    if audioManager.isLookingUpArtists {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Searching…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Artist Detection")
                } footer: {
                    Text("When you're online, each song is checked once against Apple's iTunes catalog to confirm or correct its artist, find the English spelling of Japanese names, and find which show it's from. Only the song's title and guessed artist are sent.")
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                        TextField("http://192.168.1.100:5000", text: $serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .onSubmit(saveServerURL)
                    }

                    LabeledContent("Status") {
                        Label(
                            isValidServerURL ? "Ready" : "Check URL",
                            systemImage: isValidServerURL ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(isValidServerURL ? Color.green : Color.orange)
                    }

                    Button(action: saveServerURL) {
                        Label(
                            showSavedConfirmation ? "Address Saved" : "Use This Address",
                            systemImage: showSavedConfirmation ? "checkmark" : "square.and.arrow.down"
                        )
                    }
                    .disabled(!isValidServerURL || normalizedServerURL == savedServerURL)
                } header: {
                    Text("Audio Server")
                } footer: {
                    Text("Enter the address manually, including http:// or https:// and its port. Saved changes are used for the next song download.")
                }

                Section {
                    if audioManager.recentlyDeleted.isEmpty {
                        Label("No recently deleted songs", systemImage: "trash")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioManager.recentlyDeleted, id: \.self) { song in
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28)
                                Text(audioManager.displayTitle(for: song))
                                    .lineLimit(2)
                                Spacer()
                                Menu {
                                    Button {
                                        audioManager.restoreSong(song: song)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    Button(role: .destructive) {
                                        audioManager.permanentlyDeleteSong(song: song)
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(width: 40, height: 40)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    audioManager.restoreSong(song: song)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    audioManager.permanentlyDeleteSong(song: song)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }

                        Button("Empty Recently Deleted", role: .destructive) {
                            confirmEmptyTrash = true
                        }
                    }
                } header: {
                    Text("Recently Deleted")
                } footer: {
                    Text("Songs stay on this device until you delete them permanently.")
                }

                Section("About") {
                    LabeledContent("App", value: "Saucy Musi")
                    LabeledContent("Designed for", value: "iOS 26")
                    LabeledContent("Version", value: appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppGradientBackground() }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Permanently delete every recently deleted song?",
                isPresented: $confirmEmptyTrash,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive, action: audioManager.emptyRecentlyDeleted)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action can’t be undone.")
            }
        }
        .onAppear {
            serverURL = savedServerURL
        }
        .onChange(of: fontScale) { _, scale in
            AppTypography.configureNavigationAppearance(font: appFont, scale: scale)
        }
        .onChange(of: onlineLookupEnabled) { _, isEnabled in
            if isEnabled { audioManager.startOnlineLookupIfNeeded() }
        }
    }

    private func wallpaperOption(_ option: Wallpaper) -> some View {
        let isSelected = wallpaper == option

        return Button {
            wallpaper = option
            BackgroundVideoPlayer.shared.select(option)
        } label: {
            VStack(spacing: 8) {
                Image(option.previewImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 3
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }

                Text(option.title)
                    .appFont(.footnote, weight: isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) wallpaper")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func fontOption(_ option: AppFont) -> some View {
        let isSelected = appFont == option

        return Button {
            appFont = option
            AppTypography.configureNavigationAppearance(font: option, scale: fontScale)
        } label: {
            HStack {
                Text(option.title)
                    .font(option.font(.body, scale: fontScale, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return shortVersion ?? "1.0"
    }

    private func saveServerURL() {
        guard isValidServerURL else { return }
        savedServerURL = normalizedServerURL
        showSavedConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showSavedConfirmation = false
        }
    }
}
