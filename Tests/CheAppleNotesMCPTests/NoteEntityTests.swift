import Foundation
import Testing
@testable import CheAppleNotesMCP

@Suite struct NoteEntityTests {

    private func makeNote(
        pk: Int64 = 42,
        identifier: String = "note-uuid",
        accountIdentifier: String? = "acct-uuid",
        shared: Bool = false
    ) -> Note {
        Note(
            pk: pk,
            identifier: identifier,
            title: "t",
            folderPK: nil,
            folderName: nil,
            accountName: nil,
            accountIdentifier: accountIdentifier,
            creationDate: nil,
            modificationDate: nil,
            isPinned: false,
            isPasswordProtected: false,
            snippet: nil,
            shared: shared,
            bodyText: nil,
            bodyHTML: nil,
            bodyDecodeError: false
        )
    }

    @Test func appleScriptIDUsesAccountAndPrimaryKey() {
        let n = makeNote(pk: 7, accountIdentifier: "abc")
        #expect(n.appleScriptID == "x-coredata://abc/ICNote/p7")
    }

    @Test func appleScriptIDFallsBackWhenAccountMissing() {
        let n = makeNote(identifier: "fallback-uuid", accountIdentifier: nil)
        #expect(n.appleScriptID == "fallback-uuid")
    }

    @Test func appleScriptIDFallsBackWhenAccountEmpty() {
        let n = makeNote(identifier: "empty-acct", accountIdentifier: "")
        #expect(n.appleScriptID == "empty-acct")
    }

    @Test func bodyDecodeErrorDefaultsFalse() {
        let n = makeNote()
        #expect(!n.bodyDecodeError)
    }

    @Test func sharedDefaultsFalse() {
        let n = makeNote()
        #expect(!n.shared)
    }

    @Test func sharedCanBeSetTrue() {
        let n = makeNote(shared: true)
        #expect(n.shared)
    }

    @Test func attachmentDefaultsLocalPathNil() {
        let a = Attachment(pk: 1, identifier: "att", filename: "x.png", typeUTI: "public.png", parentNotePK: 7)
        #expect(a.localPath == nil)
    }
}
