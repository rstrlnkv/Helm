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

    /// Hourly. The events cover anything that happens; this only exists for
    /// conditions that come true by themselves, which is a scale of hours.
    private static let sweepInterval: TimeInterval = 3600

    /// `home` is `WatchScope`'s reference point, injected so a test can point a
    /// whole engine at a temporary directory without being exempted from the
    /// gate the module's safety rests on.
    public init(store: NamespacedStore, transport: LocalTransport = LocalTransport(),
                home: String = NSHomeDirectory()) {
        self.runner = RuleRunner(home: home)
        self.store = store
        self.localTransport = transport
        self.transport = transport
        wireTransport()
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
            guard let data = store.data("folders"),
                  let list = try? JSONDecoder().decode([WatchedFolder].self, from: data)
            else { return [] }
            return list
        }
        set {
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
                store.set(try JSONEncoder().encode(newValue.map(\.storable)), for: "folders")
                refreshWatch()
            } catch {
                HelmLog.shared.failure("autopilot", "could not save \(newValue.count) folders",
                                       error)
            }
        }
    }

    private func refreshWatch() {
        let paths = folders.filter(\.enabled).map(\.path)
        queue.async { [self] in watcher?.watch(paths) }
    }

    private func startSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.sweepInterval, repeating: Self.sweepInterval)
        timer.setEventHandler { [weak self] in _ = self?.sweepAll() }
        timer.resume()
        sweepTimer = timer
    }

    // MARK: - Running

    /// What a folder's rules would do to what is in it right now.
    ///
    /// The same value the runner executes, so what someone was shown on the dry
    /// run and what happens afterwards cannot drift apart.
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
    public var id: String { name }
    public let name: String
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
        name = plan.facts.name
        ruleName = plan.rule.name
        action = plan.action
        destination = PlannedDestination.describe(plan)
    }
}
