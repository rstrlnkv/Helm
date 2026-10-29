import Foundation

/// The names the two halves of this module agree on.
///
/// Settings are the one place the UI and the engine touch without a compiler
/// between them: the page writes `"tapKey"` into the store, the engine reads
/// `"tapKey"` back out, and nothing checks that those are the same eleven
/// letters. Rename one side and the setting does not fail — it silently reverts
/// to its default, which is the kind of bug that ships.
///
/// This target is already a dependency of the UI target, so both can spell the
/// key once. Adding a setting means adding a case here first.
public enum LayoutKey {
    public static let automatic = "automatic"
    public static let audible = "audible"
    public static let fixCapitals = "fixCapitals"
    public static let tapKey = "tapKey"
    public static let exceptions = "exceptions"
    public static let appRules = "appRules"
    /// bundle id → input source id. The person's own binding, never learned.
    public static let appLayouts = "appLayouts"
    /// UI-only, but it lives here so the list is the whole list.
    public static let indicator = "indicator"
    public static let badgeStyle = "badgeStyle"
    /// The system input menu's «Show Input Source Name», for Helm's own
    /// indicator: the layout's name in the menu bar instead of its badge.
    public static let indicatorShowsName = "indicatorShowsName"
    public static let introSeen = "introSeen"
    /// What the hero was last showing. A view preference rather than a setting
    /// that changes what the module does — kept so the page opens where it was
    /// left, the way the sidebar width is.
    public static let heroPeriod = "heroPeriod"
}

/// The chord this module registers with the host, named once.
///
/// Two names, each read on both sides of a target boundary — the host
/// registering the shortcut and the page drawing the row for it. Neither
/// half is an error when the other changes: the slot name only has to *match*, so
/// a rename leaves the page asking `HotkeyStatus` about a binding nobody filed;
/// and the store prefix is where the recorded combination lives, so a rename
/// there means somebody's chord is read from keys nothing writes. Both fail the
/// same way — the row draws a shortcut and pressing it does nothing.
///
/// Beside `LayoutKey` because it is the same kind of fact.
public enum LayoutHotkey {
    /// The slot `HotkeyManager` files the binding under, which is this module's
    /// id and the verb it runs. Not stored anywhere: it only has to be one
    /// string in two targets.
    public static let fix = "\(LayoutEngine.moduleID).fix"

    /// Where the recorded combination is kept — `<prefix>KeyCode`,
    /// `<prefix>Modifiers`, `<prefix>Label` inside the module's own store.
    /// **Deployed stored data: this name never moves.** A new shortcut takes a
    /// new prefix instead.
    public static let storePrefix = "convertHotkey"
}
