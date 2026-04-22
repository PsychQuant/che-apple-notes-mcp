import Foundation
import Testing

@Suite(.serialized) struct ShareMetadataE2ETests {

    @Test func getShareMetadataReturnsNotSharedForFixtureNote() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"UnsharedNote","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            try await settleForNotesFlush()

            // Pull the raw ZIDENTIFIER (uuid field) — get_share_metadata joins
            // ZICINVITATION.ZROOTOBJECT by ZIDENTIFIER, not by the x-coredata
            // URL form exposed as `id`.
            let list = try await client.callTool(
                name: "list_notes",
                arguments: #"{"folder_id":"\#(fixture.id)"}"#
            )
            struct Item: Decodable { let title: String; let uuid: String }
            let items = try JSONDecoder().decode([Item].self, from: Data(list.text.utf8))
            guard let target = items.first(where: { $0.title == "UnsharedNote" }) else {
                Issue.record("Fixture note not found in list_notes output")
                return
            }

            let meta = try await client.callTool(
                name: "get_share_metadata",
                arguments: #"{"identifier":"\#(target.uuid)"}"#
            )
            #expect(!meta.isError)

            struct MetaDTO: Decodable {
                let isShared: Bool
                let serverShareDataPresent: Bool
                let shareURL: String?
            }
            let dto = try JSONDecoder().decode(MetaDTO.self, from: Data(meta.text.utf8))
            #expect(dto.isShared == false)
            #expect(dto.serverShareDataPresent == false)
            #expect(dto.shareURL == nil)
        }
    }

    @Test func listNotesWithSharedTrueExcludesFixtureNote() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"FilterCheck","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            try await settleForNotesFlush()

            let sharedOnly = try await client.callTool(
                name: "list_notes",
                arguments: #"{"folder_id":"\#(fixture.id)","shared":true}"#
            )
            #expect(!sharedOnly.isError)

            struct Item: Decodable { let title: String }
            let items = try JSONDecoder().decode([Item].self, from: Data(sharedOnly.text.utf8))
            // Fixture note is not shared, so filtering to shared=true must exclude it.
            #expect(!items.contains { $0.title == "FilterCheck" })
        }
    }

    @Test func getShareMetadataRejectsXCoreDataURL() async throws {
        // Spec-negative: caller must pass the raw ZIDENTIFIER UUID. The
        // AppleScript URL form (x-coredata://<store>/ICNote/p<PK>) is the
        // output of list_notes.id / get_note.id but does not embed ZIDENTIFIER;
        // the server must refuse loudly rather than silently return notShared.
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"URLRejectCheck","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            try await settleForNotesFlush()

            // Fetch the x-coredata:// URL form (id, not uuid).
            let list = try await client.callTool(
                name: "list_notes",
                arguments: #"{"folder_id":"\#(fixture.id)"}"#
            )
            struct Item: Decodable { let title: String; let id: String }
            let items = try JSONDecoder().decode([Item].self, from: Data(list.text.utf8))
            guard let target = items.first(where: { $0.title == "URLRejectCheck" }) else {
                Issue.record("Fixture note not found")
                return
            }
            #expect(target.id.hasPrefix("x-coredata://"))

            let meta = try await client.callTool(
                name: "get_share_metadata",
                arguments: #"{"identifier":"\#(target.id)"}"#
            )
            #expect(meta.isError)
            #expect(meta.text.contains("raw ZIDENTIFIER"))
        }
    }

    @Test func listNotesWithSharedFalseIncludesFixtureNote() async throws {
        try await withFixtureFolder { client, fixture in
            _ = try await client.callTool(
                name: "create_note",
                arguments: #"{"title":"UnsharedOnly","body_text":"x","folder":"\#(fixture.name)"}"#
            )
            try await settleForNotesFlush()

            let unsharedOnly = try await client.callTool(
                name: "list_notes",
                arguments: #"{"folder_id":"\#(fixture.id)","shared":false}"#
            )
            #expect(!unsharedOnly.isError)

            struct Item: Decodable { let title: String }
            let items = try JSONDecoder().decode([Item].self, from: Data(unsharedOnly.text.utf8))
            // All items in the fixture folder are unshared, so shared=false
            // should include the fixture note.
            #expect(items.contains { $0.title == "UnsharedOnly" })
        }
    }
}
