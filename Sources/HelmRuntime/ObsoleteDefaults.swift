import Foundation

/// Keys written by features that no longer exist.
///
/// Removing the code that reads a setting does not remove the setting: the
/// value sits in the user's defaults forever, and the next person to read that
/// file cannot tell it from a live one. Cleared once at launch.
public enum ObsoleteDefaults {
    /// Namespaced, always — a purge must not be able to reach a key that isn't
    /// Helm's own.
    public static let retired = [
        // The panel's grid layout was removed; the list is the only layout.
        "module.app.panelLayout",
        // The Island module was reverted; its settings outlived it.
        "module.island.enabled",
        "module.island.shelfBookmarks",
        // Replaced by permissionAuditVersion, which re-arms after an update.
        "module.app.permissionAuditShown",
        // The panel's width was a setting for one night. 480 pt buys a third
        // column, and that is not a reason to ask.
        "module.app.panelWidth",
    ]

    public static func purge(from store: KeyValueStore) {
        for key in retired where store.object(forKey: key) != nil {
            store.set(nil, forKey: key)
        }
    }
}
