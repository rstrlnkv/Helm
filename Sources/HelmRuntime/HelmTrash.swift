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

        /// The reason to show when the whole batch is being summarised in one
        /// line: the most common one, and the first of the batch to break a
        /// tie, so the sentence does not change between two identical runs.
        public var principalReason: TrashFailure.Reason? {
            var counts: [TrashFailure.Reason: Int] = [:]
            for refusal in refused { counts[refusal.reason, default: 0] += 1 }
            return refused.map(\.reason).max { counts[$0]! < counts[$1]! }
        }
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

        for path in allowed {
            let url = URL(fileURLWithPath: path)
            // Read before the move: afterwards the URL points at nothing.
            let size = allocatedSize(of: url)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                removed.append(path)
                freed += size
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

    /// What trashing this frees.
    ///
    /// `totalFileAllocatedSize` on a directory answers for the directory entry
    /// and not a byte of what is inside it — on APFS it answers **zero**. So
    /// Disk, whose whole job is disk space, told people a trashed folder freed
    /// nothing, and every plug-in bundle Leftovers removes would have done the
    /// same the moment it stopped keeping its own recursive count. A folder is
    /// what these modules delete most.
    ///
    /// The walk is bounded by what the person selected and happens once per
    /// path, before the move. `.skipsHiddenFiles` is deliberately not set: a
    /// hidden file inside the folder is freed along with it and belongs in the
    /// figure.
    private static func allocatedSize(of url: URL) -> Int {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        guard values.isDirectory == true else { return values.totalFileAllocatedSize ?? 0 }

        var total = 0
        let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        while let item = items?.nextObject() as? URL {
            total += (try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                .totalFileAllocatedSize ?? 0
        }
        return total
    }
}
