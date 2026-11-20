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
    static var openLaunchpad: String { L(.openLaunchpad) }
    static var toggleLaunchpad: String { L(.toggleLaunchpad) }
    static var arrangement: String { L(.arrangement) }
    static var resetArrangement: String { L(.resetArrangement) }
    static var resetQuestion: String { L(.resetQuestion) }
    static var resetNote: String { L(.resetNote) }
    static var dockIcon: String { L(.dockIcon) }
    static var dockIconNote: String { L(.dockIconNote) }
    /// The draggable icon's name for VoiceOver: the helper as the Dock will call it, then what to do with it.
    static func dockIconNamed(_ name: String) -> String { L(.dockIconNamed(name), remembered: false) }
    /// "Show in Finder" and the helper it is for, so the button names its object.
    static func showNamedInFinder(_ name: String) -> String { L(.showNamedInFinder(name), remembered: false) }
    static var grid: String { L(.grid) }
    static var gridAutomatic: String { L(.gridAutomatic) }
    static var gridAutomaticNote: String { L(.gridAutomaticNote) }
    static var gridRows: String { L(.gridRows) }
    static var gridColumns: String { L(.gridColumns) }
    static var gridIconSize: String { L(.gridIconSize) }
    static var gridFitNote: String { L(.gridFitNote) }
    /// "80 pt": the number is a string, so a language's own digits are not this key's business.
    static func gridIconSizeValue(_ points: Int) -> String { L(.gridIconSizeValue("\(points)"), remembered: false) }
    static var gridReset: String { L(.gridReset) }
    /// The reset row's title: what it resets, so the row does not repeat the section's header.
    static var gridResetTitle: String { L(.gridResetTitle) }
    /// The reset row's note: the four values it puts back.
    static var gridResetNote: String { L(.gridResetNote) }
    /// The reset button's name for VoiceOver: what it resets, since the visible word does not say.
    static var gridResetNamed: String { L(.gridResetNamed) }
    static var pinchTitle: String { L(.pinchTitle) }
    static var pinchNote: String { L(.pinchNote) }
    static var pinchSystemTitle: String { L(.pinchSystemTitle) }
    static var pinchSystemStillOn: String { L(.pinchSystemStillOn) }
    static var pinchOpenTrackpadSettings: String { L(.pinchOpenTrackpadSettings) }
    /// The state line under the switch, one sentence for each thing the watch can be.
    static func text(of state: PinchState) -> String? {
        switch state {
        case .off: nil
        case .watching: L(.pinchWatching)
        case .noTrackpad: L(.pinchNoTrackpad)
        case .unavailable: L(.pinchUnavailable)
        }
    }
    static var noHiddenApps: String { L(.noHiddenApps) }
    /// "Page 2 of 5" for a page dot; the numbers are strings, so a language's own digits and grouping are not this key's business.
    static func pageNumber(_ page: Int, of count: Int) -> String { L(.pageNumber("\(page)", "\(count)"), remembered: false) }
    /// What the last thing that did not go through says, for the window and for the page.
    static func text(of notice: LaunchNotice) -> String {
        switch notice {
        case .gone(let name): appIsGone(name)
        case .couldNotOpen(let name): couldNotOpen(name)
        case .notSaved: notSaved
        }
    }
    static func appIsGone(_ name: String) -> String { L(.appIsGone(name)) }
    static func couldNotOpen(_ name: String) -> String { L(.appCouldNotBeOpened(name)) }
    /// A folder tile's name for VoiceOver: what it is called, then what it is.
    static func folder(_ name: String) -> String { L(.folderNamed(name), remembered: false) }
    /// The folder card's name field, for VoiceOver.
    static var folderNameField: String { L(.folderNameField) }
    /// "Show" and the app it is for, so a column of Show buttons is not a column of the same word.
    static func show(_ name: String) -> String { L(.showNamed(name), remembered: false) }
}
