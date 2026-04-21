import Foundation
import Testing
@testable import CheAppleNotesMCP

@Suite struct ShareMetadataTests {

    @Test func notSharedResponseOmitsOptionalFields() {
        let m = ShareMetadata.notShared
        let dict = m.asDictionary()
        #expect(dict["isShared"] as? Bool == false)
        #expect(dict["serverShareDataPresent"] as? Bool == false)
        // Optional fields must not be present when not shared.
        #expect(dict["shareURL"] == nil)
        #expect(dict["rootObjectType"] == nil)
        #expect(dict["title"] == nil)
        #expect(dict["snippet"] == nil)
        #expect(dict["noteCount"] == nil)
        #expect(dict["subfolderCount"] == nil)
        #expect(dict["receivedDate"] == nil)
    }

    @Test func sharedResponseIncludesAllProvidedFields() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 0)
        let m = ShareMetadata(
            isShared: true,
            rootObjectType: "note",
            title: "Shared doc",
            snippet: "preview",
            shareURL: "https://www.icloud.com/notes/abc",
            noteCount: 1,
            subfolderCount: 0,
            receivedDate: receivedAt,
            serverShareDataPresent: true
        )
        let dict = m.asDictionary()
        #expect(dict["isShared"] as? Bool == true)
        #expect(dict["rootObjectType"] as? String == "note")
        #expect(dict["title"] as? String == "Shared doc")
        #expect(dict["snippet"] as? String == "preview")
        #expect(dict["shareURL"] as? String == "https://www.icloud.com/notes/abc")
        #expect(dict["noteCount"] as? Int == 1)
        #expect(dict["subfolderCount"] as? Int == 0)
        #expect(dict["serverShareDataPresent"] as? Bool == true)
        // receivedDate must round-trip as ISO 8601.
        let iso = dict["receivedDate"] as? String
        #expect(iso != nil)
        #expect(iso?.contains("2001-01-01") == true)
    }

    @Test func serverShareDataPresentAlwaysBool() {
        // Spec: serverShareDataPresent MUST be a Bool on every response,
        // even when the rest of the optional fields are absent.
        let notShared = ShareMetadata.notShared.asDictionary()
        #expect(notShared["serverShareDataPresent"] is Bool)

        let shared = ShareMetadata(
            isShared: true,
            rootObjectType: nil,
            title: nil,
            snippet: nil,
            shareURL: nil,
            noteCount: nil,
            subfolderCount: nil,
            receivedDate: nil,
            serverShareDataPresent: false
        ).asDictionary()
        #expect(shared["serverShareDataPresent"] is Bool)
    }
}
