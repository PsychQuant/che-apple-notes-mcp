# Privacy Policy for che-apple-notes-mcp

**Last Updated: April 21, 2026**

## Overview

che-apple-notes-mcp is a local MCP (Model Context Protocol) server that provides Claude with access to your macOS Notes.app. This extension operates entirely on your local machine and does not transmit any data to external servers.

## Data Access

This extension accesses the following data on your Mac:

### Notes Data
- **Note content**: title, body (plaintext + HTML), creation/modification timestamps, pinned/locked flags, folder membership
- **Folder metadata**: names, account associations (iCloud / On My Mac / other), hierarchy
- **Account metadata**: names and identifiers used by Notes.app
- **Attachment metadata** (read-only): filenames, content types, local file paths

### Two Access Paths

| Path | What it reads | Permission |
|------|---------------|------------|
| SQLite direct | `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` | Full Disk Access (optional, for fast reads) |
| AppleScript | Notes.app live state via automation | Automation permission for Notes.app |

## Data Processing

### Local Processing Only
- **All data processing occurs locally** on your Mac
- **No data is transmitted** to Anthropic, the developer, or any third-party servers
- **No data is stored** by this extension beyond the current session (undo/redo stack is in-memory and cleared on restart)

### How Data Flows
1. Claude sends a request to the local MCP server (e.g., "search notes for 'meeting'")
2. The MCP server queries either the local SQLite file or dispatches AppleScript to Notes.app
3. Results are returned to Claude through the local MCP protocol
4. Data never leaves your computer

## Permissions

On first use, macOS will request permission for this extension to access:

| Permission | Purpose | When triggered |
|------------|---------|----------------|
| Automation → Notes.app | Create, update, delete, move notes; read fallback when FDA not granted | First call to a write tool, or `--setup` |
| Full Disk Access (optional) | Direct SQLite read for fast listing and search | User must add the binary manually via System Settings; not auto-prompted |

Without Full Disk Access, read operations transparently fall back to AppleScript (same result, slower).

## Locked Notes

Notes marked "locked" in Apple Notes have their body encrypted with AES. This extension **cannot decrypt locked-note bodies** — only metadata (title, timestamps, folder, locked flag) is returned. Locked note bodies are returned as `null`.

## User Control

You can revoke permissions at any time through **System Settings → Privacy & Security**. Specifically:
- **Automation** → uncheck Notes.app under the extension's entry
- **Full Disk Access** → remove the binary from the list

## Third-Party Services

None. This extension has no network egress.

## Contact

- GitHub: https://github.com/PsychQuant/che-apple-notes-mcp
- Issues: https://github.com/PsychQuant/che-apple-notes-mcp/issues
