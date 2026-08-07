import Foundation
import HelmContract
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
    private var loadedApps = false

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
    public func reloadApps() async {
        loadingApps = true
        apps = await listApps()
        loadedApps = true
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

    public func backToPick() {
        step = .pick
        forceQuit = false
    }

    public func dismissFailures() { failures = [] }

    /// Scans every ticked app, then shows the review screen.
    public func prepareReview() async {
        scanning = true
        resultBanner = nil
        defer { scanning = false }
        // Concurrently: the scans are independent, each already hops to a
        // background queue, and awaiting them in a row stacked every delay.
        // Order comes from `apps`, not from whichever finishes first.
        let chosen = apps.filter { checked.contains($0.bundleID) }
        var scans: [String: ScanResult] = [:]
        await withTaskGroup(of: (String, ScanResult?).self) { group in
            for app in chosen {
                group.addTask { (app.bundleID, await self.scan(app)) }
            }
            for await (id, scan) in group { scans[id] = scan }
        }
        let built = chosen.map { app in
            UninstallGroup(app: app,
                           leftovers: scans[app.bundleID]?.leftovers ?? [],
                           running: scans[app.bundleID]?.runningNow ?? false)
        }
        groups = built
        selectedLeftovers = Set(UninstallPlan.defaultSelection(built))
        forceQuit = false
        HelmLog.shared.info("uninstaller",
                            "review \(built.count) apps, \(selectedLeftovers.count) leftovers, running: "
                            + built.filter(\.running).map { Redact.app($0.app.name) }.joined(separator: ","))
        step = .review
    }

    // MARK: - Removing

    public func removeSelection() async {
        guard UninstallPlan.readiness(groups, forceQuit: forceQuit) == .ready else { return }
        busy = true
        defer { busy = false }

        if forceQuit {
            for group in groups where group.running {
                HelmLog.shared.info("uninstaller", "force quit \(Redact.app(group.app.bundleID))")
                await quit(bundleID: group.app.bundleID, force: true)
            }
            // Let the apps disappear before their bundles move.
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        let paths = UninstallPlan.paths(groups, selectedLeftovers: selectedLeftovers)
        HelmLog.shared.info("uninstaller", "trashing \(paths.count) paths")
        let result = await trashPaths(paths)

        let moved = Bytes(result?.freedBytes ?? 0)
        if let failed = result?.failed, !failed.isEmpty {
            HelmLog.shared.warn("uninstaller", "failed to trash: \(Redact.paths(failed))")
            resultBanner = UnStr.movedWithFailures(moved, failed.count)
            // Leftovers that stayed put are the whole point of the module, so
            // they get a screen of their own rather than a line to overlook.
            failures = result?.failures ?? failed.map { TrashFailureInfo(path: $0, reason: "unknown") }
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

    public func listApps() async -> [InstalledApp] {
        HelmLog.shared.info("uninstaller", "listApps requested")
        let apps: [InstalledApp] = await client.request(UninstallerCommand.listApps) ?? []
        HelmLog.shared.info("uninstaller", "listApps returned \(apps.count)")
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

    public func uninstall(appPath: String, paths: [String]) async -> UninstallResult? {
        await client.request(UninstallerCommand.uninstall, encoding: UninstallRequest(appPath: appPath, paths: paths))
    }

    /// Leftovers whose owning app is gone, grouped by bundle id.
    public func systemExtensions() async -> [SystemExtensionInfo] {
        await client.request(UninstallerCommand.systemExtensions) ?? []
    }

    public func scanOrphans() async -> [OrphanGroup] {
        await client.request(UninstallerCommand.scanOrphans) ?? []
    }

    /// Whether Helm offers to clean up after an app the person drags to the
    /// Trash. Read from the engine rather than from a store this page could reach
    /// on its own: the engine is what acts on it, and one reader means the switch
    /// and the behaviour cannot disagree.
    public func watchingTrash() async -> Bool {
        await client.request(UninstallerCommand.watchingTrash) ?? false
    }

    public func setWatchingTrash(_ on: Bool) async {
        await client.send(UninstallerCommand.setWatchingTrash, encoding: on)
    }

    /// Trash arbitrary leftover paths (used by the orphans view).
    public func trashPaths(_ paths: [String]) async -> UninstallResult? {
        await client.request(UninstallerCommand.trashPaths, encoding: paths)
    }

    public func quit(bundleID: String, force: Bool = false) async {
        await client.send(UninstallerCommand.quit, encoding: QuitRequest(bundleID: bundleID, force: force))
    }
}
