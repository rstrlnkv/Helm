import Foundation
import HelmRuntime
import os

/// Turns a directory tree into the tree this module draws.
///
/// The walking itself is `BulkWalk`'s: one `getattrlistbulk` per directory
/// across a small pool of threads. This file holds what is Disk's own: the
/// tree, the fold threshold, and the directories this module refuses.
final class DiskScanner: @unchecked Sendable {
    private let foldThreshold: Int
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    /// `skip` is injected only by tests; production reads the live firmlink
    /// table for the scan root.
    private let injectedSkip: Set<String>?

    /// Stop at an application's own database rather than walking into it.
    ///
    /// Off for a scan a person asked for and is watching: this screen's job is
    /// where the space went, and a photo library is often the largest thing on
    /// the volume. On for a scan nobody is watching, where walking in costs a
    /// consent dialog at an empty chair (`ScanRoot.refusesDescent`).
    private let unattended: Bool

    init(foldThreshold: Int = 32 * 1024, skip: Set<String>? = nil,
         unattended: Bool = false) {
        self.foldThreshold = foldThreshold
        self.injectedSkip = skip
        self.unattended = unattended
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    private var isCancelled: Bool { cancelled.withLock { $0 } }

    /// Synchronous; run it via `offTheCooperativePool`.
    ///
    /// Tree building stays on THIS thread, consuming `BulkWalk`'s batches as
    /// they land, so TreeBuilder needs no locking; and because the tree exists
    /// while the walk runs, `onPartial` can hand the UI snapshots for a ring
    /// that grows live.
    func scan(root: String,
              onProgress: (@Sendable (ScanTick) -> Void)? = nil,
              onPartial: (@Sendable (DiskNode) -> Void)? = nil) -> DiskNode? {
        let builder = TreeBuilder(root: root, foldThreshold: foldThreshold)
        let rootDevice = BulkWalk.deviceID(of: root)
        // The Data volume is reachable both directly and through the firmlinks
        // that make up `/`; its duplicate side is skipped so bytes land where
        // the user expects them (FirmlinkMap has the why).
        let skip = injectedSkip ?? FirmlinkMap.skipSet(scanRoot: root)
        var filesSeen = 0
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
                }
                let now = Date()
                if now.timeIntervalSince(lastEmit) > BulkWalk.progressInterval {
                    lastEmit = now
                    onProgress?(ScanTick(files: filesSeen))
                    // The builder thread owns the tree, so snapshotting here
                    // races with nothing.
                    onPartial?(builder.build())
                }
            })

        guard completed else { return nil }
        onProgress?(ScanTick(files: filesSeen))
        return builder.build()
    }
}
