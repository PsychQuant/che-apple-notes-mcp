import Testing
@testable import CheAppleNotesMCP

@Suite struct BodyHTMLRendererTests {

    @Test func plaintextToHTMLRoundTripsPlainWord() {
        let html = BodyHTMLRenderer.plaintextToHTML("Hello")
        #expect(html.contains("Hello"))
        #expect(html.contains("<div>"))

        let back = BodyHTMLRenderer.htmlToPlaintext(html)
        #expect(back.contains("Hello"))
    }

    @Test func emptyInputProducesEmptyOutput() {
        #expect(BodyHTMLRenderer.plaintextToHTML("") == "")
    }

    @Test func newlinesBecomeBreakTags() {
        let html = BodyHTMLRenderer.plaintextToHTML("a\nb")
        #expect(html.contains("a<br>b"))
    }

    @Test func htmlSpecialCharactersAreEscaped() {
        let html = BodyHTMLRenderer.plaintextToHTML("<b>&\"'")
        #expect(html.contains("&lt;b&gt;"))
        #expect(html.contains("&amp;"))
        #expect(html.contains("&quot;"))
        #expect(html.contains("&#39;"))
    }

    @Test func htmlToPlaintextStripsTags() {
        let plain = BodyHTMLRenderer.htmlToPlaintext("<p>hello <b>world</b></p>")
        #expect(plain.contains("hello"))
        #expect(plain.contains("world"))
        #expect(!plain.contains("<p>"))
        #expect(!plain.contains("<b>"))
    }

    @Test func htmlToPlaintextHandlesEntities() {
        let plain = BodyHTMLRenderer.htmlToPlaintext("<p>&amp; &lt; &gt;</p>")
        #expect(plain.contains("&"))
        #expect(plain.contains("<"))
        #expect(plain.contains(">"))
    }
}
