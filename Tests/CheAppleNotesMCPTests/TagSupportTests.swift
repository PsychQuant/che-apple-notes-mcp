import Foundation
import SQLite3
import Testing
@testable import CheAppleNotesMCP

/// Tag-support tests (`apple-notes-tags`) driving `NotesStoreReader` against a
/// temp SQLite fixture with hashtag entities, hashtag inline attachments, a
/// non-hashtag inline attachment (mention) that must be excluded, a deleted
/// note carrying a tag, and the same tag duplicated across two accounts.
///
/// Entity IDs in the fixture's Z_PRIMARYKEY are deliberately different from
/// any real macOS release so a hardcoded Z_ENT anywhere in the tag queries
/// fails loudly here.
@Suite struct TagSupportTests {

    private static let hashtagUTI = "com.apple.notes.inlinetextattachment.hashtag"
    private static let mentionUTI = "com.apple.notes.inlinetextattachment.mention"

    // MARK: - Fixture builder

    private func runStatement(_ sql: String, on db: OpaquePointer?) {
        var stmt: OpaquePointer?
        let prepOK = sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK
        #expect(prepOK, "prepare failed for: \(sql) — \(String(cString: sqlite3_errmsg(db)))")
        let stepRC = sqlite3_step(stmt)
        #expect(stepRC == SQLITE_DONE, "step rc=\(stepRC) for: \(sql)")
        sqlite3_finalize(stmt)
    }

    /// Build a Notes-like DB at `url` with every column the listNotes + tag
    /// queries touch. `includeTagEntities: false` omits ICHashtag /
    /// ICInlineAttachment from Z_PRIMARYKEY to simulate an older or renamed
    /// schema (entity-resolution failure path).
    private func buildFixture(url: URL, includeTagEntities: Bool = true) throws {
        try? FileManager.default.removeItem(at: url)

        var writer: OpaquePointer?
        let openRC = sqlite3_open_v2(
            url.path, &writer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        )
        #expect(openRC == SQLITE_OK, "open writer rc=\(openRC)")
        defer { sqlite3_close(writer) }

        runStatement("CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER, Z_NAME VARCHAR)", on: writer)
        runStatement("""
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER,
                Z_OPT INTEGER,
                ZIDENTIFIER VARCHAR,
                ZNAME VARCHAR,
                ZTITLE VARCHAR,
                ZTITLE1 VARCHAR,
                ZTITLE2 VARCHAR,
                ZFOLDER INTEGER,
                ZOWNER INTEGER,
                ZPARENT INTEGER,
                ZISHIDDENNOTECONTAINER INTEGER,
                ZSORTORDER INTEGER,
                ZCREATIONDATE TIMESTAMP,
                ZCREATIONDATE1 TIMESTAMP,
                ZCREATIONDATE2 TIMESTAMP,
                ZCREATIONDATE3 TIMESTAMP,
                ZMODIFICATIONDATE TIMESTAMP,
                ZMODIFICATIONDATE1 TIMESTAMP,
                ZISPINNED INTEGER,
                ZISPASSWORDPROTECTED INTEGER,
                ZSNIPPET VARCHAR,
                ZSERVERSHAREDATA BLOB,
                ZZONEOWNERNAME VARCHAR,
                ZMARKEDFORDELETION INTEGER,
                ZDISPLAYTEXT VARCHAR,
                ZSTANDARDIZEDCONTENT VARCHAR,
                ZALTTEXT VARCHAR,
                ZTOKENCONTENTIDENTIFIER VARCHAR,
                ZTYPEUTI VARCHAR,
                ZTYPEUTI1 VARCHAR,
                ZNOTE INTEGER,
                ZNOTE1 INTEGER,
                ZACCOUNT INTEGER,
                ZACCOUNT1 INTEGER,
                ZACCOUNT2 INTEGER,
                ZACCOUNT3 INTEGER
            )
            """, on: writer)

        // Entity IDs — values intentionally unlike any real release (real
        // macOS 26 uses 8/9 for hashtag/inline attachment, 11-ish for note).
        runStatement("INSERT INTO Z_PRIMARYKEY VALUES (42, 'ICNote')", on: writer)
        runStatement("INSERT INTO Z_PRIMARYKEY VALUES (43, 'ICFolder')", on: writer)
        runStatement("INSERT INTO Z_PRIMARYKEY VALUES (44, 'ICAccount')", on: writer)
        if includeTagEntities {
            runStatement("INSERT INTO Z_PRIMARYKEY VALUES (45, 'ICHashtag')", on: writer)
            runStatement("INSERT INTO Z_PRIMARYKEY VALUES (46, 'ICInlineAttachment')", on: writer)
        }

        // Accounts.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZNAME, ZIDENTIFIER)
            VALUES (1, 44, 'iCloud', 'acct-icloud'), (2, 44, 'On My Mac', 'acct-local')
            """, on: writer)

        // Folders (ZTITLE2 = folder title column used by the notes join).
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZOWNER)
            VALUES (10, 43, 'folder-notes', 'Notes', 1), (11, 43, 'folder-local', 'Local', 2)
            """, on: writer)

        // Notes. 102 is marked for deletion and must vanish from tag counts
        // and tag-filtered results. Distinct modification dates pin sort order.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZFOLDER, ZMODIFICATIONDATE1, ZMARKEDFORDELETION)
            VALUES
                (100, 42, 'note-deal-a',  'Deal note A',       10, 500.0, 0),
                (101, 42, 'note-citrus',  'Citrus note',       10, 400.0, NULL),
                (102, 42, 'note-deleted', 'Deleted deal note', 10, 300.0, 1),
                (103, 42, 'note-local',   'Local deal note',   11, 200.0, 0),
                (104, 42, 'note-untagged','Untagged note',     10, 100.0, 0)
            """, on: writer)

        // Hashtag entities. ZDISPLAYTEXT has no leading '#' and
        // ZSTANDARDIZEDCONTENT is uppercase, matching the live macOS 26 rows.
        // 'Deal-Flow' exists in both accounts; 'orphan' has no live notes.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZDISPLAYTEXT, ZSTANDARDIZEDCONTENT, ZACCOUNT2)
            VALUES
                (200, 45, 'Deal-Flow', 'DEAL-FLOW', 1),
                (201, 45, 'citrus',    'CITRUS',    1),
                (202, 45, 'Deal-Flow', 'DEAL-FLOW', 2),
                (203, 45, 'orphan',    'ORPHAN',    1)
            """, on: writer)

        // Hashtag inline attachments (note FK in ZNOTE1, like macOS 26).
        // 300+301: same tag twice in note 100 (dedup). 306: mention UTI that
        // must never be treated as a tag. 307: deleted attachment row.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZALTTEXT, ZTOKENCONTENTIDENTIFIER, ZTYPEUTI1, ZNOTE1, ZMARKEDFORDELETION)
            VALUES
                (300, 46, '#Deal-Flow', 'DEAL-FLOW', '\(Self.hashtagUTI)', 100, 0),
                (301, 46, '#deal-flow', 'DEAL-FLOW', '\(Self.hashtagUTI)', 100, NULL),
                (302, 46, '#citrus',    'CITRUS',    '\(Self.hashtagUTI)', 100, 0),
                (303, 46, '#citrus',    'CITRUS',    '\(Self.hashtagUTI)', 101, 0),
                (304, 46, '#Deal-Flow', 'DEAL-FLOW', '\(Self.hashtagUTI)', 102, 0),
                (305, 46, '#Deal-Flow', 'DEAL-FLOW', '\(Self.hashtagUTI)', 103, 0),
                (306, 46, '@someone',   'SOMEONE',   '\(Self.mentionUTI)', 100, 0),
                (307, 46, '#citrus',    'CITRUS',    '\(Self.hashtagUTI)', 104, 1)
            """, on: writer)
    }

    private func makeFixtureURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TagSupportTest-\(UUID().uuidString).sqlite")
    }

    private func withReader(
        includeTagEntities: Bool = true,
        _ body: (NotesStoreReader) throws -> Void
    ) throws {
        let url = makeFixtureURL()
        try buildFixture(url: url, includeTagEntities: includeTagEntities)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try NotesStoreReader(at: url)
        try body(reader)
    }

    // MARK: - list_tags

    @Test func listTagsCountsLiveNotesAndMergesAccounts() throws {
        try withReader { reader in
            let tags = try reader.listTags()
            #expect(tags.count == 3)

            let byName = Dictionary(uniqueKeysWithValues: tags.map { ($0.standardized, $0) })
            // Deal-Flow: notes 100 + 103 live; 102 deleted. Merged across accounts.
            #expect(byName["deal-flow"]?.noteCount == 2)
            #expect(byName["deal-flow"]?.name == "#Deal-Flow")
            #expect(byName["deal-flow"]?.accounts == ["On My Mac", "iCloud"].sorted())
            // citrus: notes 100 + 101 (307 attachment deleted → 104 untagged).
            #expect(byName["citrus"]?.noteCount == 2)
            #expect(byName["citrus"]?.accounts == ["iCloud"])
            // Orphan tag kept with zero count.
            #expect(byName["orphan"]?.noteCount == 0)
        }
    }

    @Test func listTagsSortsByCountDescThenNameAsc() throws {
        try withReader { reader in
            let tags = try reader.listTags()
            // Counts 2/2/0; tie broken alphabetically: #citrus before #Deal-Flow.
            #expect(tags.map(\.name) == ["#citrus", "#Deal-Flow", "#orphan"])
        }
    }

    @Test func listTagsAccountFilterScopesNamesAndCounts() throws {
        try withReader { reader in
            let tags = try reader.listTags(accountName: "iCloud")
            let byName = Dictionary(uniqueKeysWithValues: tags.map { ($0.standardized, $0) })
            // Only the iCloud note (100) counts for deal-flow.
            #expect(byName["deal-flow"]?.noteCount == 1)
            #expect(byName["deal-flow"]?.accounts == ["iCloud"])
            #expect(byName["citrus"]?.noteCount == 2)

            let localTags = try reader.listTags(accountName: "On My Mac")
            #expect(localTags.map(\.standardized) == ["deal-flow"])
            #expect(localTags.first?.noteCount == 1)
        }
    }

    // MARK: - Tag filter on listNotes (powers get_notes_by_tag)

    @Test func tagFilterMatchAnyReturnsUnionAndExcludesDeleted() throws {
        try withReader { reader in
            var options = NotesStoreReader.NoteListOptions()
            options.tags = ["deal-flow", "citrus"]
            let notes = try reader.listNotes(options: options)
            // 100 (both tags), 101 (citrus), 103 (deal-flow); 102 deleted.
            #expect(Set(notes.map(\.identifier)) == ["note-deal-a", "note-citrus", "note-local"])
        }
    }

    @Test func tagFilterMatchAllRequiresEveryTag() throws {
        try withReader { reader in
            var options = NotesStoreReader.NoteListOptions()
            options.tags = ["deal-flow", "citrus"]
            options.tagsMatchAll = true
            let notes = try reader.listNotes(options: options)
            #expect(notes.map(\.identifier) == ["note-deal-a"])
        }
    }

    @Test func tagFilterNormalizesLeadingHashAndCase() throws {
        try withReader { reader in
            var options = NotesStoreReader.NoteListOptions()
            options.tags = ["#CITRUS"]
            let notes = try reader.listNotes(options: options)
            #expect(Set(notes.map(\.identifier)) == ["note-deal-a", "note-citrus"])
        }
    }

    @Test func tagFilterComposesWithAccountFilter() throws {
        try withReader { reader in
            var options = NotesStoreReader.NoteListOptions()
            options.tags = ["deal-flow"]
            options.accountName = "On My Mac"
            let notes = try reader.listNotes(options: options)
            #expect(notes.map(\.identifier) == ["note-local"])
        }
    }

    @Test func unknownTagInputMatchesNothingWithoutError() throws {
        try withReader { reader in
            var options = NotesStoreReader.NoteListOptions()
            options.tags = ["no-such-tag"]
            let notes = try reader.listNotes(options: options)
            #expect(notes.isEmpty)
        }
    }

    // MARK: - Zero-match warnings

    @Test func unknownTagsReportsOnlyUnmatchedInputs() throws {
        try withReader { reader in
            let unknown = try reader.unknownTags(["citrus", "#Deal-Flow", "nope"])
            #expect(unknown == ["nope"])
        }
    }

    // MARK: - tags enrichment on note reads

    @Test func notesCarryDeduplicatedSortedTags() throws {
        try withReader { reader in
            let notes = try reader.listNotes()
            let byId = Dictionary(uniqueKeysWithValues: notes.map { ($0.identifier, $0) })
            // Duplicate '#Deal-Flow' occurrence collapsed; mention excluded;
            // alphabetical order; literal in-note casing preserved.
            #expect(byId["note-deal-a"]?.tags == ["#citrus", "#Deal-Flow"])
            #expect(byId["note-citrus"]?.tags == ["#citrus"])
            // Deleted attachment row (307) does not tag note 104 — and a
            // resolved-but-empty result is [], never nil, on the SQLite path.
            #expect(byId["note-untagged"]?.tags == [])
        }
    }

    @Test func getNoteIncludesTags() throws {
        try withReader { reader in
            let note = try reader.getNote(identifier: "note-deal-a", includeBody: false)
            #expect(note?.tags == ["#citrus", "#Deal-Flow"])
        }
    }

    @Test func searchNotesIncludesTags() throws {
        try withReader { reader in
            let results = try reader.searchNotes(keywords: ["citrus"])
            #expect(results.first?.tags == ["#citrus"])
        }
    }

    // MARK: - Entity resolution (schema drift)

    @Test func listTagsThrowsEntityNotFoundOnSchemaWithoutHashtags() throws {
        try withReader(includeTagEntities: false) { reader in
            #expect(throws: NotesSQLiteError.self) {
                _ = try reader.listTags()
            }
        }
    }

    @Test func tagFilterThrowsOnSchemaWithoutInlineAttachments() throws {
        try withReader(includeTagEntities: false) { reader in
            var options = NotesStoreReader.NoteListOptions()
            options.tags = ["citrus"]
            #expect(throws: NotesSQLiteError.self) {
                _ = try reader.listNotes(options: options)
            }
        }
    }

    @Test func plainReadsSurviveSchemaWithoutTagEntities() throws {
        // Non-tag tools must keep working when the hashtag entities are
        // missing; tags degrade to nil (unknown), never [] (asserted absent).
        try withReader(includeTagEntities: false) { reader in
            let notes = try reader.listNotes()
            #expect(notes.count == 4)
            #expect(notes.allSatisfy { $0.tags == nil })
        }
    }
}
