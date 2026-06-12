# Add Tag Support (read-only)

## Why

Apple Notes tags (`#deal-flow`, `#citrus`, etc.) are a first-class organisational primitive in Notes.app — they drive the Tag Browser and Smart Folders, and heavy users organise primarily by tag rather than folder. che-apple-notes-mcp currently has zero awareness of tags: no tool lists them, no filter accepts them, and `search_notes` (SQL LIKE over title + snippet) misses tags placed below the snippet boundary in long notes.

The tag data is present and readable in the same `NoteStore.sqlite` database the server already queries for its fast-read path. This is a read-path gap, not a platform limitation.

The PRD's schema assumptions were verified against a live database (macOS 26) before implementation:

- `Z_PRIMARYKEY` contains both `ICHashtag` and `ICInlineAttachment` entities (Z_ENT 8/9 on this machine — **must be resolved dynamically, never hardcoded**)
- The hashtag inline attachment's note FK is `ZNOTE1` (`ZNOTE` is empty); the discriminator is `ZTYPEUTI1 = 'com.apple.notes.inlinetextattachment.hashtag'`
- `ZDISPLAYTEXT` has **no** leading `#` (e.g. `todo`); `ZSTANDARDIZEDCONTENT` is **uppercase** (`TODO`) — contrary to the PRD's lowercase assumption, so matching must be case-insensitive
- The hashtag entity's account FK is `ZACCOUNT2` on this schema
- All 688 hashtag attachments on this machine have `ZMARKEDFORDELETION=0`; deleted-note filtering must happen on the joined note row

## What Changes

- **New tool `list_tags`**: enumerate tags across all accounts with live-note counts (deleted notes excluded), aggregated across accounts (per-tag `accounts: [String]`), sorted by note_count desc then name asc. Orphan tags (no live notes) are included with `note_count: 0`.
- **New tool `get_notes_by_tag`**: return notes carrying the given tag(s) (`match: any|all`), composable with the existing folder / account / limit / include_body filters. Output shape matches `list_notes`, plus a `warnings` array listing input tags that matched zero hashtag entities (catches typos).
- **Tag filter on `list_notes`**: `tags: [String]?` + `match: "any"|"all"` parameters with the same semantics; `get_notes_by_tag` is implemented on the same query path (thin alias). Both tool names stay exposed — the dedicated tool name is more discoverable for LLM tool selection.
- **`tags` field on existing read tools**: on the SQLite path, every note returned by `get_note` / `list_notes` / `list_notes_quick` / `search_notes` carries `tags: [String]` (deduplicated, alphabetical). Single grouped query, no N+1. AppleScript-fallback reads return `tags: null` (**never** an empty array, which would falsely assert "no tags").
- **Error semantics**: without Full Disk Access, `list_tags`, `get_notes_by_tag`, and the `list_notes` tag filter all throw the existing `featureRequiresSQLite` error; no silent degradation to text search. Entity resolution failure (a future macOS rename) throws the existing `entityNotFound` error without affecting non-tag tools.
- **Version and docs**: bump to v0.3.0, README tool table 24 → 26, Known Limits gains "Tag creation/rename/delete: not possible — Apple stores tags in the note body protobuf; AppleScript cannot write them", CHANGELOG entry.

## Non-Goals

- **No tag writes** (create / rename / delete): tags are styled inline attachments inside the note body protobuf. AppleScript cannot create them (programmatically inserted `#text` does not activate as a tag), and writing to the SQLite database directly would corrupt CloudKit sync — same rationale as the project's existing write architecture. Read-only, documented in the README.
- **No Smart Folder evaluation**: reading `ZSMARTFOLDERQUERYJSON` and evaluating its predicate is a possible follow-up; out of scope here.
- **No AppleScript fallback for tag tools**: tags are invisible to AppleScript. Follows the existing precedent (`list_notes_quick` / `search_notes` / `get_share_metadata` error without SQLite).
- **No prefix / fuzzy tag matching**: v1 is exact match only (case-insensitive, `#`-stripped).
- **No custom normalisation**: beyond stripping the leading `#` and case-insensitive comparison against `ZSTANDARDIZEDCONTENT`, no extra unicode handling.

## Capabilities

### New Capabilities

- `apple-notes-tags`: READ capability — enumerate tags, query notes by tag, tag enrichment and tag filters on existing read tools. Entirely on the SQLite fast-read path.

### Modified Capabilities

(none — no existing spec text changes; the existing `unit-testing` / `e2e-testing` requirements naturally constrain how the new tests are written)

## Impact

- **Affected specs**:
  - New `openspec/specs/apple-notes-tags/spec.md`

- **Affected code**:
  - `Sources/CheAppleNotesMCP/NotesSQLite/SQLQueries.swift` — new hashtag / inline-attachment queries
  - `Sources/CheAppleNotesMCP/NotesSQLite/NoteEntity.swift` — new `TagSummary` struct, `Note.tags` field
  - `Sources/CheAppleNotesMCP/NotesSQLite/NotesStoreReader.swift` — new `listTags` method, note tags enrichment, tag filter on `NoteListOptions`
  - `Sources/CheAppleNotesMCP/Server.swift` — register `list_tags` / `get_notes_by_tag`, new `list_notes` parameters, `tags` in `noteToDict`, error paths
  - `Sources/CheAppleNotesMCP/Version.swift` — 0.2.0 → 0.3.0
  - `Tests/CheAppleNotesMCPTests/` — tag fixture builder + unit tests (extend NotesStoreReaderTests or new TagToolsTests; extend ServerHandlerTests)
  - `Tests/CheAppleNotesMCPE2ETests/` — env-var-gated tag E2E tests (tags cannot be created programmatically; tests run against an operator's pre-seeded tagged note)
  - `README.md` / `CHANGELOG.md` — tool table, Known Limits, release notes

- **No breaking changes**: all new tools / fields / parameters are additive.
