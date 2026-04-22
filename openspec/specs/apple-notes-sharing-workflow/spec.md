# apple-notes-sharing-workflow Specification

## Purpose

TBD - created by archiving change 'apple-notes-sharing-scope'. Update Purpose after archive.

## Requirements

### Requirement: System SHALL provide prepare_share_note workflow helper

A new MCP tool `prepare_share_note` SHALL accept a note identifier and bring Notes.app to a state where the user can complete the share invitation manually. Specifically, the tool SHALL:

1. Activate Notes.app
2. Select the note identified by the given id
3. Invoke the `File → Share Note...` menu item via AppleScript or System Events

The tool SHALL return a JSON object confirming the menu was triggered. The tool SHALL NOT attempt to fill invitee email addresses, select permission levels, or click Send — those steps remain the user's responsibility.

#### Scenario: Tool activates Notes.app and opens Share menu

- **WHEN** `prepare_share_note` is invoked with a valid note identifier
- **THEN** Notes.app SHALL come to the foreground
- **AND** the Share menu for the target note SHALL be triggered
- **AND** the tool SHALL return `{"prepared": true, "id": "<input id>"}`

#### Scenario: Tool reports error when Share menu item is unavailable

- **WHEN** `prepare_share_note` is invoked and the `File → Share Note...` menu item cannot be located
- **THEN** the tool SHALL return an error containing the string `share menu unavailable`

#### Scenario: Tool does not auto-fill invitee information

- **WHEN** `prepare_share_note` completes successfully
- **THEN** the tool response SHALL NOT contain any invitee email
- **AND** the Share sheet UI SHALL remain in its initial empty state awaiting user input


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
### Requirement: System SHALL provide prepare_share_folder workflow helper

A new MCP tool `prepare_share_folder` SHALL accept a folder identifier and bring Notes.app to a state where the user can complete the share invitation for that folder manually. The behavior mirrors `prepare_share_note` but targets a folder via the `File → Share Folder...` menu item.

#### Scenario: Tool activates Notes.app and opens folder Share menu

- **WHEN** `prepare_share_folder` is invoked with a valid folder identifier
- **THEN** Notes.app SHALL come to the foreground
- **AND** the Share menu for the target folder SHALL be triggered

#### Scenario: Tool reports error when folder cannot be focused

- **WHEN** `prepare_share_folder` is invoked with a folder identifier that cannot be resolved by AppleScript
- **THEN** the tool SHALL return an error containing the string `folder not found`


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
### Requirement: System SHALL NOT provide direct share creation tools

The MCP server SHALL NOT expose tools that programmatically create CloudKit shares, add participants, revoke shares, or list participants without going through Notes.app UI. Tools such as `create_share_link`, `invite_participant`, `revoke_share`, and `list_participants` SHALL NOT be implemented as part of this capability.

#### Scenario: Direct share creation tools are absent from the MCP tool list

- **WHEN** the MCP tool list is queried
- **THEN** no tool named `create_share_link` SHALL be present
- **AND** no tool named `invite_participant` SHALL be present
- **AND** no tool named `revoke_share` SHALL be present
- **AND** no tool named `list_participants` SHALL be present


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
### Requirement: Workflow tools SHALL degrade predictably when Notes.app is not responding

When Notes.app is unresponsive or closed at invocation time, the workflow tools SHALL attempt to launch it with a bounded wait and return a clear error if the launch does not succeed within the wait budget.

#### Scenario: Tool errors when Notes.app launch times out

- **WHEN** `prepare_share_note` is invoked while Notes.app is not running
- **AND** Notes.app fails to become frontmost within a reasonable budget
- **THEN** the tool SHALL return an error containing the string `Notes.app did not activate`

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