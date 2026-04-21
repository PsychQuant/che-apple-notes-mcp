import Foundation

/// Centralised SQL templates. `ICFolder`, `ICNote`, `ICAccount` entity IDs are
/// looked up at runtime from `Z_PRIMARYKEY` because Apple can (and occasionally
/// does) renumber them across macOS releases.
enum SQLQueries {
    static let entityIDsQuery = "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY"

    /// Accounts: name + identifier
    static let listAccounts = """
        SELECT Z_PK, ZNAME, ZIDENTIFIER
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE Z_ENT = :entityID AND ZNAME IS NOT NULL
        ORDER BY ZNAME
        """

    /// Folders. We intentionally select multiple potential title/account FK
    /// columns and pick the non-null one at runtime — schema varies by macOS.
    ///
    /// `shared` is derived via heuristic because Notes' SQLite schema has no
    /// direct boolean. `ZSERVERSHAREDATA IS NOT NULL` means the user owns a
    /// CloudKit share for this folder; `ZZONEOWNERNAME IS NOT NULL` means
    /// someone shared this folder with the user. Either signal is sufficient.
    static let listFolders = """
        SELECT
            f.Z_PK,
            f.ZIDENTIFIER,
            COALESCE(f.ZTITLE2, f.ZTITLE) AS title,
            f.ZOWNER,
            f.ZPARENT,
            f.ZISHIDDENNOTECONTAINER,
            f.ZSORTORDER,
            a.ZNAME AS account_name,
            (f.ZSERVERSHAREDATA IS NOT NULL OR f.ZZONEOWNERNAME IS NOT NULL) AS shared
        FROM ZICCLOUDSYNCINGOBJECT f
        LEFT JOIN ZICCLOUDSYNCINGOBJECT a
            ON a.Z_PK = f.ZOWNER AND a.Z_ENT = :accountEntityID
        WHERE f.Z_ENT = :folderEntityID
        ORDER BY COALESCE(f.ZSORTORDER, 0), title
        """

    /// List notes in a folder (or all) with basic metadata. Body is fetched
    /// separately via `noteBodyBlob` because it's expensive.
    ///
    /// `shared` heuristic mirrors `listFolders` — see that doc comment.
    static let listNotes = """
        SELECT
            n.Z_PK,
            n.ZIDENTIFIER,
            COALESCE(n.ZTITLE1, n.ZTITLE) AS title,
            n.ZFOLDER,
            f.ZTITLE2 AS folder_title,
            a.ZNAME AS account_name,
            a.ZIDENTIFIER AS account_identifier,
            COALESCE(n.ZCREATIONDATE3, n.ZCREATIONDATE2, n.ZCREATIONDATE1, n.ZCREATIONDATE) AS creation_date,
            COALESCE(n.ZMODIFICATIONDATE1, n.ZMODIFICATIONDATE) AS modification_date,
            n.ZISPINNED,
            n.ZISPASSWORDPROTECTED,
            n.ZSNIPPET,
            (n.ZSERVERSHAREDATA IS NOT NULL OR n.ZZONEOWNERNAME IS NOT NULL) AS shared
        FROM ZICCLOUDSYNCINGOBJECT n
        LEFT JOIN ZICCLOUDSYNCINGOBJECT f
            ON f.Z_PK = n.ZFOLDER AND f.Z_ENT = :folderEntityID
        LEFT JOIN ZICCLOUDSYNCINGOBJECT a
            ON a.Z_PK = f.ZOWNER AND a.Z_ENT = :accountEntityID
        WHERE n.Z_ENT = :noteEntityID
          AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)
        """

    /// Single note by identifier.
    static let noteByIdentifier = listNotes + "\n  AND n.ZIDENTIFIER = :identifier LIMIT 1"

    /// Body blob lookup. ZICNOTEDATA.ZNOTE is FK to ZICCLOUDSYNCINGOBJECT.Z_PK
    /// of the note row.
    static let noteBodyBlob = """
        SELECT d.ZDATA, d.ZCRYPTOTAG IS NOT NULL AS encrypted
        FROM ZICNOTEDATA d
        WHERE d.ZNOTE = :notePK
        LIMIT 1
        """

    /// Core Data stores timestamps as NSDate reference-date (2001-01-01).
    /// Caller converts via `Date(timeIntervalSinceReferenceDate:)`.
    static func coreDataDate(_ raw: Double?) -> Date? {
        guard let raw, raw > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: raw)
    }
}
