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
public final class RulesEngine: ModuleEngine, @unchecked Sendable {
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    private let store: NamespacedStore
    private let reader = FolderReader()
    private let runner = RuleRunner()
    private let queue = DispatchQueue(label: "helm.rules", qos: .utility)
    private var watcher: FolderWatcher?
    private var sweepTimer: DispatchSourceTimer?

    /// Hourly. The events cover anything that happens; this only exists for
    /// conditions that come true by themselves, which is a scale of hours.
    private static let sweepInterval: TimeInterval = 3600

    public init(store: NamespacedStore, transport: LocalTransport = LocalTransport()) {
        self.store = store
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {
        watcher = FolderWatcher { [weak self] changed in self?.handle(changed) }
        refreshWatch()
        startSweepTimer()
    }

    public func deactivate() {
        watcher?.stop()
        watcher = nil
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
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            store.set(data, for: "folders")
            refreshWatch()
        }
    }

    private func refreshWatch() {
        watcher?.watch(folders.filter(\.enabled).map(\.path))
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
            let path = (folder.path as NSString).appendingPathComponent(plan.facts.name)
            switch runner.run(plan, at: path) {
            case .moved, .renamed, .tagged, .trashed:
                acted += 1
            case .alreadyDone:
                break
            case let .refused(reason):
                refused += 1
                HelmLog.shared.warn("rules", "refused \(Redact.path(path)): \(reason.rawValue)")
            case let .failed(description):
                failed += 1
                HelmLog.shared.warn("rules", "failed \(Redact.path(path)): \(description)")
            }
        }
        let report = SweepReport(folderID: folder.id, examined: files.count,
                                 acted: acted, refused: refused, failed: failed)
        if acted + refused + failed > 0 {
            HelmLog.shared.info("rules", "swept \(files.count), acted \(acted), " +
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
    private func handle(_ changed: [String]) {
        let watched = folders.filter(\.enabled)
        guard !watched.isEmpty else { return }
        queue.async { [self] in
            for path in Set(changed) {
                let parent = (path as NSString).deletingLastPathComponent
                guard let folder = watched.first(where: { parent.hasPrefix($0.path) }),
                      FileManager.default.fileExists(atPath: path),
                      let facts = reader.facts(of: URL(fileURLWithPath: path)),
                      let plan = RulePlan.decide(facts, rules: folder.activeRules)
                else { continue }
                switch runner.run(plan, at: path) {
                case let .refused(reason):
                    HelmLog.shared.warn("rules",
                                        "refused \(Redact.path(path)): \(reason.rawValue)")
                case let .failed(description):
                    HelmLog.shared.warn("rules",
                                        "failed \(Redact.path(path)): \(description)")
                default:
                    break
                }
            }
        }
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
                let rows = self.preview(folder).map(PreviewRow.init)
                return (try? JSONEncoder().encode(rows)) ?? Data()
            case "previewDraft":
                // The folder arrives as a draft rather than by id: a rule being
                // written has not been saved, and a preview of the saved
                // version would answer a question nobody asked.
                guard let draft = try? JSONDecoder().decode(WatchedFolder.self,
                                                            from: command.payload)
                else { return Data() }
                let rows = self.preview(draft).map(PreviewRow.init)
                return (try? JSONEncoder().encode(rows)) ?? Data()
            case "runNow":
                guard let payload = try? JSONDecoder().decode(FolderPayload.self,
                                                              from: command.payload),
                      let folder = self.folders.first(where: { $0.id == payload.id })
                else { return Data() }
                return (try? JSONEncoder().encode(self.sweep(folder))) ?? Data()
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
