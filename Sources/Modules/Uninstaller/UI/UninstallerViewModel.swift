import Foundation
import HelmContract
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

/// Typed async façade over the engine's request/response transport.
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

    /// One instance per host view model, for the app's lifetime. Keyed to the
    /// view model rather than merely "exists": turning the module off drops the
    /// engine, and a cache held past that answers every request with empty Data
    /// for as long as the app runs.
    private static var cached: UninstallerViewModel?
    public static func shared(vm: ModuleViewModel) -> UninstallerViewModel {
        if let cached, cached.vm === vm { return cached }
        let created = UninstallerViewModel(vm: vm)
        cached = created
        ModuleUICache.dropWhenDisabled("uninstaller") { cached = nil }
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
        let sizes = await appSizes()
        guard !sizes.isEmpty else { return }
        apps = apps.map { app in
            // By path: two copies of one app share a bundle id and each has its
            // own size.
            guard let size = sizes[app.path], size != app.sizeBytes else { return app }
            return InstalledApp(name: app.name, bundleID: app.bundleID,
                                path: app.path, sizeBytes: size)
        }
    }

    private struct ScanReq: Codable { let bundleID: String; let appPath: String; let appName: String }
    private struct UninstallReq: Codable { let appPath: String; let paths: [String] }
    private struct QuitReq: Codable { let bundleID: String; let force: Bool }

    public func listApps() async -> [InstalledApp] {
        HelmLog.shared.info("uninstaller", "listApps requested")
        let apps: [InstalledApp] = await client.request("listApps") ?? []
        HelmLog.shared.info("uninstaller", "listApps returned \(apps.count)")
        return apps
    }

    /// Sizes arrive after the list: measuring a bundle walks every file inside
    /// it, and the names are what the user is looking at first.
    public func appSizes() async -> [String: Int] {
        await client.request("appSizes") ?? [:]
    }

    public func scan(_ app: InstalledApp) async -> ScanResult? {
        await client.request("scan", encoding: ScanReq(bundleID: app.bundleID, appPath: app.path, appName: app.name))
    }

    public func uninstall(appPath: String, paths: [String]) async -> UninstallResult? {
        await client.request("uninstall", encoding: UninstallReq(appPath: appPath, paths: paths))
    }

    /// Leftovers whose owning app is gone, grouped by bundle id.
    public func systemExtensions() async -> [SystemExtensionInfo] {
        await client.request("systemExtensions") ?? []
    }

    public func scanOrphans() async -> [OrphanGroup] {
        await client.request("scanOrphans") ?? []
    }

    /// Trash arbitrary leftover paths (used by the orphans view).
    public func trashPaths(_ paths: [String]) async -> UninstallResult? {
        await client.request("trashPaths", encoding: paths)
    }

    public func quit(bundleID: String, force: Bool = false) async {
        await client.send("quit", encoding: QuitReq(bundleID: bundleID, force: force))
    }
}
