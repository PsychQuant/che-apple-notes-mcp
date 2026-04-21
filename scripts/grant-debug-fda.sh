#!/bin/bash
# Probe Full Disk Access (FDA) for the debug binary and guide the user through
# granting it if missing. TCC entries are keyed by CDHash, so the debug binary
# built fresh by SwiftPM is treated separately from the release binary at
# ~/bin/CheAppleNotesMCP even though both share Identifier com.checheng.CheAppleNotesMCP.
#
# Exit codes:
#   0 — FDA appears granted (SQLite read succeeded)
#   1 — FDA missing; user action required

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEBUG_BIN="$REPO_ROOT/.build/debug/CheAppleNotesMCP"
NOTESTORE="$HOME/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"

if [[ ! -x "$DEBUG_BIN" ]]; then
    echo "⚠️  $DEBUG_BIN not found — run 'make build' first."
    exit 1
fi

# Probe via the binary itself — same path the tests will use.
SETUP_OUT="$("$DEBUG_BIN" --setup 2>/dev/null || true)"

if echo "$SETUP_OUT" | grep -q "SQLite read access: ✓"; then
    echo "✅ Debug binary has FDA granted. E2E SQLite path will work."
    exit 0
fi

echo "❌ Debug binary lacks Full Disk Access."
echo
echo "The SwiftPM debug binary at"
echo "    $DEBUG_BIN"
echo "has a different CDHash than ~/bin/CheAppleNotesMCP, so macOS TCC treats"
echo "it as a separate executable and does not inherit the release binary's"
echo "FDA permission."
echo
echo "To grant:"
echo "  1. Open System Settings → Privacy & Security → Full Disk Access"
echo "  2. Click the '+' button and navigate to:"
echo "     $DEBUG_BIN"
echo "  3. Enable the toggle for the added entry"
echo "  4. Re-run 'make test-e2e'"
echo
echo "Or open the settings pane directly:"
echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles'"
echo
echo "Note: every 'make clean' or major rebuild can regenerate the binary with a"
echo "new CDHash. TCC keeps the entry by path, so re-granting is rarely needed."
exit 1
