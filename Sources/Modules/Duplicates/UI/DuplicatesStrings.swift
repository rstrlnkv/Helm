import Foundation
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine

/// Every user-visible string in the duplicate finder, in eight languages.
enum DupStr {
    static var chooseFolder: String { L(.chooseFolder) }
    static var chooseAnother: String { L(.chooseAnotherFolder) }
    static var search: String { L(.searchNow) }
    static var searchAgain: String { L(.searchAgain) }
    static var startHint: String { L(.pickAFolder) }
    /// The start screen with a folder already chosen: the toolbar shows it, so
    /// the sentence does not ask for one again.
    static var startHintWithFolder: String { L(.helmWillReadThisFolder) }
    static var needsAccess: String { L(.withoutFullDiskAccess) }
    static var stop: String { HelmWord.stopScan }
    /// "Basket" appears nowhere on screen in any language — the bar above these
    /// controls is headed "To remove".
    static var basketContents: String { HelmWord.showWhatIsMarkedForRemoval }
    /// `HelmBasket` in HelmUI: Disk draws the same bar, so its two lines are
    /// built in one place.
    static func basketLine(_ count: Int, _ size: String) -> String {
        HelmBasket.line(count: count, size: size)
    }
    static func basketItem(_ name: String, _ size: String) -> String {
        HelmBasket.item(name: name, size: size)
    }
    static var moveToTrash: String { HelmWord.moveToTrash }
    static var systemItem: String { HelmWord.system }
    static var reveal: String { HelmWord.showInFinder }
    static var quickLook: String { L(.quickLook) }
    /// `HelmBasket.movedToTrash`: Disk, Duplicates and the Uninstaller end a removal on one sentence; Leftovers counts the rows as well (`LfStr.movedToTrash`).
    static func movedToTrash(_ size: String) -> String {
        HelmBasket.movedToTrash(size)
    }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        // The size stays — how much is going is worth knowing — but the promise
        // that it will be freed does not: the Trash is on the same volume.
        HelmConfirm.trash(Plural.files(count, language: AppLanguage.current.rawValue), size)
    }
    static var moduleName: String { L(.duplicates) }
    static var summary: String { L(.filesThatExistMoreThanOnce) }
    /// Takes the language, as `none` below does and for the same reason:
    /// `busyLine` chooses between this and `progressLine`, and a choice checked
    /// only in the suite's own language is checked in one language eight times.
    static func searching(language: AppLanguage = AppLanguage.current) -> String {
        L(.readingFiles, language: language)
    }
    /// The one sentence a busy screen draws: the tick when there is one, the
    /// plain «reading» when there is not — true of a search and of a removal's
    /// verification alike, since both are files being read in full.
    ///
    /// A function rather than an expression inside the page: the page draws it
    /// in two places.
    static func busyLine(_ progress: DuplicateProgress?,
                         language: AppLanguage = AppLanguage.current) -> String {
        guard let progress, progress.candidates > 0 else {
            return searching(language: language)
        }
        return progressLine(progress.hashed, progress.candidates, language: language)
    }
    /// The button beside a running removal. Not `stop` — that key says «Stop
    /// scan», and this press must not read as one about the search.
    static var stopRemoval: String { L(.stopRemoval) }
    /// The named outcome of a stopped removal. What did move before the stop is
    /// the banner's to say; this sentence owns the other half — that from the
    /// stop on, nothing else went.
    static func removalStopped(language: AppLanguage = AppLanguage.current) -> String {
        L(.removalStopped, language: language)
    }
    /// The named outcome of a stopped search — drawn as the start screen's
    /// message, because a cancelled search lands on the start phase and the
    /// screen otherwise reads as if nothing had happened. It covers the engine
    /// giving up as well as the person pressing Stop: either way the folder
    /// was not read to the end, which is the half the person acts on.
    static func searchStopped(language: AppLanguage = AppLanguage.current) -> String {
        L(.searchStopped, language: language)
    }
    /// Both counts go through `Count` — the candidate total runs over every
    /// large file under the folder, which is six digits on a real library.
    static func progressLine(_ done: Int, _ total: Int,
                             language: AppLanguage = AppLanguage.current) -> String {
        let (a, b) = (Count(done, language: language), Count(total, language: language))
        return L(.progressLine(a, b), language: language)
    }
    /// Takes the language, as `found` above does and for the same reason: the
    /// suite runs in this machine's language, so a sentence that reads
    /// `AppLanguage.current` is checked in one language eight times. This one is
    /// compared against its two neighbours below, and a comparison where only
    /// one side moves is a check that cannot fail — measured: with the refusal
    /// folded back into this sentence, every language still read Russian here.
    static func none(language: AppLanguage = AppLanguage.current) -> String {
        L(.noDuplicatesHere, language: language)
    }
    /// The message over an empty result, one per reason there is no list.
    ///
    /// **The message, not a note under «No duplicates here».** A headline with a
    /// footnote invites the reader to trust the headline, and that headline is
    /// exactly the claim a walk that was refused cannot back — the same choice
    /// `LfStr.emptyMessage` records, and the same repair.
    ///
    /// Exhaustive over the enum, with no `default`: a fourth reason would
    /// otherwise be drawn as the all-clear, which is the defect the type exists
    /// for.
    static func emptyMessage(_ nothing: DuplicatesEmpty.Reason,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch nothing {
        case .nothingFound: return none(language: language)
        case .notEverythingRead(let count): return couldNotRead(count, language: language)
        case .librariesNotOpened: return librariesNotOpened(language: language)
        }
    }
    static func couldNotRead(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L(.couldNotRead(items), language: language)
    }
    /// No count, on purpose: the walk cannot see a library macOS already knows
    /// as a package, so any figure it quoted would be short — and a number that
    /// is known to be wrong is worse than the sentence without one.
    static func librariesNotOpened(language: AppLanguage = AppLanguage.current) -> String {
        L(.librariesNotOpened, language: language)
    }
    static var floorNote: String { L(.filesFromOneMB) }
    /// What the extra copies give back, not a promise about free space.
    /// An APFS clone, which is what Finder's Duplicate makes, shares its blocks
    /// with the original, and the copies go to the Trash on the same volume.
    /// `wasted` counts what the disk actually gives back — a cloned copy
    /// returns nothing — and the figure says so. It names the Trash: the copies land there first, and the space arrives when
    /// it is emptied, which is the rule Disk keeps too.
    /// Built from `onceEmptied` below rather than spelling the tail again —
    /// `VPNStr.secretNeedsAPress`'s construction: the total line and the group
    /// headers say the same sentence because it is the same sentence, not
    /// because somebody keeps two tables in step.
    static func found(_ groups: Int, _ wasted: String,
                      language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(groups, language: language)
        let tail = onceEmptied(wasted, language: language)
        return L(.found(n, tail), language: language)
    }
    /// «\(size) once the Trash is emptied» — the tail of `found` above, on its
    /// own for the group headers: each group says what removing its extras
    /// returns, through the same words as the page's total — two spellings of one
    /// tail is how `movedToTrash` drifted.
    static func onceEmptied(_ size: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L(.onceEmptied(size), language: language)
    }
    static var keep: String { L(.stays) }
    /// The badge on a row whose survivor the person chose. Two words in a pill,
    /// beside «stays» rather than instead of it — which of the two a group shows
    /// is the whole difference the badge exists to draw.
    static var yourChoice: String { L(.yourChoice) }
    /// The row's own way in, on the icon at its left, in its context menu and in
    /// its accessibility actions — one name for one act, three places.
    static var keepThisCopy: String { L(.keepThisCopy) }
    /// And the way back, in the header of a group that has been chosen.
    static var restoreRecommendation: String { L(.restoreTheRecommendation) }

    /// Why this group's first copy is the one that stays.
    ///
    /// Says what actually decided it, in every group's header, rather than one
    /// sentence for every rung.
    ///
    /// Exhaustive, with no `default`: a rung added to `KeepReason` is a build
    /// error here, not a header that quietly says the wrong rung.
    static func keptBecause(_ grounds: KeepGrounds,
                            language: AppLanguage = AppLanguage.current) -> String {
        switch grounds {
        // Not «by place», which is the policy's name: what the person sees is a
        // folder, and the tier is the thing being explained rather than a word
        // to reuse.
        case .rung(.place): return L(.keptByFolder, language: language)
        // Said as the absence it is. «Arrived first» is what this case would
        // borrow if the missing date were folded into the rung below it, and
        // nothing on this Mac knows when the kept copy arrived — which is the
        // whole reason it is the one that stays.
        case .rung(.undated): return L(.keptNoDateRecorded, language: language)
        case .rung(.date): return L(.keptArrivedFirst, language: language)
        // Said as the fact it is. «By depth» is the rule's word for it and means
        // nothing on a screen; the shorter path is what somebody can look at.
        case .rung(.depth): return L(.keptTheShorterPath, language: language)
        // A coin toss, and it has to look like one: two copies alike in every
        // way the rule can see were separated by the alphabet. «By name» sold
        // that tie-break as a criterion; «first alphabetically» says the coin
        // it actually is.
        case .rung(.name): return L(.keptFirstAlphabetically, language: language)
        case .byHand: return L(.keptYourChoice, language: language)
        }
    }
    /// One key used to label two different actions: a group button meaning
    /// "mark this group's extras" and a row checkbox meaning "mark this copy".
    /// One English text means one thing.
    static var markRow: String { L(.markForRemoval) }
    static var markGroupExtras: String { L(.markTheExtraCopies) }
    /// Not "Select all", which invites exactly the reading this module
    /// refuses. A control that lies about its effect on files is the failure
    /// this page is most exposed to.
    static var basketAllExtras: String { L(.markEveryExtraCopy) }
    /// **Not «Clear selection».** That key is Leftovers' and the Uninstaller's,
    /// where a checkbox is a selection; here a copy is *marked* for removal, and
    /// the module says «Mark…» everywhere else. Its own key pairs «Снять
    /// отметки» with the three «Отметить…» buttons. One English text, one meaning.
    static var clearBasket: String { L(.clearTheMarks) }

    // MARK: - What an extra copy is

    /// The label in front of the policy popup. Half a sentence, and the popup
    /// finishes it — a question with a title and a control under it takes four
    /// lines to say what one line says here.
    static var extraCopyIs: String { L(.anExtraCopyIs) }

    /// One policy, as the popup says it — the second half of the sentence above.
    ///
    /// Exhaustive over `KeepPolicy` with no `default`: a third belief would
    /// otherwise draw as an empty row in the popup that decides what Helm offers
    /// to delete.
    static func policyName(_ policy: KeepPolicy,
                           language: AppLanguage = AppLanguage.current) -> String {
        switch policy {
        case .byPlace: return theOneInTransit(language: language)
        case .byDate: return L(.theOneThatArrivedLater, language: language)
        }
    }

    /// «the one in “Downloads” or “Desktop”», with the folders named the way
    /// this Mac names them.
    ///
    /// **macOS spells its own folders**, and it is not a translation Helm gets
    /// to make: Finder says «Загрузки»,「デスクトップ」and, in Portuguese, `Mesa`
    /// — a ninth translation of a name the system already has is how one folder
    /// comes to have two names on one screen. The paths come from
    /// `TransitFolders.named`, so the sentence cannot describe a tier the rule
    /// no longer has.
    ///
    /// Quoted, because they are names: the alternative is declining them, and
    /// «в Загрузки» is what interpolating a nominative folder name into a
    /// Russian preposition produces. `Quoted` is the house's marks per language,
    /// French's unbreakable spaces and all.
    ///
    /// The names go in as arguments of the catalog's `theOneInTransit`, already
    /// quoted, so the word order around them is the catalog's.
    private static func theOneInTransit(language: AppLanguage) -> String {
        let folders = TransitFolders.named.map { path in
            SystemFolderNames.display(path: path, home: NSHomeDirectory(),
                                      language: language.rawValue)
                ?? (path as NSString).lastPathComponent
        }
        // A Mac that cannot say where its own Downloads folder is answers the
        // English word, which is what the path's last component would have said.
        let (downloads, desktop) = (folders.first ?? "Downloads",
                                    folders.dropFirst().first ?? "Desktop")
        let (dl, dk) = (Quoted(downloads, language: language), Quoted(desktop, language: language))
        return L(.theOneInTransit(dl, dk), language: language)
    }

    // MARK: - What the last press did to the marks

    /// Marks taken off copies that have just become the ones that stay.
    ///
    /// Label-then-count, the shape `ApStr.historyProblems` records: «Снято
    /// отметок: 2» makes the number a count rather than the subject of a verb,
    /// and the agreement question every Slavic and Romance language would
    /// otherwise ask disappears. No noun after the colon for the same reason —
    /// what was unmarked is on the screen the sentence is under.
    static func unmarkedSurvivors(_ count: Int,
                                  language: AppLanguage = AppLanguage.current) -> String {
        L(.unmarkedSurvivors(String(count)), language: language)
    }

    /// Copies «Mark every extra copy» passed over: paths outside what Helm may
    /// remove at all.
    ///
    /// Says what Helm may not do rather than what the file is — «System» is a
    /// label on a row, and this is a sentence about a press. The count carries
    /// its noun through `Plural`, because after the colon it is still a counted
    /// noun in six of the eight languages.
    static func skippedNotRemovable(_ count: Int,
                                    language: AppLanguage = AppLanguage.current) -> String {
        let files = Plural.files(count, language: language.rawValue)
        return L(.skippedNotRemovable(files), language: language)
    }
    static var cancel: String { HelmWord.cancel }
    static var close: String { HelmWord.close }
}
