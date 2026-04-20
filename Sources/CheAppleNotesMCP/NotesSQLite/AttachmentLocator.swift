import Foundation

/// Locate attachment binaries on disk.
///
/// Notes stores attachments at:
///   ~/Library/Group Containers/group.com.apple.notes/Accounts/<account-uuid>/Media/<attachment-uuid>/<filename>
///
/// v0.1.0 only returns paths (read-only). Upload / replace is not supported.
enum AttachmentLocator {

    static let mediaRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Group Containers/group.com.apple.notes/Accounts")
    }()

    /// Build a best-effort local path for an attachment. Returns nil if we can
    /// only guess the account UUID or the file isn't present.
    static func path(accountIdentifier: String?, attachmentIdentifier: String, filename: String?) -> String? {
        guard let accountIdentifier, !accountIdentifier.isEmpty else { return nil }
        let base = mediaRoot
            .appendingPathComponent(accountIdentifier)
            .appendingPathComponent("Media")
            .appendingPathComponent(attachmentIdentifier)
        if let filename {
            return base.appendingPathComponent(filename).path
        }
        // No filename known — return the folder; caller can list it.
        return base.path
    }
}
