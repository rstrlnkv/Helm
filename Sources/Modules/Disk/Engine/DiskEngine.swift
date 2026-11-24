import Foundation
import HelmContract
import HelmRuntime
import os

/// Scans volumes and folders, and trashes what the user baskets. Long work
/// goes through `offTheCooperativePool` so the concurrency pool is never parked.
public final class DiskEngine: ModuleEngine, BackgroundScanning, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk as the `module.disk.*` keys of a store, the directory
    /// `ScanJournal` names after it, and the removal attributed to it in the
    /// log; `DiskDescriptor.id` is built from this. **The string never
    /// changes**: it names folders and settings already on people's machines.
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

    /// The volume list's reverse channel, answered by the capacity port.
    public func watchMounts(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        capacity.observeChanges(onChange)
    }

    /// The boot volume, walked by the timer instead of by a person.
    ///
    /// **The finding is the advice, not the tree.** A disk scan is a picture of
    /// what occupies space, not a list of things to remove; `advice` is the
    /// part that names specific paths worth reclaiming.
    ///
    /// **And the advice is filtered before it is written down.** The walk enters
    /// `~/Library` on purpose and the 0600 journal may not name what is in
    /// there: `UnattendedAdvice.report` is that gate, and says why it is the
    /// report's rather than the descent's.
    ///
    /// **No `ScanRoot` gate**: that gate guards a folder the person chose and
    /// Helm stored, where a rewritten plist would redirect an unattended reader.
    /// The root here is the boot volume, named in this line.
    public func backgroundScan() async -> ScanReport? {
        guard let result = await scan(path: "/", unattended: true) else { return nil }
        // The walk measured `~/Library` and the journal may not record what it
        // found there (`UnattendedAdvice`).
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
        // Registered for the whole scan, cancellation included. `begin` +
        // `defer` rather than `HelmActivity.phase`, whose closure would wrap
        // the `await` below; the `defer` makes it a scope.
        HelmActivity.begin("disk.scan")
        defer { HelmActivity.end("disk.scan") }
        let started = Date()

        let counter = OSAllocatedUnfairLock(initialState: 0)
        let freeNow = freeBytes(forPathOn: path)
        var onPartial: (@Sendable (DiskNode) -> Void)?
        if let updates {
            onPartial = { partialTree in
                // A shallow snapshot every `BulkWalk.progressInterval`: the ring grows while the
                // walk is still running.
                let snapshot = ScanResult(root: DiskEntry(partialTree, depth: 4, path: path),
                                          freeBytes: freeNow,
                                          filesScanned: counter.withLock { $0 }, seconds: 0)
                updates(.partial(snapshot))
            }
        }
        let result: ScanResult? = await offTheCooperativePool { [onPartial] in
            // `onProgress` is passed whether or not anyone listens: it is the only
            // writer of `counter`, which `filesScanned` is read from. The snapshot
            // callback is passed only to a caller that wants snapshots, because
            // asking for it makes the scanner build one every `BulkWalk.progressInterval`.
            guard let tree = scanner.scan(root: path, onProgress: { progress in
                counter.withLock { $0 = progress.files }
                updates?(.progress(progress))
            }, onPartial: onPartial) else { return nil }
            let free = self.freeBytes(forPathOn: path)
            return ScanResult(root: DiskEntry(tree, depth: 6, path: path), freeBytes: free,
                              filesScanned: counter.withLock { $0 },
                              seconds: Date().timeIntervalSince(started),
                              advice: DiskAdvisor.advise(root: tree, rootPath: path,
                                                         home: NSHomeDirectory()))
        }
        // The reclaim is owed whether the scan finished or was stopped, and Stop
        // is pressed when the footprint is at its highest. Only the sentence
        // about what was found belongs on the success path.
        HelmLog.shared.memory("disk.scan")
        if let result {
            HelmLog.shared.info(Self.moduleID, "scanned \(LogRoot.label(path)): \(result.filesScanned) files in "
                                + String(format: "%.1fs", result.seconds))
        }
        return result
    }

    /// Stops everything walking: every scan in flight, not the one that started
    /// last, so a volume scan can always be stopped.
    public func cancel() { scanners.inFlight.forEach { $0.cancel() } }

    /// Free space of the volume a path lives on — the ring's dim sector, the
    /// same figure `volumes()` reports. Unreadable is 0, which draws no wedge.
    private func freeBytes(forPathOn path: String) -> Int {
        capacity.readout(at: path)?.freeSpace?.bytes ?? 0
    }

    /// **The heaviest removal in the app**: `HelmTrash.remove` weighs every path
    /// in the batch with `FileWeight` before it moves anything, a walk per
    /// folder. The `disk.trash` phase and the memory reading come from that
    /// loop, named `"\(module).trash"` for every deleting module
    /// (`HelmTrashPhaseTests`).
    public func trash(_ paths: [String]) async -> DiskRemoval {
        await offTheCooperativePool {
            // Refused, not dropped: a path the gate rejects goes in the failed
            // list, or the page would announce it freed.
            // `UserFileScope.partition` has the same *shape* as
            // `RemovableScope.partition` and answers a different question:
            // what belongs to the user, not to an application. The two are not
            // interchangeable (Architecture/TheGates.md § The gates).
            let (allowed, refused) = UserFileScope.partition(Array(Set(paths)))
            return HelmTrash.remove(allowed: allowed, outOfScope: refused,
                                    module: Self.moduleID, trashing: self.trashing)
        }
    }
}

public struct ScanTick: Equatable, Sendable {
    public let files: Int

    public init(files: Int) {
        self.files = files
    }
}

/// What a scan says while it runs, to the caller that asked for it.
///
/// Per call rather than per engine: two scans can be walking at once, and each
/// call has its own sink, so no update has to name its scan.
public enum DiskScanUpdate: Sendable {
    /// How far the walk has got: files seen so far.
    case progress(ScanTick)
    /// A tree good enough to draw, before the walk has finished.
    case partial(ScanResult)
}

/// What `trash` answers with. `refused` carries the reason, the part worth
/// reading when Full Disk Access is the cause.
public typealias DiskRemoval = HelmTrash.Result
