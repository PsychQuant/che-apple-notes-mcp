import Testing
@testable import CheAppleNotesMCP

@Suite struct AppleScriptEscapeTests {

    @Test func simpleStringGetsQuoted() {
        #expect(AppleScriptEscape.quote("hello") == "\"hello\"")
    }

    @Test func quoteCharacterIsBackslashEscaped() {
        #expect(AppleScriptEscape.quote("say \"hi\"") == "\"say \\\"hi\\\"\"")
    }

    @Test func newlineBecomesReturnConcatenation() {
        #expect(AppleScriptEscape.quote("line1\nline2") == "\"line1\" & return & \"line2\"")
    }

    @Test func emptyStringRoundTrips() {
        #expect(AppleScriptEscape.quote("") == "\"\"")
    }

    @Test func backslashIsDoubledFirst() {
        // "\\" becomes "\\\\" in the quoted form, and " still gets escaped to \"
        #expect(AppleScriptEscape.quote("a\\b") == "\"a\\\\b\"")
    }

    @Test func onlyQuoteCharacter() {
        #expect(AppleScriptEscape.quote("\"") == "\"\\\"\"")
    }

    @Test func multipleNewlinesProduceMultipleReturns() {
        #expect(AppleScriptEscape.quote("a\nb\nc") == "\"a\" & return & \"b\" & return & \"c\"")
    }

    @Test func nullByteIsStripped() {
        #expect(AppleScriptEscape.quote("a\u{0000}b") == "\"ab\"")
    }
}
