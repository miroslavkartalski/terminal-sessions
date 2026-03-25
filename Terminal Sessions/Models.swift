import Foundation

// MARK: - Process State

enum ProcessState {
    case idle   // shell is foreground — nothing running
    case active // non-shell process is foreground — AI is doing something
}

// MARK: - Live (current open Terminal windows)

struct LiveTerminalWindow: Identifiable {
    var id: Int
    var tabs: [LiveTerminalTab]
    var hasClaudeRunning: Bool { tabs.contains { $0.hasClaudeRunning } }
}

struct LiveTerminalTab: Identifiable {
    var id: String
    var title: String        // custom title of tab (set by process via escape codes)
    var path: String?
    var tty: String
    var windowTitle: String? // full Terminal.app window title bar (richer context)
    var processState: ProcessState = .idle

    /// AI tool detected from either the tab title or the full window title.
    var aiTool: AITool? {
        let combined = (title + " " + (windowTitle ?? "")).lowercased()
        if combined.contains("claude") { return .claude }
        if combined.contains("codex")  { return .codex }
        if combined.contains("gemini") { return .gemini }
        return nil
    }

    var hasClaudeRunning: Bool { aiTool != nil }

    /// What to show in the row (stripped, dims removed). Prefers window title for context.
    var displayName: String { Self.computeDisplayName(title: title, windowTitle: windowTitle, path: path) }

    /// Full unprocessed text to show in the hover tooltip.
    var fullTitle: String { windowTitle ?? title }

    var abbreviatedPath: String? {
        guard let p = path else { return nil }
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    // MARK: - Shared display name logic (used by LiveTerminalTab + HistoryTab)

    /// Builds the display name. Uses the window title (dims-stripped) when the tab
    /// title is a generic shell/app name; otherwise uses the tab title.
    static func computeDisplayName(title: String, windowTitle: String? = nil, path: String?) -> String {
        let genericTitles: Set<String> = ["Terminal", "zsh", "bash", "fish", "sh", ""]

        // Try the full window title first — it has the most context.
        // Skip it if it stripped down to a bare number (e.g. folder "4" → "4 — 137×48" → "4"),
        // which gives no useful context; pathBasedName will do better.
        if let wt = windowTitle {
            let cleaned = stripDimensions(stripSpinners(wt))
            let isBareNumber = !cleaned.isEmpty && cleaned.allSatisfy { $0.isNumber || $0.isWhitespace }
            if !cleaned.isEmpty && !isBareNumber { return cleaned }
        }

        // Fall back to tab title if it's not generic
        let clean = stripDimensions(stripSpinners(title))
        if !clean.isEmpty && !genericTitles.contains(clean) { return clean }

        return pathBasedName(path) ?? "Terminal"
    }

    /// Removes trailing " — NNNxNNN" or " — NNN×NNN" (terminal window size).
    private static func stripDimensions(_ title: String) -> String {
        let pattern = #"\s*[—–\-]\s*\d+[x×✕]\d+\s*$"#
        if let range = title.range(of: pattern, options: .regularExpression) {
            return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// Strips braille spinner characters (U+2800–U+28FF) and known status symbols.
    private static func stripSpinners(_ title: String) -> String {
        var scalars = title.unicodeScalars
        while let first = scalars.first,
              (first.value >= 0x2800 && first.value <= 0x28FF)
                || "✳✋·".unicodeScalars.contains(first) {
            scalars = String.UnicodeScalarView(scalars.dropFirst())
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    /// Returns a display name from a path, including parent folder when the
    /// last component is short (≤ 3 chars) or a common generic subfolder name.
    static func pathBasedName(_ path: String?) -> String? {
        guard let p = path else { return nil }
        let url    = URL(fileURLWithPath: p)
        let last   = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        guard !last.isEmpty else { return nil }

        let genericFolders: Set<String> = [
            "app", "src", "web", "api", "lib", "bin",
            "dist", "build", "main", "core", "code", "ios", "android"
        ]
        if last.count <= 3 || genericFolders.contains(last.lowercased()) {
            if !parent.isEmpty && parent != "/" { return "\(parent) \(last)" }
        }
        return last
    }
}

// MARK: - Bookmarks (manual, per-path)

struct Bookmark: Codable, Identifiable {
    var id = UUID()
    var name: String
    var path: String
    var createdAt = Date()

    var folderName: String { URL(fileURLWithPath: path).lastPathComponent }
    var abbreviatedPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
    var resolvedPath: String { (path as NSString).expandingTildeInPath }
}

// MARK: - History (auto-saved snapshots)

struct HistorySnapshot: Codable, Identifiable {
    var id = UUID()
    var tabs: [HistoryTab]
    var savedAt = Date()
    var trigger: Trigger

    enum Trigger: String, Codable {
        case closed   // all Terminal windows were closed
        case periodic // periodic background save
    }

    var formattedDate: String {
        let cal = Calendar.current
        let df = DateFormatter()
        if cal.isDateInToday(savedAt) {
            df.dateFormat = "'Today at' HH:mm"
        } else if cal.isDateInYesterday(savedAt) {
            df.dateFormat = "'Yesterday at' HH:mm"
        } else {
            df.dateFormat = "MMM d 'at' HH:mm"
        }
        return df.string(from: savedAt)
    }

    var triggerLabel: String {
        switch trigger {
        case .closed:   return "terminal closed"
        case .periodic: return "auto-saved"
        }
    }
}

struct HistoryTab: Codable, Identifiable {
    var id = UUID()
    var path: String
    var title: String
    var windowTitle: String? = nil  // backward-compatible optional

    var displayName: String { LiveTerminalTab.computeDisplayName(title: title, windowTitle: windowTitle, path: path) }
    var fullTitle: String { windowTitle ?? title }
    var abbreviatedPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
    var resolvedPath: String { (path as NSString).expandingTildeInPath }
    var aiTool: AITool? {
        let combined = (title + " " + (windowTitle ?? "")).lowercased()
        if combined.contains("claude") { return .claude }
        if combined.contains("codex")  { return .codex }
        if combined.contains("gemini") { return .gemini }
        return nil
    }

    var isClaudeRunning: Bool { aiTool != nil }
}
