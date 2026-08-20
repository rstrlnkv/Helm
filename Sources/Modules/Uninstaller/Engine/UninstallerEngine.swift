import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates app listing, leftover scanning, and trashing against side-effecting
/// ports. Request/response over `transport.send` (the handler's returned `Data` is
/// the reply). Not a toggle — no active state, so it never tints the menu bar.
public final class UninstallerEngine: ModuleEngine, BackgroundScanning, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk in shapes nothing would flag if they disagreed: the
    /// `module.uninstaller.*` keys of a store, the directory `ScanJournal` names after
    /// it, and the removal attributed to it in the log. `UninstallerDescriptor.id`
    /// is built from this rather than repeating it, the direction the
    /// descriptors already carry their command enums, so the two spellings are
    /// one. **The string itself never changes** — it names folders and stored
    /// settings that are already on people's machines.
    public static let moduleID = "uninstaller"

    private let home: URL
    private let apps: AppLister
    private let fs: FileSystemPort
    private let trash: TrashPort
    private let running: RunningAppsPort
    private let extensions: SystemExtensionPort
    private let store: NamespacedStore
    /// The only mutable field here, and main-actor confinement is what makes the
    /// `@unchecked Sendable` above true. `activate` and `deactivate` are called
    /// from `ModuleHost`, which is `@MainActor`; the `setWatchingTrash` arm of
    /// the transport handler hops there for the same reason.
    private var watcher: FolderWatcher?
    /// The two live facts behind the Trash-offer switch, and the lock is because
    /// neither of them arrives on the main actor: the watcher answers on its own
    /// queue, and the Trash read happens inside a sweep off the cooperative pool.
    /// `nil` means "no answer yet" in both, which `TrashWatch.state` reads as
    /// nothing-known-against-it rather than as a failure.
    private let watchLock = NSLock()
    private var watcherStarted: Bool?
    private var trashReadable: Bool?
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    /// `store` holds one thing: which trashed apps the person has already declined
    /// to clean up after. Defaulted to memory so the thirteen tests that build this
    /// engine directly keep working — and a fresh record per test is what a test
    /// wants anyway.
    public init(home: URL, apps: AppLister, fs: FileSystemPort, trash: TrashPort,
                running: RunningAppsPort,
                extensions: SystemExtensionPort = NoSystemExtensions(),
                store: NamespacedStore = NamespacedStore(namespace: UninstallerEngine.moduleID,
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
            self.localTransport.emit(EngineEvent(name: UninstallerEvent.trashChanged.rawValue))
        }
        watcher = made
        // The stream's own answer, which used to be thrown away — so this method
        // logged «trash offer switched on» whether or not anything was watching.
        made.watch([trash]) { [weak self] started in
            guard let self else { return }
            self.watchLock.withLock { self.watcherStarted = started }
            guard !started else { return }
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "the Trash watcher did not start, so nothing will be noticed "
                                + "until the next launch")
        }
    }

    /// Whether Helm can read the Trash, from a read that really happened — a `nil`
    /// out of `trashedApps()` is a refused `contentsOfDirectory`, not a probe of
    /// the grant. Recorded when the switch goes on, because the person is owed the
    /// answer at the moment they press it, and by every sweep after that, which is
    /// what notices the grant being taken away or given back. Logged on every
    /// refusal rather than on a change: each one is an offer that did not happen.
    private func recordTrashReadable(_ readable: Bool) {
        watchLock.withLock { trashReadable = readable }
        guard !readable else { return }
        HelmLog.shared.warn(UninstallerEngine.moduleID,
                            "Helm cannot read the Trash, so the offer will not appear")
    }

    /// Stopped here and not only in `deinit`: the stream holds this object, so a
    /// `deinit` that waits for the stream to go away waits forever.
    public func deactivate() {
        watcher?.stop()
        watcher = nil
    }

    /// Where every leftover this module knows about lives.
    ///
    /// It carried a doc comment about running blocking work on a dispatch queue
    /// so a pool thread is never parked — true of this engine, and about
    /// `offTheCooperativePool`, which the operations below call directly. The
    /// helper that sentence described is gone and the sentence stayed, over the
    /// next declaration it found. Homebrew's engine had the same orphan.
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
        let sizes = await HelmActivity.phase("uninstaller.appSizes") {
            await offTheCooperativePool { self.apps.appSizes(list) }
        }
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
            // carries no id for these rules to weigh. **Not a check that was
            // skipped: applying it here deletes the guesses**, since `claims`
            // asks where the bundle id sits in the name and a display name holds
            // none — measured, and the log then calls them another app's
            // (`ANameIsAGuessNotAnOwnershipQuestionTests`). Whether another
            // installed app is *called* this is a different question, and
            // nothing on this path reads the installed display names.
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
            HelmLog.shared.warn(UninstallerEngine.moduleID,
                                "scan \(Redact.app(bundleID)): the id is declared by more than one "
                                + "installed bundle, so nothing derived from it is this app's")
        }
        guard !refused.isEmpty else { return }
        HelmLog.shared.info(UninstallerEngine.moduleID,
                            "scan \(Redact.app(bundleID)): refused \(refused.count) "
                            + "candidate(s) belonging to another installed app")
    }

    public func quit(bundleID: String, force: Bool = false) { running.quit(bundleID: bundleID, force: force) }

    /// Waits for a quit to have actually happened.
    ///
    /// `quit` only *asks*. The caller then moves the app's bundle, and it used
    /// to guess the gap with `Task.sleep(800ms)` in the view model — a number
    /// where the answer was already available, since this engine holds the port
    /// that can be asked. Too short and the bundle moves while the app still
    /// runs: the process keeps going from the moved bundle and writes its
    /// preferences on exit, so the leftovers an uninstall just removed come
    /// back. Too long and everyone waits for an app that stopped in 50 ms.
    ///
    /// **The deadline proceeds rather than refuses.** An app that ignores a
    /// quit must not block a removal the person explicitly asked for; the
    /// failures come back from `trashSync` and are shown.
    public func waitUntilGone(bundleID: String,
                              deadline: TimeInterval = 5,
                              poll: TimeInterval = 0.05) async {
        let until = Date().addingTimeInterval(deadline)
        while running.isRunning(bundleID: bundleID), Date() < until {
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
        // The read is the reverse channel: a refusal here is the switch's own row
        // being wrong, and it used to arrive as «the Trash holds no apps» — the
        // same silence a working sweep of an empty Trash gives.
        guard let found = apps.trashedApps() else {
            recordTrashReadable(false)
            HelmLog.shared.info(UninstallerEngine.moduleID,
                                "trash sweep: nothing to offer, the Trash was not readable")
            return []
        }
        recordTrashReadable(true)
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
        HelmLog.shared.info(UninstallerEngine.moduleID,
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
    /// Turning it on also asks the one question the whole feature rests on — can
    /// this process read the Trash — because the person is owed the answer at the
    /// moment they press the switch and not at whichever sweep comes next. One
    /// `contentsOfDirectory`, on a press.
    public func setWatchingTrash(_ on: Bool) {
        guard on != watchingTrash else { return }
        store.set(on, for: Self.watchKey)
        HelmLog.shared.info(UninstallerEngine.moduleID, "trash offer switched \(on ? "on" : "off")")
        startWatchingTrashIfAsked()
        guard on else { return }
        recordTrashReadable(apps.trashedApps() != nil)
        localTransport.emit(EngineEvent(name: UninstallerEvent.trashChanged.rawValue))
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

    /// The same orphan hunt the page runs, started by the timer.
    ///
    /// **No `ScanRoot` gate here, and that is not an oversight.** The other
    /// unattended scan reads a folder the person chose and Helm stored, so a
    /// rewritten plist would redirect it. This one walks `orphanScanDirs` under
    /// `~/Library` — a list in the source, not a setting — so there is nothing
    /// stored for anybody to point somewhere else.
    ///
    /// Every leftover is an item: what acting on the finding removes is each
    /// path, and the bytes are its own. Unlike duplicates there is no survivor
    /// to keep — the app these belong to is already gone.
    public func backgroundScan() async -> ScanReport? {
        // `FileSystemPort.children` answers "empty" for missing **and** for
        // unreadable — its own doc says so — and `installedBundleIDs` has no
        // error channel at all. Neither matters on the page, where a person is
        // looking at the result and knows whether they granted the permission.
        // With nobody watching, both failures wear the shape of an answer, and
        // the two directions are not equally bad.
        //
        // Reporting nothing found is a lie about a folder nobody read. Reporting
        // everything found is worse: `OrphanDetector.isOrphan` treats "not among
        // the installed apps" as evidence, so an `installedBundleIDs()` that
        // failed is indistinguishable from a Mac with no apps — and then every
        // bundle-id-shaped folder under `~/Library` becomes a removal candidate,
        // unattended.
        //
        // CLAUDE.md records that a local install drops the Full Disk Access
        // grant **every time**, so an unreadable Library is the ordinary state
        // after an update, not an exotic one.
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

    /// Trashes a batch of paths, which may hold app bundles.
    public func trashPaths(_ paths: [String],
                           quittingRunningApps mayQuit: Bool = false) async -> UninstallResult {
        await removeBatch(paths, quittingRunningApps: mayQuit)
    }

    /// The batch, with the one question that must not be carried from the scan
    /// asked again first.
    ///
    /// The review screen's `running` flag is `ScanResult.runningNow`, read when
    /// the review was built, and it is stale in both directions by the time
    /// anybody presses anything: an app the person has since quit leaves the
    /// button dead, and an app started since then has its bundle moved out from
    /// under a live process — which then writes its preferences on exit and puts
    /// back the leftovers this batch has just taken. That is the family CLAUDE.md
    /// names: a local flag standing in for a live external fact. The flag is not
    /// made fresher; the question is asked where the answer is used, and again
    /// after the quitting — which is itself long enough to have changed it.
    private func removeBatch(_ paths: [String],
                             quittingRunningApps mayQuit: Bool) async -> UninstallResult {
        // Off the pool: this reads each bundle's `Info.plist`, and the running
        // port reaches AppKit through the main thread (ARCHITECTURE § Running
        // applications).
        let upNow = await offTheCooperativePool { self.runningApps(among: paths) }
        switch UninstallPlan.verdict(running: upNow, mayQuit: mayQuit) {
        case .proceed:
            break
        case .refuse(let apps):
            return held(apps, because: "no quit allowed")
        case .quitFirst(let apps):
            for app in apps {
                HelmLog.shared.info(UninstallerEngine.moduleID, "force quit \(Redact.app(app.bundleID))")
                quit(bundleID: app.bundleID, force: true)
                // Returns when the app is actually gone. It used to be the view
                // model's business, decided there from the same stale flag.
                await waitUntilGone(bundleID: app.bundleID)
            }
            // **And the reading above is older than the move.** Two ordinary
            // things happen inside a deadline per app: one comes back up while
            // the batch quits the others — a login item, a helper, a double
            // click — or it ignores the quit and the deadline proceeds. macOS
            // moves a running app's bundle without a word, so neither refuses
            // anything, and the process writes its preferences on exit and puts
            // back the leftovers this batch has just taken. Asked again, then,
            // where the answer is used; `mayQuit: false` because the quit has
            // been spent, which is `verdict`'s existing rule at a later moment.
            let stillUp = await offTheCooperativePool { self.runningApps(among: paths) }
            if case .refuse(let up) = UninstallPlan.verdict(running: stillUp, mayQuit: false) {
                return held(up, because: "still up after the quit")
            }
        }
        return await offTheCooperativePool { self.trashSync(paths) }
    }

    /// Nothing moved, and the applications that are why. One result for both
    /// refusals because they are one outcome — a leftover carries no link back
    /// to the app it was found for, so there is no "the rest of it"
    /// (`UninstallPlan.verdict`).
    private func held(_ apps: [UninstallPlan.RunningApp], because why: String) -> UninstallResult {
        // Counts and tags: a bundle id names somebody's habits.
        HelmLog.shared.info(UninstallerEngine.moduleID, "batch held: \(apps.count) app(s) running, "
                            + "\(why) (\(apps.map { Redact.app($0.bundleID) }.joined(separator: ",")))")
        return UninstallResult(trashed: [], freedBytes: 0, stillRunning: apps.map(\.path))
    }

    /// The applications in a batch that are up at this moment.
    ///
    /// The id comes from the bundle's own `Info.plist` — the same read that ties
    /// a refusal to the app owning a system extension — because a path is what a
    /// batch carries and the port answers about ids. A batch of leftovers alone
    /// asks nothing of anybody.
    private func runningApps(among paths: [String]) -> [UninstallPlan.RunningApp] {
        paths.filter(Self.isAppBundle).compactMap { path in
            guard let id = bundleID(forAppAt: path),
                  running.isRunning(bundleID: id) else { return nil }
            return UninstallPlan.RunningApp(path: path, bundleID: id)
        }
    }

    /// The two questions a batch asks only of applications — is this one still
    /// running, and is it the host of a live system extension — asked the same
    /// way, because they are the same question about the path.
    private static func isAppBundle(_ path: String) -> Bool { path.hasSuffix(".app") }

    /// Reads Info.plist for a bundle so failures can be tied to the app that
    /// owns an active system extension.
    private func bundleID(forAppAt path: String) -> String? {
        let info = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: info)?["CFBundleIdentifier"]) as? String
    }

    /// Shared trashing core: `HelmTrash` runs the batch — the order, the sizing,
    /// the classification and the refusals — and this supplies the two things
    /// only the uninstaller knows.
    ///
    /// It used to be a copy of that loop, and the copy was missing what only
    /// shows up on a tree: a file basketed with the folder above it was reported
    /// as neither moved nor refused, two names for one file were counted twice
    /// over, and which of those happened depended on the order the paths
    /// arrived in.
    private func trashSync(_ paths: [String]) -> UninstallResult {
        // Same rule as the leftovers engine: the plan is built in a view model,
        // and a view model is not allowed to be the last word on what gets
        // deleted. A candidate that escaped its folder stops here.
        let (allowed, refused) = RemovableScope.partition(paths, home: home.path)
        // Only queried when a bundle actually fails to move — the lookup shells
        // out. **A silence is never stored here**: this holds an answer, so nil
        // means "ask again". One `systemextensionsctl` that failed to run was
        // remembered as «this Mac has no extensions» for the rest of the batch, and
        // every bundle after it lost the one reason on that sheet a person can act
        // on. Asking again costs one shell-out per *failing* app bundle.
        var extensionHosts: Set<String>?
        // What macOS said, verbatim, per path. `HelmTrash` classifies the error
        // and logs the sentence, and the sentence does not cross its `Result`;
        // the failure sheet draws it under the classified reason as the evidence
        // behind it, so this module keeps it as it goes past.
        var saidByPath: [String: String] = [:]
        let result = HelmTrash.remove(
            allowed: allowed, outOfScope: refused, module: Self.moduleID,
            hasSystemExtension: { path in
                guard Self.isAppBundle(path) else { return false }
                // Match the app's bundle id, not the path: /Applications/X.app
                // never contains "com.vendor.x".
                guard let id = self.bundleID(forAppAt: path) else { return false }
                guard let hosts = extensionHosts ?? self.extensions.activeExtensionHosts() else {
                    // The tool did not answer, so nothing here knows whether an
                    // extension is why macOS refused. It claims neither way and
                    // says so: `HelmTrash` keeps macOS's own classification, and
                    // the log is where a missing button is explained.
                    HelmLog.shared.warn(Self.moduleID,
                                        "the extension list could not be read, so a refusal "
                                        + "cannot be blamed on a live extension")
                    return false
                }
                extensionHosts = hosts
                // The separator matters: "at.obdev.littlesnitchmini" starts with
                // "at.obdev.littlesnitch" and is a different product. Without the
                // dot, the user is sent to turn off someone else's extension while
                // the real reason — no permission — is hidden.
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

    // MARK: - Transport (request/response)

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            guard let name = UninstallerCommand(rawValue: cmd.name) else { return Data() }
            switch name {
            case .listApps:
                HelmLog.shared.info(UninstallerEngine.moduleID, "engine listApps start")
                let list = await self.listApps()
                HelmLog.shared.info(UninstallerEngine.moduleID, "engine listApps done: \(list.count)")
                return EngineReply.encode(list, for: cmd)
            case .appSizes:
                guard let list = EngineReply.decode([InstalledApp].self, from: cmd)
                else { return Data() }
                return EngineReply.encode(await self.appSizes(list), for: cmd)
            case .scan:
                guard let r = EngineReply.decode(UninstallScanRequest.self, from: cmd)
                else { return Data() }
                let res = try await self.scan(bundleID: r.bundleID, appPath: r.appPath, appName: r.appName)
                return EngineReply.encode(res, for: cmd)
            case .scanOrphans:
                return EngineReply.encode(await self.scanOrphans(), for: cmd)
            case .backgroundScan:
                return EngineReply.encode(await self.backgroundScan(), for: cmd)
            case .trashedAppLeftovers:
                return EngineReply.encode(await self.trashedAppLeftovers(), for: cmd)
            case .watchingTrash:
                // The state, not the flag: a `Bool` here was the whole of what the
                // page could know, so «on» was all it could draw.
                return EngineReply.encode(self.trashWatch, for: cmd)
            case .setWatchingTrash:
                // The one arm that writes `watcher`, so it goes where the other
                // two writers already are. `send` runs this handler on the
                // caller's own executor, and nobody awaits this reply — the
                // sweep it asks for arrives as `trashChanged`.
                let on = EngineReply.decode(Bool.self, from: cmd) ?? false
                await MainActor.run { self.setWatchingTrash(on) }
                return Data()
            case .dismissTrashedApp:
                self.dismissTrashedApp(bundleID: String(decoding: cmd.payload, as: UTF8.self))
                return Data()
            case .trashPaths:
                guard let batch = EngineReply.decode(TrashBatchRequest.self, from: cmd)
                else { return Data() }
                let done = await self.trashPaths(batch.paths,
                                                 quittingRunningApps: batch.quitRunningApps)
                return EngineReply.encode(done, for: cmd)
            case .quit:
                if let r = EngineReply.decode(QuitRequest.self, from: cmd) {
                    self.quit(bundleID: r.bundleID, force: r.force)
                    // The command returns when the app is gone, so the caller
                    // does not have to guess how long that takes.
                    await self.waitUntilGone(bundleID: r.bundleID)
                }
                return Data()
            }
        }
    }
}
