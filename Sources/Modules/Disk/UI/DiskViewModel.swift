import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

@MainActor public final class DiskViewModel: ObservableObject {
    public enum Phase: Equatable { case start, scanning, result }

    @Published public private(set) var phase: Phase = .start
    @Published public private(set) var volumes: [VolumeInfo] = []
    @Published public private(set) var result: ScanResult?
    @Published public private(set) var tick: ScanTick?
    /// Path stack from the scan root to the folder the ring is showing.
    @Published public private(set) var focusPath: [DiskEntry] = []
    /// Laid-out arcs for the current focus. Cached deliberately: recomputing
    /// layout in the view's body meant a full O(n) relayout on every hover
    /// frame — hovering only changes colours, never geometry.
    @Published public private(set) var segments: [RingSegment] = []
    /// True while partial snapshots are still feeding the ring.
    @Published public private(set) var live = false
    /// Which way the last navigation went — the ring's transition mirrors it.
    /// The path we just came up out of, so the ring can fold back into the
    /// wedge that represents it instead of cross-fading. Cleared once the ring
    /// has consumed it.
    @Published public var foldingBackFrom: String?
    /// True while a folder deeper than the scan went is being measured.
    @Published public private(set) var measuring = false
    /// The scan root's human name: "Macintosh HD", not "/".
    @Published public private(set) var rootTitle = ""
    /// What the last scan measured, so it can be measured again. Without it
    /// "Scan again" had nothing to scan and could only start over — it emptied
    /// the screen and showed the volume picker, which is not what it says.
    @Published public private(set) var scannedPath: String?
    @Published public var basket: [DiskEntry] = []
    /// The second look: identical files under the focused folder. nil means
    @Published public private(set) var banner: String?
    /// Paths macOS refused. Announcing only what was freed hides these.
    /// With reasons. This was a list of bare paths, and the page printed the
    /// same sentence against every one of them — including the ones macOS
    /// refused for a reason the person could have acted on.
    @Published public private(set) var failures: [HelmTrash.Refusal] = []
    /// How many actually moved. The banner is built before the outcome is
    /// known, so it cannot be asked whether it is true.
    @Published public private(set) var removedCount = 0

    private let client: TransportClient
    private let vm: ModuleViewModel
    private var eventsTask: Task<Void, Never>?
    /// Injectable so a test does not read — and overwrite — the person's own
    /// last scan.
    private let store: ScanStore
    /// When the current result landed; drives the cache lifetime.
    @Published public private(set) var completedAt: Date?
    /// True while showing a tree restored from disk rather than just measured.
    @Published public private(set) var restored = false

    /// Names for scans, handed out in order. Two are in flight whenever
    /// somebody drills into a folder the walk has not reached, and both talk on
    /// one transport.
    private var lastScanID = 0
    /// The scan the screen belongs to. Everything else — a folder measurement's
    /// snapshots, the answer to a scan the user has since withdrawn — is not
    /// about what is on screen and is dropped rather than drawn.
    ///
    /// `cancel()` and `newScan()` move this on, which is what fences the
    /// request still suspended inside `scan(path:)`: the "cancel" command is a
    /// no-op once the engine's walk has finished, so the answer arrives either
    /// way and used to replace the picker the person had just asked for.
    private var showingScan = 0

    private func nextScanID() -> Int {
        lastScanID += 1
        return lastScanID
    }

    /// Scan state must outlive the settings page — switching modules recreates
    /// the page, and losing a minute-long scan to a sidebar click is hostile.
    /// One instance for the app's lifetime; the page observes it.
    private static var cached: DiskViewModel?
    public static func shared(vm: ModuleViewModel) -> DiskViewModel {
        // Keyed to the view model it was built against, not merely "exists".
        // Turning the module off deallocates the engine; the LocalTransport
        // held here survives, and its handler — captured weakly — answers every
        // request with empty Data from then on. `ModuleHost.enable` makes a new
        // view model, so this is the signal that the old one is talking to a
        // corpse: without it the page came back to a volume list that was
        // silently always empty, with no error, until the app restarted.
        if let cached, cached.vm === vm { return cached }
        let created = DiskViewModel(vm: vm)
        cached = created
        // Switching the module off drops the tree: a scan of a whole volume is
        // hundreds of megabytes of nodes that nobody can reach afterwards. The
        // on-disk cache still holds the scan, so this drops the copy in memory,
        // not the result.
        ModuleUICache.dropWhenDisabled("disk") { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel, store: ScanStore = ScanStore()) {
        self.vm = vm
        self.store = store
        client = TransportClient(vm.transport)
        // The VM owns the event loop, not the page: partial snapshots keep
        // building the tree even while the user is on another module.
        eventsTask = Task { [weak self] in await self?.observeEvents() }
        Task { [weak self] in await self?.restoreLastScan() }
    }

    /// A whole disk takes a minute to measure. Reopening Helm should not spend
    /// it again: the last tree is read back from disk and shown at once, with
    /// its age on the toolbar so nobody mistakes it for a fresh measurement.
    private func restoreLastScan() async {
        guard let cached = await store.loadDetached(),
              Date().timeIntervalSince(cached.savedAt) <= Self.cacheLifetime else { return }
        // A scan may have started while the file was being read; the fresh one
        // wins.
        guard phase == .start else { return }
        // And a memory of a folder that no longer exists is not worth showing.
        // Restoring one put the module on a screen with a breadcrumb, a "Scan
        // again" button and nothing else at all — no ring, no rows, no reason
        // given — and the only way out was a back arrow that did not look like
        // one. Folders get scanned and then deleted; volumes do not.
        guard FileManager.default.fileExists(atPath: cached.result.root.path) else {
            await store.clear()
            return
        }
        result = cached.result
        scannedPath = cached.result.root.path
        completedAt = cached.savedAt
        restored = true
        rootTitle = ""
        focusPath = [cached.result.root]
        phase = .result
        recomputeSegments()
        Task { await resolveRootTitle(for: cached.result.root.path) }
    }

    private func resolveRootTitle(for path: String) async {
        if volumes.isEmpty { await loadVolumes() }
        rootTitle = Self.title(for: path, volumes: volumes)
    }

    private static func title(for path: String, volumes: [VolumeInfo]) -> String {
        volumes.first { $0.path == path }?.name
            ?? ((path as NSString).lastPathComponent.isEmpty ? path
                : (path as NSString).lastPathComponent)
    }

    /// A day-old tree is a guess, not a measurement. Called on page appear.
    public static let cacheLifetime: TimeInterval = 86_400
    public func expireIfStale(now: Date = Date()) {
        guard phase == .result, !live, let completedAt,
              now.timeIntervalSince(completedAt) > Self.cacheLifetime else { return }
        newScan()
    }

    public var focus: DiskEntry? { focusPath.last }
    public var basketBytes: Int { basket.reduce(0) { $0 + $1.bytes } }

    public func loadVolumes() async {
        volumes = await client.request("volumes") ?? []
    }

    public func scan(path: String) async {
        // "/" is a path, not a name; the volume list knows what to call it.
        rootTitle = Self.title(for: path, volumes: volumes)
        scannedPath = path
        restored = false
        phase = .scanning
        live = true
        tick = nil
        banner = nil
        let mine = nextScanID()
        showingScan = mine
        let scan: ScanResult? = await client.request("scan",
                                                     encoding: ScanRequest(path: path, scan: mine))
        // Withdrawn while this was suspended: the screen has moved on and none
        // of what follows is about it.
        guard mine == showingScan else { return }
        live = false
        guard let scan else {                    // cancelled
            phase = .start
            return
        }
        result = scan
        completedAt = Date()
        store.saveDetached(scan, at: Date())
        // The user may have drilled into a partial tree; find the same spot in
        // the final one instead of yanking them back to the root.
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: scan.root)
        phase = .result
        recomputeSegments()
    }

    /// Measure the same target again — what the button has always said.
    ///
    /// A restored tree carries its root but not the path it was scanned from,
    /// so that is the fallback: the same place, either way.
    /// True when what was scanned is a whole volume rather than some folder on
    /// one. Free space only means something for the first.
    private var isVolumeScan: Bool {
        guard let path = scannedPath else { return false }
        return volumes.contains { $0.path == path }
    }

    public func rescan() async {
        guard let path = scannedPath ?? result?.root.path else { newScan(); return }
        basket = []
        banner = nil
        failures = []
        await scan(path: path)
    }

    public func cancel() {
        // Nothing in flight belongs to the screen any more. The engine may
        // already have finished walking, in which case the command below
        // changes nothing and only this line keeps the answer off the screen.
        showingScan = nextScanID()
        Task { await client.send("cancel", encoding: [String]()) }
        live = false
        phase = .start
    }

    public func newScan() {
        cancel()
        store.clear()
        phase = .start
        result = nil
        completedAt = nil
        restored = false
        focusPath = []
        segments = []
        basket = []
        banner = nil
        Task { await loadVolumes() }
    }

    /// Advice entries ready for the basket.
    public func entry(for advice: DiskAdvice) -> DiskEntry {
        DiskEntry(name: advice.name, path: advice.path, bytes: advice.bytes,
                  isDirectory: false, noAccess: false, children: [])
    }

    /// Opens a folder anywhere in the drawn rings, not only the innermost one.
    ///
    /// The ring paints three levels at once, and this used to accept a direct
    /// child only — so every arc past the first ring highlighted on hover and
    /// then did nothing. The whole chain is appended, so jumping two levels
    /// still leaves breadcrumbs that describe where you are.
    public func drill(into path: String) {
        guard let focus else { return }
        let chain = DiskFocus.chain(from: focus, to: path)
        guard let last = chain.last, last.isDirectory else { return }
        // A folder with no children is not empty — it is the depth the scan
        // stopped at. Measure it now and graft it in, or the ring simply ends
        // six levels down with no way to say why.
        //
        // Except while the scan is still running, where it means something
        // else: not walked yet. The walk in flight will bring it in, and a
        // second walk of the same folder competes with the first for the same
        // disk only to have its answer replaced by the next snapshot.
        guard !last.children.isEmpty else {
            if !live { Task { await measureAndDrill(into: path) } }
            return
        }
        focusPath.append(contentsOf: chain)
        recomputeSegments()
    }

    /// Scans one folder and splices the result into the tree, then opens it.
    private func measureAndDrill(into path: String) async {
        guard !measuring else { return }
        measuring = true
        defer { measuring = false }
        // A name of its own, and deliberately not the one the screen is
        // showing: this scan's snapshots are a folder, and the ring is a
        // volume. Only its final tree is wanted, and only if the tree it is
        // grafted into is still the one on screen.
        let owner = showingScan
        let scan: ScanResult? = await client.request("scan",
                                                     encoding: ScanRequest(path: path,
                                                                           scan: nextScanID()))
        guard owner == showingScan, let scan, let current = result else { return }
        let grafted = DiskTreeSplice.replacing(path, with: scan.root, in: current.root)
        // The advice stays: it describes the volume, not the folder just
        // measured, and recomputing it from one branch would narrow it.
        result = ScanResult(root: grafted, freeBytes: current.freeBytes,
                            filesScanned: current.filesScanned, seconds: current.seconds,
                            advice: current.advice)
        // Rebuild the focus from paths: the entries in `focusPath` are values
        // from the tree that just changed underneath them.
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: grafted)
        guard let focus else { return }
        focusPath.append(contentsOf: DiskFocus.chain(from: focus, to: path))
        recomputeSegments()
        store.saveDetached(result!, at: completedAt ?? Date())
    }

    public func back() {
        guard focusPath.count > 1 else { return }
        foldingBackFrom = focusPath.last?.path
        focusPath.removeLast()
        recomputeSegments()
    }

    public func jump(to index: Int) {
        guard focusPath.indices.contains(index), index < focusPath.count - 1 else { return }
        // Only a single step folds back into its wedge; jumping several levels
        // has no one wedge to fold into.
        foldingBackFrom = index == focusPath.count - 2 ? focusPath.last?.path : nil
        focusPath = Array(focusPath.prefix(index + 1))
        recomputeSegments()
    }

    /// The name shown for an entry: the scan root carries the volume's name,
    /// and macOS's own folders are named the way Finder names them.
    public func displayName(for entry: DiskEntry) -> String {
        if entry.path == focusPath.first?.path, !rootTitle.isEmpty { return rootTitle }
        return Self.folderName(for: entry.path) ?? entry.name
    }

    /// Localized name for a macOS folder, or nil when it has none.
    public static func folderName(for path: String) -> String? {
        SystemFolderNames.display(path: path, home: NSHomeDirectory(),
                                  language: AppLanguage.current.rawValue)
    }

    // MARK: - Basket

    public func toggleBasket(_ entry: DiskEntry) {
        if let index = basket.firstIndex(where: { $0.path == entry.path }) {
            basket.remove(at: index)
        } else if UserFileScope.isRemovable(entry.path) {
            basket.append(entry)
        }
    }

    public func isBasketed(_ entry: DiskEntry) -> Bool {
        basket.contains { $0.path == entry.path }
    }

    public func emptyBasket() async {
        let paths = basket.map(\.path)
        guard !paths.isEmpty else { return }
        let removal: DiskRemoval? = await client.request("trash", encoding: paths)
        let freed = removal?.freedBytes ?? 0
        failures = removal?.refused ?? []
        removedCount = removal?.removed.count ?? 0
        banner = DkStr.removedFreed(Bytes(freed))
        basket = []
        // Re-walking the disk to learn what we already know — those paths are
        // gone, and by how much — costs a minute on a full volume. Apply the
        // deletion to the tree in hand instead.
        guard let previous = result, let removed = removal?.removed, !removed.isEmpty else { return }
        let pruned = DiskTreePrune.removing(paths: removed, from: previous.root)
        let updated = ScanResult(root: pruned, freeBytes: previous.freeBytes + freed,
                                 filesScanned: previous.filesScanned, seconds: previous.seconds,
                                 advice: previous.advice.filter { advice in
                                     !removed.contains { advice.path == $0
                                         || advice.path.hasPrefix($0 + "/") }
                                 })
        result = updated
        store.saveDetached(updated, at: completedAt ?? Date())
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: pruned)
        recomputeSegments()
    }

    // MARK: - Events

    private func observeEvents() async {
        for await event in vm.transport.events {
            switch event.name {
            case "progress":
                if let update = try? JSONDecoder().decode(ScanTick.self, from: event.payload),
                   update.scan == showingScan {
                    tick = update
                }
            case "partial":
                // Whose snapshot this is decides everything: a folder
                // measurement's tree drawn as the volume collapses the focus,
                // keeps the volume's name and title, and draws the volume's
                // free space against a folder.
                guard live,
                      let snapshot = try? JSONDecoder().decode(PartialScan.self,
                                                               from: event.payload),
                      snapshot.scan == showingScan
                else { continue }
                result = snapshot.result
                focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: snapshot.result.root)
                phase = .result
                recomputeSegments()
            default:
                continue
            }
        }
    }


    // MARK: - Layout

    private func recomputeSegments() {
        guard let focus else { segments = []; return }
        // Free space is a fact about a volume, not about a folder. On a folder
        // scan it was still drawn: 102 GB of free disk against 6 MB of content
        // made one pale wedge worth 99.99% of the circle, and every file in the
        // folder fell under the minimum visible angle and was folded into
        // "other". The ring came out a flat grey disc that said nothing about
        // the folder it was measuring.
        let free = focusPath.count == 1 && isVolumeScan ? (result?.freeBytes ?? 0) : 0
        // One level deeper than the ring draws: the spare is invisible until a
        // drill starts, and it is what the new outermost ring slides in from.
        // See `RingUnfold.opacity(isSpare:)`.
        segments = RingLayout.layout(focus: Self.node(from: focus),
                                     depthLevels: RingView.visibleRings + 1, freeBytes: free)
    }

    /// RingLayout works on the engine's node type; the UI holds the
    /// transported snapshot, so the focused subtree is rebuilt for it.
    private static func node(from entry: DiskEntry) -> DiskNode {
        DiskNode(name: entry.name, path: entry.path, bytes: entry.bytes,
                 isDirectory: entry.isDirectory,
                 children: entry.children.map(node(from:)))
    }

}
