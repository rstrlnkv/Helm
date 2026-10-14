import Foundation

/// Moving paths to the Trash, in one place, with the reason kept.
///
/// Several modules wrote this loop: take the allowed paths, ask `FileManager` to
/// trash each one, total the bytes freed, and collect what refused. Byte for
/// byte the same in Disk and Duplicates, near enough in Autopilot and
/// Leftovers — and only one of them did anything with `TrashFailure`.
/// The others put the path on a `failed` list and dropped the error, so
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
/// paragraph would not. Some pass `trashing`: the move itself, which the
/// uninstaller takes as a port so its tests can run without a filesystem. The seam was declined once, on the grounds that it
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
    ///
    /// `ancestry` names the directory each path's parent chain resolves to. It is
    /// read once as the batch begins and again immediately before each move; a
    /// path whose answer changed is refused with `changedSinceScan`, because a
    /// symlinked ancestor was swapped between the two — the gate approved one
    /// subtree and the Trash would take another. This **narrows, it does not
    /// close**: this entry takes strings, so the reference is taken here, not at
    /// the gate, and a swap that landed before the batch began is not caught
    /// (`remove(gated:)` is the entry whose reference is the gate's). After the
    /// recheck one stat chain still separates the check from `trashItem`'s own
    /// resolve. What it does take away is the wide part — the `FileWeight` walk
    /// below, whose duration an attacker sets by handing over a large batch. A
    /// full close needs an `O_DIRECTORY | O_NOFOLLOW` parent with a relative
    /// unlink, which `trashItem` cannot express.
    ///
    /// A string that does not start at `/`, and one whose file URL has an empty
    /// path (`/.file/id=<device>.<inode>`), is turned away as `outOfScope`
    /// before any move: the URL made of the first is a place under the working
    /// directory nobody judged, and the Trash is not handed an empty path.
    ///
    /// `leaf` says what the last component of these paths is, and it decides what
    /// each line the loop below logs about a path may print. It is a fact only the
    /// module knows — for Disk and Duplicates the leaf is the person's own document,
    /// for Leftovers and the uninstaller it is a bundle id — and the loop that writes
    /// the lines is shared, so it has to be told. Left at `.fileName`, every line
    /// reads exactly as it did.
    ///
    /// `sharedWith` names the files that **stay** — the ones this batch is being
    /// removed *around*. Their clone families are seeded into the ledger below, so
    /// a copy whose blocks a survivor goes on holding is reported as the nothing
    /// it frees. The ledger cannot work this out for itself: there is no reverse
    /// lookup from a family to its members, so a family whose survivor is outside
    /// the batch was charged in full. Every caller but Duplicates leaves it empty and
    /// behaves exactly as it did; Duplicates is the module where the survivor is
    /// by construction never in the batch, so for it that was every family.
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
        // What no gate has judged is held to two rules of its own here, because
        // each would otherwise move something nobody approved.
        let movable = { (path: String) in
            path.utf8.first == PathCanonical.separator && !URL(fileURLWithPath: path).path.isEmpty
        }
        // A trailing slash names the same folder and is a different string, so
        // it is stripped before the dedupe and before the ancestry test — that
        // test is a raw prefix comparison, and `…/folder/` never prefixes
        // `…/folder/inside.bin` with the separator this expects. **All of
        // them**: a path joined onto a root that already ended in one carries
        // two, and stripping a single separator left `p` and `p//` as two
        // entries in one batch — the first moved, the second met "no such
        // file", and the branch below forgave it as a child of the first,
        // because `p//` really does begin with `p/`. One folder, two removals,
        // and `removed.count` is what the banner counts.
        var seenPaths: Set<String> = []
        let items = allowed.filter(movable).compactMap { path -> Item? in
            let stripped = PathCanonical.withoutTrailingSeparators(path)
            return seenPaths.insert(stripped).inserted
                ? Item(asked: stripped, name: stripped, reading: nil) : nil
        }
        return carryOut(items,
                        turnedAway: (outOfScope + allowed.filter { !movable($0) })
                            .map { Refusal(path: $0, reason: .outOfScope) },
                        sharedWith: sharedWith, module: module, leaf: leaf,
                        hasSystemExtension: hasSystemExtension, ancestry: ancestry,
                        trashing: trashing)
    }

    /// Trash what gates judged: the object each one read, under the one name it
    /// judged, reported under the string that was asked.
    ///
    /// `gated` and `refused` are the two halves of what `RemovableScope.gate` or
    /// `UserFileScope.gate` answered, and the rest is `remove(allowed:)`'s (the
    /// loop is the same one). The reference of the recheck is the gate's own
    /// reading, so what is compared immediately before each move is the parent the
    /// gate read with the parent now, and the object the gate read with whatever
    /// is at the judged name now (`lstat`, a link answering for itself): another
    /// object or another parent is `changedSinceScan`. This **narrows, it does not
    /// close**: one stat chain still separates the check from `trashItem`'s own
    /// resolve.
    ///
    /// Nothing at the judged name at the move is never handed to `trashing`,
    /// whichever the gate read there: it is the went-with-its-parent case when this
    /// batch moved that name or one above it, and `missing` otherwise. Something
    /// there where the gate read nothing is a change.
    ///
    /// Each answer carries the string that was asked, not the name that was
    /// moved, because a caller finds its rows by the string it handed the gate.
    static func remove(gated: [GatedPath],
                       refused: [Refusal] = [],
                       sharedWith: [String] = [],
                       module: String,
                       leaf: Redact.Leaf = .fileName,
                       hasSystemExtension: (String) -> Bool = { _ in false },
                       trashing: (URL) throws -> Void = HelmTrash.moveToTrash)
        -> Result {
        carryOut(gated.map { Item(asked: $0.asked, name: $0.name, reading: $0.reading) },
                 turnedAway: refused, sharedWith: sharedWith, module: module, leaf: leaf,
                 hasSystemExtension: hasSystemExtension,
                 ancestry: { PathCanonical.ancestryIdentity(of: $0) }, trashing: trashing)
    }

    /// The move both entries default to.
    @usableFromInline static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// One path of a batch: the string to report it under, the name to move,
    /// and the gate's reading where there was one.
    private struct Item {
        let asked: String
        let name: String
        let reading: PathCanonical.Reading?
    }

    /// What a name was answered with, whichever way the turn ended.
    private enum Answer { case removed, refused(TrashFailure.Reason) }

    /// What the recheck before a move found.
    private enum Drift { case none, changed, gone }

    private static func drift(of item: Item,
                              approved: PathCanonical.AncestryIdentity?,
                              ancestry: (String) -> PathCanonical.AncestryIdentity?) -> Drift {
        guard let reading = item.reading else {
            // Only when the parent still exists: a `nil` here is the parent gone,
            // which is the went-with-its-parent case one folder up in this same
            // batch (the `NSFileNoSuchFileError` branch of the loop owns that),
            // never a redirection — trashing a path whose parent has vanished
            // moves nothing. A parent that appeared where the gate saw none, or
            // moved to another object, is the change that matters, and both
            // differ from the reference.
            if let now = ancestry(item.name), now != approved { return .changed }
            return .none
        }
        guard let object = PathCanonical.identity(of: item.name) else { return .gone }
        return object == reading.object
            && ancestry(item.name) == reading.parent ? .none : .changed
    }

    /// The loop both entries share.
    private static func carryOut(_ items: [Item],
                                 turnedAway: [Refusal],
                                 sharedWith: [String],
                                 module: String,
                                 leaf: Redact.Leaf,
                                 hasSystemExtension: (String) -> Bool,
                                 ancestry: (String) -> PathCanonical.AncestryIdentity?,
                                 trashing: (URL) throws -> Void) -> Result {
        // One phase for every deleting module, named per module: only Disk
        // wrapped its call, and Disk was not the outlier, it was the one that got
        // audited. Scope form, so the interval closes on every way out.
        let phase = "\(module).trash"
        return HelmActivity.phase(phase) {
            // Taken before the phase ends, not after: `HelmLog.memory` names what
            // else runs beside the label it excludes, and a phase already closed
            // cannot be excluded from its own line.
            defer { HelmLog.shared.memory(phase) }
            var removed: [String] = []
            // The names that were moved, for the child that went with its parent.
            var moved: [String] = []
            // What each judged name was answered with, for its later spellings.
            var answered: [String: Answer] = [:]
            var refused = turnedAway
            var freed = 0

            for turned in turnedAway {
                let kind = turned.reason == .unreadable ? "unreadable" : "out-of-scope"
                HelmLog.shared.warn(module,
                                    "refused \(kind) path: \(Redact.path(turned.path, leaf: leaf))")
            }

            // One ledger for the batch: a hard link is one allocation under several
            // names, and the second name frees nothing — and neither does the second
            // member of an APFS clone family, whose blocks come back once when the
            // family goes (`FileWeight.reclaimed`). Opened owing whatever the files
            // that stay already hold: a family with a survivor gives back nothing at
            // all, however many of its members this batch takes.
            var counted = FileWeight.Ledger(sharedWith: sharedWith)

            // `removed` and `failed` are read as one description of one batch, and
            // the same file appeared in both when a path arrived twice: the first
            // turn trashed it, the second met `NSFileNoSuchFileError`.
            // Every caller writes `Array(Set(paths))` today; nothing in this
            // signature said they had to.
            //
            // By the exact bytes of the string, and no further: a gate's `p` and
            // `p/` are two strings for one file, a caller finds its rows by the
            // string it handed the gate, and one of them dropped from both lists
            // is a row nobody can find. The second is answered as itself, with the
            // outcome of the first, and the name is handed to the move once,
            // whatever came of it (the first thing the loop asks). `remove(allowed:)`
            // has already made one entry of `p` and `p/`, which its callers rely on.
            //
            // Shortest first, so a folder is taken before anything inside it and
            // the child can tell "the batch took my parent" from "it was never
            // there". `DiskEngine` hands over a `Set`, whose order is a hash seed —
            // the same basket gave two different answers on two runs.
            var seenAsked: Set<[UInt8]> = []
            let ordered = items
                .filter { seenAsked.insert(Array($0.asked.utf8)).inserted }
                .sorted { $0.name.count < $1.name.count }

            // The reference read, taken before any walk weighs the batch: the walk is
            // the window an attacker widens, so it has to sit inside the brackets, not
            // straddle them. A gated item carries the gate's own and reads none.
            let approvedAncestry = ordered.map { $0.reading == nil ? ancestry($0.name) : nil }

            for (index, item) in ordered.enumerated() {
                // Another spelling of a name this batch has already answered, moved
                // or not: answered under its own string with the first one's outcome,
                // not handed to the move, nor judged, a second time.
                if let first = answered[item.name] {
                    switch first {
                    case .removed:
                        removed.append(item.asked)
                    case .refused(let reason):
                        refused.append(Refusal(path: item.asked, reason: reason))
                        HelmLog.shared.error(module,
                            "trash refused \(Redact.path(item.asked, leaf: leaf)): \(reason.rawValue), as its other spelling")
                    }
                    continue
                }
                // Whichever way this turn ends, the one list it grew says what the
                // next spelling of the name is answered with.
                let removedBefore = removed.count
                let refusedBefore = refused.count
                defer {
                    answered[item.name] = removed.count > removedBefore ? .removed
                        : refused.count > refusedBefore ? .refused(refused[refusedBefore].reason) : nil
                }
                let url = URL(fileURLWithPath: item.name)
                // Whether this batch is what took the item: it is one of the names
                // moved, or lies inside one.
                let tookWithItsParent = {
                    moved.contains { item.name == $0 || item.name.hasPrefix($0 + "/") }
                }
                // Weighed against a slate of this path's own, folded into the
                // batch's ledger only where the path really goes.
                //
                // Weighing *writes* — that is how an allocation wearing several
                // names is charged once — and it happens before the recheck below,
                // which cannot move: being the last thing before the move is the
                // whole of its value. So a path that is then refused had already
                // spent the ledger, and the next name for the same allocation was
                // weighed as something already counted and added 0 — a batch
                // reporting that it freed nothing about a file it really did trash.
                var slate = counted
                // Read before the move: afterwards the URL points at nothing.
                let size = FileWeight.reclaimed(of: url, charging: &slate)
                // Read again, now, against the reference: the gate's own reading for a
                // gated path, the read as the batch began for a string. A swapped symlink
                // lands on a *different existing* directory object, so a redirected
                // subtree stops here rather than in someone's Documents.
                switch drift(of: item, approved: approvedAncestry[index], ancestry: ancestry) {
                case .none:
                    break
                case .changed:
                    refused.append(Refusal(path: item.asked, reason: .changedSinceScan))
                    let what = item.reading == nil ? "ancestor changed" : "changed"
                    HelmLog.shared.warn(module,
                        "refused: \(what) since the gate: \(Redact.path(item.asked, leaf: leaf))")
                    continue
                case .gone:
                    // Nothing there for a path the gate read as an object, or still
                    // nothing for one it read as nothing: not handed to the move.
                    if tookWithItsParent() {
                        removed.append(item.asked)
                        moved.append(item.name)
                    } else {
                        refused.append(Refusal(path: item.asked, reason: .missing))
                        HelmLog.shared.error(module,
                            "trash refused \(Redact.path(item.asked, leaf: leaf)): nothing there")
                    }
                    continue
                }
                do {
                    try trashing(url)
                    removed.append(item.asked)
                    moved.append(item.name)
                    // The one place the batch's ledger grows: what it has charged
                    // is exactly what it has taken.
                    counted = slate
                    freed += size
                } catch let error as NSError
                    where error.code == NSFileNoSuchFileError
                       && !FileManager.default.fileExists(atPath: item.name)
                       && tookWithItsParent() {
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
                    removed.append(item.asked)
                    moved.append(item.name)
                } catch {
                    let reason = TrashFailure.reason(path: item.name,
                                                     errorCode: (error as NSError).code,
                                                     hasSystemExtension: hasSystemExtension(item.name))
                    refused.append(Refusal(path: item.asked, reason: reason))
                    // Composed here rather than through `HelmLog.failure`, which is the
                    // same line at the same level, because **the system's half of it
                    // names the file too**: `trashItem` refusing answers «The file
                    // “com.acme.tool.plist” doesn’t exist» and repeats the path under
                    // `NSFilePathErrorKey`, so redacting Helm's own half would leave a
                    // module whose leaf is a bundle id naming it twice more.
                    //
                    // And for a module whose leaf names software, **not the system's
                    // sentence at all**: macOS quotes a bundle by its *display name*
                    // («“Hidden Title” couldn’t be moved…»), which is not the file's
                    // name, and a name under four characters is never replaced inside
                    // a sentence. The domain, the code and Helm's own classification
                    // say everything the sentence did; the sentence itself reaches the
                    // screen through the engine's own record of it. What the line
                    // carries instead is Helm's own and cannot quote the software, so it
                    // is not passed through `Redact.naming`, which would rewrite a word
                    // of it for an app named like one («Cocoa», «missing»).
                    let said = leaf == .softwareName
                        ? "\((error as NSError).domain) \((error as NSError).code), \(reason.rawValue)"
                        : HelmFailure.describe(error)
                    HelmLog.shared.error(module, "trash refused \(Redact.path(item.asked, leaf: leaf)): \(said)")
                }
            }

            HelmLog.shared.info(module, "trashed \(removed.count), failed \(refused.count)")
            return Result(removed: removed, refused: refused, freedBytes: freed)
        }
    }
}
