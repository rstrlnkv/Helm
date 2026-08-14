import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

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

    /// Which search the groups belong to, so a late answer cannot resurrect
    /// itself over a newer one — or over a cancellation, which is a token taken
    /// and dropped. `LatestRequest` (HelmRuntime) is the counter; this view model
    /// and Leftovers' had both written it out by hand.
    private var searches = LatestRequest()

    let vm: ModuleViewModel
    private let client: TransportClient
    private let store: NamespacedStore
    private var eventsTask: Task<Void, Never>?

    /// Search state must outlive the settings page. Settings tears the page down
    /// on every sidebar visit, and this module has no on-disk cache behind it —
    /// hashing a folder is minutes of reading, so losing it to a click is
    /// hostile. One instance per host view model; the page observes it.
    private static var cached: DuplicatesViewModel?
    public static func shared(vm: ModuleViewModel, store: NamespacedStore) -> DuplicatesViewModel {
        // Keyed to the view model it was built against, not merely "exists" —
        // see `DiskViewModel.shared(vm:)`. Turning the module off deallocates
        // the engine while the `LocalTransport` held here survives, and its
        // weakly-captured handler answers every request with empty Data from
        // then on.
        if let cached, cached.vm === vm { return cached }
        let created = DuplicatesViewModel(vm: vm, store: store)
        cached = created
        ModuleUICache.dropWhenDisabled(DuplicatesDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        self.client = TransportClient(vm.transport)
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
        store.set(DuplicatesSettings.guardOfFolder.seal(Data(url.path.utf8)) ?? "",
                  for: SettingGuard.macKey(for: "folder"))
        search()
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
        // A report about a press two screens ago. The sentence it draws is about
        // *this* list being older than the press, and there is about to be a
        // different list.
        replyLost = false
        let mine = searches.take()
        let path = folder.path
        Task {
            // `DuplicateFindings`, the type the engine's `find` answers — the
            // one place these two targets have to agree, and they had stopped:
            // asking here for the bare `[DuplicateGroup]` the engine used to
            // send made every search decode as nothing, which this method reads
            // as a cancellation. It built clean and no fake could see it,
            // because every fake in the test target spells the reply itself.
            let found: DuplicateFindings? = await client.request(DuplicatesCommand.find,
                                                                 encoding: DuplicateSearchRequest(path: path))
            guard searches.isLatest(mine) else { return }
            // Cancelled comes back nil: go back to where we were rather than
            // announce a clean folder nobody finished checking.
            guard let found else { phase = .start; return }
            groups = found.groups
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
        for path in group.paths.dropFirst() where !basket.contains(path) {
            if UserFileScope.isRemovable(path) { basket.append(path) }
        }
    }

    /// Every group's extras, through the same rule the per-group button uses.
    ///
    /// Deliberately a loop over `basketExtras(of:)` rather than its own walk of
    /// the groups: two implementations of "which copy survives" is two answers
    /// to the only question on this page that costs someone a file.
    public func basketAllExtras() {
        for group in groups { basketExtras(of: group) }
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
        defer { busy = false }
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
