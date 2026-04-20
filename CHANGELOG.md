# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
