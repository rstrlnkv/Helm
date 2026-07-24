import Foundation
import HelmContract

/// Orchestrates app listing, leftover scanning, and trashing against side-effecting
/// ports. Request/response over `transport.send` (the handler's returned `Data` is
/// the reply). Not a toggle — no active state, so it never tints the menu bar.
public final class UninstallerEngine: ModuleEngine, @unchecked Sendable {
    private let home: URL
    private let apps: AppLister
    private let fs: FileSystemPort
    private let trash: TrashPort
    private let running: RunningAppsPort
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    public init(home: URL, apps: AppLister, fs: FileSystemPort, trash: TrashPort,
                running: RunningAppsPort, transport: LocalTransport = LocalTransport()) {
        self.home = home
        self.apps = apps
        self.fs = fs
        self.trash = trash
        self.running = running
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    private var library: URL { home.appendingPathComponent("Library") }

    // MARK: - Operations

    public func listApps() async -> [InstalledApp] { apps.installedApps() }

    public func scan(bundleID: String, appPath: String, appName: String) async throws -> ScanResult {
        var leftovers: [Leftover] = []
        for c in LeftoverMatcher.candidates(bundleID: bundleID, appName: appName, library: library) {
            let urls: [URL] = c.isGlob ? fs.glob(c.url) : (fs.exists(c.url) ? [c.url] : [])
            for u in urls {
                leftovers.append(Leftover(path: u.path, kind: c.kind,
                                          sizeBytes: fs.size(u), matchedByName: c.matchedByName))
            }
        }
        leftovers.sort { $0.sizeBytes > $1.sizeBytes }
        return ScanResult(bundleID: bundleID, appPath: appPath,
                          appSizeBytes: fs.size(URL(fileURLWithPath: appPath)),
                          leftovers: leftovers,
                          runningNow: running.isRunning(bundleID: bundleID))
    }

    /// Trashes the selected leftover paths plus the app bundle. Sizes are read
    /// before trashing; only successfully trashed items count toward freedBytes.
    public func uninstall(appPath: String, paths: [String]) async throws -> UninstallResult {
        var targets = paths
        if !targets.contains(appPath) { targets.append(appPath) }
        var trashed: [String] = [], failed: [String] = []
        var freed = 0
        for p in targets {
            let url = URL(fileURLWithPath: p)
            let size = fs.size(url)
            if trash.trash(url) { trashed.append(p); freed += size } else { failed.append(p) }
        }
        return UninstallResult(trashed: trashed, failed: failed, freedBytes: freed)
    }

    public func quit(bundleID: String) { running.quit(bundleID: bundleID) }

    /// Directories whose bundle-id-named entries belong to a single app, so a
    /// leftover there identifies the app that owned it.
    private static let orphanScanDirs: [(String, LeftoverKind)] = [
        ("Application Support", .appSupport),
        ("Caches", .caches),
        ("Preferences", .preferences),
        ("Containers", .containers),
        ("Saved Application State", .savedState),
        ("HTTPStorages", .httpStorages),
        ("WebKit", .webKit),
        ("Application Scripts", .appScripts),
        ("Logs", .logs),
    ]

    /// Finds leftovers whose owning app is no longer installed, grouped by bundle
    /// id. Conservative by design — see `OrphanDetector`.
    public func scanOrphans() async -> [OrphanGroup] {
        let installedIDs = Set(apps.installedApps().map(\.bundleID))
        var byID: [String: [Leftover]] = [:]
        for (dir, kind) in Self.orphanScanDirs {
            for url in fs.children(of: library.appendingPathComponent(dir)) {
                let name = url.lastPathComponent
                guard OrphanDetector.isOrphan(name: name, installedBundleIDs: installedIDs) else { continue }
                let id = OrphanDetector.bundleID(from: name)
                byID[id, default: []].append(
                    Leftover(path: url.path, kind: kind, sizeBytes: fs.size(url), matchedByName: false))
            }
        }
        return byID
            .map { OrphanGroup(bundleID: $0.key, leftovers: $0.value.sorted { $0.sizeBytes > $1.sizeBytes }) }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Trashes arbitrary leftover paths (no app bundle involved).
    public func trashPaths(_ paths: [String]) async -> UninstallResult {
        var trashed: [String] = [], failed: [String] = []
        var freed = 0
        for p in paths {
            let url = URL(fileURLWithPath: p)
            let size = fs.size(url)
            if trash.trash(url) { trashed.append(p); freed += size } else { failed.append(p) }
        }
        return UninstallResult(trashed: trashed, failed: failed, freedBytes: freed)
    }

    // MARK: - Transport (request/response)

    private struct ScanReq: Codable { let bundleID: String; let appPath: String; let appName: String }
    private struct UninstallReq: Codable { let appPath: String; let paths: [String] }
    private struct QuitReq: Codable { let bundleID: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            switch cmd.name {
            case "listApps":
                return (try? JSONEncoder().encode(await self.listApps())) ?? Data()
            case "scan":
                guard let r = try? JSONDecoder().decode(ScanReq.self, from: cmd.payload) else { return Data() }
                let res = try await self.scan(bundleID: r.bundleID, appPath: r.appPath, appName: r.appName)
                return (try? JSONEncoder().encode(res)) ?? Data()
            case "uninstall":
                guard let r = try? JSONDecoder().decode(UninstallReq.self, from: cmd.payload) else { return Data() }
                let res = try await self.uninstall(appPath: r.appPath, paths: r.paths)
                return (try? JSONEncoder().encode(res)) ?? Data()
            case "scanOrphans":
                return (try? JSONEncoder().encode(await self.scanOrphans())) ?? Data()
            case "trashPaths":
                guard let paths = try? JSONDecoder().decode([String].self, from: cmd.payload) else { return Data() }
                return (try? JSONEncoder().encode(await self.trashPaths(paths))) ?? Data()
            case "quit":
                if let r = try? JSONDecoder().decode(QuitReq.self, from: cmd.payload) { self.quit(bundleID: r.bundleID) }
                return Data()
            default:
                return Data()
            }
        }
    }
}
