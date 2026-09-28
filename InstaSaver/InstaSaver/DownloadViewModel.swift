import Foundation

@MainActor
final class DownloadViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case fetching
        case picking
        case downloading(completed: Int, total: Int)
        case done(saved: Int, failed: Int)
        case failed(String)
    }

    @Published var input = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var post: InstagramPost?
    @Published var selection: Set<MediaItem.ID> = []

    private let client = InstagramClient()
    private let downloader = MediaDownloader()
    private var task: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .fetching, .downloading: return true
        default: return false
        }
    }

    var canFetch: Bool {
        !isBusy && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedItems: [MediaItem] {
        post?.items.filter { selection.contains($0.id) } ?? []
    }

    func fetch() {
        task?.cancel()
        let text = input
        task = Task { await runFetch(text) }
    }

    func downloadSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        task?.cancel()
        task = Task { await runDownload(items) }
    }

    func toggle(_ item: MediaItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func selectAll() {
        selection = Set(post?.items.map(\.id) ?? [])
    }

    func deselectAll() {
        selection = []
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = post?.isCarousel == true ? .picking : .idle
    }

    func reset() {
        task?.cancel()
        task = nil
        input = ""
        post = nil
        selection = []
        phase = .idle
    }

    private func runFetch(_ text: String) async {
        phase = .fetching
        post = nil
        selection = []
        do {
            let post = try await client.fetchPost(from: text)
            guard !Task.isCancelled else { return }
            self.post = post
            if post.isCarousel {
                // Let the user choose; everything is selected by default.
                selection = Set(post.items.map(\.id))
                phase = .picking
            } else {
                await runDownload(post.items)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func runDownload(_ items: [MediaItem]) async {
        do {
            try await PhotoLibrarySaver.ensureAuthorized()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        var saved = 0
        var failed = 0
        var lastError: Error?
        phase = .downloading(completed: 0, total: items.count)

        // Sequential so the items appear in Photos in carousel order.
        for item in items {
            if Task.isCancelled { return }
            do {
                let file = try await downloader.fetchBestFile(for: item)
                try await PhotoLibrarySaver.save(fileURL: file, kind: item.kind)
                saved += 1
            } catch {
                if Task.isCancelled { return }
                failed += 1
                lastError = error
            }
            phase = .downloading(completed: saved + failed, total: items.count)
        }

        if saved == 0, let lastError {
            phase = .failed(lastError.localizedDescription)
        } else {
            phase = .done(saved: saved, failed: failed)
        }
    }
}
