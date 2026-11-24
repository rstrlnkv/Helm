import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

enum DkStr {
    /// The display name only — the module id stays `disk`, or every stored
    /// setting keyed to it would be orphaned.
    static var moduleName: String { L(.disk) }
    static var summary: String { L(.summary) }
    static var scanFolder: String { L(.scanAFolder) }
    static var scanning: String { L(.scanning) }
    /// Drops the scan from the screen and goes back to the picker, and forgets the
    /// saved one: the module otherwise reopens on its last scan at every launch.
    static var chooseAnother: String { L(.chooseAnother) }
    /// The tile's own door into the page. A verb and the module's name, because
    /// VoiceOver reads it out of context: «Open» alone answers nothing in a
    /// panel holding ten tiles.
    static var openTheModule: String { L(.openDisk) }

    static var free: String { L(.free) }
    /// «X free» as one sentence, so a language puts the figure where it belongs.
    static func freeAmount(_ bytes: Int) -> String { L(.freeAmount(Bytes(bytes))) }
    static func usedOfTotal(_ volume: VolumeInfo) -> String {
        Bytes(volume.usedBytes) + " / " + Bytes(volume.totalBytes)
    }
    /// `HelmBasket` in HelmUI, the same bar Duplicates draws, so the punctuation
    /// follows the language.
    static func basketLine(_ count: Int, _ size: String) -> String {
        HelmBasket.line(count: count, size: size)
    }
    static func basketItem(_ name: String, _ size: String) -> String {
        HelmBasket.item(name: name, size: size)
    }
    /// The name of the action **and its object**, from the kit's `HelmBasket`,
    /// which Duplicates' rows read too. The row's own name is the only part of
    /// this button that differs between rows, and it is what a screen-reader
    /// user is listening for.
    static func basketAction(name: String, basketed: Bool,
                             language: AppLanguage = AppLanguage.current) -> String {
        basketed ? HelmBasket.unmark(name: name, language: language)
                 : HelmBasket.mark(name: name, language: language)
    }
    static var systemItem: String { L(.systemItem) }
    static var emptyFolder: String { L(.nothingInThisFolder) }
    static var noAccess: String { L(.noAccess) }
    static var scanNeedsAccess: String { L(.scanNeedsFullDiskAccess) }
    static var startHint: String { L(.pickAVolumeOrScanAnyFolder) }
    /// The count goes through `Count`: a scan of `/` reports seven digits, and
    /// seven ungrouped digits are read by counting them. Same in the two
    /// statements below.
    static func scannedIn(_ files: Int, _ seconds: String,
                          language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(files, language: language)
        return L(.scannedIn(n, seconds), language: language)
    }
    /// `HelmBasket.movedToTrash`: Disk, Duplicates and the Uninstaller end a removal on one sentence; Leftovers counts the rows as well (`LfStr.movedToTrash`).
    static func movedToTrash(_ size: String) -> String {
        HelmBasket.movedToTrash(size)
    }
    /// Takes the plan, not a count and a size the caller worked out for itself:
    /// the basket's figures describe a cache row as one entry, and a sentence
    /// handed only the plan cannot name something other than what the button does.
    static func confirmTrash(_ question: DiskRemovalPlan.Question) -> String {
        HelmConfirm.trash(Plural.items(question.count, language: AppLanguage.current.rawValue),
                          Bytes(question.bytes))
    }
    static func measured(_ ago: String) -> String {
        L(.measured(ago))
    }
    /// The third thing the ring can be showing, beside a fresh measurement and a
    /// memory of one: a walk that was stopped.
    ///
    /// One word, without the file count its siblings carry: with the count the
    /// Russian line overruns the width the `showsScanStatement` threshold was
    /// measured for, and a warning should not be truncated. The count is in the
    /// hint, which has no width to answer to.
    static var stopped: String { HelmWord.stopped }
    /// Why that line matters, and how far the walk got. `TreeBuilder` charges a
    /// directory as its files are found, so every folder in a stopped tree shows a
    /// floor and not a total — which is the number somebody would be deciding to
    /// delete on. Interpolated, so it is a catalog key with the count as its argument:
    /// the lookup would otherwise be asked for a key with the count already in it.
    static func stoppedHint(_ files: Int,
                            language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(files, language: language)
        return L(.stoppedHint(n), language: language)
    }
    static var advice: String { L(.recommendations) }
    static var adviceHint: String { L(.whatCouldBeDeleted) }
    static var adviceKindCache: String { L(.cacheAppsRebuildIt) }
    static var adviceKindOldDownload: String { L(.oldDownload) }
    /// What the attribute actually says. The scanner reads `ATTR_CMN_MODTIME`,
    /// when the file was last *written*, which says nothing about use: a film
    /// watched monthly is written by nobody. Nothing a bulk directory read
    /// returns reports use, so the row says the date.
    static func notModifiedSince(_ date: String) -> String {
        L(.notModifiedSince(date))
    }
    /// The same claim with no date to hang it on: advice restored from a saved
    /// scan that holds the verdict and not the date.
    static var notModifiedInMonths: String { L(.notModifiedInMonths) }
    /// Why a row is in the Advice list, and for the size-and-age verdict the
    /// date it was reached from. Here rather than in the view, so a test can ask
    /// about its three branches without rendering anything.
    static func adviceReason(_ advice: DiskAdvice) -> String {
        switch advice.kind {
        // A folder, whose own mtime says when something was last added to it
        // and nothing about what is inside. No date to offer, so no date.
        case .cache: adviceKindCache
        // Both file verdicts are dates (thirty days for a download, half a year
        // for a large file), so each shows its date. Each keeps a fallback for
        // saved advice that carries no date.
        case .oldDownload: dated(advice.modified) ?? adviceKindOldDownload
        case .largeOld: dated(advice.modified) ?? notModifiedInMonths
        }
    }

    /// The day, not the minute: these judgements are measured in months, and
    /// "19:00" is noise on a file nobody has touched since March. nil where
    /// there is no date to say anything about.
    private static func dated(_ modified: TimeInterval?) -> String? {
        modified.map { notModifiedSince(HelmDates.day(Date(timeIntervalSince1970: $0))) }
    }
    static var otherItems: String { L(.smallerItems) }
    static var ringMap: String { L(.diskMap) }
    static var openFolder: String { L(.lookInside) }
    static func ringShare(_ name: String, _ size: String, _ percent: Int) -> String {
        L(.ringShare(name, size, "\(percent)"))
    }
    static func liveCount(_ files: Int,
                          language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(files, language: language)
        return L(.liveCount(n), language: language)
    }
}
