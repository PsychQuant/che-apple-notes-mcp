import Foundation
import Testing

/// E2E coverage for the tag tools (`apple-notes-tags`).
///
/// Tags cannot be created programmatically (AppleScript-inserted "#text" does
/// not activate as a tag), so the usual create→exercise→teardown pattern is
/// impossible. Split coverage instead:
///
/// - Shape tests always run: they assert tool registration, response
///   structure, and the zero-match warnings contract on whatever library the
///   host has — meaningful even with zero tags.
/// - Content tests run only when `CHE_MCP_TAG_E2E_TAG` names a tag that the
///   operator has manually applied to at least one note in their library
///   (e.g. `CHE_MCP_TAG_E2E_TAG=todo make test-e2e`). They are visibly
///   skipped otherwise — never silently green.
@Suite(.serialized) struct TagToolsE2ETests {

    private static var seededTag: String? {
        ProcessInfo.processInfo.environment["CHE_MCP_TAG_E2E_TAG"]
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
    }

    // MARK: - Shape tests (always run)

    @Test func listTagsReturnsTagsArrayAndTotal() async throws {
        let client = try MCPClient()
        _ = try await client.initialize()
        defer { Task { await client.close() } }

        let result = try await client.callTool(name: "list_tags", arguments: "{}")
        #expect(!result.isError)

        let obj = try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any]
        let tags = obj?["tags"] as? [[String: Any]]
        #expect(tags != nil, "response must contain a tags array")
        #expect(obj?["total"] as? Int == tags?.count)
        for tag in tags ?? [] {
            #expect((tag["name"] as? String)?.hasPrefix("#") == true)
            #expect(tag["standardized"] is String)
            #expect((tag["note_count"] as? Int).map { $0 >= 0 } == true)
            #expect(tag["accounts"] is [Any])
        }
    }

    @Test func getNotesByTagWarnsOnUnknownTag() async throws {
        let client = try MCPClient()
        _ = try await client.initialize()
        defer { Task { await client.close() } }

        let bogus = "no-such-tag-\(UUID().uuidString.prefix(8))"
        let result = try await client.callTool(
            name: "get_notes_by_tag",
            arguments: #"{"tags":["\#(bogus)"]}"#
        )
        #expect(!result.isError)

        let obj = try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any]
        #expect(obj?["total"] as? Int == 0)
        let warnings = obj?["warnings"] as? [String]
        #expect(warnings?.contains(where: { $0.contains(bogus) }) == true,
                "unknown tag must surface in warnings")
    }

    @Test func listNotesIncludesTagsField() async throws {
        // Every SQLite-path note read must carry tags (array, possibly empty)
        // or null — the key must always be present.
        let client = try MCPClient()
        _ = try await client.initialize()
        defer { Task { await client.close() } }

        let result = try await client.callTool(name: "list_notes", arguments: #"{"limit":5}"#)
        #expect(!result.isError)
        let rows = try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [[String: Any]]
        for row in rows ?? [] {
            #expect(row.keys.contains("tags"), "note rows must carry a tags key")
            #expect(row["tags"] is [Any] || row["tags"] is NSNull,
                    "tags must be an array or null, never absent or another type")
        }
    }

    // MARK: - Content tests (require a pre-seeded tagged note)

    @Test(.enabled(if: seededTag != nil,
                   "set CHE_MCP_TAG_E2E_TAG to a tag manually applied to ≥1 note"))
    func listTagsIncludesSeededTag() async throws {
        let tag = Self.seededTag!
        let client = try MCPClient()
        _ = try await client.initialize()
        defer { Task { await client.close() } }

        let result = try await client.callTool(name: "list_tags", arguments: "{}")
        #expect(!result.isError)

        let obj = try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any]
        let tags = obj?["tags"] as? [[String: Any]] ?? []
        let match = tags.first { ($0["standardized"] as? String)?.caseInsensitiveCompare(tag) == .orderedSame }
        #expect(match != nil, "seeded tag #\(tag) missing from list_tags")
        #expect((match?["note_count"] as? Int).map { $0 >= 1 } == true,
                "seeded tag #\(tag) must count at least the seeded note")
    }

    @Test(.enabled(if: seededTag != nil,
                   "set CHE_MCP_TAG_E2E_TAG to a tag manually applied to ≥1 note"))
    func getNotesByTagReturnsSeededNoteWithTag() async throws {
        let tag = Self.seededTag!
        let client = try MCPClient()
        _ = try await client.initialize()
        defer { Task { await client.close() } }

        let result = try await client.callTool(
            name: "get_notes_by_tag",
            arguments: #"{"tags":["\#(tag)"],"limit":10}"#
        )
        #expect(!result.isError)

        let obj = try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any]
        #expect((obj?["total"] as? Int).map { $0 >= 1 } == true)
        #expect((obj?["warnings"] as? [String])?.isEmpty == true)
        let notes = obj?["notes"] as? [[String: Any]] ?? []
        for note in notes {
            let tags = (note["tags"] as? [String]) ?? []
            #expect(tags.contains { $0.caseInsensitiveCompare("#\(tag)") == .orderedSame },
                    "every returned note must carry #\(tag); got \(tags)")
        }
    }
}
