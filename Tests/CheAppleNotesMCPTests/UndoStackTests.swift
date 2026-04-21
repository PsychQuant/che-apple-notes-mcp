import Testing
@testable import CheAppleNotesMCP

@Suite struct UndoStackTests {

    @Test func recordPushesOntoUndoStack() {
        let stack = UndoStack()
        stack.record(.create(id: "abc"))
        #expect(stack.undoDepth() == 1)
        #expect(stack.redoDepth() == 0)
    }

    @Test func popForUndoMovesEntryToRedoStack() {
        let stack = UndoStack()
        stack.record(.create(id: "abc"))

        let op = stack.popForUndo()

        #expect(op != nil)
        #expect(stack.undoDepth() == 0)
        #expect(stack.redoDepth() == 1)
    }

    @Test func popForRedoMovesEntryBack() {
        let stack = UndoStack()
        stack.record(.create(id: "abc"))
        _ = stack.popForUndo()

        let op = stack.popForRedo()

        #expect(op != nil)
        #expect(stack.undoDepth() == 1)
        #expect(stack.redoDepth() == 0)
    }

    @Test func popForUndoOnEmptyReturnsNil() {
        let stack = UndoStack()
        #expect(stack.popForUndo() == nil)
    }

    @Test func popForRedoOnEmptyReturnsNil() {
        let stack = UndoStack()
        #expect(stack.popForRedo() == nil)
    }

    @Test func newRecordClearsRedoStack() {
        let stack = UndoStack()
        stack.record(.create(id: "a"))
        _ = stack.popForUndo()
        #expect(stack.redoDepth() == 1)

        stack.record(.create(id: "b"))

        #expect(stack.redoDepth() == 0)
        #expect(stack.undoDepth() == 1)
    }

    @Test func overflowDropsOldestEntries() {
        let stack = UndoStack(maxDepth: 3)
        stack.record(.create(id: "a"))
        stack.record(.create(id: "b"))
        stack.record(.create(id: "c"))
        stack.record(.create(id: "d"))

        #expect(stack.undoDepth() == 3)

        let history = stack.history()
        #expect(history.count == 3)
        #expect(!history.contains(where: { $0.contains("created note a") }))
        #expect(history.contains(where: { $0.contains("created note d") }))
    }

    @Test func historyRendersEachOperationOnce() {
        let stack = UndoStack()
        stack.record(.create(id: "x"))
        stack.record(.delete(id: "y", title: "t", bodyHTML: "b", folder: "f", account: "a"))
        stack.record(.move(id: "z", fromFolder: "src", account: nil, toFolder: "dst"))

        let history = stack.history()

        #expect(history.count == 3)
        #expect(history[0].contains("created note x"))
        #expect(history[1].contains("deleted note y"))
        #expect(history[2].contains("moved note z to dst"))
    }
}
