import Foundation
import Testing
@testable import CheAppleNotesMCP

@Suite struct AttachmentLocatorTests {

    @Test func returnsNilWhenAccountIdentifierMissing() {
        let p = AttachmentLocator.path(
            accountIdentifier: nil,
            attachmentIdentifier: "att-1",
            filename: "image.png"
        )
        #expect(p == nil)
    }

    @Test func returnsNilWhenAccountIdentifierEmpty() {
        let p = AttachmentLocator.path(
            accountIdentifier: "",
            attachmentIdentifier: "att-1",
            filename: "image.png"
        )
        #expect(p == nil)
    }

    @Test func composesFullPathWhenFilenamePresent() {
        let p = AttachmentLocator.path(
            accountIdentifier: "acct-uuid",
            attachmentIdentifier: "att-1",
            filename: "image.png"
        )
        #expect(p != nil)
        #expect(p!.contains("/Library/Group Containers/group.com.apple.notes/Accounts/acct-uuid/Media/att-1/image.png"))
    }

    @Test func returnsDirectoryPathWhenFilenameAbsent() {
        let p = AttachmentLocator.path(
            accountIdentifier: "acct-uuid",
            attachmentIdentifier: "att-1",
            filename: nil
        )
        #expect(p != nil)
        #expect(p!.hasSuffix("/Accounts/acct-uuid/Media/att-1"))
    }

    @Test func mediaRootIsRelativeToCurrentUserHome() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/Accounts")
            .path
        #expect(AttachmentLocator.mediaRoot.path == expected)
    }
}
