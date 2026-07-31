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
    private let store: NamespacedStore
    private var watcher: FolderWatcher?
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// `store` holds one thing: which trashed apps the person has already declined
    /// to clean up after. Defaulted to memory so the thirteen tests that build this
    /// engine directly keep working — and a fresh record per test is what a test
    /// wants anyway.
    public init(home: URL, apps: AppLister, fs: FileSystemPort, trash: TrashPort,
                running: RunningAppsPort,
                extensions: SystemExtensionPort = NoSystemExtensions(),
                store: NamespacedStore = NamespacedStore(namespace: "uninstaller",
                                                        backing: InMemoryKeyValueStore()),
                transport: LocalTransport = LocalTransport()) {
        self.home = home
        self.apps = apps
        self.fs = fs
        self.trash = trash
        self.running = running
        self.extensions = extensions
        self.store = store
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    /// Watches `~/.Trash` so that an app dragged there while Helm is running is
    /// noticed then, and not at the next launch.
    ///
    /// The watcher belongs to the engine and the judgement stays with it: the
    /// host is told "look again", never "an app arrived", and it learns that
    /// through the transport's event stream, which is the channel it is already
    /// allowed to use. The sweep on activate stays — it is the only thing that
    /// catches an app deleted while Helm was closed.
    public func activate() {
        startWatchingTrashIfAsked()
    }

    /// Off unless somebody turned it on. A window that opens unasked, a second
    /// after a drag, is not something to hand people without their say-so — so the
    /// default is silence, and the switch on the module's Leftovers tab is what
    /// changes it.
    private static let watchKey = "watchTrash"

    private var watchingTrash: Bool { store.bool(Self.watchKey, default: false) }

    private func startWatchingTrashIfAsked() {
        watcher?.stop()
        watcher = nil
        guard watchingTrash else {
            HelmLog.shared.info("uninstaller", "trash offer: off")
            return
        }
        let trash = home.appendingPathComponent(".Trash", isDirectory: true).path
        let made = FolderWatcher { [weak self] changed in
            guard let self, TrashArrival.namesAnApp(changed, trash: trash) else { return }
            HelmLog.shared.info("uninstaller", "an app reached the Trash")
            self.localTransport.emit(EngineEvent(name: Self.trashChangedEvent))
        }
        watcher = made
        made.watch([trash])
    }

    /// Stopped here and not only in `deinit`: the stream holds this object, so a
    /// `deinit` that waits for the stream to go away waits forever.
    public func deactivate() {
        watcher?.stop()
        watcher = nil
    }

    /// "Look again" — it carries nothing, because what is in the Trash and
    /// whether any of it is worth offering is answered by `trashedAppLeftovers`
    /// and by nobody else.
    public static let trashChangedEvent = "trashChanged"

    /// Runs blocking filesystem work on a dispatch queue so it never parks a
    /// Swift-concurrency pool thread (app-size scans walk whole bundles).
    private var library: URL { home.appendingPathComponent("Library") }

    // MARK: - Operations

    public func listApps() async -> [InstalledApp] {
        await offTheCooperativePool { self.apps.installedApps() }
    }

    /// Sizes for the list already on screen — which is why the list arrives as
    /// an argument. Asking `installedApps()` for it again re-read the app
    /// folders and re-parsed every `Info.plist` seconds after `listApps()` did,
    /// for a list the caller was already holding.
    public func appSizes(_ list: [InstalledApp]) async -> [String: Int] {
        let sizes = await offTheCooperativePool { self.apps.appSizes(list) }
        HelmLog.shared.memory("uninstaller.appSizes")
        return sizes
    }

    public func scan(bundleID: String, appPath: String, appName: String) async throws -> ScanResult {
        await offTheCooperativePool { self.scanSync(bundleID: bundleID, appPath: appPath, appName: appName) }
    }

    private func scanSync(bundleID: String, appPath: String, appName: String) -> ScanResult {
        var leftovers: [Leftover] = []
        // Prefix globs overlap the exact candidates they generalise; the same
        // directory must not be listed (or trashed) twice.
        var seenPaths: Set<String> = []
        // Every candidate below is derived from the app's bundle id, and the
        // facts that can refute a claim on one refute the claim on all of them,
        // so they are gathered once per scan rather than per candidate — and
        // only when there is something to judge, since an app with no leftovers
        // should not pay for a directory listing.
        var ownership: LeftoverOwnership?
        // Refusals are the point of this gate, so they are counted by path (a
        // glob and the exact candidate it generalises reach the same entry).
        var refusedPaths: Set<String> = []
        for c in LeftoverMatcher.candidates(bundleID: bundleID, appName: appName, library: library) {
            var urls: [URL] = c.isGlob ? fs.glob(c.url) : (fs.exists(c.url) ? [c.url] : [])
            // A candidate built from the display name is a different guess with
            // a different default — `defaultSelection` leaves it unticked — and
            // carries no id for these rules to weigh.
            if !c.matchedByName, !urls.isEmpty {
                let owner = ownership ?? makeOwnership(bundleID: bundleID)
                ownership = owner
                let kept = urls.filter { owner.claims(name: $0.lastPathComponent) }
                if kept.count != urls.count {
                    let keptPaths = Set(kept.map(\.path))
                    for u in urls where !keptPaths.contains(u.path) { refusedPaths.insert(u.path) }
                }
                urls = kept
            }
            for u in urls where seenPaths.insert(u.path).inserted {
                leftovers.append(Leftover(path: u.path, kind: c.kind,
                                          sizeBytes: fs.size(u), matchedByName: c.matchedByName))
            }
        }
        report(refusedPaths, bundleID: bundleID, contested: ownership?.idIsContested ?? false)
        leftovers.sort { $0.sizeBytes > $1.sizeBytes }
        return ScanResult(bundleID: bundleID, appPath: appPath,
                          // Zero, deliberately: nothing reads this, and filling it walked the
                          // whole bundle again — a median of 49 ms per app, 3.2 s for Xcode,
                          // while the user waits for the review screen. The size shown there
                          // comes from `InstalledApp`, which already has it.
                          appSizeBytes: 0,
                          leftovers: leftovers,
                          runningNow: running.isRunning(bundleID: bundleID))
    }

    /// The per-scan ownership facts, read once each: the app folders' listing,
    /// the bundles declaring this id, and LaunchServices for what neither of
    /// those can see. Its answers are remembered for the length of the scan —
    /// five folders of entries ask about the same handful of ids, and each
    /// question is a round trip to the system.
    private func makeOwnership(bundleID: String) -> LeftoverOwnership {
        var answers: [String: Bool] = [:]
        return LeftoverOwnership(
            bundleID: bundleID,
            installedBundleIDs: apps.installedBundleIDs(),
            installedPaths: apps.installedPaths(forBundleID: bundleID),
            knownToSystem: { [apps] id in
                if let remembered = answers[id] { return remembered }
                let answer = apps.isKnownToSystem(bundleID: id)
                answers[id] = answer
                return answer
            })
    }

    /// A refusal that leaves no trace reads exactly like a scan that found
    /// nothing, and those two want different answers from whoever opens the
    /// log. Ids are tags: a bundle id names somebody's habits.
    private func report(_ refused: Set<String>, bundleID: String, contested: Bool) {
        if contested {
            HelmLog.shared.warn("uninstaller",
                                "scan \(Redact.app(bundleID)): the id is declared by more than one "
                                + "installed bundle, so nothing derived from it is this app's")
        }
        guard !refused.isEmpty else { return }
        HelmLog.shared.info("uninstaller",
                            "scan \(Redact.app(bundleID)): refused \(refused.count) "
                            + "candidate(s) belonging to another installed app")
    }

    /// Trashes the selected leftover paths plus the app bundle. Sizes are read
    /// before trashing; only successfully trashed items count toward freedBytes.
    public func uninstall(appPath: String, paths: [String]) async throws -> UninstallResult {
        await offTheCooperativePool {
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

    // MARK: - Apps the person dragged to the Trash themselves

    private static let dismissedKey = "trashOfferDismissed"

    /// What is sitting in the Trash that left something behind, minus what has
    /// already been declined.
    ///
    /// One command rather than several, because the host cannot import this target
    /// and reach these pieces one at a time (Package.swift, HelmApp's dependencies).
    ///
    /// The order is the order the Trash listed, which is the order the window draws
    /// its groups in.
    public func trashedAppLeftovers() async -> [TrashedAppLeftovers] {
        await offTheCooperativePool { self.trashedAppLeftoversSync() }
    }

    private func trashedAppLeftoversSync() -> [TrashedAppLeftovers] {
        // Judged here rather than by whoever asks. The engine is the module's one
        // authority on what it will offer, and a host that had the answer and was
        // trusted to keep quiet about it is a rule enforced in the wrong place.
        guard watchingTrash else { return [] }
        let found = apps.trashedApps()
        // Four different outcomes used to look identical from outside — no
        // window — and one of them is a defect while three are the feature
        // working: the Trash holds no app, the app was declined before, another
        // copy is still installed, or it left nothing behind. Counts only; a
        // bundle id names somebody's habits.
        var stillInstalled = 0, nothingLeft = 0
        var dismissed = Set(store.stringArray(Self.dismissedKey))
        // Swept before it is read: an app that has left the Trash — restored, or
        // finally deleted — takes its "no" with it, so removing the same app later
        // is a new question rather than one already answered.
        let kept = TrashOfferMemory.stillDismissed(dismissed, found: found)
        if kept != dismissed {
            store.set(Array(kept), for: Self.dismissedKey)
            dismissed = kept
        }

        let offerable = TrashOfferMemory.toOffer(found: found, dismissed: dismissed)
        let groups = offerable
            .compactMap { app -> TrashedAppLeftovers? in
                // Two copies of one app share a bundle id, and dragging one to the
                // Trash leaves the other installed with its support files in use.
                // `installedPaths` is what makes that answerable: LaunchServices
                // reports every copy it has ever seen — five stale build copies of
                // Helm itself, on this machine — and `InstalledLocation` is the
                // positional rule that keeps only the ones that count.
                guard apps.installedPaths(forBundleID: app.bundleID).isEmpty else {
                    stillInstalled += 1
                    return nil
                }
                let result = scanSync(bundleID: app.bundleID, appPath: app.path,
                                      appName: app.name)
                guard !result.leftovers.isEmpty else {
                    nothingLeft += 1
                    return nil
                }
                return TrashedAppLeftovers(bundleID: app.bundleID, name: app.name,
                                           appPath: app.path, leftovers: result.leftovers)
            }
        HelmLog.shared.info("uninstaller",
                            "trash sweep: \(found.count) app(s) in the Trash, "
                            + "\(found.count - offerable.count) declined before, "
                            + "\(stillInstalled) still installed elsewhere, "
                            + "\(nothingLeft) left nothing behind, "
                            + "\(groups.count) to offer")
        return groups
    }

    /// The switch, read and written through the engine so that turning it on
    /// starts the watcher in the same breath — a setting that only takes effect
    /// at the next launch is a setting people report as broken.
    ///
    /// Turning it on also emits `trashChanged`, which makes the host sweep: the
    /// person just asked to be told about apps in the Trash, and the ones already
    /// sitting there are the first thing they meant.
    public func setWatchingTrash(_ on: Bool) {
        guard on != watchingTrash else { return }
        store.set(on, for: Self.watchKey)
        HelmLog.shared.info("uninstaller", "trash offer switched \(on ? "on" : "off")")
        startWatchingTrashIfAsked()
        if on { localTransport.emit(EngineEvent(name: Self.trashChangedEvent)) }
    }

    /// Cancel. Remembered so the window does not return for this app at the next
    /// launch, and forgotten when the app leaves the Trash.
    public func dismissTrashedApp(bundleID: String) {
        var dismissed = Set(store.stringArray(Self.dismissedKey))
        dismissed.insert(bundleID)
        store.set(Array(dismissed), for: Self.dismissedKey)
    }

    /// Finds leftovers whose owning app is no longer installed, grouped by bundle
    /// id. Conservative by design — see `OrphanDetector`.
    public func scanOrphans() async -> [OrphanGroup] {
        await offTheCooperativePool { self.scanOrphansSync() }
    }

    private func scanOrphansSync() -> [OrphanGroup] {
        let installedIDs = apps.installedBundleIDs()
        var byID: [String: [Leftover]] = [:]
        for (dir, kind) in Self.orphanScanDirs {
            for url in fs.children(of: library.appendingPathComponent(dir)) {
                let name = url.lastPathComponent
                guard OrphanDetector.isOrphan(name: name, installedBundleIDs: installedIDs,
                                              knownToSystem: { self.apps.isKnownToSystem(bundleID: $0) })
                else { continue }
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
        await offTheCooperativePool { self.trashSync(paths) }
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
        // Same rule as the leftovers engine: the plan is built in a view model,
        // and a view model is not allowed to be the last word on what gets
        // deleted. A candidate that escaped its folder stops here.
        let (allowed, refused) = RemovableScope.partition(paths, home: home.path)
        for p in refused {
            HelmLog.shared.warn("uninstaller", "refused out-of-scope path: \(Redact.path(p))")
            failed.append(p)
            failures.append(TrashFailureInfo(path: p,
                                             reason: TrashFailure.Reason.outOfScope.rawValue,
                                             message: ""))
        }
        for p in allowed {
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
                // The separator matters: "at.obdev.littlesnitchmini" starts with
                // "at.obdev.littlesnitch" and is a different product. Without the
                // dot, the user is sent to turn off someone else's extension while
                // the real reason — no permission — is hidden.
                let blocked = p.hasSuffix(".app") && hosts.contains { host in
                    bundleID(forAppAt: p).map { $0 == host || $0.hasPrefix(host + ".") } ?? false
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
            case "appSizes":
                guard let list = try? JSONDecoder().decode([InstalledApp].self, from: cmd.payload)
                else { return Data() }
                let sizes = await self.appSizes(list)
                return (try? JSONEncoder().encode(sizes)) ?? Data()
            case "scan":
                guard let r = try? JSONDecoder().decode(ScanReq.self, from: cmd.payload) else { return Data() }
                let res = try await self.scan(bundleID: r.bundleID, appPath: r.appPath, appName: r.appName)
                return (try? JSONEncoder().encode(res)) ?? Data()
            case "uninstall":
                guard let r = try? JSONDecoder().decode(UninstallReq.self, from: cmd.payload) else { return Data() }
                let res = try await self.uninstall(appPath: r.appPath, paths: r.paths)
                return (try? JSONEncoder().encode(res)) ?? Data()
            case "systemExtensions":
                let list = await offTheCooperativePool { self.extensions.installedExtensions() }
                return (try? JSONEncoder().encode(list)) ?? Data()
            case "scanOrphans":
                return (try? JSONEncoder().encode(await self.scanOrphans())) ?? Data()
            case "trashedAppLeftovers":
                return (try? JSONEncoder().encode(await self.trashedAppLeftovers())) ?? Data()
            case "watchingTrash":
                return (try? JSONEncoder().encode(self.watchingTrash)) ?? Data()
            case "setWatchingTrash":
                self.setWatchingTrash((try? JSONDecoder().decode(Bool.self, from: cmd.payload)) ?? false)
                return Data()
            case "dismissTrashedApp":
                self.dismissTrashedApp(bundleID: String(decoding: cmd.payload, as: UTF8.self))
                return Data()
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
