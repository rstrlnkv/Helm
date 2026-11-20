import Foundation
import HelmContract
import HelmRuntime

/// The app launcher's arrangement: what is installed, what the person put where, what they hid.
///
/// **Synchronous and blocking on disk** — a model hops with `offTheCooperativePool`. One lock
/// covers read, reconcile, edit and save, taken inside one synchronous call and never held
/// across a suspension. The layout is never cached: every `read()` asks the catalog and the file again;
/// only the latest catalog read is kept, so an edit reconciles against what the person saw.
public final class LaunchpadEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down. **The string never changes.**
    public static let moduleID = "launchpad"

    private let catalog: AppCatalogPort
    private let launcher: AppLauncherPort
    private let store: LayoutStore
    private let touches: TrackpadTouchPort
    private let systemPinch: SystemPinchPort
    /// Whether the person switched the pinch on: asked at each activation, so a value edited while the module was off counts.
    private let pinchEnabled: () -> Bool
    /// The localized name of the default arrangement's folder of utilities, asked when a default is built: the engine holds no strings.
    private let utilitiesFolderName: @Sendable () -> String
    private let lock = NSLock()
    /// The latest catalog read, so an edit reconciles against what the person was looking at.
    private var lastCatalog: CatalogReading?
    /// Between `activate()` and `deactivate()`; the pinch is watched only inside it.
    private var active = false
    /// A watch was started and not stopped. With `pinchStart` and `generation`, guarded by `lock`.
    private var watching = false
    /// What the last start came to: nil when none was started since the last stop (the switch is off, the module is not
    /// active); `.noTrackpad` and `.frameworkMissing` when it found nothing to watch (then `watching` is false); `.layoutRefused`
    /// after a stand-down; `.watching` while one runs.
    private var pinchStart: TouchWatchStart?
    /// Which start a frame, a fire or a stand-down belongs to: each start takes the next number, so what the old watch sends late is dropped.
    private var generation = 0
    /// Starts whose call into the port has not returned. A stop that finds one leaves the port to it: the start, on returning, stops what it started if it is no longer wanted.
    private var startsInFlight = 0
    /// Held around every call that starts or stops the port, so a stop decided for an old watch cannot land after a newer start began.
    private let portLock = NSLock()
    /// One recognizer per trackpad, so two pads are never read as one hand; frames and fires since the watch began, for the log.
    private var recognizers: [Int: PinchRecognizer] = [:]
    private var frames = 0
    private var fires = 0

    /// What a recognized pinch or spread does; the descriptor sets it before `activate()`, and it runs on the main actor.
    @MainActor public var onPinch: (PinchDirection) -> Void = { _ in }

    public convenience init(utilitiesFolderName: @escaping @Sendable () -> String, pinchEnabled: @escaping () -> Bool = { false }) {
        self.init(catalog: FileSystemAppCatalog(), launcher: SystemAppLauncher(), store: LayoutStore(), utilitiesFolderName: utilitiesFolderName,
                  touches: MultitouchSupportPort(), systemPinch: SystemTrackpadPreferences(), pinchEnabled: pinchEnabled)
    }

    init(catalog: AppCatalogPort, launcher: AppLauncherPort, store: LayoutStore, utilitiesFolderName: @escaping @Sendable () -> String = { "Utilities" },
         touches: TrackpadTouchPort = MultitouchSupportPort(), systemPinch: SystemPinchPort = SystemTrackpadPreferences(),
         pinchEnabled: @escaping () -> Bool = { false }) {
        self.catalog = catalog
        self.launcher = launcher
        self.store = store
        self.utilitiesFolderName = utilitiesFolderName
        self.touches = touches
        self.systemPinch = systemPinch
        self.pinchEnabled = pinchEnabled
    }

    deinit { touches.stop() }

    public func activate() {
        lock.withLock { active = true }
        if pinchEnabled() { startPinch() }
    }

    public func deactivate() {
        lock.withLock { active = false }
        stopPinch()
    }

    // MARK: - The pinch

    /// What the last start came to (`pinchStart`): nil when nothing was started or it was stopped.
    public var pinchWatch: TouchWatchStart? { lock.withLock { pinchStart } }

    /// What the system's own pinch is set to. Reads defaults, so a model hops with `offTheCooperativePool`.
    public func systemPinchSetting() -> SystemPinch { systemPinch.read() }

    /// Starts or stops the watch for the person's switch. Nothing starts while the module is not active; the answer is nil then.
    @discardableResult public func setPinchWatching(_ on: Bool) -> TouchWatchStart? {
        if on { startPinch() } else { stopPinch() }
        return pinchWatch
    }

    private func startPinch() {
        let started = lock.withLock { () -> Int? in
            guard active, !watching else { return nil }
            watching = true
            generation += 1
            startsInFlight += 1
            frames = 0
            fires = 0
            recognizers = [:]
            return generation
        }
        guard let mine = started else { return }
        let result = portLock.withLock {
            touches.start(onFrame: { [weak self] in self?.handle($0, generation: mine) },
                          onStandDown: { [weak self] in self?.standDown(generation: mine) })
        }
        // The start took time; the module may have left, or a newer start may own the port, meanwhile.
        let (current, kept) = lock.withLock { () -> (Bool, Bool) in
            startsInFlight -= 1
            let current = generation == mine
            let kept = current && watching && active
            if kept {
                pinchStart = result
                if case .watching = result {} else { watching = false }
            }
            return (current, kept)
        }
        guard kept else {
            if current, case .watching = result { stopPort(ifStillGeneration: mine) }
            return
        }
        if case .watching(let devices) = result {
            HelmLog.shared.info(Self.moduleID, "pinch: watching \(devices) trackpad(s)")
        } else if result == .noTrackpad {
            HelmLog.shared.info(Self.moduleID, "pinch: no trackpad to watch")
        } else if result == .frameworkMissing {
            HelmLog.shared.warn(Self.moduleID, "pinch: the trackpad framework or one of its symbols is not there; the pinch is off")
        }
    }

    /// Stops the watch if one runs and says how it went. `keeping` is what the state reads afterwards (a stand-down keeps its
    /// reason). With a `generation`, nothing happens when that start is no longer the current one.
    private func stopPinch(keeping reason: TouchWatchStart? = nil, generation only: Int? = nil) {
        let (counted, stopGeneration) = lock.withLock { () -> ((frames: Int, fires: Int)?, Int?) in
            if let only, only != generation { return (nil, nil) }
            let was = watching
            watching = false
            pinchStart = reason
            return (was ? (frames, fires) : nil, was && startsInFlight == 0 ? generation : nil)
        }
        guard let counted else { return }
        if let stopGeneration { stopPort(ifStillGeneration: stopGeneration) }
        HelmLog.shared.info(Self.moduleID, "pinch: stopped after \(counted.frames) frames and \(counted.fires) fire(s)")
    }

    /// Stops the port unless a newer start has begun: the check and the stop are one step under `portLock`, and a start takes a new generation before it asks for that lock.
    private func stopPort(ifStillGeneration decided: Int) {
        portLock.withLock {
            if lock.withLock({ generation == decided }) { touches.stop() }
        }
    }

    /// The port refused the layout in a row: said once, and the watch ends on a queue of its own, since this is called from the
    /// framework's thread. It ends only the watch it was told of; the person's switch off and on, or the module activated again, watches anew.
    private func standDown(generation mine: Int) {
        let first = lock.withLock { () -> Bool in
            guard watching, generation == mine, pinchStart != .layoutRefused else { return false }
            pinchStart = .layoutRefused
            return true
        }
        guard first else { return }
        HelmLog.shared.warn(Self.moduleID, "pinch: the trackpad's frames were refused in a row; the pinch is off until the switch is turned off and on, or the module is activated again")
        DispatchQueue.global().async { [weak self] in self?.stopPinch(keeping: .layoutRefused, generation: mine) }
    }

    /// On the framework's thread; the recognizer is fed under the lock and nothing else is held. A fire hops to main once, its direction taken first.
    private func handle(_ frame: TouchFrame, generation mine: Int) {
        let fired = lock.withLock { () -> PinchDirection? in
            guard watching, generation == mine else { return nil }
            frames += 1
            var recognizer = recognizers[frame.device] ?? PinchRecognizer()
            let direction = recognizer.feed(frame)
            recognizers[frame.device] = recognizer
            if direction != nil { fires += 1 }
            return direction
        }
        guard let direction = fired else { return }
        DispatchQueue.main.async { [weak self] in
            // Still the watch that saw the hand: one switched off or replaced since lands nothing.
            guard let self, lock.withLock({ watching && active && generation == mine }) else { return }
            MainActor.assumeIsolated { onPinch(direction) }
        }
    }

    /// Reconciled in memory; writes nothing.
    public func read() -> LaunchpadSnapshot {
        lock.lock(); defer { lock.unlock() }
        let reading = catalog.read()
        lastCatalog = reading
        return snapshot(reading, stored: store.load(), layout: nil, saved: true)
    }

    /// nil = refused (a vanished id, an empty name): nothing written, one line in the log without a name. Otherwise the new
    /// snapshot, with `saved` false when the write did not land — the result is still returned.
    public func apply(_ edit: LaunchpadEdit) -> LaunchpadSnapshot? {
        lock.lock(); defer { lock.unlock() }
        let reading = lastCatalog ?? catalog.read()
        lastCatalog = reading
        let stored = store.load()
        let base = storedLayout(of: stored, reading).reconciled(catalog: reading.apps.map(\.id), complete: reading.complete)
        // Reconciled again so an edit that empties the arrangement (a reset) returns the apps in catalog order, as a read would.
        var applied = base.applying(edit)
        if edit == .resetArrangement { applied?.items = defaultArrangement(reading).items }
        guard let edited = applied?.reconciled(catalog: reading.apps.map(\.id), complete: reading.complete) else {
            HelmLog.shared.info(Self.moduleID, "an arrangement edit was refused")
            return nil
        }
        let saved = (stored != .unreadable || store.moveUnreadableAside()) && store.save(edited)
        return snapshot(reading, stored: saved ? .loaded(edited) : stored, layout: edited, saved: saved)
    }

    public func hide(_ id: AppID) -> LaunchpadSnapshot? { apply(.hide(id)) }
    public func unhide(_ id: AppID) -> LaunchpadSnapshot? { apply(.unhide(id)) }
    /// Folders and order go back to the default arrangement; hidden apps stay hidden. Never refused.
    public func resetArrangement() -> LaunchpadSnapshot? { apply(.resetArrangement) }

    /// Calls `onChange` when the installed apps may have changed, until the token is let go.
    /// The engine holds nothing: the token's lifetime is the caller's.
    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        catalog.observeChanges(onChange)
    }

    /// Opens the app with this id **if a fresh read still finds it** and the bundle at its path
    /// still answers the id. The read does not become `lastCatalog`: it is for this launch only.
    /// Blocking disk work goes off the cooperative pool and no lock is held across a suspension.
    public func launch(_ id: AppID) async -> LaunchOutcome {
        let catalog = self.catalog
        let resolution = await offTheCooperativePool {
            LaunchResolution.resolve(id: id, reading: catalog.read(), bundleID: { catalog.bundleID(atPath: $0) })
        }
        switch resolution {
        case .gone:
            HelmLog.shared.info(Self.moduleID, "a launch was refused: the app is no longer installed")
            return .gone
        case .unreadable:
            HelmLog.shared.info(Self.moduleID, "a launch was refused: the app was not among those that could be read")
            return .unreadable
        case .open(let url):
            guard await launcher.open(url) else {
                HelmLog.shared.warn(Self.moduleID, "a launch was refused by the system")
                return .failed
            }
            return .launched
        }
    }

    /// What is stored; the default arrangement when there is no file (an unreadable one shows the catalog's order, as its warning says).
    private func storedLayout(of read: LayoutRead, _ reading: CatalogReading) -> LaunchpadLayout {
        switch read {
        case .loaded(let layout): layout
        case .absent: defaultArrangement(reading)
        case .unreadable: .empty
        }
    }

    private func defaultArrangement(_ reading: CatalogReading) -> LaunchpadLayout {
        .defaultArrangement(for: reading.apps, utilitiesFolderName: utilitiesFolderName())
    }

    private func snapshot(_ reading: CatalogReading, stored: LayoutRead, layout: LaunchpadLayout?, saved: Bool) -> LaunchpadSnapshot {
        let order = reading.apps.map(\.id)
        let reconciled = layout ?? storedLayout(of: stored, reading).reconciled(catalog: order, complete: reading.complete)
        var snap = LaunchpadSnapshot(apps: Dictionary(reading.apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                                     order: order, layout: reconciled, catalogComplete: reading.complete, layoutRead: stored)
        snap.saved = saved
        return snap
    }
}
