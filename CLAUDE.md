# Terminal Sessions — Claude Code Context

## Project Overview

macOS menu bar app that captures and archives Terminal.app sessions. Built with Swift/SwiftUI, targets macOS 13.0+. Distributed via GitHub Releases with Sparkle for auto-updates.

- **Bundle ID:** `com.terminalsessions.app`
- **Current version:** 1.0 (bump `MARKETING_VERSION` in project.pbxproj for releases)
- **Deployment target:** macOS 13.0 (Ventura)+
- **GitHub repo:** `github.com/miroslavkartalski/terminal-sessions`

## Architecture

### Entry Points
- `App.swift` — `@main` entry, wires `AppDelegate` and Settings scene
- `AppDelegate.swift` — Status bar item, popover, Sparkle updater, right-click context menu

### Core Files
| File | Purpose |
|------|---------|
| `ContentView.swift` | Root SwiftUI view — header, tab bar, footer; hosts NowTabView / BookmarksTabView / HistoryTabView |
| `Models.swift` | Data types: `LiveTerminalWindow`, `LiveTerminalTab`, `Bookmark`, `HistorySnapshot`, `AITool`, `ProcessState` |
| `SessionManager.swift` | JSON persistence in `~/Library/Application Support/TerminalArchiver/` — bookmarks + history (max 30 snapshots) |
| `TerminalCapture.swift` | AppleScript bridge to Terminal.app — captures windows, parses titles, detects AI tools |
| `AIIcons.swift` | SF Symbol / custom icons for Claude Code, OpenAI Codex, Gemini |

### Design Tokens
All spacing, color, and typography constants live in `DS` enum at the top of `ContentView.swift`. Use these for all new UI — never hardcode values.

### Key Patterns
- Status bar app (`LSUIElement = true`) — no Dock icon
- Popover UI: 400×520pt, `.transient` behavior
- Left-click → toggle popover; right-click → context menu (Check for Updates, Quit)
- AI session detection via window title status characters: braille U+2800–28FF = working, `·` U+00B7 = idle, `✳` U+2733 = idle
- 3-second refresh timer while popover is open
- Auto-save to history when all Terminal windows close, or every 15 min while open

## Dependencies

- **Sparkle 2.9.x** (via SPM) — auto-update framework
  - EdDSA private key stored in macOS Keychain (generated once via `./scripts/create-release.sh keys`)
  - Public key in `Info.plist → SUPublicEDKey`
  - Appcast feed: `https://raw.githubusercontent.com/miroslavkartalski/terminal-sessions/main/appcast.xml`

## Releasing a New Version

```bash
# Bump MARKETING_VERSION in Xcode (project settings → General → Version)
./scripts/create-release.sh 1.1
# Then commit appcast.xml and create a GitHub Release tagged v1.1, attach the zip
```

The script archives, zips, signs with EdDSA, and updates `appcast.xml` automatically.

## Conventions

- Follow existing `DS.*` tokens for all spacing/color
- Keep SwiftUI views as computed `var` properties on their parent struct (not separate files) unless they exceed ~100 lines
- No third-party UI libraries — AppKit + SwiftUI only (plus Sparkle)
- Avoid adding error handling for internal paths that can't fail
- `TerminalCapture.runAppleScript()` is the single point of entry for all AppleScript execution
