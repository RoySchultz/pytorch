import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: DownloadViewModel
    @ObservedObject private var session = InstagramSession.shared
    @State private var showingAccount = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inputSection
                    statusSection
                    if viewModel.phase == .picking, let post = viewModel.post {
                        CarouselPickerView(post: post)
                    }
                }
                .padding()
            }
            .navigationTitle("InstaSaver")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAccount = true
                    } label: {
                        Image(systemName: session.isLoggedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
            }
            .sheet(isPresented: $showingAccount) {
                AccountView()
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plak de link van een Instagram-post, reel of carrousel. Foto's en video's worden in de hoogst beschikbare kwaliteit in je Foto's-app gezet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField("https://www.instagram.com/p/…", text: $viewModel.input)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .submitLabel(.go)
                    .onSubmit { if viewModel.canFetch { viewModel.fetch() } }
                if !viewModel.input.isEmpty {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Wissen")
                }
            }

            HStack(spacing: 12) {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        viewModel.input = text
                        viewModel.fetch()
                    }
                }
                .labelStyle(.titleAndIcon)
                .disabled(viewModel.isBusy)

                Button {
                    inputFocused = false
                    viewModel.fetch()
                } label: {
                    Label("Downloaden", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canFetch)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.phase {
        case .idle, .picking:
            EmptyView()
        case .fetching:
            HStack(spacing: 12) {
                ProgressView()
                Text("Post ophalen…")
                Spacer()
                Button("Annuleer") { viewModel.cancel() }
            }
        case let .downloading(completed, total):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                HStack {
                    Text(total == 1 ? "Downloaden in maximale kwaliteit…" : "Downloaden \(completed) van \(total)…")
                    Spacer()
                    Button("Annuleer") { viewModel.cancel() }
                }
                .font(.subheadline)
            }
        case let .done(saved, failed):
            StatusBanner(
                systemImage: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: failed == 0 ? .green : .orange,
                text: failed == 0
                    ? (saved == 1 ? "Opgeslagen in Foto's." : "\(saved) items opgeslagen in Foto's.")
                    : "\(saved) opgeslagen, \(failed) mislukt."
            )
        case let .failed(message):
            StatusBanner(systemImage: "xmark.octagon.fill", tint: .red, text: message)
        }
    }
}

private struct StatusBanner: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
            Spacer(minLength: 0)
        }
        .padding()
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
