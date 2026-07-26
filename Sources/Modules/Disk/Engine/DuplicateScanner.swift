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
        let files = walk(root)
        if isCancelled { return nil }

        let candidates = Duplicates.sizeGroups(files, minBytes: Self.minBytes)
        let total = candidates.reduce(0) { $0 + $1.count }
        var hashed = 0

        func counted(_ digest: @escaping (FileFacts) -> String?) -> (FileFacts) -> String? {
            { file in
                if self.isCancelled { return nil }
                hashed += 1
                onProgress?(DuplicateProgress(candidates: total, hashed: min(hashed, total)))
                return digest(file)
            }
        }

        let groups = Duplicates.groups(
            files: files, minBytes: Self.minBytes,
            partial: counted { Self.hash($0.path, limit: Self.prefixBytes) },
            // Files at or under the prefix size are already fully read: their
            // prefix hash IS their full hash, so the second pass is free.
            full: counted { $0.bytes <= Self.prefixBytes
                ? Self.hash($0.path, limit: Self.prefixBytes)
                : Self.hash($0.path, limit: nil) })
        return isCancelled ? nil : groups
    }

    // MARK: - The walk

    /// Every regular file under the root, with size and inode. Symlinks are
    /// not followed and package interiors are not entered — offering half of
    /// an .app bundle as "a duplicate" invites breaking the app.
    private func walk(_ root: String) -> [FileFacts] {
        let url = URL(fileURLWithPath: root)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey,
                                      .fileResourceIdentifierKey, .isPackageKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]) else { return [] }

        var files: [FileFacts] = []
        for case let item as URL in enumerator {
            if isCancelled { return files }
            guard let values = try? item.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize, size >= Self.minBytes else { continue }
            files.append(FileFacts(path: item.path, bytes: size,
                                   fileID: inode(of: item.path)))
        }
        return files
    }

    private func inode(of path: String) -> UInt64 {
        var status = stat()
        guard lstat(path, &status) == 0 else { return 0 }
        return UInt64(status.st_ino)
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
