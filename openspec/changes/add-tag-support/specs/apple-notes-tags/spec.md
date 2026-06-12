## ADDED Requirements

### Requirement: System SHALL provide a list_tags tool that enumerates hashtags with live-note counts

A new MCP tool `list_tags` SHALL enumerate every hashtag (`ICHashtag` entity) in `NoteStore.sqlite`, optionally filtered by account name. Each returned tag SHALL include:

- `name: String` — display form with a leading `#` (`ZDISPLAYTEXT` stores it without one)
- `standardized: String` — lowercased `ZSTANDARDIZEDCONTENT`, the matching key
- `note_count: Int` — count of non-deleted notes carrying the tag
- `accounts: [String]` — account names where the tag exists, merged by standardized content across accounts

Results SHALL be sorted by `note_count` descending, then `name` ascending (case-insensitive). Orphan tags (zero live notes) SHALL be included with `note_count: 0`. The response SHALL include `total`.

#### Scenario: Tag counts exclude deleted notes

- **WHEN** a tag appears in two live notes and one note with `ZMARKEDFORDELETION = 1`
- **THEN** `list_tags` SHALL report `note_count: 2` for that tag

#### Scenario: Same tag in two accounts is merged

- **WHEN** `#x` exists as separate ICHashtag rows in iCloud and On My Mac
- **THEN** `list_tags` without an account filter SHALL return one entry for `#x`
- **AND** its `accounts` array SHALL contain both account names
- **AND** its `note_count` SHALL sum the live notes across both accounts

#### Scenario: Account filter scopes names and counts

- **WHEN** `list_tags` is invoked with `{"account": "iCloud"}`
- **THEN** only tags present in iCloud SHALL be returned
- **AND** `note_count` SHALL count only iCloud notes

#### Scenario: Orphan tag included with zero count

- **WHEN** an ICHashtag row exists with no live note carrying it
- **THEN** `list_tags` SHALL include it with `note_count: 0`

### Requirement: System SHALL provide a get_notes_by_tag tool with any/all semantics

A new MCP tool `get_notes_by_tag` SHALL accept `tags: [String]` (leading `#` optional), `match: "any"|"all"` (default `any`), and the existing `account` / `folder` / `folder_id` / `limit` / `include_body` filter parameters. Tag matching SHALL be case-insensitive exact match against the standardized tag content — no prefix or fuzzy matching. Note objects in the response SHALL have the same shape as `list_notes` output. The response SHALL include a `warnings` array naming every input tag that matched zero hashtag entities; unknown tags SHALL NOT be an error.

#### Scenario: match=any returns the union

- **WHEN** `get_notes_by_tag` is invoked with `{"tags": ["a", "b"], "match": "any"}`
- **THEN** every note carrying `#a` or `#b` (or both) SHALL be returned

#### Scenario: match=all requires every tag

- **WHEN** `get_notes_by_tag` is invoked with `{"tags": ["a", "b"], "match": "all"}`
- **THEN** only notes carrying both `#a` and `#b` SHALL be returned

#### Scenario: Leading '#' and casing are normalized

- **WHEN** the stored tag has standardized content `DEAL-FLOW`
- **AND** the caller passes `"#deal-flow"` or `"DEAL-FLOW"` or `"deal-flow"`
- **THEN** all three inputs SHALL match the same notes

#### Scenario: Unknown tag produces a warning, not an error

- **WHEN** `get_notes_by_tag` is invoked with `{"tags": ["real-tag", "typo-tag"]}` where `typo-tag` matches no hashtag entity
- **THEN** the call SHALL succeed
- **AND** the `warnings` array SHALL name `typo-tag`

#### Scenario: Deleted notes are excluded

- **WHEN** a note carrying the queried tag is marked for deletion
- **THEN** it SHALL NOT appear in the results

### Requirement: SQLite note reads SHALL include a tags field; AppleScript reads SHALL return tags null

Notes returned by `get_note`, `list_notes`, `list_notes_quick`, and `search_notes` on the SQLite path SHALL include `tags: [String]` — literal in-note display form (e.g. `"#Deal-Flow"`), deduplicated case-insensitively per note (the same tag can occur multiple times in one note body), sorted alphabetically. The association SHALL be resolved in a single grouped query over hashtag inline attachments (`ZTYPEUTI* = 'com.apple.notes.inlinetextattachment.hashtag'`), never an N+1 per-note lookup. Non-hashtag inline attachments (mentions, links) SHALL be excluded.

When tags cannot be resolved — AppleScript-fallback reads, or a schema without hashtag entities — the `tags` field SHALL be `null`, never an empty array (an empty array falsely asserts "no tags"; only the SQLite path may emit `[]`, meaning the note verifiably has none).

#### Scenario: Repeated tag occurrences are deduplicated

- **WHEN** one note contains `#x` three times
- **THEN** its `tags` array SHALL contain `#x` exactly once

#### Scenario: Mention attachments are not tags

- **WHEN** a note contains an inline attachment with UTI `com.apple.notes.inlinetextattachment.mention`
- **THEN** that attachment SHALL NOT contribute to the note's `tags`

#### Scenario: AppleScript fallback returns null tags

- **WHEN** `get_note` serves a read via AppleScript (SQLite unavailable)
- **THEN** the response SHALL contain `"tags": null`

#### Scenario: SQLite path returns empty array for untagged note

- **WHEN** `list_notes` serves a read via SQLite and a returned note carries no tags
- **THEN** that note's `tags` SHALL equal `[]`

### Requirement: list_notes SHALL accept tags and match filter parameters

The `list_notes` tool SHALL accept optional `tags: [String]` and `match: "any"|"all"` parameters with semantics identical to `get_notes_by_tag`, composable with all existing filters (folder, account, pinned, locked, date range, shared). `get_notes_by_tag` SHALL be implemented on the same reader query path; both tool names SHALL stay exposed.

#### Scenario: Tag filter composes with account filter

- **WHEN** `list_notes` is invoked with `{"tags": ["x"], "account": "On My Mac"}`
- **THEN** only On My Mac notes carrying `#x` SHALL be returned

### Requirement: Tag features SHALL be read-only and SQLite-only with loud failures

The system SHALL NOT provide tools to create, rename, or delete tags — tags are styled inline attachments inside the note body protobuf; AppleScript cannot create them and direct SQLite writes would corrupt CloudKit sync. When the SQLite reader is unavailable (no Full Disk Access), `list_tags`, `get_notes_by_tag`, and `list_notes` with a `tags` filter SHALL throw the existing `featureRequiresSQLite` error; there SHALL be no silent degradation to text search. `Z_ENT` values SHALL be resolved at runtime from `Z_PRIMARYKEY` (never hardcoded); when `ICHashtag` or `ICInlineAttachment` cannot be resolved, tag tools SHALL fail with an error naming the missing entity while non-tag tools keep working.

#### Scenario: No FDA fails loudly

- **WHEN** SQLite is unavailable and `list_tags` is invoked
- **THEN** the tool SHALL error with a message containing `requires Full Disk Access`

#### Scenario: Tag filter without FDA fails instead of degrading

- **WHEN** SQLite is unavailable and `list_notes` is invoked with a `tags` filter
- **THEN** the tool SHALL error rather than return unfiltered or text-matched results

#### Scenario: Missing hashtag entity does not break non-tag reads

- **WHEN** the schema's `Z_PRIMARYKEY` has no `ICHashtag` / `ICInlineAttachment` rows
- **THEN** `list_tags` SHALL fail naming the missing entity
- **AND** `list_notes` without a tag filter SHALL still succeed with `tags: null` on each note
