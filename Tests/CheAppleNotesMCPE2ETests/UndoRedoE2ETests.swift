import Foundation
import Testing

@Suite(.serialized) struct UndoRedoE2ETests {

    @Test func undoReversesLastCreate() async throws {
        try await withFixtureFolder { client, fixture in
            let createResult = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"UndoMe","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            struct N: Decodable { let id: String }
            _ = try JSONDecoder().decode(N.self, from: Data(createResult.text.utf8))

            let undo = try await client.callTool(name: "undo", arguments: "{}")
            #expect(!undo.isError)
        }
    }

    @Test func redoReappliesUndoneOperation() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"RedoMe","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            _ = try await client.callTool(name: "undo", arguments: "{}")

            let redo = try await client.callTool(name: "redo", arguments: "{}")
            #expect(!redo.isError)
        }
    }

    @Test func undoHistoryListsRecordedOperations() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Traceable","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            let history = try await client.callTool(name: "undo_history", arguments: "{}")
            #expect(!history.isError)
            #expect(history.text.contains("created note"))
        }
    }
}
