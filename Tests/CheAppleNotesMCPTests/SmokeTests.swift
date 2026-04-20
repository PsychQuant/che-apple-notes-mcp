import XCTest
@testable import CheAppleNotesMCP

final class SmokeTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(AppVersion.current.isEmpty)
        XCTAssertEqual(AppVersion.name, "CheAppleNotesMCP")
    }

    func testAppleScriptEscapeSimple() {
        XCTAssertEqual(AppleScriptEscape.quote("hello"), "\"hello\"")
    }

    func testAppleScriptEscapeQuoteChar() {
        XCTAssertEqual(AppleScriptEscape.quote("say \"hi\""), "\"say \\\"hi\\\"\"")
    }

    func testAppleScriptEscapeNewlines() {
        let out = AppleScriptEscape.quote("line1\nline2")
        XCTAssertEqual(out, "\"line1\" & return & \"line2\"")
    }

    func testBodyFormatterTextWrap() throws {
        let html = try BodyFormatter.resolve(bodyText: "hello\nworld", bodyHTML: nil)
        XCTAssertTrue(html.contains("<div>"))
        XCTAssertTrue(html.contains("hello"))
        XCTAssertTrue(html.contains("<br>"))
    }

    func testBodyFormatterBothRejected() {
        XCTAssertThrowsError(try BodyFormatter.resolve(bodyText: "a", bodyHTML: "<p>b</p>"))
    }

    func testBodyFormatterEmpty() throws {
        let html = try BodyFormatter.resolve(bodyText: nil, bodyHTML: nil)
        XCTAssertEqual(html, "")
    }

    func testBodyFormatterEscapesHTML() throws {
        let html = try BodyFormatter.resolve(bodyText: "<script>", bodyHTML: nil)
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testUndoStackBasicRecordAndUndo() {
        let stack = UndoStack()
        stack.record(.create(id: "abc"))
        XCTAssertEqual(stack.undoDepth(), 1)
        let op = stack.popForUndo()
        XCTAssertNotNil(op)
        XCTAssertEqual(stack.undoDepth(), 0)
        XCTAssertEqual(stack.redoDepth(), 1)
    }

    func testBodyHTMLRendererPlaintextRoundtrip() {
        let html = BodyHTMLRenderer.plaintextToHTML("Hello")
        XCTAssertTrue(html.contains("Hello"))
        let back = BodyHTMLRenderer.htmlToPlaintext(html)
        XCTAssertTrue(back.contains("Hello"))
    }
}
