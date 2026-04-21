import Foundation
import Testing

@Suite(.serialized) struct SearchE2ETests {

    @Test func searchNotesFindsByKeyword() async throws {
        try await withFixtureFolder { client, fixture in
            // Seed a note with a distinctive keyword. UUID ensures uniqueness
            // so pre-existing notes can't pollute the match count.
            let marker = "UniqMark\(UUID().uuidString.prefix(8))"
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"contains \#(marker) inside","body_text":"body","folder":"\#(fixture.name)"}"#
            )

            let search = try await client.callTool(
                name: "search_notes",
                arguments: #"{"keyword":"\#(marker)","limit":50}"#
            )
            #expect(!search.isError)
            #expect(search.text.contains(marker))
        }
    }
}
