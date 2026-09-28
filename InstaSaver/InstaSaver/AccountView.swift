import SwiftUI
import WebKit

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = InstagramSession.shared
    @AppStorage(InstagramClient.docIDDefaultsKey) private var docID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if session.isLoggedIn {
                        Label("Ingelogd bij Instagram", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Uitloggen", role: .destructive) {
                            Task { await session.logout() }
                        }
                    } else {
                        NavigationLink("Inloggen bij Instagram") {
                            LoginWebView()
                        }
                    }
                } footer: {
                    Text("Inloggen is optioneel. Het helpt als Instagram verzoeken blokkeert, en is nodig voor posts van privé-accounts die je volgt. Je gegevens blijven op dit toestel.")
                }

                Section {
                    TextField(InstagramClient.defaultDocID, text: $docID)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Geavanceerd: GraphQL doc_id")
                } footer: {
                    Text("Alleen aanpassen als Instagram zijn interne query-ID heeft gewijzigd. Leeg laten voor de standaardwaarde.")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}

private struct LoginWebView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = InstagramSession.shared

    var body: some View {
        InstagramWebView {
            Task {
                await session.syncCookiesFromWebView()
                if session.isLoggedIn { dismiss() }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Inloggen")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            Task { await session.syncCookiesFromWebView() }
        }
    }
}

private struct InstagramWebView: UIViewRepresentable {
    let onPageLoaded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageLoaded: onPageLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://www.instagram.com/accounts/login/") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onPageLoaded: () -> Void

        init(onPageLoaded: @escaping () -> Void) {
            self.onPageLoaded = onPageLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageLoaded()
        }
    }
}
