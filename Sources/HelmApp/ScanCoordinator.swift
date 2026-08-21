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

    /// Which modules have a background scan. `ScanRunner` owns the list and
    /// `ListsAgreeWithTheTreeTests` holds *that* against the registry — this is
    /// only the reading `considerAll` does, so it is private. It was internal,
    /// with a comment saying a test read it through here; no test ever did.
    private static var scannableModules: [String] { ScanRunner.scannableModules }

    init(host: ModuleHost,
         journal: ScanJournal = ScanJournal(),
         notices: AutomationNoticePort = SystemAutomationNotice(area: ScanCoordinator.logArea)) {
        self.host = host
        self.journal = journal
        self.notices = notices
    }

    /// The one category the app layer files a module's story under, and the area
    /// the notice port names itself with. `LogCategoriesAreModuleIdsTests`
    /// records it as the single shared category on purpose; a literal spelled
    /// five times in this file is the same name with five chances to drift.
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
    /// Reading the counter is this layer's job — it is a live system call, and
    /// the only thing here that cannot be handed a number. Everything the
    /// reading *means* is `ScanRunner`'s, where it is a test rather than an
    /// argument.
    func effectiveIdleSeconds(now: Date = Date()) -> TimeInterval {
        let next = ScanRunner.advance(idle, systemIdle: SystemIdle.seconds(),
                                      lastOwnNudge: lastOwnNudge, now: now)
        idle = next
        return next.personSeconds
    }

    /// Everything a tick reads that cannot differ between the modules in it.
    ///
    /// **Sampled once, not once per module.** Every field here was read inside
    /// `verdict(for:)`, so a tick over three modules paid for each answer three
    /// times: three `SecItemCopyMatching` round trips into securityd, because
    /// `AppSettings.disabledScans` verifies its seal on every read and
    /// `KeychainSealKey` caches nothing; three power readings; and six
    /// `CGSessionCopyCurrentDictionary` calls, since `ownsTheConsole` and
    /// `screenIsLocked` each make their own. Measured on this machine at
    /// 0,1785 ms for the keychain read and 0,1071 ms for the session
    /// dictionary — about 1,2 ms a tick against 0,4 hoisted, which is small and
    /// is not the reason.
    ///
    /// The reason is that they were three *different* readings. Lock the screen
    /// between the first module and the third and the same tick judged them
    /// against two different machines; re-seal `disabledScans` mid-tick and the
    /// `.adopt` branch could write while a later module read what it wrote. One
    /// snapshot cannot disagree with itself.
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
    ///   keeps, so asking it three times a tick would be three folds of the same
    ///   minute — the shape CLAUDE.md's rule about getters with side effects is
    ///   about, and cheaper to avoid than to serialise.
    func conditions(idleSeconds: TimeInterval, now: Date = Date()) -> Conditions {
        Conditions(now: now,
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
    /// A line per module per tick is 4320 a day and would push everything else
    /// out of `LogTail`, which is capped at 1000. Silence is the wrong answer
    /// too — see `considerAll`.
    private var lastLogged: [String: ScanSchedule.Verdict] = [:]

    private func considerAll() async {
        rollOverTheDayIfNeeded()
        // The off-list below is sealed, and the key behind that seal comes from
        // the login keychain — a modal authorization dialog on every ad-hoc
        // build. `AppSettings` is `@MainActor`, so a blocking read here is a
        // dialog on the thread that draws, with nobody at the desk to dismiss
        // it. Awaiting suspends; the round trip happens on another thread and
        // every read afterwards is memory (`SealKeyCache`).
        await AppSettings.scanGuard.warmKey()
        // One reading of the machine for the whole tick — see `Conditions`.
        var sampled = conditions(idleSeconds: effectiveIdleSeconds())
        for id in Self.scannableModules {
            guard !inFlight.contains(id) else { continue }
            let verdict = verdict(for: id, in: sampled)
            // **A refusal says why.** Without this the log is empty whether the
            // schedule refused correctly or the timer never fired, and "no
            // `[scan]` lines" — which is how this feature is meant to be
            // verified on battery — cannot tell a working refusal from a dead
            // coordinator. `ScanSchedule` names eight verdicts precisely so the
            // reason can be said; saying none of them wasted the vocabulary.
            //
            // On change only. The state is steady for hours at a time, and a
            // heartbeat is what makes a log unreadable.
            if lastLogged[id] != verdict {
                lastLogged[id] = verdict
                HelmLog.shared.info(Self.logArea, "\(id): \(verdict)")
            }
            guard case .run = verdict else { continue }
            await run(id)
            // A scan is minutes, not milliseconds, and the loop is suspended for
            // all of it: whatever was sampled before it is history by now. The
            // person may have come back to the keyboard, unplugged the machine
            // or locked the screen — and `notAtTheConsole` is a refusal the next
            // module is entitled to. The snapshot is for the modules judged in
            // the same instant, never for the ones judged after a walk of the
            // volume. Before this the reading was only ever taken once, so a
            // second scan could start against a minute that had long passed.
            sampled = conditions(idleSeconds: effectiveIdleSeconds())
        }
    }

    private func run(_ id: String) async {
        guard let live = host.liveModule(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        let started = Date()
        AppSettings.scanRunsToday[id, default: 0] += 1
        // The attempt is recorded before anything can go wrong with it, so a
        // scan still running is never treated as one that never happened — and
        // so a crash mid-walk costs the retry gap rather than the whole day.
        // What it must NOT do is stand in for a completion: writing one figure
        // for both is what made the day's second run unreachable.
        AppSettings.lastScanAttemptAt[id] = started

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
            .request(ScanCommand.backgroundScan, as: ScanReport.self)
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
    /// **This is the call the journal was written for and never got.**
    /// `ScanJournal.change(module:)` and `list(module:_:)` had no caller
    /// anywhere in `Sources/`: three modules walked the volume twice a day, the
    /// delta was computed and thrown away, and the whole product of it was a
    /// relative date on a settings page.
    ///
    /// **A finding, never a claim of action** — «Duplicates / 7 items since the
    /// last check — 34,2 GB», not «cleaned» and not «freed». Helm did not clean
    /// anything here; it looked. `ScanNews` decides whether the delta is worth
    /// saying and `AppStr` says it, in the eight languages and with the words
    /// that would claim an act held out by a test; what is left here is asking,
    /// which is why it is this short.
    ///
    /// Internal rather than private because it is the seam a test drives:
    /// reaching it through `run` would need a live module and a walk of the
    /// volume, which is a test of the filesystem.
    ///
    /// The log line beside it carries counts and a size and no path — the
    /// journal it read names every file the scan found, and `HelmLog` carries no
    /// names. The banner may name the person's folder; the log may not.
    func tellSomebodyWhatAppeared(in id: String) {
        guard let finding = ScanNews.finding(in: journal.change(module: id)) else { return }
        let name = ModuleRegistry.descriptor(id)?.moduleMetadata.name ?? id
        let words = AppStr.scanFindingNotice(module: name, finding: finding)
        let port = notices
        // One task, replaced rather than accumulated: the modules are scanned
        // one after another and a prompt standing through the next scan is the
        // only way two can overlap, which macOS answers once and for all anyway.
        noticeTask?.cancel()
        noticeTask = Task {
            switch await NoticeChannel.tell(port, words) {
            case .posted:
                // English outright, the way every other line in this file is
                // written: the log is read by whoever is diagnosing a Mac,
                // which is not always the person whose Mac it is.
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
    private func rollOverTheDayIfNeeded(now: Date = Date()) {
        guard ScanRunner.dayRolledOver(storedDay: AppSettings.scanBudgetDay, now: now)
        else { return }
        AppSettings.scanBudgetDay = Calendar.current.startOfDay(for: now)
        AppSettings.scanRunsToday = [:]
    }
}
