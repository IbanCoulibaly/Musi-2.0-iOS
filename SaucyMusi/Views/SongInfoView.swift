import AVFoundation
import SwiftUI

/// Lets someone correct a song's title/artist and see the file's own details
/// (added date, size, length, format, bit rate).
struct SongInfoView: View {
    let song: String
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss

    @State private var titleText = ""
    @State private var artistText = ""
    @State private var showText = ""
    @State private var fileSize: Int64?
    @State private var duration: Double?
    @State private var bitRate: Double?
    @State private var isLoadingAudioDetails = true

    private var dateAdded: Date? { audioManager.dateAdded(for: song) }
    private var fileFormat: String { (song as NSString).pathExtension.uppercased() }

    private var isSaveDisabled: Bool {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    labeledField("Song Title", placeholder: "Song title", text: $titleText)
                    labeledField("Artist", placeholder: "Artist name", text: $artistText)
                    labeledField("Show", placeholder: "Not from a show", text: $showText)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Changes only affect how the song looks in Saucy Musi. Clear the show to keep this song out of every show.")
                }

                Section("Detected") {
                    LabeledContent("Artist Found From") {
                        Text(audioManager.artistSourceDescription(for: song))
                            .multilineTextAlignment(.trailing)
                    }
                    if audioManager.hasManualEdits(for: song) {
                        Button("Reset to Automatic Detection", role: .destructive) {
                            audioManager.resetSongDetails(for: song)
                            loadFields()
                        }
                    }
                }

                Section("File") {
                    LabeledContent("Date Added", value: dateAdded.map(Self.dateFormatter.string) ?? "Unknown")
                    LabeledContent("File Size", value: fileSize.map(Self.sizeFormatter.string(fromByteCount:)) ?? "—")
                    LabeledContent(
                        "Length",
                        value: duration.map(audioManager.formattedTime) ?? (isLoadingAudioDetails ? "Loading…" : "—")
                    )
                    LabeledContent("Format", value: fileFormat)
                    if let bitRate {
                        LabeledContent("Bit Rate", value: "\(Int(bitRate.rounded())) kbps")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppGradientBackground() }
            .navigationTitle("Song Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        audioManager.updateSongDetails(for: song, title: titleText, artist: artistText, show: showText)
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .onAppear {
            loadFields()
            fileSize = audioManager.fileSize(for: song)
        }
        .task { await loadAudioDetails() }
    }

    /// A text field with its name shown above it, so it's always clear which
    /// field is the title and which is the artist, even once filled in.
    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .appFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .accessibilityLabel(label)
        }
        .padding(.vertical, 2)
    }

    private func loadFields() {
        titleText = audioManager.displayTitle(for: song)
        artistText = audioManager.artist(for: song)
        showText = audioManager.show(for: song) ?? ""
    }

    private func loadAudioDetails() async {
        guard let url = audioManager.songFileURL(for: song) else {
            isLoadingAudioDetails = false
            return
        }
        let asset = AVURLAsset(url: url)

        if let cmDuration = try? await asset.load(.duration) {
            let seconds = cmDuration.seconds
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }

        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let estimatedRate = try? await track.load(.estimatedDataRate), estimatedRate > 0 {
            bitRate = Double(estimatedRate) / 1000
        }

        isLoadingAudioDetails = false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
