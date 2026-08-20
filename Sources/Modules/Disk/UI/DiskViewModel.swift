import AppKit
import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine

@MainActor public final class DiskViewModel: ObservableObject {
    public enum Phase: Equatable { case start, scanning, result }

    @Published public private(set) var phase: Phase = .start
    @Published public private(set) var volumes: [VolumeInfo] = []
    // `internal(set)` rather than `private(set)` on the fields below that the
    // basket writes: the setter's audience is still this type — its basket half
    // lives in `DiskViewModel+Basket.swift`, and `private` stops at the file.
    @Published public internal(set) var result: ScanResult?
    @Published public private(set) var tick: ScanTick?
    /// Path stack from the scan root to the folder the ring is showing.
    @Published public internal(set) var focusPath: [DiskEntry] = []
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
    /// How many levels that fold covers, so the animation can take the time the
    /// distance deserves.
    @Published public private(set) var foldingBackLevels: Int = 1
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
    @Published public internal(set) var banner: String?
    /// Paths macOS refused. Announcing only what was freed hides these.
    /// With reasons. This was a list of bare paths, and the page printed the
    /// same sentence against every one of them — including the ones macOS
    /// refused for a reason the person could have acted on.
    @Published public internal(set) var failures: [HelmTrash.Refusal] = []
    /// How many actually moved. The banner is built before the outcome is
    /// known, so it cannot be asked whether it is true.
    @Published public internal(set) var removedCount = 0
    /// The removal whose reply never came back.
    ///
    /// A flag rather than a count, and that is the whole point: what a lost reply
    /// knows is nothing, so it must not be expressible as a number. It is read
    /// with the three fields above as one report — see `emptyBasket`.
    @Published public internal(set) var replyLost = false

    let client: TransportClient
    private let vm: ModuleViewModel
    private var eventsTask: Task<Void, Never>?
    /// Held so the observers can be taken back out: a view model dropped when
    /// the module is switched off must not be woken by the next disk somebody
    /// plugs in (ARCHITECTURE.md § An observer outlives the thing it points at).
    private var mounts: MountWatch?
    /// Injectable so a test does not read — and overwrite — the person's own
    /// last scan.
    let store: ScanStore
    /// When the current result landed; drives the cache lifetime.
    @Published public private(set) var completedAt: Date?
    /// True while showing a tree restored from disk rather than just measured.
    @Published public private(set) var restored = false
    /// True while showing a tree the walk never finished — Stop was pressed.
    ///
    /// Every number in such a tree is a **floor**: `TreeBuilder` charges a
    /// directory as its files are found, so a folder the walk had not reached the
    /// bottom of reports what had been counted so far and nothing about the rest.
    /// The screen has to say so, and the tree must never be saved: the module
    /// reopens on whatever the store holds and calls it a measurement.
    @Published public private(set) var stopped = false

    /// Whether the tree on screen is a finished measurement, and so worth
    /// keeping for the next launch. The one place that decides it, because the
    /// consequence of getting it wrong is a partial tree presented as fact at
    /// every launch — the failure "Choose another…" exists to give a way out of.
    ///
    /// **Both ways a tree can be unfinished, not only the one with a button.**
    /// This was `!stopped` alone, and `stopped` is false while a walk is
    /// *running* — so it answered yes about a tree still being built, which is
    /// every removal made from a live ring (the bar is drawn over the snapshot
    /// and dimmed only by `busy`).
    public var treeIsComplete: Bool { !stopped && !live }

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
        ModuleUICache.dropWhenDisabled(DiskDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel, store: ScanStore = ScanStore()) {
        self.vm = vm
        self.store = store
        client = TransportClient(vm.transport)
        // The VM owns the event loop, not the page: partial snapshots keep
        // building the tree even while the user is on another module.
        //
        // The stream is captured here and `self` re-acquired per event, rather
        // than handed to an instance method: `await self?.observeEvents()`
        // resolves the weak capture once and then needs `self` for the whole
        // call, and that call is a `for await` over a stream nothing finishes.
        // It held the view model — scan tree and all — for the life of the app,
        // so `ModuleUICache.dropWhenDisabled` dropped the cache and freed
        // nothing.
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }   // dropped: stop consuming
                await self.handle(event)
            }
        }
        Task { [weak self] in await self?.restoreLastScan() }
        // **A disk arriving or leaving is a fact only macOS knows.** Without
        // this the volume list is a local copy of a live external fact with no
        // channel from the port that knows — the family CLAUDE.md names. The
        // page re-asked on every appearance and so covered it up; the panel tile
        // is rebuilt rather than reappearing, and a drive plugged in while the
        // page is open never showed up in the picker at all.
        //
        // `loadVolumes` is one request and returns, so the strong hold the task
        // takes on `self` once it starts lasts as long as a `statfs` — not the
        // trap CLAUDE.md records for a `for await` over a stream nothing
        // finishes.
        mounts = MountWatch { [weak self] in
            Task { @MainActor in await self?.loadVolumes() }
        }
    }

    /// Ends the event loop, which unregisters the transport subscriber. The
    /// mount observers go out with `mounts`, whose own lifetime is the
    /// subscription — Swift 6 refuses a nonisolated `deinit` reading this
    /// object's state, and a teardown that cannot be written is a teardown
    /// nobody will write.
    ///
    /// Cancelling is what makes `AsyncStream` finish its iteration and fire
    /// `onTermination`; the `guard let self` above only notices at the next
    /// event, and a module that emits rarely would keep its subscriber until
    /// one arrived.
    deinit { eventsTask?.cancel() }

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
        //
        // **Off the main actor**, because the last thing a saved root can be is a
        // network mount nobody is holding up any more: `fileExists` then blocks
        // for the mount's own timeout, and this runs while the window is being
        // drawn — the family the three frozen windows of 2026-08-20 came from.
        // Through `offTheCooperativePool` and not a detached task: a detached
        // task is still a task on the pool, so a stat that blocks for a minute
        // holds one of its few threads whoever started it. The phase is asked
        // again on the way back — a scan may have started across the suspension,
        // and the fresh one wins.
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
        completedAt = cached.savedAt
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
    public static let cacheLifetime: TimeInterval = 86_400
    public func expireIfStale(now: Date = Date()) {
        guard phase == .result, !live, let completedAt,
              now.timeIntervalSince(completedAt) > Self.cacheLifetime else { return }
        newScan()
    }

    /// A walk is running — the volume's, or one folder's measured on demand. The
    /// header's question, and it had no name: `live` also gates whether snapshots
    /// may repaint the ring and `measuring` is also the second-walk guard, so the
    /// spinner hung on one of them and a folder measurement ran in silence.
    public var walking: Bool { live || measuring }

    public var focus: DiskEntry? { focusPath.last }
    public var basketBytes: Int { basket.reduce(0) { $0 + $1.bytes } }
    /// Whether the page draws the bar under the ring — for a basket waiting to
    /// be emptied, or for the report of an emptying that has happened.
    ///
    /// Here rather than in the page because it is the condition three exits have
    /// to satisfy, and a copy of it in the view is a copy that can be satisfied
    /// while the screen still shows the bar.
    /// `replyLost` is here for the same reason `banner` is: it is a sentence the
    /// bar has to draw, and a bar that is not there cannot draw it.
    public var showsRemovalBar: Bool { !basket.isEmpty || banner != nil || replyLost }

    /// The last read of the volume list went unanswered. Read with `volumes` as
    /// one report, the way `replyLost` is read with the removal's three fields:
    /// without it, «no volumes» and «no answer» are the same screen.
    @Published public private(set) var volumeListLost = false

    /// **A list nobody answered is not a Mac with no disks.**
    ///
    /// Folded with `??`, this drew the start screen's invitation over an empty
    /// picker, and every Mac has at least one browsable volume. The quieter half
    /// is `isVolumeScan`, a membership test against this list: with it emptied a
    /// volume scan is taken for a folder scan and `recomputeSegments` leaves the
    /// free-space wedge off — the flat disc that method's own comment exists to
    /// prevent, from the other side. So the list stays and the page says so.
    public func loadVolumes() async {
        guard let list: [VolumeInfo] = await client.request(DiskCommand.volumes) else {
            volumeListLost = true
            // Counts and outcomes are free; nothing here names a volume.
            HelmLog.shared.info(DiskEngine.moduleID, "volume list reply lost")
            return
        }
        volumes = list
        volumeListLost = false
        // **The ring is laid out against this list, and this list arrives after
        // it.** `recomputeSegments` asks `isVolumeScan`, a membership test of
        // `scannedPath` against `volumes`; `restoreLastScan` draws the cached
        // tree first and looks the volumes up afterwards, so a restored whole
        // volume settled holding both halves of the answer and a ring built from
        // neither — every arc a share of `data + free` with the free part left
        // out, which is every angle on screen wrong. Here rather than at the
        // restore, because the list is what changed: a disk mounted under an
        // open ring arrives by the same door.
        recomputeSegments()
    }

    public func scan(path: String) async {
        // "/" is a path, not a name; the volume list knows what to call it.
        rootTitle = Self.title(for: path, volumes: volumes)
        scannedPath = path
        restored = false
        stopped = false
        phase = .scanning
        live = true
        tick = nil
        // A new tree is arriving, so nothing about the old one belongs to the
        // screen any more. This lives here rather than in each caller: it is the
        // invariant "the basket only holds entries from the tree on screen", and
        // every route to a new tree comes through this method. `rescan()` and
        // `newScan()` used to each clear it themselves and Stop had to as well,
        // because Stop showed the volume picker — with Stop keeping the tree it
        // measured, this is the only door left where a tree is replaced.
        basket = []
        clearRemovalReport()
        // There is no completed measurement while one is running; leaving the
        // previous scan's date here made `expireIfStale` judge the new tree by
        // the old tree's age.
        completedAt = nil
        let mine = nextScanID()
        showingScan = mine
        let scan: ScanResult? = await client.request(DiskCommand.scan,
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
        clearRemovalReport()
        await scan(path: path)
    }

    /// Stop. Keeps what the walk had measured, and says that is what it is.
    ///
    /// It used to put the phase back to `.start`, so a minute of watching the
    /// ring grow ended at the volume picker with the tree thrown away — while
    /// `result` still held it. Everything the ring needs was already on hand;
    /// what was missing was somewhere to say the tree is unfinished.
    ///
    /// The clearing this used to do went with it, and the reason is worth
    /// keeping: the basket only ever holds entries from the tree on screen, and
    /// Stop **took the tree away**, which left the volume picker drawn over a
    /// basket bar naming folders of an abandoned scan (the page draws that bar
    /// outside `switch dvm.phase`). Stop no longer takes the tree away, so the
    /// bar is over the tree it belongs to and the invariant holds by keeping
    /// rather than by clearing. The clearing moved to `scan(path:)`, which is now
    /// the only place a tree is replaced.
    public func cancel() {
        // Nothing in flight belongs to the screen any more. The engine may
        // already have finished walking, in which case the command below
        // changes nothing and only this line keeps the answer off the screen.
        showingScan = nextScanID()
        Task { await client.send(DiskCommand.cancel, encoding: [String]()) }
        let wasWalking = live
        // The other walk this button is drawn over. Put down here rather than by
        // `measureAndDrill`'s own `defer`, which cannot run until the engine
        // answers a request the person has just withdrawn.
        let wasMeasuring = measuring
        live = false
        measuring = false
        // There is a tree worth keeping only when a walk was actually running and
        // had reported at least one snapshot. Two other callers arrive here:
        // `newScan()`, which wants the screen emptied, and Stop pressed inside
        // the first third of a second, before any partial. Both are the volume
        // picker, as they always were — and a finished tree must never be marked
        // stopped, which is the whole difference this flag carries.
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

    /// Nothing on screen about a removal. The four fields are read as one report,
    /// so they are put down together — a silence left standing over a fresh tree
    /// is a sentence about a press that belonged to another screen.
    func clearRemovalReport() {
        banner = nil
        failures = []
        removedCount = 0
        replyLost = false
    }

    public func newScan() {
        cancel()
        store.clear()
        phase = .start
        result = nil
        completedAt = nil
        restored = false
        stopped = false
        // Stated here rather than inherited from `cancel()`, which no longer
        // clears: this is the door that really does take the tree away, so it is
        // the one that has to leave the volume picker with nothing under it.
        basket = []
        clearRemovalReport()
        focusPath = []
        segments = []
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
        // A name of its own, and deliberately not the one the screen is
        // showing: this scan's snapshots are a folder, and the ring is a
        // volume. Only its final tree is wanted, and only if the tree it is
        // grafted into is still the one on screen.
        let owner = showingScan
        // Against `owner`, so a withdrawn measurement arriving late cannot put
        // down the flag of the one that replaced it — Stop clears it and moves
        // `showingScan` on.
        defer { if owner == showingScan { measuring = false } }
        let scan: ScanResult? = await client.request(DiskCommand.scan,
                                                     encoding: ScanRequest(path: path,
                                                                           scan: nextScanID()))
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
        // The rule `emptyBasket` already keeps, and this door had none at all —
        // which is the worst place for that, because a stopped tree is exactly
        // the tree full of folders the walk never reached, and measuring one on
        // demand is what a stopped screen is for. Everything around the graft is
        // still a floor.
        if treeIsComplete { store.saveDetached(measured, at: completedAt ?? Date()) }
    }

    public func back() {
        guard focusPath.count > 1 else { return }
        foldingBackLevels = 1
        foldingBackFrom = focusPath.last?.path
        focusPath.removeLast()
        recomputeSegments()
    }

    public func jump(to index: Int) {
        guard focusPath.indices.contains(index), index < focusPath.count - 1 else { return }
        // There is always exactly one wedge to fold into, however far the jump:
        // the child of the level being returned to that leads to where we were.
        // Believing otherwise left every jump of more than one level as a hard
        // cut, which is what the ring looked worst doing.
        foldingBackLevels = focusPath.count - 1 - index
        foldingBackFrom = focusPath[index + 1].path
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

    // The basket and the removal it feeds live in `DiskViewModel+Basket.swift`
    // — this file sat exactly on the linter's length limit, and the basket is
    // the one section that reads whole on its own.

    /// A removal is running. The page dims what would start a second one.
    /// Stored here because an extension cannot hold storage; set only by
    /// `emptyBasket`, one file over.
    @Published public internal(set) var busy = false

    // MARK: - Events

    private func handle(_ event: EngineEvent) async {
        switch DiskEvent(rawValue: event.name) {
        case .progress:
            if let update = try? JSONDecoder().decode(ScanTick.self, from: event.payload),
               update.scan == showingScan {
                tick = update
            }
        case .partial:
            // Whose snapshot this is decides everything: a folder
            // measurement's tree drawn as the volume collapses the focus,
            // keeps the volume's name and title, and draws the volume's
            // free space against a folder.
            guard live,
                  let snapshot = try? JSONDecoder().decode(PartialScan.self,
                                                           from: event.payload),
                  snapshot.scan == showingScan
            else { return }
            result = snapshot.result
            focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: snapshot.result.root)
            phase = .result
            recomputeSegments()
        case .none:
            return
        }
    }

    // MARK: - Layout

    /// The layout the ring is about to become, computed before the animation
    /// starts.
    ///
    /// The unfold used to interpolate the *current* layout and then swap trees
    /// at the end, and the two did not agree: folding into "other" is decided
    /// against the parent's total in one and the folder's own total in the
    /// other, so the last frame of the animation held five arcs spanning 353°
    /// and the first frame after it held three spanning 360. Every boundary
    /// moved at once, which is what read as a tear. Animating *towards* this
    /// makes the last frame the first frame by construction.
    public func ringLayout(forFocusAt path: String) -> [RingSegment] {
        guard let root = result?.root, let node = Self.find(path, in: root) else { return [] }
        // Free space belongs to a volume, not to a folder — the same rule
        // `recomputeSegments` applies, and a drill always lands below the root.
        return RingLayout.layout(focus: Self.node(from: node), path: node.path,
                                 depthLevels: RingView.visibleRings + 1, freeBytes: 0)
    }

    private static func find(_ path: String, in entry: DiskEntry) -> DiskEntry? {
        if entry.path == path { return entry }
        guard path.hasPrefix(entry.path) else { return nil }
        for child in entry.children {
            if let hit = find(path, in: child) { return hit }
        }
        return nil
    }

    func recomputeSegments() {
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
        segments = RingLayout.layout(focus: Self.node(from: focus), path: focus.path,
                                     depthLevels: RingView.visibleRings + 1, freeBytes: free)
    }

    /// RingLayout works on the engine's node type; the UI holds the
    /// transported snapshot, so the focused subtree is rebuilt for it.
    ///
    /// The entry's path is dropped here and handed to `layout` separately: a
    /// `DiskNode` keeps only the name, and the layout composes the rest back
    /// down from the focus. The paths that come out are the entries' own again,
    /// which is what the basket and `RemovableScope` see.
    private static func node(from entry: DiskEntry) -> DiskNode {
        DiskNode(name: entry.name, bytes: entry.bytes,
                 isDirectory: entry.isDirectory,
                 children: entry.children.map(node(from:)))
    }

}
