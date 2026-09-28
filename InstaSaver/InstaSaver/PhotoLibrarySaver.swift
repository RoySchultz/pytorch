import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Geen toegang tot Foto's. Sta 'Foto's toevoegen' toe via Instellingen > Privacy > Foto's > InstaSaver."
    }
}

enum PhotoLibrarySaver {
    static func ensureAuthorized() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.accessDenied }
    }

    /// Adds the file to the Photos library as an original resource (no re-compression).
    static func save(fileURL: URL, kind: MediaKind) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            request.addResource(with: kind == .video ? .video : .photo, fileURL: fileURL, options: options)
        }
    }
}
