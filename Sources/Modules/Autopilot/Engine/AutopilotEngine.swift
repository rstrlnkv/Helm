import Foundation
import HelmContract
import HelmRuntime

/// The module's engine: folders, their rules, and the three things that make
/// rules run.
///
/// Three triggers, because none of them covers the others:
///
/// - **FSEvents**, so a file that appears is sorted a moment later. This is the
///   behaviour the module exists for.
/// - **A sweep on a timer**, because a rule that says "older than 30 days"
///   becomes true with nothing happening, and no event will ever fire for it.
/// - **Run now**, because someone who has just written a rule wants to see it
///   work rather than wait an hour to find out it does not.
public final class AutopilotEngine: ModuleEngine, @unchecked Sendable {
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    private let store: NamespacedStore
    /// Whose rules these are, which one of the person's rule sets they are, and
    /// the only thing here that touches the keychain — `SealedRules`.
    private let rules: SealedRules
    private let reader = FolderReader()
    private let runner: RuleRunner
    /// The other direction. Beside the runner and holding the same home,
    /// because a return goes through a gate measured against the same one.
    private let undoer: UndoRunner
    private let queue = DispatchQueue(label: "helm.rules", qos: .utility)
    /// Behind `queue`, like everything else here. It is written on the main
    /// actor (`activate`/`deactivate` — `ModuleHost` is `@MainActor`) and read
    /// from `refreshWatch`, which the `folders` setter reaches from the
    /// transport handler on whatever thread called it. This class is
    /// `@unchecked Sendable`; that has to mean something.
    private var watcher: FolderWatcher?
    private var sweepTimer: DispatchSourceTimer?

    /// Hourly. The events cover anything that happens; this only exists for
    /// conditions that come true by themselves, which is a scale of hours.
    private static let sweepInterval: TimeInterval = 3600

    /// `home` is `WatchScope`'s reference point, injected so a test can point a
    /// whole engine at a temporary directory without being exempted from the
    /// gate the module's safety rests on. `keys` and `sequence` are injected for
    /// the same reason and one more: the production items live in the user's
    /// login keychain, and a test suite must leave nothing there.
    public init(store: NamespacedStore, transport: LocalTransport = LocalTransport(),
                home: String = NSHomeDirectory(),
                keys: RuleKeyPort = KeychainRuleKey(),
                sequence: RuleSequencePort = KeychainRuleSequence()) {
        self.runner = RuleRunner(home: home)
        self.undoer = UndoRunner(home: home)
        self.store = store
        self.rules = SealedRules(store: store, keys: keys, sequence: sequence)
        self.localTransport = transport
        self.transport = transport
        wireTransport()
        // **Nothing here reads the keychain**, and `SealedRules.init` says what
        // that costs when it is got wrong. `activate` is what makes the key
        // start existing at the first launch of a build.
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

    /// Why the stored rule set is not being run, or `nil` when it is. Read by
    /// `AutopilotCommand.status`, which is how the page draws a card saying the
    /// rules could not be read instead of an empty state saying there were never
    /// any.
    public var refusal: RuleRefusal? { rules.refusal }

    /// The same fact as a flag, which is how ARCHITECTURE.md § Autopilot names
    /// it. Derived, never stored beside `refusal`: two spellings of one verdict
    /// is how the two would come to disagree.
    public var rulesRefused: Bool { refusal != nil }

    /// Throw away a rule set that was not written by Helm, so the page can be
    /// used again. The one thing the card above the folder list may send.
    public func discardRefusedRules() { rules.discardRefused() }

    /// What the page asks for beside the folder list.
    ///
    /// The rules and the reason are asked for together, because the reason is a
    /// side effect of judging the rules — the page sends this and `folders` in
    /// the same breath, and which arrives first is the transport's business.
    public var status: AutopilotStatus {
        let (watched, reason) = rules.decision()
        // One question per folder, asked outside that decision: a page opening
        // is not a reason to hold every other reader of the rule set behind a
        // filesystem call, and `state(of:)` never touches the rules.
        var states: [String: FolderState] = [:]
        for folder in watched { states[folder.id] = reader.state(of: folder.path) }
        return AutopilotStatus(refusal: reason, folders: states,
                               watching: watchLock.withLock { watching },
                               historyRefused: historyRefused)
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
    }

    /// On the engine's queue, including the *read*.
    ///
    /// Reading `folders` resolves the key, and both callers arrive on a thread
    /// that must not wait for a keychain prompt: `activate` on the main thread
    /// during launch, the setter on whatever thread the transport handed it.
    /// Only the `watcher?.watch` used to be dispatched here, which left the
    /// blocking half on the caller.
    private func refreshWatch() {
        queue.async { [self] in
            let paths = folders.filter(\.enabled).map(\.path)
            // **The answer is taken.** `watch` grew this channel because both
            // engines that use it logged that they were watching a folder with
            // no way to know whether they were — and this one went on throwing
            // it away, which is the switch saying «on» over a folder nothing is
            // looking at.
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
            HelmLog.shared.info("autopilot", "watching \(count) folder(s)")
        } else if count > 0 {
            HelmLog.shared.error("autopilot",
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

    /// What Autopilot did, newest first, over the last thirty days.
    ///
    /// Read through the window on the way out as well as on the way in, so a
    /// store left behind by a machine that was asleep for a month shows nothing
    /// rather than a page of history that is no longer true.
    public var history: [ActionRecord] {
        ActionHistory.within(ActionHistory.decode(store.data(ActionHistory.storeKey)))
    }

    /// Whether the stored history is not Helm's, in which case nothing in it
    /// may be put back and nothing is added to it.
    ///
    /// Shown all the same: the page's job is to say what happened, and a
    /// history that has been rewritten is itself something that happened.
    public var historyRefused: Bool {
        !rules.historyIsHelms(queue.sync { store.data(ActionHistory.storeKey) })
    }

    /// On the engine's own queue, like every write to this key.
    ///
    /// `remember` is a read-modify-write and reaches the store from the timer,
    /// from `offQueue` and from the FSEvents path — all on `queue`. This
    /// arrived on whatever thread the transport handed it, so a clear landing
    /// between a `remember`'s read and its write was simply undone, and a row
    /// survived "Clear".
    public func clearHistory() {
        // `sync`, not `async`: the caller's next line reads the history back,
        // and a clear that has not landed yet reads as a clear that did not
        // happen. Safe from the transport, which arrives on the concurrency
        // pool and never on this queue.
        queue.sync { rules.clearHistory() }
    }

    /// Written once for a whole pass rather than once per file: a sweep of a
    /// full Downloads folder is one write, not two hundred.
    ///
    /// **Nothing is folded into a history that does not verify.** Appending to
    /// one and sealing the result would put Helm's own signature over records
    /// something else wrote — which is the laundering the seal exists to stop,
    /// and it would turn a forged record into one a return will act on.
    /// Deleting it instead would take the warning off the page before anybody
    /// read it. So it is frozen where it is, with the way out on the page, and
    /// the run's work is in the log as it always was.
    private func remember(_ records: [ActionRecord]) {
        guard !records.isEmpty else { return }
        let stored = store.data(ActionHistory.storeKey)
        guard rules.historyIsHelms(stored) else {
            HelmLog.shared.error("autopilot",
                                 "the stored history was not written by Helm, so \(records.count) "
                                 + "records were not added to it and none of it can be put back")
            return
        }
        var kept = ActionHistory.decode(stored)
        // Oldest first, so the newest ends up at the head after the last insert.
        for record in records.sorted(by: { $0.at < $1.at }) {
            kept = ActionHistory.recording(record, into: kept)
        }
        write(kept)
    }

    /// The seal first, then the history it signs.
    ///
    /// Either order leaves a mismatched pair if the process dies between the
    /// two writes, and a mismatched pair refuses — which is the survivable
    /// half. This order is the one where a keychain that will not answer costs
    /// nothing: the seal fails, and the history that was already there is still
    /// the history, still signed.
    private func write(_ history: [ActionRecord]) {
        guard let data = ActionHistory.encode(history), rules.seal(history: data) else { return }
        store.set(data, for: ActionHistory.storeKey)
    }

    // MARK: - Putting it back

    /// Put one action back.
    ///
    /// A report of one line rather than a bare outcome, so the page reads a
    /// single return and a whole pass the same way — and so the sentence that
    /// says what happened is composed once.
    @discardableResult
    public func undo(_ recordID: String) -> UndoReport {
        putBack { $0.id == recordID }
    }

    /// Put a whole pass back — every action of one sweep or one batch of
    /// events, newest first.
    ///
    /// Newest first because a pass can have moved two files onto one name: the
    /// second arrival was numbered, and undoing it before the first is what
    /// gives each of them its own name back.
    @discardableResult
    public func undoRun(_ run: String) -> UndoReport {
        putBack { $0.run == run }
    }

    /// On `queue`, like every other read-modify-write of this key.
    ///
    /// **The seal is asked once, for the whole gesture.** A history something
    /// else wrote is refused entire rather than record by record: every field a
    /// return acts on comes out of it, so there is no half of it worth
    /// believing — and the refusal is reported per line, because the page's
    /// report is the only place it can be said.
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
            HelmLog.shared.info("autopilot", "put back \(report.restored.count) of \(lines.count)")
        }
        if !report.notPutBack.isEmpty {
            HelmLog.shared.warn("autopilot", "could not put back \(report.notPutBack.count)")
        }
        return report
    }

    /// What a folder's rules would do to what is in it right now.
    ///
    /// The same value the runner executes, so what someone was shown on the dry
    /// run and what happens afterwards cannot drift apart. That is the module's
    /// fourth guarantee — a rule must not run before it has been seen — and the
    /// sentence had come loose from the function that keeps it.
    public func preview(_ folder: WatchedFolder) -> [RulePlan] {
        // A full folder read per keystroke in the editor, which is bulk work
        // whatever the folder — so it names itself the way `runNow` does, and
        // the reading is inside the phase for the same reason: a phase that has
        // ended cannot be excluded from its own line. `memory` is a delta and
        // silent below its threshold, so an ordinary keystroke writes nothing.
        HelmActivity.phase("autopilot.preview") {
            defer { HelmLog.shared.memory("autopilot.preview") }
            let files = reader.facts(in: folder.path, depth: folder.depth)
            return RulePlan.decide(files, rules: folder.rules.filter(\.enabled))
        }
    }

    /// `manual` is the trigger, and it decides the sweep's voice alone —
    /// `SweepAnnouncement` holds the condition, and `runNow` is the only caller
    /// that passes `true`.
    @discardableResult
    public func sweep(_ folder: WatchedFolder, manual: Bool = false) -> SweepReport {
        let reading = reader.reading(in: folder.path, depth: folder.depth)
        let files = reading.files
        let plans = RulePlan.decide(files, rules: folder.activeRules)
        let key = rules.keyMaterial
        // One value for the whole pass, so the page can offer to put a sweep
        // back rather than five hundred separate rows.
        let pass = UUID().uuidString
        var acted = 0, refused = 0, failed = 0
        var records: [ActionRecord] = []
        for plan in plans {
            let path = plan.facts.path
            let outcome = runner.run(plan, at: path, key: key)
            if let record = ActionRecord.of(plan, outcome, run: pass) { records.append(record) }
            switch outcome {
            case .moved, .renamed, .tagged, .trashed:
                acted += 1
            case .alreadyDone:
                break
            case let .refused(reason):
                refused += 1
                HelmLog.shared.warn("autopilot", "refused \(Redact.path(path)): \(reason.rawValue)")
            case let .failed(description):
                failed += 1
                HelmLog.shared.warn("autopilot", "failed \(Redact.path(path)): \(description)")
            }
        }
        remember(records)
        let report = SweepReport(folderID: folder.id, examined: files.count,
                                 acted: acted, refused: refused, failed: failed,
                                 folder: reading.state)
        if let line = SweepAnnouncement.line(for: report, manual: manual) {
            HelmLog.shared.info("autopilot", line)
        }
        // A folder that could not be read at all is the one thing a sweep of
        // nothing has to say out loud: unattended, hourly, and otherwise
        // indistinguishable from a folder where there was nothing to do.
        if reading.state != .read {
            HelmLog.shared.warn("autopilot",
                                "\(Redact.path(folder.path)) could not be swept: \(reading.state.rawValue)")
        }
        return report
    }

    /// One folder, because a person asked — and answered out loud, always.
    ///
    /// `sweep`'s line is conditional, which is right for the hourly sentinel
    /// and wrong for a command: a manual run that found nothing to do and a
    /// manual run that never started were the same silence, in the journal the
    /// button exists to be seen in. So the command's path writes the fact, the
    /// phase and the memory reading unconditionally, and the sentinel keeps
    /// its condition. The reading is inside the phase — a phase that has ended
    /// cannot be excluded from its own line.
    @discardableResult
    public func runNow(_ folder: WatchedFolder) -> SweepReport {
        HelmActivity.phase("autopilot.runNow") {
            defer { HelmLog.shared.memory("autopilot.runNow") }
            return sweep(folder, manual: true)
        }
    }

    /// Every enabled folder, which is what the sweep timer runs.
    ///
    /// Labelled because it is unattended. `HelmLog.memory` is a delta against the
    /// last reading for the same label and is silent below 8 MB, so a sweep that
    /// costs nothing says nothing — but the app's memory trail had a hole exactly
    /// the shape of this method: growth appearing between two `idle` readings with
    /// no command in between, because a timer is not a command. A reading here
    /// turns "something happened" into "the sweep happened", and the reclaim hands
    /// the emptied regions back to macOS at the moment the work ends rather than
    /// leaving them resident until the next labelled operation
    /// (docs/superpowers/plans/2026-07-29-third-pass.md has the trail).
    @discardableResult
    public func sweepAll() -> [SweepReport] {
        let reports = HelmActivity.phase("autopilot.sweep") {
            folders.filter(\.enabled).map { sweep($0) }
        }
        guard !reports.isEmpty else { return reports }
        HelmLog.shared.memory("autopilot.sweep")
        return reports
    }

    /// One event's worth of work. The paths FSEvents reports are files, and the
    /// folder they belong to decides which rules they meet.
    ///
    /// An FSEvents stream is recursive whether or not anyone asked, so which
    /// files a rule may be offered has to be decided here — `plan(for:among:)`,
    /// which asks the reader the same question the sweep's enumerator asks.
    /// Without it a depth-1 watch on Downloads acted on every file in every
    /// project unzipped into it, and on the contents of application bundles.
    ///
    /// Internal rather than private because this is the only way a test can drive
    /// the leg: `FolderWatcher` carries `kFSEventStreamCreateFlagIgnoreSelf`, so
    /// a file a test writes raises no event of its own, and a test of the stream
    /// would be a test of a child process.
    func handle(_ changed: [String]) {
        let watched = folders.filter(\.enabled)
        guard !watched.isEmpty else { return }
        queue.async { [self] in
            // Named while it runs, like the sweep — this is where the module
            // does all of its unattended work, and it was the one leg the
            // memory trail could not blame. The phase itself writes no log
            // line, so a quiet batch costs the trail nothing.
            HelmActivity.phase("autopilot.watch") {
                var acted = 0
                var records: [ActionRecord] = []
                let key = rules.keyMaterial
                // One batch of events is one pass, the way one sweep is.
                let pass = UUID().uuidString
                for path in Set(changed) {
                    guard let plan = self.plan(for: path, among: watched) else { continue }
                    let outcome = runner.run(plan, at: path, key: key)
                    if let record = ActionRecord.of(plan, outcome, run: pass) {
                        records.append(record)
                    }
                    if self.note(outcome, at: path) { acted += 1 }
                }
                self.remember(records)
                if acted > 0 {
                    HelmLog.shared.info("autopilot",
                                        "watcher acted on \(acted) of \(Set(changed).count)")
                }
                // Only a batch that did something is read: events coalesce to
                // about one batch a second while files are being written, and a
                // batch where no rule matched must not fill the one trail that
                // has to stay readable — the same line `sweepAll` draws.
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

    /// One file's outcome in the log, and whether it counts as work.
    ///
    /// The unattended path: a file arrived and a rule acted on it with nobody
    /// looking, which is exactly why every case is logged — this once recorded
    /// only refusals and failures, so a rule that worked left no trace and "what
    /// moved my file" had no answer anywhere.
    private func note(_ outcome: RuleOutcome, at path: String) -> Bool {
        switch outcome {
        case let .moved(destination):
            HelmLog.shared.info("autopilot",
                                "moved \(Redact.path(path)) → \(Redact.path(destination))")
        case let .renamed(name):
            HelmLog.shared.info("autopilot",
                                "renamed \(Redact.path(path)) → \(Redact.path(name))")
        case let .tagged(tag):
            HelmLog.shared.info("autopilot", "tagged \(Redact.path(path)): \(tag)")
        case .trashed:
            HelmLog.shared.info("autopilot", "trashed \(Redact.path(path))")
        case .alreadyDone:
            return false
        case let .refused(reason):
            HelmLog.shared.warn("autopilot", "refused \(Redact.path(path)): \(reason.rawValue)")
            return false
        case let .failed(description):
            HelmLog.shared.warn("autopilot", "failed \(Redact.path(path)): \(description)")
            return false
        }
        return true
    }

    /// What a changed path has coming to it, or nothing.
    ///
    /// Every question the FSEvents leg asks before acting, in one place: which
    /// folder's rules these are, whether those rules may be offered this file at
    /// all, whether it is still there, and which rule takes it.
    private func plan(for path: String, among watched: [WatchedFolder]) -> RulePlan? {
        let url = URL(fileURLWithPath: path)
        guard let folder = folder(for: path, among: watched),
              // The same question the sweep's reader asks, so a rule means one
              // thing whichever trigger fires it.
              reader.admits(url, under: folder),
              FileManager.default.fileExists(atPath: path),
              let facts = reader.facts(of: url)
        else { return nil }
        return RulePlan.decide(facts, rules: folder.activeRules)
    }

    /// The watched folder a changed path belongs to.
    ///
    /// Longest match, not first: with a folder and a subfolder of it both
    /// watched, the inner one's rules are the ones that were written about
    /// these files. And the prefix carries its separator — without it
    /// `~/Downloads` claimed the files in `~/Downloads Old`.
    ///
    /// Whether the folder's rules may be offered *this* file — its depth, and
    /// the hidden and package questions the sweep's enumerator asks — is
    /// `FolderReader.admits`, which used to be half here and half nowhere.
    private func folder(for path: String, among watched: [WatchedFolder]) -> WatchedFolder? {
        watched.filter { path.hasPrefix($0.path + "/") }
            .max(by: { $0.path.count < $1.path.count })
    }

    // MARK: - Transport

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            guard let name = AutopilotCommand(rawValue: command.name) else { return Data() }
            return await self.answer(name, command)
        }
    }

    /// The four commands that do real work, and everything else.
    ///
    /// Split in two because these are the ones that walk a folder or move
    /// files: each goes off the cooperative pool and onto the engine's own
    /// queue, and that is what serialises them against the hourly sweep. Both
    /// switches are exhaustive with no `default`, so a command added to the
    /// enum is a build error in whichever half it belongs to.
    private func answer(_ name: AutopilotCommand, _ command: EngineCommand) async -> Data {
        switch name {
        case .previewDraft:
            return await previewed(command)
        case .runNow:
            return await swept(command)
        case .undo:
            return await putBack(command) { self.undo($0) }
        case .undoRun:
            return await putBack(command) { self.undoRun($0) }
        case .folders, .status, .discardRefusedRules, .history, .clearHistory, .setFolders:
            return answerAtOnce(name, command)
        }
    }

    /// The commands that read state or hand a value on, which are cheap enough
    /// to answer on the thread that asked.
    private func answerAtOnce(_ name: AutopilotCommand, _ command: EngineCommand) -> Data {
        switch name {
        case .folders:
            return EngineReply.encode(folders, for: command)
        case .status:
            return EngineReply.encode(status, for: command)
        case .discardRefusedRules:
            discardRefusedRules()
        case .history:
            return EngineReply.encode(history, for: command)
        case .clearHistory:
            clearHistory()
        case .setFolders:
            setFolders(command)
        case .previewDraft, .runNow, .undo, .undoRun:
            // Answered by the half above. Named rather than defaulted, so a
            // command that moves to the other half is a build error here.
            break
        }
        return Data()
    }

    /// A list that will not decode changes nothing: the setter is what refuses a
    /// rule set it may not overwrite, and it must not be handed an empty one
    /// because a payload was truncated.
    private func setFolders(_ command: EngineCommand) {
        guard let list = EngineReply.decode([WatchedFolder].self, from: command) else { return }
        folders = list
    }

    /// The folder arrives as a draft rather than by id: a rule being written has
    /// not been saved, and a preview of the saved version would answer a question
    /// nobody asked.
    private func previewed(_ command: EngineCommand) async -> Data {
        guard let draft = EngineReply.decode(WatchedFolder.self, from: command)
        else { return Data() }
        // Runs on every keystroke in the rule editor.
        let rows = await offQueue { self.preview(draft).map(PreviewRow.init) }
        return EngineReply.encode(rows, for: command)
    }

    /// Both returns, which differ only in what the id names.
    ///
    /// Off the cooperative pool and onto the engine's queue like every other
    /// piece of blocking work here — a whole pass is N moves, and it must not
    /// run while the hourly sweep is walking the same folder.
    private func putBack(_ command: EngineCommand,
                         _ work: @escaping @Sendable (String) -> UndoReport) async -> Data {
        guard let payload = EngineReply.decode(UndoRequest.self, from: command) else { return Data() }
        let report = await offQueue { work(payload.id) }
        return EngineReply.encode(report, for: command)
    }

    private func swept(_ command: EngineCommand) async -> Data {
        guard let payload = EngineReply.decode(WatchedFolderRef.self, from: command),
              let folder = folders.first(where: { $0.id == payload.id })
        else { return Data() }
        // A walk plus N moves, off the cooperative pool — and serialised with the
        // hourly sweep, which is reachable at the same moment.
        let report = await offQueue { self.runNow(folder) }
        return EngineReply.encode(report, for: command)
    }
}
