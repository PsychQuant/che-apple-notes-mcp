# e2e-testing Specification

## Purpose

Provide end-to-end verification of `CheAppleNotesMCP` by driving the compiled server binary through subprocess + stdio JSON-RPC. Every MCP tool is exercised with a happy-path call to detect protocol regressions, AppleScript write-path failures, and SQLite schema drift. Tests isolate Notes.app side effects to UUID-named fixture folders with guaranteed teardown, and run in a dedicated SwiftPM target separate from unit tests.

## Requirements

### Requirement: Every MCP tool SHALL have one happy-path E2E test

Each of the 18 MCP tools exposed by `CheAppleNotesMCPServer` SHALL have exactly one happy-path end-to-end test in target `CheAppleNotesMCPE2ETests`. The test MUST invoke the tool with valid arguments that trigger its primary success path and MUST assert that the JSON-RPC response indicates success and contains the expected result shape.

#### Scenario: Tool invocation returns success

- **WHEN** an E2E test sends a `tools/call` JSON-RPC request for a tool with valid arguments
- **THEN** the response MUST NOT contain a JSON-RPC `error` field
- **AND** the response `result` field MUST include the expected keys for that tool

#### Scenario: Every tool is covered

- **WHEN** the test target `CheAppleNotesMCPE2ETests` is enumerated
- **THEN** the collected `@Test` functions MUST include one test per tool name registered in `CheAppleNotesMCPServer.defineTools()`


<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->

---
### Requirement: E2E tests SHALL drive the server via subprocess and stdio JSON-RPC

E2E tests SHALL launch `.build/debug/CheAppleNotesMCP` as a child process, write JSON-RPC requests to its stdin, and read JSON-RPC responses from its stdout. Tests SHALL NOT import `CheAppleNotesMCPServer` directly to execute tool calls.

#### Scenario: Test uses Process and Pipe

- **WHEN** an E2E test begins
- **THEN** it MUST spawn the debug binary using Swift's `Process` API with stdin/stdout pipes

#### Scenario: Test exchanges JSON-RPC messages

- **WHEN** an E2E test sends a request
- **THEN** the payload MUST be JSON-RPC 2.0 compliant (fields `jsonrpc`, `id`, `method`, `params`)
- **AND** the response MUST be parsed as JSON-RPC 2.0

#### Scenario: Subprocess is terminated after test

- **WHEN** an E2E test completes (success or failure)
- **THEN** the spawned child process MUST be terminated before the next test starts


<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->

---
### Requirement: E2E tests SHALL provide a reusable MCP client helper

The E2E test target SHALL include a file `MCPClient.swift` exposing at minimum these primitives: `initialize()`, `listTools()`, `callTool(name:arguments:)`. E2E test files SHALL use this helper rather than constructing raw JSON-RPC by hand.

#### Scenario: MCPClient exposes the required primitives

- **WHEN** `MCPClient.swift` is inspected
- **THEN** it MUST declare public methods `initialize()`, `listTools()`, and `callTool(name:arguments:)`
- **AND** the methods MUST be `async` and propagate errors via `throws`

#### Scenario: E2E tests use MCPClient

- **WHEN** an E2E test invokes a tool
- **THEN** it MUST call `MCPClient.callTool(...)` rather than manually encode JSON-RPC payloads


<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->

---
### Requirement: E2E tests SHALL isolate side effects to a unique fixture folder

Each E2E test that writes to Notes.app SHALL operate inside a fixture folder whose name matches the pattern `__CheMCPTest_{UUID}__`. The folder SHALL be created at test setup and deleted at test teardown, regardless of whether assertions passed. The fixture helper SHALL prefer the `On My Mac` account when it exists on the host and SHALL fall back to the server's default account otherwise.

#### Scenario: Fixture folder name includes UUID

- **WHEN** a test creates its fixture folder
- **THEN** the folder name MUST match the pattern `__CheMCPTest_[0-9A-F-]+__`

#### Scenario: Fixture folder prefers On My Mac when available

- **WHEN** the fixture folder is created and the host has an `On My Mac` account
- **THEN** the `account` argument passed to `create_folder` MUST be `"On My Mac"`

#### Scenario: Fixture folder falls back to default account

- **WHEN** the fixture folder is created and the first attempt with `On My Mac` returns an error
- **THEN** the helper MUST retry `create_folder` without an `account` argument so the server picks its default account

#### Scenario: Fixture folder is deleted on teardown

- **WHEN** a test completes (success or failure)
- **THEN** the teardown logic MUST call `delete_folder` on the fixture folder
- **AND** the call MUST execute even if the test's main assertions threw


<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->

---
### Requirement: Cleanup escape hatch SHALL be provided

The repository SHALL include a script `scripts/cleanup-test-folders.sh` that enumerates all folders matching `__CheMCPTest_*__` across all accounts and deletes them. The script provides a recovery mechanism when teardown fails.

#### Scenario: Script deletes matching folders

- **WHEN** `scripts/cleanup-test-folders.sh` runs
- **THEN** it MUST delete every folder whose name matches the pattern `__CheMCPTest_*__`
- **AND** it MUST NOT delete folders that do not match the pattern


<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->

---
### Requirement: E2E tests SHALL be isolated in a dedicated SwiftPM target

`Package.swift` SHALL declare a test target named `CheAppleNotesMCPE2ETests` distinct from `CheAppleNotesMCPTests`. Running `swift test --filter CheAppleNotesMCPTests` SHALL execute only unit tests and SHALL NOT execute E2E tests.

#### Scenario: Two test targets exist

- **WHEN** `Package.swift` is parsed
- **THEN** the `targets` array MUST contain both `CheAppleNotesMCPTests` and `CheAppleNotesMCPE2ETests` as `.testTarget` entries

#### Scenario: Filter selects unit tests only

- **WHEN** `swift test --filter CheAppleNotesMCPTests` runs
- **THEN** no tests from `CheAppleNotesMCPE2ETests` MUST execute


<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->

---
### Requirement: Makefile SHALL expose unit and E2E targets separately

`Makefile` SHALL define `test-unit` and `test-e2e` targets. `test-unit` SHALL run only the unit test target. `test-e2e` SHALL depend on `build` and run only the E2E test target.

#### Scenario: test-unit runs only unit tests

- **WHEN** `make test-unit` runs
- **THEN** the executed command MUST filter the test run to `CheAppleNotesMCPTests`

#### Scenario: test-e2e builds first

- **WHEN** `make test-e2e` runs
- **THEN** the `build` target MUST complete successfully before any test executes
- **AND** the executed test command MUST filter the run to `CheAppleNotesMCPE2ETests`

<!-- @trace
source: add-test-coverage
updated: 2026-04-21
code:
  - Tests/CheAppleNotesMCPTests/SmokeTests.swift
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift
  - Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift
  - .agents/skills/spectra-archive/SKILL.md
  - scripts/cleanup-test-folders.sh
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/CheAppleNotesMCPTests/VersionTests.swift
  - Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift
  - Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift
  - Package.swift
  - Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift
  - Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift
  - Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - AGENTS.md
  - Makefile
  - .agents/skills/spectra-debug/SKILL.md
  - CLAUDE.md
  - .agents/skills/spectra-apply/SKILL.md
  - Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift
  - Tests/CheAppleNotesMCPTests/NoteEntityTests.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .spectra.yaml
  - Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift
  - Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/TestFixture.swift
  - Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift
  - Tests/CheAppleNotesMCPTests/UndoStackTests.swift
  - Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift
  - Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift
  - Tests/CheAppleNotesMCPE2ETests/MCPClient.swift
  - Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift
  - Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift
  - README.md
-->