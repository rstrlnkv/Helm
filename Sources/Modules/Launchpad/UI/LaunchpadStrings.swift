import HelmUI

/// Localized strings for the Launchpad module. Name and summary are read at read time, so a language change shows.
enum LpStr {
    static var moduleName: String { L(.launchpad) }
    static var summary: String { L(.summary) }
    static var hide: String { L(.hide) }
    static var hiddenApps: String { L(.hiddenApps) }
    static var noApps: String { L(.noAppsToShow) }
    static var noMatch: String { L(.noAppMatches) }
    static var notSaved: String { L(.arrangementNotSaved) }
    static func appIsGone(_ name: String) -> String { L(.appIsGone(name)) }
    static func couldNotOpen(_ name: String) -> String { L(.appCouldNotBeOpened(name)) }
    /// A folder tile's name for VoiceOver: what it is called, then what it is.
    static func folder(_ name: String) -> String { L(.folderNamed(name), remembered: false) }
    /// "Show" and the app it is for, so a column of Show buttons is not a column of the same word.
    static func show(_ name: String) -> String { L(.showNamed(name), remembered: false) }
}
