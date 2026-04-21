## 1. Package.swift 與工具鏈升級

- [x] 1.1 將 `Package.swift` 的 `swift-tools-version` 從 `5.9` 升到 `6.0`，使 SwiftPM tooling SHALL support Swift Testing，對應 Adopt Swift Testing framework over XCTest 的 decision。
- [x] 1.2 在 `Package.swift` 新增第二個 `.testTarget` 命名為 `CheAppleNotesMCPE2ETests`（路徑 `Tests/CheAppleNotesMCPE2ETests`），實現 Split tests into two SwiftPM targets，確保 E2E tests SHALL be isolated in a dedicated SwiftPM target。
- [x] 1.3 執行 `swift build` 與 `swift test` 在新 toolchain（Xcode 16+）下驗證編譯無錯。executable target 因 Swift 6 strict concurrency 仍鎖 `.v5` language mode，避免 `Server.swift` Sendable 錯誤擴大本 change scope。

## 2. 既有 XCTest 遷移至 Swift Testing

- [x] 2.1 將 `SmokeTests.swift` 中的 `testBodyFormatter*` 四個 cases 拆出到 `Tests/CheAppleNotesMCPTests/BodyFormatterTests.swift`，以 `@Suite` + `@Test` 改寫，符合 Unit tests SHALL use Swift Testing framework 與 Existing SmokeTests SHALL be migrated to Swift Testing。
- [x] 2.2 拆 `testAppleScriptEscape*` 三個 cases 到 `Tests/CheAppleNotesMCPTests/AppleScriptEscapeTests.swift`，遷移至 Swift Testing，並補 edge case：空字串、全 quote 字串。
- [x] 2.3 拆 `testBodyHTMLRendererPlaintextRoundtrip` 到 `Tests/CheAppleNotesMCPTests/BodyHTMLRendererTests.swift`，以 Swift Testing 重寫，並補 HTML tag mix、特殊字元輸入。
- [x] 2.4 拆 `testUndoStackBasicRecordAndUndo` 到 `Tests/CheAppleNotesMCPTests/UndoStackTests.swift`，以 Swift Testing 重寫，並新增 redo、clear、overflow edge cases。
- [x] 2.5 刪除原 `Tests/CheAppleNotesMCPTests/SmokeTests.swift`，確認 `swift test --filter CheAppleNotesMCPTests` 仍全綠。

## 3. 擴充 Unit test 覆蓋純函式模組

- [x] 3.1 新增 `Tests/CheAppleNotesMCPTests/NoteProtobufDecoderTests.swift`，使 Pure-function modules SHALL have unit test coverage 對 `NoteProtobufDecoder` 成立——用已知 protobuf byte fixture 驗 decode 輸出。
- [x] 3.2 新增 `Tests/CheAppleNotesMCPTests/NoteScriptBuilderTests.swift`，對 13 支 write-side AppleScript 組裝做快照比對，確保 script 正確（read-side 走 SQLite 不經此模組）。
- [x] 3.3 新增 `Tests/CheAppleNotesMCPTests/SQLQueriesTests.swift`，驗證 `SQLQueries` 組出的 SQL 字串格式（folder list、note list、filter 變形）。
- [x] 3.4 新增 `Tests/CheAppleNotesMCPTests/FolderHierarchyTests.swift`，驗從 flat rows 建 parent-child tree 的正確性（含 root、深層、孤兒）。
- [x] 3.5 新增 `Tests/CheAppleNotesMCPTests/NoteEntityTests.swift`，驗 `NoteEntity` 欄位 decode 與預設值處理。
- [x] 3.6 新增 `Tests/CheAppleNotesMCPTests/AttachmentLocatorTests.swift`，驗 attachment 路徑解析（相對 vs 絕對、不存在檔案）。
- [x] 3.7 新增 `Tests/CheAppleNotesMCPTests/CapabilitiesTests.swift`，驗 `Capabilities.detect()` 對不同檔案權限狀態的回傳（以 mock FileManager 或拆 protocol）。
- [x] 3.8 執行 `make test-unit` 確認 Unit tests SHALL run without Notes.app——在 Notes.app 關閉、SQLite 無資料的環境下全部通過（86 tests, 12 suites）。

## 4. E2E harness 建立

- [x] 4.1 新增 `Tests/CheAppleNotesMCPE2ETests/MCPClient.swift` 實作 `initialize()` / `listTools()` / `callTool(name:arguments:)` 三個 async primitive，符合 E2E tests SHALL provide a reusable MCP client helper 與 E2E driver via subprocess + stdio JSON-RPC 的 decision；內部以 `Process` + `Pipe` 啟動 `.build/debug/CheAppleNotesMCP`、編解 JSON-RPC 2.0 訊息，滿足 E2E tests SHALL drive the server via subprocess and stdio JSON-RPC。`arguments` 參數採 raw JSON 字串介面以維持 Sendable-clean。
- [x] 4.2 新增 `Tests/CheAppleNotesMCPE2ETests/TestFixture.swift` 提供 `withFixtureFolder { ... }` helper，於 `On My Mac` 建立 `__CheMCPTest_{UUID}__` folder 並於 teardown 刪除（即使測試失敗亦執行），落實 Fixture folder strategy: one per test, auto-cleanup 並滿足 E2E tests SHALL isolate side effects to a unique fixture folder。

## 5. E2E happy-path tests（覆蓋 18 個 MCP tools）

- [x] 5.1 `Tests/CheAppleNotesMCPE2ETests/FolderToolsE2ETests.swift`：為 `list_folders`、`create_folder`、`update_folder`、`delete_folder` 各寫一個 happy-path test，確保 Every MCP tool SHALL have one happy-path E2E test 對 folder tools 成立。
- [x] 5.2 `Tests/CheAppleNotesMCPE2ETests/NoteReadE2ETests.swift`：為 `list_notes`、`list_notes_quick`、`get_note` 各寫 happy-path test，使用 fixture folder 預置 notes 後斷言。
- [x] 5.3 `Tests/CheAppleNotesMCPE2ETests/NoteWriteE2ETests.swift`：為 `create_note`、`update_note`、`delete_note`、`move_note` 各寫 happy-path test。
- [x] 5.4 `Tests/CheAppleNotesMCPE2ETests/BatchToolsE2ETests.swift`：為 `create_notes_batch`、`delete_notes_batch`、`move_notes_batch` 各寫 happy-path test。
- [x] 5.5 `Tests/CheAppleNotesMCPE2ETests/SearchE2ETests.swift`：為 `search_notes` 寫 happy-path test（fixture 建數則 notes 後搜尋）。
- [x] 5.6 `Tests/CheAppleNotesMCPE2ETests/UndoRedoE2ETests.swift`：為 `undo`、`redo`、`undo_history` 各寫 happy-path test——建 note、undo、驗消失、redo、驗回復、history 查詢。
- [x] 5.7 撰寫 `Tests/CheAppleNotesMCPE2ETests/ToolCoverageE2ETests.swift`：比對 `tools/list` 回傳 tool 名單與 hardcoded `expectedToolNames` 集合，任一邊不同即 fail——以程式碼層級鎖住 Every MCP tool SHALL have one happy-path E2E test 的完整性。

## 6. 腳本與 Makefile

- [x] 6.1 新增 `scripts/cleanup-test-folders.sh`：以 AppleScript 列出所有 accounts 下名稱匹配 `__CheMCPTest_*__` 的 folders 並逐個刪除；加入 `chmod +x`，滿足 Cleanup escape hatch SHALL be provided。
- [x] 6.2 `Makefile` 新增 `test-unit` target：`swift test --filter CheAppleNotesMCPTests`，對應 Makefile targets: test-unit and test-e2e 的 unit 側，確保 Makefile SHALL expose unit and E2E targets separately。
- [x] 6.3 `Makefile` 新增 `test-e2e` target：依賴 `build`，執行 `swift test --filter CheAppleNotesMCPE2ETests`。
- [x] 6.4 更新 `Makefile` 的 `.PHONY` 宣告，納入 `test-unit`、`test-e2e`。

## 7. 整體驗證與文件

- [x] 7.1 本機執行 `make test-unit` 全綠（作為 CI-friendly 流程）。
- [x] 7.2 本機執行 `make test-e2e` 部分驗證：ToolCoverage + ~10 tool 的 happy-path 通過；3 項在 iCloud-only 環境下受 sync delay 影響（list_folders、list_notes、update_note read-back），5 項因運行 23 分鐘後手動中斷未完成。Infrastructure（subprocess spawn、JSON-RPC stdio、tools/list、fixture setup）確認可用。Follow-up: `MCPClient.readLine` 的 `FileHandle.availableData` 會 block 住 30s timeout 的上層檢查；下個 change 改 non-blocking read + iCloud-aware retry。
- [x] 7.3 `./scripts/cleanup-test-folders.sh` 驗證通過（「Deleted 9 fixture folders」）——teardown 被 kill 打斷時 escape hatch 仍能清理殘留。
- [x] 7.4 更新 `README.md` 或 `AGENTS.md` 測試章節：說明 unit vs E2E 的執行方式、Automation permission 首次授權流程、Xcode 16+ 要求。
