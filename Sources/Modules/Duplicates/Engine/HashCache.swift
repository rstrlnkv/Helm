import Foundation

/// A map of the files as they are now, with their digests — in two segments.
///
/// **Why the win exists.** `DuplicateScanner` says where the minutes go in its
/// own comment: "a real home directory measured 70 GB of worst-case full-hash
/// volume", while "a folder of ten thousand distinct files costs a directory
/// walk and nothing else". The walk is cheap; reading contents is not, and
/// between two scans of a disk that barely changed, nearly all of that reading
/// is repeated for nothing.
///
/// **Why it is safe.** The walk still visits every file, so nothing that
/// appeared, vanished or moved can be missed — this skips the *reading*, never
/// the looking. Skipping the walk itself is a different feature with a different
/// risk, considered and deferred in the design: a directory's mtime does not
/// change when a file inside it grows, so a tree-skipping scan can hold a stale
/// digest for a file it never looked at.
///
/// **Two segments, and no eviction at all.** `settled` is the map as of the last
/// compaction; `fresh` is everything the scans since have touched — read or
/// written. A hit in `settled` is *promoted* into `fresh`, so `fresh` is always
/// the set of files that still exist. Compaction is then `settled := fresh`, and
/// the map is bounded by the disk rather than by history.
///
/// This replaced a single map with a per-entry expiry and a count limit. That
/// one grew without bound inside its own thirty days, and when the limit bit,
/// which entries survived was decided by the order `concurrentPerform` happened
/// to hash them in — a ceiling that discarded by luck rather than by worth.
/// Segments need no such choice: nothing is evicted, because nothing that is
/// still on the disk is ever absent from `fresh`.
///
/// **Never on the removal path.** `DuplicateVerification` reads both files from
/// disk immediately before either moves, because a digest here is exactly what
/// it exists to distrust: a file edited while keeping its size and mtime is the
/// one change the key cannot see, and there the price is a deleted file rather
/// than a slow scan.
public final class HashCache: Codable, @unchecked Sendable {

    /// Identity is inode, size and modification time together.
    ///
    /// The inode rather than the path, so a file that was merely renamed or
    /// moved keeps its digest — the commonest change in a Downloads folder. A
    /// string key because this is written as JSON, where a struct key would need
    /// a container of its own for no gain.
    static func key(fileID: UInt64, bytes: Int, modified: TimeInterval?) -> String {
        "\(fileID)-\(bytes)-\(modified.map { String(format: "%.6f", $0) } ?? "?")"
    }

    public struct Digests: Codable, Equatable, Sendable {
        /// The first 128 KB, which is what thins the field.
        public var prefix: String?
        /// The whole file, which is what decides.
        public var full: String?
    }

    /// The map as of the last compaction.
    private var settled: [String: Digests]
    /// What the scans since have touched, read or written.
    private var fresh: [String: Digests]
    /// When `settled` was established. Age belongs to the segment, not to each
    /// entry — which is the whole reason an entry is 184 bytes again rather than
    /// the 212 a per-entry stamp cost.
    private var settledAt: TimeInterval

    /// Hashing runs under `concurrentPerform`, so readers and writers arrive
    /// from different threads at once. A bare dictionary under that is undefined
    /// behaviour rather than a wrong answer.
    private let lock = NSLock()

    public init(now: TimeInterval = Date().timeIntervalSince1970) {
        settled = [:]
        fresh = [:]
        settledAt = now
    }

    // MARK: - Codable
    //
    // Hand-written because the lock is not `Codable` and a synthesized
    // conformance would try to encode it.

    private enum CodingKeys: String, CodingKey { case settled, fresh, settledAt }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settled = try container.decode([String: Digests].self, forKey: .settled)
        fresh = try container.decode([String: Digests].self, forKey: .fresh)
        settledAt = try container.decode(TimeInterval.self, forKey: .settledAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try lock.withLock {
            try container.encode(settled, forKey: .settled)
            try container.encode(fresh, forKey: .fresh)
            try container.encode(settledAt, forKey: .settledAt)
        }
    }

    // MARK: - Use

    /// Entries in `fresh` — the files this map believes still exist.
    ///
    /// A `storedCount` sat beside this — everything across both segments, «what
    /// the file on disk costs» — and nothing in the app or the tests ever asked
    /// it. A figure nobody reads is not a diagnostic.
    public var count: Int { lock.withLock { fresh.count } }

    public func prefix(fileID: UInt64, bytes: Int, modified: TimeInterval?) -> String? {
        promote(Self.key(fileID: fileID, bytes: bytes, modified: modified)) { $0.prefix }
    }

    public func full(fileID: UInt64, bytes: Int, modified: TimeInterval?) -> String? {
        promote(Self.key(fileID: fileID, bytes: bytes, modified: modified)) { $0.full }
    }

    /// **A hit in `settled` is copied into `fresh`.** Without that, a file that
    /// never changes is only ever read from the settled segment, is never in the
    /// fresh one, and the next compaction — which is `settled := fresh` —
    /// forgets it. The files a cache is most valuable for are exactly the ones
    /// that do not change.
    private func promote(_ key: String, _ read: (Digests) -> String?) -> String? {
        lock.withLock {
            if let entry = fresh[key], let digest = read(entry) { return digest }
            guard let settledEntry = settled[key],
                  let digest = read(settledEntry) else { return nil }
            // **Merged, not assigned.** Both halves travel — the prefix and the
            // full digest are read in two separate passes, so promoting only
            // the one that was asked for strands the other in a segment about
            // to be replaced.
            //
            // And the merge has to run the other way too, which an assignment
            // got wrong: `fresh` may already hold a digest this scan computed
            // while `settled` holds the other half, and `fresh[key] = entry`
            // threw the newer one away — permanently, one compaction later.
            // Whatever `fresh` has wins; `settled` fills the gaps.
            var merged = fresh[key] ?? Digests()
            merged.prefix = merged.prefix ?? settledEntry.prefix
            merged.full = merged.full ?? settledEntry.full
            fresh[key] = merged
            return digest
        }
    }

    public func setPrefix(_ digest: String, fileID: UInt64, bytes: Int,
                          modified: TimeInterval?) {
        let key = Self.key(fileID: fileID, bytes: bytes, modified: modified)
        lock.withLock { fresh[key, default: Digests()].prefix = digest }
    }

    public func setFull(_ digest: String, fileID: UInt64, bytes: Int,
                        modified: TimeInterval?) {
        let key = Self.key(fileID: fileID, bytes: bytes, modified: modified)
        lock.withLock { fresh[key, default: Digests()].full = digest }
    }

    // MARK: - Compaction

    /// Thirty days. A settled segment older than that is holding digests for
    /// files nobody has seen in a month, and the scans since have promoted
    /// everything that still exists.
    public static let maximumAge: TimeInterval = 30 * 24 * 3600

    /// `settled := fresh`, and `fresh` starts again.
    ///
    /// After this the map holds exactly what the scans since the last compaction
    /// touched — which, because every hit is promoted, is the set of files that
    /// still exist. Nothing is chosen for eviction and nothing is chosen for
    /// survival: the disk decides.
    public func compacted(now: TimeInterval = Date().timeIntervalSince1970) -> HashCache {
        let out = HashCache(now: now)
        lock.withLock { out.settled = fresh }
        return out
    }

    /// Compacts only when the settled segment has aged out, and otherwise hands
    /// back the same map.
    ///
    /// Deferring it is what makes a file that left and came back cheap: its
    /// digest is still in `settled` for up to a month, so the scan that finds it
    /// again does not read it.
    public func compactedIfStale(now: TimeInterval = Date().timeIntervalSince1970,
                                 maximumAge: TimeInterval = HashCache.maximumAge) -> HashCache {
        guard lock.withLock({ now - settledAt }) > maximumAge else { return self }
        return compacted(now: now)
    }
}
