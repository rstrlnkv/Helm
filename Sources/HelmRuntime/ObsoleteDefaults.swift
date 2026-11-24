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
        // The panel: one layout, one width, one tab face.
        "module.app.panelLayout",
        // The Island module's settings.
        "module.island.enabled",
        "module.island.shelfBookmarks",
        // Superseded by permissionAuditVersion, which re-arms after an update.
        "module.app.permissionAuditShown",
        "module.app.panelWidth",
        // Three footer switches, not one.
        "module.app.showPanelFooter",
        // Keyboard: space and punctuation confirm a word and Return does not,
        // so a chat never sends a typo; abbreviations are macOS's Text
        // Replacement; the hero shows both figures; the indicator follows the
        // app's `menuBarIconSize`.
        "module.layout.onSpace",
        "module.layout.onReturn",
        "module.layout.onPunctuation",
        "module.layout.autoReplace",
        "module.layout.heroMetric",
        "module.layout.badgeSize",
        "module.app.tabLabelStyle",
        // `HelmIconPlate` has one look.
        "module.app.sidebarStyle",
    ]

    public static func purge(from store: KeyValueStore) {
        for key in retired where store.object(forKey: key) != nil {
            store.set(nil, forKey: key)
        }
    }
}
