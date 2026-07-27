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
    public func preview(_ folder: WatchedFolder) -> [RulePlan] {
        let files = reader.facts(in: folder.path, depth: folder.depth)
        return RulePlan.decide(files, rules: folder.rules.filter(\.enabled))
    }

    @discardableResult
    public func sweep(_ folder: WatchedFolder) -> SweepReport {
        let files = reader.facts(in: folder.path, depth: folder.depth)
        let plans = RulePlan.decide(files, rules: folder.activeRules)
        var acted = 0, refused = 0, failed = 0
        for plan in plans {
            let path = plan.facts.path
            switch runner.run(plan, at: path) {
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
    private func handle(_ changed: [String]) {
        let watched = folders.filter(\.enabled)
        guard !watched.isEmpty else { return }
        queue.async { [self] in
            for path in Set(changed) {
                guard let folder = self.folder(for: path, among: watched),
                      FileManager.default.fileExists(atPath: path),
                      let facts = reader.facts(of: URL(fileURLWithPath: path)),
                      let plan = RulePlan.decide(facts, rules: folder.activeRules)
                else { continue }
                switch runner.run(plan, at: path) {
                case let .refused(reason):
                    HelmLog.shared.warn("autopilot",
                                        "refused \(Redact.path(path)): \(reason.rawValue)")
                case let .failed(description):
                    HelmLog.shared.warn("autopilot",
                                        "failed \(Redact.path(path)): \(description)")
                default:
                    break
                }
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

    public init(_ plan: RulePlan) {
        name = plan.facts.name
        ruleName = plan.rule.name
        action = plan.action
    }
}
