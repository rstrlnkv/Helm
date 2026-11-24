import AppKit
import Foundation
import HelmRuntime
import HelmUI
import HelmAppStrings

/// Runs background scans when `ScanSchedule` says they may.
///
/// Owns the clock and nothing else. Every decision belongs to `ScanSchedule`,
/// which is pure and has a test per refusal; this gathers the conditions, calls
/// the module, and writes what came back into the journal.
@MainActor
final class ScanCoordinator {
    private let host: ModuleHost
    private let journal: ScanJournal
    /// Where the one thing these scans have to say goes. Injected so a test can
    /// drive the channel without a notification centre — the real
    /// `UNUserNotificationCenter` raises an ObjC exception outside an app
    /// bundle, and that ends the whole run rather than failing a case.
    private let notices: AutomationNoticePort
    private var tick: RepeatingTick?
    private var nudgeObserver: NSObjectProtocol?
    /// Cancelled by `stop()`: `requestAuthorization` waits for the person to
    /// answer a system prompt, which can be minutes, and this object is torn
    /// down at `applicationWillTerminate`.
    private var noticeTask: Task<Void, Never>?

    /// Scans running right now.
    ///
    /// `run` writes `lastScanAt` only when a scan finishes, so without this the
    /// next tick would see the budget unspent and start a second concurrent
    /// scan of the same module; the module would cancel the first, and the
    /// day's budget would be spent on a scan that never completed.
    private var inFlight: Set<String> = []

    /// One minute. The scan itself runs at most twice a day, so this is only how
    /// often the conditions are re-read, and both readings are cheap. A timer
    /// rather than a notification because idleness has nothing to announce.
    private static let pollInterval: TimeInterval = 60

    init(host: ModuleHost,
         journal: ScanJournal = ScanJournal(),
         notices: AutomationNoticePort = SystemAutomationNotice(area: ScanCoordinator.logArea)) {
        self.host = host
        self.journal = journal
        self.notices = notices
    }

    /// The one category the app layer files a module's story under, and the area
    /// the notice port names itself with.
    static let logArea = "scan"

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
        noticeTask?.cancel()
        noticeTask = nil
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

    /// What the estimate concluded at the last tick. One reading of the counter
    /// cannot answer this — `ScanRunner.advance` has the reasoning.
    private var idle: ScanRunner.Idle?

    /// How long the person has been away, which is not what the counter says
    /// once Helm has nudged the pointer itself.
    ///
    /// Reading the counter is this layer's job, being a live system call;
    /// everything the reading means is `ScanRunner`'s, where it is tested.
    func effectiveIdleSeconds() -> TimeInterval {
        let next = ScanRunner.advance(idle, systemIdle: SystemIdle.seconds(),
                                      lastOwnNudge: lastOwnNudge, now: Date())
        idle = next
        return next.personSeconds
    }

    /// Everything a tick reads that cannot differ between the modules in it.
    ///
    /// **Sampled once, not once per module**, so the modules of one tick are
    /// judged against one machine: per-module readings could straddle a screen
    /// lock, or an `.adopt` write of `disabledScans` that a later module then
    /// reads. One snapshot cannot disagree with itself.
    struct Conditions {
        let now: Date
        let idleSeconds: TimeInterval
        /// A desktop has no battery and is always on mains, and a source that
        /// will not answer is treated the same way: never scanning on a Mac
        /// whose hardware stays quiet is the worse of the two failures.
        let onMains: Bool
        let onConsole: Bool
        let screenLocked: Bool
        let disabledScans: Set<String>
        let lastRun: [String: Date]
        let lastAttempt: [String: Date]
        let runsToday: [String: Int]
    }

    /// - Parameter idleSeconds: sampled once per tick by the caller, not read
    ///   per module. `effectiveIdleSeconds` folds a reading into an estimate it
    ///   keeps, so asking it per module would fold the same minute several times.
    func conditions(idleSeconds: TimeInterval) -> Conditions {
        Conditions(now: Date(),
                   idleSeconds: idleSeconds,
                   onMains: PowerSource.isOnMains,
                   onConsole: Self.ownsTheConsole,
                   screenLocked: Self.screenIsLocked,
                   // **Never the blocking getter, on the main actor.** Verifying
                   // the seal needs the login keychain, and on an ad-hoc build
                   // that is a modal dialog; `considerAll` awaits the warm
                   // before it gets here, so in the ordinary case this is a
                   // memory read. When the keychain refused, «cannot say» is
                   // every scan off — the same answer a broken seal gives, and
                   // the safe direction for a reader nobody is watching.
                   disabledScans: AppSettings.disabledScansIfWarm
                       ?? Set(ScanRunner.scannableModules),
                   lastRun: AppSettings.lastScanAt,
                   lastAttempt: AppSettings.lastScanAttemptAt,
                   runsToday: AppSettings.scanRunsToday)
    }

    func verdict(for id: String, in conditions: Conditions) -> ScanSchedule.Verdict {
        ScanSchedule.verdict(.init(
            now: conditions.now,
            lastRun: conditions.lastRun[id],
            idleSeconds: conditions.idleSeconds,
            onMains: conditions.onMains,
            runsToday: conditions.runsToday[id] ?? 0,
            isEnabled: !conditions.disabledScans.contains(id),
            onConsole: conditions.onConsole,
            screenLocked: conditions.screenLocked,
            lastAttempt: conditions.lastAttempt[id]))
    }

    // MARK: - Running

    /// The last verdict logged for each module, so only changes are written.
    ///
    /// A line per module per tick would push everything else out of `LogTail`.
    /// Silence is the wrong answer too; see `considerAll`.
    private var lastLogged: [String: ScanSchedule.Verdict] = [:]

    private func considerAll() async {
        rollOverTheDayIfNeeded()
        // The off-list below is sealed, and the key comes from the login
        // keychain, a modal dialog on an ad-hoc build. `AppSettings` is
        // `@MainActor`, so a blocking read here would hang the thread that
        // draws with nobody at the desk. Awaiting suspends; the round trip
        // happens on another thread and every read afterwards is memory
        // (`SealKeyCache`).
        await AppSettings.scanGuard.warmKey()
        // One reading of the machine for the whole tick — see `Conditions`.
        var sampled = conditions(idleSeconds: effectiveIdleSeconds())
        // `ScanRunner` owns the list of modules with a background scan and
        // `ListsAgreeWithTheTreeTests` holds it against the registry.
        for id in ScanRunner.scannableModules {
            guard !inFlight.contains(id) else { continue }
            let verdict = verdict(for: id, in: sampled)
            // **A refusal says why**, or an empty log could not tell a working
            // refusal from a coordinator whose timer never fired. On change
            // only: the state is steady for hours, and a heartbeat makes a log
            // unreadable.
            if lastLogged[id] != verdict {
                lastLogged[id] = verdict
                HelmLog.shared.info(Self.logArea, "\(id): \(verdict)")
            }
            guard case .run = verdict else { continue }
            await run(id)
            // A scan is minutes, and the loop is suspended for all of it: the
            // person may have come back, unplugged the machine or locked the
            // screen since. The snapshot is for the modules judged in the same
            // instant, never for the ones judged after a walk of the volume.
            sampled = conditions(idleSeconds: effectiveIdleSeconds())
        }
    }

    private func run(_ id: String) async {
        guard let live = host.liveModule(id) else { return }
        await run(id, scan: live.backgroundScan)
    }

    /// The seam a test drives with a scan of its own: a live module would need
    /// a real engine and a walk of the volume.
    func run(_ id: String, scan: @escaping @MainActor () async -> ScanReport?) async {
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        let started = Date()
        AppSettings.scanRunsToday[id, default: 0] += 1
        // The attempt is recorded before anything can go wrong with it, so a
        // scan still running is never treated as one that never happened, and
        // a crash mid-walk costs the retry gap rather than the whole day. It
        // must not stand in for a completion, or the day's second run could
        // never come.
        AppSettings.lastScanAttemptAt[id] = started

        // The interval is the walk and nothing after it: it closes before the
        // journal record and the log line, on every path out.
        let report = await HelmActivity.phase("scan.\(id)") { @Sendable in await scan() }
        let seconds = Date().timeIntervalSince(started)

        guard let report else {
            // Nil is not an empty report. A refused root or a cancelled walk
            // must not be written down as «проверено, чисто» about a folder
            // nobody read.
            HelmLog.shared.info(Self.logArea, "\(id): no answer after \(Int(seconds))s")
            return
        }
        // Only here: a completion is what holds the module for the day.
        AppSettings.lastScanAt[id] = Date()
        journal.record(ScanEntry(at: Date(), bytes: report.bytes, count: report.count,
                                 seconds: seconds),
                       items: report.items, module: id)
        HelmLog.shared.info(Self.logArea,
                            "\(id) finished in \(Int(seconds))s — \(report.count) items")
        tellSomebodyWhatAppeared(in: id)
    }

    /// A banner about what turned up while nobody was looking, or silence.
    ///
    /// **A finding, never a claim of action** (`AppStr.scanFindingNotice`).
    /// `ScanNews` decides whether the delta is worth saying and `AppStr` says
    /// it; what is left here is asking.
    ///
    /// Internal rather than private because it is the seam a test drives:
    /// reaching it through `run` would need a live module and a walk of the
    /// volume, which is a test of the filesystem.
    ///
    /// The log line beside it carries counts and a size and no path — the
    /// journal it read names every file the scan found, and a log line is not where
    /// a scan's whole result belongs. The banner may name the person's folder; the
    /// log line keeps to counts.
    ///
    /// **`change` reads back off disk what `record` has just written, on
    /// purpose.** The read costs a few times the write, once per completed
    /// scan, against a walk of the volume that took minutes. An in-memory
    /// delta would save little (`record` renames a file and never holds the
    /// previous list) and would lose the property the banner rests on:
    /// `ScanJournal.record` folds a failed `PrivateFile.write` into a log
    /// warning, so only this reading knows the write landed. Otherwise the
    /// next tick, comparing against a `previous` that never rotated, would
    /// announce the same items again.
    func tellSomebodyWhatAppeared(in id: String) {
        guard let finding = ScanNews.finding(in: journal.change(module: id)) else { return }
        let name = ModuleRegistry.descriptor(id)?.moduleMetadata.name ?? id
        let words = AppStr.scanFindingNotice(module: name, finding: finding)
        let port = notices
        // One task, replaced rather than accumulated: two overlap only while a
        // prompt stands through the next scan, and macOS answers it once.
        noticeTask?.cancel()
        noticeTask = Task {
            switch await NoticeChannel.tell(port, words) {
            case .posted:
                // English, like every log line: the log is read by whoever is
                // diagnosing a Mac, not always the person whose Mac it is.
                HelmLog.shared.info(Self.logArea,
                                    "\(id): told about \(finding.count) new, "
                                    + "\(HelmBytes.string(finding.bytes, language: "en"))")
            case .notAllowed:
                HelmLog.shared.info(Self.logArea, "\(id): what turned up was not announced — "
                                    + "macOS says banners are not allowed")
            // The app is going away; `stop()` is the account of that.
            case .cancelled:
                break
            }
        }
    }

    /// Yesterday's budget is not today's. Whether the day turned is
    /// `ScanRunner.dayRolledOver`, against the calendar rather than multiples of
    /// 86 400 seconds; what to write when it has is this line.
    private func rollOverTheDayIfNeeded() {
        let now = Date()
        guard ScanRunner.dayRolledOver(storedDay: AppSettings.scanBudgetDay, now: now)
        else { return }
        AppSettings.scanBudgetDay = Calendar.current.startOfDay(for: now)
        AppSettings.scanRunsToday = [:]
    }
}
