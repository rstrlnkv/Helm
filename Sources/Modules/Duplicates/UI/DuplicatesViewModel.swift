import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

/// Why a group's first copy is the one that stays.
///
/// The engine's `KeepReason` and one case more: the person said so. It is not a
/// case of `KeepReason` itself, and deliberately — that enum is the ladder, and
/// every rung of it is something `SurvivingCopy.separates` has to be able to
/// answer. A rung that only a human can climb would have to be handled there and
/// could never be reached.
public enum KeepGrounds: Equatable, Sendable {
    /// The rung of the policy's ladder that separated it from the next copy.
    case rung(KeepReason)
    /// Chosen on this page, in this session.
    case byHand
}

/// The module's state: which folder, what was found, what is going to the bin.
@MainActor public final class DuplicatesViewModel: ObservableObject {
    public enum Phase: Equatable { case start, searching, result }

    @Published public private(set) var phase: Phase = .start
    /// The folder the last search ran on, and the one the next will.
    @Published public private(set) var folder: URL?
    @Published public private(set) var groups: [DuplicateGroup] = []
    /// What the last walk could not compare: directories it was refused, files
    /// whose digest could not be taken. Held rather than folded into a sentence
    /// here, because the sentence is the page's and the rule is the engine's.
    @Published public private(set) var unreadable = 0
    /// Application libraries the last walk stepped over rather than opened.
    @Published public private(set) var librariesSkipped = 0
    @Published public private(set) var progress: DuplicateProgress?
    @Published public var basket: [String] = []
    @Published public private(set) var banner: String?
    /// Paths macOS refused, with their own reasons — see `DiskViewModel`. A
    /// reason chosen for the whole batch describes at most one of them.
    @Published public private(set) var failures: [HelmTrash.Refusal] = []
    /// How many actually moved. `HelmRemovalOutcome` decides what to say from
    /// this and `failures`: a sentence cannot be asked whether it is true.
    @Published public private(set) var removedCount = 0
    /// The last removal's reply never came back.
    ///
    /// The fourth thing the report is read as, and the fourth module to need it:
    /// not a claim that anything moved, not a refusal, and not silence.
    /// `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent`, so
    /// leaving the three fields at zero drew nothing at all — measured, the page
    /// after the press was pixel-identical to the page before it, and so was the
    /// page after a *second* press.
    ///
    /// The list is stale with it. This module prunes `groups` from
    /// `removal.removed` and never re-reads, so a lost reply means nothing on
    /// screen has been read since before the press — which is why the page draws
    /// `HelmRemovalOutcome.unansweredWithStaleList` and not the plain sentence,
    /// whose second half points at a list its caller has just refreshed.
    @Published public private(set) var replyLost = false
    /// The last search did not run to its end — stopped by the person, or
    /// given up by the engine.
    ///
    /// `removalStopped`'s repair, one act over: `cancel()` lands on `phase =
    /// .start` with the folder still chosen, so without this the screen read
    /// exactly as it does before anything has happened. Set on the press rather
    /// than off a reply, because for the search the press is authoritative —
    /// the same line drops the request token, so no answer can land after it —
    /// and set again where the engine itself answers nothing, which is its own
    /// way of not finishing. The next search withdraws it on the way in.
    @Published public private(set) var searchStopped = false
    /// The last removal was stopped by the person, between files.
    ///
    /// The fifth thing the report is read as — not a success, not a refusal,
    /// not silence and not a lost reply. Read off the *reply*, never off the
    /// press: the stop is a request, and what actually happened before it
    /// landed is the engine's to say. What did move before the stop is still
    /// in `removedCount` and the banner, so the two can be true at once.
    @Published public private(set) var removalStopped = false

    /// Which search the groups belong to, so a late answer cannot resurrect
    /// itself over a newer one — or over a cancellation, which is a token taken
    /// and dropped. `LatestRequest` (HelmRuntime) is the counter; this view model
    /// and Leftovers' had both written it out by hand.
    private var searches = LatestRequest()

    /// What the person believes an extra copy is, as the popup under the toolbar
    /// shows it — and as the engine has it stored, since the two are read from
    /// one place.
    @Published public private(set) var policy: KeepPolicy

    /// One line about what the last press did to the marks, or nil.
    ///
    /// **One channel, because the two things it says are about the same thing**
    /// — what is ticked — and only ever one of them is current: a policy change
    /// takes marks off copies that now stay, and «mark every extra copy» passes
    /// over what Helm may not remove. Both are silent changes to a list the
    /// person is holding a figure about, and both happen mostly below the fold.
    @Published public private(set) var marksNote: String?

    /// Groups whose survivor the person chose by hand, keyed by that survivor's
    /// own path.
    ///
    /// **In memory, for the session.** The choice is about the list on screen;
    /// the next search reads the folder again and re-decides everything, which
    /// is what somebody pressing Search again is asking for.
    ///
    /// Keyed by the survivor's path and not by `DuplicateGroup.id`: that id is a
    /// digest of the group's paths, so it survives a rearrangement but not a
    /// change of membership, and a removal is exactly that — `emptyBasket`
    /// rebuilds the group from the copies that are left and the digest moves,
    /// leaving a pin nothing on screen answers to. The survivor's path is the one
    /// copy a removal may never take (the group is rebuilt from the copies after
    /// the first), so it is stable across the very removal the id is not — and it
    /// is the thing the person actually chose. A path is in one group, so it
    /// names no other.
    private var pinned: Set<String> = []

    let vm: ModuleViewModel
    private let client: TransportClient
    private let store: NamespacedStore
    /// How a stored setting is judged to be Helm's own. A port for the reason
    /// every port here is one: the production answer is the login keychain, and
    /// a test must not write to the person's.
    private let settings: SettingGuard
    private var eventsTask: Task<Void, Never>?

    /// Search state must outlive the settings page. Settings tears the page down
    /// on every sidebar visit, and this module has no on-disk cache behind it —
    /// hashing a folder is minutes of reading, so losing it to a click is
    /// hostile. One instance per host view model; the page observes it.
    private static var cached: DuplicatesViewModel?
    ///
    /// `settings:` is forwarded rather than left to `init`'s default for the
    /// reason `ATestNamesTheKeychainPortsItBuildsOverTests` gives: the default
    /// is the login keychain, so a caller that cannot name a double — a test
    /// switching the module off to watch the subscriber go — would spend
    /// `SecItemAdd` on somebody's machine to ask a question about ARC.
    public static func shared(vm: ModuleViewModel, store: NamespacedStore,
                              settings: SettingGuard = DuplicatesSettings.guardOfScanSettings)
    -> DuplicatesViewModel {
        // Keyed to the view model it was built against, not merely "exists" —
        // see `DiskViewModel.shared(vm:)`. Turning the module off deallocates
        // the engine while the `LocalTransport` held here survives, and its
        // weakly-captured handler answers every request with empty Data from
        // then on.
        if let cached, cached.vm === vm { return cached }
        let created = DuplicatesViewModel(vm: vm, store: store, settings: settings)
        cached = created
        ModuleUICache.dropWhenDisabled(DuplicatesDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel, store: NamespacedStore,
                settings: SettingGuard = DuplicatesSettings.guardOfScanSettings) {
        self.vm = vm
        self.store = store
        self.settings = settings
        self.client = TransportClient(vm.transport)
        // Through the engine's own reading, seal and all: a page that parsed the
        // plist itself would show a forged policy as the one in force, which is
        // the single place the forgery must not be believed.
        self.policy = DuplicatesSettings.keepPolicy(in: store, guardedBy: settings)
        let remembered = store.string("folder", default: "")
        if !remembered.isEmpty { folder = URL(fileURLWithPath: remembered) }
        // The stream is captured here and `self` re-acquired per event: handing
        // the loop to an instance method resolves the weak capture once and
        // then holds `self` for the whole call, which never returns. That kept
        // the view model alive, which in turn meant the `deinit` below could
        // never run — a cancel that cancelled nothing.
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.handle(event)
            }
        }
    }

    deinit { eventsTask?.cancel() }

    /// What emptying the basket would free.
    ///
    /// **Not the sum of the ticked copies' sizes.** A clone shares its blocks
    /// with the copy it was made from, and in this module that copy is the one
    /// that stays — so its removal returns nothing, and adding the sizes up
    /// promised exactly double on the case Finder's own Duplicate command
    /// creates. `DuplicateGroup.reclaimable` is the same fold `wasted` uses and
    /// the same slate `HelmTrash` opens for the batch, so the bar, the
    /// confirmation that quotes it and the banner afterwards are one arithmetic.
    public var basketBytes: Int {
        DuplicateGroup.reclaimable(marking: Set(basket), in: groups)
    }

    /// One copy's own figure. A group's size is the copy that stays, so quoting
    /// it against a path promised a clone's nothing for a real file, or the
    /// reverse — the basket bar and the menu under it both ask this.
    public func bytes(of path: String) -> Int {
        groups.lazy.compactMap { group in
            group.copies.first { $0.path == path }
        }.first?.bytes ?? 0
    }

    /// What acting on the whole screen would free — every extra copy in every
    /// group, through the fold `basketBytes` uses, so pressing «Mark every extra
    /// copy» makes the bar say what the toolbar above it already said.
    public var wastedBytes: Int {
        DuplicateGroup.reclaimable(marking: Set(groups.flatMap { $0.paths.dropFirst() }),
                                   in: groups)
    }

    /// Why there is no list — and `nil` when there is one, which is what the
    /// page branches on.
    ///
    /// **Not `groups.isEmpty`.** «No duplicates here. Every large file under this
    /// folder is one of a kind» is an assertion about somebody's Mac, and it was
    /// drawn identically whether the walk read the whole tree or was refused at
    /// every door. `DuplicatesEmpty` holds the rule and says why there are three
    /// answers; `LeftoversViewModel.nothingToShow` is the same property for the
    /// same repair, one module over.
    public var nothingToShow: DuplicatesEmpty.Reason? {
        DuplicatesEmpty.reason(groups: groups.count, unreadable: unreadable,
                               librariesSkipped: librariesSkipped)
    }

    // MARK: - Choosing a folder

    /// The module's own folder picker. Inside Disk the search followed the
    /// ring, which meant it could only look where a ring had already been
    /// drawn; on its own it asks.
    public func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = DupStr.chooseFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        store.set(url.path, for: "folder")
        // Sealed here because here is where the authority is: an open panel the
        // person just used. The background scan reads this value with nobody
        // watching and refuses it if the seal does not match — see `SettingGuard`.
        store.set(settings.seal(Data(url.path.utf8)) ?? "",
                  for: SettingGuard.macKey(for: "folder"))
        search()
    }

    // MARK: - Which copy stays

    /// The person's answer to what an extra copy is.
    ///
    /// Stored and sealed here, because here is where the authority is — a popup
    /// somebody just used — and read back by the background scan, which has
    /// nobody at the desk. The seal is written with the value: the engine refuses
    /// a policy it did not write, so a value saved without its MAC would leave
    /// every unattended scan on the default while this page said otherwise.
    public func choose(_ chosen: KeepPolicy) {
        guard chosen != policy else { return }
        policy = chosen
        DuplicatesSettings.setKeepPolicy(chosen, in: store, guardedBy: settings)
        rearrange()
    }

    /// Which copy stays, decided again for every group the person has not
    /// decided themselves.
    ///
    /// **Nothing is read again.** The copies carry their own date added, so the
    /// same ladder the engine applied at the end of the walk answers here from
    /// what is already on screen — a policy change costs no hashing, which is
    /// what makes an immediate answer possible at all.
    ///
    /// `SurvivingCopy.order` and not a second implementation of it: the page
    /// would otherwise be free to disagree with the search it is displaying, and
    /// that disagreement is the defect `KeepPolicy.ladder` exists to prevent.
    private func rearrange() {
        let rule = KeepRule(policy)
        groups = groups.map { isPinned($0) ? $0 : ordered($0, by: rule) }
        dropMarksOnCopiesThatStay()
    }

    /// Whether the person chose this group's survivor by hand — the one question
    /// `pinned` answers, asked in one place so its keying lives here and not at
    /// every reader.
    private func isPinned(_ group: DuplicateGroup) -> Bool {
        group.copies.first.map { pinned.contains($0.path) } ?? false
    }

    /// Records that this group's survivor was chosen by hand, by that survivor's
    /// own path (see `pinned`). Any earlier survivor of the group demoted itself,
    /// so its pin goes with it — one path pinned per group.
    private func pin(_ path: String, in group: DuplicateGroup) {
        unpin(group)
        pinned.insert(path)
    }

    /// Releases this group's hand-made choice, whichever of its copies holds it.
    private func unpin(_ group: DuplicateGroup) {
        pinned.subtract(group.copies.map(\.path))
    }

    /// One group in the ladder's order — the one spelling, since the policy and
    /// a group handed back to it ask for exactly the same thing.
    ///
    /// Takes the rule rather than reading `policy`: building it is a question
    /// about this Mac's folders, which belongs to the pass and not to each group
    /// in it.
    private func ordered(_ group: DuplicateGroup, by rule: KeepRule) -> DuplicateGroup {
        DuplicateGroup(copies: SurvivingCopy.order(group.copies, by: rule))
    }

    /// The person's answer for one group, where they know something the ladder
    /// cannot see.
    ///
    /// **A rearrangement, not a second kind of state.** Everything on this page
    /// reads one invariant — the first copy of a group is the one that stays —
    /// so a chosen survivor held beside the array would be a second answer to a
    /// question the array already answers, and `wasted`, the basket arithmetic,
    /// the plans and the background scan's report would each have to be taught
    /// about it. Moving the copy to the front teaches none of them anything.
    ///
    /// The group is pinned by the same act — by the chosen copy's own path, which
    /// is the survivor a removal may never take, so the pin outlives the removal
    /// that re-keys the group (see `pinned`).
    public func keep(_ path: String, in group: DuplicateGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }),
              let chosen = groups[index].copies.first(where: { $0.path == path })
        else { return }
        pin(path, in: groups[index])
        groups[index] = DuplicateGroup(copies: [chosen]
            + groups[index].copies.filter { $0.path != path })
        // Silently, unlike a policy change: the row the person just clicked is
        // the row that changes, from a checkbox into the badge that says it
        // stays. A line of report about something visible under the pointer is
        // noise; the policy's is not, because that one moves rows nobody is
        // looking at.
        basket.removeAll { $0 == path }
    }

    /// Hands the group back to the policy.
    ///
    /// It releases the pin as well as re-ordering: a group left pinned to an
    /// order the rule happens to agree with would silently step over the next
    /// policy change, and nothing on screen would say why.
    public func restoreRecommendation(for group: DuplicateGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        unpin(groups[index])
        groups[index] = ordered(groups[index], by: KeepRule(policy))
        dropMarksOnCopiesThatStay()
    }

    /// Why this group's first copy is the one that stays — what the header says.
    ///
    /// Nil for a group of one, which the list does not draw: `SurvivingCopy`
    /// answers the rung that separated the survivor from the copy that came
    /// closest, and with nothing to compare against there is no rung.
    public func grounds(of group: DuplicateGroup) -> KeepGrounds? {
        if isPinned(group) { return .byHand }
        return SurvivingCopy.reason(among: group.copies, by: KeepRule(policy)).map(KeepGrounds.rung)
    }

    /// A ticked copy that has just become the one that stays comes off the list.
    ///
    /// The invariant the whole page rests on is that the first copy of a group is
    /// never removed, and `emptyBasket` enforces it by building its plans from
    /// the copies after the first. So a mark left on a promoted survivor is not a
    /// file at risk — it is a *count* at risk: the bar would promise four files
    /// and three would go, which is the arithmetic this module is measured by.
    private func dropMarksOnCopiesThatStay() {
        let staying = Set(groups.compactMap { $0.copies.first?.path })
        let freed = basket.filter { staying.contains($0) }
        basket.removeAll { staying.contains($0) }
        // Nil rather than left standing: a note about the previous change is a
        // report about a list that has moved on.
        marksNote = freed.isEmpty ? nil : DupStr.unmarkedSurvivors(freed.count)
    }

    // MARK: - Searching

    public func search() {
        guard let folder, phase != .searching else { return }
        phase = .searching
        progress = nil
        groups = []
        basket = []
        // The excuses belong to the walk that made them, and there is about to
        // be a different walk. **Not redundant with the assignment on the
        // reply**, which is what it looked like and was measured not to be:
        // `groups` is emptied on this line, so between here and the answer a
        // stale count is a `nothingToShow` of `.notEverythingRead` about a
        // folder nobody is reading any more.
        unreadable = 0
        librariesSkipped = 0
        // The whole removal report, not two fields of it. Clearing `replyLost`
        // alone left the banner, the failures and the count standing — a
        // refusal from the last removal drawn under a different folder's
        // results, saying «could not be moved» about a file the new search
        // never returned. The fields are one report and go together.
        clearRemovalReport()
        // The previous search's own outcome goes the same way: this press is
        // the answer to it.
        searchStopped = false
        // And the same for the marks: «unmarked: 2» is about a basket that has
        // just been emptied by the line above, and the groups it named are gone.
        marksNote = nil
        // Every hand-made choice belonged to the list that is being replaced. A
        // pin held across a search would step over the new answer for a group
        // whose id happens to match — the same content found again — while the
        // person is watching a search they asked for.
        pinned = []
        let mine = searches.take()
        let path = folder.path
        // Taken here, with the folder, so the request describes the page as it
        // was when the button was pressed rather than as it is whenever the task
        // happens to run.
        let chosen = policy
        Task {
            // `DuplicateFindings`, the type the engine's `find` answers — the
            // one place these two targets have to agree, and they had stopped:
            // asking here for the bare `[DuplicateGroup]` the engine used to
            // send made every search decode as nothing, which this method reads
            // as a cancellation. It built clean and no fake could see it,
            // because every fake in the test target spells the reply itself.
            // The policy travels with the request. The engine needs it before it
            // hashes anything — the name that stands for a hard-linked set is
            // chosen by the same ladder — and the person at an open page may be
            // looking at one they have just changed.
            let found: DuplicateFindings? = await client.request(
                DuplicatesCommand.find,
                encoding: DuplicateSearchRequest(path: path, policy: chosen))
            guard searches.isLatest(mine) else { return }
            // Cancelled comes back nil: go back to where we were rather than
            // announce a clean folder nobody finished checking — and say so.
            // The engine answering nothing is its own way of not finishing,
            // and a start screen with the folder still chosen otherwise reads
            // as if nothing had happened.
            guard let found else {
                phase = .start
                searchStopped = true
                return
            }
            groups = found.groups
            // The answer is ordered by the policy the *request* carried, and a
            // search takes minutes with the popup live throughout. When the two
            // still agree there is nothing to do — re-deciding what the engine
            // has just decided by the same rule is the second pipeline this
            // module has already paid for once. When they do not, the list would
            // otherwise sit in one order while the sentence above it named
            // another, and the header's reason — which asks the ladder rather
            // than the array — would describe a copy that is not on the first row.
            if chosen != policy { rearrange() }
            unreadable = found.unreadable
            librariesSkipped = found.librariesSkipped
            phase = .result
        }
    }

    public func cancel() {
        // Taken and dropped: everything in flight is stale from here.
        _ = searches.take()
        // No payload. It used to encode an empty `[String]` the engine never
        // decodes — two bytes of JSON standing where «nothing» was meant.
        Task { await client.send(DuplicatesCommand.cancel) }
        // A named outcome, and only for a search that was actually running: a
        // press is authoritative here because the token above is already
        // dropped, so no answer can land after it (see `searchStopped`).
        if phase == .searching { searchStopped = true }
        // Back to the start, whether or not a folder is chosen. This was
        // `folder == nil ? .start : .start` — a ternary whose two branches are
        // the same value, which is a decision somebody meant to make and did
        // not, wearing the shape of one that was made.
        phase = .start
        progress = nil
    }

    // MARK: - The bin

    public func isBasketed(_ path: String) -> Bool { basket.contains(path) }

    public func toggleBasket(_ path: String) {
        if let index = basket.firstIndex(of: path) {
            basket.remove(at: index)
        } else if UserFileScope.isRemovable(path) {
            basket.append(path)
        }
    }

    /// Every path in the group except the first — the first is the copy that
    /// stays, and there is deliberately no way to ask for all of them.
    public func basketExtras(of group: DuplicateGroup) {
        report(skipped: mark(extrasOf: group))
    }

    /// Every group's extras, through the same rule the per-group button uses.
    ///
    /// Deliberately over `mark(extrasOf:)` rather than its own walk of the
    /// groups: two implementations of "which copy survives" is two answers to
    /// the only question on this page that costs someone a file.
    public func basketAllExtras() {
        report(skipped: groups.reduce(0) { $0 + mark(extrasOf: $1) })
    }

    /// Marks what may be marked, and answers how many copies it passed over.
    ///
    /// The scope gate is `UserFileScope`, the same one the engine has the last
    /// word with — a checkbox that ticked something the engine will refuse would
    /// be a promise the page cannot keep. What was missing is the count: the
    /// refusal was silent, and one press stands for a page of decisions.
    private func mark(extrasOf group: DuplicateGroup) -> Int {
        var skipped = 0
        for path in group.paths.dropFirst() where !basket.contains(path) {
            if UserFileScope.isRemovable(path) {
                basket.append(path)
            } else {
                skipped += 1
            }
        }
        return skipped
    }

    /// One line about what the press passed over, or none.
    private func report(skipped: Int) {
        marksNote = skipped == 0 ? nil : DupStr.skippedNotRemovable(skipped)
    }

    /// Empties the basket. Nothing is deleted, nothing is moved.
    ///
    /// The counterpart to `basketAllExtras`, and the reason it can exist: one
    /// press that ticks three hundred checkboxes needs one press that unticks
    /// them. Named apart from `emptyBasket()`, which is the one that trashes —
    /// two methods about the basket differing only in outcome must not read
    /// alike at the call site.
    ///
    /// **Not while a removal is running.** `emptyBasket` captures the paths at
    /// its first line, so the request is already out with them in it: the basket
    /// emptied on screen, the files went, and «Moved to the Trash — 9 GB» arrived
    /// about a selection the person had just cleared — measured, with `trash`
    /// parked. The only control on this page that looks like a way out of a
    /// destructive act was not one. The page dims the button as well; both, or
    /// neither is reliable (ARCHITECTURE.md § One removal at a time).
    ///
    /// The guard is on this press and not on the reading, which is the trap
    /// `LeftoversViewModel.dropHiddenSelections` records: a removal holding
    /// `busy` across work of its own would refuse the very update that puts the
    /// list right.
    public func clearBasket() {
        guard !busy else { return }
        basket.removeAll()
    }

    /// A removal is running. The page dims what would start a second one.
    @Published public private(set) var busy = false

    public func emptyBasket() async {
        let paths = basket
        guard !paths.isEmpty else { return }
        // Each removal travels with the copy it duplicates, so the engine can
        // read the pair again before it moves anything. A group's first copy is
        // the survivor — `SurvivingCopy`'s order — and a basket entry whose
        // group has gone is dropped rather than sent unpaired: the engine would
        // refuse it anyway, and unpaired is exactly the shape it cannot check.
        let chosen = Set(paths)
        let plans: [DuplicatePlan] = groups.flatMap { group -> [DuplicatePlan] in
            guard let survivor = group.copies.first?.path else { return [] }
            return group.copies.dropFirst()
                .filter { chosen.contains($0.path) }
                .map { DuplicatePlan(remove: $0.path, keep: survivor) }
        }
        guard !plans.isEmpty else { return }
        // **One removal at a time**, the rule `UninstallerViewModel` already
        // follows. The basket is not emptied until the answer comes back, so
        // between the press and that moment the button is live and the same
        // paths are still in it. The second round is not a second deletion —
        // the files are already in the Trash — it is a refusal per path, and
        // the lines below overwrite the report of the removal that worked.
        guard !busy else { return }
        busy = true
        // The ticks belong to the removal that made them: cleared on the way
        // in so the busy row cannot open on the last press's «N of M», and on
        // the way out so the next one cannot.
        progress = nil
        defer {
            busy = false
            progress = nil
        }
        let removal: DuplicateRemoval? = await client.request(DuplicatesCommand.trash, encoding: plans)
        // **An unanswered removal is not a removal that did nothing.**
        // `TransportClient.request` answers nil for a request that threw and for
        // a reply that would not decode, and this module reaches the second in
        // its own tree: `wireTransport` returns empty `Data` for an engine that
        // has gone under a page still up — which `shared(vm:store:)` says is
        // every request from then on — for a command name it cannot parse, and
        // for a payload that will not decode. Returning here left the page
        // silent about a destructive press, and the reasonable reading of
        // silence is «press it again».
        //
        // Nothing else moves: the engine may well have trashed the files, and
        // the list on screen is only ever pruned from this reply. So the basket
        // and the groups stay exactly as they are, and the sentence claims
        // nothing about either.
        guard let removal else {
            clearRemovalReport()
            replyLost = true
            // Counts and outcomes are free; nothing here names a file. This was
            // the one branch that reached the screen without reaching the log,
            // which is the branch a person would be attaching a log to.
            HelmLog.shared.info(DuplicatesEngine.moduleID, "trash reply lost")
            return
        }
        // The five fields are one report, so a round that *was* answered puts the
        // previous round's «no answer» down as well.
        replyLost = false
        // Off the reply, not off the press: the engine says whether the stop
        // landed in time, and a removal that ran to the end never says stopped.
        removalStopped = removal.cancelled
        let gone = Set(removal.removed)
        groups = groups.compactMap { group in
            let left = group.copies.filter { !gone.contains($0.path) }
            return left.count > 1 ? DuplicateGroup(copies: left) : nil
        }
        // What refused stays in the basket. Emptying it wholesale made a
        // refusal cost the person their selection: fix the permission, come
        // back, and every checkbox has to be found and ticked again. Only the
        // files that actually left are dropped.
        basket = basket.filter { !gone.contains($0) }
        // The numbers, not a sentence about them: `HelmRemovalOutcome` decides
        // what is true from these — a batch where everything refused used to
        // read as a removal with a refusal appended, and one reason was chosen
        // for however many files there were.
        failures = removal.refused
        removedCount = removal.removed.count
        // No sentence for something that did not happen: "Removed 0 files, 0 B
        // freed" is a claim and its own refutation in one line.
        banner = removal.removed.isEmpty
            ? nil
            : DupStr.movedToTrash(Bytes(removal.freedBytes))
    }

    public func dismissBanner() {
        clearRemovalReport()
    }

    /// Nothing on screen about a removal — the shape `DiskViewModel` and
    /// `LeftoversViewModel` already keep, and the fields are read as one report:
    /// clearing three of the four is how a «no answer» came to outlive the press
    /// it was about.
    private func clearRemovalReport() {
        banner = nil
        failures = []
        removedCount = 0
        replyLost = false
        removalStopped = false
    }

    /// Asks the engine to stop the removal in flight, between files.
    ///
    /// Its own command, never `cancel`: that one reaches the search, and a
    /// person stopping a removal must not silently kill a search they started
    /// after it. The press claims nothing — the basket, the groups and `busy`
    /// all stand until the reply says what actually happened, because a stop
    /// that lands after the last file is a removal that ran to the end.
    public func stopRemoval() {
        guard busy else { return }
        Task { await client.send(DuplicatesCommand.stopRemoval) }
    }

    // MARK: - Events

    private func handle(_ event: EngineEvent) async {
        guard DuplicatesEvent(rawValue: event.name) == .progress else { return }
        if let update = try? JSONDecoder().decode(DuplicateProgress.self,
                                                  from: event.payload) {
            progress = update
        }
    }
}
