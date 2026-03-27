#!/bin/bash
# create-release.sh — build, sign, and publish a new Terminal Sessions release
#
# Usage:
#   ./scripts/create-release.sh          # builds and shows next steps
#   ./scripts/create-release.sh keys     # generate EdDSA key pair (first time only)
#
# Requirements:
#   - Xcode command line tools
#   - Sparkle added via SPM (provides sign_update and generate_keys tools)
#   - SPARKLE_PRIVATE_KEY set in environment, or ~/sparkle_private_key stored on disk
#     (the private key file is never committed — keep it safe)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="Terminal Sessions.xcodeproj"
SCHEME="Terminal Sessions"
APP_NAME="Terminal Sessions"
BUILD_DIR="$REPO_ROOT/release-build"
APPCAST="$REPO_ROOT/appcast.xml"

# Sparkle tools are inside the SPM build cache after Xcode resolves packages.
# Try a few known locations.
find_sparkle_tool() {
    local tool="$1"
    local candidates=(
        "$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin/$tool"
        "$HOME/Library/Developer/Xcode/DerivedData/Terminal_Sessions-*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool"
        "$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "$tool" -path "*/Sparkle/*" 2>/dev/null | head -1)"
    )
    for c in "${candidates[@]}"; do
        # shellcheck disable=SC2086
        expanded=$(eval echo $c)
        if [ -x "$expanded" ]; then
            echo "$expanded"
            return 0
        fi
    done
    # Also check if installed globally (e.g. via Homebrew)
    if command -v "$tool" &>/dev/null; then
        command -v "$tool"
        return 0
    fi
    return 1
}

# ── Key generation (first-time setup) ───────────────────────────────────────
if [ "${1:-}" = "keys" ]; then
    GENERATE_KEYS=$(find_sparkle_tool "generate_keys" || true)
    if [ -z "$GENERATE_KEYS" ]; then
        echo "❌  generate_keys not found."
        echo "    Open the project in Xcode first so SPM resolves Sparkle, then re-run."
        exit 1
    fi
    echo "Generating EdDSA key pair…"
    "$GENERATE_KEYS"
    echo ""
    echo "✅  Done. Your private key has been saved to your Keychain."
    echo "    Copy the public key printed above into Info.plist → SUPublicEDKey."
    echo "    Also update the SUPublicEDKey placeholder in Info.plist."
    exit 0
fi

# ── Validate version arg ─────────────────────────────────────────────────────
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>   e.g.  $0 1.1"
    echo "       $0 keys        (first-time key generation)"
    exit 1
fi

BUILD_NUMBER="${2:-$VERSION}"   # optional second arg for CFBundleVersion integer

echo "▶  Building Terminal Sessions $VERSION (build $BUILD_NUMBER)…"

# ── Archive via xcodebuild ───────────────────────────────────────────────────
ARCHIVE_PATH="$BUILD_DIR/TerminalSessions-$VERSION.xcarchive"

xcodebuild archive \
    -project "$REPO_ROOT/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet

echo "✅  Archive created."

# ── Export .app ──────────────────────────────────────────────────────────────
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌  .app not found at $APP_PATH"
    exit 1
fi

ZIP_NAME="Terminal.Sessions.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "✅  Zipped: $ZIP_PATH"

# ── Sign with Sparkle ────────────────────────────────────────────────────────
SIGN_UPDATE=$(find_sparkle_tool "sign_update" || true)
if [ -z "$SIGN_UPDATE" ]; then
    echo ""
    echo "⚠️   sign_update not found. Run this after Xcode resolves Sparkle packages:"
    echo "     ./scripts/create-release.sh $VERSION"
    exit 1
fi

echo "Signing update…"
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH")
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

echo "   Signature: $SIGNATURE"
echo "   Size:      $FILE_SIZE bytes"

# ── Update appcast.xml ───────────────────────────────────────────────────────
RELEASE_URL="https://github.com/miroslavkartalski/terminal-sessions/releases/download/v${VERSION}/${ZIP_NAME}"
RELEASE_NOTES_URL="https://github.com/miroslavkartalski/terminal-sessions/releases/tag/v${VERSION}"

NEW_ITEM="        <item>
            <title>Version $VERSION</title>
            <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
            <pubDate>$PUBDATE</pubDate>
            <enclosure
                url=\"$RELEASE_URL\"
                sparkle:version=\"$BUILD_NUMBER\"
                sparkle:shortVersionString=\"$VERSION\"
                length=\"$FILE_SIZE\"
                type=\"application/octet-stream\"
                sparkle:edSignature=\"$SIGNATURE\"
            />
        </item>"

# Insert the new item right after <language>en</language>
python3 - "$APPCAST" "$NEW_ITEM" <<'PYEOF'
import sys, re

appcast_path = sys.argv[1]
new_item = sys.argv[2]

with open(appcast_path, 'r') as f:
    content = f.read()

# Insert new item before the first existing <item> block
content = re.sub(
    r'(\s*<item>)',
    '\n' + new_item + '\n\n\\1',
    content,
    count=1
)

with open(appcast_path, 'w') as f:
    f.write(content)

print("✅  appcast.xml updated.")
PYEOF

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "  Terminal Sessions $VERSION — release ready"
echo "═══════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo ""
echo "  1. Commit the updated appcast.xml:"
echo "     git add appcast.xml"
echo "     git commit -m \"Release v$VERSION\""
echo "     git push"
echo ""
echo "  2. Create a GitHub Release tagged v$VERSION"
echo "     and attach:  $ZIP_PATH"
echo ""
echo "  3. Users with the app already installed will"
echo "     be prompted to update on next launch."
echo ""
