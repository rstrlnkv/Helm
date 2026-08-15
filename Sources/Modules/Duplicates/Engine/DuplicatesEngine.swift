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
    public convenience init(transport: LocalTransport = LocalTransport(),
                            store: NamespacedStore? = nil,
                            settings: SettingGuard = DuplicatesSettings.guardOfScanSettings,
                            trashing: @escaping @Sendable (URL) throws -> Void = {
                                try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
                            }) {
        // One fresh `Batch` per removal: the factory runs at the top of every
        // `trash` call, so the survivor memo lives exactly as long as the press
        // that made it.
        self.init(transport: transport, store: store, settings: settings,
                  trashing: trashing, verifying: {
                      let batch = DuplicateVerification.Batch()
                      return { batch.verify(remove: $0, keep: $1) }
                  })
    }

    /// One pair's verdict, as `trash` asks for it.
    typealias PairCheck = @Sendable (_ remove: String, _ keep: String)
        -> DuplicateVerification.Verdict

    /// - Parameter verifying: builds the pair check one removal uses — a port
    ///   for the same reason `trashing` is one, and internal because the only
    ///   caller that names it is a test: verification reads real minutes off a
    ///   real disk, and a check that answers on the spot is over before Stop
    ///   can be pressed, so the tests about "while it runs" need one that can
    ///   be mid-read.
    init(transport: LocalTransport = LocalTransport(),
         store: NamespacedStore? = nil,
         settings: SettingGuard = DuplicatesSettings.guardOfScanSettings,
         trashing: @escaping @Sendable (URL) throws -> Void,
         verifying: @escaping @Sendable () -> PairCheck) {
        self.localTransport = transport
        self.transport = transport
        self.store = store
        self.settings = settings
        self.trashing = trashing
        self.verifying = verifying
        wireTransport()
    }

    private let settings: SettingGuard
    private let trashing: @Sendable (URL) throws -> Void
    private let verifying: @Sendable () -> PairCheck
    /// The stop flag of the removal in flight, so `stopRemoval` can reach it.
    private let removalBox = InFlightBox<RemovalStop>()

    public func activate() {}
    public func deactivate() {
        finderBox.current?.cancel()
        // The verification stops the same way: nothing has moved yet at that
        // point, and an engine going away must not leave a loop reading files.
        removalBox.current?.stop()
    }

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
    private func run(under path: String, by rule: KeepRule, cache: HashCache?,
                     onProgress: (@Sendable (DuplicateProgress) -> Void)?)
    async -> DuplicateFindings? {
        // A new search supersedes any still running.
        finderBox.current?.cancel()
        let finder = DuplicateScanner()
        let slot = finderBox.start(finder)
        defer { slot.finish() }
        return await offTheCooperativePool {
            guard let groups = finder.find(under: path, by: rule, cache: cache,
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
    ///
    /// The policy is the caller's, because the person at the open page may be
    /// looking at one they have just changed and not yet stored. No default: a
    /// search that quietly keeps `standard` while the page says otherwise is the
    /// two-pipelines defect wearing a parameter list.
    public func find(under path: String, keeping policy: KeepPolicy)
    async -> DuplicateFindings? {
        await run(under: path, by: KeepRule(policy), cache: nil, onProgress: { progress in
            self.localTransport.emit(DuplicatesEvent.progress, encoding: progress)
        })
    }

    /// The policy the module was left set to, judged against its seal.
    ///
    /// The reading itself is `DuplicatesSettings.keepPolicy` and lives there
    /// because the page reads it too — what is in force is one question, and the
    /// screen that shows it and the scan that applies it must not answer it
    /// twice.
    func storedKeepPolicy() -> KeepPolicy {
        DuplicatesSettings.keepPolicy(in: store, guardedBy: settings)
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
        //
        // **The stored root is not evidence of anything on its own.** It is a
        // plain string in a plist any process running as this user can rewrite,
        // and here it decides how far a reader reaches with nobody at the desk.
        // `ScanRoot` below bounds where it may point; the seal says whether Helm
        // is the one who put it there.
        let stored: String
        switch DuplicatesSettings.stored("folder", in: store, guardedBy: settings) {
        case .unset:
            HelmLog.shared.info("scan", "duplicates: no folder chosen yet")
            return nil
        case .notHelmsOwn:
            HelmLog.shared.warn("scan", "duplicates: the stored folder is not Helm's own; "
                                + "choose it again to scan in the background")
            return nil
        case .mine(let folder):
            stored = folder
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
        guard let found = await run(under: root, by: KeepRule(storedKeepPolicy()),
                                    cache: cache, onProgress: nil) else { return nil }
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
        let verify = verifying()
        // The flag lives in the box so `stopRemoval` can reach it, and is this
        // call's own: a stop pressed with nothing running must not cancel the
        // removal after it.
        let stop = RemovalStop()
        let slot = removalBox.start(stop)
        defer { slot.finish() }
        return await offTheCooperativePool {
            var byPath: [String: DuplicatePlan] = [:]
            for plan in plans { byPath[plan.remove] = plan }
            let (inScope, outOfScope) = UserFileScope.partition(Array(byPath.keys))

            var allowed: [String] = []
            var stale: [String] = []
            // Its own phase, beside the `duplicates.trash` one `HelmTrash.remove`
            // opens below: the re-reading is where the minutes go, and it ran
            // namelessly — a spike in the memory trail had no operation named
            // against it.
            let stopped = HelmActivity.phase("duplicates.verify") { () -> Bool in
                // Before the phase ends, as `HelmTrash` takes it: the line names
                // what else runs beside the label it excludes.
                defer { HelmLog.shared.memory("duplicates.verify") }
                for path in inScope {
                    // Between files, never mid-read: a pair that began its
                    // verification finishes it, so a verdict is never partial.
                    if stop.isStopped { return true }
                    guard let plan = byPath[path] else { continue }
                    switch verify(path, plan.keep) {
                    case .identical: allowed.append(path)
                    case .changed, .unreadable: stale.append(path)
                    }
                    // Every tick is a whole file read in full, so the ticks are
                    // already paced by the disk — no throttle needed where the
                    // search needs one per 128 KB prefix.
                    self.localTransport.emit(DuplicatesEvent.progress, encoding:
                        DuplicateProgress(candidates: inScope.count,
                                          hashed: allowed.count + stale.count))
                }
                return stop.isStopped
            }
            if !stale.isEmpty {
                HelmLog.shared.info("duplicates",
                                    "refused \(stale.count) — changed since the scan")
            }
            // Spelled once for both ways out: a reply that dropped these on
            // either path would be a refusal silently discarded.
            let staleRefusals = stale.map {
                HelmTrash.Refusal(path: $0, reason: .changedSinceScan)
            }
            if stopped {
                // A named outcome, not silence — and nothing moves from here:
                // the verified remainder was about to be trashed, and Stop
                // means stop. What was already known stays reported; a refusal
                // is never silently discarded, stopped or not.
                HelmLog.shared.info("duplicates",
                                    "removal stopped — verified \(allowed.count + stale.count)"
                                    + " of \(inScope.count), nothing moved")
                return DuplicateRemoval(
                    removed: [],
                    refused: outOfScope.map {
                        HelmTrash.Refusal(path: $0, reason: .outOfScope)
                    } + staleRefusals,
                    freedBytes: 0, cancelled: true)
            }
            // The copies that stay, named for the batch's clone accounting: a
            // marked copy that shares its blocks with its survivor gives the disk
            // nothing back, and it is this module — where the survivor is never in
            // the batch — that the seed exists for.
            let result = HelmTrash.remove(allowed: allowed, outOfScope: outOfScope,
                                          sharedWith: Array(Set(plans.map(\.keep))),
                                          module: Self.moduleID, trashing: trashing)
            // A new value rather than a mutation: the reply is immutable on
            // purpose, so a refusal cannot be quietly dropped from one after the
            // fact. The stale ones join the scope refusals, and none of them is
            // ever silently discarded — the house rule this module answers to.
            return DuplicateRemoval(
                removed: result.removed,
                refused: result.refused + staleRefusals,
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
                // What the page asked for, and what the module was left set to
                // when it asked for nothing — a payload from before the policy
                // existed carries none, and the stored value is the same one the
                // background scan reads.
                let policy = payload.keepPolicy ?? self.storedKeepPolicy()
                return EngineReply.encode(await self.find(under: payload.path, keeping: policy),
                                          for: command)
            case .backgroundScan:
                return EngineReply.encode(await self.backgroundScan(), for: command)
            case .cancel:
                self.finderBox.current?.cancel()
                return Data()
            case .stopRemoval:
                self.removalBox.current?.stop()
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

/// What the trash command answers with: everything `HelmTrash.Result` says,
/// plus whether the person stopped it first.
///
/// It was a bare typealias of the result until the removal learned to stop.
/// A stopped removal is a fourth outcome — not a success, not a refusal, not
/// silence — and folding it to zeroes drew nothing at all, which reads as
/// «press it again». `cancelled` rides beside the counts rather than replacing
/// them, because a stop can land after some files have already moved and those
/// are still honestly counted; a reply that is both cancelled and lists what
/// went is exactly the state the sentence has to cover.
public struct DuplicateRemoval: Codable, Equatable, Sendable {
    public let removed: [String]
    public let refused: [HelmTrash.Refusal]
    public let freedBytes: Int
    /// The person pressed Stop and the engine obeyed between files. What was
    /// already moved stays moved and is counted above; what was not yet
    /// verified was never attempted.
    public let cancelled: Bool

    public var failed: [String] { refused.map(\.path) }

    public init(removed: [String], refused: [HelmTrash.Refusal],
                freedBytes: Int, cancelled: Bool = false) {
        self.removed = removed
        self.refused = refused
        self.freedBytes = freedBytes
        self.cancelled = cancelled
    }

    /// The engine's own construction: the trash result whole, nothing dropped
    /// on the way through — a refusal is never silently discarded.
    public init(_ result: HelmTrash.Result, cancelled: Bool) {
        self.init(removed: result.removed, refused: result.refused,
                  freedBytes: result.freedBytes, cancelled: cancelled)
    }

    /// **Hand-written, because a synthesised `Decodable` requires every key.**
    /// A reply from before the removal could be stopped carries no `cancelled`,
    /// and `JSONDecoder` gives up on the whole document rather than the one
    /// field (CLAUDE.md § A `defaulted` property on a `Codable` payload).
    /// Missing means «it ran to the end».
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        removed = try container.decode([String].self, forKey: .removed)
        refused = try container.decode([HelmTrash.Refusal].self, forKey: .refused)
        freedBytes = try container.decode(Int.self, forKey: .freedBytes)
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
    }
}

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

/// Serial box around an in-flight job, so cancel can reach it.
///
/// A job leaving clears the slot it was given and no other. The search's box
/// used to clear itself outright: a superseded search returning — cancelled,
/// and after its replacement had already started — emptied the box behind the
/// search that had taken its place, and from then on Stop reached nothing and
/// `deactivate()` left the hashing running. The removal's stop flag sits in
/// the same shape for the same reason, which is why the box is generic rather
/// than written twice.
final class InFlightBox<Job: AnyObject>: @unchecked Sendable {
    /// A serial queue rather than a lock: the callers are async, and an NSLock
    /// cannot be taken across a suspension point.
    private let queue = DispatchQueue(label: "helm.duplicates.inflight")
    private var job: Job?
    private var token = 0

    /// The right to clear one slot, spent once.
    struct Slot {
        fileprivate let token: Int
        fileprivate let box: InFlightBox
        func finish() { box.finish(token) }
    }

    var current: Job? { queue.sync { job } }

    func start(_ value: Job) -> Slot {
        let mine = queue.sync { () -> Int in
            token += 1
            job = value
            return token
        }
        return Slot(token: mine, box: self)
    }

    private func finish(_ owner: Int) {
        queue.sync { if owner == token { job = nil } }
    }
}

/// The slot the running search sits in.
typealias FinderBox = InFlightBox<DuplicateScanner>

/// The one thing a running removal can be told: stop. Checked between files —
/// a file mid-verification finishes its read — and never carried over to the
/// next removal: each `trash` call starts a flag of its own in the box.
final class RemovalStop: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    func stop() { lock.lock(); stopped = true; lock.unlock() }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
