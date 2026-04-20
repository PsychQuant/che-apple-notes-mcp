import AppKit
import Foundation
import MCP

/// MCP server for Apple Notes.app. Routes read tools to `NotesStoreReader`
/// (SQLite fast path, with AppleScript fallback) and write tools to
/// `NotesController` (AppleScript).
final class CheAppleNotesMCPServer {
    private let server: Server
    private let transport: StdioTransport
    private let tools: [Tool]

    private let capabilities: Capabilities
    private var sqlite: NotesStoreReader?
    private let applescript = NotesController()
    private let undoStack = UndoStack()

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init() async throws {
        self.capabilities = Capabilities.detect()
        if capabilities.sqliteReadable {
            self.sqlite = try? NotesStoreReader()
        }

        self.tools = Self.defineTools()

        self.server = Server(
            name: AppVersion.name,
            version: AppVersion.current,
            capabilities: .init(tools: .init())
        )
        self.transport = StdioTransport()

        await registerHandlers()
    }

    func run() async throws {
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool definitions

    private static func defineTools() -> [Tool] {
        [
            // Folders
            Tool(
                name: "list_folders",
                description: "List all note folders across all accounts. Returns hierarchy with account name, folder title, folder id, and whether folder is hidden.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "account": .object([
                            "type": .string("string"),
                            "description": .string("Optional account filter (e.g., 'iCloud', 'On My Mac')")
                        ])
                    ])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "create_folder",
                description: "Create a new note folder. Account is optional; defaults to default account when omitted.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object(["type": .string("string"), "description": .string("Folder name")]),
                        "account": .object(["type": .string("string"), "description": .string("Account name (iCloud / On My Mac). Optional.")])
                    ]),
                    "required": .array([.string("title")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "update_folder",
                description: "Rename an existing folder.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Folder id (x-coredata://...)")]),
                        "title": .object(["type": .string("string"), "description": .string("New folder name")])
                    ]),
                    "required": .array([.string("id"), .string("title")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "delete_folder",
                description: "Delete an empty folder. Errors if the folder contains notes.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Folder id")])
                    ]),
                    "required": .array([.string("id")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
            ),

            // Notes
            Tool(
                name: "list_notes",
                description: "List notes with optional filters (folder, account, pinned, locked, date range). Fast path via SQLite; falls back to AppleScript if Full Disk Access not granted.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "folder": .object(["type": .string("string"), "description": .string("Folder name to filter by")]),
                        "folder_id": .object(["type": .string("string"), "description": .string("Folder id (exact match)")]),
                        "account": .object(["type": .string("string"), "description": .string("Account name filter")]),
                        "pinned": .object(["type": .string("boolean"), "description": .string("Only pinned (true) or only unpinned (false)")]),
                        "locked": .object(["type": .string("boolean"), "description": .string("Only locked / only unlocked")]),
                        "created_after": .object(["type": .string("string"), "description": .string("ISO 8601 date (created on or after)")]),
                        "created_before": .object(["type": .string("string"), "description": .string("ISO 8601 date (created on or before)")]),
                        "modified_after": .object(["type": .string("string"), "description": .string("ISO 8601 date (modified on or after)")]),
                        "modified_before": .object(["type": .string("string"), "description": .string("ISO 8601 date (modified on or before)")]),
                        "include_body": .object(["type": .string("boolean"), "description": .string("Include body_text + body_html. Default false (metadata only).")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max rows to return")]),
                        "sort": .object(["type": .string("string"), "enum": .array([.string("asc"), .string("desc")]), "description": .string("Sort by modification date (default desc)")])
                    ])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "list_notes_quick",
                description: "Common preset ranges: 'recent' (last 30d), 'today', 'this_week', 'pinned'.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "range": .object([
                            "type": .string("string"),
                            "enum": .array([.string("recent"), .string("today"), .string("this_week"), .string("pinned")]),
                            "description": .string("Preset range")
                        ]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max rows")]),
                        "include_body": .object(["type": .string("boolean"), "description": .string("Include body")])
                    ]),
                    "required": .array([.string("range")])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "get_note",
                description: "Fetch a single note by id with full body (text + HTML) and metadata. Locked notes return metadata only.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Note id (x-coredata://...)")])
                    ]),
                    "required": .array([.string("id")])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
            Tool(
                name: "create_note",
                description: "Create a new note. Provide body_text OR body_html (not both). Folder and account are optional — defaults to the default folder of the default account.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object(["type": .string("string"), "description": .string("Note title")]),
                        "body_text": .object(["type": .string("string"), "description": .string("Plain text body (will be wrapped in <div>). Mutually exclusive with body_html.")]),
                        "body_html": .object(["type": .string("string"), "description": .string("HTML body. Mutually exclusive with body_text.")]),
                        "folder": .object(["type": .string("string"), "description": .string("Folder name")]),
                        "account": .object(["type": .string("string"), "description": .string("Account name (iCloud / On My Mac)")])
                    ]),
                    "required": .array([.string("title")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "update_note",
                description: "Update a note's title and/or body. Only fields provided are changed.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Note id")]),
                        "title": .object(["type": .string("string"), "description": .string("New title (optional)")]),
                        "body_text": .object(["type": .string("string"), "description": .string("New plaintext body")]),
                        "body_html": .object(["type": .string("string"), "description": .string("New HTML body")])
                    ]),
                    "required": .array([.string("id")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "delete_note",
                description: "Delete a note permanently. Captures title+body+folder for undo.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Note id")])
                    ]),
                    "required": .array([.string("id")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
            ),
            Tool(
                name: "move_note",
                description: "Move a note to a different folder.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string"), "description": .string("Note id")]),
                        "folder": .object(["type": .string("string"), "description": .string("Destination folder name")]),
                        "account": .object(["type": .string("string"), "description": .string("Destination account (optional)")])
                    ]),
                    "required": .array([.string("id"), .string("folder")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),

            // Search
            Tool(
                name: "search_notes",
                description: "Search notes by keyword(s). Matches in title and snippet. Use match_mode='all' to require all keywords.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "keyword": .object(["type": .string("string"), "description": .string("Single keyword")]),
                        "keywords": .object(["type": .string("array"), "description": .string("Multiple keywords")]),
                        "match_mode": .object(["type": .string("string"), "enum": .array([.string("any"), .string("all")]), "description": .string("any (OR) or all (AND). Default any.")]),
                        "limit": .object(["type": .string("integer"), "description": .string("Max rows")])
                    ])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),

            // Batch
            Tool(
                name: "create_notes_batch",
                description: "Create multiple notes in one AppleScript dispatch.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "notes": .object([
                            "type": .string("array"),
                            "description": .string("Array of {title, body_text?, body_html?, folder?, account?}")
                        ])
                    ]),
                    "required": .array([.string("notes")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "move_notes_batch",
                description: "Move multiple notes to the same destination folder.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "ids": .object(["type": .string("array"), "description": .string("Array of note ids")]),
                        "folder": .object(["type": .string("string"), "description": .string("Destination folder")]),
                        "account": .object(["type": .string("string"), "description": .string("Destination account")])
                    ]),
                    "required": .array([.string("ids"), .string("folder")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "delete_notes_batch",
                description: "Delete multiple notes.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "ids": .object(["type": .string("array"), "description": .string("Array of note ids")])
                    ]),
                    "required": .array([.string("ids")])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
            ),

            // Undo/redo
            Tool(
                name: "undo",
                description: "Undo the most recent write operation (in-memory stack, process-local).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "redo",
                description: "Redo the most recently undone operation.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ]),
                annotations: .init(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
            ),
            Tool(
                name: "undo_history",
                description: "List the in-memory undo history.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ]),
                annotations: .init(readOnlyHint: true, openWorldHint: false)
            ),
        ]
    }

    // MARK: - Handler wiring

    private func registerHandlers() async {
        await server.withMethodHandler(ListTools.self) { [tools] _ in
            ListTools.Result(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(content: [.text("Server unavailable")], isError: true)
            }
            return await self.handleToolCall(name: params.name, arguments: params.arguments ?? [:])
        }
    }

    private func handleToolCall(name: String, arguments: [String: Value]) async -> CallTool.Result {
        do {
            let result = try await executeToolCall(name: name, arguments: arguments)
            return CallTool.Result(content: [.text(result)])
        } catch {
            return CallTool.Result(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }

    func executeToolCall(name: String, arguments: [String: Value]) async throws -> String {
        switch name {
        case "list_folders":       return try handleListFolders(arguments)
        case "create_folder":      return try handleCreateFolder(arguments)
        case "update_folder":      return try handleUpdateFolder(arguments)
        case "delete_folder":      return try handleDeleteFolder(arguments)
        case "list_notes":         return try handleListNotes(arguments)
        case "list_notes_quick":   return try handleListNotesQuick(arguments)
        case "get_note":           return try handleGetNote(arguments)
        case "create_note":        return try handleCreateNote(arguments)
        case "update_note":        return try handleUpdateNote(arguments)
        case "delete_note":        return try handleDeleteNote(arguments)
        case "move_note":          return try handleMoveNote(arguments)
        case "search_notes":       return try handleSearchNotes(arguments)
        case "create_notes_batch": return try handleCreateNotesBatch(arguments)
        case "move_notes_batch":   return try handleMoveNotesBatch(arguments)
        case "delete_notes_batch": return try handleDeleteNotesBatch(arguments)
        case "undo":               return try handleUndo()
        case "redo":               return try handleRedo()
        case "undo_history":       return handleUndoHistory()
        default:
            throw NotesServerError.unknownTool(name)
        }
    }

    // MARK: - Handlers: folders

    private func handleListFolders(_ args: [String: Value]) throws -> String {
        let accountFilter = args["account"]?.stringValue

        if let sqlite {
            let folders = try sqlite.listFolders()
                .filter { accountFilter == nil || $0.accountName == accountFilter }
            return jsonify(folders.map(folderToDict))
        }
        // AppleScript fallback
        let rows = try applescript.listFolders()
            .filter { accountFilter == nil || $0.accountName == accountFilter }
        let dicts = rows.map { row -> [String: Any] in
            [
                "id": row.folderID,
                "title": row.folderName,
                "account_name": row.accountName,
                "source": "applescript"
            ]
        }
        return jsonify(dicts)
    }

    private func handleCreateFolder(_ args: [String: Value]) throws -> String {
        let title = try requireString(args, "title")
        let account = args["account"]?.stringValue
        let id = try applescript.createFolder(title: title, account: account)
        sqlite?.checkpoint()
        return jsonify(["id": id, "title": title, "account": account ?? ""])
    }

    private func handleUpdateFolder(_ args: [String: Value]) throws -> String {
        let id = try requireString(args, "id")
        let title = try requireString(args, "title")
        _ = try applescript.renameFolder(id: id, newTitle: title)
        sqlite?.checkpoint()
        return jsonify(["id": id, "title": title])
    }

    private func handleDeleteFolder(_ args: [String: Value]) throws -> String {
        let id = try requireString(args, "id")
        try applescript.deleteFolder(id: id)
        sqlite?.checkpoint()
        return jsonify(["id": id, "deleted": true])
    }

    // MARK: - Handlers: notes

    private func handleListNotes(_ args: [String: Value]) throws -> String {
        var options = NotesStoreReader.NoteListOptions()
        options.folderIdentifier = args["folder_id"]?.stringValue
        options.accountName = args["account"]?.stringValue
        if case .bool(let b)? = args["pinned"] { options.pinned = b }
        if case .bool(let b)? = args["locked"] { options.locked = b }
        options.createdAfter = parseISODate(args["created_after"]?.stringValue)
        options.createdBefore = parseISODate(args["created_before"]?.stringValue)
        options.modifiedAfter = parseISODate(args["modified_after"]?.stringValue)
        options.modifiedBefore = parseISODate(args["modified_before"]?.stringValue)
        if case .int(let n)? = args["limit"] { options.limit = n }
        if case .bool(let b)? = args["include_body"] { options.includeBody = b }
        if args["sort"]?.stringValue == "asc" { options.sortDescending = false }

        // Name-based folder filter requires looking up id first.
        if let folderName = args["folder"]?.stringValue, options.folderIdentifier == nil {
            if let sqlite {
                let match = try sqlite.listFolders().first {
                    $0.title == folderName
                        && (options.accountName == nil || $0.accountName == options.accountName)
                }
                if let match { options.folderIdentifier = match.identifier }
            }
        }

        if let sqlite {
            let notes = try sqlite.listNotes(options: options)
            return jsonify(notes.map(noteToDict))
        }

        // AppleScript fallback (limited — needs folder name)
        let folder = args["folder"]?.stringValue ?? "Notes"
        let rows = try applescript.listNotesInFolder(
            folder, account: options.accountName, limit: options.limit
        )
        return jsonify(rows.map { row -> [String: Any] in
            [
                "id": row.id,
                "title": row.title,
                "folder": folder,
                "creation_date": row.creationDate,
                "modification_date": row.modificationDate,
                "source": "applescript"
            ]
        })
    }

    private func handleListNotesQuick(_ args: [String: Value]) throws -> String {
        let range = try requireString(args, "range")
        var options = NotesStoreReader.NoteListOptions()
        if case .int(let n)? = args["limit"] { options.limit = n }
        if case .bool(let b)? = args["include_body"] { options.includeBody = b }

        let now = Date()
        let cal = Calendar.current
        switch range {
        case "recent":
            options.modifiedAfter = cal.date(byAdding: .day, value: -30, to: now)
        case "today":
            options.modifiedAfter = cal.startOfDay(for: now)
        case "this_week":
            options.modifiedAfter = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
        case "pinned":
            options.pinned = true
        default:
            throw NotesServerError.invalidArgument("range must be recent/today/this_week/pinned")
        }

        if let sqlite {
            let notes = try sqlite.listNotes(options: options)
            return jsonify(notes.map(noteToDict))
        }
        throw NotesServerError.featureRequiresSQLite("list_notes_quick")
    }

    private func handleGetNote(_ args: [String: Value]) throws -> String {
        let id = try requireString(args, "id")
        if let sqlite, let note = try sqlite.getNote(identifier: id) {
            var dict = noteToDict(note)
            // If body decode failed, fill via AppleScript
            if note.bodyDecodeError {
                if let html = try? applescript.getNoteBody(id: id) {
                    dict["body_html"] = html
                    dict["body_text"] = BodyHTMLRenderer.htmlToPlaintext(html)
                    dict["body_decode_error"] = false
                    dict["body_source"] = "applescript_fallback"
                }
            }
            return jsonify(dict)
        }
        // AppleScript only
        let html = try applescript.getNoteBody(id: id)
        return jsonify([
            "id": id,
            "body_html": html,
            "body_text": BodyHTMLRenderer.htmlToPlaintext(html),
            "source": "applescript"
        ] as [String: Any])
    }

    private func handleCreateNote(_ args: [String: Value]) throws -> String {
        let title = try requireString(args, "title")
        let bodyHTML = try BodyFormatter.resolve(
            bodyText: args["body_text"]?.stringValue,
            bodyHTML: args["body_html"]?.stringValue
        )
        let folder = args["folder"]?.stringValue
        let account = args["account"]?.stringValue

        let id = try applescript.createNote(title: title, bodyHTML: bodyHTML, folder: folder, account: account)
        undoStack.record(.create(id: id))
        sqlite?.checkpoint()
        return jsonify([
            "id": id, "title": title, "folder": folder ?? "", "account": account ?? ""
        ] as [String: Any])
    }

    private func handleUpdateNote(_ args: [String: Value]) throws -> String {
        let id = try requireString(args, "id")
        let newTitle = args["title"]?.stringValue

        var newBodyHTML: String? = nil
        if args["body_text"] != nil || args["body_html"] != nil {
            newBodyHTML = try BodyFormatter.resolve(
                bodyText: args["body_text"]?.stringValue,
                bodyHTML: args["body_html"]?.stringValue
            )
        }

        // Capture old state for undo (best-effort — skip if SQLite unavailable)
        var oldTitle: String? = nil
        var oldBodyHTML: String? = nil
        if let sqlite, let existing = try? sqlite.getNote(identifier: id) {
            oldTitle = existing.title
            oldBodyHTML = existing.bodyHTML
        }

        _ = try applescript.updateNote(id: id, newTitle: newTitle, newBodyHTML: newBodyHTML)
        undoStack.record(.update(
            id: id,
            oldTitle: oldTitle, oldBodyHTML: oldBodyHTML,
            newTitle: newTitle, newBodyHTML: newBodyHTML
        ))
        sqlite?.checkpoint()
        return jsonify(["id": id, "updated": true])
    }

    private func handleDeleteNote(_ args: [String: Value]) throws -> String {
        let id = try requireString(args, "id")

        // Capture for undo
        var capturedTitle = ""
        var capturedBodyHTML = ""
        var capturedFolder: String? = nil
        var capturedAccount: String? = nil
        if let sqlite, let existing = try? sqlite.getNote(identifier: id) {
            capturedTitle = existing.title
            capturedBodyHTML = existing.bodyHTML ?? ""
            capturedFolder = existing.folderName
            capturedAccount = existing.accountName
        }

        try applescript.deleteNote(id: id)
        undoStack.record(.delete(
            id: id, title: capturedTitle, bodyHTML: capturedBodyHTML,
            folder: capturedFolder, account: capturedAccount
        ))
        sqlite?.checkpoint()
        return jsonify(["id": id, "deleted": true])
    }

    private func handleMoveNote(_ args: [String: Value]) throws -> String {
        let id = try requireString(args, "id")
        let folder = try requireString(args, "folder")
        let account = args["account"]?.stringValue

        var fromFolder = ""
        if let sqlite, let existing = try? sqlite.getNote(identifier: id) {
            fromFolder = existing.folderName ?? ""
        }

        _ = try applescript.moveNote(id: id, toFolderName: folder, account: account)
        undoStack.record(.move(id: id, fromFolder: fromFolder, account: account, toFolder: folder))
        sqlite?.checkpoint()
        return jsonify(["id": id, "moved_to": folder])
    }

    // MARK: - Handlers: search

    private func handleSearchNotes(_ args: [String: Value]) throws -> String {
        var keywords: [String] = []
        if let single = args["keyword"]?.stringValue, !single.isEmpty {
            keywords.append(single)
        }
        if case .array(let arr)? = args["keywords"] {
            keywords.append(contentsOf: arr.compactMap { $0.stringValue })
        }
        guard !keywords.isEmpty else {
            throw NotesServerError.invalidArgument("provide 'keyword' or 'keywords'")
        }
        let matchAll = args["match_mode"]?.stringValue == "all"
        var limit: Int? = nil
        if case .int(let n)? = args["limit"] { limit = n }

        if let sqlite {
            let results = try sqlite.searchNotes(keywords: keywords, matchAll: matchAll, limit: limit)
            return jsonify(results.map(noteToDict))
        }
        throw NotesServerError.featureRequiresSQLite("search_notes")
    }

    // MARK: - Handlers: batch

    private func handleCreateNotesBatch(_ args: [String: Value]) throws -> String {
        guard case .array(let notesArr)? = args["notes"] else {
            throw NotesServerError.invalidArgument("notes must be an array")
        }
        var entries: [(title: String, bodyHTML: String, folder: String?, account: String?)] = []
        for v in notesArr {
            guard case .object(let obj) = v else {
                throw NotesServerError.invalidArgument("notes[] must contain objects")
            }
            let title = obj["title"]?.stringValue ?? "Untitled"
            let bodyHTML = try BodyFormatter.resolve(
                bodyText: obj["body_text"]?.stringValue,
                bodyHTML: obj["body_html"]?.stringValue
            )
            entries.append((
                title: title, bodyHTML: bodyHTML,
                folder: obj["folder"]?.stringValue,
                account: obj["account"]?.stringValue
            ))
        }
        let ids = try applescript.createNotesBatch(entries)
        for id in ids { undoStack.record(.create(id: id)) }
        sqlite?.checkpoint()
        return jsonify(["ids": ids, "count": ids.count] as [String: Any])
    }

    private func handleMoveNotesBatch(_ args: [String: Value]) throws -> String {
        guard case .array(let idsArr)? = args["ids"] else {
            throw NotesServerError.invalidArgument("ids must be an array")
        }
        let ids = idsArr.compactMap { $0.stringValue }
        let folder = try requireString(args, "folder")
        let account = args["account"]?.stringValue

        try applescript.moveNotesBatch(ids, toFolderName: folder, account: account)
        sqlite?.checkpoint()
        return jsonify(["moved_count": ids.count, "destination": folder] as [String: Any])
    }

    private func handleDeleteNotesBatch(_ args: [String: Value]) throws -> String {
        guard case .array(let idsArr)? = args["ids"] else {
            throw NotesServerError.invalidArgument("ids must be an array")
        }
        let ids = idsArr.compactMap { $0.stringValue }
        try applescript.deleteNotesBatch(ids)
        sqlite?.checkpoint()
        return jsonify(["deleted_count": ids.count] as [String: Any])
    }

    // MARK: - Handlers: undo/redo

    private func handleUndo() throws -> String {
        guard let op = undoStack.popForUndo() else {
            return jsonify(["undone": false, "reason": "stack empty"] as [String: Any])
        }
        switch op {
        case .create(let id):
            try applescript.deleteNote(id: id)
        case .update(let id, let oldTitle, let oldBodyHTML, _, _):
            _ = try applescript.updateNote(id: id, newTitle: oldTitle, newBodyHTML: oldBodyHTML)
        case .delete(_, let title, let bodyHTML, let folder, let account):
            _ = try applescript.createNote(title: title, bodyHTML: bodyHTML, folder: folder, account: account)
        case .move(let id, let fromFolder, let account, _):
            _ = try applescript.moveNote(id: id, toFolderName: fromFolder, account: account)
        }
        sqlite?.checkpoint()
        return jsonify(["undone": true, "operation": op.humanDescription] as [String: Any])
    }

    private func handleRedo() throws -> String {
        guard let op = undoStack.popForRedo() else {
            return jsonify(["redone": false, "reason": "stack empty"] as [String: Any])
        }
        switch op {
        case .create(let id):
            // Can't recreate a deleted id — report failure
            return jsonify(["redone": false, "reason": "create redo requires new create call", "id": id] as [String: Any])
        case .update(let id, _, _, let newTitle, let newBodyHTML):
            _ = try applescript.updateNote(id: id, newTitle: newTitle, newBodyHTML: newBodyHTML)
        case .delete(let id, _, _, _, _):
            try applescript.deleteNote(id: id)
        case .move(let id, _, let account, let toFolder):
            _ = try applescript.moveNote(id: id, toFolderName: toFolder, account: account)
        }
        sqlite?.checkpoint()
        return jsonify(["redone": true, "operation": op.humanDescription] as [String: Any])
    }

    private func handleUndoHistory() -> String {
        jsonify([
            "undo_depth": undoStack.undoDepth(),
            "redo_depth": undoStack.redoDepth(),
            "history": undoStack.history()
        ] as [String: Any])
    }

    // MARK: - Formatters

    private func folderToDict(_ f: Folder) -> [String: Any] {
        [
            "id": f.identifier,
            "title": f.title,
            "account_name": f.accountName ?? "",
            "parent_pk": f.parentPK as Any,
            "is_hidden": f.isHiddenContainer,
            "sort_order": f.sortOrder as Any
        ]
    }

    private func noteToDict(_ n: Note) -> [String: Any] {
        // `id` = AppleScript URL form, so write tools can use it directly.
        // `uuid` = raw ZIDENTIFIER for debugging / advanced consumers.
        var dict: [String: Any] = [
            "id": n.appleScriptID,
            "uuid": n.identifier,
            "title": n.title,
            "folder": n.folderName ?? "",
            "account": n.accountName ?? "",
            "pinned": n.isPinned,
            "locked": n.isPasswordProtected,
            "snippet": n.snippet ?? "",
        ]
        if let d = n.creationDate {
            dict["created_at"] = iso8601.string(from: d)
        }
        if let d = n.modificationDate {
            dict["modified_at"] = iso8601.string(from: d)
        }
        if let bt = n.bodyText {
            dict["body_text"] = bt
        }
        if let bh = n.bodyHTML {
            dict["body_html"] = bh
        }
        if n.bodyDecodeError {
            dict["body_decode_error"] = true
        }
        return dict
    }

    private func parseISODate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso8601.date(from: s)
    }

    private func requireString(_ args: [String: Value], _ key: String) throws -> String {
        guard let s = args[key]?.stringValue, !s.isEmpty else {
            throw NotesServerError.invalidArgument("missing required argument: \(key)")
        }
        return s
    }

    private func jsonify(_ obj: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\":\"\(error.localizedDescription)\"}"
        }
    }
}

enum NotesServerError: LocalizedError {
    case unknownTool(String)
    case invalidArgument(String)
    case featureRequiresSQLite(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let n): return "Unknown tool: \(n)"
        case .invalidArgument(let m): return m
        case .featureRequiresSQLite(let f):
            return "Feature '\(f)' requires Full Disk Access. Run --setup for instructions."
        }
    }
}

// MARK: - Value convenience

extension Value {
    /// Convenience accessor: coerce to String when possible.
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let n): return String(n)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}
