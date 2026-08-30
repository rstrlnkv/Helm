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
        // The panel's three footer switches spent one unreleased build folded
        // into this. They are three settings again; `PanelFooterSetting.unfolded`
        // reads this key before the list reaches it, and
        // `AppSettings.migrateAndPurge` is one function for exactly that reason.
        "module.app.showPanelFooter",
        // Keyboard's three «when to fix» triggers. Space and punctuation
        // confirm a word and Return does not — which is what they were set to
        // anyway, and what keeps a chat from sending a typo.
        "module.layout.onSpace",
        "module.layout.onReturn",
        "module.layout.onPunctuation",
        // Keyboard's abbreviations. macOS ships the same thing in Text
        // Replacement and syncs it across the person's devices.
        "module.layout.autoReplace",
        // Keyboard's hero showed one figure at a time behind a glyph. It shows
        // both at once now, so there is nothing left to remember.
        "module.layout.heroMetric",
        // Keyboard's indicator had a menu-bar size of its own, beside the app's
        // `menuBarIconSize` in General — two items in one menu bar sized by two
        // settings, over a four-point range, with the indicator's own menu rows
        // ignoring both and drawing at `.small`.
        "module.layout.badgeSize",
    ]

    public static func purge(from store: KeyValueStore) {
        for key in retired where store.object(forKey: key) != nil {
            store.set(nil, forKey: key)
        }
    }
}
