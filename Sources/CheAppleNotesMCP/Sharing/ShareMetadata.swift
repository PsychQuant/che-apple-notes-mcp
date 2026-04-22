import Foundation

/// CloudKit share metadata for a note or folder, sourced from the
/// `ZICINVITATION` SQLite table plus a heuristic fallback on
/// `ZSERVERSHAREDATA` / `ZZONEOWNERNAME`.
///
/// The raw `ZSERVERSHAREDATA` BLOB is intentionally not exposed — the
/// spec `apple-notes-sharing-metadata` forbids decoding CKShare internals.
/// Consumers receive `serverShareDataPresent: Bool` instead.
struct ShareMetadata {
    let isShared: Bool
    let rootObjectType: String?   // "note" / "folder" from ZROOTOBJECTTYPE
    let title: String?            // ZTITLE
    let snippet: String?          // ZSNIPPET
    let shareURL: String?         // ZSHAREURL — public URL Notes.app uses to invite
    let noteCount: Int?           // ZNOTECOUNT
    let subfolderCount: Int?      // ZSUBFOLDERCOUNT
    let receivedDate: Date?       // ZRECEIVEDDATE (participant perspective)
    let serverShareDataPresent: Bool

    /// Response for items that have no ZICINVITATION row and no shared
    /// heuristic hit. All optional fields are nil.
    static let notShared = ShareMetadata(
        isShared: false,
        rootObjectType: nil,
        title: nil,
        snippet: nil,
        shareURL: nil,
        noteCount: nil,
        subfolderCount: nil,
        receivedDate: nil,
        serverShareDataPresent: false
    )

    /// Dictionary for JSONSerialization. Optional fields are omitted (not
    /// null-valued) to keep the "not shared" response minimal, matching the
    /// spec scenario: `{"isShared": false}` with optional fields absent.
    /// `isShared` and `serverShareDataPresent` always present.
    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "isShared": isShared,
            "serverShareDataPresent": serverShareDataPresent,
        ]
        if let rootObjectType { dict["rootObjectType"] = rootObjectType }
        if let title { dict["title"] = title }
        if let snippet { dict["snippet"] = snippet }
        if let shareURL { dict["shareURL"] = shareURL }
        if let noteCount { dict["noteCount"] = noteCount }
        if let subfolderCount { dict["subfolderCount"] = subfolderCount }
        if let receivedDate {
            dict["receivedDate"] = Self.iso8601.string(from: receivedDate)
        }
        return dict
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
