import Foundation

/// In-memory record of write operations to enable undo/redo.
///
/// Each `Operation` stores enough info to invert itself:
/// - `create` → invert = delete by id
/// - `update` → invert = update back to old title/body
/// - `delete` → invert = create with captured title/body/folder
/// - `move`   → invert = move back to source folder
///
/// The stack is process-local (no persistence). Restarting the server resets
/// undo history.
final class UndoStack {

    enum Operation {
        case create(id: String)
        case update(id: String, oldTitle: String?, oldBodyHTML: String?, newTitle: String?, newBodyHTML: String?)
        case delete(id: String, title: String, bodyHTML: String, folder: String?, account: String?)
        case move(id: String, fromFolder: String, account: String?, toFolder: String)

        var humanDescription: String {
            switch self {
            case .create(let id): return "created note \(id)"
            case .update(let id, _, _, _, _): return "updated note \(id)"
            case .delete(let id, _, _, _, _): return "deleted note \(id)"
            case .move(let id, _, _, let to): return "moved note \(id) to \(to)"
            }
        }
    }

    private var undoStack: [Operation] = []
    private var redoStack: [Operation] = []
    private let maxDepth: Int

    init(maxDepth: Int = 50) {
        self.maxDepth = maxDepth
    }

    func record(_ op: Operation) {
        undoStack.append(op)
        if undoStack.count > maxDepth {
            undoStack.removeFirst(undoStack.count - maxDepth)
        }
        redoStack.removeAll()
    }

    func popForUndo() -> Operation? {
        guard let op = undoStack.popLast() else { return nil }
        redoStack.append(op)
        return op
    }

    func popForRedo() -> Operation? {
        guard let op = redoStack.popLast() else { return nil }
        undoStack.append(op)
        return op
    }

    func history() -> [String] {
        undoStack.enumerated().map { "\($0): \($1.humanDescription)" }
    }

    func undoDepth() -> Int { undoStack.count }
    func redoDepth() -> Int { redoStack.count }
}
