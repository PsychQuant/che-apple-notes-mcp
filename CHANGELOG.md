# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-12

### Added (Apple Notes Tags, read-only)

- **2 new tools** for hashtag visibility (capability `apple-notes-tags`, spec in `openspec/changes/add-tag-support/specs/`):
  - `list_tags` — every hashtag (`ICHashtag` entity) with live-note counts, merged across accounts (per-tag `accounts` array), orphan tags included with `note_count: 0`, sorted by count desc then name asc
  - `get_notes_by_tag` — notes carrying the given tag(s); `match: any|all`, leading `#` optional, case-insensitive exact match, composable with folder/account/limit/include_body; response carries a `warnings` array naming input tags that match no known hashtag (typo guard) — unknown tags are not an error
- **`tags` filter on `list_notes`** (`tags: [String]` + `match: any|all`), composable with all existing filters; `get_notes_by_tag` rides the same reader query path
- **`tags: [String]` field on every SQLite note read** (`get_note`, `list_notes`, `list_notes_quick`, `search_notes`) — literal in-note form (e.g. `"#Deal-Flow"`), deduplicated case-insensitively per note, sorted alphabetically; resolved via a single grouped query over hashtag inline attachments (no N+1). AppleScript-fallback reads return `tags: null`, never `[]` — null means "unknowable", `[]` means "verifiably none"
- New SQL: hashtag entity / inline-attachment queries filter strictly on `ZTYPEUTI* = 'com.apple.notes.inlinetextattachment.hashtag'` (mentions and links excluded) and exclude `ZMARKEDFORDELETION` rows on both the attachment and the joined note

### Changed

- Schema-drift handling extended to tag columns: note FK `COALESCE(ZNOTE1, ZNOTE)`, UTI `COALESCE(ZTYPEUTI1, ZTYPEUTI)`, hashtag account FK `COALESCE(ZACCOUNT3, ZACCOUNT2, ZACCOUNT1, ZACCOUNT)` (ZACCOUNT3 verified live on macOS 26). `ICHashtag` / `ICInlineAttachment` entity IDs resolved at runtime from `Z_PRIMARYKEY` like all other entities — no hardcoded `Z_ENT` values
- Tag enrichment on note reads is best-effort: a schema without hashtag entities leaves `tags: null` without failing the read; the dedicated tag tools fail loudly (`entityNotFound`) instead
- Without Full Disk Access, `list_tags` / `get_notes_by_tag` / `list_notes` with a `tags` filter throw `featureRequiresSQLite` — no silent degradation to text search
- `ToolCoverageE2ETests.expectedToolNames` brought back in sync with the server (was missing the three v0.2.0 sharing tools)

### Explicitly NOT Implemented (spec SHALL NOT)

- Tag creation / rename / delete — tags live in the note body protobuf as styled inline attachments; AppleScript cannot create them (programmatic `#text` does not activate) and direct SQLite writes would corrupt CloudKit sync
- Smart Folder predicate evaluation (`ZSMARTFOLDERQUERYJSON`) — possible follow-up
- Prefix / fuzzy tag matching — v1 is exact match only

### Tests

- **129 unit tests** (up from 112): new `TagSupportTests` (14 tests against a temp SQLite fixture with hashtag entities, duplicate occurrences, a mention attachment that must be excluded, a deleted note carrying a tag, the same tag across two accounts, and missing-entity schemas) + 2 handler error-path tests in `ServerHandlerTests`
- **5 new E2E tests** (`TagToolsE2ETests`): 3 shape tests always run; 2 content tests gate behind `CHE_MCP_TAG_E2E_TAG=<tag>` pointing at a manually pre-seeded tagged note (tags cannot be created programmatically) and are visibly skipped otherwise

## [0.2.0] - 2026-04-22

### Added (Apple Notes Sharing, fully spec-driven)

- **6 new tools** for CloudKit share visibility + creation assistance:
  - `get_share_metadata` — reads ZICINVITATION row (shareURL, invitation counts, receivedDate, serverShareDataPresent) without deserializing the CKShare BLOB
  - `prepare_share_note` / `prepare_share_folder` — activate Notes.app, focus target, trigger `File → Share Note...` / `Share Folder...` menu so the user completes invitations manually (spec forbids auto-fill)
  - `list_folders` / `list_notes` / `search_notes` accept an optional `shared: bool?` filter
- **Read tools emit `shared: Bool`** on every folder and note (derived from AppleScript `shared` property + SQLite heuristic on `ZSERVERSHAREDATA` / `ZZONEOWNERNAME`)
- New capabilities `apple-notes-sharing-metadata` + `apple-notes-sharing-workflow` in `openspec/specs/`

### Changed

- `NotesStoreReader.getShareMetadata` uses a two-stage lookup: `ZICINVITATION` row (if exists) → heuristic fallback (`ZSERVERSHAREDATA IS NOT NULL OR ZZONEOWNERNAME IS NOT NULL`).
- `SQLQueries.listFolders` split into `listFoldersBase` + `listFoldersOrderSuffix` so the shared filter inserts predicates via composition instead of a fragile `replacingOccurrences` anchor search.
- `sharedRootObjectHeuristic` SQL now filters by `Z_ENT IN (:noteEntityID, :folderEntityID)` to defend against theoretical UUID collision across entity kinds.
- `handleGetShareMetadata` rejects AppleScript-URL-form identifiers (`x-coredata://…`) loudly with a `invalidArgument` error pointing callers at the raw `uuid` field, instead of silently returning `{isShared: false}`.
- AppleScript fallback path for `list_folders` / `list_notes` now throws `featureRequiresSQLite("…shared filter")` when the `shared` param is set but FDA is unavailable; previously dropped the filter silently.
- `deleteFolderRemovesAnEmptyFolder` E2E assertion switched from raw-string `contains` to `JSONDecoder` (the server uses prettyPrinted output, so `"deleted":true` never matched — regression since v0.1.0).

### Explicitly NOT Implemented (spec SHALL NOT)

- `create_share_link`, `invite_participant`, `revoke_share`, `list_participants` — Notes.app's CloudKit container is private; no public API path exists. The workflow-helper pair is the intended escape valve.

### Tests

- **112 unit tests** (up from 86 at v0.1.0) including new `NotesStoreReaderTests` (4 integration tests against temp SQLite fixtures) and `ServerHandlerTests` (5 handler error-path tests via a new `init(sqlite:)` test seam).
- **11 E2E tests** (up from 7), adding `ShareMetadataE2ETests`.

### Known Limits (carried from v0.1.0)

- Locked notes: body decode skipped (AES-encrypted)
- Pin/unpin writes: AppleScript limitation

## [0.1.0] - 2026-04-21

### Added

- Initial release
- **Dual-track architecture**: SQLite fast read + AppleScript safe write
- **18 MCP tools**:
  - Folders: `list_folders`, `create_folder`, `update_folder`, `delete_folder`
  - Notes: `list_notes`, `list_notes_quick`, `get_note`, `create_note`, `update_note`, `delete_note`, `move_note`
  - Search: `search_notes`
  - Batch: `create_notes_batch`, `move_notes_batch`, `delete_notes_batch`
  - Undo/Redo: `undo`, `redo`, `undo_history`
- **Body dual-track**: `body_text` or `body_html` input; both returned on read
- **Capability detection**: auto-probe Full Disk Access at startup, fall back to AppleScript for reads when denied
- **Account disambiguation**: `account` parameter for folder name collisions across iCloud / On My Mac
- `--cli` mode for direct tool invocation without MCP server
- `--setup` mode: probe FDA + trigger Automation permission dialog
- `--version` / `--help`

### Known Limits (v0.1.0)

- Locked notes: body decode skipped (AES-encrypted)
- Pin/unpin writes: AppleScript limitation
- Attachment writes: not supported
- Body HTML from SQLite: plaintext-fidelity only; v0.2.0 will render attribute runs
- 1 MB body cap
