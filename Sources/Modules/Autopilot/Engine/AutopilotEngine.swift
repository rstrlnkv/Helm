import Foundation
import HelmContract
import HelmRuntime

/// The module's engine: folders, their rules, and three triggers, none of
/// which covers the others:
///
/// - **FSEvents**, so a file that appears is sorted a moment later.
/// - **An hourly sweep**, because "older than 30 days" comes true with no event.
/// - **Run now**, so someone who has just written a rule sees it work.
public final class AutopilotEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, the settings prefix and log category, written down
    /// only here. **It never changes**: it names settings already on people's
    /// machines. The keychain service and the stamp attribute are separate
    /// `com.helm.autopilot*` literals that must not follow a rename
    /// (`RuleKeychain`, `RuleStamp`).
    public static let moduleID = "autopilot"

    private let store: NamespacedStore
    /// The only thing here that touches the keychain.
    private let rules: SealedRules
    /// Internal rather than private so a test can put a reader with a seam in it
    /// in the engine's hand; nothing else assigns it after `init`.
    var reader: FolderReader
    private let runner: RuleRunner
    /// `WatchScope`'s reference point for a folder's root; the runner and
    /// `undoer` hold the same one for the files.
    private let home: String
    /// The other direction, through the same gate.
    private let undoer: UndoRunner
    private let queue = DispatchQueue(label: "helm.rules", qos: .utility)
    /// Behind `queue`: `activate`/`deactivate` run on main and `refreshWatch`
    /// wherever the model's `save` ran.
    private var watcher: FolderWatcher?
    private var sweepTimer: DispatchSourceTimer?

    /// Where an unattended pass's one banner goes; nil in tests not about it.
    /// It owns the task waiting on macOS too, so `deactivate` cancels one thing.
    private let sweepNotice: SweepNotifier?

    /// "A pass went into the history": said after the write landed, never with
    /// it. Carries nothing — the model re-asks, so the read that fills the page
    /// stays the one that judges the seal and the window.
    private let historyChanged: @Sendable () -> Void

    /// Hourly. The events cover anything that happens; this only exists for
    /// conditions that come true by themselves, which is a scale of hours.
    private static let sweepInterval: TimeInterval = 3600

    /// `home`, `keys` and `sequence` are injected so a test can point a whole
    /// engine at a temporary directory without being exempted from the gate,
    /// and leave nothing in the user's login keychain.
    public init(store: NamespacedStore,
                home: String = NSHomeDirectory(),
                keys: RuleKeyPort = KeychainRuleKey(),
                sequence: RuleSequencePort = KeychainRuleSequence(),
                sweepNotice: SweepNotifier? = nil,
                historyChanged: @escaping @Sendable () -> Void = {}) {
        self.sweepNotice = sweepNotice
        self.historyChanged = historyChanged
        self.home = home
        self.reader = FolderReader(home: home)
        self.runner = RuleRunner(home: home)
        self.undoer = UndoRunner(home: home)
        self.store = store
        self.rules = SealedRules(store: store, keys: keys, sequence: sequence)
        // **Nothing here reads the keychain** (`SealedRules.init` says why).
    }

    // MARK: - The folders

    public var folders: [WatchedFolder] {
        get { rules.folders }
        set {
            // Outside the decision the setter takes: it only enqueues, but what
            // it enqueues is another decision.
            if rules.save(newValue) { refreshWatch() }
        }
    }

    /// Throw away a rule set that was not written by Helm, so the page can be
    /// used again. The one thing the card above the folder list may send.
    func discardRefusedRules() { rules.discardRefused() }

    /// What the page asks for beside the folder list. The reason is a side
    /// effect of judging the rules, so the two are asked together.
    var status: AutopilotStatus {
        let (watched, reason, unapplied) = rules.decision()
        // One question per folder, asked outside that decision: a page opening
        // is not a reason to hold every other reader of the rule set behind a
        // filesystem call, and `state(of:)` never touches the rules.
        var states: [String: FolderState] = [:]
        for folder in watched {
            // The sweep's own root question first: told `.read` for a folder
            // the gate refuses, the page draws no notice over a row that does nothing.
            states[folder.id] = WatchScope.allows(folder.path, home: home)
                ? reader.state(of: folder.path) : .refused
        }
        return AutopilotStatus(refusal: reason, folders: states,
                               watching: watchLock.withLock { watching },
                               historyRefused: historyRefused, unapplied: unapplied)
    }

    public func activate() {
        let made = FolderWatcher { [weak self] changed in self?.handle(changed) }
        queue.async { [self] in watcher = made }
        refreshWatch()
        startSweepTimer()
    }

    public func deactivate() {
        queue.async { [self] in
            watcher?.stop()
            watcher = nil
        }
        sweepTimer?.cancel()
        sweepTimer = nil
        sweepNotice?.cancel()
    }

    /// An engine dropped without `deactivate` still stops its timer and its
    /// pending banner. Not dispatched onto `queue`: `FolderWatcher` stops in its
    /// own `deinit`.
    deinit {
        sweepTimer?.cancel()
        sweepNotice?.cancel()
    }

    /// On the engine's queue, including the *read*: reading `folders` resolves
    /// the key, and neither caller may wait on a keychain prompt (`activate` on
    /// main during launch, the setter wherever the model's `save` ran).
    private func refreshWatch() {
        queue.async { [self] in
            let paths = folders.filter(\.enabled).map(\.path)
            // The watcher's answer is recorded, so the log never says a folder
            // is watched while no stream is running.
            watcher?.watch(paths) { [weak self] started in
                self?.record(watching: started, over: paths.count)
            }
        }
    }

    /// Whether a stream is running, as the watcher last answered. `nil` until it
    /// has been asked — an engine nobody activated does not know, and "does not
    /// know" is not "no".
    private let watchLock = NSLock()
    private var watching: Bool?

    private func record(watching started: Bool, over count: Int) {
        let changed: Bool = watchLock.withLock {
            guard watching != started else { return false }
            watching = started
            return true
        }
        guard changed else { return }
        if started {
            HelmLog.shared.info(Self.moduleID, "watching \(count) folder(s)")
        } else if count > 0 {
            HelmLog.shared.error(Self.moduleID,
                                 "nothing is watching \(count) folder(s); "
                                 + "only the hourly sweep will act")
        }
    }

    private func startSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.sweepInterval, repeating: Self.sweepInterval)
        timer.setEventHandler { [weak self] in _ = self?.sweepAll() }
        timer.resume()
        sweepTimer = timer
    }

    // MARK: - What it did

    /// What Autopilot did, newest first, over the last thirty days. Windowed on
    /// the way out too, so a machine asleep for a month shows nothing stale.
    var history: [ActionRecord] {
        ActionHistory.within(ActionHistory.decode(store.data(ActionHistory.storeKey)))
    }

    /// Whether the stored history is not Helm's: then nothing in it is put back
    /// or added to. It is shown all the same, since a rewritten history is
    /// itself something that happened.
    ///
    /// **The whole verdict is on the queue.** The history and its seal are two
    /// store reads (two writes in `write`); a reader between them could hold
    /// Helm's new seal over the old history and call it rewritten. `remember`
    /// and `putBack` judge the pair on this queue too
    /// (`TheHistorysVerdictIsOneReadingTests`). Safe to `sync`: `readStatus`
    /// runs off the cooperative pool, never on this queue.
    public var historyRefused: Bool {
        !queue.sync { rules.historyIsHelms(store.data(ActionHistory.storeKey)) }
    }

    /// On the engine's queue: a clear landing inside `remember`'s
    /// read-modify-write would be undone.
    func clearHistory() {
        // `sync`: the caller reads the history back next. Safe from
        // `dropHistory`, which never runs on this queue.
        queue.sync { rules.clearHistory() }
    }

    /// Written once per pass, not once per file.
    ///
    /// **Nothing is folded into a history that does not verify**: sealing the
    /// result would sign records something else wrote, and a return would act
    /// on them. Deleting it would take the warning off the page unread. So it
    /// is frozen, with the way out on the page, and the run's work is in the log.
    private func remember(_ records: [ActionRecord]) {
        guard !records.isEmpty else { return }
        let stored = store.data(ActionHistory.storeKey)
        guard rules.historyIsHelms(stored) else {
            HelmLog.shared.error(Self.moduleID,
                                 "the stored history was not written by Helm, so \(records.count) "
                                 + "records were not added to it and none of it can be put back")
            return
        }
        var kept = ActionHistory.decode(stored)
        // Oldest first, so the newest ends up at the head after the last insert.
        for record in records.sorted(by: { $0.at < $1.at }) {
            kept = ActionHistory.recording(record, into: kept)
        }
        guard write(kept) else { return }
        // Only once the write landed. A return is not announced: the page's
        // own gesture made it, and it reloads.
        historyChanged()
    }

    /// The seal first, then the history it signs. A death between the writes
    /// leaves a mismatched pair either way, which refuses; this order means a
    /// keychain that will not answer leaves the old history still signed.
    /// Answers whether it wrote, so `remember` announces no refused seal.
    @discardableResult
    private func write(_ history: [ActionRecord]) -> Bool {
        guard let data = ActionHistory.encode(history), rules.seal(history: data) else { return false }
        store.set(data, for: ActionHistory.storeKey)
        return true
    }

    // MARK: - Putting it back

    /// Put one action back. A one-line report, so the page reads a single
    /// return and a whole pass the same way.
    @discardableResult
    public func undo(_ recordID: String) -> UndoReport {
        putBack { $0.id == recordID }
    }

    /// Put a whole pass back, newest first: a pass can have moved two files
    /// onto one name, and undoing the numbered second arrival first gives each
    /// its own name back.
    @discardableResult
    func undoRun(_ run: String) -> UndoReport {
        putBack { $0.run == run }
    }

    /// On `queue`, like every read-modify-write of this key.
    ///
    /// **The seal is asked once, for the whole gesture**: every field a return
    /// acts on comes from the history, so one something else wrote is refused
    /// entire. The refusal is reported per line, the only place it can be said.
    private func putBack(_ matching: (ActionRecord) -> Bool) -> UndoReport {
        let stored = store.data(ActionHistory.storeKey)
        var history = ActionHistory.within(ActionHistory.decode(stored))
        let chosen = history.filter(matching)
        guard rules.historyIsHelms(stored) else {
            return UndoReport(lines: chosen.map {
                UndoReport.Line(id: $0.id, file: $0.file, outcome: .refused(.historyRefused))
            })
        }
        let key = rules.keyMaterial
        let now = Date()
        var lines: [UndoReport.Line] = []
        // Newest first, which `within` already sorts them into.
        for record in chosen {
            let outcome = undoer.undo(record, key: key)
            lines.append(UndoReport.Line(id: record.id, file: record.file, outcome: outcome))
            // Only what really went back is marked. A row marked after a
            // refusal is a row that can never be tried again.
            guard case .restored = outcome,
                  let index = history.firstIndex(where: { $0.id == record.id })
            else { continue }
            history[index] = history[index].undone(at: now)
        }
        let report = UndoReport(lines: lines)
        if !report.restored.isEmpty {
            write(history)
            HelmLog.shared.info(Self.moduleID, "put back \(report.restored.count) of \(lines.count)")
        }
        if !report.notPutBack.isEmpty {
            HelmLog.shared.warn(Self.moduleID, "could not put back \(report.notPutBack.count)")
        }
        return report
    }

    /// What a folder's rules would do to it right now: the value the runner
    /// executes, so the dry run and what happens cannot drift apart.
    func preview(_ folder: WatchedFolder) -> [RulePlan] {
        // A full folder read per keystroke is bulk work, so it names itself
        // like `runNow`, with the reading inside the phase: a phase that has
        // ended cannot be excluded from its own line.
        HelmActivity.phase("autopilot.preview") {
            defer { HelmLog.shared.memory("autopilot.preview") }
            // A refused root previews as nothing (`readGated`).
            return RulePlan.decide(readGated(folder).files, rules: folder.rules.filter(\.enabled))
        }
    }

    /// A folder read, with the gate asked on both sides of it.
    ///
    /// Before: the root, because by the time the runner's per-file gate
    /// refuses, every name in the folder is in hand. After: every file, because
    /// a link put in place of an ancestor meanwhile leads the walk somewhere
    /// the first question never judged, and the walk answers in the resolved
    /// spelling. Dropped here, those are never planned, counted, logged or
    /// recorded. A refused root reads as `.refused`.
    private func readGated(_ folder: WatchedFolder) -> FolderReading {
        guard WatchScope.allows(folder.path, home: home) else { return .refused }
        let reading = reader.reading(in: folder.path, depth: folder.depth)
        return FolderReading(state: reading.state,
                             files: reading.files.filter { WatchScope.allows($0.path, home: home) })
    }

    /// `manual` (only `runNow`) decides the sweep's voice (`SweepAnnouncement`)
    /// and reaches no banner: the person is looking at the page.
    @discardableResult
    func sweep(_ folder: WatchedFolder, manual: Bool = false) -> SweepReport {
        swept(folder, manual: manual).report
    }

    /// The sweep with the records it wrote: the banner is decided from those,
    /// the log line from the report, so three folders make one banner.
    private func swept(_ folder: WatchedFolder,
                       manual: Bool) -> (report: SweepReport, records: [ActionRecord]) {
        // The root is asked before it is read (`readGated`): what the sweep
        // reads goes into a history any process can read.
        let reading = readGated(folder)
        let files = reading.files
        let plans = RulePlan.decide(files, rules: folder.activeRules)
        let key = rules.keyMaterial
        // One value for the whole pass, so the page can offer to put a sweep
        // back rather than five hundred separate rows.
        let pass = UUID().uuidString
        var acted = 0, refused = 0, failed = 0
        var records: [ActionRecord] = []
        let counters = CounterBook()
        for plan in plans {
            let path = plan.facts.path
            let outcome = runner.run(plan, at: path, key: key, counters: counters)
            if let record = ActionRecord.of(plan, outcome, run: pass) { records.append(record) }
            switch outcome {
            case .moved, .renamed, .tagged, .trashed:
                acted += 1
            case .alreadyDone:
                break
            case .refused, .targetOutOfScope:
                refused += 1
                warnUnlessDone(outcome, plan: plan, at: path)
            case .failed:
                failed += 1
                warnUnlessDone(outcome, plan: plan, at: path)
            }
        }
        remember(records)
        let report = SweepReport(folderID: folder.id, examined: files.count,
                                 acted: acted, refused: refused, failed: failed,
                                 folder: reading.state)
        if let line = SweepAnnouncement.line(for: report, manual: manual) {
            HelmLog.shared.info(Self.moduleID, line)
        }
        // A folder that could not be read at all is the one thing a sweep of
        // nothing has to say out loud: unattended, hourly, and otherwise
        // indistinguishable from a folder where there was nothing to do.
        if reading.state != .read {
            HelmLog.shared.warn(Self.moduleID,
                                "\(Redact.path(folder.path)) could not be swept: \(reading.state.rawValue)")
        }
        return (report, records)
    }

    /// One folder, because a person asked, and always answered out loud: with
    /// `sweep`'s conditional line, a run that found nothing and one that never
    /// started would be the same silence. The memory reading is inside the phase.
    @discardableResult
    func runNow(_ folder: WatchedFolder) -> SweepReport {
        HelmActivity.phase("autopilot.runNow") {
            defer { HelmLog.shared.memory("autopilot.runNow") }
            return sweep(folder, manual: true)
        }
    }

    /// Every enabled folder: the sweep timer's pass. Labelled because a timer
    /// is not a command, and growth between two `idle` readings needs something
    /// to blame (Architecture/DiagnosticsLog.md § The memory trail).
    @discardableResult
    func sweepAll() -> [SweepReport] {
        let passes = HelmActivity.phase("autopilot.sweep") {
            folders.filter(\.enabled).map { swept($0, manual: false) }
        }
        guard !passes.isEmpty else { return [] }
        HelmLog.shared.memory("autopilot.sweep")
        // One banner for the whole hour, never one per watched folder: «what did
        // Helm do while I was away» is a question about the pass. `runNow` does
        // not come through here, which is how it stays silent.
        sweepNotice?.tell(passes.flatMap(\.records))
        return passes.map(\.report)
    }

    /// One batch of FSEvents paths; the folder each belongs to decides its rules.
    ///
    /// The stream is recursive regardless, so `plan(for:among:)` asks the
    /// sweep walk's question, or a depth-1 watch on Downloads would act inside
    /// every unzipped project and bundle. Internal so a test can drive the leg:
    /// `kFSEventStreamCreateFlagIgnoreSelf` gives a test's file no event.
    func handle(_ changed: [String]) {
        queue.async { [self] in
            // Read on the engine's queue, never on `FolderWatcher`'s: reading
            // the rule set resolves the seal's key, which can sit behind a modal
            // keychain prompt (`AWatcherEventNeverAwaitsTheKeychainTests`).
            let watched = folders.filter(\.enabled)
            guard !watched.isEmpty else { return }
            // Named while it runs, like the sweep, so the memory trail can
            // blame it. The phase writes no log line of its own.
            HelmActivity.phase("autopilot.watch") {
                var acted = 0
                var records: [ActionRecord] = []
                let key = rules.keyMaterial
                // One batch of events is one pass, the way one sweep is.
                let pass = UUID().uuidString
                let counters = CounterBook()
                for path in Set(changed) {
                    guard let plan = self.plan(for: path, among: watched) else { continue }
                    let outcome = runner.run(plan, at: path, key: key, counters: counters)
                    if let record = ActionRecord.of(plan, outcome, run: pass) {
                        records.append(record)
                    }
                    if self.note(outcome, plan: plan, at: path) { acted += 1 }
                }
                self.remember(records)
                if acted > 0 {
                    HelmLog.shared.info(Self.moduleID,
                                        "watcher acted on \(acted) of \(Set(changed).count)")
                }
                // The other unattended leg, same rule: a file binned a moment
                // after it arrived is the same loss as one the sweep takes.
                self.sweepNotice?.tell(records)
                // Only a batch that did something is read: events arrive about
                // once a second while files are written.
                guard !records.isEmpty else { return }
                HelmLog.shared.memory("autopilot.watch")
            }
        }
    }

    /// Blocking work, on the module's own queue rather than the cooperative
    /// pool — and serialised, which is also what stops the timer's sweep and a
    /// Run now from walking the same folder at once.
    private func offQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// The log's line for a refusal about a file.
    ///
    /// **A scope refusal names the rule, not the file**: the file is somewhere
    /// no rule may reach, often a protected folder behind a link, and
    /// `helm.log` is readable by any process running as the user. The rule's id
    /// is enough to find it. Every other reason keeps its path.
    static func refusalLine(_ reason: RuleOutcome.Refusal, plan: RulePlan, path: String) -> String {
        reason == .outOfScope
            ? "refused (rule \(plan.rule.id)): \(reason.rawValue)"
            : "refused \(Redact.path(path)): \(reason.rawValue)"
    }

    /// One file's outcome in the log, and whether it counts as work. Every case
    /// is logged: "what moved my file" must have an answer.
    private func note(_ outcome: RuleOutcome, plan: RulePlan, at path: String) -> Bool {
        switch outcome {
        case let .moved(destination):
            HelmLog.shared.info(Self.moduleID,
                                "moved \(Redact.path(path)) → \(Redact.path(destination))")
        case let .renamed(name):
            HelmLog.shared.info(Self.moduleID,
                                "renamed \(Redact.path(path)) → \(Redact.path(name))")
        case let .tagged(tag):
            HelmLog.shared.info(Self.moduleID, "tagged \(Redact.path(path)): \(tag)")
        case .trashed:
            HelmLog.shared.info(Self.moduleID, "trashed \(Redact.path(path))")
        case .alreadyDone:
            return false
        case .refused, .targetOutOfScope, .failed:
            warnUnlessDone(outcome, plan: plan, at: path)
            return false
        }
        return true
    }

    /// The log's warning for the three outcomes that did not happen, which the
    /// sweep and the unattended path word the same.
    private func warnUnlessDone(_ outcome: RuleOutcome, plan: RulePlan, at path: String) {
        switch outcome {
        case let .refused(reason):
            HelmLog.shared.warn(Self.moduleID, Self.refusalLine(reason, plan: plan, path: path))
        case .targetOutOfScope:
            HelmLog.shared.warn(Self.moduleID,
                                "refused \(Redact.path(path)): \(RuleOutcome.Refusal.outOfScope.rawValue)")
        case let .failed(description):
            HelmLog.shared.warn(Self.moduleID, "failed \(Redact.path(path)): \(description)")
        case .moved, .renamed, .tagged, .trashed, .alreadyDone:
            break
        }
    }

    /// What a changed path has coming to it, or nothing: every question the
    /// FSEvents leg asks before acting, in one place.
    private func plan(for path: String, among watched: [WatchedFolder]) -> RulePlan? {
        let url = URL(fileURLWithPath: path)
        // The gate before any read of the path: `admits` and `facts(of:)` stat
        // it, and a path behind a link into a protected folder is not one whose
        // metadata this module may take — the runner's gate stays behind this.
        guard WatchScope.allows(path, home: home),
              let folder = folder(for: path, among: watched),
              // The same question the sweep's reader asks, so a rule means one
              // thing whichever trigger fires it.
              reader.admits(url, under: folder),
              FileManager.default.fileExists(atPath: path),
              let facts = reader.facts(of: url)
        else { return nil }
        return RulePlan.decide(facts, rules: folder.activeRules)
    }

    /// The watched folder a changed path belongs to: the longest match, so a
    /// watched subfolder's rules win, and the prefix carries its separator, or
    /// `~/Downloads` would claim `~/Downloads Old`.
    ///
    /// **By spelling first, by where both lead if that finds nothing**: FSEvents
    /// reports real paths, so a folder saved as a link is spelled under no
    /// event's path. The second question (`WatchScope.isWithin`) costs stats.
    private func folder(for path: String, among watched: [WatchedFolder]) -> WatchedFolder? {
        let spelled = watched.filter { path.hasPrefix($0.path + "/") }
        let inside = spelled.isEmpty
            ? watched.filter { path != $0.path && WatchScope.isWithin(path, $0.path) }
            : spelled
        return inside.max(by: { $0.path.count < $1.path.count })
    }

    // MARK: - The model's door

    // Architecture/Autopilot.md § How Autopilot's model reaches its engine.
    // The cheap ones go **never onto `queue`**: `status` and `dropHistory` take
    // `queue.sync`, and a sync onto the running queue kills the process
    // (`TheModelsDoorNeverWaitsOnTheEnginesQueueTests`).

    public func readFolders() async -> [WatchedFolder] { await offTheCooperativePool { self.folders } }
    public func readStatus() async -> AutopilotStatus { await offTheCooperativePool { self.status } }
    public func readHistory() async -> [ActionRecord] { await offTheCooperativePool { self.history } }

    /// Answers nothing, whether it saved or refused: the setter is what turns
    /// down a rule set it may not overwrite, and the model re-reads.
    public func save(_ list: [WatchedFolder]) async {
        await offTheCooperativePool { self.folders = list }
    }

    public func dropRefusedRules() async { await offTheCooperativePool { self.discardRefusedRules() } }
    public func dropHistory() async { await offTheCooperativePool { self.clearHistory() } }

    /// The folder arrives as a draft rather than by id: a rule being written has
    /// not been saved, and a preview of the saved version would answer a question
    /// nobody asked. Runs on every keystroke in the rule editor.
    public func dryRun(_ draft: WatchedFolder) async -> [PreviewRow] {
        await offQueue {
            let counters = CounterBook()
            return self.preview(draft).map { PreviewRow($0, counters: counters) }
        }
    }

    /// Nil for a folder the engine does not hold, or one that is switched off.
    public func sweepNow(folderID: String) async -> SweepReport? {
        guard let folder = await readFolders().first(where: { $0.id == folderID }) else { return nil }
        // **A switched-off folder is not swept, by hand either**: checked here,
        // not only at the button, because this is a second door. No report
        // rather than an empty one, which would blur read, missing and refused.
        guard folder.enabled else {
            HelmLog.shared.info(Self.moduleID, "run now refused: the folder is switched off")
            return nil
        }
        // A walk plus N moves, serialised with the hourly sweep, which is
        // reachable at the same moment.
        return await offQueue { self.runNow(folder) }
    }

    /// Both returns, on `queue`: a pass is N moves, and must not run while the
    /// sweep walks the same folder.
    public func putBack(record id: String) async -> UndoReport { await offQueue { self.undo(id) } }
    public func putBack(run id: String) async -> UndoReport { await offQueue { self.undoRun(id) } }
}
