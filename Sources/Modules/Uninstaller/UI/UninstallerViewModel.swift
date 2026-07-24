import Foundation
import HelmContract
import HelmUI
import Module_Uninstaller_Engine

/// Typed async façade over the engine's request/response transport.
@MainActor public final class UninstallerViewModel: ObservableObject {
    private let transport: EngineTransport
    public init(vm: ModuleViewModel) { self.transport = vm.transport }

    private struct ScanReq: Codable { let bundleID: String; let appPath: String; let appName: String }
    private struct UninstallReq: Codable { let appPath: String; let paths: [String] }
    private struct QuitReq: Codable { let bundleID: String }

    public func listApps() async -> [InstalledApp] {
        await send("listApps", Data(), as: [InstalledApp].self) ?? []
    }

    public func scan(_ app: InstalledApp) async -> ScanResult? {
        let req = ScanReq(bundleID: app.bundleID, appPath: app.path, appName: app.name)
        return await send("scan", encode(req), as: ScanResult.self)
    }

    public func uninstall(appPath: String, paths: [String]) async -> UninstallResult? {
        let req = UninstallReq(appPath: appPath, paths: paths)
        return await send("uninstall", encode(req), as: UninstallResult.self)
    }

    /// Leftovers whose owning app is gone, grouped by bundle id.
    public func scanOrphans() async -> [OrphanGroup] {
        await send("scanOrphans", Data(), as: [OrphanGroup].self) ?? []
    }

    /// Trash arbitrary leftover paths (used by the orphans view).
    public func trashPaths(_ paths: [String]) async -> UninstallResult? {
        await send("trashPaths", encode(paths), as: UninstallResult.self)
    }

    public func quit(bundleID: String) async {
        _ = try? await transport.send(EngineCommand(name: "quit", payload: encode(QuitReq(bundleID: bundleID))))
    }

    // MARK: - Plumbing

    private func encode<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }

    private func send<T: Decodable>(_ name: String, _ payload: Data, as: T.Type) async -> T? {
        guard let data = try? await transport.send(EngineCommand(name: name, payload: payload)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
