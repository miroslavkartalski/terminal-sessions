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
        bookmarks.contains { matchesBookmark($0, path: path) }
    }

    /// Fuzzy match: exact, OR bookmark is a bare fragment (no slash) that the
    /// full path ends with — handles stale bookmarks saved before a path-capture bug fix.
    private func matchesBookmark(_ bookmark: Bookmark, path: String) -> Bool {
        if bookmark.path == path { return true }
        guard !bookmark.path.contains("/") else { return false }
        return path.hasSuffix("/" + bookmark.path) || path.hasSuffix(" " + bookmark.path)
    }

    /// Called each refresh: upgrades any fragment-only bookmark paths to the
    /// full resolved path seen in the current live tabs.
    func migrateBookmarkPaths(liveTabs: [LiveTerminalTab]) {
        var changed = false
        for i in bookmarks.indices {
            guard !bookmarks[i].path.contains("/") else { continue }
            if let fullPath = liveTabs.first(where: { tab in
                guard let p = tab.path else { return false }
                return matchesBookmark(bookmarks[i], path: p)
            })?.path {
                bookmarks[i].path = fullPath
                changed = true
            }
        }
        if changed { saveBookmarks() }
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
