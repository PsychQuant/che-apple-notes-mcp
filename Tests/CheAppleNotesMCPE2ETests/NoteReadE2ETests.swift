import Foundation
import Testing

@Suite(.serialized) struct NoteReadE2ETests {

    @Test func listNotesReturnsNotesInFixtureFolder() async throws {
        try await withFixtureFolder { client, fixture in
            // Seed 2 notes in the fixture folder.
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Alpha","body_text":"a","folder":"\#(fixture.name)"}"#
            )
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Beta","body_text":"b","folder":"\#(fixture.name)"}"#
            )

            try await settleForNotesFlush()

            let list = try await client.callTool(
                name: "list_notes",
                arguments: #"{"folder_id":"\#(fixture.id)"}"#
            )
            #expect(!list.isError)

            struct Item: Decodable { let id: String; let title: String }
            let items = try JSONDecoder().decode([Item].self, from: Data(list.text.utf8))
            #expect(items.count >= 2)
            let titles = Set(items.map(\.title))
            #expect(titles.contains("Alpha"))
            #expect(titles.contains("Beta"))
        }
    }

    @Test func listNotesQuickAcceptsRecentRange() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Fresh","body_text":"n","folder":"\#(fixture.name)"}"#
            )
            let result = try await client.callTool(
                name: "list_notes_quick",
                arguments: #"{"range":"recent","limit":100}"#
            )
            #expect(!result.isError)
            // Response is a JSON array even when empty; check it starts with [.
            #expect(result.text.hasPrefix("["))
        }
    }

    @Test func listNotesIncludesSharedField() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"SharedCheck","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            try await settleForNotesFlush()

            let list = try await client.callTool(
                name: "list_notes",
                arguments: #"{"folder_id":"\#(fixture.id)"}"#
            )
            #expect(!list.isError)

            struct Item: Decodable { let title: String; let shared: Bool }
            let items = try JSONDecoder().decode([Item].self, from: Data(list.text.utf8))
            #expect(items.contains { $0.title == "SharedCheck" })
        }
    }

    @Test func getNoteReturnsCreatedNoteByID() async throws {
        try await withFixtureFolder { client, fixture in
            let createResult = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"Readable","body_text":"body content","folder":"\#(fixture.name)"}"#
            )
            struct CreateDTO: Decodable { let id: String }
            let created = try JSONDecoder().decode(CreateDTO.self, from: Data(createResult.text.utf8))

            let get = try await client.callTool(
                name: "get_note",
                arguments: #"{"id":"\#(created.id)"}"#
            )
            #expect(!get.isError)
            #expect(get.text.contains("Readable"))
        }
    }
}
