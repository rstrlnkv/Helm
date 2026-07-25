import Foundation
import HelmContract
import HelmUI
import HelmRuntime
import Module_Uninstaller_Engine

/// Typed async façade over the engine's request/response transport.
@MainActor public final class UninstallerViewModel: ObservableObject {
    private let client: TransportClient
    public init(vm: ModuleViewModel) { self.client = TransportClient(vm.transport) }

    private struct ScanReq: Codable { let bundleID: String; let appPath: String; let appName: String }
    private struct UninstallReq: Codable { let appPath: String; let paths: [String] }
    private struct QuitReq: Codable { let bundleID: String; let force: Bool }

    public func listApps() async -> [InstalledApp] {
        HelmLog.shared.info("uninstaller", "listApps requested")
        let apps: [InstalledApp] = await client.request("listApps") ?? []
        HelmLog.shared.info("uninstaller", "listApps returned \(apps.count)")
        return apps
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
