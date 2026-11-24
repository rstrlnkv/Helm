import Foundation
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine

/// Every user-visible string in the autopilot module, in eight languages.
///
/// Named for what it does: the module keeps a folder on course without hands on
/// it, the instrument Helm is named after one step further along.
enum ApStr {
    static var moduleName: String { L(.autopilot) }
    static var summary: String { L(.foldersThatKeepThemselvesInOrder) }
    static var startHint: String { L(.pointHelmAtAFolderAnd) }
    static var needsAccess: String { L(.withoutFullDiskAccessAProtected) }
    /// `WatchScope`'s refusal, which is positional: `~/Library`, a whole volume,
    /// anything outside the home. Its own sentence, never `needsAccess` — that
    /// one names a grant, and no grant changes a position.
    static var folderOutOfReach: String { L(.aRuleCanWatchFoldersInside) }

    // MARK: - Rules that are not Helm's to run

    /// **Two sentences for two states, and the split is the point.** The rules
    /// being unreadable and the rules being somebody else's leave the same empty
    /// folder list behind, and a person can do something about only one of them:
    /// a locked keychain is waited out, a rewritten plist is not.
    static var rulesTampered: String { L(.theRulesStoredOnThisMac) }
    static var rulesUnreadable: String { L(.helmCannotReadTheKeyIts) }
    /// A record that is not a rule list at all, with the seal fitting: not the key
    /// (`rulesUnreadable`) and not somebody else's (`rulesTampered`).
    static var rulesNotRead: String { L(.helmCouldNotReadTheStored) }
    /// The verb beside the first of those, and the only thing a refused page may
    /// send. It says what it does — the rules go, and the folder list starts
    /// again — rather than «OK».
    static var discardRules: String { L(.discardAndStartAgain) }

    /// What each of the three deleting gestures asks before it acts, and the verb
    /// its destructive button carries — the words the gesture already wears.
    static func discardQuestion(_ what: AutopilotViewModel.Discard) -> String {
        switch what {
        case .rules: L(.discardTheStoredRulesIncludingAny)
        case .history: L(.clearTheRecordOfWhatAutopilot)
        case .refusedHistory: L(.clearTheUnreadableRecordOfWhat)
        }
    }

    static func discardVerb(_ what: AutopilotViewModel.Discard) -> String {
        switch what {
        case .rules: discardRules
        case .history: HelmWord.clear
        case .refusedHistory: discardHistory
        }
    }

    // MARK: - Folders

    static var addFolder: String { L(.addFolder) }
    /// The folder header's switch, which carries no words on screen. The name
    /// says what the switch does and the path beside it says which folder.
    static var watchFolder: String { L(.watchThisFolder) }
    static var removeFolder: String { L(.stopWatching) }
    static var runNow: String { L(.runNow) }
    static var noRules: String { L(.noRulesYet) }
    /// Under a rule this build cannot read, which a newer Helm wrote: said beside it
    /// because the rule runs nowhere and has no switch to say so.
    static var newerHelmRule: String { L(.createdInANewerVersionOf) }
    /// Beside the path of a folder that is gone from the list but whose unapplied
    /// rules are kept.
    static var folderRemoved: String { L(.folderRemoved) }
    static var depth: String { L(.includeSubfolders) }

    /// **What a switch that says «on» is not saying.** A renamed folder, a folder
    /// behind Full Disk Access and an empty one are kept apart because a person
    /// does something different about each: point the rule elsewhere, grant the
    /// permission, or nothing. Each takes the language, so a test reads all eight.
    static func folderMissing(language: AppLanguage = AppLanguage.current) -> String {
        L(.thisFolderIsNoLongerThere, language: language)
    }

    static func folderUnreadable(language: AppLanguage = AppLanguage.current) -> String {
        HelmWord.cannotReadThisFolder(language: language)
    }

    /// The hourly sweep still runs, which is why this says what stopped rather
    /// than «this folder is not being tidied».
    static func notWatching(language: AppLanguage = AppLanguage.current) -> String {
        L(.changesHereAreNotBeingNoticed, language: language)
    }

    // MARK: - Rules

    static var newRule: String { L(.newRule) }
    static var untitledRule: String { L(.untitledRule) }
    static var ruleName: String { L(.name) }
    static var matchAll: String { L(.allOf) }
    static var matchAny: String { L(.anyOf) }
    static var whenLabel: String { L(.when) }
    static var thenLabel: String { L(.then) }
    static var addCondition: String { L(.addCondition) }
    static var firstMatchNote: String { L(.rulesRunTopToBottomAnd) }

    // MARK: - Rules somebody can have without writing one

    /// The menu that opens a starting rule, on the empty page and beside «Add
    /// folder…» — drawn only where there are no rules, which is what makes the
    /// words true. The tour's step has its own (`tourOffer`).
    static var welcomeOffer: String { L(.showTheRulesToStartWith) }

    /// The tour's button on Autopilot's step, not the menu above: the tour cannot
    /// read the rules, and the starting rules are on the page only while there
    /// are none, so this one says only where it goes.
    static var tourOffer: String { L(.openAutopilot) }

    /// The five names, the only translated part of a preset; what each *does* is
    /// `RuleSummary.describe(rule)`, built from the rule itself. Exhaustive over
    /// the engine's `PresetKind`: a sixth preset does not build until it has a
    /// name in eight languages.
    static func presetName(_ kind: PresetKind,
                           language: AppLanguage = AppLanguage.current) -> String {
        switch kind {
        case .screenshots: L(.screenshotsIntoTheirOwnFolder, language: language)
        case .downloadsByKind: L(.downloadsSortedByKind, language: language)
        case .oldInstallers: L(.oldInstallersToTheTrash, language: language)
        case .largeDownloads: L(.aTagOnBigDownloads, language: language)
        case .desktopByMonth: L(.desktopSortedByMonth, language: language)
        }
    }

    /// What a preset is called over a folder that is not its own.
    ///
    /// Two of the five names carry a folder word, and a «Downloads sorted by
    /// kind» over Pictures is a name that lies, so those two are built from the
    /// folder's display name. **Not a template over the five names above**: a
    /// name like «Téléchargements triés par type» agrees in gender with its
    /// folder, and the two that take any folder put it first and follow it with a
    /// phrase that agrees with nothing — a noun after a colon or a dash in
    /// Russian, Spanish, French and Portuguese, and a participle or a particle
    /// with neither in English, German, Japanese and Chinese. The other three
    /// read the same anywhere and are returned as they are.
    ///
    /// Two keys of the module's catalog, one template each; French takes an
    /// unbreakable space before its colon.
    static func presetName(_ kind: PresetKind, inFolder folder: String,
                           language: AppLanguage = AppLanguage.current) -> String {
        switch kind {
        case .downloadsByKind:
            L(.presetNameByKind(folder), language: language)
        case .desktopByMonth:
            L(.presetNameByMonth(folder), language: language)
        case .screenshots, .oldInstallers, .largeDownloads:
            presetName(kind, language: language)
        }
    }

    // MARK: - Dry run

    static var dryRun: String { L(.whatWouldHappen) }
    /// Under the folder line of a preset's editor, only while Done is followed by
    /// a sweep — `AutopilotViewModel.sweepsAfterSaving` decides both.
    static var savingStartsTheWatch: String { L(.onceSavedHelmWatchesThisFolder) }
    static var dryRunNote: String { L(.aRuleIsADecisionMade) }
    static var nothingWouldHappen: String { L(.nothingInThisFolderMatchesYet) }
    /// The heading over the rows this rule does not get. The dry run is of the
    /// whole folder, first match wins, so without it a file another rule takes
    /// reads as this rule's work. A whole sentence, not a word per row: the rows
    /// carry the rule's own name, and a name is not a claim.
    static var takenByAnotherRule: String { L(.anotherRuleTakesTheseFiles) }
    static var enableRule: String { L(.turnTheRuleOn) }
    /// **What the dry run above it is not showing**: a folder watched with
    /// subfolders hands every rule in it the whole tree, a setting of the
    /// person's that a preset does not change.
    static var folderIncludesSubfolders: String { L(.subfoldersAreIncludedForThisFolder) }
    /// What a Run now did — and, when there is one, what it did not do.
    ///
    /// **«Acted on 0 of 3» is also what a refusal on every file looks like**, so
    /// the sentence carries `refused` and `failed` as well.
    ///
    /// The two halves are joined rather than rewritten: `historyProblems` already
    /// says the second one in eight languages, with the colon-before-count that
    /// keeps the agreement right. The language is a parameter, as for
    /// `HelmConfirm.trash`, so a test checks all eight rather than this Mac's.
    static func swept(_ acted: Int, _ examined: Int, notCompleted: Int = 0,
                      language: AppLanguage = AppLanguage.current) -> String {
        let sentence = L(.swept(String(acted), String(examined)), language: language)
        guard notCompleted > 0 else { return sentence }
        return sentence + " · " + historyProblems(notCompleted, language: language)
    }

    // MARK: - Fields

    static var fieldName: String { L(.fullName) }
    /// The name with the extension taken off. Sits next to "Full name" rather
    /// than replacing it: a rule written against the full name is somebody's
    /// working rule, and changing what it means would break it in silence.
    static var fieldBaseName: String { L(.nameWithoutExtension) }
    static var fieldExtension: String { L(.fileExtension) }
    static var fieldKind: String { L(.kind) }
    static var fieldSize: String { L(.size) }
    static var fieldDateAdded: String { L(.dateAdded) }
    static var fieldDateModified: String { L(.dateModified) }
    static var fieldSource: String { L(.downloadedFrom) }
    static var fieldTag: String { L(.tag) }

    static var comparisonIs: String { L(.isExactly) }
    static var comparisonContains: String { L(.contains) }
    static var comparisonBegins: String { L(.beginsWith) }
    static var comparisonEnds: String { L(.endsWith) }
    static var comparisonLarger: String { L(.largerThan) }
    static var comparisonSmaller: String { L(.smallerThan) }
    static var comparisonOlder: String { L(.olderThan) }
    static var comparisonNewer: String { L(.newerThan) }
    static var unitMegabytes: String { L(.megabytesUnit) }
    /// The word, agreeing with the number in the field beside it: the field
    /// holds a number, so the word counts with it.
    ///
    /// Both of these stand after «старше» or «новее», which govern the
    /// genitive, so the agreement is `DayUnit`'s rather than `Plural`'s: the
    /// count's own «1 день» / «2 дня» is the wrong case in this position.
    static func unitDays(for count: Double) -> String {
        DayUnit.wordAfterComparison(count, language: AppLanguage.current.rawValue)
    }

    /// Composed with the number rather than glued to it: a bare word after a
    /// numeral gives «1 дней» and «22 дней» in Russian, and "1 days" in English.
    static func days(_ count: Double) -> String {
        DayUnit.afterComparison(count, language: AppLanguage.current.rawValue)
    }

    static func kindName(_ kind: FileKind) -> String {
        switch kind {
        case .image: L(.image)
        case .document: L(.document)
        case .archive: L(.archive)
        case .video: HelmWord.video
        case .audio: L(.audio)
        case .folder: L(.folder)
        case .other: L(.other)
        }
    }

    // MARK: - Actions

    static var actionMove: String { L(.moveToFolder) }
    static var actionSort: String { L(.sortIntoSubfolder) }
    static var actionTag: String { L(.addTag) }
    static var schemeKind: String { L(.byKind) }
    static var schemeMonth: String { L(.byMonth) }
    static var patternHint: String { L(.nameDateAndCounterAreReplaced) }

    // MARK: - Common

    static var delete: String { L(.delete) }

    // MARK: - Names for controls that carry none on screen

    /// A rule reads as a sentence built from pickers and fields whose meaning
    /// comes from their place in the row; read aloud it would be "pop up button,
    /// pop up button, text field", so each control carries a name. Kept short,
    /// because VoiceOver reads the name before every value.
    static var a11yField: String { L(.whatToCheck) }
    static var a11yComparison: String { L(.howToCompare) }
    static var a11yValue: String { L(.valueToMatch) }
    static var a11yExtensions: String { L(.extensionsSeparatedByCommas) }
    static var a11yDays: String { L(.numberOfDays) }
    static var a11yMegabytes: String { L(.sizeInMegabytes) }
    static var a11yHost: String { L(.siteTheFileCameFrom) }
    static var a11yTagValue: String { L(.tagName) }
    static var a11yAction: String { L(.whatToDo) }
    static var a11yScheme: String { L(.howToSort) }
    static var a11yPattern: String { L(.namePattern) }
    static var a11yMatch: String { L(.whichConditionsMustMatch) }

    // MARK: - What it did

    static var historyTitle: String { L(.last30Days) }

    /// **Why the record is empty: three states with three different next steps**:
    /// no watched folder, every rule switched off, a running rule that found
    /// nothing. Exhaustive, so a fourth reason needs a sentence to build.
    static func historyEmpty(_ reason: HistoryEmpty.Reason,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch reason {
        case .noFolders:
            L(.nothingIsBeingWatchedYetSo, language: language)
        case .everyRuleOff:
            L(.everyRuleIsSwitchedOffSo, language: language)
        case .nothingYet:
            L(.nothingYetAFileThatArrives, language: language)
        }
    }
    /// Refusals and failures counted together: both mean a file the rule meant
    /// to act on is still sitting where it was.
    static func historyProblems(_ count: Int,
                                language: AppLanguage = AppLanguage.current) -> String {
        // Written as label-then-count on purpose. "2 не прошло" needs "прошли"
        // for two through four in Russian, and the same trap waits in every
        // language that agrees a verb with a numeral; a colon makes the number
        // a count rather than a subject and the agreement question disappears.
        L(.historyProblems(String(count)), language: language)
    }

    /// The verb for one row. Past tense, because the row is a record of
    /// something that already happened — the rule editor's list says "Move",
    /// this says "moved", and the difference is the whole point of the section.
    static func historyVerb(_ kind: ActionRecord.Kind) -> String {
        switch kind {
        case .moved: L(.movedTo)
        case .renamed: L(.renamedTo)
        // A past participle in every language. Not German «Tag», the word for
        // *day* that the same column prints («älter als 30 Tage»), and not a
        // capitalised noun such as French «Étiquette» among lowercase verbs.
        case .tagged: L(.tagged)
        case .trashed: L(.movedToTrash)
        case .refused: L(.refused)
        case .failed: L(.failed)
        }
    }

    /// One history row's second half: the verb and its detail as one key per
    /// kind, so each language places the detail itself. "trashed" and an empty
    /// detail stay the bare verb. A refusal is the exception: its detail is the
    /// reason's rawValue — stored data, not words — so it is read back into the
    /// enum and spoken whole; a detail no current reason claims (a record a
    /// newer Helm wrote) keeps the verb and the value rather than falling silent.
    static func historyDetail(_ record: ActionRecord) -> String {
        if record.kind == .refused,
           let reason = RuleOutcome.Refusal(rawValue: record.detail) {
            return historyRefusal(reason)
        }
        let detail = record.detail
        guard !detail.isEmpty else { return historyVerb(record.kind) }
        switch record.kind {
        case .moved: return L(.historyMovedTo(detail))
        case .renamed: return L(.historyRenamedTo(detail))
        case .tagged: return L(.historyTagged(detail))
        case .failed: return L(.historyFailed(detail))
        case .refused: return L(.historyRefused(detail))
        case .trashed: return historyVerb(.trashed)
        }
    }

    // MARK: - Putting it back

    /// The item on a row and the button on a pass's header.
    static var putBack: String { L(.putBack) }

    /// The button over a pass. The count is what could actually go back, which
    /// is what makes it a promise rather than an intention.
    static func putBackFiles(_ count: Int,
                             language: AppLanguage = AppLanguage.current) -> String {
        // The counted noun comes from `Plural`, so "Put back 1 file" and
        // "Put back 5 files" are one key in every language.
        L(.putBackFiles(Plural.files(count, language: language.rawValue)), language: language)
    }

    /// The word on a row that has already gone back; the row stays, since hiding
    /// what was undone would hide an action. Not "put back" again: that is the
    /// button's word, and one English text means one thing, capital letter or not.
    static var putBackAlready: String { L(.backWhereItWas) }

    /// The header over one pass: the time, the folder the files came from when
    /// they all came from one, and how many there were.
    ///
    /// Composed from three pieces rather than written as a sentence, because
    /// the middle one is a folder name and the last already agrees with its own
    /// number in eight languages.
    static func passHeader(at when: Date, folder: String?, files: Int,
                           language: AppLanguage = AppLanguage.current,
                           home: String = NSHomeDirectory()) -> String {
        // macOS names its own folders («Загрузки», «ダウンロード»); a ninth
        // translation would give one folder two names on one screen.
        let named = folder.map {
            SystemFolderNames.displayOrOwn(path: $0, home: home, language: language.rawValue)
        }
        return [HelmDates.dayAndMinute(when), named,
                Plural.files(files, language: language.rawValue)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// What a return came to. Both halves always, because "8 back" alone reads
    /// as "all of them" — and a pass is not atomic.
    static func putBackReport(_ restored: Int, notPutBack: Int,
                              language: AppLanguage = AppLanguage.current) -> String {
        let done = L(.putBackReportRestored(String(restored)), language: language)
        guard notPutBack > 0 else { return done }
        return done + " · " + L(.putBackReportNotPutBack(String(notPutBack)), language: language)
    }

    /// A file that came back under a name it did not have. Told outright, or
    /// somebody goes looking for `march.pdf` and it is `march 2.pdf`.
    static func landedAs(_ file: String, as name: String,
                         language: AppLanguage = AppLanguage.current) -> String {
        // The marks are `Quoted`'s. Every language here punctuates quotation
        // differently and a table spelling them itself is a table that gets one
        // of them wrong.
        L(.landedAs(Quoted(file, language: language), Quoted(name, language: language)), language: language)
    }

    /// One file that did not go back, and why.
    ///
    /// The separator is the table's, not a dash written once for eight
    /// languages: Japanese and Chinese punctuate an apposition with their own
    /// marks, and an em dash between two of their phrases is a European
    /// sentence wearing their words.
    static func notPutBack(_ file: String, _ reason: String,
                           language: AppLanguage = AppLanguage.current) -> String {
        L(.notPutBack(file, reason), language: language)
    }

    /// The mark that stops a rule acting twice did not stick, so the rule will
    /// take this file again on the next sweep. The one line in this report with
    /// something for a person to do about it.
    static var ruleMayTakeItAgain: String {
        L(.theMarkThatStopsARule)
    }

    /// Beside that warning. Named, because a person with four rules needs to
    /// know which one is about to take the file back.
    static func turnRuleOff(_ rule: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L(.turnRuleOff(Quoted(rule, language: language)), language: language)
    }

    /// Why one file did not go back. Exhaustive on purpose, like the rule
    /// refusals beside it: a new reason refuses to build until it can say
    /// itself, and the `rawValue` never reaches a screen.
    static func undoRefusal(_ reason: UndoRefusal,
                            language: AppLanguage = AppLanguage.current) -> String {
        switch reason {
        case .notThere: L(.itIsNoLongerWhereAutopilot, language: language)
        case .notTheSameFile: L(.somethingElseIsThereNow, language: language)
        case .originGone: L(.theFolderItCameFromIs, language: language)
        case .originOutOfScope: L(.itIsOutsideTheFoldersA, language: language)
        case .changedSinceCheck: L(.thePathChangedUnderneath, language: language)
        case .nameTaken: L(.theOldNameIsTaken, language: language)
        case .trashEmptied: L(.itIsNoLongerInThe, language: language)
        case .alreadyUndone: L(.itHasAlreadyBeenPutBack, language: language)
        case .historyRefused: L(.thisRecordWasNotWrittenBy, language: language)
        case .noIdentity: L(.helmDidNotRecordEnoughTo, language: language)
        }
    }

    /// The card over a history that something else wrote. Its own sentence
    /// rather than `rulesTampered`: a forged history leaves the module working.
    static var historyTampered: String { L(.theRecordOfWhatAutopilotDid) }
    /// The verb beside it. Says what it does — the record goes, and Autopilot
    /// starts keeping one again — rather than «OK».
    static var discardHistory: String { L(.clearTheRecordAndStartAgain) }

    /// Why a row was refused, in the reader's language. The record stores the
    /// reason's rawValue, stable data, and only here does it become words.
    /// Exhaustive: a new reason refuses to build until it can say itself.
    static func historyRefusal(_ reason: RuleOutcome.Refusal,
                               language: AppLanguage = AppLanguage.current) -> String {
        switch reason {
        case .outOfScope: L(.refusedOutsideTheAllowedFolders, language: language)
        case .badPattern: L(.refusedUnusableRenamePattern, language: language)
        case .counterNumbersUsedUp: L(.refusedEveryCounterNumberIsUsed, language: language)
        case .folderUnreadable: L(.refusedTheFolderCouldNotBeRead, language: language)
        case .missing: L(.refusedTheFileIsNoLonger, language: language)
        case .changedSinceCheck: L(.refusedThePathChangedUnderneath, language: language)
        }
    }

    // MARK: - The banner for a pass nobody watched

    /// What the hourly sweep says out loud, and the only surface this module has
    /// that reaches somebody who is not looking at it.
    ///
    /// **The Trash is why it exists.** Everything else Autopilot does is a move
    /// it can undo from History, and a banner for each would be switched off
    /// before it said the one thing that matters. `SweepNews` holds that rule;
    /// this is only its voice.
    ///
    /// Titled with the module's name: a notification with no title shows the
    /// app's name, and «Helm» does not say which module is speaking (as
    /// `KAStr.batteryVetoNotice`).
    static func sweepNotice(_ tally: SweepNews.Tally,
                            language: AppLanguage = AppLanguage.current) -> NoticeText {
        // Two clauses at most, and each stands alone: what went to the Trash,
        // and what a rule could not act on. A single sentence adding them would
        // read «4 things happened», which sends the person to the log to find
        // out which — and the log is where the per-file detail already is.
        let clauses = [
            tally.trashed > 0 ? sweepTrashed(tally.trashed, language: language) : nil,
            tally.refused + tally.failed > 0
                ? sweepNotActedOn(tally.refused + tally.failed, language: language) : nil,
        ].compactMap { $0 }
        return NoticeText(title: L(.autopilot, language: language),
                          body: clauses.joined(separator: " · "))
    }

    /// The files are counted in `language`'s own plural first, and the Trash's
    /// word is written into the template, copied from the eight translations of
    /// `HelmWord.moveToTrash` (macOS's own spellings) so one folder never has two
    /// words. Check the copy against those if either changes.

    static func sweepTrashed(_ count: Int,
                             language: AppLanguage = AppLanguage.current) -> String {
        L(.sweepTrashed(Plural.files(count, language: language.rawValue)), language: language)
    }

    /// Refusals and failures under one clause, deliberately. They are different
    /// facts — the gate held, the filesystem said no — and the log keeps them
    /// apart under the same pass; what a banner owes the person is that a rule
    /// they wrote did not run, because every screen otherwise looks well.
    static func sweepNotActedOn(_ count: Int,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.sweepNotActedOn(Plural.files(count, language: language.rawValue)), language: language)
    }
}

extension RuleRefusal {
    /// The sentence the refused page says for this reason.
    var sentence: String {
        switch self {
        case .tampered: ApStr.rulesTampered
        case .noKey: ApStr.rulesUnreadable
        case .unreadable: ApStr.rulesNotRead
        }
    }

    /// Only a rule set somebody else wrote can be answered by throwing it away: a
    /// locked keychain is answered by waiting, and a record this build cannot
    /// read is not this build's to delete.
    var offersDiscard: Bool { self == .tampered }
}
