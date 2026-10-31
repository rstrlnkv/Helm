import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// Localized strings for the Uninstaller module.
enum UnStr {
    static var moduleName: String { L(.uninstaller) }
    static var summary: String { L(.removeAnAppWithAllOfItsFiles) }
    static var searchApps: String { L(.searchApps) }
    static var scanning: String { HelmWord.scanning }
    /// The same note when the Trash switch is on, because then the missing
    /// grant costs two things rather than one — and one grant deserves one
    /// notice, not a second row with its own Grant button saying the same.
    static var accessNeededWithWatch: String {
        L(.withoutFullDiskAccessOrTheTrash)
    }
    static var removalNeedsAccess: String { L(.withoutFullDiskAccess) }
    static var moveToTrash: String { HelmWord.moveToTrash }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }
    static var cancel: String { HelmWord.cancel }

    /// A leftover's kind and its size, as one caption.
    ///
    /// It was assembled in `OrphansView` as `"\(kind) · \(size)"`: the kind
    /// went through `L()` and the dot between them did not, so every language
    /// got a Latin middle dot. The same shape turned up in Duplicates' basket
    /// bar and VPN's connection row; `DupStr.found` sets `・` for Japanese and
    /// this now does too.
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
    /// The one standing line in that window, and the honest cost of offering
    /// now rather than waiting for the Trash to be emptied: the app is in the
    /// Trash, not gone, and it can come back without these.
    ///
    /// One sentence, because the first half of the two it used to be was the
    /// window's own title said again with more words. Naming the Trash carries
    /// the provenance, so nothing was lost with it. It stays literally true after
    /// the files are moved: they land beside the app, and restoring the app alone
    /// still does not bring them.
    static var trashOfferNote: String {
        L(.puttingTheAppBack)
    }
    /// What Cancel really means here, said outright. The record holds for as long
    /// as the app is in the Trash, and once the Trash is emptied there is nothing
    /// left to ask about — so "Later" would be a lie and «Отменить» is the system
    /// word for "make nothing happen", which this does not do.
    static var trashOfferKeep: String { L(.keepTheseFiles) }
    /// The switch on the Leftovers tab.
    ///
    /// Impersonal, like every other switch in Helm and — the reason that settles
    /// it — like Finder's own Trash settings in all eight languages.
    ///
    /// "when an app goes to the Trash" rather than a state: the person is being
    /// asked to turn on a thing that happens *at a moment*, and the moment is
    /// what they will recognise. The offer still covers apps already sitting
    /// there when the switch goes on — `setWatchingTrash` emits `trashChanged`
    /// for exactly that — but that is the caption's business, not the label's.
    static var watchTrash: String { L(.lookForLeftoversAutomatically) }
    /// What the feature does, and the one limit worth knowing before turning it
    /// on: the bundle in the Trash is what says whose files these are, so
    /// emptying the Trash first leaves nothing to identify them by.
    static var watchTrashNote: String {
        L(.helmShowsWhatItLeftBehind)
    }
    static var tabApps: String { HelmWord.apps }
    static var tabOrphans: String { HelmWord.leftovers }
    static var orphansIntro: String { L(.filesLeftByAppsNoLongerHere) }
    static var scanOrphans: String { L(.scanForLeftovers) }
    static var scanningOrphans: String { HelmWord.searching }
    static var noOrphans: String { HelmWord.noLeftoversFound }
    static var selectAll: String { HelmWord.selectAll }
    static var rescan: String { HelmWord.scanAgain }
    static func selectedSummary(_ n: Int, _ size: String,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.selectedSummary(String(n), size), language: language)
    }
    static var selectNone: String { HelmWord.clearSelection }
    /// At zero the button says only its verb: it is disabled with nothing
    /// checked, and a dimmed «Review 0» is a control naming a count of nothing.
    /// The count returns with the first tick.
    static func reviewCount(_ n: Int,
                            language: AppLanguage = AppLanguage.current) -> String {
        guard n > 0 else { return L(.review, language: language) }
        return L(.reviewCount(String(n)), language: language)
    }
    static var back: String { HelmWord.back }
    static var removing: String { L(.removing) }
    /// The caption under the first row of every review group. The last screen
    /// before deletion has no dialog after it, and it said nothing at all about
    /// the app — only about the files beside it.
    static var theAppItself: String { L(.theAppItself) }
    /// Word for word what Disk calls a row it may not remove (`DkStr.systemItem`).
    static var systemApp: String { HelmWord.system }
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
    static func movedToTrash(_ size: String) -> String { HelmBasket.movedToTrash(size) }
    static func movedWithFailures(_ size: String, _ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L(.movedWithFailures(size, items))
    }
    static var blockedByRunning: String { L(.quitTheRunningAppsFirst) }
    static func couldNotRemove(_ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L(.couldNotRemove(items))
    }
    /// The sentences moved to `TrashReasonText` when Disk and Duplicates
    /// started needing them too. Kept as a name the pages already call.
    static func failureReason(_ reason: TrashFailure.Reason) -> String {
        TrashReasonText.sentence(reason.rawValue)
    }
    /// Marks a leftover found by the app's display name rather than its
    /// bundle id, and it is not ticked by default.
    ///
    /// "by name" named the *method* and left the reader to work out what was
    /// wrong with it — and two translators drifted to a noun for a category
    /// («по названию», 名前一致), which is what an under-specified fragment does.
    /// The word this app already uses for the thing is a guess.
    static var matchedByName: String { L(.guess) }
    /// The message over an empty Apps tab, one per reason there is no list.
    ///
    /// Takes the language rather than reading `AppLanguage.current`: the suite
    /// runs in whatever language this machine is set to, so a sentence checked
    /// against `.current` is checked in one language eight times — and these
    /// two are compared against each other, which is a check that cannot fail
    /// when both sides move together.
    ///
    /// Exhaustive over the enum, with no `default`: a third reason would
    /// otherwise be drawn as one of these two, which is the defect
    /// `AppsEmpty.Reason` exists for.
    static func emptyMessage(_ nothing: AppsEmpty.Reason,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch nothing {
        case .noApps: return L(.noApplicationsFound, language: language)
        // A claim about the search field, which is on screen directly above this
        // message — not about the Mac.
        case .searchHidesAll: return L(.noApplicationsMatchThisSearch, language: language)
        }
    }
    static var openDiskAccess: String { HelmWord.openFullDiskAccess }
    /// `HelmUI`'s, because Leftovers' extension row draws the same label over the
    /// same call — it said «Manage…» there until the two were made one.
    static var openExtensions: String { HelmControlName.openExtensions }
    static var done: String { HelmWord.done }
    static var refreshList: String { HelmWord.refreshList }
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
