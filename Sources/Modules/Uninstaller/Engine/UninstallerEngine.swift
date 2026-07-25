import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates app listing, leftover scanning, and trashing against side-effecting
/// ports. Request/response over `transport.send` (the handler's returned `Data` is
/// the reply). Not a toggle — no active state, so it never tints the menu bar.
public final class UninstallerEngine: ModuleEngine, @unchecked Sendable {
    private let home: URL
    private let apps: AppLister
    private let fs: FileSystemPort
    private let trash: TrashPort
    private let running: RunningAppsPort
    private let extensions: SystemExtensionPort
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    public init(home: URL, apps: AppLister, fs: FileSystemPort, trash: TrashPort,
                running: RunningAppsPort,
                extensions: SystemExtensionPort = NoSystemExtensions(),
                transport: LocalTransport = LocalTransport()) {
        self.home = home
        self.apps = apps
        self.fs = fs
        self.trash = trash
        self.running = running
        self.extensions = extensions
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    /// Runs blocking filesystem work on a dispatch queue so it never parks a
    /// Swift-concurrency pool thread (app-size scans walk whole bundles).
    private func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
        }
    }

    private var library: URL { home.appendingPathComponent("Library") }

    // MARK: - Operations

    public func listApps() async -> [InstalledApp] {
        await blocking { self.apps.installedApps() }
    }

    public func scan(bundleID: String, appPath: String, appName: String) async throws -> ScanResult {
        await blocking { self.scanSync(bundleID: bundleID, appPath: appPath, appName: appName) }
    }

    private func scanSync(bundleID: String, appPath: String, appName: String) -> ScanResult {
        var leftovers: [Leftover] = []
        // Prefix globs overlap the exact candidates they generalise; the same
        // directory must not be listed (or trashed) twice.
        var seenPaths: Set<String> = []
        for c in LeftoverMatcher.candidates(bundleID: bundleID, appName: appName, library: library) {
            let urls: [URL] = c.isGlob ? fs.glob(c.url) : (fs.exists(c.url) ? [c.url] : [])
            for u in urls where seenPaths.insert(u.path).inserted {
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
        await blocking {
            var targets = paths
            if !targets.contains(appPath) { targets.append(appPath) }
            return self.trashSync(targets)
        }
    }

    public func quit(bundleID: String, force: Bool = false) { running.quit(bundleID: bundleID, force: force) }

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
        await blocking { self.scanOrphansSync() }
    }

    private func scanOrphansSync() -> [OrphanGroup] {
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
        await blocking { self.trashSync(paths) }
    }

    /// Reads Info.plist for a bundle so failures can be tied to the app that
    /// owns an active system extension.
    private func bundleID(forAppAt path: String) -> String? {
        let info = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: info)?["CFBundleIdentifier"]) as? String
    }

    /// Shared trashing core: sizes are read before trashing; only successfully
    /// trashed items count toward freedBytes.
    private func trashSync(_ paths: [String]) -> UninstallResult {
        var trashed: [String] = [], failed: [String] = []
        var failures: [TrashFailureInfo] = []
        var freed = 0
        // Only queried when something actually fails — the lookup shells out.
        var extensionHosts: Set<String>?
        for p in paths {
            let url = URL(fileURLWithPath: p)
            let size = fs.size(url)
            let outcome = trash.trashItem(url)
            if outcome.succeeded {
                trashed.append(p); freed += size
            } else if outcome.errorCode == NSFileNoSuchFileError, !fs.exists(url) {
                // Already gone (a duplicate path, or removed meanwhile): there
                // is nothing for the user to act on, so it is not a failure.
                continue
            } else {
                failed.append(p)
                let hosts = extensionHosts ?? extensions.activeExtensionHosts()
                extensionHosts = hosts
                // Match the app's bundle id, not the path: /Applications/X.app
                // never contains "com.vendor.x".
                let blocked = p.hasSuffix(".app") && hosts.contains { host in
                    bundleID(forAppAt: p).map { $0 == host || $0.hasPrefix(host) } ?? false
                }
                failures.append(TrashFailureInfo(
                    path: p,
                    reason: TrashFailure.reason(path: p, errorCode: outcome.errorCode,
                                                hasSystemExtension: blocked).rawValue,
                    message: outcome.message))
            }
        }
        return UninstallResult(trashed: trashed, failed: failed,
                               freedBytes: freed, failures: failures)
    }

    // MARK: - Transport (request/response)

    private struct ScanReq: Codable { let bundleID: String; let appPath: String; let appName: String }
    private struct UninstallReq: Codable { let appPath: String; let paths: [String] }
    private struct QuitReq: Codable { let bundleID: String; let force: Bool? }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            switch cmd.name {
            case "listApps":
                HelmLog.shared.info("uninstaller", "engine listApps start")
                let list = await self.listApps()
                HelmLog.shared.info("uninstaller", "engine listApps done: \(list.count)")
                return (try? JSONEncoder().encode(list)) ?? Data()
            case "scan":
                guard let r = try? JSONDecoder().decode(ScanReq.self, from: cmd.payload) else { return Data() }
                let res = try await self.scan(bundleID: r.bundleID, appPath: r.appPath, appName: r.appName)
                return (try? JSONEncoder().encode(res)) ?? Data()
            case "uninstall":
                guard let r = try? JSONDecoder().decode(UninstallReq.self, from: cmd.payload) else { return Data() }
                let res = try await self.uninstall(appPath: r.appPath, paths: r.paths)
                return (try? JSONEncoder().encode(res)) ?? Data()
            case "systemExtensions":
                let list = await self.blocking { self.extensions.installedExtensions() }
                return (try? JSONEncoder().encode(list)) ?? Data()
            case "scanOrphans":
                return (try? JSONEncoder().encode(await self.scanOrphans())) ?? Data()
            case "trashPaths":
                guard let paths = try? JSONDecoder().decode([String].self, from: cmd.payload) else { return Data() }
                return (try? JSONEncoder().encode(await self.trashPaths(paths))) ?? Data()
            case "quit":
                if let r = try? JSONDecoder().decode(QuitReq.self, from: cmd.payload) {
                    self.quit(bundleID: r.bundleID, force: r.force ?? false)
                }
                return Data()
            default:
                return Data()
            }
        }
    }
}
