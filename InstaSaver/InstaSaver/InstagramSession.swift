import Foundation
import WebKit

/// Optional Instagram login. Cookies from the login web view are copied into
/// `HTTPCookieStorage.shared`, which `URLSession.shared` uses for API requests.
@MainActor
final class InstagramSession: ObservableObject {
    static let shared = InstagramSession()

    @Published private(set) var isLoggedIn = false

    private init() {
        isLoggedIn = Self.hasSessionCookie()
    }

    func syncCookiesFromWebView() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("instagram.com") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        isLoggedIn = Self.hasSessionCookie()
    }

    func logout() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("instagram") })
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.contains("instagram.com") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        isLoggedIn = false
    }

    private static func hasSessionCookie() -> Bool {
        guard let url = URL(string: "https://www.instagram.com") else { return false }
        return HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "sessionid" && !$0.value.isEmpty } ?? false
    }
}
