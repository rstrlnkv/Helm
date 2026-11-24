import Foundation

/// Where a path *leads*, which is the only thing a removal gate may judge.
///
/// `URL.standardizedFileURL` and `NSString.standardizingPath` collapse `.` and
/// `..` and do not resolve symbolic links; `FileManager`'s `trashItem` follows
/// them. Without resolving, a path approved as
/// `~/Library/Caches/com.evil.app/taxes.pdf` can be executed as
/// `~/Documents/taxes.pdf`: any process running as the user can create a
/// directory the leftovers scan enumerates as a link to somewhere protected.
///
/// The **leaf is deliberately not resolved.** Trashing a symlink removes the
/// link and leaves its target alone, which is exactly what a person clearing a
/// stale alias asks for. It is an *ancestor* that redirects that makes the
/// spelling a lie, so only the parent chain is resolved.
///
/// `RemovableScope` and `UserFileScope` both need it. `WatchScope`
/// canonicalises on its own (Architecture/TheGates.md § The gates).
public enum PathCanonical {

    /// One folder, one spelling. `…/Ghost`, `…/Ghost/` and `…/Ghost//` are one
    /// place and three strings, and a batch that treats them as three answers
    /// three times for one folder.
    ///
    /// **Every** separator: a path joined onto a root that already ended in one
    /// carries two. The root keeps its own.
    public static func withoutTrailingSeparators(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    /// A stable name for the directory a path's parent chain resolves to *now*.
    ///
    /// Device and inode together identify one directory object; a rename or a
    /// swapped symlink in the parent chain lands on a different one, and that is
    /// exactly the change a gate approves before and a move must refuse after.
    /// `nil` when the parent does not exist — a path pointing at nothing yet
    /// (the scan and the click are minutes apart), which is a steady state, not a
    /// change, so two `nil`s compare equal.
    public struct AncestryIdentity: Equatable, Sendable {
        let device: UInt64
        public let inode: UInt64
        public init(device: UInt64, inode: UInt64) {
            self.device = device
            self.inode = inode
        }
        /// The one conversion of a signed `st_dev` to the unsigned bit pattern kept.
        public init(status: stat) {
            self.init(device: UInt64(bitPattern: Int64(status.st_dev)), inode: status.st_ino)
        }
    }

    /// Who a file is, as opposed to what it is called.
    ///
    /// Device and inode together name one object on one volume, and survive a
    /// rename and a move within that volume: the answer to "is the thing at
    /// this path still the thing I acted on". A move *across* volumes changes
    /// the inode, and callers fail safe: a mark stops matching, and a return
    /// refuses rather than moving a stranger's file.
    ///
    /// The device is `UInt64(bitPattern: st_dev)` and stays so: it is lossless,
    /// and it is stored in `ActionRecord.device` and in the stamp MAC
    /// (`StampMark.of(rule:device:inode:key:)`), so converting it would read
    /// every stamped file on a volume with a negative `st_dev` as unstamped.
    public struct FileIdentity: Equatable, Sendable {
        public let device: UInt64
        public let inode: UInt64
        public init(device: UInt64, inode: UInt64) {
            self.device = device
            self.inode = inode
        }
        /// The same bit pattern as `AncestryIdentity(status:)`, and what Autopilot's history stores.
        public init(status: stat) {
            let ancestry = AncestryIdentity(status: status)
            self.init(device: ancestry.device, inode: ancestry.inode)
        }
    }

    /// The identity of whatever is at `path`, or nothing when there is nothing.
    ///
    /// `lstat`, so a symlink answers with its own identity rather than its
    /// target's, as in `RuleStamp`: otherwise a link could stand in for the
    /// file it points at.
    public static func identity(of path: String) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileIdentity(status: info)
    }

    /// The identity of the directory `path`'s resolved parent chain leads to.
    ///
    /// Read as a reference and again immediately before the move: if the two
    /// disagree, a symlinked ancestor was swapped in between (`HelmTrash.remove`
    /// says where it takes the reference and what that narrows).
    public static func ancestryIdentity(of path: String) -> AncestryIdentity? {
        let resolved = resolvingAncestors(path)
        let parent = (resolved as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return nil }
        var info = stat()
        // `stat`, not `lstat`: the parent chain is already symlink-resolved, so
        // the two agree — and what is wanted is the object the name leads to.
        guard stat(parent, &info) == 0 else { return nil }
        return AncestryIdentity(status: info)
    }

    /// The directory a path names, with the leaf resolved too.
    ///
    /// The other half of `resolvingAncestors`. A gate over *removal* leaves the
    /// leaf alone, because trashing a stale alias must remove the alias. A gate
    /// over *reading* has no such case: you cannot walk a link, only what it
    /// points at, and `FileManager.enumerator` handed a link to a directory
    /// yields nothing, an empty scan recorded as clean.
    ///
    /// Standardized **before** anything else: `URL(fileURLWithPath:)` resolves a
    /// relative path against the process's working directory, so canonicalizing
    /// first answers a question nobody asked (`ScanRoot.resolve`).
    ///
    /// Shared by the scan root gate and the duplicate finder's transit tier,
    /// which compare a stored path against paths a walk produced and are wrong
    /// if either side is left unresolved.
    public static func resolvingWholePath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return URL(fileURLWithPath: standardized)
            .resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Where a path leads with every link in it followed — the leaf too, and a
    /// link whose target is not there yet.
    ///
    /// **`realpath` cannot answer for a link that points at nothing.**
    /// `resolvingSymlinksInPath()` fails with `ENOENT` on such a link and hands
    /// back the path unchanged, so `resolvingWholePath` calls a dangling link
    /// the place it names. A link planted before its target is created is
    /// invisible to it.
    ///
    /// So the parent chain is resolved as `resolvingAncestors` does — the deepest
    /// ancestor that exists, with the missing tail put back — and the leaf is
    /// then followed with `readlink`, which answers whether or not the target is
    /// there. A chain of links is followed to its end; a loop is stopped at
    /// `linkHops`, and what comes back is then a spelling that is not the one
    /// handed in, which every caller reads as «not the place it names».
    ///
    /// Use it wherever an unresolvable path must not read as an honest one.
    /// `resolvingWholePath` stays for the gates that compare two paths that both
    /// exist, where `realpath` is the cheaper reading of the same question.
    public static func followingEveryLink(_ path: String) -> String {
        var resolved = resolvingAncestors(path)
        for _ in 0..<linkHops {
            guard let target = try? FileManager.default
                .destinationOfSymbolicLink(atPath: resolved) else { return resolved }
            let absolute = target.hasPrefix("/")
                ? target
                : (resolved as NSString).deletingLastPathComponent + "/" + target
            resolved = resolvingAncestors(absolute)
        }
        return resolved
    }

    /// How many links deep this will follow before it gives up, which is what a
    /// loop of them looks like from here. `SYMLOOP_MAX` is 32 on this system and
    /// the kernel's own limit for the same walk.
    private static let linkHops = 32

    /// The same place, spelled without the `/private` the filesystem treats as
    /// invisible and a prefix test does not.
    ///
    /// Not `standardizingPath`, which does this rewrite **only for a path that
    /// exists**, and asks the disk to find out. This is a fact about the two
    /// spellings, and holds for a path that was never there.
    ///
    /// `ScanRoot` folds it away on both sides of a comparison, because an
    /// enumerator can hand back children spelled differently from its root;
    /// `UserFileScope` needs the pair, because its list holds `/private/var/db`
    /// itself.
    static func withoutPrivate(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    /// The path with every symlink in its parent chain resolved, and its last
    /// component put back untouched.
    ///
    /// A path that does not exist yet is still answered — the scan and the
    /// click are separated by however long the user takes — by resolving the
    /// deepest ancestor that does exist and re-appending the missing tail.
    static func resolvingAncestors(_ path: String) -> String {
        // A relative path is handed back untouched. `URL(fileURLWithPath:)`
        // resolves one against the process's working directory, which would
        // silently promote `""` and `relative/path` to absolute paths a gate
        // then approves.
        guard path.hasPrefix("/") else { return path }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        guard standardized.path != "/" else { return standardized.path }

        let leaf = standardized.lastPathComponent
        var parent = standardized.deletingLastPathComponent()
        var missing: [String] = []
        while parent.path != "/", !FileManager.default.fileExists(atPath: parent.path) {
            missing.append(parent.lastPathComponent)
            parent = parent.deletingLastPathComponent()
        }
        var resolved = parent.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        resolved.appendPathComponent(leaf)
        return resolved.path
    }
}
