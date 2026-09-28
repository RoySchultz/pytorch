import Foundation

enum InstagramURLParser {
    /// Finds the first Instagram URL in arbitrary text (e.g. a pasted share message).
    static func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            for match in detector.matches(in: trimmed, range: range) {
                if let url = match.url, isInstagramHost(url) {
                    return normalized(url)
                }
            }
        }
        if let url = URL(string: trimmed), isInstagramHost(url) {
            return normalized(url)
        }
        return nil
    }

    static func isInstagramHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com") || host == "instagr.am"
    }

    /// `instagram.com/share/...` links redirect to the real post URL.
    static func isShareLink(_ url: URL) -> Bool {
        pathParts(url).first?.lowercased() == "share"
    }

    /// Supports /p/{code}, /reel/{code}, /reels/{code}, /tv/{code} and /{user}/p/{code}.
    static func shortcode(from url: URL) -> String? {
        guard !isShareLink(url) else { return nil }
        let parts = pathParts(url)
        let markers: Set<String> = ["p", "reel", "reels", "tv"]
        for (index, part) in parts.enumerated() where markers.contains(part.lowercased()) {
            if index + 1 < parts.count, !parts[index + 1].isEmpty {
                return parts[index + 1]
            }
        }
        return nil
    }

    /// Converts a post shortcode into Instagram's numeric media ID (base64-url alphabet).
    static func mediaID(fromShortcode code: String) -> String? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var lookup: [Character: UInt64] = [:]
        for (index, char) in alphabet.enumerated() {
            lookup[char] = UInt64(index)
        }
        // Posts of private accounts carry a 28-character suffix that is not part of the ID.
        let core = code.count > 28 ? String(code.dropLast(28)) : code
        var id: UInt64 = 0
        for char in core {
            guard let value = lookup[char] else { return nil }
            let (shifted, overflow1) = id.multipliedReportingOverflow(by: 64)
            let (sum, overflow2) = shifted.addingReportingOverflow(value)
            if overflow1 || overflow2 { return nil }
            id = sum
        }
        return id == 0 ? nil : String(id)
    }

    private static func pathParts(_ url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    private static func normalized(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }
}
