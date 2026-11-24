import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// Localized strings for the Uninstaller module.
enum UnStr {
    static var moduleName: String { L(.uninstaller) }
    static var summary: String { L(.removeAnAppWithAllOfItsFiles) }
    /// The same note when the Trash switch is on, naming both costs: one grant,
    /// one notice.
    static var accessNeededWithWatch: String {
        L(.withoutFullDiskAccessOrTheTrash)
    }
    static var removalNeedsAccess: String { L(.withoutFullDiskAccess) }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }

    /// A leftover's kind and its size, as one caption.
    ///
    /// One sentence, so the dot between is the language's too (`・` in Japanese,
    /// as `DupStr.found` sets it).
    static func kindAndSize(_ kind: LeftoverKind, _ size: String) -> String {
        let name = self.kind(kind)
        return L(.kindAndSize(name, size))
    }

    static func kind(_ k: LeftoverKind) -> String {
        switch k {
        case .appSupport: return L(.applicationSupport)
        case .caches: return L(.caches)
        case .preferences: return HelmWord.settingsFiles
        case .containers: return L(.containers)
        case .groupContainers: return L(.groupContainers)
        case .savedState: return L(.savedWindows)
        case .logs: return L(.logs)
        case .httpStorages: return L(.networkCacheAndCookies)
        case .webKit: return L(.websiteData)
        case .cookies: return L(.cookies)
        case .appScripts: return L(.applicationScripts)
        case .launchAgent: return HelmWord.launchAgents
        }
    }
    /// The Trash offer's window title. Not "Leftovers" — that is the module's
    /// own tab, for files whose app is already gone, and one English text means
    /// one thing.
    static var trashOfferTitle: String { L(.filesLeftInYourLibrary) }
    /// The one standing line in that window, the cost of offering now: the app
    /// is in the Trash, not gone, and it can come back without these. It stays
    /// true after the files are moved, since restoring the app alone does not
    /// bring them.
    static var trashOfferNote: String {
        L(.puttingTheAppBack)
    }
    /// What Cancel really means here, said outright: the record holds while the
    /// app is in the Trash, so "Later" would be a lie, and «Отменить» means "make
    /// nothing happen", which this does not do.
    static var trashOfferKeep: String { L(.keepTheseFiles) }
    /// The switch on the Leftovers tab.
    ///
    /// Impersonal, like every switch in Helm and like Finder's own Trash settings
    /// in all eight languages.
    ///
    /// "when an app goes to the Trash", a moment the person recognises, rather
    /// than a state. Apps already there are covered too (`setWatchingTrash`), but
    /// that is the caption's business.
    static var watchTrash: String { L(.lookForLeftoversAutomatically) }
    /// What the feature does, and the one limit worth knowing before turning it
    /// on: the bundle in the Trash is what says whose files these are, so
    /// emptying the Trash first leaves nothing to identify them by.
    static var watchTrashNote: String {
        L(.helmShowsWhatItLeftBehind)
    }
    static var orphansIntro: String { L(.filesLeftByAppsNoLongerHere) }
    static var scanOrphans: String { L(.scanForLeftovers) }
    static func selectedSummary(_ n: Int, _ size: String,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.selectedSummary(String(n), size), language: language)
    }
    /// At zero the button says only its verb: it is disabled with nothing
    /// checked, and a dimmed «Review 0» is a control naming a count of nothing.
    /// The count returns with the first tick.
    static func reviewCount(_ n: Int,
                            language: AppLanguage = AppLanguage.current) -> String {
        guard n > 0 else { return L(.review, language: language) }
        return L(.reviewCount(String(n)), language: language)
    }
    static var removing: String { L(.removing) }
    /// The caption under the first row of every review group: the last screen
    /// before deletion has no dialog after it, so it says the app goes too.
    static var theAppItself: String { L(.theAppItself) }
    static var systemApp: String { L(.systemApp) }
    static var noLeftoversForApp: String { L(.noExtraFilesFound) }
    static var runningBadge: String { L(.running) }
    static func runningWarning(_ names: String) -> String {
        L(.runningWarning(names))
    }
    static var forceQuitAndRemove: String { L(.forceQuitAndRemoveAnyway) }
    /// Where the files are going, not what the disk will gain. The button one
    /// click later says "Move to Trash", and `~/.Trash` is a folder on the same
    /// volume: nothing is free until somebody empties it.
    static func toTrash(_ size: String) -> String {
        L(.toTrash(size))
    }
    /// `HelmBasket.movedToTrash`: Disk, Duplicates and the Uninstaller end a removal on one sentence.
    static func movedWithFailures(_ size: String, _ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L(.movedWithFailures(size, items))
    }
    static var blockedByRunning: String { L(.quitTheRunningAppsFirst) }
    static func couldNotRemove(_ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L(.couldNotRemove(items))
    }
    /// The sentences are `TrashReasonText`'s, shared with Disk and Duplicates.
    static func failureReason(_ reason: TrashFailure.Reason) -> String {
        TrashReasonText.sentence(reason.rawValue)
    }
    /// Marks a leftover found by the app's display name rather than its
    /// bundle id, and it is not ticked by default.
    ///
    /// The word is "guess", what the app calls it elsewhere, not the method
    /// ("by name"), which left the reader to work out what was wrong with it.
    static var matchedByName: String { L(.guess) }
    /// The message over an empty Apps tab, one per reason there is no list.
    ///
    /// Takes the language rather than reading `AppLanguage.current`, so the
    /// eight tables can be checked from one machine.
    ///
    /// Exhaustive over the enum, with no `default`: a third reason would
    /// otherwise be drawn as one of these two (`AppsEmpty.Reason`).
    static func emptyMessage(_ nothing: AppsEmpty.Reason,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch nothing {
        case .noApps: return L(.noApplicationsFound, language: language)
        // A claim about the search field, which is on screen directly above this
        // message — not about the Mac.
        case .searchHidesAll: return L(.noApplicationsMatchThisSearch, language: language)
        }
    }
    /// The toolbar action's tooltip and VoiceOver name. Finder's own words for
    /// the same menu.
    static var sortBy: String { L(.sortBy) }
    /// Whole phrases and not «Name»: that key already names an Autopilot rule's
    /// field, «Size» its condition — one key, one meaning.
    static func sortName(_ order: AppSortOrder) -> String {
        switch order {
        case .name: return L(.sortByName)
        case .size: return L(.sortBySize)
        case .dateLastOpened: return L(.sortByDateLastOpened)
        }
    }
    /// The age is `HelmDates.age(_, style: .full)`.
    static func opened(_ age: String) -> String {
        L(.opened(age))
    }
    /// Spotlight has no date. Deliberately not «Never opened»: it is silent for
    /// an unindexed volume and for a fresh reindex as well.
    static var noRecordOfOpening: String { L(.noRecordOfOpening) }
    /// Nil while the first query is still out: the line reads as a count that
    /// has not arrived rather than a count of zero.
    static func appsCount(_ n: Int?) -> String {
        guard let n else { return L(.countingApps) }
        return Plural.apps(n, language: AppLanguage.current.rawValue)
    }
    static func appsCountSelected(_ n: Int?, _ chosen: Int, _ size: String) -> String {
        let apps = appsCount(n)
        return L(.appsCountSelected(apps, String(chosen), size))
    }
}
