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

    public func prefix(fileID: UInt64, bytes: Int, modified: TimeInterval?) -> String? {
        lock.withLock { entries[Self.key(fileID: fileID, bytes: bytes, modified: modified)]?.prefix }
    }

    public func full(fileID: UInt64, bytes: Int, modified: TimeInterval?) -> String? {
        lock.withLock { entries[Self.key(fileID: fileID, bytes: bytes, modified: modified)]?.full }
    }

    public func setPrefix(_ digest: String, fileID: UInt64, bytes: Int,
                          modified: TimeInterval?) {
        let key = Self.key(fileID: fileID, bytes: bytes, modified: modified)
        lock.withLock { entries[key, default: Digests()].prefix = digest }
    }

    public func setFull(_ digest: String, fileID: UInt64, bytes: Int,
                        modified: TimeInterval?) {
        let key = Self.key(fileID: fileID, bytes: bytes, modified: modified)
        lock.withLock { entries[key, default: Digests()].full = digest }
    }

    /// Everything this search did not touch is dropped.
    ///
    /// Without it the file grows forever: every version of every file ever
    /// hashed keeps an entry, because a changed file gets a *new* key rather
    /// than replacing the old one. Called with the keys the finished search
    /// used, so the cache is always the size of the last scan and not of the
    /// machine's history.
    public func keeping(_ live: Set<String>) -> HashCache {
        let kept = HashCache()
        kept.entries = lock.withLock { entries.filter { live.contains($0.key) } }
        return kept
    }
}
