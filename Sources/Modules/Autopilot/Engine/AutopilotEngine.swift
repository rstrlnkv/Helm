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
                               watching: watchLock.withLock { watching })
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
        ActionHistory.within(ActionHistory.decode(store.data(Self.historyKey)))
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
        queue.sync { store.set(nil, for: Self.historyKey) }
    }

    private static let historyKey = "history"

    /// Written once for a whole pass rather than once per file: a sweep of a
    /// full Downloads folder is one write, not two hundred.
    private func remember(_ records: [ActionRecord]) {
        guard !records.isEmpty else { return }
        var kept = ActionHistory.decode(store.data(Self.historyKey))
        // Oldest first, so the newest ends up at the head after the last insert.
        for record in records.sorted(by: { $0.at < $1.at }) {
            kept = ActionHistory.recording(record, into: kept)
        }
        store.set(ActionHistory.encode(kept), for: Self.historyKey)
    }

    /// What a folder's rules would do to what is in it right now.
    ///
    /// The same value the runner executes, so what someone was shown on the dry
    /// run and what happens afterwards cannot drift apart. That is the module's
    /// fourth guarantee — a rule must not run before it has been seen — and the
    /// sentence had come loose from the function that keeps it.
    public func preview(_ folder: WatchedFolder) -> [RulePlan] {
        let files = reader.facts(in: folder.path, depth: folder.depth)
        return RulePlan.decide(files, rules: folder.rules.filter(\.enabled))
    }

    @discardableResult
    public func sweep(_ folder: WatchedFolder) -> SweepReport {
        let reading = reader.reading(in: folder.path, depth: folder.depth)
        let files = reading.files
        let plans = RulePlan.decide(files, rules: folder.activeRules)
        let key = rules.keyMaterial
        var acted = 0, refused = 0, failed = 0
        var records: [ActionRecord] = []
        for plan in plans {
            let path = plan.facts.path
            let outcome = runner.run(plan, at: path, key: key)
            if let record = ActionRecord.of(plan, outcome) { records.append(record) }
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
        if acted + refused + failed > 0 {
            HelmLog.shared.info("autopilot", "swept \(files.count), acted \(acted), " +
                                         "refused \(refused), failed \(failed)")
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
            var acted = 0
            var records: [ActionRecord] = []
            let key = rules.keyMaterial
            for path in Set(changed) {
                guard let plan = self.plan(for: path, among: watched) else { continue }
                let outcome = runner.run(plan, at: path, key: key)
                if let record = ActionRecord.of(plan, outcome) { records.append(record) }
                if self.note(outcome, at: path) { acted += 1 }
            }
            self.remember(records)
            if acted > 0 {
                HelmLog.shared.info("autopilot", "watcher acted on \(acted) of \(Set(changed).count)")
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
            switch name {
            case .folders:
                return EngineReply.encode(self.folders, for: command)
            case .status:
                return EngineReply.encode(self.status, for: command)
            case .discardRefusedRules:
                self.discardRefusedRules()
                return Data()
            case .history:
                return EngineReply.encode(self.history, for: command)
            case .clearHistory:
                self.clearHistory()
                return Data()
            case .setFolders:
                self.setFolders(command)
                return Data()
            case .previewDraft:
                return await self.previewed(command)
            case .runNow:
                return await self.swept(command)
            }
        }
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

    private func swept(_ command: EngineCommand) async -> Data {
        guard let payload = EngineReply.decode(WatchedFolderRef.self, from: command),
              let folder = folders.first(where: { $0.id == payload.id })
        else { return Data() }
        // A walk plus N moves, off the cooperative pool — and serialised with the
        // hourly sweep, which is reachable at the same moment.
        let report = await offQueue { self.sweep(folder) }
        return EngineReply.encode(report, for: command)
    }
}
