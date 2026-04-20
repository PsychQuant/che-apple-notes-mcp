import Foundation

/// Normalize incoming `body_text` / `body_html` from MCP tool arguments into the
/// HTML string that Notes.app's `body` AppleScript property accepts.
enum BodyFormatter {

    enum BodyInputError: LocalizedError {
        case bothProvided
        case tooLarge(bytes: Int)

        var errorDescription: String? {
            switch self {
            case .bothProvided:
                return "Specify only one of body_text / body_html, not both."
            case .tooLarge(let bytes):
                return "Body too large (\(bytes) bytes); v0.1.0 caps at 1 MB. Split into multiple notes."
            }
        }
    }

    static let maxBodyBytes = 1_048_576  // 1 MB

    /// Normalize inputs. Returns the HTML string to feed AppleScript.
    static func resolve(bodyText: String?, bodyHTML: String?) throws -> String {
        if bodyText != nil, bodyHTML != nil {
            throw BodyInputError.bothProvided
        }
        let html: String
        if let html_ = bodyHTML {
            html = html_
        } else if let text = bodyText {
            html = BodyHTMLRenderer.plaintextToHTML(text)
        } else {
            html = ""
        }
        if html.utf8.count > maxBodyBytes {
            throw BodyInputError.tooLarge(bytes: html.utf8.count)
        }
        return html
    }
}
