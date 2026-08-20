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

    /// Public because the type crosses the target boundary: the UI's fakes
    /// build the tick the engine would have emitted, and a wire type only one
    /// side can construct is a branch no test on the other side can reach.
    public init(candidates: Int, hashed: Int) {
        self.candidates = candidates
        self.hashed = hashed
    }
}

/// Finds files with identical content under one folder.
///
/// The decisions live in `Duplicates` (pure, tested); this class supplies the
/// walking and the hashing. Size nominates, a prefix hash thins the field, a
/// full hash decides — so a folder of ten thousand distinct files costs a
/// directory walk and nothing else, and only real candidates are ever read in
/// full.
final class DuplicateScanner: @unchecked Sendable {
    /// Below this a file is not worth offering: the list would drown in
    /// kilobyte-sized config copies whose deletion frees nothing anyone can
    /// feel.
    static let minBytes = 1_000_000
    /// Enough of a prefix that two files agreeing on it are usually the same
    /// file; cheap enough that reading it costs one I/O burst.
    private static let prefixBytes = 128 * 1024

    private var cancelled = false
    private let lock = NSLock()
    private var unreadable = 0
    private var skippedLibraries = 0
    private var unreadableDigests = 0

    /// Paths the walk was refused — a folder without read permission, an item
    /// that vanished between being listed and being read. A count, not the
    /// paths: the question the log is asked is whether the answer was whole,
    /// not whose folder was in the way.
    var unreadablePaths: Int {
        lock.lock(); defer { lock.unlock() }
        return unreadable
    }

    private func noteUnreadable() {
        lock.lock(); unreadable += 1; lock.unlock()
    }

    /// Files whose digest could not be taken, over both hashing passes.
    ///
    /// Read off the scanner rather than left inside `find`: they leave the
    /// running by design — unknown is not identical — and a search that found
    /// nothing because nothing could be read is a different answer from a clean
    /// one. Kept beside `unreadablePaths` so the engine has one place to ask
    /// what the answer is missing.
    var unreadableFiles: Int {
        lock.lock(); defer { lock.unlock() }
        return unreadableDigests
    }

    /// Application libraries the walk declined to enter — a photo library, a
    /// Music library, a Final Cut bundle. Not a fault and still a hole: the
    /// largest things under `~/Pictures` are inside one.
    var librariesSkipped: Int {
        lock.lock(); defer { lock.unlock() }
        return skippedLibraries
    }

    private func noteSkippedLibrary() {
        lock.lock(); skippedLibraries += 1; lock.unlock()
    }

    /// Stop at the subtrees of the home an unattended reader has no business in
    /// (`ScanRoot.refusesDescentInHome`), rather than only refusing to start
    /// there.
    ///
    /// Off for a search a person asked for and is watching: they picked the
    /// folder in an open panel, and a gate that quietly dropped half of what
    /// they pointed at would be answering a question they did not ask. On for
    /// the timer, where the journal written afterwards names every path found,
    /// at 0600 — readable by every process running as this user, including the
    /// ones macOS refuses.
    private let unattended: Bool
    /// Injected only by tests; production takes the canonical home, which is the
    /// spelling `ScanRoot.resolve` hands the walk its root in.
    private let home: String

    init(unattended: Bool = false, home: String = ScanRoot.canonicalHome) {
        self.unattended = unattended
        self.home = home
    }

    func cancel() {
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
    /// - Parameter rule: which copy of identical content the search keeps. It is
    ///   needed **before** the hashing and not only after it: the name that
    ///   stands for a set of hard links is chosen by the same rule, and a
    ///   representative picked one way while the survivor is picked another is
    ///   the two-pipelines defect this module has already paid for once.
    func find(under root: String, by rule: KeepRule,
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
        HelmLog.shared.info(DuplicatesEngine.moduleID, "walked \(LogRoot.label(root)): "
                            + "\(files.count) files at or above the floor"
                            + (refused > 0 ? ", \(refused) unreadable" : ""))
        let candidates = Duplicates.sizeGroups(files, minBytes: Self.minBytes, by: rule)
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
                        found.append(Duplicates.group(identical, by: rule))
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
        // what tells a triage session — and now the page — whether "no
        // duplicates" meant "none" or "nothing could be read". Kept on the
        // scanner, so the engine reads one object rather than reaching into the
        // progress meter this function owns.
        // Named apart from the `unreadable` property, which counts what the
        // *walk* was refused: two different holes, and a local shadowing the
        // other one while being assigned into a third name is a line nobody can
        // read twice the same way.
        let digestFailures = progress.unreadableCount
        lock.lock(); unreadableDigests = digestFailures; lock.unlock()
        HelmLog.shared.info(DuplicatesEngine.moduleID, "\(groups.count) groups from \(total) candidates"
                            + (digestFailures > 0 ? ", \(digestFailures) unreadable" : ""))
        return groups
    }

    // MARK: - The walk

    /// Every regular file under the root, with size and inode. Symlinks are
    /// not followed, package interiors are not entered — offering half of an
    /// .app bundle as "a duplicate" invites breaking the app — and the walk
    /// stays on the root's volume: descending into a mounted backup drive
    /// means reading gigabytes over whatever bus it hangs from.
    ///
    /// **`BulkWalk`, not `FileManager.enumerator`.** The same question asked the
    /// same way as Disk asks it, and the reason the shared walker exists:
    /// measured warm on this Mac, compiled `-O`, `~/Projects` at 105 000 files
    /// costs 0,79 s enumerated and 0,23 s walked. What the enumerator used to
    /// answer per entry — the size, the inode, the modification time, the date
    /// added — the walk hands over with the entry, so the `lstat` this loop used
    /// to make per candidate is gone too.
    ///
    /// Internal rather than private so `WalkFootprintTests` can measure it apart
    /// from the hashing — the two are the module's two bulk loops and they have
    /// different answers about memory. `find` is its only caller in the app.
    func walk(_ root: String,
              onProgress: (@Sendable (DuplicateProgress) -> Void)?) -> [FileFacts] {
        let rootDevice = BulkWalk.deviceID(of: root)
        // Walking "/" reaches every user file twice — once as /Users/… and
        // once as /System/Volumes/Data/Users/…. The inode collapse keeps that
        // from inventing duplicates, but the second visit is a whole disk of
        // wasted reads. The same table DiskScanner uses names the twins.
        let firmlinkSkip = FirmlinkMap.skipSet(scanRoot: root)

        var files: [FileFacts] = []
        var seen = 0
        var lastEmit = Date.distantPast
        BulkWalk.walk(
            root: root,
            isCancelled: { self.isCancelled },
            descends: { entry in
                !self.stops(at: entry.path, firmlinkSkip: firmlinkSkip, rootDevice: rootDevice)
            },
            consume: { batch in
                // A subtree the walk was refused is a hole in "what is
                // duplicated", and the count is what the log reports — the way
                // DiskScanner marks a denied directory `noAccess` instead of
                // dropping it.
                for _ in batch.denied { self.noteUnreadable() }
                seen += batch.files.count
                for file in batch.files
                where file.isRegularFile && file.logicalBytes >= Self.minBytes {
                    // The date the copy arrived decides which copy stays
                    // (`SurvivingCopy`), and the clone family is what tells the
                    // size of a copy from what removing it returns — one
                    // `getattrlist`, and only for files already past the floor.
                    files.append(FileFacts(path: file.path, bytes: file.logicalBytes,
                                           fileID: file.fileID, added: file.added,
                                           allocated: file.allocatedBytes,
                                           cloneFamily: CloneShare.familyID(ofFileAt: file.path),
                                           modified: file.modified))
                }
                // The walk is silent work; without a tick the sheet sits inert
                // for the seconds a big folder takes, which reads as a hang.
                // Once per directory rather than once per file: `Date()` in the
                // inner loop was a reading taken a hundred thousand times to be
                // thrown away, and a batch is a directory.
                if Date().timeIntervalSince(lastEmit) > 0.35 {
                    lastEmit = Date()
                    onProgress?(DuplicateProgress(candidates: 0, hashed: seen))
                }
            })
        return files
    }

    /// Whether the walk stops at this directory rather than going into it.
    ///
    /// Five different reasons, each with its own record to keep, which is why
    /// they read better as one question than as five branches inside the walk.
    private func stops(at path: String, firmlinkSkip: Set<String>,
                       rootDevice: BulkWalk.DeviceID) -> Bool {
        // The Data volume's second face. Descending it reads the whole disk
        // twice for an answer the inode collapse has already given.
        if firmlinkSkip.contains(path) { return true }
        // An application's own database — a photo library, a Music library, a
        // Final Cut bundle. Judged by name, so a library copied from another
        // machine — one this Mac has never registered a type for — is still a
        // database and not a folder of somebody's files. The unattended case is
        // worse than meaningless — see `ScanRoot.refusesDescent`.
        if ScanRoot.refusesDescent(into: path) {
            noteSkippedLibrary()
            return true
        }
        // Any other package: an `.app`, an `.rtfd`, a `.pkg`. This is the half
        // `.skipsPackageDescendants` used to carry on the enumerator, and it has
        // to travel with the walk rather than be left behind with it — offering
        // half of an application bundle as "a duplicate" invites breaking the
        // app.
        if isPackage(path) { return true }
        // `~/Library` and what is under it, on the timer's path only. The root
        // gate cannot cover this: the home is the commonest duplicate-scan root
        // there is, so refusing to *begin* there stops nothing once the walk is
        // one step in.
        if unattended, ScanRoot.refusesDescentInHome(into: path, home: home) {
            // Said out loud, because an unattended run that finds fewer copies
            // than the interactive one owes the reason. Not `noteSkippedLibrary`:
            // that count draws «Photo and music libraries were not opened» on
            // the page, which this is not.
            HelmLog.shared.info(DuplicatesEngine.moduleID,
                                "unattended: not descending into "
                                + Redact.path(path, home: home))
            return true
        }
        // Another volume mounted inside this one: reading a backup drive means
        // gigabytes over whatever bus it hangs from. A `stat` per directory, and
        // `BulkWalk.deviceID` says why the walk cannot answer this itself.
        if !BulkWalk.deviceID(of: path).matches(rootDevice) { return true }
        return false
    }

    /// Whether macOS draws this directory as one item.
    ///
    /// Asked only of a name that carries an extension, and that is a
    /// measurement rather than a guess: of 221 packages under `~/Projects` and
    /// 2452 under `/Applications`, every one had an extension, while asking the
    /// question of *every* directory costs 0,34 s over the 12 000 in
    /// `~/Projects` — a third of the walk it is part of. A directory carrying
    /// the bundle bit and no extension is walked into, which is the one case
    /// this differs from `.skipsPackageDescendants` in.
    private func isPackage(_ path: String) -> Bool {
        guard !(path as NSString).pathExtension.isEmpty else { return false }
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey])
        return values?.isPackage == true
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
        return HexDigest.string(of: hasher.finalize())
    }
}
