import Foundation

/// Escape arbitrary strings for safe inclusion inside AppleScript source as
/// double-quoted literals.
enum AppleScriptEscape {

    /// Turn `Hello "world"\n` into `Hello \"world\"\n` as AppleScript will see it
    /// (i.e., backslash-escape quotes and backslashes; keep actual newlines as
    /// `\n` literal by concatenating with `return`).
    ///
    /// AppleScript does NOT interpret `\n` inside string literals — embedded
    /// newlines must be built with `& return & ` concatenation. We handle this
    /// by splitting on `\n` and joining with `& return &`.
    static func quote(_ s: String) -> String {
        let parts = s.components(separatedBy: "\n")
        if parts.count == 1 {
            return "\"\(escapeSingleLine(parts[0]))\""
        }
        return parts
            .map { "\"\(escapeSingleLine($0))\"" }
            .joined(separator: " & return & ")
    }

    private static func escapeSingleLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            // Tab can appear — AppleScript accepts tab inside string literals literally.
            .replacingOccurrences(of: "\u{0000}", with: "")  // null byte would terminate
    }
}
