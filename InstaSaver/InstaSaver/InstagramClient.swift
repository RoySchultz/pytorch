import Foundation

enum InstagramError: LocalizedError {
    case invalidURL
    case notFound
    case loginRequired
    case rateLimited
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Dit is geen geldige Instagram-link naar een post of reel."
        case .notFound:
            return "Geen foto's of video's gevonden. Is de post verwijderd of privé?"
        case .loginRequired:
            return "Instagram vraagt om in te loggen. Log in via het account-icoon rechtsboven en probeer het opnieuw."
        case .rateLimited:
            return "Instagram weigert tijdelijk verzoeken (te veel aanvragen). Probeer het over een paar minuten opnieuw of log in."
        case .http(let code):
            return "Instagram gaf een onverwachte fout (HTTP \(code))."
        }
    }
}

/// Fetches post metadata the same way web downloaders such as snapinsta do:
/// ask Instagram's own web endpoints for the post and read the full list of
/// encodes, then pick the largest one. Several endpoints are tried in turn
/// because Instagram regularly changes or rate-limits them.
final class InstagramClient {
    static let webAppID = "936619743392459"
    static let defaultDocID = "8845758582119845"
    static let docIDDefaultsKey = "graphqlDocID"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var docID: String {
        let stored = UserDefaults.standard.string(forKey: Self.docIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? Self.defaultDocID : stored
    }

    func fetchPost(from input: String) async throws -> InstagramPost {
        guard var url = InstagramURLParser.extractURL(from: input) else { throw InstagramError.invalidURL }
        if InstagramURLParser.isShareLink(url) {
            url = try await resolveShareLink(url)
        }
        guard let code = InstagramURLParser.shortcode(from: url) else { throw InstagramError.invalidURL }

        var strategies: [(String) async throws -> InstagramPost?] = []
        if hasCookie("sessionid") {
            // Logged-in private API returns the original upload resolution and works for
            // private accounts you follow.
            strategies.append(fetchViaMediaInfo)
        }
        strategies.append(fetchViaGraphQL)
        strategies.append(fetchViaJSONPage)
        strategies.append(fetchViaEmbed)

        var lastError: Error = InstagramError.notFound
        for strategy in strategies {
            try Task.checkCancellation()
            do {
                if let post = try await strategy(code), !post.items.isEmpty {
                    return post
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch InstagramError.notFound {
                // Keep a more informative earlier error (e.g. login required) if there is one.
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Strategies

    /// `/api/v1/media/{id}/info/` — requires a logged-in session cookie.
    private func fetchViaMediaInfo(_ code: String) async throws -> InstagramPost? {
        guard let mediaID = InstagramURLParser.mediaID(fromShortcode: code),
              let url = URL(string: "https://www.instagram.com/api/v1/media/\(mediaID)/info/") else { return nil }
        let data = try await send(makeRequest(url, shortcode: code))
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return MediaParser.parse(json: json, shortcode: code)
    }

    /// The GraphQL query the Instagram website itself uses to render a post page.
    private func fetchViaGraphQL(_ code: String) async throws -> InstagramPost? {
        guard let url = URL(string: "https://www.instagram.com/graphql/query") else { return nil }
        let lsd = "AVqbxe3J_YA"
        let variables = #"{"shortcode":"\#(code)","fetch_tagged_user_count":null,"hoisted_comment_id":null,"hoisted_reply_id":null}"#
        let form: [(String, String)] = [
            ("av", "0"),
            ("__d", "www"),
            ("__user", "0"),
            ("__a", "1"),
            ("__comet_req", "7"),
            ("lsd", lsd),
            ("fb_api_caller_class", "RelayModern"),
            ("fb_api_req_friendly_name", "PolarisPostActionLoadPostQueryQuery"),
            ("variables", variables),
            ("server_timestamps", "true"),
            ("doc_id", docID),
        ]

        var request = makeRequest(url, shortcode: code)
        request.httpMethod = "POST"
        request.httpBody = Data(formEncode(form).utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(lsd, forHTTPHeaderField: "X-FB-LSD")
        request.setValue("129477", forHTTPHeaderField: "X-ASBD-ID")
        request.setValue("PolarisPostActionLoadPostQueryQuery", forHTTPHeaderField: "X-FB-Friendly-Name")
        request.setValue("https://www.instagram.com", forHTTPHeaderField: "Origin")

        let data = try await send(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let post = MediaParser.parse(json: json, shortcode: code) {
            return post
        }
        // `xdt_shortcode_media: null` means the post is private or needs a login.
        if let root = json as? [String: Any], let dataObject = root["data"] as? [String: Any],
           dataObject["xdt_shortcode_media"] is NSNull {
            throw InstagramError.loginRequired
        }
        return nil
    }

    /// Legacy `?__a=1&__d=dis` JSON variant of the post page.
    private func fetchViaJSONPage(_ code: String) async throws -> InstagramPost? {
        guard let url = URL(string: "https://www.instagram.com/p/\(code)/?__a=1&__d=dis") else { return nil }
        let data = try await send(makeRequest(url, shortcode: code))
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return MediaParser.parse(json: json, shortcode: code)
    }

    /// Public embed page; contains the GraphQL media object as escaped JSON, or at least an image srcset.
    private func fetchViaEmbed(_ code: String) async throws -> InstagramPost? {
        guard let url = URL(string: "https://www.instagram.com/p/\(code)/embed/captioned/") else { return nil }
        var request = makeRequest(url, shortcode: code)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        if let context = Self.extractContextJSON(from: html),
           let post = MediaParser.parse(json: context, shortcode: code) {
            return post
        }
        if let image = Self.largestEmbeddedImage(in: html) {
            let item = MediaItem(id: code, kind: .photo, url: image.url, thumbnailURL: image.url,
                                 width: image.width, height: image.height, dash: nil)
            return InstagramPost(shortcode: code, owner: nil, items: [item])
        }
        return nil
    }

    // MARK: - Networking

    private func resolveShareLink(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        guard let final = response.url else { throw InstagramError.invalidURL }
        if final.path.contains("/accounts/login"),
           let next = URLComponents(url: final, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "next" })?.value,
           let target = URL(string: next, relativeTo: URL(string: "https://www.instagram.com")) {
            return target.absoluteURL
        }
        return final
    }

    private func makeRequest(_ url: URL, shortcode: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.webAppID, forHTTPHeaderField: "X-IG-App-ID")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("nl-NL,nl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.instagram.com/p/\(shortcode)/", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let csrf = cookieValue("csrftoken") {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InstagramError.notFound }
        if let finalURL = http.url, finalURL.path.contains("/accounts/login") {
            throw InstagramError.loginRequired
        }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw InstagramError.loginRequired
        case 404: throw InstagramError.notFound
        case 429: throw InstagramError.rateLimited
        default: throw InstagramError.http(http.statusCode)
        }
    }

    private func cookieValue(_ name: String) -> String? {
        guard let url = URL(string: "https://www.instagram.com") else { return nil }
        return HTTPCookieStorage.shared.cookies(for: url)?.first { $0.name == name && !$0.value.isEmpty }?.value
    }

    private func hasCookie(_ name: String) -> Bool {
        cookieValue(name) != nil
    }

    private func formEncode(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    // MARK: - Embed page parsing

    /// Decodes the `"contextJSON":"…"` string literal embedded in the embed page.
    static func extractContextJSON(from html: String) -> Any? {
        guard let start = html.range(of: "\"contextJSON\":\"") else { return nil }
        var index = start.upperBound
        var escaped = false
        var end: String.Index?
        while index < html.endIndex {
            let char = html[index]
            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                end = index
                break
            }
            index = html.index(after: index)
        }
        guard let end else { return nil }
        let literal = "\"" + String(html[start.upperBound..<end]) + "\""
        guard let literalData = literal.data(using: .utf8),
              let inner = try? JSONSerialization.jsonObject(with: literalData, options: .fragmentsAllowed) as? String,
              let innerData = inner.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: innerData)
    }

    static func largestEmbeddedImage(in html: String) -> MediaParser.Candidate? {
        guard let tagRegex = try? NSRegularExpression(pattern: "<img[^>]*EmbeddedMediaImage[^>]*>"),
              let srcsetRegex = try? NSRegularExpression(pattern: "srcset=\"([^\"]+)\"") else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let tagMatch = tagRegex.firstMatch(in: html, range: range),
              let tagRange = Range(tagMatch.range, in: html) else { return nil }
        let tag = String(html[tagRange])
        let tagNSRange = NSRange(tag.startIndex..., in: tag)
        guard let srcsetMatch = srcsetRegex.firstMatch(in: tag, range: tagNSRange),
              let srcsetRange = Range(srcsetMatch.range(at: 1), in: tag) else { return nil }

        let candidates: [MediaParser.Candidate] = tag[srcsetRange]
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(separator: ",")
            .compactMap { entry in
                let parts = entry.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard let first = parts.first, let url = URL(string: String(first)) else { return nil }
                let width = parts.count > 1 ? Int(parts[1].dropLast()) ?? 0 : 0
                return MediaParser.Candidate(url: url, width: width, height: width)
            }
        return MediaParser.best(candidates)
    }
}
