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
    /// The ring's line under the figure while the walk runs: the kit's «Scanning…»,
    /// which the other scanning pages read.
    static var scanningNow: String { HelmWord.scanning }
    static var stop: String { HelmWord.stopScan }
    static var cancel: String { HelmWord.cancel }
    /// Drops the scan from the screen and goes back to the picker — and forgets the
    /// saved one, which is the only way out of a scan that should not have been
    /// there: without it the module reopens on its last scan at every launch.
    static var chooseAnother: String { L(.chooseAnother) }
    static var scanAgain: String { HelmWord.scanAgain }
    /// The tile's own door into the page. A verb and the module's name, because
    /// VoiceOver reads it out of context: «Open» alone answers nothing in a
    /// panel holding ten tiles.
    static var openTheModule: String { L(.openDisk) }

    static var free: String { L(.free) }
    static var moveToTrash: String { HelmWord.moveToTrash }
    /// "Basket" was the only place the English UI used the word: no visible
    /// label says it — the bar itself is headed "To remove".
    static var basketContents: String { HelmWord.showWhatIsMarkedForRemoval }
    /// `HelmBasket` in HelmUI — the same bar Duplicates draws, and both had
    /// these two lines built inside the view with a Latin middle dot and an
    /// ASCII colon whatever the language.
    static func basketLine(_ count: Int, _ size: String) -> String {
        HelmBasket.line(count: count, size: size)
    }
    static func basketItem(_ name: String, _ size: String) -> String {
        HelmBasket.item(name: name, size: size)
    }
    /// The name of the action **and its object**, which is the half that was
    /// missing: "Add" had no object, and the fix for that changed the verb only —
    /// so a screen reader still said the same four words once per row down a list
    /// of two hundred. The row's own name is the only part of this button that
    /// differs between rows, and it is what the person is listening for.
    ///
    /// One button, two meanings: the name of the action and its object, from
    /// the kit's `HelmBasket`, which Duplicates' rows read too.
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
    /// Takes the plan, not a count and a size the caller worked out for itself.
    ///
    /// The page had both to hand — `basket.count` and `basketBytes` — and they
    /// describe the basket, which for a cache row is one entry standing for the
    /// contents of a folder. Passing the question along is the same repair
    /// `VPNStr.secretNeedsAPress` made by construction: the sentence cannot name
    /// something other than what the button does, because it is handed nothing
    /// else to name.
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
    /// One word, and deliberately without the file count its siblings carry.
    /// Measured against the widest existing statement at `.caption`, "Остановлено
    /// — файлов: 263144" is 161 pt against a 122 pt budget — and the width the
    /// `showsScanStatement` threshold was measured for is that budget, so at
    /// windows just above it the line would arrive truncated. A warning with an
    /// ellipsis in it is a poor warning; the count moved to the hint, which has no
    /// width to answer to.
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
    /// which is when the file was last *written*; the row used to claim
    /// "Untouched for months", which is a statement about use. A Parallels
    /// image opened every morning and a film watched monthly are both written
    /// to by nobody, and both were listed as untouched. Nothing macOS hands a
    /// bulk directory read reports use, so the row says the date instead —
    /// which is also the reason it was previously missing.
    static func notModifiedSince(_ date: String) -> String {
        L(.notModifiedSince(date))
    }
    /// The same claim with no date to hang it on: advice restored from a saved
    /// scan that holds the verdict and not the date.
    static var notModifiedInMonths: String { L(.notModifiedInMonths) }
    /// Why a row is in the Advice list — and, for the size-and-age verdict, the
    /// date it was reached from. Here rather than in the view because it is a
    /// decision with three branches and one of them turns on whether there is a
    /// date at all, which is exactly the kind of thing a test should be able to
    /// ask about without rendering anything.
    static func adviceReason(_ advice: DiskAdvice) -> String {
        switch advice.kind {
        // A folder, whose own mtime says when something was last added to it
        // and nothing about what is inside. No date to offer, so no date.
        case .cache: adviceKindCache
        // Both file verdicts are dates — thirty days for a download, half a year
        // for a large file — and the download row offered the category word as
        // its whole evidence against a request to bin an 8 GB installer. Each
        // keeps its own fallback beside it, for advice cached by a build that
        // did not carry the date.
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
    static var back: String { HelmWord.back }
    static func liveCount(_ files: Int,
                          language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(files, language: language)
        return L(.liveCount(n), language: language)
    }
}
