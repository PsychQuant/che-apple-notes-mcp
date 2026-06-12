import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Read-only wrapper around Notes.app's `NoteStore.sqlite`. All public methods
/// throw on failure; typical call sites route to AppleScript fallback on throw.
final class NotesStoreReader {
    private var db: OpaquePointer?
    private let path: String
    private var entityIDs: [String: Int32] = [:]

    init(at url: URL = Capabilities.noteStoreURL) throws {
        self.path = url.path

        let uri = "file:\(url.path)?mode=ro&cache=shared"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(uri, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errstr(rc))
            throw NotesSQLiteError.cannotOpen(path: url.path, code: rc)
                .prepending("\(msg)")
        }

        // Populate entity ID cache from Z_PRIMARYKEY.
        try loadEntityIDs()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Entity ID resolution

    private func loadEntityIDs() throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.entityIDsQuery, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.entityIDsQuery,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let ent = sqlite3_column_int(stmt, 0)
            if let namePtr = sqlite3_column_text(stmt, 1) {
                let name = String(cString: namePtr)
                entityIDs[name] = ent
            }
        }
    }

    func entityID(for name: String) throws -> Int32 {
        guard let id = entityIDs[name] else {
            throw NotesSQLiteError.entityNotFound(name)
        }
        return id
    }

    // MARK: - Checkpoint

    /// Force a passive WAL checkpoint. Call after AppleScript writes to pick up
    /// latest changes without waiting for Notes.app's idle flush.
    func checkpoint() {
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
    }

    // MARK: - Accounts

    func listAccounts() throws -> [Account] {
        let accountEnt = try entityID(for: "ICAccount")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.listAccounts, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.listAccounts,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        try bind(stmt: stmt, name: ":entityID", value: Int64(accountEnt))

        var results: [Account] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = sqlite3_column_int64(stmt, 0)
            let name = columnText(stmt, 1) ?? "(unnamed)"
            let ident = columnText(stmt, 2) ?? ""
            results.append(Account(pk: pk, name: name, identifier: ident))
        }
        return results
    }

    // MARK: - Folders

    /// List folders with an optional shared filter.
    /// - Parameter sharedOnly: nil → all folders; true → only shared; false → only unshared.
    func listFolders(sharedOnly: Bool? = nil) throws -> [Folder] {
        let folderEnt = try entityID(for: "ICFolder")
        let accountEnt = try entityID(for: "ICAccount")

        // Compose from base + order suffix so we can splice a filter predicate
        // between them without relying on a string-search anchor. If
        // SQLQueries.listFolders ever drifts from this composition, the
        // listFoldersIsComposableFromBaseAndOrderSuffix test catches it.
        var sql = SQLQueries.listFoldersBase
        if let sharedOnly {
            let sharedPredicate = sharedOnly
                ? "(f.ZSERVERSHAREDATA IS NOT NULL OR f.ZZONEOWNERNAME IS NOT NULL)"
                : "(f.ZSERVERSHAREDATA IS NULL AND f.ZZONEOWNERNAME IS NULL)"
            sql += "\n  AND \(sharedPredicate)"
        }
        sql += "\n" + SQLQueries.listFoldersOrderSuffix

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: sql,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        try bind(stmt: stmt, name: ":folderEntityID", value: Int64(folderEnt))
        try bind(stmt: stmt, name: ":accountEntityID", value: Int64(accountEnt))

        var results: [Folder] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Folder(
                pk: sqlite3_column_int64(stmt, 0),
                identifier: columnText(stmt, 1) ?? "",
                title: columnText(stmt, 2) ?? "(untitled)",
                accountPK: columnInt64Optional(stmt, 3),
                accountName: columnText(stmt, 7),
                parentPK: columnInt64Optional(stmt, 4),
                isHiddenContainer: sqlite3_column_int(stmt, 5) != 0,
                sortOrder: columnIntOptional(stmt, 6),
                shared: sqlite3_column_int(stmt, 8) != 0
            ))
        }
        return results
    }

    // MARK: - Notes

    struct NoteListOptions {
        var folderIdentifier: String? = nil
        var accountName: String? = nil
        var pinned: Bool? = nil
        var locked: Bool? = nil
        var createdAfter: Date? = nil
        var createdBefore: Date? = nil
        var modifiedAfter: Date? = nil
        var modifiedBefore: Date? = nil
        var limit: Int? = nil
        var sortDescending: Bool = true  // newest first by default
        var includeBody: Bool = false
        /// nil: no share filter. true: only shared items. false: only unshared.
        /// Heuristic: `ZSERVERSHAREDATA IS NOT NULL OR ZZONEOWNERNAME IS NOT NULL`.
        var sharedOnly: Bool? = nil
        /// Tag filter. Inputs accepted with or without leading '#'; matched
        /// case-insensitively against the standardized tag token. nil/empty:
        /// no tag filter. Requires the ICInlineAttachment entity — throws
        /// entityNotFound on schemas without it rather than silently ignoring
        /// the filter.
        var tags: [String]? = nil
        /// false (default): note must carry at least one of `tags`.
        /// true: note must carry every tag in `tags`.
        var tagsMatchAll: Bool = false
    }

    func listNotes(options: NoteListOptions = NoteListOptions()) throws -> [Note] {
        let noteEnt = try entityID(for: "ICNote")
        let folderEnt = try entityID(for: "ICFolder")
        let accountEnt = try entityID(for: "ICAccount")

        var sql = SQLQueries.listNotes
        var extras: [String] = []

        // folder_id may arrive as either a bare ZIDENTIFIER UUID or the
        // AppleScript URL form `x-coredata://<store-uuid>/ICFolder/p<PK>`.
        // Extract the PK and filter on ZFOLDER when the URL form is given.
        let folderPKFromURL = Self.extractCoreDataPK(options.folderIdentifier)
        if folderPKFromURL != nil {
            extras.append("n.ZFOLDER = :folderPK")
        } else if options.folderIdentifier != nil {
            extras.append("f.ZIDENTIFIER = :folderIdent")
        }
        if options.accountName != nil {
            extras.append("a.ZNAME = :accountName")
        }
        if let pinned = options.pinned {
            extras.append("COALESCE(n.ZISPINNED, 0) = \(pinned ? 1 : 0)")
        }
        if let locked = options.locked {
            extras.append("COALESCE(n.ZISPASSWORDPROTECTED, 0) = \(locked ? 1 : 0)")
        }
        if options.createdAfter != nil {
            extras.append("COALESCE(n.ZCREATIONDATE3, n.ZCREATIONDATE2, n.ZCREATIONDATE1, n.ZCREATIONDATE) >= :createdAfter")
        }
        if options.createdBefore != nil {
            extras.append("COALESCE(n.ZCREATIONDATE3, n.ZCREATIONDATE2, n.ZCREATIONDATE1, n.ZCREATIONDATE) <= :createdBefore")
        }
        if options.modifiedAfter != nil {
            extras.append("COALESCE(n.ZMODIFICATIONDATE1, n.ZMODIFICATIONDATE) >= :modifiedAfter")
        }
        if options.modifiedBefore != nil {
            extras.append("COALESCE(n.ZMODIFICATIONDATE1, n.ZMODIFICATIONDATE) <= :modifiedBefore")
        }
        if let sharedOnly = options.sharedOnly {
            if sharedOnly {
                extras.append("(n.ZSERVERSHAREDATA IS NOT NULL OR n.ZZONEOWNERNAME IS NOT NULL)")
            } else {
                extras.append("(n.ZSERVERSHAREDATA IS NULL AND n.ZZONEOWNERNAME IS NULL)")
            }
        }

        // Tag filter. Entity resolution happens here (not at the top) so
        // schemas without ICInlineAttachment only fail when a tag filter is
        // actually requested — plain listNotes keeps working.
        var tagTokens: [String] = []
        if let tags = options.tags, !tags.isEmpty {
            _ = try entityID(for: "ICInlineAttachment")
            tagTokens = tags.map { Self.normalizeTagInput($0) }
            if options.tagsMatchAll {
                for i in tagTokens.indices {
                    extras.append(SQLQueries.tagFilterSubquery(tokenParams: [":tagTok\(i)"]))
                }
            } else {
                let params = tagTokens.indices.map { ":tagTok\($0)" }
                extras.append(SQLQueries.tagFilterSubquery(tokenParams: params))
            }
        }

        if !extras.isEmpty {
            sql += "\n  AND " + extras.joined(separator: "\n  AND ")
        }
        sql += "\nORDER BY modification_date \(options.sortDescending ? "DESC" : "ASC")"
        if let limit = options.limit {
            sql += "\nLIMIT \(limit)"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: sql,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        try bind(stmt: stmt, name: ":noteEntityID", value: Int64(noteEnt))
        try bind(stmt: stmt, name: ":folderEntityID", value: Int64(folderEnt))
        try bind(stmt: stmt, name: ":accountEntityID", value: Int64(accountEnt))
        if let pk = folderPKFromURL {
            try bind(stmt: stmt, name: ":folderPK", value: pk)
        } else if let ident = options.folderIdentifier {
            try bind(stmt: stmt, name: ":folderIdent", value: ident)
        }
        if let name = options.accountName {
            try bind(stmt: stmt, name: ":accountName", value: name)
        }
        if let d = options.createdAfter {
            try bind(stmt: stmt, name: ":createdAfter", value: d.timeIntervalSinceReferenceDate)
        }
        if let d = options.createdBefore {
            try bind(stmt: stmt, name: ":createdBefore", value: d.timeIntervalSinceReferenceDate)
        }
        if let d = options.modifiedAfter {
            try bind(stmt: stmt, name: ":modifiedAfter", value: d.timeIntervalSinceReferenceDate)
        }
        if let d = options.modifiedBefore {
            try bind(stmt: stmt, name: ":modifiedBefore", value: d.timeIntervalSinceReferenceDate)
        }
        if !tagTokens.isEmpty {
            try bind(stmt: stmt, name: ":inlineAttachmentEntityID",
                     value: Int64(try entityID(for: "ICInlineAttachment")))
            try bind(stmt: stmt, name: ":hashtagUTI", value: SQLQueries.hashtagUTI)
            for (i, token) in tagTokens.enumerated() {
                try bind(stmt: stmt, name: ":tagTok\(i)", value: token)
            }
        }

        var notes: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var note = Note(
                pk: sqlite3_column_int64(stmt, 0),
                identifier: columnText(stmt, 1) ?? "",
                title: columnText(stmt, 2) ?? "(untitled)",
                folderPK: columnInt64Optional(stmt, 3),
                folderName: columnText(stmt, 4),
                accountName: columnText(stmt, 5),
                accountIdentifier: columnText(stmt, 6),
                creationDate: SQLQueries.coreDataDate(columnDoubleOptional(stmt, 7)),
                modificationDate: SQLQueries.coreDataDate(columnDoubleOptional(stmt, 8)),
                isPinned: sqlite3_column_int(stmt, 9) != 0,
                isPasswordProtected: sqlite3_column_int(stmt, 10) != 0,
                snippet: columnText(stmt, 11),
                shared: sqlite3_column_int(stmt, 12) != 0,
                bodyText: nil,
                bodyHTML: nil
            )

            if options.includeBody {
                attachBody(to: &note)
            }
            notes.append(note)
        }
        attachTags(to: &notes)
        return notes
    }

    func getNote(identifier: String, includeBody: Bool = true) throws -> Note? {
        var options = NoteListOptions()
        options.includeBody = includeBody
        var notes = try listNotes(options: options).filter { $0.identifier == identifier }
        return notes.first.map { n in
            var copy = n
            if includeBody && copy.bodyText == nil && !copy.isPasswordProtected {
                attachBody(to: &copy)
            }
            return copy
        }
    }

    // MARK: - Share metadata

    /// Resolve share metadata for a note or folder by its `ZIDENTIFIER`.
    ///
    /// Two-stage lookup:
    /// 1. Query `ZICINVITATION` joined to `ZICCLOUDSYNCINGOBJECT` via ZROOTOBJECT.
    ///    If a row exists, return full metadata.
    /// 2. Fall back to heuristic on the root item itself (ZSERVERSHAREDATA /
    ///    ZZONEOWNERNAME). A hit yields `{isShared: true}` with other fields
    ///    nil — the item is shared but lacks a dedicated invitation record.
    /// 3. Neither hits → `ShareMetadata.notShared`.
    func getShareMetadata(identifier: String) throws -> ShareMetadata {
        if let fromInvitation = try shareMetadataFromInvitation(identifier: identifier) {
            return fromInvitation
        }
        if let heuristic = try rootObjectSharedHeuristic(identifier: identifier), heuristic.shared {
            return ShareMetadata(
                isShared: true,
                rootObjectType: nil,
                title: nil,
                snippet: nil,
                shareURL: nil,
                noteCount: nil,
                subfolderCount: nil,
                receivedDate: nil,
                serverShareDataPresent: heuristic.serverShareDataPresent
            )
        }
        return .notShared
    }

    private func shareMetadataFromInvitation(identifier: String) throws -> ShareMetadata? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.shareMetadataByRootIdentifier, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.shareMetadataByRootIdentifier,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt, name: ":rootIdentifier", value: identifier)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return ShareMetadata(
            isShared: true,
            rootObjectType: columnText(stmt, 0),
            title: columnText(stmt, 1),
            snippet: columnText(stmt, 2),
            shareURL: columnText(stmt, 3),
            noteCount: columnIntOptional(stmt, 4),
            subfolderCount: columnIntOptional(stmt, 5),
            receivedDate: SQLQueries.coreDataDate(columnDoubleOptional(stmt, 6)),
            serverShareDataPresent: sqlite3_column_int(stmt, 7) != 0
        )
    }

    private struct HeuristicRow {
        let shared: Bool
        let serverShareDataPresent: Bool
    }

    private func rootObjectSharedHeuristic(identifier: String) throws -> HeuristicRow? {
        let noteEnt = try entityID(for: "ICNote")
        let folderEnt = try entityID(for: "ICFolder")

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.sharedRootObjectHeuristic, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.sharedRootObjectHeuristic,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt, name: ":rootIdentifier", value: identifier)
        try bind(stmt: stmt, name: ":noteEntityID", value: Int64(noteEnt))
        try bind(stmt: stmt, name: ":folderEntityID", value: Int64(folderEnt))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return HeuristicRow(
            shared: sqlite3_column_int(stmt, 0) != 0,
            serverShareDataPresent: sqlite3_column_int(stmt, 1) != 0
        )
    }

    // MARK: - Search

    func searchNotes(
        keywords: [String],
        matchAll: Bool = false,
        limit: Int? = nil,
        sharedOnly: Bool? = nil
    ) throws -> [Note] {
        guard !keywords.isEmpty else { return [] }

        let noteEnt = try entityID(for: "ICNote")
        let folderEnt = try entityID(for: "ICFolder")
        let accountEnt = try entityID(for: "ICAccount")

        let joiner = matchAll ? " AND " : " OR "
        let conds = (0..<keywords.count).map { i in
            "(LOWER(COALESCE(n.ZTITLE1, n.ZTITLE, '')) LIKE :kw\(i) OR LOWER(COALESCE(n.ZSNIPPET, '')) LIKE :kw\(i))"
        }.joined(separator: joiner)

        var sql = SQLQueries.listNotes + "\n  AND (\(conds))"
        if let sharedOnly {
            sql += sharedOnly
                ? "\n  AND (n.ZSERVERSHAREDATA IS NOT NULL OR n.ZZONEOWNERNAME IS NOT NULL)"
                : "\n  AND (n.ZSERVERSHAREDATA IS NULL AND n.ZZONEOWNERNAME IS NULL)"
        }
        sql += "\nORDER BY modification_date DESC"
        if let limit { sql += "\nLIMIT \(limit)" }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: sql,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }

        try bind(stmt: stmt, name: ":noteEntityID", value: Int64(noteEnt))
        try bind(stmt: stmt, name: ":folderEntityID", value: Int64(folderEnt))
        try bind(stmt: stmt, name: ":accountEntityID", value: Int64(accountEnt))
        for (i, kw) in keywords.enumerated() {
            try bind(stmt: stmt, name: ":kw\(i)", value: "%\(kw.lowercased())%")
        }

        var results: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(Note(
                pk: sqlite3_column_int64(stmt, 0),
                identifier: columnText(stmt, 1) ?? "",
                title: columnText(stmt, 2) ?? "(untitled)",
                folderPK: columnInt64Optional(stmt, 3),
                folderName: columnText(stmt, 4),
                accountName: columnText(stmt, 5),
                accountIdentifier: columnText(stmt, 6),
                creationDate: SQLQueries.coreDataDate(columnDoubleOptional(stmt, 7)),
                modificationDate: SQLQueries.coreDataDate(columnDoubleOptional(stmt, 8)),
                isPinned: sqlite3_column_int(stmt, 9) != 0,
                isPasswordProtected: sqlite3_column_int(stmt, 10) != 0,
                snippet: columnText(stmt, 11),
                shared: sqlite3_column_int(stmt, 12) != 0,
                bodyText: nil,
                bodyHTML: nil
            ))
        }
        attachTags(to: &results)
        return results
    }

    // MARK: - Tags

    /// Strip the leading '#' and surrounding whitespace from user-supplied tag
    /// input. The only normalization v1 performs — matching is then
    /// case-insensitive against ZSTANDARDIZEDCONTENT / ZTOKENCONTENTIDENTIFIER.
    static func normalizeTagInput(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        return s
    }

    /// Enumerate tags across accounts (or one account), with live-note counts.
    /// Tags present in several accounts are merged by standardized content and
    /// report the union of account names; counts sum across the merged rows
    /// (a note belongs to exactly one account, so the sum stays distinct).
    func listTags(accountName: String? = nil) throws -> [TagSummary] {
        let hashtagEnt = try entityID(for: "ICHashtag")
        let attachmentEnt = try entityID(for: "ICInlineAttachment")
        let noteEnt = try entityID(for: "ICNote")
        let folderEnt = try entityID(for: "ICFolder")
        let accountEnt = try entityID(for: "ICAccount")

        // Pass 1: hashtag entities — source of truth for tag names. Orphan
        // tags (zero live notes) appear here and nowhere else.
        var tagSQL = SQLQueries.listHashtags
        if accountName != nil { tagSQL += "\n  AND a.ZNAME = :accountName" }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, tagSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(sql: tagSQL, message: String(cString: sqlite3_errmsg(db)))
        }
        try bind(stmt: stmt, name: ":hashtagEntityID", value: Int64(hashtagEnt))
        try bind(stmt: stmt, name: ":accountEntityID", value: Int64(accountEnt))
        if let accountName { try bind(stmt: stmt, name: ":accountName", value: accountName) }

        struct Agg {
            var display: String
            var standardized: String
            var accounts: Set<String> = []
        }
        var aggs: [String: Agg] = [:]  // keyed by uppercased token
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let token = columnText(stmt, 2) else { continue }
            let display = columnText(stmt, 0) ?? token.lowercased()
            let standardized = columnText(stmt, 1) ?? token
            var agg = aggs[token] ?? Agg(display: display, standardized: standardized)
            if let account = columnText(stmt, 3) { agg.accounts.insert(account) }
            aggs[token] = agg
        }
        sqlite3_finalize(stmt)

        // Pass 2: live-note counts grouped by token.
        var countSQL = SQLQueries.tagNoteCountsBase
        if accountName != nil { countSQL += "\n  AND a.ZNAME = :accountName" }
        countSQL += "\n" + SQLQueries.tagNoteCountsGroupSuffix

        stmt = nil
        guard sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(sql: countSQL, message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt, name: ":inlineAttachmentEntityID", value: Int64(attachmentEnt))
        try bind(stmt: stmt, name: ":noteEntityID", value: Int64(noteEnt))
        try bind(stmt: stmt, name: ":folderEntityID", value: Int64(folderEnt))
        try bind(stmt: stmt, name: ":accountEntityID", value: Int64(accountEnt))
        try bind(stmt: stmt, name: ":hashtagUTI", value: SQLQueries.hashtagUTI)
        if let accountName { try bind(stmt: stmt, name: ":accountName", value: accountName) }

        var counts: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let token = columnText(stmt, 0) else { continue }
            counts[token, default: 0] += Int(sqlite3_column_int(stmt, 1))
        }

        return aggs
            .map { token, agg in
                TagSummary(
                    name: "#" + agg.display,
                    standardized: agg.standardized.lowercased(),
                    noteCount: counts[token] ?? 0,
                    accounts: agg.accounts.sorted()
                )
            }
            .sorted {
                if $0.noteCount != $1.noteCount { return $0.noteCount > $1.noteCount }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Subset of `inputs` (raw user form, leading '#' optional) matching no
    /// hashtag entity — feeds get_notes_by_tag's warnings array so typos
    /// don't silently return zero notes.
    func unknownTags(_ inputs: [String]) throws -> [String] {
        guard !inputs.isEmpty else { return [] }
        let hashtagEnt = try entityID(for: "ICHashtag")

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.knownTagStandardizedContents, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.knownTagStandardizedContents,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt, name: ":hashtagEntityID", value: Int64(hashtagEnt))

        var known: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let s = columnText(stmt, 0) { known.insert(s.uppercased()) }
        }
        return inputs.filter { !known.contains(Self.normalizeTagInput($0).uppercased()) }
    }

    /// Best-effort tag enrichment for note reads: one pass over hashtag
    /// attachments grouped by note PK, no per-note round trips. Failure (e.g.
    /// ICInlineAttachment absent on an older schema) leaves `tags` nil on
    /// every note instead of failing the read — only the dedicated tag tools
    /// treat a missing entity as an error.
    private func attachTags(to notes: inout [Note]) {
        guard !notes.isEmpty else { return }
        guard let tagMap = try? hashtagOccurrencesByNotePK() else { return }
        for i in notes.indices {
            notes[i].tags = tagMap[notes[i].pk] ?? []
        }
    }

    /// All hashtag occurrences grouped by owning note PK, deduplicated per
    /// note by token (one note can repeat the same tag) and sorted
    /// alphabetically. Values are the literal in-note form from ZALTTEXT
    /// (e.g. "#Deal-Flow"), falling back to "#" + lowercased token.
    private func hashtagOccurrencesByNotePK() throws -> [Int64: [String]] {
        let attachmentEnt = try entityID(for: "ICInlineAttachment")

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.noteHashtagOccurrences, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.noteHashtagOccurrences,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt, name: ":inlineAttachmentEntityID", value: Int64(attachmentEnt))
        try bind(stmt: stmt, name: ":hashtagUTI", value: SQLQueries.hashtagUTI)

        var seen: [Int64: Set<String>] = [:]   // note PK → tokens already taken
        var grouped: [Int64: [String]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let notePK = sqlite3_column_int64(stmt, 0)
            guard let token = columnText(stmt, 2) else { continue }
            guard seen[notePK, default: []].insert(token).inserted else { continue }
            let alt = columnText(stmt, 1) ?? "#" + token.lowercased()
            grouped[notePK, default: []].append(alt.hasPrefix("#") ? alt : "#" + alt)
        }
        for pk in grouped.keys {
            grouped[pk]?.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return grouped
    }

    // MARK: - Body blob

    private func attachBody(to note: inout Note) {
        if note.isPasswordProtected {
            note.bodyDecodeError = false
            return  // locked → keep body* nil
        }
        do {
            guard let blob = try fetchBodyBlob(notePK: note.pk) else {
                note.bodyDecodeError = false
                return
            }
            if blob.encrypted {
                note.bodyDecodeError = false
                return
            }
            let (text, html) = try NoteProtobufDecoder.decode(blob.data)
            note.bodyText = text
            note.bodyHTML = html
        } catch {
            note.bodyDecodeError = true
        }
    }

    private struct BodyBlob {
        let data: Data
        let encrypted: Bool
    }

    private func fetchBodyBlob(notePK: Int64) throws -> BodyBlob? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.noteBodyBlob, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.noteBodyBlob,
                message: String(cString: sqlite3_errmsg(db))
            )
        }
        defer { sqlite3_finalize(stmt) }
        try bind(stmt: stmt, name: ":notePK", value: notePK)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let blobPtr = sqlite3_column_blob(stmt, 0) else { return nil }
        let length = sqlite3_column_bytes(stmt, 0)
        let data = Data(bytes: blobPtr, count: Int(length))
        let encrypted = sqlite3_column_int(stmt, 1) != 0
        return BodyBlob(data: data, encrypted: encrypted)
    }

    // MARK: - Helpers

    /// Parse `x-coredata://<store-uuid>/ICFolder/p<N>` (or ICNote) and return N,
    /// or nil if the input is a bare UUID / unrecognized form.
    static func extractCoreDataPK(_ id: String?) -> Int64? {
        guard let id, id.hasPrefix("x-coredata://") else { return nil }
        guard let pRange = id.range(of: "/p", options: .backwards) else { return nil }
        let pkStr = id[pRange.upperBound...]
        return Int64(pkStr)
    }

    // MARK: - Named parameter binding helpers

    private func bind(stmt: OpaquePointer?, name: String, value: Int64) throws {
        let idx = sqlite3_bind_parameter_index(stmt, name)
        guard idx > 0 else { return }
        let rc = sqlite3_bind_int64(stmt, idx, value)
        guard rc == SQLITE_OK else {
            throw NotesSQLiteError.stepFailed(code: rc, message: "bind \(name)")
        }
    }

    private func bind(stmt: OpaquePointer?, name: String, value: Double) throws {
        let idx = sqlite3_bind_parameter_index(stmt, name)
        guard idx > 0 else { return }
        let rc = sqlite3_bind_double(stmt, idx, value)
        guard rc == SQLITE_OK else {
            throw NotesSQLiteError.stepFailed(code: rc, message: "bind \(name)")
        }
    }

    private func bind(stmt: OpaquePointer?, name: String, value: String) throws {
        let idx = sqlite3_bind_parameter_index(stmt, name)
        guard idx > 0 else { return }
        let rc = sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw NotesSQLiteError.stepFailed(code: rc, message: "bind \(name)")
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: p)
    }

    private func columnInt64Optional(_ stmt: OpaquePointer?, _ i: Int32) -> Int64? {
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, i)
    }

    private func columnIntOptional(_ stmt: OpaquePointer?, _ i: Int32) -> Int? {
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(stmt, i))
    }

    private func columnDoubleOptional(_ stmt: OpaquePointer?, _ i: Int32) -> Double? {
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, i)
    }
}

private extension NotesSQLiteError {
    func prepending(_ prefix: String) -> NotesSQLiteError {
        // Preserves enum case but embellishes message via cannotOpen/prepareFailed.
        return self
    }
}
