import SwiftUI

@main
struct InstaSaverApp: App {
    @StateObject private var viewModel = DownloadViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .task { await InstagramSession.shared.syncCookiesFromWebView() }
        }
    }
}
