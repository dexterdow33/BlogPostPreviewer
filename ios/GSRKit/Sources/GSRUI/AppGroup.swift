#if os(iOS)
import Foundation
import GSRKit

/// The App Group the app and its share extension share. Must match both targets'
/// entitlements in ios/project.yml.
public enum AppGroup {
    public static let id = "group.com.granitestatereport.app"

    /// The shared outbox. Falls back to this process's own Application Support folder
    /// when the group is unavailable (an unsigned simulator build), so the app still works;
    /// the app and the extension just stop seeing each other's drafts.
    public static func outbox() throws -> OutboxStore {
        if let shared = try? OutboxStore.shared(appGroup: id) { return shared }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try OutboxStore(root: base.appendingPathComponent("Outbox", isDirectory: true))
    }
}
#endif
