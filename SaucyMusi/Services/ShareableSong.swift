import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A song as shared from the app: the audio file itself (so it can be
/// AirDropped, sent in Messages or saved to Files), under a proper
/// "Artist - Title" name rather than whatever the file is called on disk.
struct ShareableSong: Transferable {
    let fileURL: URL
    let fileName: String
    let title: String
    let artist: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mp3) { song in
            SentTransferredFile(try song.namedCopy())
        }
        .exportingCondition { $0.fileURL.pathExtension.lowercased() == "mp3" }

        FileRepresentation(exportedContentType: .mpeg4Audio) { song in
            SentTransferredFile(try song.namedCopy())
        }
        .exportingCondition { $0.fileURL.pathExtension.lowercased() == "m4a" }
    }

    /// A copy of the file under its share name, in a temporary folder that's
    /// cleared on each share so copies don't pile up.
    private func namedCopy() throws -> URL {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent("Shared Songs", isDirectory: true)
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(fileName)
        try fileManager.copyItem(at: fileURL, to: copy)
        return copy
    }
}
