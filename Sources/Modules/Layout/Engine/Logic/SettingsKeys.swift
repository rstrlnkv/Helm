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
    public static let onSpace = "onSpace"
    public static let onReturn = "onReturn"
    public static let onPunctuation = "onPunctuation"
    public static let exceptions = "exceptions"
    public static let appRules = "appRules"
    public static let autoReplace = "autoReplace"
    /// UI-only, but it lives here so the list is the whole list.
    public static let indicator = "indicator"
    public static let badgeStyle = "badgeStyle"
    public static let badgeSize = "badgeSize"
    /// The system input menu's «Show Input Source Name», for Helm's own
    /// indicator: the layout's name in the menu bar instead of its badge.
    public static let indicatorShowsName = "indicatorShowsName"
    public static let introSeen = "introSeen"
    /// What the hero was last showing. A view preference rather than a setting
    /// that changes what the module does — kept so the page opens where it was
    /// left, the way the sidebar width is.
    public static let heroPeriod = "heroPeriod"
    public static let heroMetric = "heroMetric"
}
