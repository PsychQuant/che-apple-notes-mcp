# Sharing

此模組承接 Apple Notes 共享功能的 MCP tools(由 Spectra change **`apple-notes-sharing-scope`** 定案)。

> **目前僅為保留結構 — 尚無任何實作程式碼。**

## 將由哪些 issue 實作

| Issue | Scope | Spec |
|-------|-------|------|
| **#3** | READ 能力（`get_share_metadata`、`shared` filter）| `openspec/changes/apple-notes-sharing-scope/specs/apple-notes-sharing-metadata/spec.md` → 後續 archive 至 `openspec/specs/apple-notes-sharing-metadata/` |
| **#4** | WRITE workflow helpers（`prepare_share_note` / `prepare_share_folder`）| `openspec/changes/apple-notes-sharing-scope/specs/apple-notes-sharing-workflow/spec.md` → 後續 archive 至 `openspec/specs/apple-notes-sharing-workflow/` |

## 為什麼自成一個 module

參見 `apple-notes-sharing-scope/design.md` **Decision 7：Module structure — 新增 `Sources/CheAppleNotesMCP/Sharing/`**。簡述:

- `sharing` 是獨立 domain（invitation metadata + share workflow），跟既有 `AppleScript/` / `NotesSQLite/` / `Notes/` 的職責劃分正交
- 單獨 module 讓讀者一眼知道 scope：所有與 CloudKit share 相關的程式碼都在這裡
- Reader 結構與 Apple 私有 `NotesShared.framework` 的 `ICMSharingMenuController` / `ICCollaborationController` 對齊，未來若要接手 Path E 也有明確落腳處

## 預期檔案結構（實作時才會建立）

```
Sharing/
├── README.md                    ← 本檔
├── InvitationReader.swift       ← ZICINVITATION query + ShareMetadata struct(#3)
├── SharingController.swift      ← prepare_share_* 的 AppleScript wrapper(#4)
└── ShareMetadata.swift          ← struct 與 JSON encoding(#3,或 fold 進 NoteEntity.swift)
```

## 不會做的事

見 `apple-notes-sharing-scope/design.md` **Decisions 1/2/4/5**:

- ❌ 不做 public `CKShare` 呼叫(container 私有)
- ❌ 不做 URL scheme 呼叫(Notes.app 無 share URL path)
- ❌ 不做 UI automation 自動點按 Share sheet(fragile)
- ❌ 不做 AppIntents 呼叫(Notes.app 無 `ShareNoteIntent`)
- ⏸️ 不做 `NotesShared.framework` dlopen(延後,若要做需另開獨立 spike issue)

## Cross-reference

- Spectra change: `openspec/changes/apple-notes-sharing-scope/`
- GitHub issues: #3（READ）、#4（WRITE workflow）
