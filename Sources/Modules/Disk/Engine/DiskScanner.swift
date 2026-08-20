import Foundation
import HelmRuntime

struct ScanProgress: Sendable {
    let filesSeen: Int
    let bytesSeen: Int
    let currentPath: String
}

/// Turns a directory tree into the tree this module draws.
///
/// The walking itself is `BulkWalk`'s — one `getattrlistbulk` per directory
/// across a small pool of threads, which is why MacDirStat-style scanners
/// outrun FileManager by an order of magnitude. It lived here until the two
/// other modules that walk a tree were still doing it the slow way; what is
/// left in this file is Disk's own: the tree, the fold threshold, and the
/// directories this module refuses.
final class DiskScanner: @unchecked Sendable {
    private let foldThreshold: Int
    private var cancelled = false
    private let lock = NSLock()

    /// `skip` is injected only by tests; production reads the live firmlink
    /// table for the scan root.
    private let injectedSkip: Set<String>?

    /// Stop at an application's own database rather than walking into it.
    ///
    /// Off for a scan a person asked for and is watching: this screen's whole
    /// job is where the space went, and a photo library is often the largest
    /// thing on the volume — refusing to measure it would be a lie of omission
    /// in the one place that must not tell one. On for a scan nobody is
    /// watching, where the cost of walking in is a consent dialog at an empty
    /// chair (`ScanRoot.refusesDescent`).
    private let unattended: Bool

    init(foldThreshold: Int = 32 * 1024, skip: Set<String>? = nil,
         unattended: Bool = false) {
        self.foldThreshold = foldThreshold
        self.injectedSkip = skip
        self.unattended = unattended
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Synchronous; run it via the module's `blocking` bridge.
    ///
    /// Directories are walked by `BulkWalk` — a small pool of threads and one
    /// `getattrlistbulk` per directory, which is what makes this an order of
    /// magnitude faster than a `FileManager` enumeration (a single-threaded walk
    /// measured 4,7k files/s: 63 s on a real home directory). Tree building
    /// stays on THIS thread, consuming worker batches as they land, so
    /// TreeBuilder needs no locking — and because the tree exists while the walk
    /// runs, `onPartial` can hand the UI snapshots for a ring that grows live
    /// instead of a spinner.
    ///
    /// The walk itself lives in `HelmRuntime` now, because `FileWeight` and the
    /// duplicate finder ask the same question and used to ask it the slow way.
    /// What stays here is everything that is Disk's: the tree, the folding
    /// threshold, and which directories this module refuses.
    func scan(root: String,
              onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
              onPartial: (@Sendable (DiskNode) -> Void)? = nil) -> DiskNode? {
        let builder = TreeBuilder(root: root, foldThreshold: foldThreshold)
        let rootDevice = BulkWalk.deviceID(of: root)
        // The Data volume is reachable both directly and through the firmlinks
        // that make up `/`; its duplicate side is skipped so bytes land where
        // the user expects them (FirmlinkMap has the why).
        let skip = injectedSkip ?? FirmlinkMap.skipSet(scanRoot: root)
        var filesSeen = 0
        var bytesSeen = 0
        var lastPath = root
        var lastEmit = Date()

        let completed = BulkWalk.walk(
            root: root,
            isCancelled: { self.isCancelled },
            descends: { entry in
                // Before the device check, because that one stats the path and
                // the point is to touch an application's database as little as
                // reading its parent already did.
                if self.unattended, ScanRoot.refusesDescent(into: entry.path) { return false }
                guard !skip.contains(entry.path) else { return false }
                // A `stat` per directory, and `BulkWalk.deviceID` says why the
                // walk cannot answer this itself: a bulk read describes a
                // directory as its *parent's* filesystem holds it, so a mount
                // point reports the volume it is mounted on.
                return BulkWalk.deviceID(of: entry.path).matches(rootDevice)
            },
            consume: { batch in
                for path in batch.denied { builder.markNoAccess(path: path) }
                for entry in batch.files {
                    builder.addFile(path: entry.path, bytes: entry.allocatedBytes,
                                    fileID: entry.fileID, modified: entry.modified)
                    filesSeen += 1
                    bytesSeen += entry.allocatedBytes
                    lastPath = entry.path
                }
                let now = Date()
                if now.timeIntervalSince(lastEmit) > 0.35 {
                    lastEmit = now
                    onProgress?(ScanProgress(filesSeen: filesSeen, bytesSeen: bytesSeen,
                                             currentPath: lastPath))
                    // The builder thread owns the tree, so snapshotting here
                    // races with nothing.
                    onPartial?(builder.build())
                }
            })

        guard completed else { return nil }
        onProgress?(ScanProgress(filesSeen: filesSeen, bytesSeen: bytesSeen, currentPath: root))
        return builder.build()
    }
}
