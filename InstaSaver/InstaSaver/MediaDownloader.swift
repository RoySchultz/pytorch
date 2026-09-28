import AVFoundation
import Foundation

enum DownloadError: LocalizedError {
    case badResponse(Int)
    case muxFailed

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Downloaden mislukt (HTTP \(code))."
        case .muxFailed:
            return "Kon video en audio niet samenvoegen."
        }
    }
}

/// Downloads media files to a temporary location, ready to be handed to Photos.
final class MediaDownloader {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns a local file with the best available quality for `item`.
    func fetchBestFile(for item: MediaItem) async throws -> URL {
        if item.kind == .video, let dash = item.dash, dash.pixelCount > item.width * item.height {
            do {
                return try await downloadDash(dash)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall back to the progressive MP4 below.
            }
        }
        return try await download(item.url, fallbackExtension: item.kind == .video ? "mp4" : "jpg")
    }

    private func downloadDash(_ dash: DashSource) async throws -> URL {
        let video = try await download(dash.videoURL, fallbackExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: video) }
        var audio: URL?
        if let audioURL = dash.audioURL {
            audio = try await download(audioURL, fallbackExtension: "m4a")
        }
        defer { if let audio { try? FileManager.default.removeItem(at: audio) } }

        let output = Self.temporaryFile(extension: "mp4")
        try await VideoMuxer.mux(video: video, audio: audio, output: output)
        return output
    }

    private func download(_ url: URL, fallbackExtension: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(InstagramClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")
        // Ask for JPEG so Photos gets a universally compatible original rather than WebP.
        request.setValue("image/jpeg,image/*;q=0.8,video/*,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let (temporary, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw DownloadError.badResponse(http.statusCode)
        }
        let ext = Self.fileExtension(for: response.mimeType) ?? fallbackExtension
        let destination = Self.temporaryFile(extension: ext)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    static func temporaryFile(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InstaSaver-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    private static func fileExtension(for mimeType: String?) -> String? {
        switch mimeType?.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/webp": return "webp"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
        default: return nil
        }
    }
}

/// Combines a video-only and an audio-only stream into one MP4 without re-encoding.
enum VideoMuxer {
    static func mux(video videoURL: URL, audio audioURL: URL?, output: URL) async throws {
        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(withMediaType: .video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw DownloadError.muxFailed }
        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        if let audioURL {
            let audioAsset = AVURLAsset(url: audioURL)
            if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let compositionAudio = composition.addMutableTrack(withMediaType: .audio,
                                                                  preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = try await audioAsset.load(.duration)
                let duration = CMTimeMinimum(videoDuration, audioDuration)
                try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
            }
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw DownloadError.muxFailed
        }
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await export.export()
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw export.error ?? DownloadError.muxFailed
        }
    }
}
