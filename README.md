# che-apple-notes-mcp

macOS Apple Notes.app MCP Server — **SQLite fast read + AppleScript safe write**, 18 tools.

## Architecture

| Path | Backend | Operations |
|------|---------|-----------|
| Read | `NoteStore.sqlite` (Core Data, direct) | `list_folders`, `list_notes`, `list_notes_quick`, `get_note`, `search_notes` |
| Write | AppleScript via `NSAppleScript` | `create_note`, `update_note`, `delete_note`, `move_note`, `*_folder`, `*_batch` |

**Why dual-track?** AppleScript round-trip is ~50 ms per call — fine for writes but painful for listing. SQLite direct read handles 1000+ notes in <10 ms. Writing to SQLite would corrupt CloudKit sync, so all writes stay on AppleScript.

If Full Disk Access isn't granted, read tools automatically fall back to AppleScript (same result, slower).

## Installation

```bash
# From source
git clone https://github.com/PsychQuant/che-apple-notes-mcp
cd che-apple-notes-mcp
make install      # builds + codesigns + places binary at ~/bin/CheAppleNotesMCP
~/bin/CheAppleNotesMCP --setup   # probe FDA + request Automation permission
```

Or via the Claude Code plugin: `claude plugin install che-apple-notes-mcp@psychquant-claude-plugins`

## Requirements

- macOS 13+
- Swift 5.9+ (for building)
- Automation permission to Notes.app (prompted on first write)
- **Recommended**: Full Disk Access — enables the SQLite fast path

## Usage

### MCP server mode (default)

```bash
~/bin/CheAppleNotesMCP
```

### CLI mode (scripting)

```bash
~/bin/CheAppleNotesMCP --cli list_folders
~/bin/CheAppleNotesMCP --cli list_notes --limit 10
~/bin/CheAppleNotesMCP --cli create_note --title "Test" --body_text "hello" --folder "Notes"
echo '{"tool":"search_notes","arguments":{"keyword":"meeting"}}' | ~/bin/CheAppleNotesMCP --cli
```

## The 18 tools

### Folders (4)
`list_folders` · `create_folder` · `update_folder` · `delete_folder`

### Notes (7)
`list_notes` · `list_notes_quick` · `get_note` · `create_note` · `update_note` · `delete_note` · `move_note`

### Search (1)
`search_notes`

### Batch (3)
`create_notes_batch` · `move_notes_batch` · `delete_notes_batch`

### Undo/Redo (3)
`undo` · `redo` · `undo_history`

## Body Format

Input accepts **either** `body_text` (auto-wrapped in `<div>`) **or** `body_html` (raw). Not both.

Output returns **both** `body_text` and `body_html` for reads with `include_body=true`.

```jsonc
// Create with plaintext
{"tool":"create_note","arguments":{"title":"Idea","body_text":"Line 1\nLine 2","folder":"Notes"}}

// Returned by get_note
{
  "id": "x-coredata://<acct>/ICNote/p123",
  "title": "Idea",
  "body_text": "Line 1\nLine 2",
  "body_html": "<div>Line 1<br>Line 2</div>",
  "created_at": "2026-04-21T10:00:00Z",
  "pinned": false,
  "locked": false
}
```

## Known Limits (v0.1.0)

- Locked notes: metadata only; body is AES-encrypted and cannot be decoded.
- Pin/unpin writes: AppleScript doesn't expose the `pinned` attribute.
- Attachments: read-only metadata; no upload/replace.
- Body HTML from SQLite: approximates via longest-UTF-8-string scan. v0.2.0 will decode attribute runs for bold/italic/link/list fidelity.
- 1 MB body cap per note.
- macOS 13/14/15 tested; protobuf schema may drift on future macOS.

## License

MIT © Che Cheng
