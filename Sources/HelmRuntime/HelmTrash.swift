import Foundation

/// Moving paths to the Trash, in one place, with the reason kept: a refusal
/// reported as a bare count tells the person nothing they can act on.
/// Architecture/Removal.md § Removal.
///
/// The scope gate stays outside: what a module is allowed to touch is the
/// module's own question (`RemovableScope`, `UserFileScope`, `WatchScope`),
/// and this type takes paths that have already passed it.
///
/// Every batch removal in the app comes through here (`grep -rn
/// 'HelmTrash.remove(' Sources`). Some pass `trashing`, the move itself, which
/// the uninstaller takes as a port so its tests can run without a filesystem;
/// a second copy of the loop would miss the rules below.
///
/// `removeOne` is the other entry: one file inside a rule the caller has
/// already decided. It answers with where the file landed, shares the batch's
/// classification of a refusal, and rechecks more strictly.
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

        var failed: [String] { refused.map(\.path) }
    }

    /// The move as macOS makes it: what an engine passes as `trashing` in the app, and what a test replaces.
    public static let moveToTrash: @Sendable (URL) throws -> Void = {
        _ = try moveToTrashSayingWhere($0)
    }

    /// The same move, answering where the Trash put the file. The Trash renames
    /// what it takes when the name is occupied, so the path the file had is not a
    /// path anything is at. Nil when macOS took it and would not say.
    public static let moveToTrashSayingWhere: @Sendable (URL) throws -> URL? = {
        var landed: NSURL?
        try FileManager.default.trashItem(at: $0, resultingItemURL: &landed)
        return landed as URL?
    }

    /// One file's answer: a sum, so a path cannot be neither or both.
    public enum OneFile: Equatable, Sendable {
        /// In the Trash. Nil when macOS took it and would not say where.
        case trashed(at: URL?)
        /// Still where it stood. `said` is the system's sentence; nil when Helm
        /// itself stopped and nothing was attempted.
        case refused(Refusal, said: String?)
    }

    /// `path` has passed the caller's gate; `approved` is what its parents resolved
    /// to when it did. Compared strictly: unlike a batch, no earlier turn can have
    /// taken the parent, so a parent gone is a change.
    ///
    /// No phase, no memory line and no log of its own: a sweep trashes file by
    /// file, so a reading per file would flood the trail, and the caller records
    /// each outcome. No ledger either, nobody reads bytes here.
    ///
    /// `trashing` throws the way `FileManager` does and **leaves the item gone**:
    /// a return with the item still standing is refused (`moveChecked`).
    public static func removeOne(_ path: String,
                                 approved: PathCanonical.AncestryIdentity?,
                                 ancestry: (String) -> PathCanonical.AncestryIdentity?,
                                 trashing: (URL) throws -> URL?) -> OneFile {
        // Built before the recheck, which is the last thing before the move.
        let url = URL(fileURLWithPath: path)
        guard ancestry(path) == approved else {
            return .refused(Refusal(path: path, reason: .changedSinceScan), said: nil)
        }
        do {
            return .trashed(at: try moveChecked(path) { try trashing(url) })
        } catch {
            return .refused(refusal(of: error, path: path, hasSystemExtension: false),
                            said: HelmFailure.describe(error))
        }
    }

    /// What `lstat` says stands at a path. Nothing there (`ENOENT`, or a parent
    /// that is no folder) and «could not read» (`EACCES` and the rest) are
    /// different facts, and only the first may go on to the move.
    private enum Look: Equatable {
        case nothing
        case item(PathCanonical.FileIdentity)
        case unreadable
    }

    private static func look(_ path: String) -> Look {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .nothing : .unreadable
        }
        return .item(PathCanonical.FileIdentity(status: st))
    }

    /// The two refusals Helm makes of its own around a move, as errors so both
    /// entries classify them where they classify macOS's.
    private static let guardDomain = "HelmTrash.guard"
    private enum Guard: Int {
        case unreadable = 1, stillInPlace

        var error: NSError {
            NSError(domain: HelmTrash.guardDomain, code: rawValue, userInfo: [
                NSLocalizedDescriptionKey: self == .unreadable
                    ? "the item could not be read at the moment of the move"
                    : "reported moved, still in place",
            ])
        }
    }

    /// The one place a move is checked, for `remove` and `removeOne` alike.
    ///
    /// A move that did not throw is not a move that happened: a sealed or
    /// system-protected place can answer success and leave the item. So the item
    /// found at `path` is read before the move (by `lstat`, which does not follow
    /// a final symlink, as `fileExists` would) and the path again after it; the
    /// same device and inode still there is a refusal. A *different* file under
    /// the name is what a caller's replacement put there, and is not.
    ///
    /// A path that cannot be read before the move is not attempted, and one that
    /// cannot be read after it is not believed: both `.unreadable`, a false
    /// refusal at worst. Nothing there before the move goes on to it, so macOS
    /// gives the reason it always did.
    private static func moveChecked<T>(_ path: String, _ move: () throws -> T) throws -> T {
        let before = look(path)
        if before == .unreadable { throw Guard.unreadable.error }
        let result = try move()
        guard case .item = before else { return result }
        switch look(path) {
        case before: throw Guard.stillInPlace.error
        case .unreadable: throw Guard.unreadable.error
        default: return result
        }
    }

    /// What macOS's answer means for `path`; the one classification both entries use.
    private static func refusal(of error: Error, path: String, hasSystemExtension: Bool) -> Refusal {
        if (error as NSError).domain == guardDomain {
            return Refusal(path: path, reason: (error as NSError).code == Guard.unreadable.rawValue
                           ? .unreadable : .systemRefused)
        }
        return Refusal(path: path, reason: TrashFailure.reason(path: path,
                                                        errorCode: (error as NSError).code,
                                                        hasSystemExtension: hasSystemExtension))
    }

    /// Trash `allowed`, and record `outOfScope` for everything the caller's own
    /// gate turned away — the refusal has to arrive with the rest of the batch
    /// or the count and the list disagree.
    ///
    /// `hasSystemExtension` answers "is this bundle a live system extension",
    /// which changes the reason from "macOS said no" to something the person
    /// can act on. Modules that cannot be handed an app bundle leave it alone.
    ///
    /// `trashing` is the move, a parameter so a module that reaches the
    /// filesystem through a port can hand that port over rather than keep a
    /// second copy of this loop. It **leaves the item gone**: a return with the
    /// same item still standing is refused (`moveChecked`), as is a path
    /// unreadable before the move. It throws the way `FileManager` does, because
    /// a failure is read by its `NSError` code.
    ///
    /// `ancestry` names the directory each path's parent chain resolves to. It is
    /// read once as the batch begins and again immediately before each move; a
    /// path whose answer changed is refused with `changedSinceScan`, because a
    /// symlinked ancestor was swapped between the two. This **narrows, it does
    /// not close**: a swap before the batch began is not caught, and one stat
    /// chain still separates the recheck from `trashItem`'s own resolve. It takes
    /// away the wide part, the `FileWeight` walk, whose duration an attacker sets
    /// with a large batch. A full close needs an `O_DIRECTORY | O_NOFOLLOW`
    /// parent with a relative unlink, which `trashItem` cannot express.
    ///
    /// `leaf` says what the last component of these paths is, and so what the
    /// log lines may print: the person's own document for Disk and Duplicates, a
    /// bundle id for Leftovers and the uninstaller. Only the module knows.
    ///
    /// `sharedWith` names the files that **stay**. Their clone families are
    /// seeded into the ledger, so a copy whose blocks a survivor goes on holding
    /// is reported as freeing nothing; the ledger has no reverse lookup from a
    /// family to its members to work that out. Duplicates passes it, since its
    /// survivor is never in the batch.
    public static func remove(allowed: [String],
                              outOfScope: [String] = [],
                              sharedWith: [String] = [],
                              module: String,
                              leaf: Redact.Leaf = .fileName,
                              hasSystemExtension: (String) -> Bool = { _ in false },
                              ancestry: (String) -> PathCanonical.AncestryIdentity? = {
                                  PathCanonical.ancestryIdentity(of: $0)
                              },
                              trashing: (URL) throws -> Void = HelmTrash.moveToTrash)
        -> Result {
        // One phase for every deleting module, named per module, so a new one
        // cannot forget it. Scope form, so the interval closes on every way out.
        let phase = "\(module).trash"
        return HelmActivity.phase(phase) {
            // Taken before the phase ends, not after: `HelmLog.memory` names what
            // else runs beside the label it excludes, and a phase already closed
            // cannot be excluded from its own line.
            defer { HelmLog.shared.memory(phase) }
            var removed: [String] = []
            var refused = outOfScope.map { Refusal(path: $0, reason: .outOfScope) }
            var freed = 0

            for path in outOfScope {
                HelmLog.shared.warn(module,
                                    "refused out-of-scope path: \(Redact.path(path, leaf: leaf))")
            }

            // One ledger for the batch: a hard link is one allocation under several
            // names, and the second name frees nothing — and neither does the second
            // member of an APFS clone family, whose blocks come back once when the
            // family goes (`FileWeight.reclaimed`). Opened owing whatever the files
            // that stay already hold: a family with a survivor gives back nothing at
            // all, however many of its members this batch takes.
            var counted = FileWeight.Ledger(sharedWith: sharedWith)

            // One outcome per path, whatever the caller handed over: a path
            // arriving twice would otherwise be both removed and failed.
            //
            // Trailing separators, all of them, are stripped before the dedupe
            // and the ancestry test: that test is a raw prefix comparison, and
            // `p` and `p//` would be one folder counted as two removals.
            //
            // Shortest first, so a folder is taken before anything inside it and
            // the child can tell "the batch took my parent" from "it was never
            // there", and a `Set` handed over gives the same answer every run.
            var seenPaths: Set<String> = []
            let ordered = allowed
                .map(PathCanonical.withoutTrailingSeparators)
                .filter { seenPaths.insert($0).inserted }
                .sorted { $0.count < $1.count }

            // The reference read, taken before any walk weighs the batch: the walk is
            // the window an attacker widens, so it has to sit inside the brackets, not
            // straddle them.
            let approvedAncestry = ordered.map(ancestry)

            for (index, path) in ordered.enumerated() {
                let url = URL(fileURLWithPath: path)
                // Weighed against a slate of this path's own, folded into the
                // batch's ledger only where the path really goes. Weighing
                // writes, and it happens before the recheck, which must stay
                // last before the move; a refused path must not spend the
                // ledger for the next name of the same allocation.
                var slate = counted
                // Read before the move: afterwards the URL points at nothing.
                let size = FileWeight.reclaimed(of: url, charging: &slate)
                // Read the ancestry again, now, against the batch's reference. A
                // swapped symlink lands on a *different existing* directory object, so
                // a redirected subtree stops here rather than in someone's Documents.
                //
                // Only when the parent still exists: a `nil` here is the parent
                // gone, which the `NSFileNoSuchFileError` branch below owns, never
                // a redirection. A parent that appeared where the reference saw
                // none, or moved to another object, differs from the reference.
                if let now = ancestry(path), now != approvedAncestry[index] {
                    refused.append(Refusal(path: path, reason: .changedSinceScan))
                    HelmLog.shared.warn(module,
                        "refused: ancestor changed since the gate: \(Redact.path(path, leaf: leaf))")
                    continue
                }
                do {
                    try moveChecked(path) { try trashing(url) }
                    removed.append(path)
                    // The one place the batch's ledger grows: what it has charged
                    // is exactly what it has taken.
                    counted = slate
                    freed += size
                } catch let error as NSError
                    where error.code == NSFileNoSuchFileError
                       && !FileManager.default.fileExists(atPath: path)
                       && removed.contains(where: { path.hasPrefix($0 + "/") }) {
                    // It went with its parent, earlier in this same batch.
                    // "macOS refused" would send somebody looking for a file that
                    // is in the Trash. Only when this batch took it: a path gone
                    // before the batch began is a refusal, a stale list the
                    // person should be told about.
                    removed.append(path)
                } catch {
                    let refusal = refusal(of: error, path: path,
                                          hasSystemExtension: hasSystemExtension(path))
                    let reason = refusal.reason
                    refused.append(refusal)
                    // Composed here rather than through `HelmLog.failure`, because
                    // the system's half names the file too («The file
                    // “com.acme.tool.plist” doesn’t exist», and `NSFilePathErrorKey`).
                    //
                    // Where the leaf names software, the system's sentence stays out
                    // of the log entirely: macOS quotes a bundle by its display
                    // name, which no replacement of the file name could find. The
                    // domain, the code and Helm's classification name nothing. A
                    // caller that shows the sentence keeps its own record of it
                    // (the Uninstaller's `saidByPath`).
                    let said = leaf == .softwareName
                        ? "\((error as NSError).domain) \((error as NSError).code), \(reason.rawValue)"
                        : HelmFailure.describe(error)
                    HelmLog.shared.error(module, "trash refused \(Redact.path(path, leaf: leaf)): \(said)")
                }
            }

            HelmLog.shared.info(module, "trashed \(removed.count), failed \(refused.count)")
            return Result(removed: removed, refused: refused, freedBytes: freed)
        }
    }
}
