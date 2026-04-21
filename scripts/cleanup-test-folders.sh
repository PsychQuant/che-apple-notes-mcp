#!/usr/bin/env bash
# Escape hatch for E2E test folders that survived teardown.
# Iterates every account in Notes.app, finds folders whose name matches the
# fixture pattern `__CheMCPTest_*__`, and deletes them (plus contained notes).
#
# Usage: ./scripts/cleanup-test-folders.sh
#
# Safety: the pattern is strict — only folders whose name starts with
# `__CheMCPTest_` and ends with `__` are touched. User-created folders that
# don't match the pattern are left alone.

set -euo pipefail

osascript <<'APPLESCRIPT'
tell application "Notes"
    set deletedCount to 0
    repeat with a in accounts
        set folderList to folders of a
        repeat with f in folderList
            set fname to name of f
            if fname starts with "__CheMCPTest_" and fname ends with "__" then
                -- Delete notes inside first (delete folder refuses if non-empty)
                set noteList to notes of f
                repeat with n in noteList
                    delete n
                end repeat
                delete f
                set deletedCount to deletedCount + 1
            end if
        end repeat
    end repeat
    return "Deleted " & deletedCount & " fixture folders."
end tell
APPLESCRIPT
