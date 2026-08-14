import Foundation
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

/// Two steps, AppCleaner-style: tick the apps, then review what was found for
/// them. Which one the person is on belongs to the module, not to the page.
public enum UninstallStep: Equatable, Sendable { case pick, review }

/// Typed async façade over the engine's request/response transport, and the
/// module's own state — see `step` and below.
@MainActor public final class UninstallerViewModel: ObservableObject {
    private let client: TransportClient
    private let vm: ModuleViewModel

    /// The installed apps, and their sizes once those have been measured.
    ///
    /// These live here rather than in the page's `@State` because the page does
    /// not survive a sidebar click: leaving the module tears down the subtree,
    /// and coming back builds a fresh one whose `@State` is empty, so `.task`
    /// re-ran `listApps()` and `appSizes()` from nothing. Measuring 39 bundles
    /// took four seconds, nine on a cold cache — paid on every visit, for a
    /// list that had not changed. Caching the view model alone would not have
    /// helped while the list it produced lived on the page.
    @Published public private(set) var apps: [InstalledApp] = []
    /// True while the names are being fetched. Sizes land afterwards and do not
    /// hold the list back — the names are what somebody is looking for.
    @Published public private(set) var loadingApps = false
    /// Whether the list has ever been **answered**, which is not the same as
    /// having been asked for. It used to be set whatever came back, so one lost
    /// reply left the module holding «you have no applications» for the life of
    /// the process — `loadAppsIfNeeded` would not ask again, and only the Refresh
    /// button would.
    private var loadedApps = false

    /// How many applications are installed, or nil while Helm does not know.
    ///
    /// The page's footer draws this through `UnStr.appsCount`, which already has a
    /// sentence for the unknown — «Counting apps…» — and that is the honest state
    /// for a query still out **and** for one that came back with nothing at all.
    /// Read from the flag rather than from `apps.isEmpty`, because a Mac with no
    /// applications on it is an answer and reads as «0 apps».
    public var appCount: Int? {
        guard loadedApps, !loadingApps else { return nil }
        return apps.count
    }

    // MARK: - Where the person is, and what they chose

    /// The rest of the flow lives here for the same reason the list does, and
    /// the cost of it being on the page was steeper: ticking apps and clicking
    /// Disk in the sidebar came back to a count of 0; doing it on the review
    /// screen threw away a leftovers scan of every ticked app; doing it on the
    /// failure report threw away the only record of what macOS refused and why,
    /// which nothing in the app can produce a second time.
    @Published public private(set) var step: UninstallStep = .pick
    /// Bundle ids ticked on the picker.
    @Published public private(set) var checked: Set<String> = []
    @Published public private(set) var groups: [UninstallGroup] = []
    @Published public private(set) var selectedLeftovers: Set<String> = []
    @Published public private(set) var failures: [TrashFailureInfo] = []
    @Published public var forceQuit = false
    @Published public private(set) var scanning = false
    @Published public private(set) var busy = false
    @Published public private(set) var resultBanner: String?
    @Published public private(set) var replyLost = false

    /// What the Trash-offer switch is doing, from the engine — the switch's own
    /// position and, when it is on, whether either of the two things it depends on
    /// has refused. See `TrashWatch`.
    @Published public private(set) var trashWatch: TrashWatch = .off

    /// One instance per host view model, for the app's lifetime. Keyed to the
    /// view model rather than merely "exists": turning the module off drops the
    /// engine, and a cache held past that answers every request with empty Data
    /// for as long as the app runs.
    private static var cached: UninstallerViewModel?
    public static func shared(vm: ModuleViewModel) -> UninstallerViewModel {
        if let cached, cached.vm === vm { return cached }
        let created = UninstallerViewModel(vm: vm)
        cached = created
        ModuleUICache.dropWhenDisabled(UninstallerDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
    }

    /// What the page asks for on appear: the first visit does the work, later
    /// visits show what is already here.
    public func loadAppsIfNeeded() async {
        guard !loadedApps else { return }
        await reloadApps()
    }

    /// What the Refresh button asks for, and what a removal asks for once it
    /// has changed the list.
    ///
    /// **A list nobody answered is not a Mac with no applications on it.** Folded
    /// with `??`, this drew «0 apps» over somebody's Mac and set the flag anyway,
    /// so nothing asked again — and a Refresh that went unanswered emptied the list
    /// the person was looking at. It keeps what it has and stays in the state the
    /// footer already has a sentence for.
    public func reloadApps() async {
        loadingApps = true
        if let list = await listApps() {
            apps = list
            loadedApps = true
        } else {
            // Counts and outcomes are free; nothing here names an application.
            HelmLog.shared.info(UninstallerEngine.moduleID, "app list reply lost")
        }
        loadingApps = false
        await fillInSizes()
    }

    /// The list is drawn from names alone and the numbers land a moment later.
    private func fillInSizes() async {
        let sizes = await appSizes(for: apps)
        guard !sizes.isEmpty else { return }
        apps = apps.map { app in
            // By path: two copies of one app share a bundle id and each has its
            // own size.
            guard let size = sizes[app.path], size != app.sizeBytes else { return app }
            return InstalledApp(name: app.name, bundleID: app.bundleID,
                                path: app.path, sizeBytes: size)
        }
    }

    // MARK: - Picking

    public func isChecked(_ bundleID: String) -> Bool { checked.contains(bundleID) }

    /// A `com.apple.` app is refused rather than merely undrawn. The row leaves
    /// the checkbox out (`SystemApp.isSystem`), and this is the same rule at the
    /// only place that can put an id into the set — a tick macOS will refuse
    /// costs the person a scan, a click and a failure report to find that out.
    public func setChecked(_ bundleID: String, _ on: Bool) {
        guard !SystemApp.isSystem(bundleID: bundleID) else { return }
        if on { checked.insert(bundleID) } else { checked.remove(bundleID) }
    }

    public func toggleChecked(_ bundleID: String) { setChecked(bundleID, !isChecked(bundleID)) }

    public func clearChecked() { checked.removeAll() }

    // MARK: - Reviewing

    public func isSelected(leftover path: String) -> Bool { selectedLeftovers.contains(path) }

    public func setSelected(leftover path: String, _ on: Bool) {
        if on { selectedLeftovers.insert(path) } else { selectedLeftovers.remove(path) }
    }

    /// Leaving the review ends the round, so the report of the last press goes
    /// with it — the pick screen's own footer draws `resultBanner`, and a
    /// sentence about a batch that was refused for a running app has nothing to
    /// say there.
    public func backToPick() {
        step = .pick
        forceQuit = false
        resultBanner = nil
        replyLost = false
    }

    public func dismissFailures() { failures = [] }

    /// Scans every ticked app, then shows the review screen.
    public func prepareReview() async {
        scanning = true
        resultBanner = nil
        replyLost = false
        defer { scanning = false }
        let chosen = apps.filter { checked.contains($0.bundleID) }
        let built = await scanned(chosen, keeping: [])
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
    ///
    /// **A scan that was not answered leaves its group as it was.** `scan()` is a
    /// request like any other and comes back nil for an engine that is gone or a
    /// reply that would not decode; folded to `[]` it would report "this app left
    /// nothing behind" — and on the rescan below that reads as *the removal
    /// worked*, over a list that is the person's own review.
    private func scanned(_ chosen: [InstalledApp],
                         keeping previous: [UninstallGroup]) async -> [UninstallGroup] {
        var scans: [String: ScanResult] = [:]
        await withTaskGroup(of: (String, ScanResult?).self) { group in
            for app in chosen {
                group.addTask { (app.bundleID, await self.scan(app)) }
            }
            for await (id, scan) in group { scans[id] = scan }
        }
        return chosen.map { app in
            guard let scan = scans[app.bundleID] else {
                return previous.first { $0.app.path == app.path }
                    ?? UninstallGroup(app: app, leftovers: [], running: false)
            }
            return UninstallGroup(app: app, leftovers: scan.leftovers, running: scan.runningNow)
        }
    }

    // MARK: - Removing

    /// **Which apps are still up is the engine's question now, asked at the point
    /// of removal.** This used to quit them here, from `group.running` — a flag
    /// read when the review was built, so an app the person had since quit left
    /// the button dead and an app started since then was never asked to quit at
    /// all, and had its bundle moved out from under it.
    public func removeSelection() async {
        // The model refuses a second run itself rather than trusting the page
        // to have dimmed the button: `.disabled(model.busy)` is a redraw away,
        // and the row menu reaches this by another road.
        guard !busy else { return }
        let paths = UninstallPlan.paths(groups, selectedLeftovers: selectedLeftovers)
        // An empty batch would come back as "moved 0 items, 0 bytes" — a success
        // sentence about a removal nobody asked for.
        guard !paths.isEmpty else { return }
        busy = true
        defer { busy = false }

        HelmLog.shared.info(UninstallerEngine.moduleID, "trashing \(paths.count) paths")
        let result = await trashPaths(paths, quittingRunningApps: forceQuit)

        // **A batch nobody answered is not a batch that moved nothing.** Folded
        // with `??`, this said «Moved to the Trash — 0 bytes» over applications
        // that are exactly where they were, and cleared the review — the scan of
        // every ticked app — on the strength of it. Nor is it a batch that
        // failed: the engine may have moved everything and the reply been lost.
        // So it claims nothing, keeps what the person is looking at, and says
        // that it does not know.
        guard let result else {
            resultBanner = nil
            failures = []
            replyLost = true
            // Counts and outcomes are free; nothing here names an application.
            // It was the one branch that reached the screen without reaching the
            // file a person attaches to a bug report.
            HelmLog.shared.info(UninstallerEngine.moduleID, "trash reply lost")
            // What the report over the review says is that the list under it is
            // where the files are now, so the list is read again — and a scan
            // that is also unanswered leaves each group as it was rather than
            // reporting it empty.
            groups = await scanned(groups.map(\.app), keeping: groups)
            selectedLeftovers.formIntersection(groups.flatMap(\.leftovers).map(\.path))
            return
        }
        replyLost = false

        // Nothing moved: an app in the batch was up and nobody had allowed Helm
        // to quit it. The review stays, its `running` flags are replaced by what
        // the engine has just read, and the offer the person needs — quit it, or
        // tick the force quit — is the one already on this screen.
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
                                "failed to trash: \(Redact.paths(result.failed))")
            resultBanner = UnStr.movedWithFailures(moved, result.failed.count)
            // Leftovers that stayed put are the whole point of the module, so
            // they get a screen of their own rather than a line to overlook.
            //
            // There used to be a fallback here, building a failure per path with
            // the reason `"unknown"`, for a result whose `failed` held paths its
            // `failures` did not. That was already unreachable — `failed` is
            // `failures.map(\.path)` — and `"unknown"` was not one of the
            // reasons, so what it drew was the sentence for a cause nobody knew.
            failures = result.failures
        } else {
            resultBanner = UnStr.movedToTrash(moved)
            failures = []
        }

        checked.removeAll()
        groups = []
        selectedLeftovers = []
        forceQuit = false
        step = .pick
        await reloadApps()
    }

    // MARK: - Transport

    // The three request shapes are the engine's own — they were declared here
    // as well, and `QuitReq` had already drifted: `force` was `Bool` on this
    // side and `Bool?` on the other. See `UninstallerCommand.swift`.

    /// The installed apps, or nil for a request the engine did not answer — an
    /// engine that has gone under a page that is still up, a command it could not
    /// parse, a reply that would not decode. The nil is the caller's to read; it
    /// used to be folded here, where the difference stopped existing.
    public func listApps() async -> [InstalledApp]? {
        HelmLog.shared.info(UninstallerEngine.moduleID, "listApps requested")
        let apps: [InstalledApp]? = await client.request(UninstallerCommand.listApps)
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "listApps returned \(apps.map { "\($0.count)" } ?? "nothing")")
        return apps
    }

    /// Sizes arrive after the list: measuring a bundle walks every file inside
    /// it, and the names are what the user is looking at first. The list goes
    /// with the request — the engine had been enumerating the app folders a
    /// second time to rebuild what the caller already had.
    public func appSizes(for list: [InstalledApp]) async -> [String: Int] {
        await client.request(UninstallerCommand.appSizes, encoding: list) ?? [:]
    }

    public func scan(_ app: InstalledApp) async -> ScanResult? {
        await client.request(UninstallerCommand.scan, encoding: UninstallScanRequest(bundleID: app.bundleID, appPath: app.path, appName: app.name))
    }

    public func scanOrphans() async -> [OrphanGroup] {
        await client.request(UninstallerCommand.scanOrphans) ?? []
    }

    /// Whether Helm offers to clean up after an app the person drags to the
    /// Trash — **and whether it is in a position to.** Read from the engine rather
    /// than from a store this page could reach on its own: the engine is what acts
    /// on it, and one reader means the switch and the behaviour cannot disagree.
    ///
    /// It lives here rather than in two `@State`s, which is where it was: the page
    /// kept one for its permission note and the Leftovers tab another for the
    /// switch, and the fact is the module's.
    public func refreshTrashWatch() async {
        // A request nobody answered leaves the last reading where it is. Folded to
        // `false`, an unanswered read drew the switch as off — which is a claim
        // about a setting, on the control the person would press to change it.
        guard let state: TrashWatch = await client.request(UninstallerCommand.watchingTrash)
        else {
            HelmLog.shared.info(UninstallerEngine.moduleID, "trash watch reply lost")
            return
        }
        trashWatch = state
    }

    /// The press answers the switch at once — waiting for the round trip would let
    /// a `Toggle` snap back under the pointer — and the engine's own reading of what
    /// it is now doing arrives immediately after.
    public func setWatchingTrash(_ on: Bool) async {
        trashWatch = on ? .on : .off
        await client.send(UninstallerCommand.setWatchingTrash, encoding: on)
        await refreshTrashWatch()
    }

    /// Trash a batch of paths — leftovers alone from the orphans view, or a
    /// review's app bundles and everything ticked with them.
    ///
    /// `quittingRunningApps` is the person's answer to «Force quit and remove
    /// anyway», and it travels with the batch because the engine is what asks
    /// whether the app is *still* up. The alternative was what this module did:
    /// quit here, from a flag the scan read minutes ago.
    public func trashPaths(_ paths: [String],
                           quittingRunningApps mayQuit: Bool = false) async -> UninstallResult? {
        await client.request(UninstallerCommand.trashPaths,
                             encoding: TrashBatchRequest(paths: paths, quitRunningApps: mayQuit))
    }
}
