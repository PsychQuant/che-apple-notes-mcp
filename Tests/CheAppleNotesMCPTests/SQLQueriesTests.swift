import Foundation
import Testing
@testable import CheAppleNotesMCP

@Suite struct SQLQueriesTests {

    @Test func entityIDsQuerySelectsPrimaryKeyTable() {
        #expect(SQLQueries.entityIDsQuery.contains("Z_PRIMARYKEY"))
        #expect(SQLQueries.entityIDsQuery.contains("Z_ENT"))
        #expect(SQLQueries.entityIDsQuery.contains("Z_NAME"))
    }

    @Test func listAccountsFiltersByEntityParameter() {
        #expect(SQLQueries.listAccounts.contains(":entityID"))
        #expect(SQLQueries.listAccounts.contains("ZICCLOUDSYNCINGOBJECT"))
        #expect(SQLQueries.listAccounts.contains("ZNAME"))
    }

    @Test func listFoldersUsesFolderAndAccountEntityParams() {
        #expect(SQLQueries.listFolders.contains(":folderEntityID"))
        #expect(SQLQueries.listFolders.contains(":accountEntityID"))
        #expect(SQLQueries.listFolders.contains("COALESCE(f.ZTITLE2, f.ZTITLE)"))
        #expect(SQLQueries.listFolders.contains("ZISHIDDENNOTECONTAINER"))
    }

    @Test func listNotesHasNoteEntityAndMarkedForDeletionFilter() {
        #expect(SQLQueries.listNotes.contains(":noteEntityID"))
        #expect(SQLQueries.listNotes.contains(":folderEntityID"))
        #expect(SQLQueries.listNotes.contains(":accountEntityID"))
        #expect(SQLQueries.listNotes.contains("ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0"))
    }

    @Test func listNotesCoalescesCreationDateColumns() {
        #expect(SQLQueries.listNotes.contains("COALESCE(n.ZCREATIONDATE3"))
        #expect(SQLQueries.listNotes.contains("ZCREATIONDATE2"))
        #expect(SQLQueries.listNotes.contains("ZCREATIONDATE1"))
        #expect(SQLQueries.listNotes.contains("n.ZCREATIONDATE)"))
    }

    @Test func listFoldersExposesSharedHeuristic() {
        // Phase 1 (#2): shared derived from ZSERVERSHAREDATA (I own the share)
        // or ZZONEOWNERNAME (someone shared with me). No direct ZISSHARED column.
        #expect(SQLQueries.listFolders.contains("ZSERVERSHAREDATA"))
        #expect(SQLQueries.listFolders.contains("ZZONEOWNERNAME"))
        #expect(SQLQueries.listFolders.contains("AS shared"))
    }

    @Test func listNotesExposesSharedHeuristic() {
        #expect(SQLQueries.listNotes.contains("ZSERVERSHAREDATA"))
        #expect(SQLQueries.listNotes.contains("ZZONEOWNERNAME"))
        #expect(SQLQueries.listNotes.contains("AS shared"))
    }

    @Test func shareMetadataByRootIdentifierQueriesICInvitation() {
        // Phase 2 (#3): ZICINVITATION has the share metadata, joined via
        // ZROOTOBJECT FK to the note/folder row in ZICCLOUDSYNCINGOBJECT.
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZICINVITATION"))
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains(":rootIdentifier"))
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZSHAREURL"))
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZROOTOBJECTTYPE"))
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZNOTECOUNT"))
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZSUBFOLDERCOUNT"))
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZRECEIVEDDATE"))
        // Must report whether the CKShare BLOB is present without selecting its bytes.
        #expect(SQLQueries.shareMetadataByRootIdentifier.contains("ZSERVERSHAREDATA IS NOT NULL"))
        // Do not expose raw CKShare BLOB column in projection.
        #expect(!SQLQueries.shareMetadataByRootIdentifier.contains("i.ZSERVERSHAREDATA,"))
    }

    @Test func sharedRootObjectHeuristicQueriesSingleRow() {
        // Fallback for items without ZICINVITATION row but still marked shared
        // via ZSERVERSHAREDATA / ZZONEOWNERNAME on the item row itself.
        #expect(SQLQueries.sharedRootObjectHeuristic.contains(":rootIdentifier"))
        #expect(SQLQueries.sharedRootObjectHeuristic.contains("ZSERVERSHAREDATA"))
        #expect(SQLQueries.sharedRootObjectHeuristic.contains("ZZONEOWNERNAME"))
    }

    @Test func sharedRootObjectHeuristicProjectsServerShareDataPresent() {
        // Regression guard for verify-3 BLOCKER: heuristic fallback must
        // independently report whether ZSERVERSHAREDATA IS NOT NULL so the
        // reader can populate ShareMetadata.serverShareDataPresent truthfully.
        // Two columns: shared (aggregate heuristic) + server_share_data_present.
        #expect(SQLQueries.sharedRootObjectHeuristic.contains("AS shared"))
        #expect(SQLQueries.sharedRootObjectHeuristic.contains("AS server_share_data_present"))
    }

    @Test func noteByIdentifierAppendsIdentifierFilterAndLimit() {
        #expect(SQLQueries.noteByIdentifier.hasPrefix(SQLQueries.listNotes))
        #expect(SQLQueries.noteByIdentifier.contains(":identifier"))
        #expect(SQLQueries.noteByIdentifier.contains("LIMIT 1"))
    }

    @Test func noteBodyBlobReturnsZDATAAndEncryptedFlag() {
        #expect(SQLQueries.noteBodyBlob.contains("ZICNOTEDATA"))
        #expect(SQLQueries.noteBodyBlob.contains("ZDATA"))
        #expect(SQLQueries.noteBodyBlob.contains("ZCRYPTOTAG IS NOT NULL AS encrypted"))
        #expect(SQLQueries.noteBodyBlob.contains(":notePK"))
    }

    @Test func coreDataDateReturnsNilForNilOrNonPositive() {
        #expect(SQLQueries.coreDataDate(nil) == nil)
        #expect(SQLQueries.coreDataDate(0) == nil)
        #expect(SQLQueries.coreDataDate(-1) == nil)
    }

    @Test func coreDataDateUsesReferenceDateEpoch() {
        // 2001-01-01T00:00:00Z corresponds to reference date 0; use a known offset.
        // 1 day after reference: 86400 seconds
        let d = SQLQueries.coreDataDate(86400)
        let expected = Date(timeIntervalSinceReferenceDate: 86400)
        #expect(d == expected)
    }
}
