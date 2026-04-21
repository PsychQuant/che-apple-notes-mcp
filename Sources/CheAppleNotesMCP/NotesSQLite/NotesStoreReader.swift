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

    func listFolders() throws -> [Folder] {
        let folderEnt = try entityID(for: "ICFolder")
        let accountEnt = try entityID(for: "ICAccount")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, SQLQueries.listFolders, -1, &stmt, nil) == SQLITE_OK else {
            throw NotesSQLiteError.prepareFailed(
                sql: SQLQueries.listFolders,
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

    // MARK: - Search

    func searchNotes(keywords: [String], matchAll: Bool = false, limit: Int? = nil) throws -> [Note] {
        guard !keywords.isEmpty else { return [] }

        let noteEnt = try entityID(for: "ICNote")
        let folderEnt = try entityID(for: "ICFolder")
        let accountEnt = try entityID(for: "ICAccount")

        let joiner = matchAll ? " AND " : " OR "
        let conds = (0..<keywords.count).map { i in
            "(LOWER(COALESCE(n.ZTITLE1, n.ZTITLE, '')) LIKE :kw\(i) OR LOWER(COALESCE(n.ZSNIPPET, '')) LIKE :kw\(i))"
        }.joined(separator: joiner)

        var sql = SQLQueries.listNotes + "\n  AND (\(conds))\nORDER BY modification_date DESC"
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
        return results
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
