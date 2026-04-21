import Foundation
import Testing
@testable import CheAppleNotesMCP

@Suite struct CapabilitiesTests {

    @Test func noteStoreURLPointsAtGroupContainer() {
        let path = Capabilities.noteStoreURL.path
        #expect(path.hasSuffix("/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"))
    }

    @Test func noteStoreURLIsRelativeToCurrentUserHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Capabilities.noteStoreURL.path.hasPrefix(home))
    }

    @Test func detectReturnsConsistentShape() {
        // Runs without Notes.app state. Fields may be true/false depending on FDA;
        // we only assert the struct exists and that appleScriptAvailable is set
        // to the optimistic default documented in the source (always true at startup).
        let caps = Capabilities.detect()
        #expect(caps.appleScriptAvailable == true)
    }

    @Test func structConstructsWithExplicitFlags() {
        let caps = Capabilities(sqliteReadable: false, appleScriptAvailable: true)
        #expect(caps.sqliteReadable == false)
        #expect(caps.appleScriptAvailable == true)
    }
}
