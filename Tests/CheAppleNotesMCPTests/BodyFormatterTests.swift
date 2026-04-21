import Testing
@testable import CheAppleNotesMCP

@Suite struct BodyFormatterTests {

    @Test func textIsWrappedInDivWithLineBreaks() throws {
        let html = try BodyFormatter.resolve(bodyText: "hello\nworld", bodyHTML: nil)
        #expect(html.contains("<div>"))
        #expect(html.contains("hello"))
        #expect(html.contains("<br>"))
    }

    @Test func bothInputsRejected() {
        #expect(throws: BodyFormatter.BodyInputError.self) {
            _ = try BodyFormatter.resolve(bodyText: "a", bodyHTML: "<p>b</p>")
        }
    }

    @Test func emptyInputsReturnEmptyString() throws {
        let html = try BodyFormatter.resolve(bodyText: nil, bodyHTML: nil)
        #expect(html == "")
    }

    @Test func plaintextIsHTMLEscaped() throws {
        let html = try BodyFormatter.resolve(bodyText: "<script>", bodyHTML: nil)
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func providedHTMLPassesThroughUnchanged() throws {
        let html = try BodyFormatter.resolve(bodyText: nil, bodyHTML: "<p>raw</p>")
        #expect(html == "<p>raw</p>")
    }

    @Test func oversizedBodyIsRejected() {
        let huge = String(repeating: "a", count: BodyFormatter.maxBodyBytes + 1)
        #expect(throws: BodyFormatter.BodyInputError.self) {
            _ = try BodyFormatter.resolve(bodyText: huge, bodyHTML: nil)
        }
    }

    @Test func exactlyMaxSizeAccepted() throws {
        // plaintextToHTML wraps in <div>...</div> so pick text that keeps under the cap
        let text = String(repeating: "a", count: BodyFormatter.maxBodyBytes - 16)
        let html = try BodyFormatter.resolve(bodyText: text, bodyHTML: nil)
        #expect(html.utf8.count <= BodyFormatter.maxBodyBytes)
    }
}
