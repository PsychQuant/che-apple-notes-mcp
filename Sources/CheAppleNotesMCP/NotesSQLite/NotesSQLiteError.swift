import Foundation

enum NotesSQLiteError: LocalizedError {
    case cannotOpen(path: String, code: Int32)
    case prepareFailed(sql: String, message: String)
    case stepFailed(code: Int32, message: String)
    case entityNotFound(String)
    case decodeFailed(String)
    case fullDiskAccessDenied

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path, let code):
            return "Cannot open NoteStore.sqlite at \(path) (sqlite code \(code))"
        case .prepareFailed(let sql, let message):
            return "SQL prepare failed: \(message). Query: \(sql)"
        case .stepFailed(let code, let message):
            return "SQL step failed (code \(code)): \(message)"
        case .entityNotFound(let name):
            return "Entity '\(name)' not found in Z_PRIMARYKEY. Notes.app schema may have changed."
        case .decodeFailed(let reason):
            return "Failed to decode note body: \(reason)"
        case .fullDiskAccessDenied:
            return "Full Disk Access required to read NoteStore.sqlite. Run --setup for instructions."
        }
    }
}
