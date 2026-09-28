import Foundation

enum MediaKind: String, Hashable {
    case photo
    case video
}

/// Separate video + audio streams from Instagram's DASH manifest. Instagram often
/// serves its highest resolution only through DASH, so we mux these ourselves.
struct DashSource: Hashable {
    let videoURL: URL
    let audioURL: URL?
    let width: Int
    let height: Int

    var pixelCount: Int { width * height }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let kind: MediaKind
    /// Highest-quality single-file URL (JPEG for photos, progressive MP4 for videos).
    let url: URL
    let thumbnailURL: URL?
    let width: Int
    let height: Int
    /// Optional higher-quality DASH streams for videos.
    let dash: DashSource?

    var bestWidth: Int { max(width, dash?.width ?? 0) }
    var bestHeight: Int { max(height, dash?.height ?? 0) }
}

struct InstagramPost: Hashable {
    let shortcode: String
    let owner: String?
    let items: [MediaItem]

    var isCarousel: Bool { items.count > 1 }
}
