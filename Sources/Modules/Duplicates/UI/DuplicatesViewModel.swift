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
    @Published public private(set) var progress: DuplicateProgress?
    @Published public var basket: [String] = []
    @Published public private(set) var banner: String?
    /// Paths macOS refused, with their own reasons — see `DiskViewModel`. A
    /// reason chosen for the whole batch describes at most one of them.
    @Published public private(set) var failures: [HelmTrash.Refusal] = []
    /// How many actually moved. `HelmRemovalOutcome` decides what to say from
    /// this and `failures`: a sentence cannot be asked whether it is true.
    @Published public private(set) var removedCount = 0

    /// Bumped whenever the running search stops being the one we want, so a
    /// late answer cannot resurrect itself over a newer one.
    private var generation = 0

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

    /// What emptying the basket would free: each ticked copy's own figure. The
    /// group's size is the copy that stays, and quoting it once per ticked path
    /// promised a clone's nothing for a real file, or the reverse.
    public var basketBytes: Int {
        basket.reduce(0) { $0 + bytes(of: $1) }
    }

    /// One copy's own figure. A group's size is the copy that stays, so quoting
    /// it against a path promised a clone's nothing for a real file, or the
    /// reverse — the basket bar and the menu under it both ask this.
    public func bytes(of path: String) -> Int {
        groups.lazy.compactMap { group in
            group.copies.first { $0.path == path }
        }.first?.bytes ?? 0
    }

    public var wastedBytes: Int { groups.reduce(0) { $0 + $1.wasted } }

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
        generation += 1
        let mine = generation
        let path = folder.path
        Task {
            let found: [DuplicateGroup]? = await client.request(DuplicatesCommand.find,
                                                                 encoding: DuplicateSearchRequest(path: path))
            guard mine == generation else { return }
            // Cancelled comes back nil: go back to where we were rather than
            // announce a clean folder nobody finished checking.
            guard let found else { phase = .start; return }
            groups = found
            phase = .result
        }
    }

    public func cancel() {
        generation += 1
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
    public func clearBasket() {
        basket.removeAll()
    }

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
        let removal: DuplicateRemoval? = await client.request(DuplicatesCommand.trash, encoding: plans)
        guard let removal else { return }
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
        banner = nil
        failures = []
        removedCount = 0
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
