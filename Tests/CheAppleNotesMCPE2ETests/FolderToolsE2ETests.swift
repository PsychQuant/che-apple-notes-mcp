import Foundation
import Testing

@Suite(.serialized) struct FolderToolsE2ETests {

    @Test func listFoldersIncludesFixtureFolder() async throws {
        try await withFixtureFolder { client, fixture in
            // Filter by the account the fixture actually landed in. Hosts
            // without "On My Mac" fall back to the server's default (iCloud),
            // so a hardcoded filter would return empty on iCloud-only Macs.
            let args: String = fixture.account.map {
                #"{"account":"\#($0)"}"#
            } ?? "{}"
            let result = try await client.callTool(
                name: "list_folders",
                arguments: args
            )
            #expect(!result.isError)
            #expect(result.text.contains(fixture.name))
        }
    }

    @Test func createFolderReturnsNonEmptyID() async throws {
        // Don't touch the fixture folder — create a second one specifically for
        // this assertion so fixture teardown still works cleanly.
        try await withFixtureFolder { client, _ in
            let tempName = "__CheMCPTest_\(UUID().uuidString.uppercased())__"
            let result = try await client.callTool(
                name: "create_folder",
                arguments: #"{"title":"\#(tempName)"}"#
            )
            #expect(!result.isError)

            struct FolderDTO: Decodable { let id: String; let title: String }
            let dto = try JSONDecoder().decode(FolderDTO.self, from: Data(result.text.utf8))
            #expect(!dto.id.isEmpty)
            #expect(dto.title == tempName)

            // Clean up the extra folder immediately.
            _ = try? await client.callTool(
                name: "delete_folder",
                arguments: #"{"id":"\#(dto.id)"}"#
            )
        }
    }

    @Test func updateFolderRenamesTheFolder() async throws {
        try await withFixtureFolder { client, fixture in
            let newName = "__CheMCPTest_\(UUID().uuidString.uppercased())__renamed"
            let result = try await client.callTool(
                name: "update_folder",
                arguments: #"{"id":"\#(fixture.id)","title":"\#(newName)"}"#
            )
            #expect(!result.isError)

            struct UpdateDTO: Decodable { let id: String; let title: String }
            let dto = try JSONDecoder().decode(UpdateDTO.self, from: Data(result.text.utf8))
            #expect(dto.id == fixture.id)
            #expect(dto.title == newName)
        }
    }

    @Test func deleteFolderRemovesAnEmptyFolder() async throws {
        try await withFixtureFolder { client, _ in
            // Create a second empty folder dedicated to deletion verification.
            let name = "__CheMCPTest_\(UUID().uuidString.uppercased())__todelete"
            let createResult = try await client.callTool(
                name: "create_folder",
                arguments: #"{"title":"\#(name)"}"#
            )
            struct FolderDTO: Decodable { let id: String }
            let dto = try JSONDecoder().decode(FolderDTO.self, from: Data(createResult.text.utf8))

            let delete = try await client.callTool(
                name: "delete_folder",
                arguments: #"{"id":"\#(dto.id)"}"#
            )
            #expect(!delete.isError)
            #expect(delete.text.contains("\"deleted\":true"))
        }
    }
}
