import Testing
@testable import CheAppleNotesMCP

@Suite struct VersionTests {

    @Test func currentVersionIsNotEmpty() {
        #expect(!AppVersion.current.isEmpty)
    }

    @Test func nameMatchesPackage() {
        #expect(AppVersion.name == "CheAppleNotesMCP")
    }
}
