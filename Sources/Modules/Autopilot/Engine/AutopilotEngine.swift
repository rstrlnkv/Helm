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

    /// The rule set is read from the timer, from FSEvents and from the
    /// transport — three threads, none of them `queue`, because the read has to
    /// answer before the work is dispatched onto it. So the key and the verdict
    /// carry their own lock rather than borrowing one that is held elsewhere.
    private let keys: RuleKeyPort
    private let trustLock = NSLock()
    /// Held only around `keys.key()` — see `resolvedKey`. Never held with
    /// `trustLock`, in either order.
    private let keyLock = NSLock()
    /// One decision about the stored rules at a time: reading the plist,
    /// judging it against its seal, and recording that judgement are one
    /// indivisible act, and so is saving a rule set.
    ///
    /// The four callers that read the rule set — the sweep timer, FSEvents, the
    /// transport and the watch refresh — each record what they decided in
    /// `refusal`. Unordered, that write says what was true of the file at the
    /// moment *that* read snapshotted it: a read which began before something
    /// edited the plist could finish after the read that saw the edit and put
    /// "these are Helm's own rules" back over "something else wrote these".
    /// Which of the two verdicts a person is shown then depends on which thread
    /// the scheduler ran last, and the verdict is the only signal they get.
    /// `AutopilotSealRaceTests` holds one read open and asserts on the other.
    ///
    /// Taken before `keyLock`, never after, and never with `trustLock` held —
    /// `trustLock` answers `rulesRefused`, which must not wait behind a keychain
    /// prompt. Everything that waits on this lock is already a caller that wants
    /// the rule set, which is what `keyLock` makes them queue for in any case.
    private let decisionLock = NSLock()
    private var key: RuleKey?
    private var refusalReason: RuleRefusal?
    /// Whether the one trust-on-first-use adoption is still unspent. See
    /// `takeTheOneAdoption`.
    private var adoptable = false

    /// Hourly. The events cover anything that happens; this only exists for
    /// conditions that come true by themselves, which is a scale of hours.
    private static let sweepInterval: TimeInterval = 3600

    /// `home` is `WatchScope`'s reference point, injected so a test can point a
    /// whole engine at a temporary directory without being exempted from the
    /// gate the module's safety rests on. `keys` is injected for the same
    /// reason and one more: the production key lives in the user's login
    /// keychain, and a test suite must leave nothing there.
    public init(store: NamespacedStore, transport: LocalTransport = LocalTransport(),
                home: String = NSHomeDirectory(),
                keys: RuleKeyPort = KeychainRuleKey()) {
        self.runner = RuleRunner(home: home)
        self.store = store
        self.keys = keys
        self.localTransport = transport
        self.transport = transport
        wireTransport()
        // **Nothing here reads the key.** `ModuleHost.bootstrap()` builds every
        // enabled module's engine on the main thread inside
        // `applicationDidFinishLaunching`, before the status item exists, and
        // reading the key can take as long as a person takes to answer a modal
        // keychain prompt — which an ad-hoc build raises on every rebuild,
        // because its designated requirement is its cdhash and a rebuilt binary
        // is a different application to the keychain. Measured on an installed
        // build: two prompts per launch, 20.7 s and 31.1 s with no menu bar.
        //
        // The key must still start existing at the first launch of this build —
        // its absence is the whole migration policy below — and `activate` is
        // what makes that true: it reads the rule set, and the first read
        // resolves the key. See `AutopilotLaunchTests`.
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

    // MARK: - The folders

    public var folders: [WatchedFolder] {
        get { decisionLock.withLock { decided() } }
        set {
            let saved = decisionLock.withLock { save(newValue) }
            // Outside the lock. It only enqueues, but what it enqueues is
            // another decision, which takes this lock.
            if saved { refreshWatch() }
        }
    }

    /// Whose rules the plist holds, and the ones that may run. Behind
    /// `decisionLock`, with the `refusing` calls it makes.
    private func decided() -> [WatchedFolder] {
        // Unverifiable is refused, not assumed. Without a key there is no
        // way to tell the person's rules from anyone else's, and this
        // module moves files with nobody watching.
        guard let resolved = resolvedKey() else { refusing(.noKey); return [] }
        // Spent here, before the rules are even looked at, so that a machine
        // whose plist held nothing on the first run of this build cannot be
        // handed a rule set a month later and read it as one that predates
        // the seal.
        let key = RuleKey(material: resolved.material, firstUse: takeTheOneAdoption())
        guard let data = store.data("folders"), !data.isEmpty else { return [] }
        switch RuleSeal.verdict(payload: data, mac: storedMAC, key: key) {
        case .sealed:
            break
        case .adopt:
            store.set(RuleSeal.mac(for: data, key: key.material), for: RuleSeal.storeKey)
            HelmLog.shared.info("autopilot", "sealed the rules that were already here")
        case .broken:
            refusing(.tampered)
            return []
        }
        refusing(nil)
        guard let list = try? JSONDecoder().decode([WatchedFolder].self, from: data)
        else { return [] }
        // On the way out as well as in. The setter has always brought
        // numbers into range, and a plist somebody edited by hand — or one
        // written by an older build — never went through the setter. It
        // reaches the engine here.
        return list.map(\.storable)
    }

    /// The rule set on its way to the plist, sealed. Behind `decisionLock` for
    /// the reason above and one more: the payload and its seal are two writes,
    /// and a read landing between them judges a rule set against the seal of the
    /// one before it — which is the same "something else wrote these" the module
    /// exists to report, said about Helm's own save.
    ///
    /// True when something was written, which is when the watch has to catch up.
    private func save(_ folders: [WatchedFolder]) -> Bool {
        // No key, no save. Writing the rules unsealed would be worse than
        // refusing: the next launch would read them as somebody else's and
        // throw away work the person had just done.
        guard let key = resolvedKey() else {
            HelmLog.shared.error("autopilot",
                                 "could not seal \(folders.count) folders, so they were not saved")
            return false
        }
        // **A rule set the engine refuses to run is one it must not overwrite.**
        // Judged from the plist rather than from `refusalReason`, so the answer
        // does not depend on whether anything has read the rules yet this run —
        // a save is the one moment where a stale verdict would be spent
        // destroying the thing it exists to protect.
        guard RuleSeal.mayOverwrite(storedVerdict(key)) else {
            refusing(.tampered)
            HelmLog.shared.error("autopilot",
                                 "the stored rules were not written by Helm, so \(folders.count) " +
                                 "folders were not saved over them")
            return false
        }
        // Encoding a rule list can genuinely fail — `JSONEncoder` refuses a
        // non-finite `Double`, which a condition can hold — and returning
        // quietly discarded every folder and every rule while the screen
        // went on showing the new state. The old list survives instead, and
        // the failure is in the log.
        // Clamped first: a condition holding ±∞ makes `JSONEncoder` throw,
        // and the rules are one JSON value — so one unencodable number in
        // one rule discarded every folder and every rule the person had,
        // silently, while the screen went on showing the new state.
        do {
            let data = try JSONEncoder().encode(folders.map(\.storable))
            // Rules first, seal second. Interrupted between the two, the
            // plist holds a rule set whose seal does not fit it — which is
            // refused, and refusing rules the person did save is the
            // survivable half of this pair.
            store.set(data, for: "folders")
            store.set(RuleSeal.mac(for: data, key: key.material), for: RuleSeal.storeKey)
            // Whatever was in the file before, these are Helm's now.
            refusing(nil)
            return true
        } catch {
            HelmLog.shared.failure("autopilot", "could not save \(folders.count) folders", error)
            return false
        }
    }

    private var storedMAC: String? {
        let mac = store.string(RuleSeal.storeKey, default: "")
        return mac.isEmpty ? nil : mac
    }

    /// What the seal says about the rules in the plist right now, or `nil` when
    /// there are none. Behind `decisionLock`, like both of its callers.
    private func storedVerdict(_ key: RuleKey) -> RuleSeal.Verdict? {
        guard let data = store.data("folders"), !data.isEmpty else { return nil }
        return RuleSeal.verdict(payload: data, mac: storedMAC, key: key)
    }

    /// Throw away a rule set that was not written by Helm, so the page can be
    /// used again.
    ///
    /// The one thing the card above the folder list may send, and the only way
    /// past the guard in `save`. It takes `tampered` alone: a `noKey` refusal is
    /// a keychain that would not answer, where the rules are very probably the
    /// person's own and the answer is to wait rather than to delete them.
    public func discardRefusedRules() {
        decisionLock.withLock {
            guard refusal == .tampered else { return }
            store.set(nil, for: "folders")
            store.set(nil, for: RuleSeal.storeKey)
            refusing(nil)
            HelmLog.shared.info("autopilot", "the rules that did not match their seal were discarded")
        }
    }

    // MARK: - Whose rules these are

    /// Why the stored rule set is not being run, or `nil` when it is.
    ///
    /// **The two reasons are not one sentence, and folding them was half of what
    /// made this dangerous.** `noKey` is a keychain that would not answer: the
    /// rules may be perfectly good and unreadable for as long as a login
    /// keychain stays locked, and the answer is to wait. `tampered` is a rule
    /// set something else wrote, where waiting changes nothing and the only way
    /// forward is to throw it away — which is why `discardRefusedRules` takes
    /// only that one.
    ///
    /// Read by `AutopilotCommand.status`, which is how the page draws a card
    /// saying the rules could not be read instead of an empty state saying there
    /// were never any.
    public var refusal: RuleRefusal? { trustLock.withLock { refusalReason } }

    /// The same fact as a flag, which is how ARCHITECTURE.md § Autopilot names
    /// it. Derived, never stored beside `refusal`: two spellings of one verdict
    /// is how the two would come to disagree.
    public var rulesRefused: Bool { refusal != nil }

    /// What the page asks for beside the folder list.
    ///
    /// The verdict is a *side effect* of judging the stored rules, so this
    /// judges them rather than repeating whatever the last read decided — the
    /// page sends this and `folders` in the same breath, and which arrives first
    /// is the transport's business, not something a screen should depend on.
    /// The judgement and the reading of it are one critical section for the
    /// reason `decisionLock` exists at all.
    public var status: AutopilotStatus {
        let (reason, watched) = decisionLock.withLock { () -> (RuleRefusal?, [WatchedFolder]) in
            let list = decided()
            return (trustLock.withLock { refusalReason }, list)
        }
        // One question per folder, asked outside the lock: a page opening is not
        // a reason to hold every other reader of the rule set behind a
        // filesystem call, and `state(of:)` never touches the rules.
        var states: [String: FolderState] = [:]
        for folder in watched { states[folder.id] = reader.state(of: folder.path) }
        return AutopilotStatus(refusal: reason, folders: states,
                               watching: watchLock.withLock { watching })
    }

    /// Logged on the way in, once per transition. The rules are read on every
    /// sweep, every filesystem event and every settings request, and a line per
    /// read would bury the log in the state it is warning about.
    private func refusing(_ next: RuleRefusal?) {
        trustLock.lock()
        defer { trustLock.unlock() }
        guard next != refusalReason else { return }
        refusalReason = next
        switch next {
        case .tampered:
            // No path, no folder, no rule name: the log ships to strangers, and
            // this line is about the rule set as a whole in any case.
            HelmLog.shared.error("autopilot",
                                 "the stored rules do not match their seal — something other " +
                                 "than Helm wrote them; none of them will run")
        case .noKey:
            HelmLog.shared.error("autopilot",
                                 "the key the rules are sealed with is unavailable; " +
                                 "no rules will run until it can be read")
        case .none:
            break
        }
    }

    /// The key, resolved once per run and held. The `firstUse` it carries out
    /// of the keychain is not the one the verdict sees — that one comes from
    /// `takeTheOneAdoption`, which is stricter.
    ///
    /// **`trustLock` is not held across the port call.** The port can sit inside
    /// a modal keychain prompt for as long as a person ignores it, and
    /// `trustLock` is also what answers `rulesRefused` — so holding it there put
    /// a dialog between the UI and the engine's own state. `keyLock` is held
    /// instead: it serialises the port, so the three threads that read the rule
    /// set cannot each raise a prompt of their own, and it guards nothing any
    /// other caller wants.
    private func resolvedKey() -> RuleKey? {
        if let held = trustLock.withLock({ key }) { return held }

        keyLock.lock()
        defer { keyLock.unlock() }
        // Another thread may have resolved it while this one waited.
        if let held = trustLock.withLock({ key }) { return held }
        guard let resolved = keys.key() else { return nil }

        return trustLock.withLock {
            key = RuleKey(material: resolved.material, firstUse: false)
            // Armed by the keychain having had to create the item, and by
            // nothing else. This is the entire migration policy: the key's
            // absence is the only evidence available that this installation
            // predates sealing, and it is evidence kept somewhere the plist's
            // author cannot reach.
            adoptable = resolved.firstUse
            return key
        }
    }

    /// **The migration, and the judgement behind it.** People upgrading to this
    /// build have rules and no seal. Refusing them would delete real
    /// configuration — a worse defect than the one the seal closes, and one the
    /// person has no way to diagnose. So the run that *creates* the key accepts
    /// the rule set it finds and seals it: trust on first use.
    ///
    /// The weakness is real and worth stating plainly: an attacker who plants
    /// rules before the first run of this build has them adopted, and wins. It
    /// is accepted because it is a race they must win once, on one machine,
    /// against an update they cannot schedule — against a door that today
    /// stands open at any hour on every machine.
    ///
    /// What is not left open is re-arming it, which would give that back:
    ///
    /// - The latch is the keychain item, not a flag in the plist. Writing rules
    ///   *and deleting `foldersMAC`* is the obvious attack on trust-on-first-use
    ///   and it buys nothing, because the seal's absence is not what says a
    ///   migration is due. Deleting the keychain item would say so, and that is
    ///   an item whose access list names only Helm — another process removing it
    ///   has to get past the user.
    /// - One adoption per run of the process, spent at the first read of the
    ///   rule set whether or not there was one to read. Helm stays running for
    ///   days; without this, an attacker who wrote rules at any point during the
    ///   launch that created the key would be adopted too.
    private func takeTheOneAdoption() -> Bool {
        trustLock.lock()
        defer { trustLock.unlock() }
        defer { adoptable = false }
        return adoptable
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
        var acted = 0, refused = 0, failed = 0
        var records: [ActionRecord] = []
        for plan in plans {
            let path = plan.facts.path
            let outcome = runner.run(plan, at: path)
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
            for path in Set(changed) {
                guard let plan = self.plan(for: path, among: watched) else { continue }
                let outcome = runner.run(plan, at: path)
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
