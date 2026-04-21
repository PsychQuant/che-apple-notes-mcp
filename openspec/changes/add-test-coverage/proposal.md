## Why

`CheAppleNotesMCP` 目前有 3,725 行 production code，但只有 60 行、9 個 unit test，覆蓋 4 個模組（`AppleScriptEscape`、`BodyFormatter`、`UndoStack`、`BodyHTMLRenderer`）。18 個 MCP tools 走 stdio JSON-RPC，全部沒有 end-to-end 驗證——protocol 回歸、AppleScript 寫入路徑失效、SQLite schema 漂移都無法自動偵測。在繼續新增功能前，需要先補齊測試基線。

## What Changes

- **新增 unit test 檔案**：`NoteProtobufDecoderTests`、`NoteScriptBuilderTests`、`SQLQueriesTests`、`FolderHierarchyTests`、`NoteEntityTests`、`AttachmentLocatorTests`、`CapabilitiesTests`，覆蓋所有無副作用的純函式模組。
- **擴充既有 unit test**：`SmokeTests.swift` 拆成 `BodyFormatterTests` / `AppleScriptEscapeTests` / `BodyHTMLRendererTests` / `UndoStackTests` 四支，補 edge cases（redo、overflow、clear、空輸入、HTML 混排等）。
- **新增 E2E test target** `CheAppleNotesMCPE2ETests`：spawn `.build/debug/CheAppleNotesMCP` 子行程，透過 stdio 送 JSON-RPC，每個 MCP tool 一個 happy-path test（18 個）。
- **新增 E2E test helpers**：`MCPClient.swift`（封裝 initialize / tools/list / tools/call）、`TestFixture.swift`（setup/teardown 專屬 `__CheMCPTest_{UUID}__` folder，位於 `On My Mac` account）。
- **BREAKING**：`Package.swift` `swift-tools-version` 從 `5.9` 升到 `6.0`，啟用 Swift Testing framework（`@Test` + `#expect`）。
- **重寫既有 9 個 XCTest 測試為 Swift Testing**：`XCTestCase` → `@Suite`、`XCTAssert*` → `#expect`。
- **Makefile 新增** `test-unit` / `test-e2e` 兩個 target，分別對應 CI 可跑與本機手動。

## Capabilities

### New Capabilities

- `unit-testing`: 為 `CheAppleNotesMCP` 純函式模組（AppleScript 組裝、protobuf 解碼、SQL 字串、folder 樹結構、entity decode、body formatter、undo stack）建立可在 CI 執行的 Swift Testing unit test。
- `e2e-testing`: 透過 subprocess + stdio JSON-RPC 驗證 MCP server 的 18 個 tool，包含 fixture folder 自動 setup/teardown。

### Modified Capabilities

(none)

## Impact

- **Affected specs**: 新增 `unit-testing`、`e2e-testing` 兩個新 capability spec。
- **Affected code**:
  - `Package.swift`——bump `swift-tools-version` 到 `6.0`、新增 `CheAppleNotesMCPE2ETests` target。
  - `Tests/CheAppleNotesMCPTests/SmokeTests.swift`——拆分並改寫成 Swift Testing。
  - `Tests/CheAppleNotesMCPTests/`——新增 7 支 unit test 檔。
  - `Tests/CheAppleNotesMCPE2ETests/`（新目錄）——新增 `MCPClient.swift`、`TestFixture.swift`、5 支 E2E test 檔（Folder / NoteCRUD / Batch / Search / UndoRedo）。
  - `Makefile`——新增 `test-unit`、`test-e2e` 目標。
- **Dependencies**: 無新增第三方套件；Swift Testing 隨 Swift 6 toolchain 內建。
- **Runtime requirements**: E2E 需 macOS 13+ 實機、Notes.app 安裝、首次執行需授予 Automation 權限；unit test 無額外需求。
- **CI impact**: `make test-unit` 可在 `macos-latest` runner 跑；`make test-e2e` 只本機執行，不進 CI。
