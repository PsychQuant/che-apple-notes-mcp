import AppKit
import Foundation

/// Converts between plaintext and basic HTML. Used by:
/// - SQLite read path when returning bodies (wrapping plaintext in `<div>`)
/// - AppleScript write path converting `body_text` input into HTML for Notes.app
///
/// v0.2.0 TODO: accept AttributeRun metadata from protobuf to produce `<b>`,
/// `<i>`, `<a>`, `<ul>`, `<li>`.
enum BodyHTMLRenderer {

    /// Escape + wrap plaintext. Newlines become `<br>`.
    static func plaintextToHTML(_ text: String) -> String {
        if text.isEmpty { return "" }
        let escaped = escapeHTML(text)
            .replacingOccurrences(of: "\n", with: "<br>")
        return "<div>\(escaped)</div>"
    }

    /// Best-effort HTML → plaintext via NSAttributedString. Falls back to a
    /// regex-based stripper if NSAttributedString init fails (e.g., malformed HTML).
    static func htmlToPlaintext(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return stripTags(html) }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attr = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            return attr.string
        }
        return stripTags(html)
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
