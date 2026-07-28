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
    public func find(under root: String,
                     onProgress: (@Sendable (DuplicateProgress) -> Void)? = nil)
    -> [DuplicateGroup]? {
        let files = walk(root, onProgress: onProgress)
        if isCancelled { return nil }

        HelmLog.shared.info("duplicates", "walked \(Redact.path(root)): "
                            + "\(files.count) files at or above the floor")
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
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            if self.isCancelled { return }
            var found: [DuplicateGroup] = []
            let byPrefix = Duplicates.refine(candidates[index]) { file in
                if self.isCancelled { return nil }
                progress.bump()
                let digest = Self.hash(file.path, limit: Self.prefixBytes,
                                       expecting: min(Self.prefixBytes, file.bytes))
                if digest == nil { progress.noteUnreadable() }
                return digest
            }
            for group in byPrefix {
                // Files at or under the prefix size are already fully read:
                // their prefix hash IS their full hash.
                for identical in Duplicates.refine(group, by: { file in
                    if self.isCancelled { return nil }
                    progress.bump()
                    let digest = file.bytes <= Self.prefixBytes
                        ? Self.hash(file.path, limit: Self.prefixBytes,
                                    expecting: file.bytes)
                        : Self.hash(file.path, limit: nil, expecting: file.bytes)
                    // The second pass fails too, and on the largest files —
                    // where an unreadable file is most likely to be the whole
                    // answer. Counting only the first pass undercounts exactly
                    // there. (No double count: a file that failed the prefix
                    // pass never reaches this one.)
                    if digest == nil { progress.noteUnreadable() }
                    return digest
                }) {
                    found.append(DuplicateGroup(bytes: identical.first?.bytes ?? 0,
                                                paths: identical.map(\.path).sorted()))
                }
            }
            bucketLock.lock(); buckets[index] = found; bucketLock.unlock()
        }
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
                                      .addedToDirectoryDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]) else { return [] }

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
                                   added: values.addedToDirectoryDate))
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
    private static func hash(_ path: String, limit: Int?, expecting: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        var hashed = 0
        while remaining > 0 {
            let slice = min(remaining, 1024 * 1024)
            // A thrown read is a failure; a nil/empty read is honest EOF.
            let read: Data?
            do { read = try handle.read(upToCount: slice) } catch { return nil }
            guard let data = read, !data.isEmpty else { break }
            hasher.update(data: data)
            hashed += data.count
            remaining -= data.count
        }
        guard hashed >= expecting else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
