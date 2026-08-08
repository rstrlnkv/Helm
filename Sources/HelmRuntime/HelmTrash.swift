import Foundation

/// Moving paths to the Trash, in one place, with the reason kept.
///
/// Four modules wrote this loop: take the allowed paths, ask `FileManager` to
/// trash each one, total the bytes freed, and collect what refused. Byte for
/// byte the same in Disk and Duplicates, near enough in Autopilot and
/// Leftovers — and only one of the four did anything with `TrashFailure`.
/// The other three put the path on a `failed` list and dropped the error, so
/// the person who had just been refused by Full Disk Access was told a number
/// and nothing else. Which reason it was is the only part of that sentence
/// worth reading.
///
/// The scope gate stays outside: what a module is allowed to touch is the
/// module's own question (`RemovableScope`, `UserFileScope`, `WatchScope`),
/// and this type takes paths that have already passed it.
///
/// Every batch removal in the app comes through here — `grep -rn
/// 'HelmTrash.remove' Sources` says which, and a number written down in this
/// paragraph would not. The last one in was the uninstaller, through `trashing`:
/// the move itself, which that module takes as a port so its tests can run
/// without a filesystem. The seam was declined once, on the grounds that it
/// changed this for every caller to serve one; what the copy it left in place
/// then cost was three rules stated in the comments below and missing there — a
/// child taken with its parent reported as neither moved nor refused, a hard
/// link's bytes counted once per name, and a batch whose order decided its own
/// answer.
///
/// `RuleRunner` is the one path still outside, and it is a different shape: one
/// file at a time inside a rule it has already decided, with no batch for any of
/// the rules here to be about.
public enum HelmTrash {

    /// What happened to one path.
    public struct Refusal: Codable, Equatable, Sendable {
        public let path: String
        public let reason: TrashFailure.Reason

        public init(path: String, reason: TrashFailure.Reason) {
            self.path = path
            self.reason = reason
        }
    }

    public struct Result: Codable, Equatable, Sendable {
        public let removed: [String]
        public let refused: [Refusal]
        public let freedBytes: Int

        public init(removed: [String], refused: [Refusal], freedBytes: Int) {
            self.removed = removed
            self.refused = refused
            self.freedBytes = freedBytes
        }

        public var failed: [String] { refused.map(\.path) }
    }

    /// Trash `allowed`, and record `outOfScope` for everything the caller's own
    /// gate turned away — the refusal has to arrive with the rest of the batch
    /// or the count and the list disagree.
    ///
    /// `hasSystemExtension` answers "is this bundle a live system extension",
    /// which changes the reason from "macOS said no" to something the person
    /// can act on. Modules that cannot be handed an app bundle leave it alone.
    ///
    /// `trashing` is the move, and the only reason it is a parameter: a module
    /// that reaches the filesystem through a port has to be able to hand that
    /// port over here rather than keep a second copy of this loop. It throws the
    /// way `FileManager` does, because what this does with a failure is read its
    /// `NSError` code — a port that reports an outcome instead wraps it back up.
    public static func remove(allowed: [String],
                              outOfScope: [String] = [],
                              module: String,
                              hasSystemExtension: (String) -> Bool = { _ in false },
                              trashing: (URL) throws -> Void = {
                                  try FileManager.default.trashItem(at: $0,
                                                                    resultingItemURL: nil)
                              })
        -> Result {
        var removed: [String] = []
        var refused = outOfScope.map { Refusal(path: $0, reason: .outOfScope) }
        var freed = 0

        for path in outOfScope {
            HelmLog.shared.warn(module, "refused out-of-scope path: \(Redact.path(path))")
        }

        // One set for the batch: a hard link is one allocation under several
        // names, and the second name frees nothing.
        var counted: Set<UInt64> = []

        // One outcome per path, whatever the caller handed over. `removed` and
        // `failed` are read as one description of one batch, and the same file
        // appeared in both when a path arrived twice: the first turn trashed
        // it, the second met `NSFileNoSuchFileError` and the "went with its
        // parent" branch does not fire for a path that *is* itself. Every
        // caller writes `Array(Set(paths))` today; nothing in this signature
        // said they had to.
        //
        // A trailing slash names the same folder and is a different string, so
        // it is stripped before either the dedupe or the ancestry test — that
        // test is a raw prefix comparison, and `…/folder/` never prefixes
        // `…/folder/inside.bin` with the separator this expects. **All of
        // them**: a path joined onto a root that already ended in one carries
        // two, and stripping a single separator left `p` and `p//` as two
        // entries in one batch — the first moved, the second met "no such
        // file", and the branch below forgave it as a child of the first,
        // because `p//` really does begin with `p/`. One folder, two removals,
        // and `removed.count` is what the banner counts.
        //
        // Shortest first, so a folder is taken before anything inside it and
        // the child can tell "the batch took my parent" from "it was never
        // there". `DiskEngine` hands over a `Set`, whose order is a hash seed —
        // the same basket gave two different answers on two runs.
        var seenPaths: Set<String> = []
        let ordered = allowed
            .map(withoutTrailingSeparators)
            .filter { seenPaths.insert($0).inserted }
            .sorted { $0.count < $1.count }
        for path in ordered {
            let url = URL(fileURLWithPath: path)
            // Read before the move: afterwards the URL points at nothing.
            let size = FileWeight.allocated(of: url, countingOnce: &counted)
            do {
                try trashing(url)
                removed.append(path)
                freed += size
            } catch let error as NSError
                where error.code == NSFileNoSuchFileError
                   && !FileManager.default.fileExists(atPath: path)
                   && removed.contains(where: { path.hasPrefix($0 + "/") }) {
                // It went with its parent, earlier in this same batch: basket a
                // folder from one screen and a file inside it from another and
                // the child's turn comes after the folder has moved. Reporting
                // "macOS refused" would send somebody looking for a file that is
                // in the Trash, and the count would say one when two went.
                //
                // Only when this batch is what took it. A path that was already
                // gone before any of this started is still a refusal with a
                // reason — the person is looking at a stale list and should be
                // told so.
                removed.append(path)
            } catch {
                let reason = TrashFailure.reason(path: path,
                                                 errorCode: (error as NSError).code,
                                                 hasSystemExtension: hasSystemExtension(path))
                refused.append(Refusal(path: path, reason: reason))
                HelmLog.shared.failure(module, "trash refused \(Redact.path(path))", error)
            }
        }

        HelmLog.shared.info(module, "trashed \(removed.count), failed \(refused.count)")
        return Result(removed: removed, refused: refused, freedBytes: freed)
    }

    /// The spelling the batch answers under. The root is the one path that is
    /// nothing but separators, and it keeps its own.
    private static func withoutTrailingSeparators(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}
