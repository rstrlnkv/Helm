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
    private var key: RuleKey?
    private var refusal: Refusal?
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
        get {
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
        set {
            // No key, no save. Writing the rules unsealed would be worse than
            // refusing: the next launch would read them as somebody else's and
            // throw away work the person had just done.
            guard let key = resolvedKey() else {
                HelmLog.shared.error("autopilot",
                                     "could not seal \(newValue.count) folders, so they were not saved")
                return
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
                let data = try JSONEncoder().encode(newValue.map(\.storable))
                // Rules first, seal second. Interrupted between the two, the
                // plist holds a rule set whose seal does not fit it — which is
                // refused, and refusing rules the person did save is the
                // survivable half of this pair.
                store.set(data, for: "folders")
                store.set(RuleSeal.mac(for: data, key: key.material), for: RuleSeal.storeKey)
                // Whatever was in the file before, these are Helm's now.
                refusing(nil)
                refreshWatch()
            } catch {
                HelmLog.shared.failure("autopilot", "could not save \(newValue.count) folders",
                                       error)
            }
        }
    }

    private var storedMAC: String? {
        let mac = store.string(RuleSeal.storeKey, default: "")
        return mac.isEmpty ? nil : mac
    }

    // MARK: - Whose rules these are

    /// True while the stored rule set is not being run — it does not match its
    /// seal, or there is no key to check it against.
    ///
    /// **This has no reader yet, and that is a known gap rather than an
    /// oversight.** A refused rule set makes `folders` empty, so the settings
    /// page draws its "no folders yet" empty state: a person whose rules were
    /// tampered with is told they never had any. The log says what happened and
    /// nothing on screen does.
    ///
    /// What closing it takes, precisely:
    ///
    /// 1. a `rulesRefused` command in `wireTransport`, beside `history`;
    /// 2. `@Published var rulesRefused` on `AutopilotViewModel`, read in
    ///    `load()` — not the existing `banner`, which is a dismissible report
    ///    of a sweep and this must not be dismissible;
    /// 3. a card above the folder list in `AutopilotSettingsPage`, with an
    ///    `ApStr` string in all eight languages saying the rules on disk were
    ///    not written by Helm and none of them are running.
    ///
    /// It is left undone deliberately. The affordance beside that message is a
    /// real decision — the obvious one, "discard them and start again", throws
    /// away the person's own rules on the reading of a machine that has just
    /// been told it cannot trust what it is reading — and the house rule is
    /// that UI is verified in the running app through the env-gated screenshot
    /// harness, which lives in a target this work may not touch. A card that
    /// compiles is not a card that was seen.
    public var rulesRefused: Bool { trustLock.withLock { refusal != nil } }

    private enum Refusal { case tampered, noKey }

    /// Logged on the way in, once per transition. The rules are read on every
    /// sweep, every filesystem event and every settings request, and a line per
    /// read would bury the log in the state it is warning about.
    private func refusing(_ next: Refusal?) {
        trustLock.lock()
        defer { trustLock.unlock() }
        guard next != refusal else { return }
        refusal = next
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
            watcher?.watch(paths)
        }
    }

    private func startSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.sweepInterval, repeating: Self.sweepInterval)
        timer.setEventHandler { [weak self] in _ = self?.sweepAll() }
        timer.resume()
        sweepTimer = timer
    }

    // MARK: - Running

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
        let files = reader.facts(in: folder.path, depth: folder.depth)
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
                                 acted: acted, refused: refused, failed: failed)
        if acted + refused + failed > 0 {
            HelmLog.shared.info("autopilot", "swept \(files.count), acted \(acted), " +
                                         "refused \(refused), failed \(failed)")
        }
        return report
    }

    @discardableResult
    public func sweepAll() -> [SweepReport] {
        folders.filter(\.enabled).map { sweep($0) }
    }

    /// One event's worth of work. The paths FSEvents reports are files, and the
    /// folder they belong to decides which rules they meet.
    ///
    /// An FSEvents stream is recursive whether or not anyone asked, so the depth
    /// has to be applied here — without it, the folder's own "include
    /// subfolders" setting did not reach the module's primary trigger and a
    /// depth-1 watch on Downloads acted on every file in every project unzipped
    /// into it.
    /// The unattended path: a file arrived and a rule acted on it with nobody
    /// looking. Which is exactly why it is logged — this used to record only
    /// refusals and failures, so a rule that worked left no trace at all, and
    /// the answer to "what moved my file" was nowhere. `sweep` has always
    /// logged its totals; this had `default: break`.
    private func handle(_ changed: [String]) {
        let watched = folders.filter(\.enabled)
        guard !watched.isEmpty else { return }
        queue.async { [self] in
            var acted = 0
            var records: [ActionRecord] = []
            for path in Set(changed) {
                guard let folder = self.folder(for: path, among: watched),
                      FileManager.default.fileExists(atPath: path),
                      let facts = reader.facts(of: URL(fileURLWithPath: path)),
                      let plan = RulePlan.decide(facts, rules: folder.activeRules)
                else { continue }
                let outcome = runner.run(plan, at: path)
                if let record = ActionRecord.of(plan, outcome) { records.append(record) }
                switch outcome {
                case let .moved(destination):
                    acted += 1
                    HelmLog.shared.info("autopilot",
                                        "moved \(Redact.path(path)) → \(Redact.path(destination))")
                case let .renamed(name):
                    acted += 1
                    HelmLog.shared.info("autopilot",
                                        "renamed \(Redact.path(path)) → \(Redact.path(name))")
                case let .tagged(tag):
                    acted += 1
                    HelmLog.shared.info("autopilot", "tagged \(Redact.path(path)): \(tag)")
                case .trashed:
                    acted += 1
                    HelmLog.shared.info("autopilot", "trashed \(Redact.path(path))")
                case .alreadyDone:
                    break
                case let .refused(reason):
                    HelmLog.shared.warn("autopilot",
                                        "refused \(Redact.path(path)): \(reason.rawValue)")
                case let .failed(description):
                    HelmLog.shared.warn("autopilot",
                                        "failed \(Redact.path(path)): \(description)")
                }
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

    /// The watched folder a changed path belongs to, at that folder's depth.
    ///
    /// Longest match, not first: with a folder and a subfolder of it both
    /// watched, the inner one's rules are the ones that were written about
    /// these files. And the prefix carries its separator — without it
    /// `~/Downloads` claimed the files in `~/Downloads Old`.
    private func folder(for path: String, among watched: [WatchedFolder]) -> WatchedFolder? {
        let candidates = watched.filter { path.hasPrefix($0.path + "/") }
        guard let folder = candidates.max(by: { $0.path.count < $1.path.count })
        else { return nil }
        let below = path.dropFirst(folder.path.count + 1).filter { $0 == "/" }.count
        return below < folder.depth ? folder : nil
    }

    // MARK: - Transport

    private struct FolderPayload: Codable { let id: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "folders":
                return (try? JSONEncoder().encode(self.folders)) ?? Data()
            case "history":
                return (try? JSONEncoder().encode(self.history)) ?? Data()
            case "clearHistory":
                self.clearHistory()
                return Data()
            case "setFolders":
                guard let list = try? JSONDecoder().decode([WatchedFolder].self,
                                                           from: command.payload)
                else { return Data() }
                self.folders = list
                return Data()
            case "preview":
                guard let payload = try? JSONDecoder().decode(FolderPayload.self,
                                                              from: command.payload),
                      let folder = self.folders.first(where: { $0.id == payload.id })
                else { return Data() }
                // The plans carry a rule each; the page needs the file and what
                // will happen to it, which is what `PreviewRow` is.
                let rows = await self.offQueue { self.preview(folder).map(PreviewRow.init) }
                return (try? JSONEncoder().encode(rows)) ?? Data()
            case "previewDraft":
                // The folder arrives as a draft rather than by id: a rule being
                // written has not been saved, and a preview of the saved
                // version would answer a question nobody asked.
                guard let draft = try? JSONDecoder().decode(WatchedFolder.self,
                                                            from: command.payload)
                else { return Data() }
                // Runs on every keystroke in the rule editor.
                let rows = await self.offQueue { self.preview(draft).map(PreviewRow.init) }
                return (try? JSONEncoder().encode(rows)) ?? Data()
            case "runNow":
                guard let payload = try? JSONDecoder().decode(FolderPayload.self,
                                                              from: command.payload),
                      let folder = self.folders.first(where: { $0.id == payload.id })
                else { return Data() }
                // A walk plus N moves, off the cooperative pool — and serialised
                // with the hourly sweep, which is reachable at the same moment.
                let report = await self.offQueue { self.sweep(folder) }
                return (try? JSONEncoder().encode(report)) ?? Data()
            default:
                return Data()
            }
        }
    }
}

/// One line of a dry run: the file, and the one thing that would happen to it.
public struct PreviewRow: Codable, Equatable, Identifiable, Sendable {
    /// The path, not the name. `ForEach` draws one row per identity, and two
    /// files called `report.pdf` in two folders were two plans and one row — so
    /// the screen a person reads before letting a rule loose hid a file the
    /// rule was about to touch. Ordinary at any depth above one.
    public var id: String { path }
    /// Shown as the name; carried as the path for exactly the reason above.
    public var name: String { (path as NSString).lastPathComponent }
    public let path: String
    public let ruleName: String
    public let action: RuleAction
    /// Where it lands, when the action has a where. The preview named the
    /// action — "sort into subfolders by kind" — and left the person to work
    /// out which subfolder, which is the only part they could not have known
    /// from the rule they had just written.
    ///
    /// The folder, not the final filename: a name already taken gets numbered
    /// at the moment of the move, and touching the disk to find out on every
    /// keystroke of the editor is not worth knowing it a second early.
    public let destination: String?

    public init(_ plan: RulePlan) {
        path = plan.facts.path
        ruleName = plan.rule.name
        action = plan.action
        destination = PlannedDestination.describe(plan)
    }
}
