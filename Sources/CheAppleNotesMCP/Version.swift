import Foundation

/// Centralized version management
enum AppVersion {
    static let current = "0.1.0"
    static let name = "CheAppleNotesMCP"
    static let displayName = "macOS Apple Notes MCP Server"

    static var versionString: String {
        "\(name) \(current)"
    }

    static var helpMessage: String {
        """
        \(displayName)

        Usage: \(name) [options]
               \(name) --cli <tool> [--key value ...]
               echo '{"tool":"...","arguments":{}}' | \(name) --cli

        Options:
          --version, -v    Show version information
          --help, -h       Show this help message
          --setup          Probe SQLite read access (Full Disk Access) and trigger
                           the Automation permission dialog for Notes.app. Run once
                           from Terminal before using in non-interactive sessions.
          --cli <tool>     Run a tool directly without MCP server.

        Architecture: SQLite read (fast) + AppleScript write (safe). Falls back to
        AppleScript for reads when Full Disk Access is not granted.

        Version: \(current)
        Repository: https://github.com/PsychQuant/che-apple-notes-mcp
        """
    }
}
