import Foundation
import AppKit

enum TerminalCapture {

    // MARK: - Live capture

    static func captureWindows() -> [LiveTerminalWindow] {
        let script = """
        tell application "Terminal"
            set output to ""
            set wCount to count of windows
            repeat with wIdx from 1 to wCount
                try
                    set w to window wIdx
                    set winTitle to name of w
                    set tCount to count of tabs of w
                    repeat with tIdx from 1 to tCount
                        try
                            set t to tab tIdx of w
                            set theTTY to tty of t
                            set theTitle to custom title of t
                            set output to output & wIdx & "|||" & theTitle & "|||" & theTTY & "|||" & winTitle & linefeed
                        end try
                    end repeat
                end try
            end repeat
            return output
        end tell
        """

        guard let result = runAppleScript(script), !result.isEmpty else { return [] }

        var windowMap: [Int: [LiveTerminalTab]] = [:]

        for line in result.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 3,
                  let windowIdx = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }

            let title     = parts[1].trimmingCharacters(in: .whitespaces)
            let tty       = parts[2].trimmingCharacters(in: .whitespaces)
            // parts[3...] joined handles window titles that might contain "|||"
            let winTitle  = parts.count >= 4
                ? parts[3...].joined(separator: "|||").trimmingCharacters(in: .whitespaces)
                : ""
            let path = getWorkingDir(forTTY: tty)
            let state = getProcessState(forTTY: tty,
                                        windowTitle: winTitle.isEmpty ? nil : winTitle,
                                        tabTitle: title.isEmpty ? nil : title)

            let tab = LiveTerminalTab(id: tty, title: title, path: path, tty: tty,
                                     windowTitle: winTitle.isEmpty ? nil : winTitle,
                                     processState: state)
            windowMap[windowIdx, default: []].append(tab)
        }

        return windowMap
            .sorted { $0.key < $1.key }
            .map { LiveTerminalWindow(id: $0.key, tabs: $0.value) }
    }

    // MARK: - Focus window

    static func focusWindow(index: Int) {
        let script = """
        tell application "Terminal"
            set index of window \(index) to 1
            activate
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Helpers

    @discardableResult
    static func runAppleScript(_ source: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-"]
        let inPipe  = Pipe()
        let outPipe = Pipe()
        task.standardInput  = inPipe
        task.standardOutput = outPipe
        task.standardError  = Pipe()
        try? task.run()
        inPipe.fileHandleForWriting.write(source.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
        task.waitUntilExit()
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        return output?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escapePath(_ path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Determines whether the TTY is idle or active.
    ///
    /// Claude Code sets the tab custom title starting with a status character:
    ///   ✳ (U+2733)       = idle, waiting for user input
    ///   · (U+00B7)       = thinking / tool use in progress
    ///   braille U+2800–28FF = spinning / actively processing
    ///
    /// The window title (name of w) prepends the directory, so the status char
    /// appears after the first " — " separator: "Dir — · Task — processes"
    /// We check both the raw tab title AND the post-separator part of the window title.
    static func getProcessState(forTTY tty: String, windowTitle: String?, tabTitle: String?) -> ProcessState {
        // ✳ U+2733 = explicit idle marker
        let idleMarker: UInt32 = 0x2733

        func statusScalar(in s: String) -> UInt32? {
            // Check character after first " — " (window title format)
            if let r = s.range(of: " — ") {
                if let v = s[r.upperBound...].unicodeScalars.first?.value { return v }
            }
            // Fallback: first character (tab custom title format)
            return s.unicodeScalars.first?.value
        }

        for candidate in [tabTitle, windowTitle].compactMap({ $0 }) {
            guard let sc = statusScalar(in: candidate) else { continue }
            if sc == idleMarker { return .idle }                       // ✳ = explicitly idle
            if sc >= 0x2800 && sc <= 0x28FF { return .active }        // braille spinner
            if sc == 0x00B7 { return .active }                        // · middle dot = thinking
        }

        // Fallback: foreground process in R (running on CPU) state
        let ttyShort = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        let shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "login"]
        let output = run("ps -t \(ttyShort) -o stat=,comm= 2>/dev/null")
        for line in output.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            guard parts.count >= 2 else { continue }
            let stat = parts[0], comm = URL(fileURLWithPath: parts[1]).lastPathComponent
            if stat.contains("+") && stat.hasPrefix("R") && !shells.contains(comm) { return .active }
        }
        return .idle
    }

    static func getWorkingDir(forTTY tty: String) -> String? {
        let ttyShort = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty

        // First try: find a shell process (zsh/bash/fish) on this TTY
        let shellPid = run(
            "ps -t \(ttyShort) -o pid=,comm= 2>/dev/null | awk '$2~/zsh|bash|fish/{print $1; exit}'"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback: any first process on the TTY
        let anyPid = run(
            "ps -t \(ttyShort) -o pid= 2>/dev/null | grep -v '^ *$' | head -1"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let pid = shellPid.isEmpty ? anyPid : shellPid
        guard !pid.isEmpty else { return nil }

        // -Fn outputs just the filename field prefixed with "n", one per line — handles spaces in paths
        let cwd = run("lsof -a -d cwd -p \(pid) -Fn 2>/dev/null | grep '^n' | head -1 | cut -c2-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cwd.isEmpty ? nil : cwd
    }

    private static func run(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
