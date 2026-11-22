import HelmUI

/// Localized strings for the Launchpad module. Name and summary are read at read time, so a language change shows.
enum LpStr {
    static var moduleName: String { L(.launchpad) }
    static var summary: String { L(.summary) }
    static var hide: String { L(.hide) }
    /// The app menu's second file row; "Show in Finder" is the kit's (`HelmWord.showInFinder`).
    static var copyPath: String { L(.copyPath) }
    /// An app's name for VoiceOver while it carries the "new" dot: a full key, so each language has its own separator.
    static func appIsNew(_ name: String) -> String { L(.appIsNew(name), remembered: false) }
    static var showAppNames: String { L(.showAppNames) }
    /// The folder tile's menu items: the size it can be given.
    static var enlargeFolder: String { L(.enlargeFolder) }
    static var shrinkFolder: String { L(.shrinkFolder) }
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
    /// The reset row's note: the five values it puts back.
    static var gridResetNote: String { L(.gridResetNote) }
    /// The reset button's name for VoiceOver: what it resets, since the visible word does not say.
    static var gridResetNamed: String { L(.gridResetNamed) }
    static var moveToCategory: String { L(.moveToCategory) }
    static var ownCategory: String { L(.ownCategory) }
    static func movedApps(_ count: Int) -> String { L(.movedApps("\(count)"), remembered: false) }
    static var returnAllMoved: String { L(.returnAllMoved) }
    static var returnAllMovedNamed: String { L(.returnAllMovedNamed) }
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

    /// The window's switch: its second tab (the first is the kit's `HelmWord.apps`), and the block that gathers what is new.
    static var categories: String { L(.categories) }
    static var launchCountsTitle: String { L(.launchCountsTitle) }
    static var launchCountsNote: String { L(.launchCountsNote) }
    /// The reset button's title: what it resets, in full (the host's bare "Reset" is another key).
    static var resetLaunchCountsNamed: String { L(.resetLaunchCountsNamed) }
    /// A category block's name for VoiceOver: what it is called, then what it is.
    static func category(_ name: String) -> String { L(.categoryNamed(name), remembered: false) }

    /// The locked block's name, and its name for VoiceOver (a full key of its own: what it is, then that it is shut).
    static var hiddenBlock: String { L(.hiddenBlock) }
    static var hiddenLocked: String { L(.hiddenLocked) }
    /// What follows "Helm is trying to" in the system's dialog; a phrase, as the system asks for one.
    static var hiddenAuthReason: String { L(.hiddenAuthReason) }
    static func hiddenAppsCount(_ count: Int) -> String { L(.hiddenAppsCount("\(count)"), remembered: false) }
    static var hiddenUnavailable: String { L(.hiddenUnavailable) }
    /// The settings page's Show button, named for what it shows (the list's own Show buttons name an app).
    static var showHiddenNamed: String { L(.showHiddenNamed) }

    /// A tile's place by VoiceOver: one full key for each action, no verb interpolated.
    static var moveEarlier: String { L(.moveEarlier) }
    static var moveLater: String { L(.moveLater) }
    static var moveToPreviousPage: String { L(.moveToPreviousPage) }
    static var moveToNextPage: String { L(.moveToNextPage) }
    static var makeFolderWithPrevious: String { L(.makeFolderWithPrevious) }
    static var makeFolderWithNext: String { L(.makeFolderWithNext) }
    static var addToPreviousFolder: String { L(.addToPreviousFolder) }
    static var addToNextFolder: String { L(.addToNextFolder) }
    static var takeOutOfFolder: String { L(.takeOutOfFolder) }
    /// What is said after a move: the numbers are strings, so a language's own digits and grouping are not these keys' business.
    static func announceMoved(_ name: String, place: Int, of count: Int, page: Int, of pages: Int) -> String {
        L(.announceMoved(name, "\(place)", "\(count)", "\(page)", "\(pages)"), remembered: false)
    }
    static func announceFolderMade(_ name: String, _ other: String) -> String { L(.announceFolderMade(name, other), remembered: false) }
    static func announceAddedToFolder(_ name: String, _ folder: String) -> String { L(.announceAddedToFolder(name, folder), remembered: false) }
    static func announceTakenOut(_ name: String, _ folder: String, place: Int, page: Int) -> String {
        L(.announceTakenOut(name, folder, "\(place)", "\(page)"), remembered: false)
    }
    static func announceCannotMove(_ name: String) -> String { L(.announceCannotMove(name), remembered: false) }
}
