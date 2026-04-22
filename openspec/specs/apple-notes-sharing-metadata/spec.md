# apple-notes-sharing-metadata Specification

## Purpose

TBD - created by archiving change 'apple-notes-sharing-scope'. Update Purpose after archive.

## Requirements

### Requirement: System SHALL expose shared status on every note and folder read output

The read tools `list_folders`, `list_notes`, `list_notes_quick`, `get_note`, and `search_notes` SHALL include a `shared` field of type Bool on every item in their response payload. The value SHALL be derived via the following precedence:

1. When AppleScript is the source of truth, `shared of <folder|note>` is used directly.
2. When SQLite is the source, the heuristic `ZSERVERSHAREDATA IS NOT NULL OR ZZONEOWNERNAME IS NOT NULL` is used.

#### Scenario: AppleScript source returns shared=true for a collaborated folder

- **WHEN** a folder has an active CloudKit share
- **AND** AppleScript is the source path
- **THEN** the folder response SHALL contain `"shared": true`

#### Scenario: SQLite heuristic returns shared=false for an unshared note

- **WHEN** a note has neither `ZSERVERSHAREDATA` nor `ZZONEOWNERNAME` populated
- **AND** SQLite is the source path
- **THEN** the note response SHALL contain `"shared": false`

#### Scenario: Both paths return consistent results for the same item

- **WHEN** both AppleScript and SQLite are available
- **AND** a note is queried
- **THEN** the two paths SHALL produce the same `shared` value for the same note


<!-- @trace
source: apple-notes-sharing-scope
updated: 2026-04-22
code:
  - Sources/CheAppleNotesMCP/NotesSQLite/NotesStoreReader.swift
  - Sources/CheAppleNotesMCP/Sharing/ShareMetadata.swift
  - Tests/CheAppleNotesMCPE2ETests/ShareMetadataE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NotesStoreReaderTests.swift
  - Tests/CheAppleNotesMCPTests/ShareMetadataTests.swift
  - Sources/CheAppleNotesMCP/AppleScript/NotesController.swift
  - Sources/CheAppleNotesMCP/AppleScript/NoteScriptBuilder.swift
  - Sources/CheAppleNotesMCP/Server.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Sources/CheAppleNotesMCP/NotesSQLite/SQLQueries.swift
  - Tests/CheAppleNotesMCPTests/ServerHandlerTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
-->

---
### Requirement: System SHALL provide a get_share_metadata tool that returns ZICINVITATION metadata

A new MCP tool `get_share_metadata` SHALL accept a note or folder identifier and return a JSON object containing the corresponding `ZICINVITATION` row fields when one exists. The returned object SHALL include at minimum:

- `isShared: Bool` — derived from presence of invitation or heuristic
- `rootObjectType: String?` — `"note"` or `"folder"` from `ZROOTOBJECTTYPE`
- `title: String?` — from `ZTITLE`
- `snippet: String?` — from `ZSNIPPET`
- `shareURL: String?` — from `ZSHAREURL` (the public share URL Notes.app uses for invitations)
- `noteCount: Int?` — from `ZNOTECOUNT`
- `subfolderCount: Int?` — from `ZSUBFOLDERCOUNT`
- `receivedDate: String?` — ISO-8601 from `ZRECEIVEDDATE`
- `serverShareDataPresent: Bool` — whether `ZSERVERSHAREDATA` is non-null; the tool MUST NOT deserialize the BLOB

When the identifier refers to an item that has no `ZICINVITATION` row, the tool SHALL return `{"isShared": false}` with all other fields absent or null.

#### Scenario: Tool returns full metadata when item is shared

- **WHEN** `get_share_metadata` is invoked with an identifier that maps to a `ZICINVITATION` row with `ZSHAREURL` populated
- **THEN** the response SHALL include `shareURL` containing the URL value
- **AND** the response SHALL include `isShared: true`

#### Scenario: Tool returns not-shared response for regular item

- **WHEN** `get_share_metadata` is invoked with an identifier of a note that has never been shared
- **THEN** the response SHALL equal `{"isShared": false}` (with optional fields omitted or null)

#### Scenario: Tool does not deserialize CKShare BLOB

- **WHEN** `get_share_metadata` is invoked for any shared item
- **THEN** the response SHALL NOT include a decoded representation of `ZSERVERSHAREDATA`
- **AND** the response SHALL include `serverShareDataPresent` as a Bool


<!-- @trace
source: apple-notes-sharing-scope
updated: 2026-04-22
code:
  - Sources/CheAppleNotesMCP/NotesSQLite/NotesStoreReader.swift
  - Sources/CheAppleNotesMCP/Sharing/ShareMetadata.swift
  - Tests/CheAppleNotesMCPE2ETests/ShareMetadataE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NotesStoreReaderTests.swift
  - Tests/CheAppleNotesMCPTests/ShareMetadataTests.swift
  - Sources/CheAppleNotesMCP/AppleScript/NotesController.swift
  - Sources/CheAppleNotesMCP/AppleScript/NoteScriptBuilder.swift
  - Sources/CheAppleNotesMCP/Server.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Sources/CheAppleNotesMCP/NotesSQLite/SQLQueries.swift
  - Tests/CheAppleNotesMCPTests/ServerHandlerTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
-->

---
### Requirement: Read tools SHALL accept an optional shared filter parameter

The tools `search_notes`, `list_notes`, and `list_folders` SHALL accept an optional parameter `shared` of type `Bool?`. When the parameter is `true`, the tool SHALL return only items where the shared heuristic evaluates true. When `false`, only items where it evaluates false. When the parameter is absent or null, no filtering by shared status SHALL occur.

#### Scenario: shared=true returns only shared items

- **WHEN** `list_notes` is invoked with `{"shared": true}`
- **THEN** every item in the response SHALL satisfy the shared heuristic
- **AND** no unshared item SHALL appear in the response

#### Scenario: shared=false excludes shared items

- **WHEN** `search_notes` is invoked with `{"keyword": "foo", "shared": false}`
- **THEN** no item in the response SHALL have shared=true

#### Scenario: absent parameter returns all items regardless of shared status

- **WHEN** `list_folders` is invoked without the `shared` parameter
- **THEN** the response SHALL contain both shared and unshared folders if both exist


<!-- @trace
source: apple-notes-sharing-scope
updated: 2026-04-22
code:
  - Sources/CheAppleNotesMCP/NotesSQLite/NotesStoreReader.swift
  - Sources/CheAppleNotesMCP/Sharing/ShareMetadata.swift
  - Tests/CheAppleNotesMCPE2ETests/ShareMetadataE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NotesStoreReaderTests.swift
  - Tests/CheAppleNotesMCPTests/ShareMetadataTests.swift
  - Sources/CheAppleNotesMCP/AppleScript/NotesController.swift
  - Sources/CheAppleNotesMCP/AppleScript/NoteScriptBuilder.swift
  - Sources/CheAppleNotesMCP/Server.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Sources/CheAppleNotesMCP/NotesSQLite/SQLQueries.swift
  - Tests/CheAppleNotesMCPTests/ServerHandlerTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
-->

---
### Requirement: AppleScript fallback SHALL refuse share metadata queries when SQLite is unavailable

When Full Disk Access is not granted and SQLite reader is unavailable, `get_share_metadata` SHALL return an error of the form `featureRequiresSQLite("get_share_metadata")` rather than falling back to AppleScript. AppleScript does not expose invitation metadata and cannot satisfy the tool contract.

#### Scenario: Tool errors with clear message when SQLite unavailable

- **WHEN** `get_share_metadata` is invoked and SQLite reader is unavailable
- **THEN** the tool SHALL return an error containing the string `requires Full Disk Access`

<!-- @trace
source: apple-notes-sharing-scope
updated: 2026-04-22
code:
  - Sources/CheAppleNotesMCP/NotesSQLite/NotesStoreReader.swift
  - Sources/CheAppleNotesMCP/Sharing/ShareMetadata.swift
  - Tests/CheAppleNotesMCPE2ETests/ShareMetadataE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NotesStoreReaderTests.swift
  - Tests/CheAppleNotesMCPTests/ShareMetadataTests.swift
  - Sources/CheAppleNotesMCP/AppleScript/NotesController.swift
  - Sources/CheAppleNotesMCP/AppleScript/NoteScriptBuilder.swift
  - Sources/CheAppleNotesMCP/Server.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Sources/CheAppleNotesMCP/NotesSQLite/SQLQueries.swift
  - Tests/CheAppleNotesMCPTests/ServerHandlerTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
-->