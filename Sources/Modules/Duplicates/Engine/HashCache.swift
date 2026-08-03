import Foundation

/// Digests kept from the last search, so the next one does not read the file
/// again.
///
/// **Why this is the win.** `DuplicateScanner` says where the minutes go in its
/// own comment: "a real home directory measured 70 GB of worst-case full-hash
/// volume", while "a folder of ten thousand distinct files costs a directory
/// walk and nothing else". The walk is cheap; reading contents is not. On a disk
/// that barely changed between two scans, this is the difference between reading
/// 70 GB and reading almost none of it.
///
/// **Why it is safe.** The walk still visits every file, so nothing that
/// appeared, vanished or moved can be missed — the cache only avoids *reading*
/// what the walk already found. That is the whole reason it is a hash cache and
/// not the tree-skipping the design considered and deferred: skipping the walk
/// changes what is looked at, and a mistake there produces a number that looks
/// perfectly normal and is wrong.
///
/// **Where it must never be used.** Not on the removal path.
/// `DuplicateVerification` reads both files from disk immediately before either
/// moves, precisely because a cached digest is what it exists to distrust: a
/// file edited while keeping its size and mtime — `cp -p`, `rsync --times`, a
/// restored backup — would otherwise send a file that is no longer a duplicate
/// to the Trash.
public final class HashCache: Codable, @unchecked Sendable {

    /// Identity is inode, size and modification time together.
    ///
    /// The inode rather than the path, so a file that was merely renamed or
    /// moved keeps its digest — which is the commonest change between two scans
    /// of a Downloads folder. A string key because this is written as JSON and
    /// a struct key would need a container of its own for no gain.
    static func key(fileID: UInt64, bytes: Int, modified: TimeInterval?) -> String {
        "\(fileID)-\(bytes)-\(modified.map { String(format: "%.6f", $0) } ?? "?")"
    }

    public struct Digests: Codable, Equatable, Sendable {
        /// The first 128 KB, which is what thins the field.
        public var prefix: String?
        /// The whole file, which is what decides.
        public var full: String?
        /// When this entry was last written or read.
        ///
        /// What makes the file bounded. A changed file takes a *new* key rather
        /// than replacing its old one — the mtime is part of the key — so
        /// without an expiry every state of every file ever hashed would stay
        /// forever.
        public var usedAt: TimeInterval = 0
    }

    private var entries: [String: Digests]
    /// Hashing runs under `concurrentPerform`, so every reader and writer here
    /// arrives from a different thread at once. A bare dictionary under that is
    /// undefined behaviour rather than a wrong answer — the failure mode
    /// `InMemoryKeyValueStore` records having taken a whole module down.
    private let lock = NSLock()

    public init() { self.entries = [:] }

    // MARK: - Codable
    //
    // Hand-written because the lock is not `Codable` and a synthesized
    // conformance would try to encode it.

    private enum CodingKeys: String, CodingKey { case entries }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([String: Digests].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lock.withLock { entries }, forKey: .entries)
    }

    // MARK: - Use

    public var count: Int { lock.withLock { entries.count } }

    /// **A read that writes.** Touching the entry is what keeps a file that is
    /// still on the disk from expiring, so the freshness stamp cannot be updated
    /// only on misses — a file that never changes would then age out and be
    /// re-read every thirty days, which is the one case the cache exists for.
    public func prefix(fileID: UInt64, bytes: Int, modified: TimeInterval?,
                       now: TimeInterval = Date().timeIntervalSince1970) -> String? {
        touch(Self.key(fileID: fileID, bytes: bytes, modified: modified), now) { $0.prefix }
    }

    public func full(fileID: UInt64, bytes: Int, modified: TimeInterval?,
                     now: TimeInterval = Date().timeIntervalSince1970) -> String? {
        touch(Self.key(fileID: fileID, bytes: bytes, modified: modified), now) { $0.full }
    }

    private func touch(_ key: String, _ now: TimeInterval,
                       _ read: (Digests) -> String?) -> String? {
        lock.withLock {
            guard let entry = entries[key], let digest = read(entry) else { return nil }
            entries[key]?.usedAt = now
            return digest
        }
    }

    public func setPrefix(_ digest: String, fileID: UInt64, bytes: Int,
                          modified: TimeInterval?,
                          now: TimeInterval = Date().timeIntervalSince1970) {
        let key = Self.key(fileID: fileID, bytes: bytes, modified: modified)
        lock.withLock {
            entries[key, default: Digests()].prefix = digest
            entries[key]?.usedAt = now
        }
    }

    public func setFull(_ digest: String, fileID: UInt64, bytes: Int,
                        modified: TimeInterval?,
                        now: TimeInterval = Date().timeIntervalSince1970) {
        let key = Self.key(fileID: fileID, bytes: bytes, modified: modified)
        lock.withLock {
            entries[key, default: Digests()].full = digest
            entries[key]?.usedAt = now
        }
    }

    // MARK: - Keeping it bounded

    /// Thirty days: a file untouched for a month is one the next scan can
    /// afford to read again.
    public static let maximumAge: TimeInterval = 30 * 24 * 3600

    /// Twenty thousand entries, about **3,9 MB** at the measured 196 bytes each.
    ///
    /// The age limit alone is not a ceiling — it is a *rate*. A disk whose files
    /// churn faster than they expire grows without bound inside thirty days,
    /// and the entries are worth roughly what they cost only while the file
    /// stays smaller than the scan it saves. Measured: `~/Documents` produces
    /// 6900 entries, so this is comfortable room above a real folder and a hard
    /// stop above an unreasonable one.
    public static let limit = 20_000

    /// Drops what expired, then what does not fit, oldest first.
    ///
    /// Both, and in that order. Age is the rule; the count is the backstop for
    /// the disk that outruns it.
    public func pruned(now: TimeInterval = Date().timeIntervalSince1970,
                       maximumAge: TimeInterval = HashCache.maximumAge,
                       limit: Int = HashCache.limit) -> HashCache {
        let kept = HashCache()
        kept.entries = lock.withLock {
            let fresh = entries.filter { now - $0.value.usedAt <= maximumAge }
            guard fresh.count > limit else { return fresh }
            // Most recently used first, then cut. A dictionary has no order, so
            // without the sort the survivors would be whichever the hash table
            // happened to yield.
            return Dictionary(uniqueKeysWithValues:
                fresh.sorted { $0.value.usedAt > $1.value.usedAt }.prefix(limit)
                    .map { ($0.key, $0.value) })
        }
        return kept
    }
}
