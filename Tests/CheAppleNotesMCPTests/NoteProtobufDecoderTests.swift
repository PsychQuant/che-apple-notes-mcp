import Foundation
import Testing
@testable import CheAppleNotesMCP

@Suite struct NoteProtobufDecoderTests {

    /// Minimal protobuf: field #2, wire type 2 (length-delimited), UTF-8 payload.
    private func embedString(_ s: String) -> Data {
        let bytes = Array(s.utf8)
        var out: [UInt8] = [0x12]  // tag = (2 << 3) | 2
        // length varint
        var len = bytes.count
        while len >= 0x80 {
            out.append(UInt8((len & 0x7F) | 0x80))
            len >>= 7
        }
        out.append(UInt8(len))
        out.append(contentsOf: bytes)
        return Data(out)
    }

    @Test func decodesSingleStringFromPlainProtobuf() throws {
        let payload = embedString("hello world from the body")
        let (text, html) = try NoteProtobufDecoder.decode(payload)
        #expect(text == "hello world from the body")
        #expect(html.contains("<div>"))
        #expect(html.contains("hello world from the body"))
    }

    @Test func picksLongestCandidateWhenMultipleStrings() {
        var buf = Data()
        buf.append(embedString("no"))
        buf.append(embedString("short tag"))
        buf.append(embedString("this is the actual longest body string in the message"))
        buf.append(embedString("a"))
        let result = NoteProtobufDecoder.extractLongestString(buf)
        #expect(result == "this is the actual longest body string in the message")
    }

    @Test func emptyInputReturnsNil() {
        #expect(NoteProtobufDecoder.extractLongestString(Data()) == nil)
    }

    @Test func gunzipOnNonGzippedDataReturnsItUnchanged() throws {
        let plain = embedString("plain protobuf, no gzip header")
        let out = try NoteProtobufDecoder.gunzip(plain)
        #expect(out == plain)
    }

    @Test func htmlOutputEscapesSpecialCharacters() throws {
        let payload = embedString("body with <b>tags</b> & amps")
        let (_, html) = try NoteProtobufDecoder.decode(payload)
        #expect(html.contains("&lt;b&gt;"))
        #expect(html.contains("&amp;"))
    }

    @Test func newlinesBecomeBreaksInHTML() throws {
        let payload = embedString("line1\nline2\nline3")
        let (_, html) = try NoteProtobufDecoder.decode(payload)
        #expect(html.contains("line1<br>line2<br>line3"))
    }

    @Test func emptyDataDecodesToEmptyStrings() throws {
        let (text, html) = try NoteProtobufDecoder.decode(Data())
        #expect(text == "")
        #expect(html == "")
    }
}
