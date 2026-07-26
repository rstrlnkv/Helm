import CryptoKit
import Foundation

/// Where the duplicate search stands, for a sheet that shows its work.
public struct DuplicateProgress: Codable, Sendable {
    /// Files whose size made them worth reading.
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

        let candidates = Duplicates.sizeGroups(files, minBytes: Self.minBytes)
        let total = candidates.reduce(0) { $0 + $1.count }
        let progress = ThrottledProgress(total: total, onProgress: onProgress)

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
                return Self.hash(file.path, limit: Self.prefixBytes)
            }
            for group in byPrefix {
                // Files at or under the prefix size are already fully read:
                // their prefix hash IS their full hash.
                for identical in Duplicates.refine(group, by: { file in
                    if self.isCancelled { return nil }
                    progress.bump()
                    return file.bytes <= Self.prefixBytes
                        ? Self.hash(file.path, limit: Self.prefixBytes)
                        : Self.hash(file.path, limit: nil)
                }) {
                    found.append(DuplicateGroup(bytes: identical.first?.bytes ?? 0,
                                                paths: identical.map(\.path).sorted()))
                }
            }
            bucketLock.lock(); buckets[index] = found; bucketLock.unlock()
        }
        if isCancelled { return nil }
        return buckets.flatMap { $0 }.sorted { $0.wasted > $1.wasted }
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
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
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
                                   fileID: UInt64(status.st_ino)))
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
        private var lastEmit = Date.distantPast

        init(total: Int, onProgress: (@Sendable (DuplicateProgress) -> Void)?) {
            self.total = total
            self.onProgress = onProgress
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
    private static func hash(_ path: String, limit: Int?) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let slice = min(remaining, 1024 * 1024)
            guard let data = try? handle.read(upToCount: slice), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
