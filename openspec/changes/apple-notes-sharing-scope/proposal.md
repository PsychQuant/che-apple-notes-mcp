## Why

原本 GitHub issue #4(Phase 3 — create and manage Apple Notes share invitations）規劃了 4 個 CRUD-style tools（`create_share_link` / `invite_participant` / `revoke_share` / `list_participants`），但 `/spectra-discuss` 階段對 6 條技術路徑做實測後確認：

- **Path A**（public `CKShare` API）：Notes.app 使用私有 CloudKit container（`iCloud.com.apple.Notes`），第三方無法 attach
- **Path B**（URL scheme）：Notes.app 只暴露 3 個 URL（`showNote` / `callRecordingCreateNote` / `callRecordingAddAudioAttachment`），無 share 相關 path
- **Path C**（UI automation via System Events）：可行但 Notes.app 一升版就壞
- **Path D**（workflow helper — 打開 Share menu 交給使用者）：穩定、透明、最可行
- **Path E**（私有 `NotesKit` / `NotesShared` framework via `dlopen`）：類別存在（`ICMSharingMenuController` / `ICCollaborationController` / `ICInvitation`）但需 `dyld-shared-cache-util` + class-dump，ROI 低
- **Path F**（Shortcuts / AppIntents）：Notes.app 50+ intents **無** `ShareNoteIntent`

同時意外發現 SQLite `ZICINVITATION` table 完整 schema，其中 `ZSHAREURL VARCHAR`（unique indexed）就是 Notes.app 的公開 share URL —— 所有 READ 能力（誰分享什麼、分享 URL 是什麼、有幾個 invitation）**不需任何 private API** 就能取得。

因此 #3 Phase 2 和 #4 Phase 3 的 scope 需要重新對齊，避免把「做不到的 CREATE」和「本來就能做的 READ」混在同一個 issue 裡。

## What Changes

- **#3 吸收所有 READ 能力**：
  - `get_share_metadata(identifier)` 擴充為回傳 `ZICINVITATION` 完整欄位（note/subfolder count、receivedDate、title、snippet、`ZSHAREURL`）
  - `search_notes` / `list_notes` / `list_folders` 加 `shared` filter（已有 heuristic from #2 Phase 1）
  - 新增 CoreData FK join：`ZICINVITATION.ZROOTOBJECT` → `ZICCLOUDSYNCINGOBJECT.Z_PK` 拿回被分享的 note/folder 實體

- **#4 收斂為 workflow helpers + 決策文檔**：
  - 保留並實作：`prepare_share_note(id)` / `prepare_share_folder(id)` —— 打開 Notes.app 並 focus 到該 item，觸發 Share menu；控制權交還使用者填 email
  - **BREAKING**：原計畫的 `create_share_link` / `invite_participant` / `revoke_share` / `list_participants` 4 個 tool **全部作廢**
  - 新增決策 appendix（在本 change 的 `design.md`）：完整記錄 Path A/B/C/E/F 的 probe 結果與否決理由，供未來想走 private API 路線的人參考

- **刻意不在本 change 裡做的事**（見 Non-Goals）：
  - 不實作任何 CREATE share 的 public-API 路徑（技術上不存在）
  - 不走 private `dlopen` 路線（需要另一個獨立 spike issue）

## Non-Goals

- **不做 public CKShare CREATE**：Notes.app container 私有，Path A 無可行實作
- **不做 URL-scheme CREATE**：`applenotes://` 無 share path，Path B 確認死
- **不做 Shortcuts-based CREATE**：Notes.app 無 `ShareNoteIntent`，Path F 確認死
- **不做 private framework dlopen**：`ICMSharingMenuController` 雖存在但需額外 class-dump + ARC 小心處理 + dyld 限制，成本 / 風險比低；**appendix 記錄現況，不寫程式碼**
- **不做 UI automation 自動點 Share menu**：Notes.app UI 變動就壞，可維護性差；Path D 的 workflow helper 已提供類似價值
- **不做 CKShare BLOB 反序列化**：`ZSERVERSHAREDATA` 是 CloudKit 內部格式，#3 的 `get_share_metadata` 僅回報 `serverShareDataPresent: bool`，不解析內容

## Capabilities

### New Capabilities

- `apple-notes-sharing-metadata`：READ 能力 —— 查詢 note / folder 的共享狀態、邀請 metadata、公開 share URL。實作於 #3 Phase 2。
- `apple-notes-sharing-workflow`：CREATE 輔助 —— 透過 `prepare_share_*` tool 把 Notes.app 帶到 Share menu，使用者手動完成後續步驟。實作於 #4 Phase 3（收斂後）。

### Modified Capabilities

無 —— 本 change 僅新增 sharing 相關 capability，不觸碰既有已 archive 的 testing 類 spec。

## Impact

- **Affected specs**：
  - 新 `openspec/specs/apple-notes-sharing-metadata/spec.md`
  - 新 `openspec/specs/apple-notes-sharing-workflow/spec.md`

- **Affected code**（由 #3 和 #4 實作階段處理，本 change 只定 scope）：
  - `Sources/CheAppleNotesMCP/NotesSQLite/SQLQueries.swift` — 新增 ZICINVITATION 相關 queries
  - `Sources/CheAppleNotesMCP/NotesSQLite/NoteEntity.swift` — 新增 `ShareMetadata` / `Invitation` struct
  - `Sources/CheAppleNotesMCP/NotesSQLite/NotesStoreReader.swift` — 新方法 `getShareMetadata` / `listInvitations`
  - `Sources/CheAppleNotesMCP/Sharing/`（新 module）— `prepare_share_note` / `prepare_share_folder` 的 AppleScript helper
  - `Sources/CheAppleNotesMCP/Server.swift` — 註冊新 tools

- **Affected GitHub issues**：
  - #3 scope 由「filter by shared」擴充為「全面 share READ」
  - #4 scope 由「4 個 CRUD tool」收斂為「2 個 workflow helper + 決策文檔」
  - 新增 issue #5（之前 scope guard 觸發的 pre-existing assertion bug）不在本 change 範圍

- **沒有 breaking change**：所有新 tool / 新 field 都是 additive，既有 read tool 的 `shared: bool`（from #2）保持不變
