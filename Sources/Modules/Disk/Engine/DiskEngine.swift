import Foundation
import HelmContract
import HelmRuntime

/// Scans volumes and folders, and trashes what the user baskets. Long work
/// goes through `offTheCooperativePool` so the concurrency pool is never parked.
public final class DiskEngine: ModuleEngine, BackgroundScanning, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk in shapes nothing would flag if they disagreed: the
    /// `module.disk.*` keys of a store, the directory `ScanJournal` names after
    /// it, and the removal attributed to it in the log. `DiskDescriptor.id`
    /// is built from this rather than repeating it, so the two spellings are
    /// one. **The string itself never changes** — it names folders and stored
    /// settings that are already on people's machines.
    public static let moduleID = "disk"

    /// Every scan in flight, not the last one started: drilling into a folder
    /// the walk never reached starts a second scan beside the first.
    private let scanners = ScanRegistry<DiskScanner>()
    private let capacity: any VolumeCapacityPort

    private let trashing: @Sendable (URL) throws -> Void

    /// - Parameter trashing: the move, `HelmTrash.moveToTrash` in the app. No default: a construction
    ///   that forgot it would move whatever it was handed into the Trash of whoever runs it.
    public init(capacity: any VolumeCapacityPort = SystemVolumeCapacity(),
                trashing: @escaping @Sendable (URL) throws -> Void) {
        self.capacity = capacity
        self.trashing = trashing
    }

    public func activate() {}
    public func deactivate() {
        cancel()
    }

    /// Free space here is what Finder shows — purgeable space counts as free
    /// (`VolumeReadout.freeSpace`), so the tile and the page agree with the
    /// system's own figure rather than reading tens of gigabytes low.
    public func volumes() -> [VolumeInfo] {
        capacity.mounted().compactMap { readout in
            guard readout.isBrowsable, let total = readout.total,
                  let free = readout.freeSpace else { return nil }
            return VolumeInfo(name: readout.name ?? URL(fileURLWithPath: readout.path).lastPathComponent,
                              path: readout.path, totalBytes: total, freeBytes: free.bytes)
        }
    }

    /// The same list off the main actor: the volume attributes of a network mount
    /// nobody holds up any more block for the mount's own timeout, so the model
    /// asks through here and never calls `volumes()` itself.
    public func mountedVolumes() async -> [VolumeInfo] {
        await offTheCooperativePool { self.volumes() }
    }

    /// The boot volume, walked by the timer instead of by a person.
    ///
    /// **The finding is the advice, not the tree.** A disk scan answers "what
    /// occupies space", which is a picture rather than a list of things to
    /// remove — mapping every node of it into a report would promise a decision
    /// the module never made. `advice` is the part that already names specific
    /// paths worth reclaiming: caches past their threshold, big downloads
    /// nobody has touched in a month, huge files untouched for half a year.
    ///
    /// **And the advice is filtered before it is written down.** The walk enters
    /// `~/Library` on purpose and the 0600 journal may not name what is in
    /// there — `UnattendedAdvice.report` is that gate, and it is the report's
    /// rather than the descent's for a reason it carries.
    ///
    /// **No `ScanRoot` gate**, and not by omission. That gate guards a folder
    /// the person chose and Helm stored, where a rewritten plist would redirect
    /// an unattended reader. The root here is the boot volume, named in this
    /// line rather than read from anywhere.
    public func backgroundScan() async -> ScanReport? {
        guard let result = await scan(path: "/", unattended: true) else { return nil }
        // The walk measured `~/Library` — it has to, or «where did the space go»
        // omits the largest folder on the volume — and the journal may not
        // record what it found there. `UnattendedAdvice` has the reasoning.
        return UnattendedAdvice.report(of: result.advice)
    }

    /// - Parameter unattended: nobody is watching, so the walk stops at an
    ///   application's own database instead of asking macOS for permission to
    ///   read it at an empty chair. Defaults to false: a scan a person started
    ///   measures everything, because "where did the space go" must not quietly
    ///   omit the largest folder on the volume.
    /// - Parameter updates: where the walk's progress and its partial snapshots go
    ///   while it runs; nil asks for neither. Called from worker threads. Two scans
    ///   can be walking at once (the volume and the folder a drill measures) and
    ///   each has its own sink, so an update is never another scan's.
    public func scan(path: String, unattended: Bool = false,
                     updates: (@Sendable (DiskScanUpdate) -> Void)? = nil) async -> ScanResult? {
        let scanner = DiskScanner(unattended: unattended)
        let token = scanners.add(scanner)
        defer { scanners.remove(token) }
        // Registered for the whole scan, cancellation included. The pair is
        // `begin` + `defer` rather than `HelmActivity.phase`, because the phase
        // is this whole function body and wrapping it in a closure would put the
        // `await` below inside one; the `defer` is what makes it a scope, and
        // there must never be a `begin` without one.
        HelmActivity.begin("disk.scan")
        defer { HelmActivity.end("disk.scan") }
        let started = Date()

        let counter = FileCounter()
        let freeNow = freeBytes(forPathOn: path)
        var onPartial: (@Sendable (DiskNode) -> Void)?
        if let updates {
            onPartial = { partialTree in
                // A shallow snapshot every ~0.35s: the ring grows while the
                // walk is still running.
                let snapshot = ScanResult(root: DiskEntry(partialTree, depth: 4, path: path),
                                          freeBytes: freeNow,
                                          filesScanned: counter.value, seconds: 0)
                updates(.partial(snapshot))
            }
        }
        let result: ScanResult? = await offTheCooperativePool { [onPartial] in
            // `onProgress` is passed whether or not anyone listens: it is the only
            // writer of `counter`, which `filesScanned` is read from. The snapshot
            // callback is passed only to a caller that wants snapshots, because
            // asking for it makes the scanner build one every ~0.35s.
            guard let tree = scanner.scan(root: path, onProgress: { progress in
                counter.value = progress.filesSeen
                updates?(.progress(ScanTick(files: progress.filesSeen, bytes: progress.bytesSeen,
                                            path: progress.currentPath)))
            }, onPartial: onPartial) else { return nil }
            let free = self.freeBytes(forPathOn: path)
            return ScanResult(root: DiskEntry(tree, depth: 6, path: path), freeBytes: free,
                              filesScanned: counter.value,
                              seconds: Date().timeIntervalSince(started),
                              advice: DiskAdvisor.advise(root: tree, rootPath: path,
                                                         home: NSHomeDirectory()))
        }
        // The reclaim is owed whether the scan finished or was stopped — and Stop
        // is pressed when the footprint is at its highest, because that is why
        // the person pressed it. It used to sit inside `if let result`, so a
        // cancelled walk of a volume handed nothing back to macOS and wrote
        // nothing to the trail. Only the sentence about what was found belongs
        // on the success path.
        HelmLog.shared.memory("disk.scan")
        if let result {
            HelmLog.shared.info(Self.moduleID, "scanned \(LogRoot.label(path)): \(result.filesScanned) files in "
                                + String(format: "%.1fs", result.seconds))
        }
        return result
    }

    /// Stops everything walking. A volume scan the user cannot stop is the
    /// worst of the two mistakes available here, so this asks every scan in
    /// flight rather than the one that started last.
    public func cancel() { scanners.inFlight.forEach { $0.cancel() } }

    /// Free space of the volume a path lives on — the ring's dim sector, the
    /// same figure `volumes()` reports. Unreadable is 0, which draws no wedge.
    private func freeBytes(forPathOn path: String) -> Int {
        capacity.readout(at: path)?.freeSpace?.bytes ?? 0
    }

    /// **The heaviest removal in the app**: `HelmTrash.remove` weighs every path
    /// in the batch with `FileWeight` before it moves anything — a folder, so a
    /// walk each. The `disk.trash` phase and the memory reading come from that
    /// loop now, named `"\(module).trash"` for every deleting module — this
    /// engine wrapped its own call while the other three ran nameless, and Disk
    /// was not the outlier, it was the one that got audited
    /// (`HelmTrashPhaseTests`).
    public func trash(_ paths: [String]) async -> DiskRemoval {
        await offTheCooperativePool {
            // Refused, not dropped. Filtering the loop meant a path the gate
            // rejected reached neither list, and the page then announced
            // "Removed — N freed" over a file still sitting there.
            // `UserFileScope.partition` is written to the same *shape* as
            // `RemovableScope.partition` and answers a different question —
            // what belongs to the user, not what belongs to an application.
            // The two are not interchangeable and the earlier wording here
            // ("one question, two spellings") read as an invitation to merge
            // them: wiring a module to the wrong gate is a real mistake with
            // a misleading symptom, and the duplicate finder shipped one
            // (ARCHITECTURE.md § The gates).
            let (allowed, refused) = UserFileScope.partition(Array(Set(paths)))
            return HelmTrash.remove(allowed: allowed, outOfScope: refused,
                                    module: Self.moduleID, trashing: self.trashing)
        }
    }
}

/// Progress arrives from worker threads; the count needs a home that is safe
/// to write from any of them.
private final class FileCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

public struct ScanTick: Equatable, Sendable {
    public let files: Int
    public let bytes: Int
    public let path: String

    public init(files: Int, bytes: Int, path: String) {
        self.files = files
        self.bytes = bytes
        self.path = path
    }
}

/// What a scan says while it runs, to the caller that asked for it.
///
/// Per call rather than per engine: two scans can be walking at once, and an
/// update that travelled on one shared channel had to name its scan to be told
/// from the other's. Here each call has its own sink, so it cannot be another's.
public enum DiskScanUpdate: Sendable {
    /// How far the walk has got — files seen, bytes so far.
    case progress(ScanTick)
    /// A tree good enough to draw, before the walk has finished.
    case partial(ScanResult)
}

/// What `trash` answers with.
///
/// This was a field-for-field copy of `HelmTrash.Result` — the same three
/// stored properties in the same order, the same `failed`, the same
/// conformances — which the engine built and then unwrapped and re-wrapped for
/// no gain. `refused` still carries the reason, which is the only part worth reading when Full Disk Access is the
/// cause.
public typealias DiskRemoval = HelmTrash.Result
