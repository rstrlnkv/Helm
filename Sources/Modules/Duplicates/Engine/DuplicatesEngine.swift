import Foundation
import HelmContract
import HelmRuntime

/// The duplicate finder, as a module of its own.
///
/// It began inside Disk, sharing that module's scan and its basket, because
/// the folder it searched was whatever the ring was showing. That coupling was
/// the feature's whole shape: you could not look for duplicates anywhere you
/// had not first drawn a ring. Standing on its own, it takes a folder
/// directly — which is what someone looking for duplicates actually wants —
/// and Disk goes back to answering one question.
public final class DuplicatesEngine: ModuleEngine, BackgroundScanning, @unchecked Sendable {
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    private let finderBox = FinderBox()
    /// Where the person last pointed the search. Held here, not only in the view
    /// model, because a background scan has no view model behind it — nobody is
    /// looking at the page when the timer comes round.
    ///
    /// Optional so every existing caller and test keeps its zero-argument
    /// initializer; without a store there is simply no background scan.
    private let store: NamespacedStore?

    public init(transport: LocalTransport = LocalTransport(),
                store: NamespacedStore? = nil) {
        self.localTransport = transport
        self.transport = transport
        self.store = store
        wireTransport()
    }

    public func activate() {}
    public func deactivate() { finderBox.current?.cancel() }

    /// Synchronous work on the module's own queue; nil when cancelled, because
    /// a partial answer to "what is duplicated" is a wrong answer rather than
    /// a smaller right one.
    public func find(under path: String) async -> [DuplicateGroup]? {
        // A new search supersedes any still running.
        finderBox.current?.cancel()
        let finder = DuplicateScanner()
        let slot = finderBox.start(finder)
        defer { slot.finish() }
        let groups: [DuplicateGroup]? = await offTheCooperativePool {
            finder.find(under: path, onProgress: { progress in
                if let data = try? JSONEncoder().encode(progress) {
                    self.localTransport.emit(EngineEvent(name: "progress", payload: data))
                }
            })
        }
        return groups
    }

    /// The search, with digests carried over from the last one.
    private func findCaching(under path: String, cache: HashCache) async -> [DuplicateGroup]? {
        finderBox.current?.cancel()
        let finder = DuplicateScanner()
        let slot = finderBox.start(finder)
        defer { slot.finish() }
        return await offTheCooperativePool { finder.find(under: path, cache: cache) }
    }

    /// Beside the journal, and private for the same reason: the keys name
    /// nothing but inodes, yet the file is a record of what was on this disk.
    static func cacheURL() -> URL {
        ScanJournal().directory(module: "duplicates")
            .appendingPathComponent("hashes.json")
    }

    static func loadCache() -> HashCache? {
        guard let data = try? Data(contentsOf: cacheURL()) else { return nil }
        return try? JSONDecoder().decode(HashCache.self, from: data)
    }

    static func saveCache(_ cache: HashCache) {
        let url = cacheURL()
        PrivateFile.directory(at: url.deletingLastPathComponent())
        PrivateFile.write(cache, to: url)
    }

    /// The same search the page runs, started by the timer instead of a person.
    ///
    /// **Nil rather than an empty report** whenever it cannot answer honestly: a
    /// refused root, or a walk that was cancelled. An empty report means "we
    /// looked and there was nothing", and a coordinator that could not tell the
    /// two apart would record «проверено, чисто» about a folder nobody read.
    ///
    /// **The stored root is re-checked here.** An interactive scan has the
    /// person's own open panel behind it; this one has a plist entry that any
    /// process running as this user can rewrite, so it goes through `ScanRoot` —
    /// the gate that exists for precisely this difference.
    public func backgroundScan() async -> ScanReport? {
        // The walk uses what the gate returned, never what was stored. Judging
        // one spelling and walking another is how `$HOME/link/.` got past a
        // check that had already approved a different path.
        guard let stored = store?.string("folder", default: ""), !stored.isEmpty else {
            HelmLog.shared.info("scan", "duplicates: no folder chosen yet")
            return nil
        }
        guard let root = ScanRoot.resolve(stored) else {
            HelmLog.shared.warn("scan", "duplicates: stored root refused")
            return nil
        }
        // The cache from the last background scan, filled by this one. An
        // interactive search passes none: a person watching a progress bar has
        // already accepted the wait, and the pay-off is on the run nobody sees.
        let cache = Self.loadCache() ?? HashCache()
        guard let groups = await findCaching(under: root, cache: cache) else { return nil }
        // Compacted on the way out, never on the way in: a scan cut short would
        // otherwise replace the settled segment with a fresh one holding only
        // the files it reached before it stopped.
        Self.saveCache(cache.compactedIfStale())
        // Every copy but the survivor: that is what acting on the finding would
        // remove. The bytes come from `wasted` rather than from adding the sizes
        // up, because on APFS a clone shares its blocks and removing it returns
        // nothing — the same arithmetic the page shows.
        let items = groups.flatMap { group in
            group.copies.dropFirst().map { ScanItem(path: $0.path, bytes: $0.bytes) }
        }
        return ScanReport(bytes: groups.reduce(0) { $0 + $1.wasted },
                          count: items.count, items: items)
    }

    /// The engine has the last word on deletion, as everywhere else in Helm:
    /// the view model builds the list, and this decides what may go.
    /// Refusals come back in `failed`, never dropped.
    public func trash(_ paths: [String]) async -> DuplicateRemoval {
        await offTheCooperativePool {
            let unique = Array(Set(paths))
            let (allowed, refused) = UserFileScope.partition(unique)
            return HelmTrash.remove(allowed: allowed, outOfScope: refused, module: "duplicates")
        }
    }

    /// The same removal, with each copy named beside the one it duplicates.
    ///
    /// **Every pair is read again here**, immediately before anything moves.
    /// The offer on screen is always older than the press that acts on it —
    /// minutes when a person ran the search, a day when the timer did, longer
    /// still once a cached digest stands in for a file. A pair that stopped
    /// matching is refused with `changedSinceScan` and nothing is attempted;
    /// `DuplicateVerification` says why it can stop matching.
    ///
    /// The scope gate still runs, and first: what may be deleted at all is a
    /// different question from whether this particular deletion still makes
    /// sense, and the engine has the last word on both.
    public func trash(_ plans: [DuplicatePlan]) async -> DuplicateRemoval {
        await offTheCooperativePool {
            var byPath: [String: DuplicatePlan] = [:]
            for plan in plans { byPath[plan.remove] = plan }
            let (inScope, outOfScope) = UserFileScope.partition(Array(byPath.keys))

            var allowed: [String] = []
            var stale: [String] = []
            for path in inScope {
                guard let plan = byPath[path] else { continue }
                switch DuplicateVerification.verify(remove: path, keep: plan.keep) {
                case .identical: allowed.append(path)
                case .changed, .unreadable: stale.append(path)
                }
            }
            if !stale.isEmpty {
                HelmLog.shared.info("duplicates",
                                    "refused \(stale.count) — changed since the scan")
            }
            let result = HelmTrash.remove(allowed: allowed, outOfScope: outOfScope,
                                          module: "duplicates")
            // A new value rather than a mutation: `Result` is immutable on
            // purpose, so a refusal cannot be quietly dropped from one after the
            // fact. The stale ones join the scope refusals, and none of them is
            // ever silently discarded — the house rule this module answers to.
            return HelmTrash.Result(
                removed: result.removed,
                refused: result.refused + stale.map {
                    HelmTrash.Refusal(path: $0, reason: .changedSinceScan)
                },
                freedBytes: result.freedBytes)
        }
    }


    // MARK: - Transport

    private struct PathPayload: Codable { let path: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "find":
                guard let payload = try? JSONDecoder().decode(PathPayload.self,
                                                              from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.find(under: payload.path))) ?? Data()
            case ScanCommand.backgroundScan:
                return (try? JSONEncoder().encode(await self.backgroundScan())) ?? Data()
            case "cancel":
                self.finderBox.current?.cancel()
                return Data()
            case "trash":
                // Plans, not paths. The old shape cannot be verified — the
                // engine would be trusting the very reading it is meant to
                // re-check — so there is no fallback to it: a caller sending
                // bare paths gets nothing removed rather than something removed
                // unchecked.
                guard let plans = try? JSONDecoder().decode([DuplicatePlan].self,
                                                            from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.trash(plans))) ?? Data()
            default:
                return Data()
            }
        }
    }
}

/// What the trash command answers with — the same value `DiskRemoval` names,
/// and for the same reason. Its doc comment used to point at `DiskRemoval` for
/// the explanation of a field, which is a type citing its own duplicate.
public typealias DuplicateRemoval = HelmTrash.Result

/// One removal, with the copy it duplicates named beside it.
///
/// The old command took bare paths, which is all the engine needed while it
/// trusted the search that produced them. It cannot verify a pair it was never
/// told about, so the survivor travels with the file — the view model has both,
/// since a `DuplicateGroup` is exactly that pairing.
public struct DuplicatePlan: Codable, Equatable, Sendable {
    /// The copy going to the Trash.
    public let remove: String
    /// The copy that stays, and the thing `remove` has to still be identical to.
    public let keep: String

    public init(remove: String, keep: String) {
        self.remove = remove
        self.keep = keep
    }
}

/// Serial box around the in-flight search, so cancel can reach it.
///
/// A search leaving clears the slot it was given and no other. It used to clear
/// the box outright: a superseded search returning — cancelled, and after its
/// replacement had already started — emptied the box behind the search that had
/// taken its place, and from then on Stop reached nothing and `deactivate()`
/// left the hashing running.
final class FinderBox: @unchecked Sendable {
    /// A serial queue rather than a lock: the callers are async, and an NSLock
    /// cannot be taken across a suspension point.
    private let queue = DispatchQueue(label: "helm.duplicates.finder")
    private var finder: DuplicateScanner?
    private var token = 0

    /// The right to clear one slot, spent once.
    struct Slot {
        fileprivate let token: Int
        fileprivate let box: FinderBox
        func finish() { box.finish(token) }
    }

    var current: DuplicateScanner? { queue.sync { finder } }

    func start(_ value: DuplicateScanner) -> Slot {
        let mine = queue.sync { () -> Int in
            token += 1
            finder = value
            return token
        }
        return Slot(token: mine, box: self)
    }

    private func finish(_ owner: Int) {
        queue.sync { if owner == token { finder = nil } }
    }
}
