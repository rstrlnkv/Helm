import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

enum LfStr {
    // Named after the macOS pane that covers the same ground, so the mapping
    // is obvious: System Settings → General → Login Items & Extensions.
    static var moduleName: String { L(.loginItemsAndExtensions) }

    /// What the sidebar calls it. macOS carries the same pair: the pane is
    /// "Login Items & Extensions" and a list of panes says "Login Items" —
    /// these are its own words for the short form, language by language.
    static var moduleNameShort: String { L(.loginItems) }
    static var summary: String { L(.summary) }
    static var filterAll: String { L(.all) }
    static var filterLeftovers: String { HelmWord.leftovers }
    static var statusInUse: String { L(.inUse) }
    static var statusProtected: String { HelmWord.system }
    static var statusOrphaned: String { L(.leftover) }
    /// The badge on a row whose plist would not be read. Not «Unknown», which
    /// this app already uses for a VPN whose state it has not been told — one
    /// English text means one thing, and what this one says is that the file
    /// itself could not be read.
    static var statusUnreadable: String { L(.unreadable) }
    /// The badge on a row whose *file* was read and whose verdict still could not be
    /// reached: the program it points at is somewhere this process may not look, or
    /// the tool that lists what macOS has loaded did not answer. Not
    /// «Unreadable» — that word is about this file, and this file was fine.
    static var statusUndetermined: String { L(.notChecked) }
    static var scan: String { L(.scan) }
    static var scanning: String { HelmWord.scanning }
    static var rescan: String { HelmWord.scanAgain }
    /// Under the invitation on the first screen, so it is read once and then not
    /// again: what is in the list, and what may leave it.
    static var intro: String { L(.whatTheListHolds) }
    static var notScannedYet: String { L(.scanToSeeWhatAppsLeftBehind) }
    /// The one sentence on this screen a person must not miss, and it says why
    /// rather than telling them how to behave: nothing is pre-ticked *because
    /// macOS loads every one of these*.
    static var reviewNote: String { L(.nothingIsSelectedForYou) }
    /// **What the grant buys here is judgement, not removal.**
    /// `PermissionCheck.reason` names Full Disk Access for `/Library/Containers/`
    /// and `/Library/Group Containers/` paths only, and none of the scanner's
    /// seven sources can reach one — so no removal on this page can fail that
    /// way, and the note promised a consequence this module cannot have. What a
    /// refused read actually costs is a verdict: `exists` answers nil, the row is
    /// `.undetermined`, and a short list of leftovers then looks exactly like a
    /// Mac with none. Duplicates' own note says the same thing about folders.
    static var scanNeedsAccess: String {
        L(.scanNeedsFullDiskAccess)
    }
    /// **The button opens a pane; it manages nothing.** It calls
    /// `PermissionCheck.openExtensionSettings()`, and the Uninstaller's own
    /// button drives the identical call — so «Manage…» was a second label for one
    /// act, and the vaguer of the two. The Russian aspect problem goes with it:
    /// «Открыть» is perfective, which is what a button that acts once should be.
    ///
    /// The label itself is `HelmUI`'s, because two modules draw it.
    static var openExtensions: String { HelmControlName.openExtensions }
    /// The switch on a row, both ways round. Functions rather than properties
    /// because `confirmDeleteInUse` names this control inside a sentence, and it
    /// can only be read back in the other seven languages if the language can be
    /// named — and because a pair should read as one.
    static func disable(language: AppLanguage = AppLanguage.current) -> String {
        L(.turnOff, language: language)
    }

    static func enable(language: AppLanguage = AppLanguage.current) -> String {
        HelmWord.turnOn(language: language)
    }
    static var statusDisabled: String { L(.disabled) }
    /// The menu that narrows the list, drawn beside a filter glyph. «Show» is the
    /// panel's button elsewhere, and the two are not the same thing: this one is
    /// imperfective in Russian («Показывать: всё»), the button perfective
    /// («Показать»), so a shared key would put the wrong aspect on one of them in
    /// every Slavic language.
    static var filter: String { L(.filter) }
    static var cancelAction: String { HelmWord.cancel }
    /// **The row's menu names the same act as the bar's button**, plus the
    /// ellipsis that says a question follows: the dialog's destructive button says
    /// «Move to Trash» and the report afterwards «Moved to the Trash», so the
    /// control a person reads last uses the same name.
    static var deleteItem: String { L(.moveToTrashAndAsk) }
    /// The question the row asks before deleting — or nil for a row it deletes
    /// without asking.
    ///
    /// **One argument, and it is the item**, for the reason
    /// `LeftoverActions.available` records: a second parameter carrying the reason
    /// beside the item it is about buys nothing except the ability to disagree
    /// with it. The reason is a pure function of the item, so it is asked here.
    ///
    /// Exhaustive over `AskFirst` for the reason `kindName` records: the one
    /// question this module had said «It is loaded now», and it was drawn for
    /// every row that is not a leftover — including, once `.unreadable` existed, a
    /// file whose contents Helm never got to see.
    static func confirmDelete(_ item: StaleItem,
                              language: AppLanguage = AppLanguage.current) -> String? {
        switch LeftoverActions.askBeforeDeleting(item) {
        case .loadedNow: return confirmDeleteInUse(item.identifier, language: language)
        case .cannotBeRead: return confirmDeleteUnreadable(item.identifier, language: language)
        case .cannotBeChecked: return confirmDeleteUnchecked(item.identifier, language: language)
        case nil: return nil
        }
    }
    /// The file read fine; what Helm could not do is check whether anything still
    /// uses it — the program it points at sits where this process may not look, or
    /// macOS's own list of what is loaded did not come. So the sentence says that,
    /// rather than blaming the file the way `confirmDeleteUnreadable` does.
    static func confirmDeleteUnchecked(_ name: String,
                                       language: AppLanguage = AppLanguage.current) -> String {
        L(.confirmDeleteUnchecked(name), language: language)
    }

    static func confirmDeleteUnreadable(_ name: String,
                                        language: AppLanguage = AppLanguage.current) -> String {
        L(.confirmDeleteUnreadable(name), language: language)
    }

    /// **The clause about the switch is the load-bearing half.** «It is loaded
    /// now» warns about the lesser fact: `LeftoversEngine.trash` moves paths and
    /// nothing else, so the job goes on running after its file is in the Trash —
    /// until the next login, or until the app puts the file back. What stops it is
    /// the switch on this same row: `ActiveExtensions.setDisabled` sends `launchctl
    /// disable` **and** `bootout`.
    ///
    /// It **asks** that control for its word rather than spelling it again
    /// (`VPNStr.secretNeedsAPress` is the same construction), so renaming the
    /// button carries the sentence with it in all eight instead of leaving it
    /// behind — the 0.9.0 defect CLAUDE.md records. `Quoted` puts it in each
    /// language's own marks.
    static func confirmDeleteInUse(_ name: String,
                                   language: AppLanguage = AppLanguage.current) -> String {
        let off = Quoted(disable(language: language), language: language)
        return L(.confirmDeleteInUse(name, off), language: language)
    }
    /// Why there is no delete button on this row, in the person's terms. Two
    /// sentences, because the two states ask different things of them: one is a
    /// password somebody has, the other is nothing anybody can do.
    ///
    /// Exhaustive over the reason for the same cause `kindName` records — a
    /// `default` here is how one of the two sentences would come to be drawn for
    /// both, which is the defect this pair exists to end.
    static func noDelete(_ reason: NoDelete) -> String {
        switch reason {
        case .needsAdministrator: return needsAdmin
        case .protectedByMacOS: return L(.protectedByMacOS)
        }
    }

    /// Says what the act is, which is moving a file to the Trash.
    static var needsAdmin: String { L(.onlyAnAdministratorCanMoveThis) }
    static var nothingFound: String { HelmWord.noLeftoversFound }
    /// The message over the empty list, one per reason there is no list.
    ///
    /// Over the enum and exhaustive, for the reason `kindName` records: a
    /// `default` here would draw a sentence about a clean Mac for a fourth state
    /// nobody had looked at, which is how «No leftovers found» came to be shown
    /// with rows in the model in the first place.
    static func emptyMessage(_ nothing: LeftoversEmpty.Reason) -> String {
        switch nothing {
        case .notScanned: return notScannedYet
        case .nothingFound: return nothingFound
        // A claim about the filter, not about the Mac — and the filter menu is on
        // screen above this line, which is what makes it worth its own sentence.
        case .hiddenByFilter: return L(.everythingHiddenByFilter)
        // **The message, not a note under «No leftovers found».** A headline with
        // a footnote invites the reader to trust the headline, and that headline
        // is exactly the claim this scan cannot back.
        case .notEverythingChecked(let count): return couldNotCheck(count)
        }
    }

    /// What the scan could not judge, beside what it found — a label, because the
    /// strip it sits in holds controls and no prose, and its neighbour is
    /// «Found: N».
    ///
    /// **Two sentences rather than one for both places.** The prose form measured
    /// 194 pt in Russian against `foundLine`'s 108 in that bar; and on the empty
    /// screen the reverse fails, where a bare label is a number with no claim
    /// under it. Both are built from each language's own `statusUndetermined`
    /// badge and `confirmDeleteUnchecked` question, so the count, the pill and the
    /// delete question cannot drift apart. Neither names the verb: the Scan button
    /// is the answer and it is on screen either way.
    static func uncheckedLine(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L(.uncheckedLine(items), language: language)
    }

    static func couldNotCheck(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L(.couldNotCheck(items), language: language)
    }
    /// Asked before the batch, because this button is the one that acts on the
    /// most load-bearing files in the app — launch agents and login items —
    /// and it was the only multi-file removal in Helm that did not ask.
    /// One question, and nothing after it. It used to promise "It will free
    /// 4 KB" — of files that move to a folder on the same volume, where they
    /// stay until the Trash is emptied. Disk's `confirmTrash` is the shape: the
    /// size sits inside the question as what is going, not as what is gained.
    static func confirmSelected(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }
    static var removeSelected: String { HelmWord.moveToTrash }
    static var selectAll: String { HelmWord.selectAll }
    static var deselectAll: String { HelmWord.clearSelection }
    /// **A badge is a mark, not a predicate.** «Runs at login» measured 137 pt of
    /// pill in German, and against the fourteen real launch-agent labels on this
    /// Mac ten of the fourteen then truncated — seven of fourteen in Russian. What
    /// the row is for is its name; this is the qualifier beside it.
    static var runsAtLogin: String { L(.atLogin) }
    /// The one line under a row's name: where the file is, and what is wrong with
    /// it if anything is.
    ///
    /// **One line, because the list had three heights.** The path and the missing
    /// target were two rows of their own — 44 pt with a path, 59 pt with both, 32 pt
    /// for a system extension — and two of those are the same row wearing a fact it
    /// happens to carry. One line, and the row draws it as two `Text`s side by side:
    /// which of the two gives way when the width runs out is the whole point, and a
    /// single joined string can only ever surrender its own end.
    ///
    /// Nil for a system extension, and that is not an omission: the scan gives one
    /// its identifier as its path (`LeftoversScanner.systemExtensions`), so the
    /// line would be the name again a step quieter.
    /// **The dot is language-shaped too**, and this was the one join in the module
    /// that did not know it: `selectedLine` twenty lines down sets `・` for
    /// Japanese, as does every other join in the app, and this one handed all eight
    /// languages a Latin middle dot.
    ///
    /// **The separator belongs to the reason.** Left on the path it is the first
    /// thing a truncation eats, and a middle dot with nothing after it is the same
    /// defect one character shorter.
    struct Detail: Equatable, Sendable {
        /// Where the file is: the half that gives way, and is cut in the middle,
        /// because both its ends carry meaning — or is not drawn at all, below
        /// the width of its own last component (`LeftoverPathFloor`).
        let path: String
        /// What is wrong with it, bare — the fallback where the path is not
        /// drawn: with nothing in front of it, a separator would dangle at the
        /// line's *start*, the defect below one character earlier.
        let clause: String?
        /// The language-shaped mark between the halves. It belongs to the
        /// reason, not the path: left on the path it is the first thing the
        /// truncation eats, and a middle dot with nothing after it is the same
        /// defect one character shorter.
        let separator: String
        /// What is wrong with it, separator and all — drawn whole beside the
        /// path: it is the strongest evidence a login item is dead. Computed,
        /// so the two spellings of the reason cannot drift apart.
        var reason: String? { clause.map { separator + $0 } }
    }

    static func detail(for item: StaleItem,
                       language: AppLanguage = AppLanguage.current) -> Detail? {
        guard item.kind != .systemExtension else { return nil }
        // Written as the one difference rather than as eight rows of which seven
        // are identical: only Japanese changes the mark.
        let dot = language == .ja ? "・" : " · "
        return Detail(path: item.path, clause: clause(for: item, language: language),
                      separator: dot)
    }

    /// What is wrong with this row, in one clause — or nothing, for a row whose
    /// badge is the whole story.
    ///
    /// **One clause, and the order is what a person can do about it.** A leftover
    /// whose label another file registers carries two facts at once: that it points
    /// at a missing file, which is why it is badged «Leftover» — a mark already on
    /// screen — and that another file wears its name, which is why the row has no
    /// «Turn off». The second explains a control that is *not* there, and a missing
    /// control with no reason is what this sentence exists to prevent.
    ///
    /// Exhaustive over the status for the reason `kindName` records: a source row's
    /// sentence is the only thing on its row, and a `default` is how one would come
    /// to be drawn with the wrong one or with none.
    private static func clause(for item: StaleItem, language: AppLanguage) -> String? {
        switch item.status {
        case .sourceRedirected: return item.leadsTo.map { sourceLeadsElsewhere($0, language: language) }
        case .sourceUnreadable: return folderUnreadable(language: language)
        case .orphaned, .inUse, .protectedItem, .unreadable, .undetermined:
            if let other = item.labelAlsoClaimedBy {
                return labelClaimedTwice(other, language: language)
            }
            return item.missingTarget.map { missingTarget($0, language: language) }
        }
    }

    /// A source of the scan that leads somewhere else, and where it leads.
    ///
    /// The destination rather than the folder: the row already draws the folder as
    /// its name and its path, and what a person cannot see anywhere else is where
    /// the link actually goes — which is what tells them whether it is theirs.
    static func sourceLeadsElsewhere(_ destination: String,
                                     language: AppLanguage = AppLanguage.current) -> String {
        L(.sourceLeadsElsewhere(destination), language: language)
    }

    /// A source of the scan this process could not open. **Autopilot's key, not a
    /// second one saying the same thing**: it is the same sentence about the same
    /// fact, and one English text means one thing.
    static func folderUnreadable(language: AppLanguage = AppLanguage.current) -> String {
        HelmWord.cannotReadThisFolder(language: language)
    }

    /// The other file that registers this row's login item.
    ///
    /// **It names the file rather than counting the files**, because the question
    /// the row leaves a person with is «then which one am I looking at» — and the
    /// pair point at each other, so either row answers it. The clause is why there
    /// is no «Turn off» here: the switch is aimed at the name, two files carry the
    /// name, and Helm cannot read which registration launchd kept.
    static func labelClaimedTwice(_ other: String,
                                  language: AppLanguage = AppLanguage.current) -> String {
        L(.labelClaimedTwice(other), language: language)
    }
    static func missingTarget(_ path: String,
                              language: AppLanguage = AppLanguage.current) -> String {
        L(.missingTarget(path), language: language)
    }
    /// The bar under the list, about the selection and nothing else. It used to
    /// pair the number of rows found with the size of the selection, and a
    /// middle dot made the two look like one measurement: "1 item · 0 B" over a
    /// visible row saying 4 KB.
    static func selectedLine(_ n: Int, _ size: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L(.selectedLine(items, size), language: language)
    }

    /// What the scan turned up, beside the control that filters it.
    static func foundLine(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L(.foundLine(items), language: language)
    }
    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. The same
    /// sentence Disk settled on, in Finder's own words for the act (`AL13`) in
    /// the past tense — one phrasing across the app, not a second one here.
    ///
    /// **The count as well as the size.** The person ticked a number of rows and
    /// `LeftoversViewModel.removedCount` is in hand where this is built, so a
    /// report that measured the batch without counting it was leaving out the
    /// half they had chosen. Russian keeps the em dash with the word before it;
    /// Japanese and Chinese use their own colon and their own dot, which is what
    /// `selectedLine` two functions up already does.
    static func movedToTrash(_ count: Int, _ size: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(count, language: language.rawValue)
        return L(.movedToTrash(items, size), language: language)
    }
    /// **The kind, not its `rawValue`.** This took a `String` and ended in a
    /// `default` that answered "Plug-ins" — so a sixth `StaleKind` would have
    /// been drawn under the wrong heading, silently, and the `default` is
    /// exactly the shape CLAUDE.md keeps out of the engines for the same reason:
    /// it makes an unhandled case look like an answer. Over the enum the switch
    /// is exhaustive and a new case is a build error.
    static func kindName(_ kind: StaleKind) -> String {
        switch kind {
        case .launchAgent: return HelmWord.launchAgents
        case .launchDaemon: return L(.launchDaemons)
        case .preference: return HelmWord.settingsFiles
        case .systemExtension: return L(.systemExtensions)
        case .plugin: return L(.plugIns)
        }
    }
}
