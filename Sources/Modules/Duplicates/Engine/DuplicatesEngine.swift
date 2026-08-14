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
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk in shapes nothing would flag if they disagreed: the
    /// `module.duplicates.*` keys of a store, the directory `ScanJournal` names after
    /// it, and the removal attributed to it in the log. `DuplicatesDescriptor.id`
    /// is built from this rather than repeating it, the direction the
    /// descriptors already carry their command enums, so the two spellings are
    /// one. **The string itself never changes** — it names folders and stored
    /// settings that are already on people's machines.
    public static let moduleID = "duplicates"

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

    /// - Parameter settings: how a stored setting is judged to be Helm's own.
    ///   Injectable for the same reason every other port here is: the production
    ///   answer is the login keychain, and a test must not write to the user's.
    /// - Parameter trashing: the move itself, the parameter `HelmTrash.remove`
    ///   already takes and for the same reason. What this engine reports as
    ///   freed is arithmetic over a *clone family*, and the only fixture that can
    ///   exercise it is a real `clonefile` pair — so the test that proves the
    ///   figure must be able to run without moving anybody's file to the Trash.
    public init(transport: LocalTransport = LocalTransport(),
                store: NamespacedStore? = nil,
                settings: SettingGuard = DuplicatesSettings.guardOfFolder,
                trashing: @escaping @Sendable (URL) throws -> Void = {
                    try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
                }) {
        self.localTransport = transport
        self.transport = transport
        self.store = store
        self.settings = settings
        self.trashing = trashing
        wireTransport()
    }

    private let settings: SettingGuard
    private let trashing: @Sendable (URL) throws -> Void

    public func activate() {}
    public func deactivate() { finderBox.current?.cancel() }

    /// The one place a search is started.
    ///
    /// Synchronous work on the module's own queue; nil when cancelled, because
    /// a partial answer to "what is duplicated" is a wrong answer rather than a
    /// smaller right one.
    ///
    /// **Written twice until now** — once for the page and once for the timer —
    /// differing only in whether progress is reported and whether digests are
    /// carried over. What the two copies shared was the box dance, and that is
    /// the part that must not drift: `FinderBox`'s own comment records what a
    /// slot cleared by the wrong search cost, which was a Stop button that
    /// reached nothing and a `deactivate()` that left the hashing running.
    ///
    /// **What it could not look at travels with what it found.** The two counts
    /// are read off the scanner the moment its walk returns, here, where the
    /// instance that did the walking is still in hand — a hole nobody is told
    /// about reads as a clean folder, which was this module's whole answer in the
    /// case where it is most likely to be wrong.
    private func run(under path: String, cache: HashCache?,
                     onProgress: (@Sendable (DuplicateProgress) -> Void)?)
    async -> DuplicateFindings? {
        // A new search supersedes any still running.
        finderBox.current?.cancel()
        let finder = DuplicateScanner()
        let slot = finderBox.start(finder)
        defer { slot.finish() }
        return await offTheCooperativePool {
            guard let groups = finder.find(under: path, cache: cache,
                                           onProgress: onProgress) else { return nil }
            return DuplicateFindings(
                groups: groups,
                // One number, because one sentence: a directory the walk was
                // refused and a file whose digest failed are both "this scan did
                // not compare that", and the person can do the same thing about
                // either.
                unreadable: finder.unreadablePaths + finder.unreadableFiles,
                librariesSkipped: finder.librariesSkipped)
        }
    }

    /// The search a person is watching: no cache — they have already accepted
    /// the wait — and every tick of progress crosses the transport.
    public func find(under path: String) async -> DuplicateFindings? {
        await run(under: path, cache: nil, onProgress: { progress in
            self.localTransport.emit(DuplicatesEvent.progress, encoding: progress)
        })
    }

    /// Beside the journal, and private for the same reason: the keys name
    /// nothing but inodes, yet the file is a record of what was on this disk.
    static func cacheURL() -> URL {
        ScanJournal().directory(module: moduleID)
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
        // **The stored root is not evidence of anything on its own.** It is a
        // plain string in a plist any process running as this user can rewrite,
        // and here it decides how far a reader reaches with nobody at the desk.
        // `ScanRoot` below bounds where it may point; this says whether Helm is
        // the one who put it there.
        let mac = store?.string(SettingGuard.macKey(for: "folder"), default: "")
        switch settings.verdict(payload: Data(stored.utf8), mac: mac) {
        case .sealed:
            break
        case .adopt:
            // Chosen before sealing existed, on an installation that has never
            // sealed anything. Accepted once and sealed, the same trust-on-first
            // -use Autopilot's rules take.
            store?.set(settings.seal(Data(stored.utf8)) ?? "",
                       for: SettingGuard.macKey(for: "folder"))
        case .broken:
            HelmLog.shared.warn("scan", "duplicates: the stored folder is not Helm's own; "
                                + "choose it again to scan in the background")
            return nil
        }
        guard let root = ScanRoot.resolve(stored) else {
            HelmLog.shared.warn("scan", "duplicates: stored root refused")
            return nil
        }
        // The cache from the last background scan, filled by this one. An
        // interactive search passes none: a person watching a progress bar has
        // already accepted the wait, and the pay-off is on the run nobody sees.
        // No progress: nobody is watching, so every tick would cross the
        // transport to a view model that may not exist.
        let cache = Self.loadCache() ?? HashCache()
        guard let found = await run(under: root, cache: cache, onProgress: nil) else { return nil }
        let groups = found.groups
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
    ///
    /// **There was a `trash(_ paths: [String])` beside this**, and it was worse
    /// than dead. Nothing called it — the transport sends plans, the view model
    /// builds plans, and its three remaining callers in the tests were passing
    /// `[DuplicatePlan]` and resolving to this overload. What it was, was a
    /// public entrance that deleted on the strength of the scan alone: the
    /// comment on `.trash` below says a caller sending bare paths must get
    /// nothing removed rather than something removed unchecked, and this method
    /// was exactly the bare-paths caller's way in.
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
        let trashing = self.trashing
        return await offTheCooperativePool {
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
            // The copies that stay, named for the batch's clone accounting: a
            // marked copy that shares its blocks with its survivor gives the disk
            // nothing back, and it is this module — where the survivor is never in
            // the batch — that the seed exists for.
            let result = HelmTrash.remove(allowed: allowed, outOfScope: outOfScope,
                                          sharedWith: Array(Set(plans.map(\.keep))),
                                          module: Self.moduleID, trashing: trashing)
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

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            // A name this engine does not know is a refusal here, once, rather
            // than a `default` at the bottom of a switch nobody re-reads.
            guard let name = DuplicatesCommand(rawValue: command.name) else { return Data() }
            switch name {
            case .find:
                guard let payload = EngineReply.decode(DuplicateSearchRequest.self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.find(under: payload.path), for: command)
            case .backgroundScan:
                return EngineReply.encode(await self.backgroundScan(), for: command)
            case .cancel:
                self.finderBox.current?.cancel()
                return Data()
            case .trash:
                // Plans, not paths. The old shape cannot be verified — the
                // engine would be trusting the very reading it is meant to
                // re-check — so there is no fallback to it: a caller sending
                // bare paths gets nothing removed rather than something removed
                // unchecked.
                guard let plans = EngineReply.decode([DuplicatePlan].self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.trash(plans), for: command)
            }
        }
    }
}

/// What a search answers with: the groups, and what the walk could not look at.
///
/// **A bare array had nowhere to put the second half.** The scanner counts the
/// directories it was refused, the files whose digest it could not take and the
/// application libraries it declined to enter, and all three ended in the log —
/// so the page drew «Every large file under this folder is one of a kind» over a
/// tree that had been refused at every door. `DuplicatesEmpty` is the rule that
/// reads these; this is how they cross the wire.
///
/// The counts and not the paths: whose folder was in the way is nobody's
/// business but the reader's, and a count is what the sentence needs.
public struct DuplicateFindings: Codable, Equatable, Sendable {
    public let groups: [DuplicateGroup]
    /// Directories the walk was refused, plus files whose digest could not be
    /// taken.
    public let unreadable: Int
    /// Application libraries stepped over rather than opened.
    public let librariesSkipped: Int

    public init(groups: [DuplicateGroup], unreadable: Int = 0, librariesSkipped: Int = 0) {
        self.groups = groups
        self.unreadable = unreadable
        self.librariesSkipped = librariesSkipped
    }

    /// **Hand-written, because a synthesised `Decodable` requires every key.**
    /// A reply from a build without the two counts would throw, and
    /// `JSONDecoder` gives up on the whole document rather than on the field —
    /// so a page would read a lost search where there was a perfectly good list
    /// (CLAUDE.md § A `defaulted` property on a `Codable` payload).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([DuplicateGroup].self, forKey: .groups)
        unreadable = try container.decodeIfPresent(Int.self, forKey: .unreadable) ?? 0
        librariesSkipped = try container.decodeIfPresent(Int.self,
                                                         forKey: .librariesSkipped) ?? 0
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
