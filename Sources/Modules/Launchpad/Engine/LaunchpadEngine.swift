import Foundation
import HelmContract
import HelmRuntime

/// The app launcher's arrangement: what is installed, what the person put where, what they hid.
///
/// **Synchronous and blocking on disk** — a model hops with `offTheCooperativePool`. `lock`
/// covers read, reconcile, edit and save, taken inside one synchronous call and never held
/// across a suspension. The pinch has a lock of its own, `pinchLock` (the activation flag, the watch, the recognizers, the mailbox, the
/// scrub's owner): the framework's thread and main must never wait on a disk read. Order: `portLock`, then `pinchLock`; `lock` is
/// never taken inside `pinchLock` nor the other way round. The layout is never cached: every `read()` asks the catalog and the file again;
/// only the latest catalog read is kept, so an edit reconciles against what the person saw.
public final class LaunchpadEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down. **The string never changes.**
    public static let moduleID = "launchpad"

    private let catalog: AppCatalogPort
    private let launcher: AppLauncherPort
    private let store: LayoutStore
    /// Launches counted per app, beside the layout file; its lock is taken after `lock` and never before it.
    private let counts: LaunchCountStore
    private let touches: TrackpadTouchPort
    private let systemPinch: SystemPinchPort
    /// Whether the person switched the pinch on: asked at each activation, so a value edited while the module was off counts.
    private let pinchEnabled: () -> Bool
    /// The localized name of the default arrangement's folder of utilities, asked when a default is built: the engine holds no strings.
    private let utilitiesFolderName: @Sendable () -> String
    private let lock = NSLock()
    /// See the type's comment: guards everything below that says "under `pinchLock`", and `active`.
    private let pinchLock = NSLock()
    private let now: @Sendable () -> TimeInterval
    /// The latest catalog read, so an edit reconciles against what the person was looking at.
    private var lastCatalog: CatalogReading?
    /// Between `activate()` and `deactivate()`; the pinch is watched only inside it.
    private var active = false
    /// A watch was started and not stopped. With `pinchStart` and `generation`, under `pinchLock`.
    private var watching = false
    /// What the last start came to: nil when none was started since the last stop (the switch is off, the module is not
    /// active); `.noTrackpad` and `.frameworkMissing` when it found nothing to watch (then `watching` is false); `.layoutRefused`
    /// after a stand-down; `.watching` while one runs.
    private var pinchStart: TouchWatchStart?
    /// Which start a frame, an event or a stand-down belongs to: each start takes the next number, so what the old watch sends late is dropped.
    private var generation = 0
    /// Starts whose call into the port has not returned. A stop that finds one leaves the port to it: the start, on returning, stops what it started if it is no longer wanted.
    private var startsInFlight = 0
    /// Held around every call that starts or stops the port (but the engine's `deinit`, when nothing else holds the engine), so a stop decided for an old watch cannot land after a newer start began.
    private let portLock = NSLock()
    /// One recognizer per trackpad, so two pads are never read as one hand; frames, scrubs begun and scrubs completed since the watch began, for the log.
    private var recognizers: [Int: PinchRecognizer] = [:]
    private var frames = 0
    private var scrubs = 0
    private var completions = 0
    /// What the pinch said and main has not yet heard, in order, under `pinchLock`. A `moved` replaces a `moved` at the end, so a main
    /// thread that is busy holds three events at most per scrub, not a frame's worth a hundred times a second.
    private var mailbox: [PinchEvent] = []
    /// A hop to main is on its way to empty `mailbox`, so another is not scheduled. Under `pinchLock`.
    private var drainScheduled = false
    /// The pad whose scrub main is following: the one scrub at a time, and a second pad's is dropped. Under `pinchLock`.
    private var scrubOwner: Int?
    /// When the owner's last frame arrived (`now`), and whether a check for its silence is on its way. Under `pinchLock`.
    private var ownerHeardAt: TimeInterval = 0
    private var silenceCheckScheduled = false
    /// A pad that sends nothing for this long (seconds) in the middle of a scrub has gone (a Bluetooth drop): the scrub is reverted.
    static let silenceLimit: TimeInterval = 0.5
    private static let silenceCheckEvery: TimeInterval = 0.25

    /// What a hand does to the window, one event at a time in order (`PinchEvent`); the descriptor sets it before `activate()`,
    /// and it runs on the main actor. A scrub that main was told began is always told it ended: a watch that stops inside one, or a pad that falls silent in one, delivers `.ended(.revert)`.
    @MainActor public var onPinch: (PinchEvent) -> Void = { _ in }

    public convenience init(utilitiesFolderName: @escaping @Sendable () -> String, pinchEnabled: @escaping () -> Bool = { false }) {
        self.init(catalog: FileSystemAppCatalog(), launcher: SystemAppLauncher(), store: LayoutStore(), utilitiesFolderName: utilitiesFolderName,
                  touches: MultitouchSupportPort(), systemPinch: SystemTrackpadPreferences(), pinchEnabled: pinchEnabled)
    }

    init(catalog: AppCatalogPort, launcher: AppLauncherPort, store: LayoutStore, utilitiesFolderName: @escaping @Sendable () -> String = { "Utilities" },
         touches: TrackpadTouchPort = MultitouchSupportPort(), systemPinch: SystemPinchPort = SystemTrackpadPreferences(),
         pinchEnabled: @escaping () -> Bool = { false }, now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        self.catalog = catalog
        self.launcher = launcher
        self.store = store
        counts = LaunchCountStore(directory: store.directory)
        self.utilitiesFolderName = utilitiesFolderName
        self.touches = touches
        self.systemPinch = systemPinch
        self.pinchEnabled = pinchEnabled
    }

    deinit { touches.stop() }

    public func activate() {
        pinchLock.withLock { active = true }
        if pinchEnabled() { startPinch() }
    }

    public func deactivate() {
        pinchLock.withLock { active = false }
        stopPinch()
    }

    // MARK: - The pinch

    /// What the last start came to (`pinchStart`): nil when nothing was started or it was stopped.
    public var pinchWatch: TouchWatchStart? { pinchLock.withLock { pinchStart } }

    /// What the system's own pinch is set to. Reads defaults, so a model hops with `offTheCooperativePool`.
    public func systemPinchSetting() -> SystemPinch { systemPinch.read() }

    /// Starts or stops the watch for the person's switch. Nothing starts while the module is not active; the answer is nil then.
    @discardableResult public func setPinchWatching(_ on: Bool) -> TouchWatchStart? {
        if on { startPinch() } else { stopPinch() }
        return pinchWatch
    }

    private func startPinch() {
        let started = pinchLock.withLock { () -> Int? in
            guard active, !watching else { return nil }
            watching = true
            generation += 1
            startsInFlight += 1
            frames = 0
            scrubs = 0
            completions = 0
            recognizers = [:]
            scrubOwner = nil
            silenceCheckScheduled = false
            return generation
        }
        guard let mine = started else { return }
        let result = portLock.withLock {
            touches.start(onFrame: { [weak self] in self?.handle($0, generation: mine) },
                          onStandDown: { [weak self] in self?.standDown(generation: mine) })
        }
        // The start took time; the module may have left, or a newer start may own the port, meanwhile.
        let (current, kept) = pinchLock.withLock { () -> (Bool, Bool) in
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
        let (counted, stopGeneration, schedule) = pinchLock.withLock { () -> ((frames: Int, scrubs: Int, completions: Int)?, Int?, Bool) in
            if let only, only != generation { return (nil, nil, false) }
            let was = watching
            watching = false
            pinchStart = reason
            var schedule = false
            if was { schedule = endScrubs() }
            return (was ? (frames, scrubs, completions) : nil, was && startsInFlight == 0 ? generation : nil, schedule)
        }
        guard let counted else { return }
        if schedule { scheduleDrain() }
        if let stopGeneration { stopPort(ifStillGeneration: stopGeneration) }
        HelmLog.shared.info(Self.moduleID, "pinch: stopped after \(counted.frames) frames, \(counted.scrubs) scrub(s), \(counted.completions) completion(s)")
    }

    /// Under `pinchLock`. A scrub still owned is ended now with a revert; from the first `began` main was never told of,
    /// everything is dropped, and what comes before it (an `ended` main is owed) stays. True when the caller must schedule the hop to main.
    private func endScrubs() -> Bool {
        if let untold = mailbox.firstIndex(where: { if case .began = $0 { true } else { false } }) {
            mailbox.removeSubrange(untold...)
        }
        // A scrub still owned ends with a revert even when main never heard it begin: an end main has no scrub for, it ignores.
        if scrubOwner != nil { mailbox.append(.ended(.revert)) }
        scrubOwner = nil
        guard !mailbox.isEmpty, !drainScheduled else { return false }
        drainScheduled = true
        return true
    }

    /// Stops the port unless a newer start has begun: the check and the stop are one step under `portLock`, and a start takes a new generation before it asks for that lock.
    private func stopPort(ifStillGeneration decided: Int) {
        portLock.withLock {
            if pinchLock.withLock({ generation == decided }) { touches.stop() }
        }
    }

    /// The port refused the layout in a row: said once, and the watch ends on a queue of its own, since this is called from the
    /// framework's thread. It ends only the watch it was told of; the person's switch off and on, or the module activated again, watches anew.
    private func standDown(generation mine: Int) {
        let first = pinchLock.withLock { () -> Bool in
            guard watching, generation == mine, pinchStart != .layoutRefused else { return false }
            pinchStart = .layoutRefused
            return true
        }
        guard first else { return }
        HelmLog.shared.warn(Self.moduleID, "pinch: the trackpad's frames were refused in a row; the pinch is off until the switch is turned off and on, or the module is activated again")
        DispatchQueue.global().async { [weak self] in self?.stopPinch(keeping: .layoutRefused, generation: mine) }
    }

    /// On the framework's thread; the recognizer is fed under `pinchLock` and nothing else is held. What it says goes to the mailbox
    /// (`accept`), and main is told once.
    private func handle(_ frame: TouchFrame, generation mine: Int) {
        let (schedule, arm) = pinchLock.withLock { () -> (Bool, Bool) in
            guard watching, generation == mine else { return (false, false) }
            frames += 1
            var recognizer = recognizers[frame.device] ?? PinchRecognizer()
            let event = recognizer.feed(frame)
            recognizers[frame.device] = recognizer
            let schedule = event.map { accept($0, from: frame.device) } ?? false
            guard scrubOwner == frame.device else { return (schedule, false) }
            ownerHeardAt = now()
            let arm = !silenceCheckScheduled
            silenceCheckScheduled = true
            return (schedule, arm)
        }
        if schedule { scheduleDrain() }
        if arm { scheduleSilenceCheck() }
    }

    private func scheduleSilenceCheck() {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.silenceCheckEvery) { [weak self] in self?.checkSilence() }
    }

    /// While a scrub has an owner: when its pad has sent no frame for `silenceLimit`, the scrub is over (the pad no longer owns one, so what it sends later is dropped), and main is told `.ended(.revert)`. Otherwise looks again later; nothing is scheduled with no scrub.
    func checkSilence() {
        let (schedule, again, silent) = pinchLock.withLock { () -> (Bool, Bool, Bool) in
            guard watching, let owner = scrubOwner else { silenceCheckScheduled = false; return (false, false, false) }
            guard now() - ownerHeardAt >= Self.silenceLimit else { return (false, true, false) }
            silenceCheckScheduled = false
            return (endScrubs(), false, true)
        }
        if schedule { scheduleDrain() }
        if again { scheduleSilenceCheck() }
        if silent { HelmLog.shared.info(Self.moduleID, "pinch: a trackpad went silent in the middle of a scrub; the scrub was reverted") }
    }

    /// Under `pinchLock`. One pad's scrub at a time: a second pad's `began` is dropped and so is whatever it says after; only the owner
    /// moves or ends. True when the caller must schedule the hop to main.
    private func accept(_ event: PinchEvent, from device: Int) -> Bool {
        switch event {
        case .began:
            guard scrubOwner == nil else { return false }
            scrubOwner = device
            scrubs += 1
        case .moved:
            guard scrubOwner == device else { return false }
        case .ended(let outcome):
            guard scrubOwner == device else { return false }
            scrubOwner = nil
            if outcome == .complete { completions += 1 }
        }
        if case .moved = event, case .moved? = mailbox.last { mailbox[mailbox.count - 1] = event } else { mailbox.append(event) }
        let schedule = !drainScheduled
        drainScheduled = true
        return schedule
    }

    private func scheduleDrain() {
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }

    /// On main: takes what the mailbox holds, then delivers it in order. `onPinch` is read where it is delivered.
    private func drain() {
        let events = pinchLock.withLock { () -> [PinchEvent] in
            drainScheduled = false
            defer { mailbox = [] }
            return mailbox
        }
        MainActor.assumeIsolated { for event in events { onPinch(event) } }
    }

    /// Reconciled in memory; writes nothing. `reason` is what asked, for the catalog's log line.
    public func read(reason: CatalogReadReason) -> LaunchpadSnapshot {
        lock.lock(); defer { lock.unlock() }
        let reading = catalog.read(reason: reason)
        lastCatalog = reading
        return snapshot(reading, stored: store.load(), layout: nil, saved: true)
    }

    /// nil = refused (a vanished id, an empty name): nothing written, one line in the log without a name. Otherwise the new
    /// snapshot, with `saved` false when the write did not land — the result is still returned.
    public func apply(_ edit: LaunchpadEdit) -> LaunchpadSnapshot? {
        lock.lock(); defer { lock.unlock() }
        let reading = lastCatalog ?? catalog.read(reason: .edit)
        lastCatalog = reading
        let stored = store.load()
        let base = storedLayout(of: stored, reading).reconciled(catalog: reading.apps.map(\.id), complete: reading.complete)
        // Reconciled again so an edit that empties the arrangement (a reset) returns the apps in catalog order, as a read would.
        var applied = Self.resolved(edit, in: reading).flatMap(base.applying)
        if edit == .resetArrangement { applied?.items = defaultArrangement(reading).items }
        guard let edited = applied?.reconciled(catalog: reading.apps.map(\.id), complete: reading.complete) else {
            HelmLog.shared.info(Self.moduleID, "an arrangement edit was refused")
            return nil
        }
        let saved = (stored != .unreadable || store.moveUnreadableAside()) && store.save(edited)
        return snapshot(reading, stored: saved ? .loaded(edited) : stored, layout: edited, saved: saved)
    }

    /// A move to the category the app already has is the same as taking its move away, so it stores nothing; a move of an app
    /// the read does not find is refused (nil). The layout alone cannot tell: it holds no categories.
    private static func resolved(_ edit: LaunchpadEdit, in reading: CatalogReading) -> LaunchpadEdit? {
        guard case .setCategory(let id, let target) = edit else { return edit }
        guard let app = reading.apps.first(where: { $0.id == id }) else { return nil }
        return target == LaunchpadCategoryTarget(raw: app.category) ? .setCategory(id, nil) : edit
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
            LaunchResolution.resolve(id: id, reading: catalog.read(reason: .launch), bundleID: { catalog.bundleID(atPath: $0) })
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
            // Counted only here, after the system opened it: a refusal counts nothing. Blocking disk, so off the pool.
            let counts = self.counts
            _ = await offTheCooperativePool { counts.record(id) }
            return .launched
        }
    }

    /// The counts emptied (nothing is written when there are none); nil when the write did not land, so the caller reads again.
    public func resetLaunchCounts() -> LaunchpadSnapshot? {
        lock.lock(); defer { lock.unlock() }
        // The catalog as the person last saw it, as an edit reconciles against (`apply`): the counts are no part of a catalog read.
        let reading = lastCatalog ?? catalog.read(reason: .reset)
        lastCatalog = reading
        guard counts.reset() else { return nil }
        return snapshot(reading, stored: store.load(), layout: nil, saved: true)
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
        snap.launchCounts = counts.load().counts
        return snap
    }
}
