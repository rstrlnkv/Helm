import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates app listing, leftover scanning, and trashing against side-effecting
/// ports. The module's model calls its methods directly (`UninstallerWork`); the
/// one thing it says unasked, "look at the Trash again", goes out through
/// `trashChanged`. Not a toggle — no active state, so it never tints the menu bar.
public final class UninstallerEngine: ModuleEngine, BackgroundScanning, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It names stored keys, the `ScanJournal` directory and the log's removals,
    /// and `UninstallerDescriptor.id` is built from it. The string never changes:
    /// it names folders and settings already on people's machines.
    public static let moduleID = "uninstaller"

    private let home: URL
    private let apps: AppLister
    private let fs: FileSystemPort
    private let trash: TrashPort
    private let running: RunningAppsPort
    private let extensions: SystemExtensionPort
    private let fullDiskAccess: FullDiskAccessPort
    private let store: NamespacedStore
    /// The one mutable field without a lock: main-actor confinement makes the
    /// `@unchecked Sendable` true of it. Its callers (`ModuleHost`, the model)
    /// are `@MainActor`.
    private var watcher: FolderWatcher?
    /// The two live facts behind the Trash-offer switch, under a lock because
    /// neither arrives on the main actor. `nil` is "no answer yet", which
    /// `TrashWatch.state` does not read as a failure.
    private let watchLock = NSLock()
    private var watcherStarted: Bool?
    private var trashReadable: Bool?
    /// Whether the last unattended scan was refused for want of the grant, so the
    /// refusal is logged when it begins and not on every wake-up.
    private var refusedForAccess = false
    /// Told that something reached the Trash that could have been an app, or
    /// that the offer was switched on: "look again". May be called from any queue.
    private let trashChanged: @Sendable () -> Void
    /// The running Helm's own bundle id and path, which the door never removes (nil in tests that do not care).
    private let ownApp: (bundleID: String, path: String)?
    /// What each preview counted as the app's own leftovers, by app path: `removeApp` takes no more than that.
    private let previewLock = NSLock()
    private var previewed: [String: Set<String>] = [:]


    /// `store` holds the declined trashed apps, the Trash-offer switch and the
    /// sort order. It defaults to memory, a fresh record per test.
    public init(home: URL, apps: AppLister, fs: FileSystemPort, trash: TrashPort,
                running: RunningAppsPort,
                extensions: SystemExtensionPort = NoSystemExtensions(),
                fullDiskAccess: FullDiskAccessPort = GrantedFullDiskAccess(),
                store: NamespacedStore = NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                        backing: InMemoryKeyValueStore()),
                trashChanged: @escaping @Sendable () -> Void = {},
                ownApp: (bundleID: String, path: String)? = nil) {
        self.ownApp = ownApp
        self.home = home
        self.apps = apps
        self.fs = fs
        self.trash = trash
        self.running = running
        self.extensions = extensions
        self.fullDiskAccess = fullDiskAccess
        self.store = store
        self.trashChanged = trashChanged
    }

    /// Watches `~/.Trash` so that an app dragged there while Helm is running is
    /// noticed then, and not at the next launch.
    ///
    /// The judgement stays with the engine: the host is told "look again"
    /// through `trashChanged`, never "an app arrived". The host's own sweep at
    /// launch is what catches an app trashed while Helm was closed.
    public func activate() {
        startWatchingTrashIfAsked()
    }

    /// Off unless the person turned it on: a window that opens unasked after a
    /// drag needs their say-so. The switch is on the Leftovers tab.
    private static let watchKey = "watchTrash"

    private var watchingTrash: Bool { store.bool(Self.watchKey, default: false) }

    /// What the switch is doing, as against what it says — read, never remembered.
    /// Both things that can make «on» a lie change while the app is running:
    /// FSEvents can refuse the stream, and the grant the read depends on is taken
    /// away by every install and given back in System Settings.
    public var trashWatch: TrashWatch {
        watchLock.withLock {
            TrashWatch.state(on: watchingTrash, watching: watcherStarted,
                             trashReadable: trashReadable)
        }
    }

    private func startWatchingTrashIfAsked() {
        watcher?.stop()
        watcher = nil
        watchLock.withLock { watcherStarted = nil }
        guard watchingTrash else {
            HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer: off")
            return
        }
        let trash = home.appendingPathComponent(".Trash", isDirectory: true).path
        let made = FolderWatcher { [weak self] changed in
            guard let self, TrashArrival.namesAnApp(changed, trash: trash) else { return }
            HelmLog.shared.info(UninstallerEngine.moduleID, "an app reached the Trash")
            self.trashChanged()
        }
        watcher = made
        // The stream's own answer: «on» is true only if something is watching.
        made.watch([trash]) { [weak self] started in
            guard let self else { return }
            self.watchLock.withLock { self.watcherStarted = started }
            guard !started else { return }
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "the Trash watcher did not start, so nothing will be noticed "
                                + "until the next launch")
        }
    }

    /// Whether Helm can read the Trash, from a read that really happened (a nil
    /// `trashedApps()` is a refused listing, not a probe of the grant). Recorded
    /// when the switch goes on and by every sweep, which notices the grant going
    /// and coming back. Logged on every refusal: each is an offer that did not happen.
    private func recordTrashReadable(_ readable: Bool) {
        watchLock.withLock { trashReadable = readable }
        guard !readable else { return }
        HelmLog.shared.warn(UninstallerEngine.moduleID,
                            "Helm cannot read the Trash, so the offer will not appear")
    }

    /// Stopped here rather than left to the watcher's `deinit`, which runs only
    /// once the engine itself is released.
    public func deactivate() {
        watcher?.stop()
        watcher = nil
    }

    /// Where every leftover this module knows about lives.
    private var library: URL { home.appendingPathComponent("Library") }

    // MARK: - Operations

    public func listApps() async -> [InstalledApp] {
        HelmLog.shared.info(UninstallerEngine.moduleID, "engine listApps start")
        let list = await offTheCooperativePool { self.apps.installedApps() }
        HelmLog.shared.info(UninstallerEngine.moduleID, "engine listApps done: \(list.count)")
        return list
    }

    /// Sizes for the list already on screen, passed in so the app folders and
    /// every `Info.plist` are not read a second time.
    public func appSizes(_ list: [InstalledApp]) async -> [String: Int] {
        let sizes = await HelmActivity.phase("uninstaller.appSizes") {
            await offTheCooperativePool { self.apps.appSizes(list) }
        }
        HelmLog.shared.memory("uninstaller.appSizes")
        return sizes
    }

    // MARK: - Order and last-opened dates

    private static let sortOrderKey = "sortOrder"

    /// Read from the store on every ask, so a value written elsewhere is judged
    /// when used and nothing cached goes stale. Not sealed: it steers no
    /// unattended work, and a seal read while a view is built is a keychain
    /// dialog on every install.
    public var sortOrder: AppSortOrder {
        AppSortOrder(stored: store.string(Self.sortOrderKey, default: ""))
    }

    public func setSortOrder(_ order: AppSortOrder) {
        guard order != sortOrder else { return }
        store.set(order.rawValue, for: Self.sortOrderKey)
    }

    /// The most bundles one read looks up, and the longest it may take: the
    /// ceilings are for a Mac where Spotlight is reindexing. What the read did
    /// not reach comes back as `unread`, which is not "no record".
    public static let lastOpenedCeiling = 1_000
    public static let lastOpenedDeadline: TimeInterval = 5

    /// Off the pool, bounded, and a date later than now is dropped: a clock that
    /// was wrong when the app was opened is not evidence of when it was.
    ///
    /// The deadline bounds the whole read, not the gap between two lookups, so
    /// one hung Spotlight call cannot carry it. The lookups run on a worker of
    /// their own and the caller is answered at the deadline with what the worker
    /// had; the rest reads as `unread`. A hung call cannot be interrupted, so the
    /// worker stops when it returns. While one is stuck, a new read starts no
    /// second worker (Refresh would stack a thread per press) and answers
    /// everything as `unread`.
    public func lastOpened(_ list: [InstalledApp],
                           deadline: TimeInterval = UninstallerEngine.lastOpenedDeadline,
                           ceiling: Int = UninstallerEngine.lastOpenedCeiling,
                           now: Date = Date()) async -> AppOpenedReading {
        let reading: AppOpenedReading
        if list.isEmpty {
            reading = AppOpenedReading(opened: [:], unread: [])
        } else if !claimOpenedWorker() {
            reading = AppOpenedReading(opened: [:], unread: list.map(\.path))
        } else {
            reading = await withCheckedContinuation { continuation in
                let read = OpenedRead(paths: list.map(\.path), ceiling: ceiling,
                                      continuation: continuation)
                DispatchQueue.global(qos: .userInitiated).async { [apps] in
                    read.run(until: Date().addingTimeInterval(deadline)) { path in
                        guard let date = apps.lastOpened(path: path), date <= now else { return nil }
                        return date
                    }
                    // Given back before the caller is answered, so a read made
                    // straight after finds the worker free.
                    self.releaseOpenedWorker()
                    read.answer()
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) {
                    read.cutShort()
                }
            }
        }
        if !reading.unread.isEmpty {
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "last-opened read stopped early: \(reading.unread.count) of \(list.count) not read")
        }
        return reading
    }

    private let openedWorkerLock = NSLock()
    private var openedWorkerBusy = false

    private func claimOpenedWorker() -> Bool {
        openedWorkerLock.withLock {
            if openedWorkerBusy { return false }
            openedWorkerBusy = true
            return true
        }
    }

    private func releaseOpenedWorker() { openedWorkerLock.withLock { openedWorkerBusy = false } }

    public func scan(bundleID: String, appName: String) async -> ScanResult {
        await offTheCooperativePool { self.scanSync(bundleID: bundleID, appName: appName) }
    }

    private func scanSync(bundleID: String, appName: String) -> ScanResult {
        var leftovers: [Leftover] = []
        // Prefix globs overlap the exact candidates they generalise; the same
        // directory must not be listed (or trashed) twice.
        var seenPaths: Set<String> = []
        // The ownership facts are gathered once per scan, and only when there is
        // something to judge: an app with no leftovers pays for no listing.
        var ownership: LeftoverOwnership?
        // Counted by path: a glob and the exact candidate it generalises reach
        // the same entry.
        var refusedPaths: Set<String> = []
        for c in LeftoverMatcher.candidates(bundleID: bundleID, appName: appName, library: library) {
            var urls: [URL] = c.isGlob ? fs.glob(c.url) : (fs.exists(c.url) ? [c.url] : [])
            // A candidate built from the display name arrives unticked and holds
            // no id for these rules to weigh: `claims` would refuse every one of
            // them (`ANameIsAGuessNotAnOwnershipQuestionTests`).
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
        return ScanResult(leftovers: leftovers, runningNow: running.isRunning(bundleID: bundleID))
    }

    /// The per-scan ownership facts, read once each: the app folders' listing,
    /// the bundles declaring this id, and LaunchServices for what neither of
    /// those can see. Its answers are remembered for the scan: the folders ask
    /// about the same few ids, each a round trip to the system.
    private func makeOwnership(bundleID: String) -> LeftoverOwnership {
        LeftoverOwnership(
            bundleID: bundleID,
            installedBundleIDs: apps.installedBundleIDs(),
            installedPaths: apps.installedPaths(forBundleID: bundleID),
            knownToSystem: rememberingLaunchServices())
    }

    /// One scan's LaunchServices answers, each asked once.
    private func rememberingLaunchServices() -> (String) -> Bool {
        var answers: [String: Bool] = [:]
        return { [apps] id in
            if let remembered = answers[id] { return remembered }
            let answer = apps.isKnownToSystem(bundleID: id)
            answers[id] = answer
            return answer
        }
    }

    /// A refusal that leaves no trace reads exactly like a scan that found
    /// nothing, and those two want different answers from whoever opens the
    /// log. Ids are tags: a bundle id names somebody's habits.
    private func report(_ refused: Set<String>, bundleID: String, contested: Bool) {
        if contested {
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "scan \(Redact.app(bundleID)): the id is declared by more than one "
                                + "installed bundle, so nothing derived from it is this app's")
        }
        guard !refused.isEmpty else { return }
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "scan \(Redact.app(bundleID)): refused \(refused.count) "
                            + "candidate(s) belonging to another installed app")
    }

    func quit(bundleID: String, force: Bool) { running.quit(bundleID: bundleID, force: force) }

    /// Waits for a quit to have actually happened.
    ///
    /// `quit` only asks. A bundle moved while its app still runs gets its
    /// preferences written back on exit, so the removed leftovers return; a fixed
    /// sleep is either that or a needless wait.
    ///
    /// The deadline ends the wait, not the question. An app that ignores a
    /// quit does not make this fail or throw; `trashPaths` asks whether the app
    /// still runs once this returns, and a batch still holding one moves nothing.
    func waitUntilGone(bundleID: String,
                      deadline: TimeInterval = 5,
                      poll: TimeInterval = 0.05) async {
        let until = Date().addingTimeInterval(deadline)
        // Each poll is a blocking AppKit read: off the cooperative pool, the sleep
        // between polls stays a suspension (Architecture/RunningOtherPrograms.md § Running applications).
        while await offTheCooperativePool({ self.running.isRunning(bundleID: bundleID) }),
              Date() < until {
            try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
        }
    }

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

    /// One lock over read-change-write of the dismissed set, so the sweep's prune
    /// and a cancel cannot overwrite each other. Neither suspends while holding it.
    private let dismissedLock = NSLock()

    /// What is sitting in the Trash that left something behind, minus what has
    /// already been declined, in the order the Trash listed, which the window draws.
    public func trashedAppLeftovers() async -> [TrashedAppLeftovers] {
        await offTheCooperativePool { self.trashedAppLeftoversSync() }
    }

    private func trashedAppLeftoversSync() -> [TrashedAppLeftovers] {
        // Judged here, not by the caller: the engine is the one authority on
        // what it offers.
        guard watchingTrash else { return [] }
        // A refused read is the switch's row being wrong, not an empty Trash.
        guard let found = apps.trashedApps() else {
            recordTrashReadable(false)
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "trash sweep: nothing to offer, the Trash was not readable")
            return []
        }
        recordTrashReadable(true)
        // Four outcomes give no window, and the log tells them apart: no app in
        // the Trash, declined before, another copy installed, nothing left
        // behind. Counts only; a bundle id names somebody's habits.
        var stillInstalled = 0, nothingLeft = 0
        dismissedLock.lock()
        var dismissed = Set(store.stringArray(Self.dismissedKey))
        // Swept before it is read: an app that has left the Trash — restored, or
        // finally deleted — takes its "no" with it, so removing the same app later
        // is a new question rather than one already answered.
        let kept = TrashOfferMemory.stillDismissed(dismissed, found: found)
        if kept != dismissed {
            store.set(Array(kept), for: Self.dismissedKey)
            dismissed = kept
        }
        dismissedLock.unlock()

        let offerable = TrashOfferMemory.toOffer(found: found, dismissed: dismissed)
        let groups = offerable
            .compactMap { app -> TrashedAppLeftovers? in
                // Two copies of one app share a bundle id, and trashing one leaves
                // the other using its support files. LaunchServices reports every
                // copy it has seen, stale builds included; `InstalledLocation`
                // keeps only the ones that count.
                guard apps.installedPaths(forBundleID: app.bundleID).isEmpty else {
                    stillInstalled += 1
                    return nil
                }
                let result = scanSync(bundleID: app.bundleID, appName: app.name)
                guard !result.leftovers.isEmpty else {
                    nothingLeft += 1
                    return nil
                }
                return TrashedAppLeftovers(bundleID: app.bundleID, name: app.name,
                                           appPath: app.path, leftovers: result.leftovers)
            }
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "trash sweep: \(found.count) app(s) in the Trash, "
                            + "\(found.count - offerable.count) declined before, "
                            + "\(stillInstalled) still installed elsewhere, "
                            + "\(nothingLeft) left nothing behind, "
                            + "\(groups.count) to offer")
        return groups
    }

    /// The switch, written through the engine so turning it on starts the
    /// watcher at once rather than at the next launch.
    ///
    /// Turning it on also asks whether the Trash is readable, so the person gets
    /// the answer at the press, and emits `trashChanged`, so the host sweeps the
    /// apps already there.
    public func setWatchingTrash(_ on: Bool) {
        guard on != watchingTrash else { return }
        store.set(on, for: Self.watchKey)
        HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer switched \(on ? "on" : "off")")
        startWatchingTrashIfAsked()
        guard on else { return }
        recordTrashReadable(apps.trashIsReadable())
        trashChanged()
    }

    /// Cancel. Remembered so the window does not return for this app at the next
    /// launch, and forgotten when the app leaves the Trash.
    public func dismissTrashedApp(bundleID: String) {
        dismissedLock.lock()
        defer { dismissedLock.unlock() }
        var dismissed = Set(store.stringArray(Self.dismissedKey))
        dismissed.insert(bundleID)
        store.set(Array(dismissed), for: Self.dismissedKey)
    }

    /// Finds leftovers whose owning app is no longer installed, grouped by bundle
    /// id. Conservative by design — see `OrphanDetector`.
    public func scanOrphans() async -> [OrphanGroup] {
        await offTheCooperativePool { self.scanOrphansSync() }
    }

    /// The same orphan hunt the page runs, started by the timer.
    ///
    /// No `ScanRoot` gate: this walks `orphanScanDirs` under `~/Library`, a list
    /// in the source, so nothing stored can point it elsewhere.
    ///
    /// Every leftover is an item, with its own bytes; there is no survivor to
    /// keep, since the owning app is gone.
    public func backgroundScan() async -> ScanReport? {
        // `FileSystemPort.children` answers empty for missing and for unreadable,
        // and `installedBundleIDs` has no error channel. With nobody watching,
        // both failures look like answers. A failed installed list is worse than
        // an unread folder: `OrphanDetector.isOrphan` would then make every
        // bundle-id-shaped folder under `~/Library` a removal candidate.
        //
        // A local install drops the Full Disk Access grant every time
        // (Architecture/Release.md § Signing and grants), so the grant is asked
        // first, before a single listing; only `.granted` goes on, and no answer
        // is not one.
        let access = await offTheCooperativePool { [fullDiskAccess] in fullDiskAccess.fullDiskAccess() }
        let refused = access != .granted
        let wasRefused = watchLock.withLock { () -> Bool in
            defer { refusedForAccess = refused }
            return refusedForAccess
        }
        guard !refused else {
            if !wasRefused {
                HelmLog.shared.warn("scan", "uninstaller: Full Disk Access not confirmed — "
                                    + "no unattended leftovers scan")
            }
            return nil
        }
        let checks = await offTheCooperativePool { [apps, fs, library] in
            (installed: apps.installedBundleIDs(),
             library: fs.children(of: library).count)
        }
        guard checks.library > 0 else {
            HelmLog.shared.warn("scan", "uninstaller: ~/Library unreadable — not a clean scan")
            return nil
        }
        let groups = await scanOrphans()
        // A Library holding third-party folders while no app is installed is a
        // contradiction, not a discovery.
        guard !checks.installed.isEmpty || groups.isEmpty else {
            HelmLog.shared.warn("scan",
                                "uninstaller: no installed apps readable — refusing "
                                + "\(groups.count) would-be orphans")
            return nil
        }
        let items = groups.flatMap { group in
            group.leftovers.map { ScanItem(path: $0.path, bytes: $0.sizeBytes) }
        }
        return ScanReport(bytes: items.reduce(0) { $0 + $1.bytes },
                          count: items.count, items: items)
    }

    private func scanOrphansSync() -> [OrphanGroup] {
        let installedIDs = apps.installedBundleIDs()
        let knownToSystem = rememberingLaunchServices()
        var byID: [String: [Leftover]] = [:]
        for (dir, kind) in Self.orphanScanDirs {
            for url in fs.children(of: library.appendingPathComponent(dir)) {
                let name = url.lastPathComponent
                guard OrphanDetector.isOrphan(name: name, installedBundleIDs: installedIDs,
                                              knownToSystem: knownToSystem)
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

    /// Trashes a batch of paths, which may hold app bundles, asking first who
    /// is running.
    ///
    /// The review's `running` flag (`ScanResult.runningNow`) is stale in both
    /// directions by the press, and a bundle moved from under a live process
    /// gets its leftovers written back on exit: a local flag standing in for a
    /// live fact (Architecture/TheGates.md § The gates). So the question is asked
    /// where the answer is used, and again after the quitting.
    ///
    /// The deadline ends the wait, not the question: an app can come back up
    /// while the others quit, or ignore the quit, and macOS moves a running
    /// app's bundle without a word.
    public func trashPaths(_ paths: [String],
                           quittingRunningApps mayQuit: Bool = false) async -> UninstallResult {
        await trashPaths(paths, quittingRunningApps: mayQuit, stillAllowed: nil)
    }

    /// `stillAllowed`, when given, is asked once more after a quit and before the move: the quit wait
    /// is long enough for the folder, the link or the bundle's id to have changed. False moves nothing.
    private func trashPaths(_ paths: [String], quittingRunningApps mayQuit: Bool,
                            stillAllowed: (@Sendable () -> Bool)?) async -> UninstallResult {
        // Off the pool: this reads each bundle's `Info.plist`, and the running
        // port reaches AppKit through the main thread
        // (Architecture/RunningOtherPrograms.md § Running applications).
        let upNow = await offTheCooperativePool { self.runningApps(among: paths) }
        switch UninstallPlan.verdict(running: upNow, mayQuit: mayQuit) {
        case .proceed:
            break
        case .refuse(let apps):
            return held(apps, because: "no quit allowed")
        case .quitFirst(let apps):
            for app in apps {
                HelmLog.shared.info(UninstallerEngine.moduleID, "force quit \(Redact.app(app.bundleID))")
                await offTheCooperativePool { self.quit(bundleID: app.bundleID, force: true) }
                await waitUntilGone(bundleID: app.bundleID)
            }
            // `mayQuit: false`: the quit has been spent.
            let stillUp = await offTheCooperativePool { self.runningApps(among: paths) }
            if case .refuse(let up) = UninstallPlan.verdict(running: stillUp, mayQuit: false) {
                return held(up, because: "still up after the quit")
            }
            if let stillAllowed, !(await offTheCooperativePool { stillAllowed() }) {
                HelmLog.shared.info(UninstallerEngine.moduleID, "batch refused: the app changed while it was quit")
                return UninstallResult(trashed: [], freedBytes: 0)
            }
        }
        return await offTheCooperativePool { self.trashSync(paths) }
    }

    // MARK: - Removing one app for another module

    /// How long the preview waits for the bundle's size. A big bundle takes seconds to walk,
    /// and the card says no size rather than wait or show a wrong one.
    static let appSizeDeadline: TimeInterval = 2

    /// The verdict, as the Uninstaller would give it now: the folder, link and scope rules
    /// (`AppRemovability`), then the bundle's own `Info.plist` — a bundle that says another id than
    /// the candidate carried is not the app the person was shown. Reads files: off the main thread.
    private func removalVerdict(_ candidate: AppRemovalCandidate) -> AppRemovalVerdict {
        let verdict = AppRemovability.verdict(candidate, home: home.path, ownApp: ownApp)
        guard verdict == .removable else { return verdict }
        return WorkspaceAppLister.bundleID(forAppAt: candidate.path) == candidate.bundleID
            ? .removable : .refused(.notOffered)
    }

    public func removalVerdicts(for candidates: [AppRemovalCandidate]) async -> [AppRemovalVerdict] {
        await offTheCooperativePool { candidates.map { self.removalVerdict($0) } }
    }

    /// The verdict, and only for a removable app the leftovers scan: nothing is scanned for a refused one.
    private enum Judged: Sendable { case refused(AppRemovalVerdict.Refusal), scanned(ScanResult) }

    private func judgedAndScanned(_ candidate: AppRemovalCandidate) async -> Judged {
        await offTheCooperativePool {
            if case .refused(let why) = self.removalVerdict(candidate) {
                HelmLog.shared.info(UninstallerEngine.moduleID, "app removal refused: \(why)")
                return .refused(why)
            }
            return .scanned(self.scanSync(bundleID: candidate.bundleID, appName: candidate.name))
        }
    }

    /// What removing this app would take. The leftovers are the review's default selection
    /// (`UninstallPlan.ownLeftovers`), found by bundle id and never by name.
    public func removalPreview(_ candidate: AppRemovalCandidate) async -> AppRemovalAsk {
        await removalPreview(candidate, sizeDeadline: Self.appSizeDeadline)
    }

    func removalPreview(_ candidate: AppRemovalCandidate, sizeDeadline: TimeInterval) async -> AppRemovalAsk {
        switch await judgedAndScanned(candidate) {
        case .refused(let why):
            return .refused(why)
        case .scanned(let scan):
            let own = UninstallPlan.ownLeftovers(scan.leftovers)
            previewLock.withLock { previewed[candidate.path] = Set(own.map(\.path)) }
            let bytes = await measured(candidate.path, deadline: sizeDeadline)
            return .ready(AppRemovalPreview(appBytes: bytes, leftoverCount: own.count,
                                            leftoverBytes: own.reduce(0) { $0 + $1.sizeBytes },
                                            running: scan.runningNow))
        }
    }

    /// The bundle's size, or nil when the walk had not finished at the deadline. The walk cannot be
    /// interrupted and is left to end on its own; whoever answers first, once, resumes the caller.
    private func measured(_ path: String, deadline: TimeInterval) async -> Int? {
        await withCheckedContinuation { continuation in
            let answer = OnceAnswer(continuation)
            DispatchQueue.global(qos: .userInitiated).async { [fs] in
                answer.give(fs.size(URL(fileURLWithPath: path)))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) {
                answer.give(nil)
            }
        }
    }

    /// Moves one app and what the card counted as its own to the Trash, through `trashPaths` — the only
    /// removal this module has — so the gate and the "is it running" question are the ones a batch
    /// from the page meets, the second asked again after the quit loop.
    ///
    /// The verdict is asked here, not trusted from a list read earlier, and again after a quit
    /// (`stillAllowed`): the app can have been swapped, linked or started since the card.
    /// The bundle goes alone and first. A batch of both would send the leftovers to the Trash while
    /// macOS refused the bundle, and the app would be back with its data gone. The leftovers are the
    /// ones the preview counted and the fresh scan still finds — nothing that appeared after the card.
    public func removeApp(_ candidate: AppRemovalCandidate,
                          quittingIfRunning mayQuit: Bool) async -> AppRemovalReport {
        guard case .scanned(let scan) = await judgedAndScanned(candidate) else { return AppRemovalReport(.refused) }
        let counted = previewLock.withLock { previewed.removeValue(forKey: candidate.path) } ?? []
        let leftovers = UninstallPlan.ownLeftovers(scan.leftovers).map(\.path).filter { counted.contains($0) }
        let bundle = await trashPaths([candidate.path], quittingRunningApps: mayQuit,
                                      stillAllowed: { self.removalVerdict(candidate) == .removable })
        guard bundle.stillRunning.isEmpty else { return AppRemovalReport(.stillRunning) }
        guard bundle.trashed.contains(candidate.path) else {
            HelmLog.shared.info(UninstallerEngine.moduleID, "app removal: refused, nothing moved")
            return AppRemovalReport(.refused, failed: bundle.failures.map(\.reason))
        }
        let rest = leftovers.isEmpty ? UninstallResult(trashed: [], freedBytes: 0)
            : await trashPaths(leftovers, quittingRunningApps: false)
        let failed = (bundle.failures + rest.failures).map(\.reason)
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "app removal: moved, \(rest.trashed.count) of \(leftovers.count) leftovers moved")
        return AppRemovalReport(failed.isEmpty ? .moved : .movedWithFailures,
                                freedBytes: bundle.freedBytes + rest.freedBytes, failed: failed)
    }

    /// Nothing moved, and the applications that are why. One result for both
    /// refusals: a leftover carries no link back to its app, so there is no
    /// "the rest of it" to move (`UninstallPlan.verdict`).
    private func held(_ apps: [UninstallPlan.RunningApp], because why: String) -> UninstallResult {
        // Counts and tags: a bundle id names somebody's habits.
        HelmLog.shared.info(UninstallerEngine.moduleID, "batch held: \(apps.count) app(s) running, "
                            + "\(why) (\(apps.map { Redact.app($0.bundleID) }.joined(separator: ",")))")
        return UninstallResult(trashed: [], freedBytes: 0, stillRunning: apps.map(\.path))
    }

    /// The applications in a batch that are up at this moment.
    ///
    /// The id comes from the bundle's own `Info.plist`: a batch carries paths and
    /// the port answers about ids. A batch of leftovers alone asks nothing.
    private func runningApps(among paths: [String]) -> [UninstallPlan.RunningApp] {
        paths.filter(Self.isAppBundle).compactMap { path in
            guard let id = WorkspaceAppLister.bundleID(forAppAt: path),
                  running.isRunning(bundleID: id) else { return nil }
            return UninstallPlan.RunningApp(path: path, bundleID: id)
        }
    }

    /// The two questions a batch asks only of applications — is this one still
    /// running, and is it the host of a live system extension — asked the same
    /// way, because they are the same question about the path.
    private static func isAppBundle(_ path: String) -> Bool { path.hasSuffix(".app") }

    /// Shared trashing core: `HelmTrash` runs the batch — the order, the sizing,
    /// the classification and the refusals — and this supplies the two things
    /// only the uninstaller knows.
    private func trashSync(_ paths: [String]) -> UninstallResult {
        // A view model built the plan and is not the last word on what is
        // deleted: a candidate that escaped its folder stops here.
        let (allowed, refused) = RemovableScope.partition(paths, home: home.path)
        // Asked only when a bundle fails to move, since the lookup shells out.
        // A silence is never stored: nil means "ask again", so one failed
        // `systemextensionsctl` does not read as «no extensions» for the rest of
        // the batch.
        var extensionHosts: Set<String>?
        // What macOS said, verbatim, per path. It does not cross `HelmTrash`'s
        // `Result`, and the failure sheet draws it under the classified reason.
        var saidByPath: [String: String] = [:]
        let result = HelmTrash.remove(
            allowed: allowed, outOfScope: refused, module: Self.moduleID,
            // The leaf of an app bundle is the name the person gave it and of a
            // leftover a bundle id; neither belongs in the log.
            leaf: .softwareName,
            hasSystemExtension: { path in
                guard Self.isAppBundle(path) else { return false }
                // Match the app's bundle id, not the path: /Applications/X.app
                // never contains "com.vendor.x".
                guard let id = WorkspaceAppLister.bundleID(forAppAt: path) else { return false }
                guard let hosts = extensionHosts ?? self.extensions.activeExtensionHosts() else {
                    // The tool did not answer: claim neither way, keep macOS's
                    // own classification, and say so in the log.
                    HelmLog.shared.warn(Self.moduleID,
                                        "the extension list could not be read, so a refusal "
                                        + "cannot be blamed on a live extension")
                    return false
                }
                extensionHosts = hosts
                // The separator matters: "at.obdev.littlesnitchmini" starts with
                // "at.obdev.littlesnitch" and is a different product, whose
                // extension the person would be sent to turn off.
                return hosts.contains { id == $0 || id.hasPrefix($0 + ".") }
            },
            trashing: { url in
                let outcome = self.trash.trashItem(url)
                guard !outcome.succeeded else { return }
                saidByPath[url.path] = outcome.message
                throw NSError(domain: NSCocoaErrorDomain, code: outcome.errorCode,
                              userInfo: outcome.message.isEmpty
                                  ? nil : [NSLocalizedDescriptionKey: outcome.message])
            })
        return UninstallResult(
            trashed: result.removed, freedBytes: result.freedBytes,
            failures: result.refused.map {
                TrashFailureInfo(path: $0.path, reason: $0.reason,
                                 message: saidByPath[$0.path] ?? "")
            })
    }
}

/// A continuation resumed by whichever of two answers arrives first, once.
private final class OnceAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int?, Never>?
    init(_ continuation: CheckedContinuation<Int?, Never>) { self.continuation = continuation }
    func give(_ value: Int?) {
        let taken = lock.withLock { () -> CheckedContinuation<Int?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        taken?.resume(returning: value)
    }
}

/// One last-opened read in flight: the worker fills it in, and whichever of the
/// worker finishing and the deadline arrives first answers the caller, once.
private final class OpenedRead: @unchecked Sendable {
    private let lock = NSLock()
    private let paths: [String]
    private let ceiling: Int
    private var continuation: CheckedContinuation<AppOpenedReading, Never>?
    private var opened: [String: Date] = [:]
    /// How many paths have been looked up to the end. The one being looked up
    /// now is not counted, so a call that never returns reads as `unread`.
    private var done = 0
    private var stopped = false

    init(paths: [String], ceiling: Int, continuation: CheckedContinuation<AppOpenedReading, Never>) {
        self.paths = paths
        self.ceiling = ceiling
        self.continuation = continuation
    }

    /// Reads until done, the ceiling or the deadline. It does **not** answer: the
    /// caller of the worker gives the worker back first and then calls `answer()`.
    func run(until: Date, lookup: (String) -> Date?) {
        for (index, path) in paths.enumerated() {
            guard index < ceiling, Date() < until, !isStopped else { break }
            let date = lookup(path)
            lock.withLock {
                if let date { opened[path] = date }
                done = index + 1
            }
        }
    }

    var isStopped: Bool { lock.withLock { stopped } }

    /// The deadline: stop the worker and answer with what it has.
    func cutShort() {
        lock.withLock { stopped = true }
        answer()
    }

    func answer() {
        let taken: (CheckedContinuation<AppOpenedReading, Never>, AppOpenedReading)? = lock.withLock {
            guard let continuation else { return nil }
            self.continuation = nil
            let reading = AppOpenedReading(opened: opened, unread: Array(paths[min(done, paths.count)...]))
            return (continuation, reading)
        }
        taken.map { $0.0.resume(returning: $0.1) }
    }
}
