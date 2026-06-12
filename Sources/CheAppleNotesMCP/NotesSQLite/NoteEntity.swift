import Foundation

/// Identifier used by AppleScript (`note id "x-coredata://..."`). Persisted in
/// the SQLite column ZIDENTIFIER. We surface this directly to callers so a note
/// returned from SQLite can be targeted by AS write tools.
typealias NoteID = String

struct Account {
    let pk: Int64           // Z_PK
    let name: String        // ZNAME
    let identifier: String  // ZIDENTIFIER (e.g., "LocalAccount", "<icloud-uuid>")
}

struct Folder {
    let pk: Int64
    let identifier: String  // ZIDENTIFIER
    let title: String       // ZTITLE2 or ZTITLE
    let accountPK: Int64?   // ZACCOUNT4 or similar FK
    let accountName: String?
    let parentPK: Int64?    // ZPARENT FK for nested folders
    let isHiddenContainer: Bool
    let sortOrder: Int?
    /// True when the folder participates in a CloudKit share — either the user
    /// owns it (ZSERVERSHAREDATA present) or it was shared with them
    /// (ZZONEOWNERNAME present). AppleScript `shared of folder` is preferred
    /// when available; SQLite heuristic is a fallback.
    let shared: Bool
}

struct Note {
    let pk: Int64
    let identifier: NoteID  // ZIDENTIFIER (UUID only)
    let title: String
    let folderPK: Int64?
    let folderName: String?
    let accountName: String?
    let accountIdentifier: String?  // account UUID, used to build AS id
    let creationDate: Date?
    let modificationDate: Date?
    let isPinned: Bool
    let isPasswordProtected: Bool
    let snippet: String?  // ZSNIPPET from SQLite (preview line)
    /// True when this note (or its enclosing folder) participates in a CloudKit
    /// share. See `Folder.shared` for the heuristic.
    let shared: Bool

    /// Construct the AppleScript `note id "..."` URL form. Needed because
    /// Notes.app's AppleScript dictionary expects `x-coredata://<acct-uuid>/ICNote/p<Z_PK>`
    /// while SQLite ZIDENTIFIER stores just the note UUID.
    var appleScriptID: String {
        guard let acct = accountIdentifier, !acct.isEmpty else {
            return identifier  // fallback — write ops may fail
        }
        return "x-coredata://\(acct)/ICNote/p\(pk)"
    }

    /// Optional body payload. Populated by `get_note` or `list_notes` with
    /// `include_body=true`. nil means not requested; empty string means empty note.
    var bodyText: String?
    var bodyHTML: String?

    /// Set to true when the note is locked (body is AES-encrypted and we didn't
    /// attempt decode) or when protobuf decode failed. Callers may fall back to
    /// AppleScript for body.
    var bodyDecodeError: Bool = false

    /// Hashtags carried by this note in literal in-note form (e.g. "#Deal-Flow"),
    /// deduplicated case-insensitively and sorted alphabetically. nil means tags
    /// could not be resolved (AppleScript source, or a schema without hashtag
    /// entities) — callers must surface null, never [], so "unknown" is
    /// distinguishable from "no tags".
    var tags: [String]? = nil
}

/// One distinct tag as shown by the Notes.app Tag Browser, aggregated across
/// accounts (the DB stores `#x` in iCloud and `#x` in On My Mac as separate
/// ICHashtag rows; `list_tags` merges them by standardized content).
struct TagSummary {
    /// Display form with leading '#' (ZDISPLAYTEXT stores it without one).
    let name: String
    /// Lowercased ZSTANDARDIZEDCONTENT — the matching key for tag filters.
    let standardized: String
    /// Count of live (non-deleted) notes carrying this tag, across the
    /// queried accounts. Orphan tags report 0.
    let noteCount: Int
    /// Account names where this tag exists, sorted.
    let accounts: [String]
}

struct Attachment {
    let pk: Int64
    let identifier: String
    let filename: String?
    let typeUTI: String?
    let parentNotePK: Int64?
    /// Local path inside `~/Library/Group Containers/group.com.apple.notes/Accounts/<acct>/Media/<attach>/`.
    /// Requires FDA to read.
    var localPath: String?
}
