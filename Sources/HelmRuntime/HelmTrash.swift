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
/// Three of the four call it: Disk, Duplicates and Leftovers. The other two
/// paths that trash things do not, and the reason is the same in both — they
/// take a port so their tests can run without a filesystem, while this hard-
/// wires `FileManager`. `UninstallerEngine.trashSync` also carries a rule this
/// does not (a bundle that is a live system extension is blamed on the
/// extension rather than on macOS), and `RuleRunner` trashes one file at a time
/// inside a rule it has already decided. Adopting them needs an injectable
/// seam here, which would change this for all five callers to serve two —
/// weighed and declined, deliberately, rather than overlooked.
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
    /// can act on. Modules that cannot be handed an app bundle pass nil.
    public static func remove(allowed: [String],
                              outOfScope: [String] = [],
                              module: String,
                              hasSystemExtension: (String) -> Bool = { _ in false })
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
        // `…/folder/inside.bin` with the separator this expects.
        //
        // Shortest first, so a folder is taken before anything inside it and
        // the child can tell "the batch took my parent" from "it was never
        // there". `DiskEngine` hands over a `Set`, whose order is a hash seed —
        // the same basket gave two different answers on two runs.
        var seenPaths: Set<String> = []
        let ordered = allowed
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            .filter { seenPaths.insert($0).inserted }
            .sorted { $0.count < $1.count }
        for path in ordered {
            let url = URL(fileURLWithPath: path)
            // Read before the move: afterwards the URL points at nothing.
            let size = FileWeight.allocated(of: url, countingOnce: &counted)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
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
}
