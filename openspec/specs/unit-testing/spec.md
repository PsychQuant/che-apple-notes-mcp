# unit-testing Specification

## Purpose

Establish a Swift Testing–based unit test baseline for `CheAppleNotesMCP`. This capability covers the pure-function modules of the server (AppleScript escaping, protobuf decoding, SQL string assembly, folder hierarchy, entity decoding, body formatting, HTML rendering, undo/redo stack, attachment locator, capabilities) so that regressions in side-effect-free logic can be detected in CI without Notes.app being installed or running.

## Requirements

### Requirement: Unit tests SHALL use Swift Testing framework

All unit test files in `Tests/CheAppleNotesMCPTests/` SHALL be written using the Swift Testing framework (`@Test`, `@Suite`, `#expect`). XCTest-based test cases SHALL NOT be added; any existing XCTest code SHALL be migrated.

#### Scenario: New test file uses Swift Testing

- **WHEN** a developer adds a new unit test file under `Tests/CheAppleNotesMCPTests/`
- **THEN** the file MUST import `Testing` and declare tests using `@Test` functions or `@Suite` struct
- **AND** the file MUST NOT import `XCTest`

#### Scenario: Assertions use the expect macro

- **WHEN** a unit test verifies a value
- **THEN** the test MUST use `#expect(...)` or `#require(...)` macros
- **AND** the test MUST NOT call `XCTAssert*` functions


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
### Requirement: Pure-function modules SHALL have unit test coverage

Every production module that performs pure-function transformations (no filesystem, no subprocess, no AppleScript, no SQLite IO) SHALL have at least one unit test file verifying its public surface. This applies to the following modules: `AppleScriptEscape`, `BodyFormatter`, `BodyHTMLRenderer`, `UndoStack`, `NoteProtobufDecoder`, `NoteScriptBuilder`, `SQLQueries`, `FolderHierarchy`, `NoteEntity`, `AttachmentLocator`, and `Capabilities`.

#### Scenario: Every listed pure-function module has a test file

- **WHEN** the test target `CheAppleNotesMCPTests` is enumerated
- **THEN** the directory MUST contain one test file per listed module, named `<ModuleName>Tests.swift`
- **AND** each file MUST contain at least one `@Test` function

#### Scenario: Each test file exercises the public surface

- **WHEN** a unit test file for module `M` runs
- **THEN** it MUST invoke at least one public entry point of `M` and assert on the result


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
### Requirement: Existing SmokeTests SHALL be migrated to Swift Testing

The 9 existing XCTest cases in `Tests/CheAppleNotesMCPTests/SmokeTests.swift` SHALL be rewritten as Swift Testing tests. The original assertions MUST remain semantically equivalent (same inputs, same expected outputs). The monolithic `SmokeTests.swift` SHALL be split into per-module files (`BodyFormatterTests.swift`, `AppleScriptEscapeTests.swift`, `BodyHTMLRendererTests.swift`, `UndoStackTests.swift`).

#### Scenario: SmokeTests.swift is removed after migration

- **WHEN** the change is applied
- **THEN** `Tests/CheAppleNotesMCPTests/SmokeTests.swift` MUST NOT exist
- **AND** per-module test files MUST exist in its place

#### Scenario: Migrated tests produce equivalent assertions

- **WHEN** each migrated test runs
- **THEN** it MUST assert on the same input-output pair as the original XCTest case


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
### Requirement: Unit tests SHALL run without Notes.app

Unit tests SHALL NOT launch subprocesses, invoke `osascript`, access `~/Library/Group Containers/group.com.apple.notes/`, or require Notes.app to be running. A unit test run on a macOS environment with no Notes.app data SHALL pass.

#### Scenario: CI runner executes unit tests

- **WHEN** `make test-unit` runs on a macOS CI runner with no Notes.app state
- **THEN** all unit tests MUST pass
- **AND** no AppleScript or SQLite-access errors MUST be logged


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
### Requirement: SwiftPM tooling SHALL support Swift Testing

`Package.swift` SHALL declare `swift-tools-version: 6.0` or higher so that the Swift Testing framework is available without additional dependencies.

#### Scenario: swift-tools-version is 6.0 or higher

- **WHEN** the first line of `Package.swift` is inspected
- **THEN** it MUST declare `swift-tools-version: 6.0` or a later version

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