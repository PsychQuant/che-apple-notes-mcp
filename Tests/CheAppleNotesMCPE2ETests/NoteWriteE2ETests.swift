import Foundation
import Testing

@Suite(.serialized) struct NoteWriteE2ETests {

    @Test func createNoteReturnsID() async throws {
        try await withFixtureFolder { client, fixture in
            let result = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"NewNote","body_text":"hi","folder":"\#(fixture.name)"}"#
            )
            #expect(!result.isError)

            struct Dto: Decodable { let id: String; let title: String }
            let dto = try JSONDecoder().decode(Dto.self, from: Data(result.text.utf8))
            #expect(!dto.id.isEmpty)
            #expect(dto.title == "NewNote")
        }
    }

    @Test func updateNoteChangesTitle() async throws {
        try await withFixtureFolder { client, fixture in
            let createResult = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Before","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            struct Created: Decodable { let id: String }
            let created = try JSONDecoder().decode(Created.self, from: Data(createResult.text.utf8))

            let update = try await client.callTool(
                name: "update_note",
                arguments: #"{"id":"\#(created.id)","title":"After"}"#
            )
            #expect(!update.isError)

            let get = try await client.callTool(
                name: "get_note",
                arguments: #"{"id":"\#(created.id)"}"#
            )
            #expect(!get.isError)
            #expect(get.text.contains("After"))
        }
    }

    @Test func deleteNoteRemovesByID() async throws {
        try await withFixtureFolder { client, fixture in
            let createResult = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Doomed","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            struct Created: Decodable { let id: String }
            let created = try JSONDecoder().decode(Created.self, from: Data(createResult.text.utf8))

            let delete = try await client.callTool(
                name: "delete_note",
                arguments: #"{"id":"\#(created.id)"}"#
            )
            #expect(!delete.isError)
        }
    }

    @Test func moveNoteChangesFolder() async throws {
        try await withFixtureFolder { client, fixture in
            // Create a secondary destination folder within the same process.
            let destName = "__CheMCPTest_\(UUID().uuidString.uppercased())__dest"
            let destCreate = try await client.callTool(
                name: "create_folder",
                arguments: #"{"title":"\#(destName)"}"#
            )
            struct FolderDto: Decodable { let id: String }
            let destFolder = try JSONDecoder().decode(FolderDto.self, from: Data(destCreate.text.utf8))

            let noteCreate = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Mover","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            struct NoteDto: Decodable { let id: String }
            let note = try JSONDecoder().decode(NoteDto.self, from: Data(noteCreate.text.utf8))

            let move = try await client.callTool(
                name: "move_note",
                arguments: #"{"id":"\#(note.id)","folder":"\#(destName)"}"#
            )
            #expect(!move.isError)

            // Clean up the extra destination folder (and its note).
            _ = try? await client.callTool(
                name: "delete_note",
                arguments: #"{"id":"\#(note.id)"}"#
            )
            _ = try? await client.callTool(
                name: "delete_folder",
                arguments: #"{"id":"\#(destFolder.id)"}"#
            )
        }
    }
}
