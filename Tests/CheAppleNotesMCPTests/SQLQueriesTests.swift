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
