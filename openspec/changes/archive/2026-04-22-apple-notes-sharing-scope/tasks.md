## 1. 更新 GitHub Issue #3（Phase 2 scope 擴充）

- [x] 1.1 更新 #3 body，把 _Decision 6：SQLite `ZICINVITATION` unblocks READ completely_ 的 schema 證據與 `ZSHAREURL` 發現寫進 Context 區塊
- [x] 1.2 在 #3 body 的 Expected 區塊對齊 _System SHALL provide a get_share_metadata tool that returns ZICINVITATION metadata_，列出最終 response 欄位（`shareURL`、`rootObjectType`、`receivedDate`、`serverShareDataPresent` 等）
- [x] 1.3 在 #3 body Expected 區塊新增 _Read tools SHALL accept an optional shared filter parameter_ 對應的 `shared: bool?` 參數 across `search_notes` / `list_notes` / `list_folders`
- [x] 1.4 #3 body 新增 error semantics 小節，說明 _AppleScript fallback SHALL refuse share metadata queries when SQLite is unavailable_ 的 error shape（`featureRequiresSQLite("get_share_metadata")`）
- [x] 1.5 #3 body 的 Context 確認：「System SHALL expose shared status on every note and folder read output」已由 #2 交付；記錄 `shared: bool` 現為 #3 的 baseline 而非新需求

## 2. 更新 GitHub Issue #4（Phase 3 scope 收斂）

- [x] 2.1 重寫 #4 title 和 Problem 區塊：從「create and manage Apple Notes share invitations」改為「workflow helpers for initiating share via Notes.app」，反映 _Decision 3：Path D（workflow helper）chosen as primary WRITE path_
- [x] 2.2 #4 body Expected 區塊放入 _System SHALL provide prepare_share_note workflow helper_ 的 tool contract（activate + menu trigger + 不自動填 email）
- [x] 2.3 #4 body Expected 區塊放入 _System SHALL provide prepare_share_folder workflow helper_ 的對應 folder 版 contract
- [x] 2.4 #4 body 新增「Explicitly Out of Scope」區塊，錨定 _System SHALL NOT provide direct share creation tools_（`create_share_link` / `invite_participant` / `revoke_share` / `list_participants` 全部不做）
- [x] 2.5 #4 body 加上 fallback 行為說明：_Workflow tools SHALL degrade predictably when Notes.app is not responding_，列 timeout 與 error message 契約

## 3. 記錄已否決與延後的技術路徑

- [x] 3.1 在 #4 body appendix 引用 design.md 的 _Decision 1：Path A（public CKShare）rejected — CloudKit container 私有_，並保留 `Info.plist` `CKSharingSupported=true` 的證據鏈結
- [x] 3.2 在 #4 body appendix 引用 _Decision 2：Path B（URL scheme）rejected — 無 share-related URL path_，列出 `applenotes://` 的 3 條實際 path
- [x] 3.3 在 #4 body appendix 引用 _Decision 5：Path F（Shortcuts / AppIntents）rejected — 無 ShareNoteIntent_，附上 Notes.app 50+ intents 清單證據
- [x] 3.4 在 #4 body appendix 引用 _Decision 4：Path E（private framework dlopen）deferred — 高成本低收益_，提供未來若要接手需重新評估的成本估算
- [x] 3.5 評估是否要另開 standalone issue 追蹤 Path E（決策文檔 + spike proposal），若決定要開，在本 tasks 完成後執行（不 fold 進 #4）— **決定：不另開**。理由：#4 appendix 的 Decision 4 已完整記錄成本與證據，當下無人接手 demand，開空殼 issue 會成 zombie。未來若要接手，從該 appendix 再開新 issue 即可。

## 4. Capability 與模組結構對齊

- [x] 4.1 確認 `apple-notes-sharing-metadata` spec 的所有 requirement 將由 #3 實作，在 #3 body 的 Scope Changes 區塊明確聲明引用本 Spectra change 作為 source of truth
- [x] 4.2 確認 `apple-notes-sharing-workflow` spec 的所有 requirement 將由 #4 實作，#4 body 同步引用
- [x] 4.3 在 `Sources/CheAppleNotesMCP/Sharing/` 下預留 README.md stub 說明 _Decision 7：Module structure — 新增 `Sources/CheAppleNotesMCP/Sharing/`_ 是為了承接 #4 的 workflow helper 程式碼（**只建 README，不寫任何實作**）

## 5. Archive 與交接

- [x] 5.1 跑 `spectra validate apple-notes-sharing-scope` 確認所有 artifact 無 Critical / Warning
- [x] 5.2 在 #3 和 #4 各自的 body 尾端留下本 Spectra change 的交叉引用（路徑 `openspec/changes/apple-notes-sharing-scope/`）
- [x] 5.3 完成後跑 `/spectra-archive apple-notes-sharing-scope` 把 change 歸檔到 `openspec/changes/archive/`，specs 搬到 `openspec/specs/` — **留給使用者決定**：issue body 已更新、README stub 已建立、validate 通過。archive 是本 apply 完成後的獨立步驟，使用者可選擇立即 archive 或等 #3/#4 實作後再一起 archive。
