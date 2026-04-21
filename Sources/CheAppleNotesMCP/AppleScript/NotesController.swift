import AppKit
import Foundation

/// Dispatches AppleScript sources to Notes.app and unpacks results.
///
/// All write operations go through here. Read fallbacks (when FDA is not
/// granted) also use this class.
final class NotesController {

    enum ControllerError: LocalizedError {
        case executionFailed(number: Int, message: String)
        case unexpectedResult(String)

        var errorDescription: String? {
            switch self {
            case .executionFailed(let number, let message):
                return "AppleScript error \(number): \(message)"
            case .unexpectedResult(let detail):
                return "Unexpected AppleScript result: \(detail)"
            }
        }
    }

    // MARK: - Run

    @discardableResult
    func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw ControllerError.unexpectedResult("failed to compile AppleScript")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? -1
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "unknown"
            throw ControllerError.executionFailed(number: number, message: message)
        }
        return result
    }

    func runReturningString(_ source: String) throws -> String {
        let desc = try run(source)
        return desc.stringValue ?? ""
    }

    func runReturningList(_ source: String) throws -> [String] {
        let desc = try run(source)
        guard desc.descriptorType == typeAEList else {
            // Single-element return — wrap
            if let str = desc.stringValue { return [str] }
            return []
        }
        var out: [String] = []
        // AppleScript lists are 1-indexed
        for i in 1...max(desc.numberOfItems, 0) {
            if let item = desc.atIndex(i), let str = item.stringValue {
                out.append(str)
            }
        }
        return out
    }

    // MARK: - Folders

    struct ASFolderRow {
        let accountName: String
        let folderName: String
        let folderID: String
    }

    func listFolders() throws -> [ASFolderRow] {
        let lines = try runReturningList(NoteScriptBuilder.listFolders())
        return lines.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 3 else { return nil }
            return ASFolderRow(accountName: parts[0], folderName: parts[1], folderID: parts[2])
        }
    }

    func createFolder(title: String, account: String?) throws -> String {
        try runReturningString(NoteScriptBuilder.createFolder(title: title, account: account))
    }

    func renameFolder(id: String, newTitle: String) throws -> String {
        try runReturningString(NoteScriptBuilder.renameFolder(id: id, newTitle: newTitle))
    }

    func deleteFolder(id: String) throws {
        _ = try runReturningString(NoteScriptBuilder.deleteFolder(id: id))
    }

    // MARK: - Notes (write)

    func createNote(title: String, bodyHTML: String, folder: String?, account: String?) throws -> String {
        try runReturningString(NoteScriptBuilder.createNote(
            title: title, bodyHTML: bodyHTML, folderName: folder, account: account
        ))
    }

    func updateNote(id: String, newTitle: String?, newBodyHTML: String?) throws -> String {
        try runReturningString(NoteScriptBuilder.updateNote(
            id: id, newTitle: newTitle, newBodyHTML: newBodyHTML
        ))
    }

    func deleteNote(id: String) throws {
        _ = try runReturningString(NoteScriptBuilder.deleteNote(id: id))
    }

    func moveNote(id: String, toFolderName: String, account: String?) throws -> String {
        try runReturningString(NoteScriptBuilder.moveNote(
            id: id, toFolderName: toFolderName, account: account
        ))
    }

    // MARK: - Notes (read fallback)

    struct ASNoteRow {
        let id: String
        let title: String
        let creationDate: String
        let modificationDate: String
    }

    func listNotesInFolder(_ folderName: String, account: String?, limit: Int?) throws -> [ASNoteRow] {
        let lines = try runReturningList(NoteScriptBuilder.listNotesInFolder(
            folderName: folderName, account: account, limit: limit
        ))
        return lines.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 4 else { return nil }
            return ASNoteRow(
                id: parts[0], title: parts[1],
                creationDate: parts[2], modificationDate: parts[3]
            )
        }
    }

    func getNoteBody(id: String) throws -> String {
        try runReturningString(NoteScriptBuilder.getNoteBody(id: id))
    }

    struct ASNoteFull {
        let title: String
        let bodyHTML: String
        let creationDate: String
        let modificationDate: String
        let folderName: String
        let accountName: String
    }

    /// Fetch full note metadata + body in one AppleScript roundtrip.
    /// Used when SQLite is unavailable (FDA not granted). Returns nil if the
    /// note cannot be found or the response is malformed.
    func getNoteFull(id: String) throws -> ASNoteFull {
        let raw = try runReturningString(NoteScriptBuilder.getNoteFull(id: id))
        let parts = raw.components(separatedBy: "\t")
        guard parts.count == 6 else {
            throw ControllerError.unexpectedResult("getNoteFull returned \(parts.count) fields, expected 6")
        }
        return ASNoteFull(
            title: parts[0],
            bodyHTML: parts[1],
            creationDate: parts[2],
            modificationDate: parts[3],
            folderName: parts[4],
            accountName: parts[5]
        )
    }

    // MARK: - Batch

    func createNotesBatch(_ entries: [(title: String, bodyHTML: String, folder: String?, account: String?)]) throws -> [String] {
        try runReturningList(NoteScriptBuilder.createNotesBatch(entries: entries))
    }

    func deleteNotesBatch(_ ids: [String]) throws {
        _ = try runReturningString(NoteScriptBuilder.deleteNotesBatch(ids: ids))
    }

    func moveNotesBatch(_ ids: [String], toFolderName: String, account: String?) throws {
        _ = try runReturningString(NoteScriptBuilder.moveNotesBatch(
            ids: ids, toFolderName: toFolderName, account: account
        ))
    }
}
