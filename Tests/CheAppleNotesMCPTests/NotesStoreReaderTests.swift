import Foundation
import SQLite3
import Testing
@testable import CheAppleNotesMCP

/// Integration tests that build a minimal Notes-like SQLite database in a
/// temp file, then drive `NotesStoreReader` against it. The goal is to
/// exercise the share-metadata fallback paths with real row shapes that
/// were previously only covered by SQL-string assertions.
///
/// Added as part of #6 hardening — Finding 9 from the #3 round-2
/// verification report pointed out that
/// `sharedRootObjectHeuristicProjectsServerShareDataPresent` only checks
/// SQL text, not runtime behavior on a participant-side fake row (ZZONEOWNERNAME
/// set, ZSERVERSHAREDATA NULL), which is the exact pre-fix BLOCKER case.
@Suite struct NotesStoreReaderTests {

    // MARK: - Test fixture builder

    /// Run one SQL statement against an open writer handle. Swift-side
    /// alternative to batch-running schema text; kept simple so each DDL /
    /// INSERT is individually asserted.
    private func runStatement(_ sql: String, on db: OpaquePointer?) {
        var stmt: OpaquePointer?
        let prepOK = sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK
        #expect(prepOK, "prepare failed for: \(sql)")
        let stepRC = sqlite3_step(stmt)
        #expect(stepRC == SQLITE_DONE, "step rc=\(stepRC) for: \(sql)")
        sqlite3_finalize(stmt)
    }

    /// Build a tiny Notes-compatible DB at `url` with rows exercising the
    /// participant, owner, and unshared heuristic branches. Uses a separate
    /// SQLite handle in read-write mode to seed data; the `NotesStoreReader`
    /// under test then re-opens it read-only via its existing init path.
    private func buildFixture(url: URL) throws {
        try? FileManager.default.removeItem(at: url)

        var writer: OpaquePointer?
        let openRC = sqlite3_open_v2(
            url.path,
            &writer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        #expect(openRC == SQLITE_OK, "open writer rc=\(openRC)")
        defer { sqlite3_close(writer) }

        // Minimal schema subset — only columns touched by the queries under
        // test. Real NoteStore.sqlite has ~150 columns; we only need the
        // handful the heuristic + invitation queries touch.
        runStatement("CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER, Z_NAME VARCHAR)", on: writer)
        runStatement("""
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER,
                Z_OPT INTEGER,
                ZIDENTIFIER VARCHAR,
                ZSERVERSHAREDATA BLOB,
                ZZONEOWNERNAME VARCHAR
            )
            """, on: writer)
        runStatement("""
            CREATE TABLE ZICINVITATION (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER,
                Z_OPT INTEGER,
                ZROOTOBJECT INTEGER,
                ZROOTOBJECTTYPE VARCHAR,
                ZTITLE VARCHAR,
                ZSNIPPET VARCHAR,
                ZSHAREURL VARCHAR,
                ZNOTECOUNT INTEGER,
                ZSUBFOLDERCOUNT INTEGER,
                ZRECEIVEDDATE TIMESTAMP,
                ZSERVERSHAREDATA BLOB
            )
            """, on: writer)

        // Entity IDs — ICNote=12 ICFolder=15 to mimic the real schema.
        runStatement("INSERT INTO Z_PRIMARYKEY VALUES (12, 'ICNote')", on: writer)
        runStatement("INSERT INTO Z_PRIMARYKEY VALUES (15, 'ICFolder')", on: writer)

        // Participant-side note: shared (someone shared it with us) but
        // ZSERVERSHAREDATA is NULL because we aren't the CKShare owner.
        // Regression guard for the pre-fix BLOCKER.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZSERVERSHAREDATA, ZZONEOWNERNAME)
            VALUES (100, 12, 'participant-note-uuid', NULL, 'shared-by-someone')
            """, on: writer)

        // Owner-side note: we own a CKShare, so ZSERVERSHAREDATA is non-null.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZSERVERSHAREDATA, ZZONEOWNERNAME)
            VALUES (101, 12, 'owner-note-uuid', X'01020304', NULL)
            """, on: writer)

        // Unshared note: both signals NULL.
        runStatement("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZSERVERSHAREDATA, ZZONEOWNERNAME)
            VALUES (102, 12, 'unshared-note-uuid', NULL, NULL)
            """, on: writer)
    }

    private func makeFixtureURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("NotesStoreReaderTest-\(UUID().uuidString).sqlite")
    }

    // MARK: - Tests

    @Test func getShareMetadataParticipantSideReturnsSharedWithoutServerShareData() throws {
        // Finding-9 regression guard: participant-side row must report
        // isShared=true AND serverShareDataPresent=false. The pre-fix bug
        // hardcoded serverShareDataPresent=false even for owner-side rows,
        // but this test pins the genuine participant case.
        let url = makeFixtureURL()
        try buildFixture(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try NotesStoreReader(at: url)
        let metadata = try reader.getShareMetadata(identifier: "participant-note-uuid")

        #expect(metadata.isShared)
        #expect(metadata.serverShareDataPresent == false)
        // No ZICINVITATION row → optional fields stay nil.
        #expect(metadata.shareURL == nil)
        #expect(metadata.rootObjectType == nil)
    }

    @Test func getShareMetadataOwnerSideReturnsSharedWithServerShareData() throws {
        // Owner-side row: ZSERVERSHAREDATA has bytes → serverShareDataPresent=true.
        let url = makeFixtureURL()
        try buildFixture(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try NotesStoreReader(at: url)
        let metadata = try reader.getShareMetadata(identifier: "owner-note-uuid")

        #expect(metadata.isShared)
        #expect(metadata.serverShareDataPresent)
    }

    @Test func getShareMetadataUnsharedNoteReturnsNotShared() throws {
        // Both signals NULL → fully unshared response.
        let url = makeFixtureURL()
        try buildFixture(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try NotesStoreReader(at: url)
        let metadata = try reader.getShareMetadata(identifier: "unshared-note-uuid")

        #expect(metadata.isShared == false)
        #expect(metadata.serverShareDataPresent == false)
        #expect(metadata.shareURL == nil)
    }

    @Test func getShareMetadataUnknownIdentifierReturnsNotShared() throws {
        // ZIDENTIFIER that isn't in the DB at all → reader falls through the
        // invitation + heuristic paths to ShareMetadata.notShared.
        let url = makeFixtureURL()
        try buildFixture(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try NotesStoreReader(at: url)
        let metadata = try reader.getShareMetadata(identifier: "no-such-uuid")

        #expect(metadata.isShared == false)
        #expect(metadata.serverShareDataPresent == false)
    }
}
