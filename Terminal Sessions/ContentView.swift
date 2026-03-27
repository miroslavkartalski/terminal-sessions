import SwiftUI

// MARK: - Design tokens

private enum DS {
    static let space4:  CGFloat = 4
    static let space6:  CGFloat = 6
    static let space8:  CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16

    static let textPrimary   = Color.primary
    static let textSecondary = Color(NSColor.secondaryLabelColor)
    static let textTertiary  = Color(NSColor.tertiaryLabelColor)
    static let surface       = Color(NSColor.controlBackgroundColor)
    static let divider       = Color(white: 1, opacity: 0.07)
    static let claudeAccent  = Color(red: 0.72, green: 0.42, blue: 0.90)
    static let folderBlue    = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let rowRadius: CGFloat = 6

    /// Truncates to `max` characters, appending "…" if cut.
    static func truncated(_ s: String, to max: Int = 34) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "…"
    }
}

// MARK: - Tab enum

enum AppTab: CaseIterable {
    case now, bookmarks, history
    var label: String {
        switch self { case .now: return "Now"; case .bookmarks: return "Bookmarks"; case .history: return "History" }
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var manager: SessionManager
    @State private var activeTab: AppTab = .now
    @State private var liveWindows: [LiveTerminalWindow] = []
    @State private var refreshTimer: Timer?
    @State private var previousTabCount = 0
    @State private var lastPeriodicSave = Date.distantPast
    @State private var isHoveringCredit = false
    @State private var isHoveringUpdate = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar

            Group {
                switch activeTab {
                case .now:       NowTabView(liveWindows: liveWindows)
                case .bookmarks: BookmarksTabView(liveWindows: liveWindows)
                case .history:   HistoryTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 400, height: 540)
        .environmentObject(manager)
        .onAppear {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in refresh() }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: - Header

    var header: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.folderBlue)
            Text("Terminal Sessions")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    // MARK: - Tab bar

    var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isActive = activeTab == tab
                Button(action: { activeTab = tab }) {
                    Text(tab.label)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, DS.space12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isActive ? Color(white: 1, opacity: 0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space6)
    }

    // MARK: - Footer

    var footer: some View {
        HStack(spacing: DS.space6) {
            Text("\(liveWindows.flatMap { $0.tabs }.count) terminal\(liveWindows.flatMap { $0.tabs }.count == 1 ? "" : "s") open")
                .font(.system(size: 11))
                .foregroundStyle(DS.textTertiary)
            Spacer()
            Text("v\(appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(DS.textTertiary)
            Button(action: { (NSApp.delegate as? AppDelegate)?.checkForUpdates() }) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isHoveringUpdate ? DS.folderBlue : DS.textTertiary)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringUpdate = $0 }
            .help("Check for Updates")
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(DS.textTertiary)
            Button(action: { NSWorkspace.shared.open(URL(string: "https://mirokartalski.com")!) }) {
                Text("by Miro Kartalski")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textTertiary)
                    .underline(isHoveringCredit)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringCredit = $0 }
            .help("mirokartalski.com")
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(DS.textTertiary)
            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space8)
        .padding(.bottom, DS.space10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.divider)
                .frame(height: 0.5)
        }
    }

    // MARK: - Refresh + auto-save logic

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = TerminalCapture.captureWindows()
            DispatchQueue.main.async {
                let currentCount = windows.flatMap { $0.tabs }.count

                // Auto-save to history when all windows close
                if previousTabCount > 0 && currentCount == 0 {
                    manager.addSnapshot(from: liveWindows, trigger: .closed)
                }
                // Periodic auto-save every 15 min while windows are open
                if currentCount > 0 && Date().timeIntervalSince(lastPeriodicSave) >= 900 {
                    manager.addSnapshot(from: windows, trigger: .periodic)
                    lastPeriodicSave = Date()
                }

                let liveTabs = windows.flatMap { $0.tabs }
                manager.migrateBookmarkPaths(liveTabs: liveTabs)
                liveWindows = windows
                previousTabCount = currentCount
            }
        }
    }
}

// MARK: - Now Tab

struct NowTabView: View {
    @EnvironmentObject var manager: SessionManager
    let liveWindows: [LiveTerminalWindow]

    private typealias TabEntry = (tab: LiveTerminalTab, windowId: Int)

    private var allEntries: [TabEntry] {
        liveWindows.flatMap { w in w.tabs.map { (tab: $0, windowId: w.id) } }
    }

    private var pinned: [TabEntry] {
        allEntries.filter { manager.isBookmarked(path: $0.tab.path ?? "") }
    }

    private var others: [TabEntry] {
        allEntries.filter { !manager.isBookmarked(path: $0.tab.path ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if allEntries.isEmpty {
                    emptyState
                } else {
                    if !pinned.isEmpty {
                        sectionHeader("Bookmarked")
                        ForEach(pinned, id: \.tab.id) { e in
                            NowTabRow(tab: e.tab, windowIndex: e.windowId)
                        }
                        Divider().overlay(DS.divider).padding(.horizontal, DS.space16)
                    }

                    if !others.isEmpty {
                        if !pinned.isEmpty { sectionHeader("Open") }
                        ForEach(others, id: \.tab.id) { e in
                            NowTabRow(tab: e.tab, windowIndex: e.windowId)
                        }
                    }
                }
            }
            .padding(.vertical, DS.space8)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, DS.space16)
            .padding(.top, DS.space10)
            .padding(.bottom, DS.space4)
    }

    var emptyState: some View {
        VStack(spacing: DS.space10) {
            Spacer().frame(height: 40)
            Image(systemName: "terminal").font(.system(size: 36, weight: .light)).foregroundStyle(DS.textTertiary)
            Text("No Terminal windows open").font(.system(size: 13)).foregroundStyle(DS.textSecondary)
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WorkingIndicator: View {
    private let frames = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    @State private var frameIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            Text(frames[frameIndex])
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.orange)
            Text("Working")
                .font(.system(size: 11))
                .foregroundStyle(Color.orange)
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }
}

struct NowTabRow: View {
    @EnvironmentObject var manager: SessionManager
    let tab: LiveTerminalTab
    let windowIndex: Int
    @State private var isHovering = false

    private var isBookmarked: Bool {
        guard let path = tab.path else { return false }
        return manager.isBookmarked(path: path)
    }

    private var primaryLabel: String { tab.displayName }

    var body: some View {
        HStack(spacing: DS.space12) {
            // Icon
            Group {
                if let tool = tab.aiTool {
                    AIToolIcon(tool: tool, size: 16)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.folderBlue)
                }
            }
            .frame(width: 18)
            .padding(.leading, DS.space16)

            // Text — tap to focus
            Button(action: { TerminalCapture.focusWindow(index: windowIndex) }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.space6) {
                        if tab.processState == .active { WorkingIndicator() }
                        Text(DS.truncated(primaryLabel))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .help(tab.fullTitle)
                    }
                    if let path = tab.abbreviatedPath {
                        Text(path).font(.system(size: 11)).foregroundStyle(DS.textTertiary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Bookmark button (always in layout, visible on hover or if already bookmarked)
            if let path = tab.path {
                Button(action: {
                    if isBookmarked {
                        if let bm = manager.bookmarks.first(where: { $0.path == path }) {
                            manager.removeBookmark(id: bm.id)
                        }
                    } else {
                        manager.addBookmark(path: path, name: tab.displayName)
                    }
                }) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12))
                        .foregroundStyle(isBookmarked ? DS.folderBlue : DS.textTertiary)
                }
                .buttonStyle(.plain)
                .help(isBookmarked ? "Remove bookmark" : "Bookmark this terminal")
                .opacity(isHovering || isBookmarked ? 1 : 0)
                .padding(.trailing, DS.space16)
            } else {
                Color.clear.frame(width: 28).padding(.trailing, DS.space16)
            }
        }
        .padding(.vertical, DS.space10)
        .background(
            RoundedRectangle(cornerRadius: DS.rowRadius)
                .fill(isHovering ? DS.surface : Color.clear)
                .padding(.horizontal, DS.space8)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Bookmarks Tab

struct BookmarksTabView: View {
    @EnvironmentObject var manager: SessionManager
    let liveWindows: [LiveTerminalWindow]

    private var liveTabs: [LiveTerminalTab] { liveWindows.flatMap { $0.tabs } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if manager.bookmarks.isEmpty {
                    VStack(spacing: DS.space10) {
                        Spacer().frame(height: 40)
                        Image(systemName: "bookmark").font(.system(size: 36, weight: .light)).foregroundStyle(DS.textTertiary)
                        Text("No bookmarks yet").font(.system(size: 13)).foregroundStyle(DS.textSecondary)
                        Text("Tap the bookmark icon on any open terminal")
                            .font(.system(size: 11)).foregroundStyle(DS.textTertiary)
                            .multilineTextAlignment(.center)
                        Spacer().frame(height: 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(manager.bookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark, aiTool: liveTabs.first { $0.path == bookmark.path }?.aiTool)
                    }
                }
            }
            .padding(.vertical, DS.space8)
        }
    }
}

struct BookmarkRow: View {
    @EnvironmentObject var manager: SessionManager
    let bookmark: Bookmark
    var aiTool: AITool? = nil
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.space12) {
            // Show AI tool icon if the terminal is currently open, otherwise folder
            Group {
                if let tool = aiTool {
                    AIToolIcon(tool: tool, size: 16)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.folderBlue)
                }
            }
            .frame(width: 18)
            .padding(.leading, DS.space16)

            // Tap to open in Terminal
            Button(action: { openBookmark() }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DS.truncated(bookmark.name))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(bookmark.abbreviatedPath)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(bookmark.name)

            // Remove button — visible on hover
            Button(action: { manager.removeBookmark(id: bookmark.id) }) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove bookmark")
            .opacity(isHovering ? 1 : 0)
            .padding(.trailing, DS.space16)
        }
        .padding(.vertical, DS.space10)
        .background(
            RoundedRectangle(cornerRadius: DS.rowRadius)
                .fill(isHovering ? DS.surface : Color.clear)
                .padding(.horizontal, DS.space8)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    func openBookmark() {
        let safePath = "'" + bookmark.resolvedPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(safePath) && clear"
        end tell
        """
        TerminalCapture.runAppleScript(script)
    }
}

// MARK: - History Tab

struct HistoryTabView: View {
    @EnvironmentObject var manager: SessionManager
    @State private var searchText = ""

    /// All unique tabs from history, deduped by path per day, newest day first.
    private var dayGroups: [(label: String, tabs: [HistoryTab])] {
        let cal = Calendar.current
        // Collect (date, tab) pairs
        let pairs: [(Date, HistoryTab)] = manager.history.flatMap { snap in
            snap.tabs.map { (snap.savedAt, $0) }
        }
        // Filter by search
        let filtered: [(Date, HistoryTab)] = searchText.isEmpty ? pairs : pairs.filter {
            let q = searchText.lowercased()
            return $0.1.displayName.lowercased().contains(q)
                || $0.1.abbreviatedPath.lowercased().contains(q)
        }
        // Group by day
        var buckets: [(Date, [HistoryTab])] = []
        for (date, tab) in filtered {
            let day = cal.startOfDay(for: date)
            if let idx = buckets.firstIndex(where: { cal.isDate($0.0, inSameDayAs: day) }) {
                // Deduplicate by path within the day
                if !buckets[idx].1.contains(where: { $0.path == tab.path }) {
                    buckets[idx].1.append(tab)
                }
            } else {
                buckets.append((day, [tab]))
            }
        }
        // Sort days newest first; format label
        let df = DateFormatter()
        return buckets
            .sorted { $0.0 > $1.0 }
            .map { (date, tabs) in
                let label: String
                if cal.isDateInToday(date)     { label = "Today" }
                else if cal.isDateInYesterday(date) { label = "Yesterday" }
                else { df.dateFormat = "MMMM d"; label = df.string(from: date) }
                return (label: label, tabs: tabs)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar — visually separated from tab bar
            HStack(spacing: DS.space8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textTertiary)
                TextField("Search history…", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 1, opacity: 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(white: 1, opacity: 0.10), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, DS.space12)
            .padding(.top, DS.space12)
            .padding(.bottom, DS.space4)

            if manager.history.isEmpty {
                VStack(spacing: DS.space10) {
                    Spacer().frame(height: 40)
                    Image(systemName: "clock").font(.system(size: 36, weight: .light)).foregroundStyle(DS.textTertiary)
                    Text("No history yet").font(.system(size: 13)).foregroundStyle(DS.textSecondary)
                    Text("Snapshots are saved automatically\nwhen Terminal windows close")
                        .font(.system(size: 11)).foregroundStyle(DS.textTertiary)
                        .multilineTextAlignment(.center)
                    Spacer().frame(height: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dayGroups.isEmpty {
                VStack(spacing: DS.space8) {
                    Spacer().frame(height: 30)
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 13)).foregroundStyle(DS.textSecondary)
                    Spacer().frame(height: 30)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(dayGroups, id: \.label) { group in
                            // Day header
                            Text(group.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.textTertiary)
                                .padding(.horizontal, DS.space16)
                                .padding(.top, DS.space12)
                                .padding(.bottom, DS.space4)

                            ForEach(group.tabs) { tab in
                                HistoryTabRow(tab: tab)
                            }

                            Divider().overlay(DS.divider).padding(.horizontal, DS.space16)
                        }
                    }
                    .padding(.bottom, DS.space8)
                }
            }
        }
    }
}

struct HistoryTabRow: View {
    let tab: HistoryTab
    @State private var isHovering = false

    var body: some View {
        Button(action: openTab) {
            HStack(spacing: DS.space12) {
                Group {
                    if let tool = tab.aiTool {
                        AIToolIcon(tool: tool, size: 16)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.folderBlue)
                    }
                }
                .frame(width: 18)
                .padding(.leading, DS.space16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(DS.truncated(tab.displayName))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .help(tab.fullTitle)
                    Text(tab.abbreviatedPath)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, DS.space8)
            .background(
                RoundedRectangle(cornerRadius: DS.rowRadius)
                    .fill(isHovering ? DS.surface : Color.clear)
                    .padding(.horizontal, DS.space8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func openTab() {
        let safePath = "'" + tab.resolvedPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(safePath) && clear"
        end tell
        """
        TerminalCapture.runAppleScript(script)
    }
}
