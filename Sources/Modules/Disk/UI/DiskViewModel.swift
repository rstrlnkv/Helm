import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

/// What the model asks of the engine. A port, so the model's tests hold the
/// engine's place without a walk of anybody's disk in reach.
///
/// The progress and the snapshots of a scan travel to the sink the caller hands
/// over for that one call; the answer is the return value, so there is nothing
/// to subscribe to and no reply that can be lost.
protocol DiskWork: AnyObject, Sendable {
    func mountedVolumes() async -> [VolumeInfo]
    /// Calls back when a disk comes or goes, until the returned token is dropped.
    func watchMounts(_ onChange: @escaping @Sendable () -> Void) -> AnyObject
    func scan(path: String, unattended: Bool,
              updates: (@Sendable (DiskScanUpdate) -> Void)?) async -> ScanResult?
    func cancel()
    func trash(_ paths: [String]) async -> DiskRemoval
    func backgroundScan() async -> ScanReport?
}

extension DiskEngine: DiskWork {}

@MainActor public final class DiskViewModel: ObservableObject {
    enum Phase: Equatable { case start, scanning, result }

    @Published private(set) var phase: Phase = .start
    @Published private(set) var volumes: [VolumeInfo] = []
    /// When `volumes` was last answered; the wedge weighs it against the scan's own reading.
    private var volumesReadAt: Date?
    // Plain internal rather than `private(set)` on the fields below that the
    // basket writes: the setter's audience is still this type — its basket half
    // lives in `DiskViewModel+Basket.swift`, and `private` stops at the file.
    @Published var result: ScanResult?
    @Published private(set) var tick: ScanTick?
    /// Path stack from the scan root to the folder the ring is showing.
    @Published var focusPath: [DiskEntry] = []
    /// Laid-out arcs for the current focus. Cached so a hover, which changes
    /// colours and never geometry, does not relayout every arc.
    @Published private(set) var segments: [RingSegment] = []
    /// True while partial snapshots are still feeding the ring.
    @Published private(set) var live = false
    /// The path we just came up out of, so the ring can fold back into the
    /// wedge that represents it instead of cross-fading. Cleared once the ring
    /// has consumed it.
    @Published var foldingBackFrom: String?
    /// How many levels that fold covers, so the animation can take the time the
    /// distance deserves.
    @Published private(set) var foldingBackLevels: Int = 1
    /// True while a folder deeper than the scan went is being measured.
    @Published private(set) var measuring = false
    /// The scan root's human name: "Macintosh HD", not "/".
    @Published private(set) var rootTitle = ""
    /// What the last scan measured, so "Scan again" measures it again rather
    /// than starting over.
    @Published private(set) var scannedPath: String?
    @Published var basket: [DiskEntry] = []
    /// The verdict of the last removal, «Moved to the Trash — …»; nil until one has run.
    @Published var banner: String?
    /// Paths macOS refused, each with its reason: announcing only what was
    /// freed hides them, and some refusals are ones the person can act on.
    @Published var failures: [HelmTrash.Refusal] = []
    /// How many actually moved. The banner is built before the outcome is
    /// known, so it cannot be asked whether it is true.
    @Published var removedCount = 0

    let work: any DiskWork
    /// Set by `stop()`: the module is switched off or Helm is quitting, and a
    /// press on a page still on screen reaches no work.
    var closed = false
    /// Held so the observers can be taken back out: a view model dropped when
    /// the module is switched off must not be woken by the next disk somebody
    /// plugs in (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
    private var mounts: AnyObject?
    private var appeared = false
    /// Injectable so a test does not read — and overwrite — the person's own
    /// last scan.
    let store: ScanStore
    /// When the current result landed; drives the cache lifetime.
    @Published private(set) var completedAt: Date?
    /// True while showing a tree restored from disk rather than just measured.
    @Published private(set) var restored = false
    /// True while showing a tree the walk never finished — Stop was pressed.
    ///
    /// Every number in such a tree is a **floor**: `TreeBuilder` charges a
    /// directory as its files are found, so a folder the walk had not reached the
    /// bottom of reports what had been counted so far and nothing about the rest.
    /// The screen has to say so, and the tree must never be saved: the module
    /// reopens on whatever the store holds and calls it a measurement.
    @Published private(set) var stopped = false

    /// Whether the tree on screen is a finished measurement, and so worth
    /// keeping for the next launch. The one place that decides it: a wrong yes
    /// presents a partial tree as fact at every launch.
    ///
    /// **Both ways a tree can be unfinished, not only the one with a button.**
    /// `stopped` is false while a walk is running, and a removal can be made
    /// from a live ring (the bar is drawn over the snapshot, dimmed only by `busy`).
    var treeIsComplete: Bool { !stopped && !live }

    /// Names for scans, handed out in order. Two are in flight whenever
    /// somebody drills into a folder the walk has not reached.
    private var lastScanID = 0
    /// The scan the screen belongs to. Everything else — a folder measurement's
    /// answer, the answer to a scan the user has since withdrawn — is not about
    /// what is on screen and is dropped rather than drawn.
    ///
    /// `cancel()` and `newScan()` move this on, which is what fences the call
    /// still suspended inside `scan(path:)`: cancelling is a no-op once the
    /// engine's walk has finished, so the answer arrives either way and, unfenced,
    /// replaces the picker the person has just asked for.
    private var showingScan = 0

    private func nextScanID() -> Int {
        lastScanID += 1
        return lastScanID
    }

    init(work: any DiskWork, store: ScanStore = ScanStore()) {
        self.work = work
        self.store = store
    }

    /// Closes the model; the host calls it before the engine's `deactivate()`, on
    /// the person's switch and on quit. After it the scan, the drill, the
    /// removal, the volume list and the background scan reach no work, and the
    /// mount observers are taken back out.
    func stop() {
        closed = true
        showingScan = nextScanID()
        mounts = nil
    }

    /// What the model does when a page or the tile is first drawn, and what is
    /// re-asked every time.
    ///
    /// **Not in `init`**, which the host runs when the module starts: the saved
    /// scan is an index of every file on the volume and nobody has opened Disk
    /// yet. Once per model: the last scan is read back and the mount observers
    /// registered; every time:
    /// the volume list, because a tile rebuilt on each opening of the panel
    /// would otherwise show the figure from the first.
    func appear() async {
        if !appeared {
            appeared = true
            if !closed { Task { [weak self] in await self?.restoreLastScan() } }
            // **A disk arriving or leaving is a fact only macOS knows**, so the
            // list needs a channel from the port that knows
            // (Architecture/ModulePattern.md § Ports and logic). Re-asking on
            // appearance misses a drive plugged in while the page is open.
            //
            // `loadVolumes` is one call and returns, so the strong hold the task
            // takes on `self` lasts one volume-attributes read, not a `for await`
            // over a stream nothing finishes (Architecture/StateAndLifetime.md § State that outlives a page and ends with its module).
            mounts = closed ? nil : work.watchMounts { [weak self] in
                Task { @MainActor in await self?.loadVolumes() }
            }
        }
        await loadVolumes()
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
        // A folder that no longer exists is not restored: it would draw a
        // breadcrumb and "Scan again" with no ring, no rows and no reason.
        //
        // **Off the main actor**: a saved root can be a network mount nobody
        // holds up any more, and `fileExists` then blocks for the mount's own
        // timeout while the window is being drawn. Through
        // `offTheCooperativePool` and not a detached task, which would still
        // hold one of the pool's few threads. The phase is asked again on the
        // way back, since a scan may have started across the suspension.
        let rootPath = cached.result.root.path
        let rootIsThere = await offTheCooperativePool {
            FileManager.default.fileExists(atPath: rootPath)
        }
        guard phase == .start else { return }
        guard rootIsThere else {
            store.clear()
            return
        }
        result = cached.result
        scannedPath = cached.result.root.path
        // A date ahead of the clock is no reading: kept, it would outrank every
        // list this Mac reads, so the wedge would disagree with the tile, and
        // every re-save would carry it on. It is taken as no newer than the list
        // already read, and failing that as now.
        let now = Date()
        completedAt = cached.savedAt <= now ? cached.savedAt : (volumesReadAt ?? now)
        restored = true
        stopped = false
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
    static let cacheLifetime: TimeInterval = 86_400
    func expireIfStale(now: Date = Date()) {
        guard phase == .result, !live, let completedAt,
              now.timeIntervalSince(completedAt) > Self.cacheLifetime else { return }
        newScan()
    }

    /// A walk is running: the volume's, or one folder's measured on demand. The
    /// header's spinner asks this, not `live` or `measuring`, which each also
    /// carry another job (snapshot repaints, the second-walk guard).
    var walking: Bool { live || measuring }

    var focus: DiskEntry? { focusPath.last }
    var basketBytes: Int { basket.map(\.bytes).saturatingSum() }
    /// Whether the page draws the bar under the ring — for a basket waiting to
    /// be emptied, or for the report of an emptying that has happened.
    ///
    /// Here rather than in the page because it is the condition three exits have
    /// to satisfy, and a copy of it in the view is a copy that can be satisfied
    /// while the screen still shows the bar.
    var showsRemovalBar: Bool { !basket.isEmpty || banner != nil }

    func loadVolumes() async {
        guard !closed else { return }
        let list = await work.mountedVolumes()
        volumes = list
        volumesReadAt = Date()
        // **The ring is laid out against this list, which can arrive after it.**
        // `recomputeSegments` asks `isVolumeScan`, a test of `scannedPath`
        // against `volumes`, and `restoreLastScan` draws before the list is
        // read; without this a restored volume's free part is left out of every
        // angle. Here rather than at the restore, because a disk mounted under
        // an open ring arrives by the same door.
        recomputeSegments()
    }

    func scan(path: String) async {
        guard !closed else { return }
        // "/" is a path, not a name; the volume list knows what to call it.
        rootTitle = Self.title(for: path, volumes: volumes)
        scannedPath = path
        restored = false
        stopped = false
        phase = .scanning
        live = true
        tick = nil
        // A new tree is arriving, so nothing about the old one belongs to the
        // screen. Here rather than in each caller: it keeps "the basket only
        // holds entries from the tree on screen", and this is the one door
        // where a tree is replaced.
        basket = []
        clearRemovalReport()
        // No measurement is complete while one runs; the old date would make
        // `expireIfStale` judge the new tree by the old tree's age.
        completedAt = nil
        let mine = nextScanID()
        showingScan = mine
        // The updates travel on a stream made for this call and are drained here
        // while the answer is awaited, so they are applied on the main actor and
        // all of them before the answer is.
        let (updates, sink) = AsyncStream.makeStream(of: DiskScanUpdate.self)
        let work = self.work
        async let answer: ScanResult? = {
            defer { sink.finish() }
            return await work.scan(path: path, unattended: false, updates: { sink.yield($0) })
        }()
        for await update in updates { apply(update, of: mine) }
        let scan = await answer
        // Withdrawn while this was suspended: the screen has moved on and none
        // of what follows is about it.
        guard mine == showingScan else { return }
        live = false
        // The count is the walk's; a folder measured after this one must not
        // draw it beside its own spinner.
        tick = nil
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

    /// True when what was scanned is a whole volume rather than some folder on
    /// one. Free space only means something for the first.
    private var isVolumeScan: Bool {
        guard let path = scannedPath else { return false }
        return volumes.contains { $0.path == path }
    }

    /// Measure the same target again. A restored tree carries its root but not
    /// the path it was scanned from, so the root is the fallback.
    ///
    /// Refused while a walk or a removal is running, as the button is dimmed:
    /// under a folder measurement a second scan would leave `measuring` set for
    /// good, under a removal it would replace the tree the reply lands on.
    func rescan() async {
        guard !walking, !busy else { return }
        guard let path = scannedPath ?? result?.root.path else { newScan(); return }
        await scan(path: path)
    }

    /// Stop. Keeps what the walk had measured, and says that is what it is.
    ///
    /// The basket only ever holds entries from the tree on screen, and the page
    /// draws its bar outside `switch dvm.phase`. Stop keeps the tree, so the
    /// basket stays with it; a path back to the volume picker clears the basket.
    func cancel() {
        // Nothing in flight belongs to the screen any more. The engine may
        // already have finished walking, in which case the call below
        // changes nothing and only this line keeps the answer off the screen.
        showingScan = nextScanID()
        if !closed { work.cancel() }
        let wasWalking = live
        // The other walk this button is drawn over. Put down here rather than by
        // `measureAndDrill`'s own `defer`, which cannot run until the engine
        // answers a request the person has just withdrawn.
        let wasMeasuring = measuring
        live = false
        measuring = false
        tick = nil
        // There is a tree worth keeping only when a walk was running and had
        // reported at least one snapshot. `newScan()` and a Stop before the first
        // partial both land on the volume picker, and a finished tree is never
        // marked stopped.
        guard wasWalking || wasMeasuring, phase == .result, result != nil else {
            phase = .start
            basket = []
            clearRemovalReport()
            return
        }
        // **Only a stopped *walk* leaves floors.** A withdrawn measurement grafts
        // nothing, so the tree is the one the volume walk finished and marking it
        // stopped would put «a folder may hold more» over figures that are totals.
        if wasWalking { stopped = true }
    }

    /// Nothing on screen about a removal. The three fields are read as one report,
    /// so they are put down together — a silence left standing over a fresh tree
    /// is a sentence about a press that belonged to another screen.
    func clearRemovalReport() {
        banner = nil
        failures = []
        removedCount = 0
    }

    /// Refused while a removal runs, like the button: the volume picker would
    /// replace the tree the reply is about to land on.
    func newScan() {
        guard !busy else { return }
        cancel()
        store.clear()
        phase = .start
        result = nil
        completedAt = nil
        restored = false
        stopped = false
        // Stated here rather than left to `cancel()`, which may keep the tree:
        // this door takes the tree away, so it leaves nothing under the picker.
        basket = []
        clearRemovalReport()
        focusPath = []
        segments = []
        Task { await loadVolumes() }
    }

    /// Advice entries ready for the basket.
    func entry(for advice: DiskAdvice) -> DiskEntry {
        DiskEntry(name: advice.name, path: advice.path, bytes: advice.bytes,
                  isDirectory: false, noAccess: false, children: [])
    }

    /// Opens a folder anywhere in the drawn rings, not only the innermost one,
    /// since every drawn arc highlights on hover. The whole chain is appended,
    /// so a jump of two levels still leaves breadcrumbs for each.
    func drill(into path: String) {
        guard let focus else { return }
        let chain = DiskFocus.chain(from: focus, to: path)
        guard let last = chain.last, last.isDirectory else { return }
        // A folder with no children is the depth the scan stopped at, not an
        // empty one: it is measured now and grafted in. While the scan still
        // runs it means not walked yet, and the walk in flight will bring it in;
        // a second walk would only compete for the disk and be overwritten.
        guard !last.children.isEmpty else {
            if !live { Task { await measureAndDrill(into: path) } }
            return
        }
        focusPath.append(contentsOf: chain)
        recomputeSegments()
    }

    /// Scans one folder and splices the result into the tree, then opens it.
    private func measureAndDrill(into path: String) async {
        guard !measuring, !closed else { return }
        measuring = true
        // Asks for no updates: this scan's snapshots are a folder, and the ring
        // is a volume. Only its final tree is wanted, and only if the tree it is
        // grafted into is still the one on screen.
        let owner = showingScan
        // Against `owner`, so a withdrawn measurement arriving late cannot put
        // down the flag of the one that replaced it — Stop clears it and moves
        // `showingScan` on.
        defer { if owner == showingScan { measuring = false } }
        let scan = await work.scan(path: path, unattended: false, updates: nil)
        guard owner == showingScan, let scan, let current = result else { return }
        let grafted = DiskTreeSplice.replacing(path, with: scan.root, in: current.root)
        // The advice stays: it describes the volume, not the folder just
        // measured, and recomputing it from one branch would narrow it.
        let measured = ScanResult(root: grafted, freeBytes: current.freeBytes,
                                  filesScanned: current.filesScanned, seconds: current.seconds,
                                  advice: current.advice)
        result = measured
        // Rebuild the focus from paths: the entries in `focusPath` are values
        // from the tree that just changed underneath them.
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: grafted)
        guard let focus else { return }
        focusPath.append(contentsOf: DiskFocus.chain(from: focus, to: path))
        recomputeSegments()
        // The rule `emptyBasket` keeps: a stopped tree stays unsaved after a
        // graft, since everything around the measured folder is still a floor.
        if treeIsComplete { store.saveDetached(measured, at: completedAt ?? Date()) }
    }

    func back() {
        guard focusPath.count > 1 else { return }
        foldingBackLevels = 1
        foldingBackFrom = focusPath.last?.path
        focusPath.removeLast()
        recomputeSegments()
    }

    func jump(to index: Int) {
        guard focusPath.indices.contains(index), index < focusPath.count - 1 else { return }
        // There is always exactly one wedge to fold into, however far the jump:
        // the child of the level being returned to that leads to where we were.
        foldingBackLevels = focusPath.count - 1 - index
        foldingBackFrom = focusPath[index + 1].path
        focusPath = Array(focusPath.prefix(index + 1))
        recomputeSegments()
    }

    /// The name shown for an entry: the scan root carries the volume's name,
    /// and macOS's own folders are named the way Finder names them.
    func displayName(for entry: DiskEntry) -> String {
        if entry.path == focusPath.first?.path, !rootTitle.isEmpty { return rootTitle }
        return Self.folderName(for: entry.path) ?? entry.name
    }

    /// Localized name for a macOS folder, or nil when it has none.
    static func folderName(for path: String) -> String? {
        SystemFolderNames.display(path: path, home: NSHomeDirectory(),
                                  language: AppLanguage.current.rawValue)
    }

    // The basket and the removal it feeds live in `DiskViewModel+Basket.swift`,
    // the one section that reads whole on its own.

    /// A removal is running. The page dims what would start a second one.
    /// Stored here because an extension cannot hold storage; set only by
    /// `emptyBasket`, one file over.
    @Published var busy = false

    // MARK: - Updates

    /// One thing the scan `scan` said while it ran. Dropped unless that scan is
    /// still the one the screen belongs to: a snapshot of a walk withdrawn since
    /// would otherwise repaint the ring with a tree nobody asked for.
    private func apply(_ update: DiskScanUpdate, of scan: Int) {
        guard scan == showingScan else { return }
        switch update {
        case .progress(let progress):
            tick = progress
        case .partial(let snapshot):
            guard live else { return }
            result = snapshot
            focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: snapshot.root)
            phase = .result
            recomputeSegments()
        }
    }

    /// The unattended walk the host's scheduler asks for, answered by return. A
    /// stopped model answers nil, which the scheduler reads as no answer.
    func backgroundScan() async -> ScanReport? {
        guard !closed else { return nil }
        return await work.backgroundScan()
    }

    // MARK: - Layout

    /// The layout the ring is about to become, computed before the animation
    /// starts. Folding into "other" is decided against the parent's total in the
    /// current layout and the folder's own total in the next, so the two
    /// disagree; animating *towards* this makes the last frame the first frame
    /// after it by construction.
    func ringLayout(forFocusAt path: String) -> [RingSegment] {
        guard let root = result?.root,
              let node = path == root.path ? root : DiskFocus.chain(from: root, to: path).last
        else { return [] }
        // Free space belongs to a volume, not to a folder — the same rule
        // `recomputeSegments` applies, and a drill always lands below the root.
        return RingLayout.layout(focus: Self.node(from: node), path: node.path,
                                 depthLevels: RingView.visibleRings + 1, freeBytes: 0)
    }

    func recomputeSegments() {
        guard let focus else { segments = []; return }
        // Free space is a fact about a volume, not about a folder: on a folder
        // scan it would fill the circle and fold every file into "other".
        // The wedge draws the fresher of two readings of the same volume: the
        // list the tile beside it draws (`volumesReadAt`) and the free space the
        // scan read at the end of its walk (`completedAt`, which a restore sets
        // to the day the scan was saved). «Scan again» refreshes only the second;
        // a restored scan is older than any list read since. A tie goes to the list.
        let live = volumes.first { $0.path == scannedPath }?.freeBytes
        let scanIsNewer = volumesReadAt.map { read in completedAt.map { $0 > read } ?? false } ?? true
        let free = focusPath.count == 1 && isVolumeScan
            ? (scanIsNewer ? (result?.freeBytes ?? live) : live) ?? 0 : 0
        // One level deeper than the ring draws: the spare is invisible until a
        // drill starts, and it is what the new outermost ring slides in from.
        // See `RingView.visibleRings`.
        segments = RingLayout.layout(focus: Self.node(from: focus), path: focus.path,
                                     depthLevels: RingView.visibleRings + 1, freeBytes: free)
    }

    /// RingLayout works on the engine's node type; the UI holds the
    /// flattened DiskEntry snapshot, so the focused subtree is rebuilt for it.
    ///
    /// The entry's path is handed to `layout` separately: a `DiskNode` keeps
    /// only the name, and the layout composes the paths back down from the
    /// focus, so the basket and `UserFileScope` see the entries' own paths.
    /// `noAccess` and `isFolded` are carried for the unreadable and folded wedges.
    private static func node(from entry: DiskEntry) -> DiskNode {
        DiskNode(name: entry.name, bytes: entry.bytes,
                 isDirectory: entry.isDirectory,
                 children: entry.children.map(node(from:)),
                 isFolded: entry.isFolded, noAccess: entry.noAccess)
    }

}
