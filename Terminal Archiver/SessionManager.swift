import Foundation

class SessionManager: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    @Published var history: [HistorySnapshot] = []

    private let bookmarksURL: URL
    private let historyURL: URL
    private let maxSnapshots = 30

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TerminalArchiver")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        bookmarksURL = dir.appendingPathComponent("bookmarks.json")
        historyURL   = dir.appendingPathComponent("history.json")
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: bookmarksURL),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([HistorySnapshot].self, from: data) {
            history = decoded
        }
    }

    // MARK: - Bookmarks

    func addBookmark(path: String, name: String) {
        guard !bookmarks.contains(where: { $0.path == path }) else { return }
        bookmarks.insert(Bookmark(name: name, path: path), at: 0)
        saveBookmarks()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    func isBookmarked(path: String) -> Bool {
        bookmarks.contains { $0.path == path }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            try? data.write(to: bookmarksURL, options: .atomic)
        }
    }

    // MARK: - History

    func addSnapshot(from windows: [LiveTerminalWindow], trigger: HistorySnapshot.Trigger) {
        let tabs = windows.flatMap { $0.tabs }.compactMap { tab -> HistoryTab? in
            guard let path = tab.path else { return nil }
            return HistoryTab(path: path, title: tab.title, windowTitle: tab.windowTitle)
        }
        guard !tabs.isEmpty else { return }

        // Don't duplicate: skip if identical paths as last snapshot
        if let last = history.first {
            let lastPaths = Set(last.tabs.map { $0.path })
            let newPaths  = Set(tabs.map { $0.path })
            if lastPaths == newPaths { return }
        }

        let snapshot = HistorySnapshot(tabs: tabs, trigger: trigger)
        history.insert(snapshot, at: 0)

        // Prune oldest
        if history.count > maxSnapshots {
            history = Array(history.prefix(maxSnapshots))
        }
        saveHistory()
    }

    func removeSnapshot(id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
