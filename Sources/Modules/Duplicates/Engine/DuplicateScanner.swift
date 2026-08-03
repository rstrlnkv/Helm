import CryptoKit
import Foundation
import HelmRuntime

/// Where the duplicate search stands, for a sheet that shows its work.
public struct DuplicateProgress: Codable, Sendable {
    /// Hash operations this search will perform: two per candidate, a prefix
    /// pass and a full one. Not a file count — the sheet says "checks".
    public let candidates: Int
    /// How many of them have been hashed so far.
    public let hashed: Int
}

/// Finds files with identical content under one folder.
///
/// The decisions live in `Duplicates` (pure, tested); this class supplies the
/// walking and the hashing. Size nominates, a prefix hash thins the field, a
/// full hash decides — so a folder of ten thousand distinct files costs a
/// directory walk and nothing else, and only real candidates are ever read in
/// full.
public final class DuplicateScanner: @unchecked Sendable {
    /// Below this a file is not worth offering: the list would drown in
    /// kilobyte-sized config copies whose deletion frees nothing anyone can
    /// feel.
    public static let minBytes = 1_000_000
    /// Enough of a prefix that two files agreeing on it are usually the same
    /// file; cheap enough that reading it costs one I/O burst.
    private static let prefixBytes = 128 * 1024

    private var cancelled = false
    private let lock = NSLock()
    private var unreadable = 0

    /// Paths the walk was refused — a folder without read permission, an item
    /// that vanished between being listed and being read. A count, not the
    /// paths: the question the log is asked is whether the answer was whole,
    /// not whose folder was in the way.
    public var unreadablePaths: Int {
        lock.lock(); defer { lock.unlock() }
        return unreadable
    }

    private func noteUnreadable() {
        lock.lock(); unreadable += 1; lock.unlock()
    }

    public init() {}

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Synchronous; run it via the module's `blocking` bridge. Returns nil
    /// when cancelled — a partial answer to "what is duplicated" is a wrong
    /// answer, not a smaller right one.
    /// - Parameter cache: digests kept from the last search. Nil means read
    ///   every candidate, which is what an interactive search does today and
    ///   what any search does the first time. When one is supplied it is also
    ///   **filled**: whatever this search reads is written back, so the caller
    ///   can persist it and the next search reads less.
    public func find(under root: String,
                     cache: HashCache? = nil,
                     onProgress: (@Sendable (DuplicateProgress) -> Void)? = nil)
    -> [DuplicateGroup]? {
        let files = HelmActivity.phase("duplicates.walk") {
            walk(root, onProgress: onProgress)
        }
        // Before the cancellation check, not after it. Stop is pressed when the
        // footprint is at its highest — that is why it is pressed — and the
        // reclaim used to sit below this line, so the one run that most needed
        // its memory handed back was the only run that never got it.
        HelmLog.shared.memory("duplicates.walk")
        if isCancelled { return nil }

        // A subtree the walk was refused is a hole in "what is duplicated", and
        // a hole nobody is told about reads as a clean folder.
        let refused = unreadablePaths
        HelmLog.shared.info("duplicates", "walked \(LogRoot.label(root)): "
                            + "\(files.count) files at or above the floor"
                            + (refused > 0 ? ", \(refused) unreadable" : ""))
        let candidates = Duplicates.sizeGroups(files, minBytes: Self.minBytes)
        let total = candidates.reduce(0) { $0 + $1.count }
        // Twice per candidate: the prefix pass, then the full pass for
        // whatever survives it. Counting each candidate once parked the bar at
        // 100% for the entire second pass, which is the longer one.
        let progress = ThrottledProgress(total: total * 2, onProgress: onProgress)

        // Size groups are independent by construction, and hashing is where
        // the minutes go: a real home directory measured 70 GB of worst-case
        // full-hash volume, which single-threaded is the difference between
        // "a moment" and "go make tea". One group per iteration; the buckets
        // keep results ordered without the workers sharing an array.
        var buckets = [[DuplicateGroup]](repeating: [], count: candidates.count)
        let bucketLock = NSLock()
        HelmActivity.phase("duplicates.hash") {
            DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
                if self.isCancelled { return }
                var found: [DuplicateGroup] = []
                let byPrefix = Duplicates.refine(candidates[index]) { file in
                    if self.isCancelled { return nil }
                    progress.bump()
                    // The cache first, and the file only if it misses. The walk has
                    // already seen this file, so nothing new can hide here — this
                    // skips the *reading*, not the looking.
                    if let known = cache?.prefix(fileID: file.fileID, bytes: file.bytes,
                                                 modified: file.modified) {
                        return known
                    }
                    let digest = Self.hash(file.path, limit: Self.prefixBytes,
                                           expecting: min(Self.prefixBytes, file.bytes))
                    if digest == nil { progress.noteUnreadable() }
                    if let digest {
                        cache?.setPrefix(digest, fileID: file.fileID, bytes: file.bytes,
                                         modified: file.modified)
                    }
                    return digest
                }
                for group in byPrefix {
                    // Files at or under the prefix size are already fully read:
                    // their prefix hash IS their full hash.
                    for identical in Duplicates.refine(group, by: { file in
                        if self.isCancelled { return nil }
                        progress.bump()
                        if let known = cache?.full(fileID: file.fileID, bytes: file.bytes,
                                                   modified: file.modified) {
                            return known
                        }
                        let digest = file.bytes <= Self.prefixBytes
                            ? Self.hash(file.path, limit: Self.prefixBytes,
                                        expecting: file.bytes)
                            : Self.hash(file.path, limit: nil, expecting: file.bytes)
                        if let digest {
                            cache?.setFull(digest, fileID: file.fileID, bytes: file.bytes,
                                           modified: file.modified)
                        }
                        // The second pass fails too, and on the largest files —
                        // where an unreadable file is most likely to be the whole
                        // answer. Counting only the first pass undercounts exactly
                        // there. (No double count: a file that failed the prefix
                        // pass never reaches this one.)
                        if digest == nil { progress.noteUnreadable() }
                        return digest
                    }) {
                        found.append(Duplicates.group(identical))
                    }
                }
                bucketLock.lock(); buckets[index] = found; bucketLock.unlock()
            }
        }
        // Same as the walk above: the hashing loop is the one that has already
        // caused a 48 GB incident, and a stopped run is where it is biggest.
        HelmLog.shared.memory("duplicates.hash")
        if isCancelled { return nil }
        let groups = buckets.flatMap { $0 }.sorted { $0.wasted > $1.wasted }
        // Unreadable files leave the running silently by design; the count is
        // what tells a triage session whether "no duplicates" meant "none" or
        // "nothing could be read".
        let unreadable = progress.unreadableCount
        HelmLog.shared.info("duplicates", "\(groups.count) groups from \(total) candidates"
                            + (unreadable > 0 ? ", \(unreadable) unreadable" : ""))
        return groups
    }

    // MARK: - The walk

    /// Every regular file under the root, with size and inode. Symlinks are
    /// not followed, package interiors are not entered — offering half of an
    /// .app bundle as "a duplicate" invites breaking the app — and the walk
    /// stays on the root's volume: descending into a mounted backup drive
    /// means reading gigabytes over whatever bus it hangs from.
    private func walk(_ root: String,
                      onProgress: (@Sendable (DuplicateProgress) -> Void)?) -> [FileFacts] {
        let url = URL(fileURLWithPath: root)
        var rootStat = stat()
        let rootDevice: Int32? = lstat(root, &rootStat) == 0 ? rootStat.st_dev : nil
        // Walking "/" reaches every user file twice — once as /Users/… and
        // once as /System/Volumes/Data/Users/…. The inode collapse keeps that
        // from inventing duplicates, but the second visit is a whole disk of
        // wasted reads. The same table DiskScanner uses names the twins.
        let firmlinkSkip = FirmlinkMap.skipSet(scanRoot: root)
        // `addedToDirectoryDate` decides which copy stays — the Finder's
        // "Date Added", not the creation date a file carries with it when it
        // is copied. See `SurvivingCopy`.
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey,
                                      .totalFileAllocatedSizeKey,
                                      .addedToDirectoryDateKey]
        // The handler is what makes "keep walking" a decision instead of a
        // default. Measured on this OS, the handler-less overload already walks
        // past a directory it cannot open — but it walks past it *silently*,
        // and a whole subtree missing from "what is duplicated" is the one
        // thing this answer must not hide. Returning true carries on; the count
        // is what the log reports, the way DiskScanner marks a denied directory
        // `noAccess` instead of dropping it.
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { [weak self] _, _ in
                self?.noteUnreadable()
                return true
            }) else { return [] }

        var files: [FileFacts] = []
        var seen = 0
        var lastEmit = Date.distantPast
        for case let item as URL in enumerator {
            if isCancelled { return files }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            seen += 1
            // The walk is silent work; without a tick the sheet sits inert
            // for the seconds a big folder takes, which reads as a hang.
            if Date().timeIntervalSince(lastEmit) > 0.35 {
                lastEmit = Date()
                onProgress?(DuplicateProgress(candidates: 0, hashed: seen))
            }
            if values.isDirectory == true {
                if firmlinkSkip.contains(item.path) {
                    enumerator.skipDescendants()
                    continue
                }
                var dirStat = stat()
                if let rootDevice, lstat(item.path, &dirStat) == 0,
                   dirStat.st_dev != rootDevice {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true,
                  let size = values.fileSize, size >= Self.minBytes else { continue }
            var status = stat()
            guard lstat(item.path, &status) == 0 else { continue }
            if let rootDevice, status.st_dev != rootDevice { continue }
            files.append(FileFacts(path: item.path, bytes: size,
                                   fileID: UInt64(status.st_ino),
                                   added: values.addedToDirectoryDate,
                                   allocated: values.totalFileAllocatedSize ?? size,
                                   // One `getattrlist` per candidate, and only
                                   // for files already past the size floor. What
                                   // it buys is the difference between the size
                                   // of a copy and what removing it returns.
                                   cloneFamily: CloneShare.familyID(ofFileAt: item.path),
                                   // Free: the `lstat` above was already made
                                   // for the inode and the device.
                                   modified: TimeInterval(status.st_mtimespec.tv_sec)
                                       + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000))
        }
        return files
    }

    // MARK: - Progress

    /// Hash-rate progress, throttled the way DiskScanner throttles partials:
    /// pass one alone measured 7.6k events against the ~3/s a person can
    /// read, and every one of them crossed the transport to a main-actor
    /// publish.
    private final class ThrottledProgress: @unchecked Sendable {
        private let total: Int
        private let onProgress: (@Sendable (DuplicateProgress) -> Void)?
        private let lock = NSLock()
        private var count = 0
        private var unreadable = 0
        private var lastEmit = Date.distantPast

        init(total: Int, onProgress: (@Sendable (DuplicateProgress) -> Void)?) {
            self.total = total
            self.onProgress = onProgress
        }

        /// Files whose digest could not be taken. They leave the running by
        /// design — unknown is not identical — but a search that found nothing
        /// because nothing could be read is a different answer from a clean one.
        var unreadableCount: Int {
            lock.lock(); defer { lock.unlock() }
            return unreadable
        }

        func noteUnreadable() {
            lock.lock(); unreadable += 1; lock.unlock()
        }

        func bump() {
            lock.lock()
            count += 1
            let now = Date()
            let due = now.timeIntervalSince(lastEmit) > 0.35
            if due { lastEmit = now }
            let snapshot = min(count, total)
            lock.unlock()
            if due { onProgress?(DuplicateProgress(candidates: total, hashed: snapshot)) }
        }
    }

    // MARK: - Hashing

    /// SHA-256 of the file's first `limit` bytes, or of all of it. Streamed in
    /// 1 MB slices so a video does not become a Data the size of the video.
    ///
    /// `expecting` is how many bytes must actually be hashed for the answer to
    /// mean anything. Without it, a read that failed on the first slice — an
    /// iCloud-evicted file, a dying disk, a file truncated between the walk
    /// and the hash — returned the digest of *nothing*, which is the same
    /// digest for every such file. Two unreadable files of equal size grouped
    /// as duplicates and the sheet offered to trash content nobody had read.
    /// Unknown is not identical: short reads answer nil and leave the running.
    /// What one slice of a read came to. An enum rather than three flags
    /// because the pool closure has to answer with a value, not with a
    /// `return` that would only leave the closure.
    private enum SliceOutcome {
        case read(Int)
        case end
        case failed
    }

    /// Internal rather than private so `DuplicateVerification` can hash a file
    /// exactly the way the search did. A verification that hashes differently
    /// verifies something else — and this one stands between a stale offer and
    /// a deleted file.
    static func hash(_ path: String, limit: Int?, expecting: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        var hashed = 0
        while remaining > 0 {
            // The pool is INSIDE the loop, and it is the whole reason the
            // streaming above works. `FileHandle.read` hands back an
            // autoreleased `Data`, and `concurrentPerform` drains no pool per
            // iteration — so without this, every slice ever read stayed alive
            // until the entire parallel block finished, and the footprint
            // tracked the volume read rather than the slice size. Measured:
            // 1.8 GB of reads ended at 1760 MB as written, 6 MB with the pool.
            // A user saw 48 GB. Around the loop is not enough either: one 20 GB
            // video is a single iteration of the caller's work.
            let outcome: SliceOutcome = autoreleasepool {
                let slice = min(remaining, 1024 * 1024)
                // A thrown read is a failure; a nil/empty read is honest EOF.
                let read: Data?
                do { read = try handle.read(upToCount: slice) } catch { return .failed }
                guard let data = read, !data.isEmpty else { return .end }
                hasher.update(data: data)
                return .read(data.count)
            }
            switch outcome {
            case .failed: return nil
            case .end: break
            case .read(let count):
                hashed += count
                remaining -= count
                continue
            }
            break
        }
        guard hashed >= expecting else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
