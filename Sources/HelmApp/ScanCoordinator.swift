import AppKit
import Foundation
import HelmRuntime
import HelmUI

/// Runs background scans when `ScanSchedule` says they may.
///
/// Owns the clock and nothing else. Every decision belongs to `ScanSchedule`,
/// which is pure and has a test per refusal; this gathers the conditions, calls
/// the module, and writes what came back into the journal.
@MainActor
final class ScanCoordinator {
    private let host: ModuleHost
    private let journal = ScanJournal()
    private var tick: RepeatingTick?
    private var nudgeObserver: NSObjectProtocol?

    /// Scans running right now.
    ///
    /// Without it the tick at t=60 s reads a `lastScanAt` that `run` only writes
    /// when it *finishes*, sees the budget unspent, and starts a **second
    /// concurrent scan of the same module** — two readers of every file in
    /// scope. The module then cancels the first, so the day's budget of two is
    /// spent on one scan that never completed.
    private var inFlight: Set<String> = []

    /// One minute. The scan itself runs at most twice a day, so this is only how
    /// often the conditions are re-read — and both readings are cheap: idle was
    /// measured at 0,0000 ms after the first call, the power source at well
    /// under a millisecond. A timer rather than a notification because idleness
    /// has nothing to announce: nothing tells you that nothing happened.
    private static let pollInterval: TimeInterval = 60

    /// Which modules have a background scan.
    ///
    /// A literal list far from the modules it names is how `OverviewPage.order`
    /// went stale. It is spelled out anyway, because a module gaining a scan is
    /// a decision with a cost — it reads the volume — and should take an edit
    /// here rather than following from a protocol somebody conformed to.
    static let scannableModules = ["duplicates", "uninstaller", "disk"]

    init(host: ModuleHost) { self.host = host }

    func start() {
        // Keep Awake's nudge resets the system idle counter, and its default
        // interval is exactly the idle threshold. Heard here, discounted below.
        nudgeObserver = NotificationCenter.default.addObserver(
            forName: .helmPointerNudged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lastOwnNudge = Date() }
        }
        let made = RepeatingTick(interval: Self.pollInterval) { [weak self] in
            Task { @MainActor in await self?.considerAll() }
        }
        tick = made
        made.set(active: true)
    }

    /// Cancelled from outside, and from the owner's teardown — not only from
    /// `deinit`, which cannot run while a task still retains self.
    func stop() {
        tick?.set(active: false)
        tick = nil
        if let nudgeObserver { NotificationCenter.default.removeObserver(nudgeObserver) }
        nudgeObserver = nil
    }

    private var lastOwnNudge: Date?

    // MARK: - Deciding

    /// This session owns the console. Under fast user switching the other
    /// session receives no events, so the idle counter climbs forever and an
    /// empty desk is indistinguishable from somebody else being at the keyboard.
    static var ownsTheConsole: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session[kCGSessionOnConsoleKey as String] as? Bool ?? true
    }

    /// The key is absent when unlocked, present and 1 when locked.
    static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Int == 1
    }

    /// The idle counter, minus what Helm did to it itself.
    ///
    /// Measured: a synthetic `mouseMoved` takes the counter from 284,97 s to
    /// 0,30 s, and Keep Awake's nudge is exactly that. Its default interval is
    /// five minutes — `ScanSchedule.idleThreshold` — so trusting the raw number
    /// means no background scan ever runs for anybody with that switch on.
    ///
    /// When the counter reset at about the moment of our own nudge, the reading
    /// is measuring our event rather than the person, and how long since that
    /// nudge is the better answer. Two seconds of tolerance because the
    /// notification and the counter are not read at the same instant.
    func effectiveIdleSeconds(now: Date = Date()) -> TimeInterval {
        let system = SystemIdle.seconds()
        guard let nudge = lastOwnNudge else { return system }
        let sinceNudge = now.timeIntervalSince(nudge)
        guard abs(sinceNudge - system) < 2 else { return system }
        return sinceNudge + system
    }

    func verdict(for id: String, now: Date = Date()) -> ScanSchedule.Verdict {
        ScanSchedule.verdict(.init(
            now: now,
            lastRun: AppSettings.lastScanAt[id],
            idleSeconds: effectiveIdleSeconds(now: now),
            // A desktop has no battery and is always on mains, and a source that
            // will not answer is treated the same way: never scanning on a Mac
            // whose hardware stays quiet is the worse of the two failures.
            onMains: PowerSource.isOnMains,
            runsToday: AppSettings.scanRunsToday[id] ?? 0,
            isEnabled: !AppSettings.disabledScans.contains(id),
            onConsole: Self.ownsTheConsole,
            screenLocked: Self.screenIsLocked))
    }

    // MARK: - Running

    private func considerAll() async {
        rollOverTheDayIfNeeded()
        for id in Self.scannableModules {
            guard !inFlight.contains(id), case .run = verdict(for: id) else { continue }
            await run(id)
        }
    }

    private func run(_ id: String) async {
        guard let live = host.liveModule(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        let started = Date()
        AppSettings.scanRunsToday[id, default: 0] += 1
        // Written at the start as well as at the end. The end write is what
        // makes tomorrow's schedule right; this one stops the next minute's tick
        // treating a scan still running as one that never happened.
        AppSettings.lastScanAt[id] = started

        // The transport is lifted out of the closure rather than reached through
        // `live` inside it: this type is `@MainActor` and the request is not, so
        // capturing the view model would carry actor-isolated state across.
        let transport = live.vm.transport
        // `begin` with a `defer`, not the `phase` scope: that one takes a
        // synchronous closure, and wrapping an `await` in it hands a
        // non-`Sendable` async function across an isolation boundary. The
        // `defer` gives the same guarantee the scope exists for — the interval
        // closes on every path out, return and cancellation alike.
        HelmActivity.begin("scan.\(id)")
        defer { HelmActivity.end("scan.\(id)") }
        let report = await TransportClient(transport)
            .request("backgroundScan", as: ScanReport.self)
        let seconds = Date().timeIntervalSince(started)
        AppSettings.lastScanAt[id] = Date()

        guard let report else {
            // Nil is not an empty report. A refused root or a cancelled walk
            // must not be written down as «проверено, чисто» about a folder
            // nobody read.
            HelmLog.shared.info("scan", "\(id): no answer after \(Int(seconds))s")
            return
        }
        journal.record(ScanEntry(at: Date(), bytes: report.bytes, count: report.count,
                                 seconds: seconds, startedByHand: false),
                       items: report.items, module: id)
        HelmLog.shared.info("scan",
                            "\(id) finished in \(Int(seconds))s — \(report.count) items")
    }

    /// Yesterday's budget is not today's. Compared against the calendar rather
    /// than against multiples of 86 400 seconds, because days are not all the
    /// same length — the rule `EventWindows` already follows.
    private func rollOverTheDayIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard AppSettings.scanBudgetDay != today else { return }
        AppSettings.scanBudgetDay = today
        AppSettings.scanRunsToday = [:]
    }
}
