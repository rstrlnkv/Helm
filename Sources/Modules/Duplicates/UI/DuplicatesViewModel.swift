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

    /// Bumped whenever the running search stops being the one we want, so a
    /// late answer cannot resurrect itself over a newer one.
    private var generation = 0

    let vm: ModuleViewModel
    private let client: TransportClient
    private let store: NamespacedStore
    private var eventsTask: Task<Void, Never>?

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
        basket.reduce(0) { total, path in
            total + (groups.lazy.compactMap { group in
                group.copies.first { $0.path == path }
            }.first?.bytes ?? 0)
        }
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
            let found: [DuplicateGroup]? = await client.request("find", encoding: ["path": path])
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
        Task { await client.send("cancel", encoding: [String]()) }
        phase = folder == nil ? .start : .start
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

    public func emptyBasket() async {
        let paths = basket
        guard !paths.isEmpty else { return }
        let removal: DuplicateRemoval? = await client.request("trash", encoding: paths)
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
        if removal.refused.isEmpty {
            banner = DupStr.removed(removal.removed.count, Bytes(removal.freedBytes))
        } else {
            let count = DupStr.removedWithFailures(removal.removed.count, removal.refused.count)
            let why = HelmTrash.Result(removed: removal.removed, refused: removal.refused,
                                       freedBytes: removal.freedBytes).principalReason
            // A count with no reason sends the person back to the same folder
            // to try the same thing again.
            // A full stop, not a dash: the reason sentences carry their own
            // em-dash, and "refused 1 — no permission — it may be locked"
            // reads as one run-on clause.
            banner = why.map { "\(count). \(TrashReasonText.sentence($0.rawValue))" } ?? count
        }
    }

    public func dismissBanner() { banner = nil }

    // MARK: - Events

    private func handle(_ event: EngineEvent) async {
        guard event.name == "progress" else { return }
        if let update = try? JSONDecoder().decode(DuplicateProgress.self,
                                                  from: event.payload) {
            progress = update
        }
    }
}
