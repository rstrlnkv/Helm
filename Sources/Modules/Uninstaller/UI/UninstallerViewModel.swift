import Foundation
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

/// Two steps, AppCleaner-style: tick the apps, then review what was found for
/// them. Which one the person is on belongs to the module, not to the page.
enum UninstallStep: Equatable, Sendable { case pick, review }

/// What the model asks of the engine. A port, so the model's tests hold the
/// engine's place without a Mac's applications in reach.
///
/// Every answer is the return value, so there is nothing to subscribe to and no
/// reply that can be lost. The one thing the engine says unasked, "look at the
/// Trash again", does not come through here: the descriptor hands the model
/// a stream of it (`UninstallerViewModel.listenForTrash`).
protocol UninstallerWork: AnyObject, Sendable {
    func listApps() async -> [InstalledApp]
    func appSizes(_ list: [InstalledApp]) async -> [String: Int]
    func lastOpened(_ list: [InstalledApp], deadline: TimeInterval, ceiling: Int,
                    now: Date) async -> AppOpenedReading
    var sortOrder: AppSortOrder { get }
    func setSortOrder(_ order: AppSortOrder)
    func scan(bundleID: String, appName: String) async -> ScanResult
    func scanOrphans() async -> [OrphanGroup]
    func trashPaths(_ paths: [String], quittingRunningApps: Bool) async -> UninstallResult
    func removalVerdicts(for candidates: [AppRemovalCandidate]) async -> [AppRemovalVerdict]
    func removalPreview(_ candidate: AppRemovalCandidate) async -> AppRemovalAsk
    func removeApp(_ candidate: AppRemovalCandidate, quittingIfRunning: Bool) async -> AppRemovalReport
    var trashWatch: TrashWatch { get }
    func setWatchingTrash(_ on: Bool)
    func trashedAppLeftovers() async -> [TrashedAppLeftovers]
    func dismissTrashedApp(bundleID: String)
    func backgroundScan() async -> ScanReport?
}

extension UninstallerEngine: UninstallerWork {}

/// The module's own state — see `step` and below — and the one door to its
/// engine: the page, the Leftovers tab and the Trash offer all call the engine
/// through here.
@MainActor public final class UninstallerViewModel: ObservableObject {
    private let work: any UninstallerWork
    /// The engine's "look at the Trash again", one value per signal. The
    /// descriptor makes it with the engine; `listenForTrash` reads it.
    private let arrivals: AsyncStream<Void>
    private var listening: Task<Void, Never>?
    private var onTrashArrival: (@MainActor () -> Void)?
    /// The Trash offer on screen, if one is: it takes an arrival into the list it
    /// shows, and the host's handler (which would open a second window) is not
    /// called. Weak: the window owns the offer, and registering it here must not
    /// keep it alive. It is registered **before** its first read, so an arrival
    /// between the read and the registration is not lost.
    weak var openOffer: TrashedLeftoversModel?
    /// Set by `stop()`. The host stops the model before the engine's
    /// `deactivate()`, and a page still on screen — or a task already queued —
    /// may press a control after that; a stopped model reaches no work.
    private(set) var closed = false

    /// The Leftovers tab's state, kept here so that it outlives a sidebar click;
    /// `stop()` clears it.
    lazy var orphans = OrphansModel(uvm: self)

    /// The installed apps, and their sizes once those have been measured.
    ///
    /// These live here rather than in the page's `@State` because the page does
    /// not survive a sidebar click: leaving the module tears down the subtree,
    /// and coming back builds a fresh one whose `@State` is empty, so `.task`
    /// re-ran `listApps()` and `appSizes()` from nothing. Measuring 39 bundles
    /// took four seconds, nine on a cold cache — paid on every visit, for a
    /// list that had not changed. Caching the view model alone would not have
    /// helped while the list it produced lived on the page.
    @Published private(set) var apps: [InstalledApp] = []
    /// Which sizes have been measured, by path. **Absent means "not measured"**,
    /// which a zero cannot say: the list arrives unsized and a bundle that could
    /// not be read measures as zero too.
    @Published private(set) var measuredSizes: [String: Int] = [:]
    /// When Spotlight says each app was last opened; `nil` until it has been
    /// asked. An app missing from an answered table has no record.
    @Published private(set) var lastOpened: [String: Date]?
    /// Paths the last-opened read did not reach: neither a date nor "no record".
    @Published private(set) var lastOpenedUnread: Set<String> = []
    /// The remembered order, as the engine last said it. The engine owns it.
    @Published private(set) var sortOrder: AppSortOrder = .standard

    /// What the list is really ordered by — a stored date order over a Mac where
    /// Spotlight said nothing reads as the name order.
    var effectiveSortOrder: AppSortOrder {
        AppSort.effective(sortOrder, opened: lastOpened)
    }

    /// The list in the person's order; search narrows this and never reorders it.
    var sortedApps: [InstalledApp] {
        AppSort.sorted(apps, order: sortOrder, sizes: measuredSizes, opened: lastOpened,
                       unread: lastOpenedUnread)
    }

    var dateOrderAvailable: Bool { AppSort.dateOrderAvailable(lastOpened) }

    /// True while the names are being fetched. Sizes land afterwards and do not
    /// hold the list back — the names are what somebody is looking for.
    @Published private(set) var loadingApps = false
    /// Which reload of the list is the newest, so an older answer does not land
    /// on a newer list.
    private var latestList = LatestRequest()
    /// Whether the list has ever been **answered**, which is not the same as
    /// having been asked for: before the page's first `.task` there is no list
    /// and no reason to say «0 apps».
    ///
    /// One flag for the body (`AppsEmpty.reason(answered:apps:shown:)`) and the
    /// footer (`AppsEmpty.status(answered:loading:apps:)`) alike: two sources of
    /// "has anybody answered" would drift into a page whose count says
    /// «Counting apps…» over a body claiming the Mac holds no applications.
    private(set) var listAnswered = false
    /// Counts removals through the door, so a list read that began before one does not mark the list current after it.
    private var doorRemovals = 0

    // MARK: - Where the person is, and what they chose

    /// The rest of the flow lives here for the same reason the list does, and
    /// the cost of it being on the page was steeper: ticking apps and clicking
    /// Disk in the sidebar came back to a count of 0; doing it on the review
    /// screen threw away a leftovers scan of every ticked app; doing it on the
    /// failure report threw away the only record of what macOS refused and why,
    /// which nothing in the app can produce a second time.
    @Published private(set) var step: UninstallStep = .pick
    /// Bundle paths ticked on the picker: two copies of one app share an id and
    /// are two rows, so a tick belongs to the copy on disk.
    @Published private(set) var checked: Set<String> = []
    @Published private(set) var groups: [UninstallGroup] = []
    @Published private(set) var selectedLeftovers: Set<String> = []
    @Published private(set) var failures: [TrashFailureInfo] = []
    @Published var forceQuit = false
    @Published private(set) var scanning = false
    @Published private(set) var busy = false
    @Published private(set) var resultBanner: String?

    /// What the Trash-offer switch is doing, from the engine — the switch's own
    /// position and, when it is on, whether either of the two things it depends on
    /// has refused. See `TrashWatch`.
    @Published private(set) var trashWatch: TrashWatch = .off

    init(work: any UninstallerWork, trashArrivals: AsyncStream<Void>) {
        self.work = work
        self.arrivals = trashArrivals
    }

    /// Closes the model: the host calls it before the engine's `deactivate()`.
    /// Whatever is pressed after reaches no work, and a list, its readings or a
    /// review still in flight is not shown; a removal, an orphan scan or a Trash
    /// sweep already handed to the engine still lands. The arrival subscription
    /// and the open offer let go.
    /// Saving a chosen sort order is not refused — it is the person's setting,
    /// not work.
    public func stop() {
        closed = true
        listening?.cancel()
        listening = nil
        onTrashArrival = nil
        openOffer = nil
        orphans.clear()
    }

    /// Takes the engine's "look at the Trash again" while the model lives. With
    /// an offer open the signal is the offer's; without one it is `arrived`,
    /// which is the host's sweep. One iteration of the stream, ever: a second
    /// call only replaces the handler.
    public func listenForTrash(_ arrived: @escaping @MainActor () -> Void) {
        guard !closed else { return }
        onTrashArrival = arrived
        guard listening == nil else { return }
        let stream = arrivals
        listening = Task { [weak self] in
            for await _ in stream {
                guard let self, !self.closed else { break }
                if let offer = self.openOffer {
                    await offer.refresh()
                } else {
                    self.onTrashArrival?()
                }
            }
        }
    }

    /// What the page asks for on appear: the first visit does the work, later
    /// visits show what is already here.
    func loadAppsIfNeeded() async {
        guard !closed, !listAnswered else { return }
        await reloadApps()
    }

    /// What the Refresh button asks for, and what a removal asks for once it
    /// has changed the list.
    func reloadApps() async {
        guard !closed else { return }
        let mine = latestList.take()
        let removalsAtStart = doorRemovals
        loadingApps = true
        let list = await work.listApps()
        // An older answer is dropped whole, `loadingApps` included: the newer
        // reload is still out and clears it when it lands.
        guard latestList.isLatest(mine) else { return }
        loadingApps = false
        guard !closed else { return }
        apps = list
        // The readings belong to the list they were taken for.
        measuredSizes = [:]
        lastOpened = nil
        lastOpenedUnread = []
        listAnswered = removalsAtStart == doorRemovals
        // Independent: the dates take milliseconds and must not wait behind sizes
        // that take seconds, nor the other way round.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fillInSizes(for: mine) }
            group.addTask { await self.fillInDates(for: mine) }
        }
    }

    private func fillInDates(for token: Int) async {
        let reading = await work.lastOpened(apps, deadline: UninstallerEngine.lastOpenedDeadline,
                                            ceiling: UninstallerEngine.lastOpenedCeiling,
                                            now: Date())
        guard !closed, latestList.isLatest(token) else { return }
        lastOpened = reading.opened
        lastOpenedUnread = Set(reading.unread)
    }

    /// The remembered order, read again on every appearance of the page. The
    /// read is a store's and does not suspend, so no press can land between
    /// asking and assigning.
    func refreshSortOrder() async {
        guard !closed else { return }
        sortOrder = work.sortOrder
    }

    /// The press answers at once and the engine remembers it.
    func setSortOrder(_ order: AppSortOrder) async {
        sortOrder = order
        work.setSortOrder(order)
    }

    /// The list is drawn from names alone and the numbers land a moment later.
    private func fillInSizes(for token: Int) async {
        let sizes = await work.appSizes(apps)
        guard !closed, latestList.isLatest(token), !sizes.isEmpty else { return }
        // By path: two copies of one app share a bundle id and each has its own size.
        measuredSizes = sizes
    }

    // MARK: - Picking

    func isChecked(_ app: InstalledApp) -> Bool { checked.contains(app.path) }

    /// A `com.apple.` app is refused rather than merely undrawn. The row leaves
    /// the checkbox out (`SystemApp.isSystem`), and this is the same rule at the
    /// only place that can put a path into the set — a tick macOS will refuse
    /// costs the person a scan, a click and a failure report to find that out.
    func setChecked(_ app: InstalledApp, _ on: Bool) {
        guard !SystemApp.isSystem(bundleID: app.bundleID) else { return }
        if on { checked.insert(app.path) } else { checked.remove(app.path) }
    }

    func toggleChecked(_ app: InstalledApp) { setChecked(app, !isChecked(app)) }

    func clearChecked() { checked.removeAll() }

    // MARK: - Reviewing

    func isSelected(leftover path: String) -> Bool { selectedLeftovers.contains(path) }

    func setSelected(leftover path: String, _ on: Bool) {
        if on { selectedLeftovers.insert(path) } else { selectedLeftovers.remove(path) }
    }

    /// What the review would move, or `nil` while any app in it has not been
    /// measured — a sum with one term missing is a smaller number nobody
    /// measured. Read from `measuredSizes`, which keeps arriving after the review
    /// opened; `groups` is a snapshot and carries no size of its own.
    var reviewBytes: Int? {
        guard !groups.isEmpty,
              groups.allSatisfy({ measuredSizes[$0.app.path] != nil }) else { return nil }
        return UninstallPlan.totalBytes(groups, appBytes: measuredSizes, selectedLeftovers: selectedLeftovers)
    }

    /// Leaving the review ends the round, so the report of the last press goes
    /// with it — the pick screen's own footer draws `resultBanner`, and a
    /// sentence about a batch that was refused for a running app has nothing to
    /// say there.
    func backToPick() {
        step = .pick
        forceQuit = false
        resultBanner = nil
    }

    func dismissFailures() { failures = [] }

    /// Scans every ticked app, then shows the review screen.
    func prepareReview() async {
        guard !closed, !scanning else { return }
        scanning = true
        resultBanner = nil
        defer { scanning = false }
        let chosen = apps.filter { checked.contains($0.path) }
        let built = await scanned(chosen)
        guard !closed else { return }
        groups = built
        selectedLeftovers = Set(UninstallPlan.defaultSelection(built))
        forceQuit = false
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "review \(built.count) apps, \(selectedLeftovers.count) leftovers, running: "
                            + built.filter(\.running).map { Redact.app($0.app.name) }.joined(separator: ","))
        step = .review
    }

    /// One review group per app, from a scan each.
    ///
    /// Concurrently: the scans are independent, each already hops to a background
    /// queue, and awaiting them in a row stacked every delay. Order comes from the
    /// list handed in, not from whichever finishes first.
    private func scanned(_ chosen: [InstalledApp]) async -> [UninstallGroup] {
        let work = self.work
        var done: [(Int, ScanResult)] = []
        await withTaskGroup(of: (Int, ScanResult).self) { group in
            for (index, app) in chosen.enumerated() {
                group.addTask {
                    (index, await work.scan(bundleID: app.bundleID, appName: app.name))
                }
            }
            for await item in group { done.append(item) }
        }
        let ordered = done.sorted { $0.0 < $1.0 }.map(\.1)
        return zip(chosen, ordered).map { app, scan in
            UninstallGroup(app: app, leftovers: scan.leftovers, running: scan.runningNow)
        }
    }

    // MARK: - Removing

    /// **Which apps are still up is the engine's question now, asked at the point
    /// of removal.** This used to quit them here, from `group.running` — a flag
    /// read when the review was built, so an app the person had since quit left
    /// the button dead and an app started since then was never asked to quit at
    /// all, and had its bundle moved out from under it.
    func removeSelection() async {
        // The model refuses a second run itself rather than trusting the page
        // to have dimmed the button: `.disabled(model.busy)` is a redraw away,
        // and the row menu reaches this by another road.
        guard !closed else { return }
        guard !busy else { return }
        let paths = UninstallPlan.paths(groups, selectedLeftovers: selectedLeftovers)
        // An empty batch would come back as "moved 0 items, 0 bytes" — a success
        // sentence about a removal nobody asked for.
        guard !paths.isEmpty else { return }
        busy = true
        defer { busy = false }

        HelmLog.shared.info(UninstallerEngine.moduleID, "trashing \(paths.count) paths")
        // Nil only when the module was stopped under the page: nothing moved, and
        // the review stays as it is.
        guard let result = await trashPaths(paths, quittingRunningApps: forceQuit) else { return }

        // Nothing moved: an app in the batch was up, with no quit allowed or
        // still up after the quit. The review stays, its `running` flags are replaced by what
        // the engine has just read, and the offer the person needs — quit it, or,
        // where no quit was allowed, tick the force quit — is the one already on this screen.
        guard result.stillRunning.isEmpty else {
            let up = Set(result.stillRunning)
            groups = groups.map {
                UninstallGroup(app: $0.app, leftovers: $0.leftovers, running: up.contains($0.app.path))
            }
            failures = []
            resultBanner = UnStr.blockedByRunning
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "batch held: \(up.count) app(s) still running")
            return
        }

        let moved = Bytes(result.freedBytes)
        if !result.failed.isEmpty {
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "failed to trash: "
                                + result.failed.map { Redact.path($0, leaf: .softwareName) }.joined(separator: ", "))
            resultBanner = UnStr.movedWithFailures(moved, result.failed.count)
            // Leftovers that stayed put are the whole point of the module, so
            // they get a screen of their own rather than a line to overlook.
            //
            // No fallback: `failed` is `failures.map(\.path)`, so every failed
            // path already has its reason.
            failures = result.failures
        } else {
            resultBanner = HelmBasket.movedToTrash(moved)
            failures = []
        }

        checked.removeAll()
        groups = []
        selectedLeftovers = []
        forceQuit = false
        step = .pick
        await reloadApps()
    }

    // MARK: - The engine's other doors

    /// Leftovers whose app is gone, or nil when the module has been stopped.
    func scanOrphans() async -> [OrphanGroup]? {
        guard !closed else { return nil }
        return await work.scanOrphans()
    }

    /// Whether Helm offers to clean up after an app the person drags to the
    /// Trash — **and whether it is in a position to.** Read from the engine rather
    /// than from a store this page could reach on its own: the engine is what acts
    /// on it, and one reader means the switch and the behaviour cannot disagree.
    ///
    /// It lives here rather than in two `@State`s, which is where it was: the page
    /// kept one for its permission note and the Leftovers tab another for the
    /// switch, and the fact is the module's.
    func refreshTrashWatch() async {
        guard !closed else { return }
        trashWatch = work.trashWatch
    }

    /// The press answers the switch at once — a `Toggle` would snap back under the
    /// pointer otherwise — and the engine's own reading of what it is now doing
    /// follows immediately.
    func setWatchingTrash(_ on: Bool) async {
        guard !closed else { return }
        trashWatch = on ? .on : .off
        work.setWatchingTrash(on)
        await refreshTrashWatch()
    }

    /// Trash a batch of paths — leftovers alone from the orphans view, or a
    /// review's app bundles and everything ticked with them. Nil only when the
    /// module has been stopped: nothing moved.
    ///
    /// `quittingRunningApps` is the person's answer to «Force quit and remove
    /// anyway», and it travels with the batch because the engine is what asks
    /// whether the app is *still* up. The alternative was what this module did:
    /// quit here, from a flag the scan read minutes ago.
    func trashPaths(_ paths: [String],
                           quittingRunningApps mayQuit: Bool = false) async -> UninstallResult? {
        guard !closed else { return nil }
        return await work.trashPaths(paths, quittingRunningApps: mayQuit)
    }

    /// What is sitting in the Trash that left something behind, or nil when the
    /// module has been stopped.
    func trashedAppLeftovers() async -> [TrashedAppLeftovers]? {
        guard !closed else { return nil }
        return await work.trashedAppLeftovers()
    }

    /// Remembers a "no" to the offer for this app.
    func dismissTrashedApp(bundleID: String) async {
        guard !closed else { return }
        work.dismissTrashedApp(bundleID: bundleID)
    }

    /// The unattended orphan scan, asked by the descriptor; nil is no answer.
    func backgroundScan() async -> ScanReport? {
        guard !closed else { return nil }
        return await work.backgroundScan()
    }
}

// MARK: - The door for another module's removal of one app

/// In this file because it takes `busy` and calls `work`, both private to it: the model refuses a second
/// removal itself, the same guard `removeSelection` holds, so a Launchpad press cannot run beside a batch
/// from the page, and a batch from the page cannot run beside it.
extension UninstallerViewModel: AppRemovalService {
    public func verdicts(for candidates: [AppRemovalCandidate]) async -> [AppRemovalVerdict] {
        guard !closed else { return candidates.map { _ in .refused(.stopped) } }
        return await work.removalVerdicts(for: candidates)
    }

    public func preview(_ candidate: AppRemovalCandidate) async -> AppRemovalAsk {
        guard !closed else { return .refused(.stopped) }
        return await work.removalPreview(candidate)
    }

    public func remove(_ candidate: AppRemovalCandidate, quittingIfRunning: Bool) async -> AppRemovalReport {
        guard !closed else { return AppRemovalReport(.stopped) }
        guard !busy else { return AppRemovalReport(.busy) }
        busy = true
        defer { busy = false }
        let report = await work.removeApp(candidate, quittingIfRunning: quittingIfRunning)
        // The list the page holds is older than this removal: it is read again when the page next appears.
        if report.outcome == .moved || report.outcome == .movedWithFailures {
            listAnswered = false
            doorRemovals += 1
            checked.remove(candidate.path)
        }
        return report
    }
}
