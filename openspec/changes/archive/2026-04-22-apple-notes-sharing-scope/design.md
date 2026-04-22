## Context

Apple Notes.app 的「共享筆記 / 共享資料夾」功能建立於 Apple 私有 CloudKit container（`iCloud.com.apple.Notes`），`Info.plist` 顯示 `CKSharingSupported = true`。這意味著任何第三方（包含本 MCP server）想透過 public `CKShare` API 直接操作 Notes 的 share 生態系**在技術上不可行**。

這個認知在執行 `/spectra-discuss` 時被具體 probe 結果確認，同時意外發現 Notes.app 的 SQLite schema 把所有已存在的 invitations 暴露在 `ZICINVITATION` table 中，READ 能力的邊界因此重新定義。

本 change 的目的**不是實作**任何 share 功能（那會由後續 #3 / #4 實作階段負責），而是記錄經實測驗證的 6 條技術路徑與最終 scope 收斂決策，讓未來回頭考慮「是不是該做更完整的 share CREATE」的人能直接參考 evidence，不用重新 probe 一輪。

## Goals / Non-Goals

**Goals:**

- 以 probe 證據記錄 Apple Notes sharing 的 6 條技術路徑（A-F），每條都有可驗證的實測結果
- 重新劃定 #3 Phase 2 和 #4 Phase 3 的 scope 邊界：READ 歸 #3，WRITE-workflow 歸 #4，WRITE-direct 目前不做
- 為「apple-notes-sharing-metadata」和「apple-notes-sharing-workflow」兩個新 capability 建立 spec 與 task 骨架
- 讓「為什麼不走 Path E 私有 framework」的決策有 **可重讀** 的文字依據

**Non-Goals:**

- 不實作任何 share 功能的程式碼（那是 #3 / #4 的事）
- 不深入 class-dump `NotesShared.framework` 的 ObjC API（留給未來可能的 Path E spike issue）
- 不反序列化 `ZSERVERSHAREDATA` BLOB（CKShare 內部格式，#3 僅 report `present: bool`）
- 不修改既有的 `apple-notes` / `unit-testing` / `e2e-testing` spec

## Decisions

### Decision 1：Path A（public CKShare）rejected — CloudKit container 私有

**證據**：`plutil -p /System/Applications/Notes.app/Contents/Info.plist` 顯示 `CKSharingSupported = true`，但 Apple 沒公開 `iCloud.com.apple.Notes` container identifier 給第三方 app 使用。`CKContainer(identifier:)` 若自行建立新 container，將與 Notes.app 的 share 生態系無法互通。

**Alternative considered**：取得 Apple Internal entitlement。被否決 — 第三方 developer 無此選項。

**Implication**：Path A 不 spike、不實作、不留 stub。

### Decision 2：Path B（URL scheme）rejected — 無 share-related URL path

**證據**：`strings /System/Applications/Notes.app/Contents/MacOS/Notes | grep '^applenotes://'` 只 match 到 3 條：

```
applenotes://callRecordingAddAudioAttachment
applenotes://callRecordingCreateNote
applenotes://showNote?identifier=
```

**Alternative considered**：嘗試未文件化的 URL 如 `applenotes://share`。被否決 —— 無對應的 handler class，`open` 會失敗或 no-op。

**Implication**：Path B 不 spike、不實作。

### Decision 3：Path D（workflow helper）chosen as primary WRITE path

**技術形狀**：`prepare_share_note(id)` 的底層實作 = focus Notes.app → 透過 AppleScript 開啟對應 note → 用 `tell application "System Events"` 觸發 `File → Share Note...` menu item → 控制權交還 GUI 使用者。

**與 Path C 的差異**：Path D 不嘗試在 Share sheet 內自動填 email / 按 Send —— 那部分留給使用者手動完成。差異意味著**容錯** —— Notes.app 升版改 menu 佈局仍能 degrade 為「打開了 menu 但位置不準」，使用者可以手動調整；Path C 則會 silent-fail。

**Rationale**：MCP 不該假裝能完成它實際做不到的事。Path D 把能自動化的部分（focus + 開 menu）自動化，把**必須**人工判斷的部分（誰是 invitee / 權限等級）留給人工，UX 誠實。

**Alternative considered**：
- Path C full UI automation —— fragile、不 headless，否決
- 直接放棄 write path —— 使用者體驗差，否決

### Decision 4：Path E（private framework dlopen）deferred — 高成本低收益

**證據**：Notes.app 主 binary `strings` 可見以下類別名：

```
ICMSharingMenuController   (Share menu controller)
ICCollaborationController   (Collaboration logic)
ICInvitation                (Core Data entity)
ICInvitationsCoreDataIndexer
CKShare                     (透過 NotesShared 間接 link)
```

`/System/Library/PrivateFrameworks/` 中相關 framework（`NotesShared`、`NotesUI`、`NotesUIServices`、`NotesSiriUI` 等）實體檔案存在，但 macOS 26+ 採 dyld shared cache，`nm` / `strings` 無法直接 dump symbol table。

**成本估計**：
- `dyld-shared-cache-util` extract → 2h
- `class-dump -H` Notes binary + private frameworks → 1-2h
- 試打 `ICMSharingMenuController` 的 ObjC runtime 呼叫（ARC、main thread 要求、entitlement 檢查）→ 1-2d
- 總計 >= 2 天 spike，**仍不保證** 能繞過 entitlement / sandbox 限制

**Rationale for defer**：ROI 太低。即使 Path E 成功，結果仍受 Apple macOS 更新破壞，維運成本高。且 MCP server 作為 CLI binary 沒有 signed app bundle，某些 ObjC 呼叫可能會 trip sandbox。Path D 以很低成本提供 80% 的實用價值。

**Alternative considered**：
- 直接 spike Path E —— 當下 ROI 不合理，否決
- 完全刪除 Path E 的考慮 —— 不行，未來若 Apple 開放 public API 或第三方做出成功 demo，此 appendix 的 context 仍有價值

**Implication**：Path E 保留於 design appendix 作為未來參考，若有人想接手需另開獨立 issue（不 fold 進 #4）。

### Decision 5：Path F（Shortcuts / AppIntents）rejected — 無 ShareNoteIntent

**證據**：`strings /System/Applications/Notes.app/Contents/MacOS/Notes | grep 'Intent$'` 列出 Notes.app 50+ AppIntents，完整清單：

```
AddFileAttachmentIntent, AddLinkAttachmentIntent, AddOrRemoveNoteLockIntent,
AddTagsToNotesIntent, AppendMarkdownToNoteIntent, AppendToNoteIntent,
ApplyFormattingIntent, ChangeFolderViewSettingIntent, ChangeSettingIntent,
ChangeTagSelectionIntent, CloseNoteIntent, CloseNotesViewIntent,
CreateChecklistItemIntent, CreateFolderIntent, CreateNoteFromMarkdownIntent,
CreateNoteIntent, CreateTableIntent, CreateTagIntent, DeleteAttachmentsIntent,
DeleteChecklistItemsIntent, DeleteFoldersIntent, DeleteNotesIntent,
DeleteTablesIntent, DeleteTagsIntent, GetLinkedNotesIntent, ICAppIntentsManager,
ICNoteIntent, ICNoteIntentResponse, ICNotesFolderIntent, ICNotesFolderIntentResponse,
InsertAllMentionIntent, InsertMentionIntent, InsertNoteLinkIntent,
MoveNotesToFolderIntent, OpenAccountIntent, OpenAttachmentIntent,
OpenChecklistItemIntent, OpenFolderIntent, OpenManagedEntityIntent,
OpenNoteIntent, OpenNotesViewIntent, OpenTableIntent, OpenTagIntent,
OpenTopLevelFolderIntent, PinNotesIntent, RemoveTagsFromNotesIntent,
RenameFolderIntent, ReplaceSelectionIntent, SetAttachmentSizeIntent,
SetChecklistItemsCheckedIntent, SetParagraphStyleIntent,
ShowNotesAppSearchResultsIntent, ShowQuickNoteIntent, StartRecordingIntent
```

無任何包含 `Share` / `Invite` / `Collaborate` / `Participant` 字樣的 intent class。

Siri 文字模板中雖有 `"Bring me to my list of shared notes."` / `"Bring up my shared notes."`，但這些對應到既有 list intents（filter shared = true），屬於 **navigation** 而非 **creation**。

**Alternative considered**：使用者預先建立自訂 macOS Shortcut。被否決 —— 需要使用者手動設定，且仍需要底層 action 能建立 share，目前不存在。

**Implication**：Path F 不 spike、不實作。

### Decision 6：SQLite `ZICINVITATION` unblocks READ completely

**證據**：`sqlite3 NoteStore.sqlite ".schema ZICINVITATION"` 顯示 table schema：

```sql
ZICINVITATION:
  Z_PK, Z_ENT, Z_OPT,
  ZNOTECOUNT, ZNOTECOUNTRECURSIVE,
  ZSNIPPETATTACHMENTCOUNT, ZSNIPPETATTACHMENTTYPE,
  ZSUBFOLDERCOUNT, ZSUBFOLDERCOUNTRECURSIVE,
  ZACCOUNT,              -- FK to Account
  ZROOTOBJECT,           -- FK to ZICCLOUDSYNCINGOBJECT (the shared note/folder)
  Z3_ROOTOBJECT,
  ZCREATIONDATE, ZMODIFICATIONDATE, ZRECEIVEDDATE,
  ZROOTOBJECTTYPE,       -- "note" / "folder"
  ZSNIPPET, ZTITLE,
  ZSHAREURL,             -- ⭐ Public share URL (unique indexed)
  ZSERVERSHAREDATA,      -- CKShare serialized BLOB
  ZTHUMBNAILDATADARK, ZTHUMBNAILDATALIGHT
```

**Implication**：#3 Phase 2 的 `get_share_metadata` 可以 return 完整的 ZICINVITATION 欄位，**包含 `ZSHAREURL`** —— 這是 Notes.app 的公開 share URL，意義上等同「share link」。使用者拿到 URL 後可以貼到 Messages / Mail 手動分享。

**與 Path D 的互補關係**：
- `get_share_metadata` 回 `ZSHAREURL` → 使用者已有現成的 share URL，可直接複製貼
- `prepare_share_note` → 觸發 UI 讓 Notes.app 自己發新 URL 或邀請 email
- 兩者覆蓋 read-existing 和 create-new 兩個場景

### Decision 7：Module structure — 新增 `Sources/CheAppleNotesMCP/Sharing/`

**形狀**：
- `Sharing/SharingController.swift` —— 薄的 AppleScript wrapper 打開 Share menu
- `Sharing/InvitationReader.swift`（若不在 `NotesSQLite/` 下）—— 讀 `ZICINVITATION` table

**Alternative considered**：把所有新功能塞進 `NotesSQLite/` 和 `AppleScript/` —— 否決，因為「sharing」是一個獨立的 domain，單獨 module 讓 reader 一看就懂 scope。

## Risks / Trade-offs

- **[Risk] `ZSHAREURL` 可能為 nil 或 expired URL** → Mitigation：`get_share_metadata` 明確回報 URL 是否存在，不保證 URL 有效期（Apple 側決定）
- **[Risk] 私有 column 名稱在 macOS 升版改變** → Mitigation：既有 codebase 已有 `COALESCE(ZTITLE1, ZTITLE)` 的 defensive pattern，Phase 2 實作時套用同樣做法（例如 `COALESCE(ZSHAREURL, '')`）
- **[Risk] Path D 的 AppleScript 在未來 Notes.app 無 `File → Share Note...` menu item 時失效** → Mitigation：實作時加 error report「Share menu 不可用」，不要 silently no-op
- **[Risk] 使用者可能誤以為 MCP 能「完成」share** → Mitigation：tool description 和 issue acceptance criteria 要明確說「只打開 Share menu，不自動填 invitee」
- **[Trade-off] 放棄 Path E 意味著使用者永遠不能透過 MCP 一步完成 share** → 接受此 trade-off，等 Apple 開放或有第三方做出 demo 再回頭評估

## Open Questions

- （無顯著 open question — 所有 probe 已執行，所有 decision 有證據）
