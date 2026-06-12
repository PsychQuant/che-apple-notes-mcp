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
    ///
    /// The query is exposed as `listFoldersBase` + `listFoldersOrderSuffix`
    /// so the reader's shared-filter variant can splice an `AND` clause
    /// before the ORDER BY without string-search fragility. `listFolders`
    /// stays as a backwards-compatible full query for unfiltered callers.
    static let listFoldersBase = """
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
        """

    static let listFoldersOrderSuffix = """
        ORDER BY COALESCE(f.ZSORTORDER, 0), title
        """

    static let listFolders = listFoldersBase + "\n" + listFoldersOrderSuffix

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

    /// ZICINVITATION carries CloudKit share metadata for the root note/folder
    /// it references via ZROOTOBJECT (FK to ZICCLOUDSYNCINGOBJECT.Z_PK).
    ///
    /// `server_share_data_present` is computed as a bool — we never select the
    /// raw BLOB because spec forbids deserializing CKShare (`apple-notes-sharing-metadata`
    /// requirement: tool SHALL NOT include a decoded representation of
    /// ZSERVERSHAREDATA).
    static let shareMetadataByRootIdentifier = """
        SELECT
            i.ZROOTOBJECTTYPE,
            i.ZTITLE,
            i.ZSNIPPET,
            i.ZSHAREURL,
            i.ZNOTECOUNT,
            i.ZSUBFOLDERCOUNT,
            i.ZRECEIVEDDATE,
            (i.ZSERVERSHAREDATA IS NOT NULL) AS server_share_data_present
        FROM ZICINVITATION i
        JOIN ZICCLOUDSYNCINGOBJECT r
            ON r.Z_PK = i.ZROOTOBJECT
        WHERE r.ZIDENTIFIER = :rootIdentifier
        LIMIT 1
        """

    /// Heuristic check for items without a ZICINVITATION row but still shared
    /// via presence of ZSERVERSHAREDATA (owner) or ZZONEOWNERNAME (participant).
    /// Used as fallback when `shareMetadataByRootIdentifier` returns no row.
    ///
    /// Projects two columns so the reader can populate
    /// `ShareMetadata.serverShareDataPresent` truthfully even on this fallback
    /// path — the aggregate `shared` bit is not enough because it conflates
    /// owner and participant cases.
    ///
    /// `Z_ENT IN (:noteEntityID, :folderEntityID)` guards against ZIDENTIFIER
    /// collision with non-shareable entity kinds (accounts, attachments, etc).
    /// Notes assigns globally-unique UUIDs today so this is defense in depth.
    static let sharedRootObjectHeuristic = """
        SELECT
            (ZSERVERSHAREDATA IS NOT NULL OR ZZONEOWNERNAME IS NOT NULL) AS shared,
            (ZSERVERSHAREDATA IS NOT NULL) AS server_share_data_present
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE ZIDENTIFIER = :rootIdentifier
          AND Z_ENT IN (:noteEntityID, :folderEntityID)
        LIMIT 1
        """

    // MARK: - Tags (apple-notes-tags)

    /// UTI that marks an inline attachment row as a hashtag occurrence. Other
    /// inline attachment types exist (mentions, note links) and must never be
    /// treated as tags.
    static let hashtagUTI = "com.apple.notes.inlinetextattachment.hashtag"

    /// Normalized tag token expression for an inline-attachment row with the
    /// given alias. `ZTOKENCONTENTIDENTIFIER` matches the hashtag entity's
    /// `ZSTANDARDIZEDCONTENT`; `LTRIM(ZALTTEXT, '#')` is the fallback when the
    /// token column is unpopulated. `UPPER()` folds the casing drift between
    /// macOS versions (standardized content is uppercase on macOS 26 but has
    /// been reported lowercase elsewhere).
    static func tagToken(_ alias: String) -> String {
        "UPPER(COALESCE(\(alias).ZTOKENCONTENTIDENTIFIER, LTRIM(\(alias).ZALTTEXT, '#')))"
    }

    /// Hashtag entities — the Tag Browser's source of truth, one row per
    /// distinct tag per account. Orphan tags (zero live notes) still have a
    /// row here. The account FK column drifts across model versions, hence
    /// the COALESCE chain (ZACCOUNT3 on macOS 26).
    ///
    /// Composable: the reader appends `AND a.ZNAME = :accountName` when an
    /// account filter is requested. No trailing ORDER BY for that reason —
    /// sorting happens in Swift after cross-account aggregation.
    static let listHashtags = """
        SELECT
            h.ZDISPLAYTEXT,
            h.ZSTANDARDIZEDCONTENT,
            UPPER(h.ZSTANDARDIZEDCONTENT) AS token,
            a.ZNAME AS account_name
        FROM ZICCLOUDSYNCINGOBJECT h
        LEFT JOIN ZICCLOUDSYNCINGOBJECT a
            ON a.Z_PK = COALESCE(h.ZACCOUNT3, h.ZACCOUNT2, h.ZACCOUNT1, h.ZACCOUNT) AND a.Z_ENT = :accountEntityID
        WHERE h.Z_ENT = :hashtagEntityID
          AND (h.ZMARKEDFORDELETION IS NULL OR h.ZMARKEDFORDELETION = 0)
        """

    /// Live-note counts per tag token per account. Inner join to the owning
    /// note filters deleted notes (and dangling attachment rows) out of the
    /// counts; DISTINCT collapses repeated occurrences of the same tag inside
    /// one note.
    ///
    /// Split base + suffix so the reader can splice `AND a.ZNAME = :accountName`
    /// before GROUP BY, mirroring the listFolders composition pattern.
    static let tagNoteCountsBase = """
        SELECT
            \(tagToken("t")) AS token,
            COUNT(DISTINCT n.Z_PK) AS note_count
        FROM ZICCLOUDSYNCINGOBJECT t
        JOIN ZICCLOUDSYNCINGOBJECT n
            ON n.Z_PK = COALESCE(t.ZNOTE1, t.ZNOTE)
           AND n.Z_ENT = :noteEntityID
           AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)
        LEFT JOIN ZICCLOUDSYNCINGOBJECT f
            ON f.Z_PK = n.ZFOLDER AND f.Z_ENT = :folderEntityID
        LEFT JOIN ZICCLOUDSYNCINGOBJECT a
            ON a.Z_PK = f.ZOWNER AND a.Z_ENT = :accountEntityID
        WHERE t.Z_ENT = :inlineAttachmentEntityID
          AND COALESCE(t.ZTYPEUTI1, t.ZTYPEUTI) = :hashtagUTI
          AND (t.ZMARKEDFORDELETION IS NULL OR t.ZMARKEDFORDELETION = 0)
        """

    static let tagNoteCountsGroupSuffix = """
        GROUP BY token
        """

    /// Every hashtag occurrence with its owning note PK — fetched in one pass
    /// and grouped in Swift to enrich note reads with a `tags` array without
    /// an N+1 per-note lookup. ZALTTEXT is the literal in-note text ("#tag").
    static let noteHashtagOccurrences = """
        SELECT
            COALESCE(t.ZNOTE1, t.ZNOTE) AS note_pk,
            t.ZALTTEXT,
            \(tagToken("t")) AS token
        FROM ZICCLOUDSYNCINGOBJECT t
        WHERE t.Z_ENT = :inlineAttachmentEntityID
          AND COALESCE(t.ZTYPEUTI1, t.ZTYPEUTI) = :hashtagUTI
          AND (t.ZMARKEDFORDELETION IS NULL OR t.ZMARKEDFORDELETION = 0)
          AND COALESCE(t.ZNOTE1, t.ZNOTE) IS NOT NULL
        """

    /// All distinct standardized tag contents — compared in Swift against
    /// user input to produce get_notes_by_tag's zero-match warnings.
    static let knownTagStandardizedContents = """
        SELECT DISTINCT ZSTANDARDIZEDCONTENT
        FROM ZICCLOUDSYNCINGOBJECT
        WHERE Z_ENT = :hashtagEntityID
          AND ZSTANDARDIZEDCONTENT IS NOT NULL
          AND (ZMARKEDFORDELETION IS NULL OR ZMARKEDFORDELETION = 0)
        """

    /// Membership predicate for the notes query: note carries at least one of
    /// the tags bound to the given named parameters. Caller passes one
    /// parameter for "any-of" semantics across several tags, or calls once
    /// per tag (AND-ed) for "all" semantics.
    static func tagFilterSubquery(tokenParams: [String]) -> String {
        let list = tokenParams.map { "UPPER(\($0))" }.joined(separator: ", ")
        return """
            n.Z_PK IN (SELECT COALESCE(t.ZNOTE1, t.ZNOTE) FROM ZICCLOUDSYNCINGOBJECT t
                WHERE t.Z_ENT = :inlineAttachmentEntityID
                  AND COALESCE(t.ZTYPEUTI1, t.ZTYPEUTI) = :hashtagUTI
                  AND (t.ZMARKEDFORDELETION IS NULL OR t.ZMARKEDFORDELETION = 0)
                  AND \(tagToken("t")) IN (\(list)))
            """
    }

    /// Core Data stores timestamps as NSDate reference-date (2001-01-01).
    /// Caller converts via `Date(timeIntervalSinceReferenceDate:)`.
    static func coreDataDate(_ raw: Double?) -> Date? {
        guard let raw, raw > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: raw)
    }
}
