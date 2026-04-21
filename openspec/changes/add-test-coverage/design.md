## Context

`CheAppleNotesMCP` 是 macOS 上的 Apple Notes MCP server，對外暴露 18 個 MCP tools，內部由兩條路徑實作：

- **讀路徑**：`NotesStoreReader`（413 行）走 SQLite 讀 `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`，涉及 protobuf 解碼（`NoteProtobufDecoder`）與 folder hierarchy 重建（`FolderHierarchy`）。
- **寫路徑**：`NotesController`（158 行）走 `osascript` 執行 AppleScript，由 `NoteScriptBuilder`（212 行）組裝腳本。

目前 `Tests/CheAppleNotesMCPTests/SmokeTests.swift` 只有 9 個 XCTest，覆蓋 4 個邊陲模組，主要業務邏輯（protobuf decode、SQL 查詢、script 組裝、MCP tool routing）完全未測。18 個 tools 的 JSON-RPC 契約也無自動化驗證。

相關約束：

- 專案為 Swift Package (SwiftPM)，`swift-tools-version` 目前為 `5.9`，platform 鎖 macOS 13+。
- 依賴僅 `swift-sdk` (MCP)，不打算引入第三方 test framework。
- MCP server 以 `StdioTransport` 啟動，`main.swift` 直接建立 `CheAppleNotesMCPServer` 並 `run()`——不支援 in-process 載入作 integration test。
- 專案以 `~/bin/CheAppleNotesMCP` binary 方式部署，CI/本機都用同一 binary。

## Goals / Non-Goals

**Goals:**

- 所有無副作用的純函式模組皆有 unit test（Swift Testing，CI 可跑）。
- 18 個 MCP tools 各有一個 happy-path E2E test，透過 subprocess + stdio JSON-RPC 驗證完整 pipeline。
- Unit 與 E2E 在 SwiftPM 層級拆分成兩個 test target，CI 只跑 unit、本機手動跑 E2E。
- E2E 自我清理：測試結束後不留下污染 Notes.app 的資料。
- 既有 `SmokeTests.swift` 的 9 個測試改寫為 Swift Testing，保留覆蓋率不回退。

**Non-Goals:**

- Error-branch 覆蓋、failure path 的 exhaustive testing（happy path only）。
- Integration test（直接呼叫 Swift API）——E2E 一律走 subprocess。
- Line coverage 100%——以 tool-level 覆蓋為度量，不追行數。
- CI 跑 E2E——macOS runner 無 Automation permission，暫不支援。
- Mock AppleScript executor——保持 `NotesController` 架構不變，不插入 protocol 抽象。
- 為 protobuf decoder 準備 malformed 輸入 fixture 或 craft fuzz test。
- 針對 iCloud account 的測試（只用 `On My Mac`）。

## Decisions

### Adopt Swift Testing framework over XCTest

選擇 **Swift Testing**（`@Test` + `#expect`）作為所有新舊測試的統一框架。

- **理由**:
  - `#expect` 失敗時自動展開 expression（例：`a == b → 3 == 5`），對 JSON-RPC 回應與 AppleScript 字串 diff 特別有價值。
  - `@Suite` + `@Tag` 提供原生分組，未來要加 `.tag(.slow)`、`.tag(.requires_notes_app)` 無需改架構。
  - 原生 `async throws` 支援，MCP client 是 async 介面，語法乾淨。
- **Alternatives**:
  - **延用 XCTest**：既有測試無需改寫、toolchain 不用 bump。但 assertion 訊息弱、async 支援補丁式、無原生 parameterized/tagging。在這個 scope 下未來擴充成本較高。
  - **同時保留兩套**：過度複雜，拒絕。
- **Cost**: `swift-tools-version` 要從 `5.9` 升 `6.0`；既有 9 個 XCTest 重寫（低成本，60 行程式碼）；CI runner 需 Xcode 16+。

### Split tests into two SwiftPM targets

`Package.swift` 新增 `CheAppleNotesMCPE2ETests` target，與既有 `CheAppleNotesMCPTests` 並列。

- **理由**:
  - Unit test 無外部依賴、CI 必跑；E2E 需 Notes.app 實機與 Automation permission、只本機跑。混在同一 target 會讓 CI fail 或需複雜 skip 邏輯。
  - SwiftPM `.testTarget` 層級拆分最簡潔，`swift test --filter CheAppleNotesMCPTests` 可精確挑選。
- **Alternatives**:
  - **單一 target + `@Tag` 過濾**：可行但 `swift test` 預設會跑全部，E2E failure 會混入 CI 結果。
  - **獨立 Swift Package**：過度切割，共用 `@testable import CheAppleNotesMCP` 會失效。
- **Impact**: 兩個 test target 都可以 `@testable import CheAppleNotesMCP`。

### E2E driver via subprocess + stdio JSON-RPC

E2E 測試啟動 `.build/debug/CheAppleNotesMCP` 子行程，透過 `Process` + `Pipe` 送收 JSON-RPC 訊息。

- **理由**:
  - MCP 的對外契約就是 stdio JSON-RPC，任何抽象層都會跳過實際 transport bug。
  - 子行程獨立，測試 crash 不影響 test runner 本體。
  - 與正式部署（`~/bin/CheAppleNotesMCP`）路徑一致。
- **Alternatives**:
  - **In-process 建立 `CheAppleNotesMCPServer`**：繞過 `StdioTransport`，不算 E2E；且 `Server.start(transport:)` 需 async lifecycle 難 teardown。
  - **用官方 MCP client SDK**：引入新依賴、增加失敗面向；自行實作 client 成本低。
- **Design**:
  - 新增 `MCPClient.swift` 封裝 `initialize` / `tools/list` / `tools/call` 三個 primitive。
  - 每個 test 開一個 child process、結束 terminate，避免狀態殘留。
  - `debug` build 使用，不使用 `release`（build 快、symbol 完整）。

### Fixture folder strategy: one per test, auto-cleanup

每個 E2E test 在 `On My Mac` account 建 `__CheMCPTest_{UUID}__` folder，teardown 刪除整個 folder（含所有 notes）。

- **理由**:
  - UUID 後綴確保並行/重跑無衝突。
  - 刪 folder 會連動刪 notes，單一 teardown 指令清完。
  - `On My Mac` 不走 iCloud 同步，避免延遲污染測試斷言。
- **Alternatives**:
  - **iCloud default account**：sync 延遲可能讓 assertion 看不到剛建的 note。
  - **全域共用 fixture folder**：並行測試會互相干擾。
  - **獨立 macOS user account / VM**：使用者明確表示可接受污染本機 Notes，拒絕此方案。
- **Failure handling**:
  - Teardown 在 `deinit` 或 `@Suite` 收尾，即使 assertion 失敗也要嘗試刪 folder。
  - 提供 `scripts/cleanup-test-folders.sh` 掃描並刪除所有 `__CheMCPTest_*__` folder 作為 escape hatch。

### Makefile targets: test-unit and test-e2e

`Makefile` 新增兩個 target：

```
test-unit:
	swift test --filter CheAppleNotesMCPTests

test-e2e: build
	swift test --filter CheAppleNotesMCPE2ETests
```

- **理由**:
  - `test-unit` 對應 CI 腳本與 PR check。
  - `test-e2e` 先確保 debug binary 存在再跑測試。
  - 原 `test` target 保留（跑全部），但 CI 用 `test-unit` 明確。
- **Alternatives**:
  - **只留 `test` 全跑**：CI 會在 GitHub runner 無 Notes.app 時 fail。
  - **用 shell script 包裝**：不一致，與現有 Makefile convention 違背。

## Risks / Trade-offs

- **Swift tools bump 可能破 CI** → Mitigation: 先在本地驗證 `swift test` 過；GitHub Actions runner 確認升到 Xcode 16+；若 runner 不支援則 pin Xcode 版本。
- **Automation permission 首次觸發需人工點擊** → Mitigation: E2E 文件註記；提供腳本預先呼叫 `osascript` 觸發權限對話框；CI 不跑 E2E 避開此問題。
- **Notes.app 狀態殘留影響測試** → Mitigation: 每個 test 獨立 UUID fixture folder；提供 `cleanup-test-folders.sh` 作後備；test 順序獨立不依賴先前狀態。
- **Subprocess 啟動成本影響 E2E 速度** → Mitigation: 接受單次 E2E 執行時間 1~3 分鐘；若過慢，改為 shared process + 每測試用新 fixture folder（列為後續 optimization，非本次 scope）。*Post-run observation*：在 iCloud-only 環境下，單一 AppleScript call 可達 30~80 s（Notes.app 等待 sync），18 tests 實測 >20 分鐘。此外 `MCPClient.readLine` 使用 `FileHandle.availableData` 會阻塞到 byte 可讀，上層 `waitForResponse` 的 30 s timeout 無法生效——需後續 change 改 non-blocking I/O。
- **iCloud sync delay 導致 list-after-write 讀不到新資料** → Observation: `listFoldersIncludesFixtureFolder`、`listNotesReturnsNotesInFixtureFolder` 在 fixture 建完立刻 list 會拿到空結果（CloudKit 寫入未 propagate 回 SQLite 副本）。Mitigation: 下個 change 加入 retry with backoff 或以 `On My Mac` 作為 CI 先決條件文件化。
- **SQLite 讀路徑仍無覆蓋（real DB 需要）** → Mitigation: E2E 透過 `list_notes` / `get_note` 間接驗證 SQLite 路徑；若未來要 unit test `NotesStoreReader`，另起 change 處理 fixture DB。
- **Swift Testing 在 Xcode 16 之前是 preview** → Mitigation: 鎖 Xcode 16+ 作為開發最低需求；README 加註。
