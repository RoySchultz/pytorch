import Foundation

/// Turns the different JSON shapes Instagram returns into an `InstagramPost`,
/// always picking the highest-resolution variant of every photo and video.
///
/// Supported shapes:
/// - "v1" API items (`/api/v1/media/{id}/info/`, `?__a=1&__d=dis`,
///   `xdt_api__v1__media__shortcode__web_info`): `image_versions2.candidates`,
///   `video_versions`, `video_dash_manifest`, `carousel_media`.
/// - GraphQL `shortcode_media` / `xdt_shortcode_media`: `display_resources`,
///   `video_url`, `dash_info`, `edge_sidecar_to_children`.
enum MediaParser {
    struct Candidate {
        let url: URL
        let width: Int
        let height: Int
        var pixelCount: Int { width * height }
    }

    static func parse(json: Any, shortcode: String) -> InstagramPost? {
        if let item = findV1Item(in: json) {
            return parseV1(item, shortcode: shortcode)
        }
        if let media = findDictionary(forKeys: ["xdt_shortcode_media", "shortcode_media"], in: json) {
            return parseGraph(media, shortcode: shortcode)
        }
        return nil
    }

    // MARK: - v1 API format

    private static func parseV1(_ item: [String: Any], shortcode: String) -> InstagramPost? {
        let owner = (item["user"] as? [String: Any])?["username"] as? String
        let nodes: [[String: Any]]
        if let carousel = item["carousel_media"] as? [[String: Any]], !carousel.isEmpty {
            nodes = carousel
        } else {
            nodes = [item]
        }
        let items = nodes.enumerated().compactMap { index, node in
            parseV1Node(node, fallbackID: "\(shortcode)_\(index)")
        }
        guard !items.isEmpty else { return nil }
        return InstagramPost(shortcode: shortcode, owner: owner, items: items)
    }

    private static func parseV1Node(_ node: [String: Any], fallbackID: String) -> MediaItem? {
        let id = stringValue(node["pk"]) ?? stringValue(node["id"]) ?? fallbackID
        let imageCandidates = ((node["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]]) ?? []
        let images = candidates(imageCandidates, urlKey: "url", widthKey: "width", heightKey: "height")
        let bestImage = best(images)
        let thumbnail = thumbnail(images)?.url ?? bestImage?.url

        let videoList = (node["video_versions"] as? [[String: Any]]) ?? []
        if let bestVideo = best(candidates(videoList, urlKey: "url", widthKey: "width", heightKey: "height")) {
            let dash = (node["video_dash_manifest"] as? String).flatMap(DashManifestParser.parse)
            return MediaItem(id: id, kind: .video, url: bestVideo.url, thumbnailURL: thumbnail,
                             width: bestVideo.width, height: bestVideo.height, dash: dash)
        }

        guard let bestImage else { return nil }
        return MediaItem(id: id, kind: .photo, url: bestImage.url, thumbnailURL: thumbnail,
                         width: bestImage.width, height: bestImage.height, dash: nil)
    }

    // MARK: - GraphQL format

    private static func parseGraph(_ media: [String: Any], shortcode: String) -> InstagramPost? {
        let owner = (media["owner"] as? [String: Any])?["username"] as? String
        var nodes: [[String: Any]] = [media]
        if let sidecar = media["edge_sidecar_to_children"] as? [String: Any],
           let edges = sidecar["edges"] as? [[String: Any]] {
            let children = edges.compactMap { $0["node"] as? [String: Any] }
            if !children.isEmpty { nodes = children }
        }
        let items = nodes.enumerated().compactMap { index, node in
            parseGraphNode(node, fallbackID: "\(shortcode)_\(index)")
        }
        guard !items.isEmpty else { return nil }
        return InstagramPost(shortcode: shortcode, owner: owner, items: items)
    }

    private static func parseGraphNode(_ node: [String: Any], fallbackID: String) -> MediaItem? {
        let id = stringValue(node["id"]) ?? fallbackID
        let dimensions = node["dimensions"] as? [String: Any]
        let width = intValue(dimensions?["width"])
        let height = intValue(dimensions?["height"])

        var images = candidates((node["display_resources"] as? [[String: Any]]) ?? [],
                                urlKey: "src", widthKey: "config_width", heightKey: "config_height")
        if let display = (node["display_url"] as? String).flatMap(URL.init(string:)) {
            images.append(Candidate(url: display, width: width, height: height))
        }
        let bestImage = best(images)
        let thumbnail = thumbnail(images)?.url ?? bestImage?.url

        if boolValue(node["is_video"]), let video = (node["video_url"] as? String).flatMap(URL.init(string:)) {
            let manifest = ((node["dash_info"] as? [String: Any])?["video_dash_manifest"] as? String)
                ?? (node["video_dash_manifest"] as? String)
            let dash = manifest.flatMap(DashManifestParser.parse)
            return MediaItem(id: id, kind: .video, url: video, thumbnailURL: thumbnail,
                             width: width, height: height, dash: dash)
        }

        guard let bestImage else { return nil }
        return MediaItem(id: id, kind: .photo, url: bestImage.url, thumbnailURL: thumbnail,
                         width: bestImage.width, height: bestImage.height, dash: nil)
    }

    // MARK: - Quality selection

    static func candidates(_ list: [[String: Any]], urlKey: String, widthKey: String, heightKey: String) -> [Candidate] {
        list.compactMap { entry in
            guard let string = entry[urlKey] as? String, let url = URL(string: string) else { return nil }
            return Candidate(url: url, width: intValue(entry[widthKey]), height: intValue(entry[heightKey]))
        }
    }

    /// Largest pixel count wins; on a tie the earliest entry wins because
    /// Instagram lists its highest-quality encode first.
    static func best(_ list: [Candidate]) -> Candidate? {
        list.enumerated().max { lhs, rhs in
            if lhs.element.pixelCount != rhs.element.pixelCount {
                return lhs.element.pixelCount < rhs.element.pixelCount
            }
            return lhs.offset > rhs.offset
        }?.element
    }

    /// A small-but-sharp variant for the carousel grid.
    private static func thumbnail(_ list: [Candidate]) -> Candidate? {
        list.filter { $0.width >= 320 }.min { $0.pixelCount < $1.pixelCount }
    }

    // MARK: - JSON helpers

    private static func findV1Item(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if let items = dict["items"] as? [[String: Any]],
               let first = items.first, first["media_type"] != nil {
                return first
            }
            for value in dict.values {
                if let found = findV1Item(in: value) { return found }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let found = findV1Item(in: value) { return found }
            }
        }
        return nil
    }

    static func findDictionary(forKeys keys: [String], in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            for key in keys {
                if let found = dict[key] as? [String: Any] { return found }
            }
            for value in dict.values {
                if let found = findDictionary(forKeys: keys, in: value) { return found }
            }
        } else if let array = json as? [Any] {
            for value in array {
                if let found = findDictionary(forKeys: keys, in: value) { return found }
            }
        }
        return nil
    }

    static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func boolValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

/// Picks the best H.264/HEVC video representation and best audio track from an MPD manifest.
final class DashManifestParser: NSObject, XMLParserDelegate {
    private struct Representation {
        var mimeType: String
        var codecs: String
        var width: Int
        var height: Int
        var bandwidth: Int
        var baseURL = ""

        var isVideo: Bool { mimeType.contains("video") }
        var isAudio: Bool { mimeType.contains("audio") }
        var isPlayableOnIOS: Bool {
            codecs.isEmpty || codecs.hasPrefix("avc1") || codecs.hasPrefix("hvc1") || codecs.hasPrefix("hev1")
        }
    }

    private var setType = ""
    private var setCodecs = ""
    private var current: Representation?
    private var text = ""
    private var representations: [Representation] = []

    static func parse(_ manifest: String) -> DashSource? {
        let delegate = DashManifestParser()
        let parser = XMLParser(data: Data(manifest.utf8))
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        let videos = delegate.representations.filter { $0.isVideo && $0.isPlayableOnIOS && URL(string: $0.baseURL) != nil }
        let audios = delegate.representations.filter { $0.isAudio && URL(string: $0.baseURL) != nil }
        guard let video = videos.max(by: { ($0.width * $0.height, $0.bandwidth) < ($1.width * $1.height, $1.bandwidth) }),
              let videoURL = URL(string: video.baseURL) else { return nil }
        let audio = audios.max { $0.bandwidth < $1.bandwidth }
        return DashSource(videoURL: videoURL, audioURL: audio.flatMap { URL(string: $0.baseURL) },
                          width: video.width, height: video.height)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "AdaptationSet":
            setType = attributeDict["contentType"] ?? attributeDict["mimeType"] ?? ""
            setCodecs = attributeDict["codecs"] ?? ""
        case "Representation":
            current = Representation(
                mimeType: attributeDict["mimeType"] ?? setType,
                codecs: attributeDict["codecs"] ?? setCodecs,
                width: Int(attributeDict["width"] ?? "") ?? 0,
                height: Int(attributeDict["height"] ?? "") ?? 0,
                bandwidth: Int(attributeDict["bandwidth"] ?? "") ?? 0
            )
        case "BaseURL":
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "BaseURL":
            current?.baseURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "Representation":
            if let current { representations.append(current) }
            current = nil
        default:
            break
        }
    }
}
