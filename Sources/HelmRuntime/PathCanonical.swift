import Foundation

/// Where a path *leads*, which is what a removal gate judges, and whether it
/// begins with a prefix the kernel answers itself instead
/// (`beginsWithAKernelPrefix`).
///
/// `URL.standardizedFileURL` and `NSString.standardizingPath` collapse `.` and
/// `..` and stop there — they do not resolve symbolic links. `FileManager`'s
/// `trashItem` follows a link among the ancestors and moves the object the path
/// reaches through it. That gap let a path be approved as
/// `~/Library/Caches/com.evil.app/taxes.pdf` and executed as
/// `~/Documents/taxes.pdf`: any process running as the user can create one of
/// the plug-in directories the leftovers scan enumerates — none of them exist
/// on a stock install — as a link to somewhere protected, and wait.
///
/// The **leaf is deliberately not resolved.** `trashItem` moves a symbolic-link
/// leaf itself and leaves what it points at — a file, a directory or a bundle
/// (`RealTrashLeafTests`) — which is exactly what a person clearing a stale
/// alias asks for. It is an *ancestor* that redirects that makes the spelling a
/// lie, so only the parent chain is resolved.
///
/// This is the rule `WatchScope.canonical` already applies inside Autopilot,
/// written once here now that a second and third gate need it.
///
/// The trailing separator below is the same subject one layer down — not where
/// a path leads but which of several strings names the same place.
public enum PathCanonical {

    private static let separator = UInt8(ascii: "/")

    /// One folder, one spelling. `…/Ghost`, `…/Ghost/` and `…/Ghost//` are one
    /// place and three strings, and a batch that treats them as three answers
    /// three times for one folder.
    ///
    /// **Every** separator: a path joined onto a root that already ended in one
    /// carries two, and stripping a single one left `p` and `p//` different.
    /// The root is the one path that is nothing but a separator, and it keeps
    /// its own.
    ///
    /// Counted in bytes, as the kernel reads a path: the reading below hands
    /// the result to the kernel with the order not to follow a last link, and
    /// the kernel follows one all the same when a separator is left after it.
    public static func withoutTrailingSeparators(_ path: String) -> String {
        let bytes = path.utf8
        let trailing = bytes.reversed().prefix(while: { $0 == separator }).count
        guard trailing > 0 else { return path }
        return String(Substring(bytes.prefix(max(bytes.count - trailing, 1))))
    }

    /// The components of a path, cut at every `/` byte.
    ///
    /// Bytes, because a `String` is cut on characters, and a `/` with a
    /// combining mark after it is one character that is no separator: cut that
    /// way, a name that begins with such a mark merges with the folder it is
    /// in, and a rule about that folder no longer reads it there
    /// (`TheGatesTakeOneReadingOfTheObjectTests` holds the refusals).
    static func components(of path: String) -> [Substring] {
        path.utf8.split(separator: separator).map { Substring($0) }
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
        public let device: UInt64
        public let inode: UInt64
        public init(device: UInt64, inode: UInt64) {
            self.device = device
            self.inode = inode
        }
    }

    /// Who a file is, as opposed to what it is called.
    ///
    /// Device and inode together name one object on one volume, and they
    /// survive both a rename and a move within that volume — which is what
    /// makes them the right answer to "is the thing at this path still the
    /// thing I acted on". A move *across* volumes changes the inode, and the
    /// two callers here fail in the same direction when it does: a mark stops
    /// matching, and a return refuses rather than moving a stranger's file.
    public struct FileIdentity: Equatable, Sendable, Codable {
        public let device: UInt64
        public let inode: UInt64
        public init(device: UInt64, inode: UInt64) {
            self.device = device
            self.inode = inode
        }
    }

    /// The identity of whatever is at `path`, or nothing when there is nothing.
    ///
    /// `lstat`, so a symlink answers with its own identity rather than its
    /// target's — the same reading `RuleStamp` takes for the same reason: an
    /// answer about the target would let a link stand in for the file it points
    /// at.
    public static func identity(of path: String) -> FileIdentity? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: info.st_ino)
    }

    /// The identity of the directory `path`'s resolved parent chain leads to.
    ///
    /// Read once at the gate and once immediately before the move: if the two
    /// disagree, a symlinked ancestor was swapped in between (`HelmTrash.remove`
    /// says what that narrows and what it does not).
    ///
    /// It is the reading's parent: the level directly above the last component,
    /// links followed, when the kernel answers for it as a directory, and
    /// nothing otherwise.
    public static func ancestryIdentity(of path: String) -> AncestryIdentity? {
        reading(of: path).parent
    }

    /// The directory a path names, with the leaf resolved too.
    ///
    /// The other half of `resolvingAncestors`, and the difference is the whole
    /// reason both exist. A gate over *removal* leaves the leaf alone, because
    /// trashing a stale alias must remove the alias. A gate over *reading* has
    /// no such case: you cannot walk a link, only what it points at — and
    /// `FileManager.enumerator` handed a link to a directory yields nothing,
    /// which is how a moved `~/Downloads` came back as an empty scan recorded as
    /// «looked, and it was clean».
    ///
    /// Standardized **before** anything else: `URL(fileURLWithPath:)` resolves a
    /// relative path against the process's working directory, so canonicalizing
    /// first answers a question nobody asked. `ScanRoot.resolve` records what the
    /// `$HOME/link/.` spelling cost when the two steps were the other way round.
    ///
    /// Written twice before it moved here — the scan root gate and the duplicate
    /// finder's transit tier, which compare a stored path and a system folder
    /// against paths a walk produced, and are wrong in the same way if either
    /// side is left unresolved.
    public static func resolvingWholePath(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return URL(fileURLWithPath: standardized)
            .resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Where a path leads with every link in it followed — the leaf too, and a
    /// link whose target is not there yet.
    ///
    /// **`realpath` cannot answer for a link that points at nothing.**
    /// `resolvingSymlinksInPath()` is `realpath` underneath, it fails with
    /// `ENOENT` on such a link, and Foundation's answer to a failure is the path
    /// it was handed, unchanged — so `resolvingWholePath` above says «this is the
    /// place it names» about a name that is a link to somewhere else. A source
    /// planted as a link before its target is created is invisible to it, and
    /// creating the target afterwards is the second half of the same act.
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
    /// exists** — so it answers differently about a folder that has just been
    /// removed, and it asks the disk to find out. This is a fact about the two
    /// spellings, and it holds for a path that was never there.
    ///
    /// Internal rather than public: both callers are in this target. `ScanRoot`
    /// folds it away on both sides of a comparison, because an enumerator can
    /// hand back children spelled differently from the root it was given;
    /// `UserFileScope` needs the pair, because the *list* it tests against holds
    /// `/private/var/db` itself.
    static func withoutPrivate(_ path: String) -> String {
        path.utf8.starts(with: "/private/".utf8) ? String(path.dropFirst("/private".count)) : path
    }

    /// Whether the components `parts` of a path are those of `folder`, or begin
    /// with them, each pair compared without regard to case.
    ///
    /// The boot volume reads names that way, so a test on the exact string
    /// misses `/USR/bin`. Nor is `lowercased()` the fold it reads: it leaves a
    /// long s, U+017F, alone, which the volume reads as `s`, and
    /// `.caseInsensitive` folds it.
    static func isAtOrBelow(_ parts: [Substring], _ folder: [Substring]) -> Bool {
        parts.count >= folder.count
            && zip(parts, folder).allSatisfy { $0.compare($1, options: .caseInsensitive) == .orderedSame }
    }

    /// Whether a path begins with a prefix the kernel answers itself: `/.vol`,
    /// `/.nofollow` or `/.resolve`.
    ///
    /// - `/.vol`: the kernel answers `/.vol/<device>/<inode>` with the object
    ///   that pair identifies, a place named by number and not by name. Nothing
    ///   is mounted there; the comments call that prefix the mount.
    /// - `/.nofollow` and `/.resolve/<n>`: the kernel answers
    ///   `/.nofollow/<path>` and `/.resolve/<n>/<path>` with the object
    ///   `/<path>` names, or with an error where the prefix forbids the way
    ///   there (a link in `<path>`, under `/.nofollow`), and the path it returns
    ///   for that object keeps the prefix in front.
    ///
    /// A removal gate judges by names — a prefix, a depth, a suffix — and the
    /// first component of such a path is the name of no place the gate's tests
    /// can read, so both gates refuse it instead of judging what the string does
    /// not say, and before the kernel is asked (`readingForRemoval`).
    ///
    /// **The refusals do not rest on the same thing.** A name the reading makes
    /// of `/.nofollow/<path>` or `/.resolve/<n>/<path>` begins with the prefix
    /// and not with the first component of the object's own name, so no rule of
    /// either gate reads it as the place it is: that refusal closes a way round
    /// a protected place. The refusal of the mount is policy — a gate that
    /// judges by name does not accept a place named by number.
    /// `TheGatesRefuseAnObjectsOtherSpellingsTests` holds both gates' refusals.
    ///
    /// Both spellings are asked, the one given and the name the reading made of
    /// it (`readingForRemoval` hands it over without a `/private` in front),
    /// because a link to `/` in the middle of a path leaves the given one
    /// starting anywhere while the name starts in the prefix.
    /// Each is read left to right as typed, cut at the `/` byte: empty parts
    /// and `.` are dropped, a
    /// `..` pops only what stands before it, and the answer is `true` the moment
    /// the first component left at the root is a prefix, before a `..` that
    /// follows can pop it, because the kernel climbs a `..` after
    /// `/.vol/<device>/<inode>` through the real parents of that object and not
    /// through the components typed before it. The component is compared without
    /// regard to case rather than the string folded, which can change its
    /// length. A spelling that does not start at `/` is not read here: the
    /// reading gives one no name, and both gates refuse it for that.
    ///
    /// A spelling with no component that begins with a dot is answered without
    /// splitting it: each prefix, `.` and `..` begins with one.
    static func beginsWithAKernelPrefix(_ given: String, resolved: String) -> Bool {
        [given, resolved].contains { spelling in
            let bytes = spelling.utf8
            guard bytes.first == separator, zip(bytes, bytes.dropFirst()).contains(where: {
                $0.0 == separator && $0.1 == UInt8(ascii: ".")
            }) else { return false }
            var depth = 0
            for part in components(of: spelling) where part != "." {
                if part == ".." { depth = max(depth - 1, 0); continue }
                if depth == 0, kernelPrefixes.contains(where: {
                    part.compare($0, options: .caseInsensitive) == .orderedSame
                }) { return true }
                depth += 1
            }
            return false
        }
    }

    /// The first components of a path the kernel answers by device and inode,
    /// `.vol`, or with the object another path names, `.nofollow` and
    /// `.resolve`.
    private static let kernelPrefixes = [".vol", ".nofollow", ".resolve"]

    /// The path with every symlink in its parent chain resolved, and its last
    /// component put back untouched.
    ///
    /// A path that does not exist yet is still answered — the scan and the
    /// click are separated by however long the user takes — by resolving the
    /// deepest ancestor that does exist and re-appending the missing tail.
    public static func resolvingAncestors(_ path: String) -> String {
        // A relative path is handed back untouched. `URL(fileURLWithPath:)`
        // resolves one against the process's working directory, so resolving
        // first and validating afterwards silently promotes `""` and
        // `relative/path` to absolute paths a gate then approves — which is
        // exactly what happened the first time this was wired in. "Where does
        // it lead" is not a question a relative path has an answer to.
        guard path.hasPrefix("/") else { return path }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        guard standardized.path != "/" else { return standardized.path }

        let leaf = standardized.lastPathComponent
        var parent = standardized.deletingLastPathComponent()
        var missing: [String] = []
        while parent.path != "/", !FileManager.default.fileExists(atPath: parent.path) {
            let above = parent.deletingLastPathComponent()
            // Of a `/.file/id=…` string it cannot resolve, Foundation makes a
            // URL with an empty path, and the level above an empty path is the
            // empty path: the loop had no way out.
            guard above.path.utf8.count < parent.path.utf8.count else { return path }
            missing.append(parent.lastPathComponent)
            parent = above
        }
        var resolved = parent.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        resolved.appendPathComponent(leaf)
        return resolved.path
    }

    // MARK: - The reading

    /// What the kernel says a typed string names, read once: the string as it
    /// came in, the name the kernel gives what it names, whether a rule may
    /// judge that name, and who the object and the directory above it are.
    ///
    /// A gate that judges the letters of a path judges something the kernel
    /// does not read. The letters fold `..` where the kernel climbs the real
    /// parent of a link's target, they keep the case and the normalisation that
    /// were typed, and of a `/.file/id=…` string Foundation cannot resolve it
    /// makes a URL with an empty path. So nothing folds or expands the string —
    /// no `~`, no `standardizingPath`, no `URL`; only its trailing separators
    /// are taken off — and the kernel is asked what it names and what it calls
    /// it:
    ///
    /// - **A directory** is named by the path the kernel returns for it.
    /// - **Anything else that is there** — a file, a link, a socket — is named
    ///   by the path the kernel returns for the string less its last component,
    ///   links followed, plus that component as typed. The leaf is never
    ///   followed (`PathCanonical`'s doc comment says why), and a file is never
    ///   named by the path the kernel returns for the file itself.
    /// - **Nothing there**: the kernel is asked up the typed string, a level at
    ///   a time, until a directory answers, and the name is that directory's
    ///   path plus the rest of the string by its letters.
    struct Reading: Sendable {
        /// Whether `name` is one a rule about places may judge.
        enum Standing: Equatable, Sendable {
            /// Something is there, and `name` is the kernel's name for it.
            case object
            /// Nothing is there. Every level that did not answer said `ENOENT`,
            /// the level below the directory that answered is missing as itself
            /// and is no link to nothing, and what is left of the string has no
            /// `.` or `..` in it. `name` is where the string would lead.
            case nothingThere
            /// No rule may judge `name`: the string does not start at `/` or
            /// holds a NUL byte, its last component is `.` or `..`, a `.` or
            /// `..` stands in the part of it that is not there, the object has
            /// no type (a descriptor's entry under `/dev/fd`), the object is no
            /// directory and no directory answers above it (a file named by
            /// number, `/.vol/<device>/<inode>`), or the way there ends
            /// otherwise than in `ENOENT` — below a file, below a link to
            /// nothing, through a loop of links, past a level too long. The
            /// gates' entry gives it as well to a string that begins with a
            /// kernel prefix, as typed or as named (`readingForRemoval`).
            case noName
            /// A level answered `EACCES` or `EPERM`. Below a folder without the
            /// search bit the kernel answers the same for a child that is there
            /// and for one that is not, so this is never `nothingThere`.
            case noAccess
        }

        /// The string as it came in.
        let asked: String
        /// The name: as `Reading`'s doc comment says where the standing is
        /// `object` or `nothingThere`, and otherwise the deepest directory that
        /// answered plus the rest of the string, or the string itself.
        let name: String
        let standing: Standing
        /// Who is there, the link itself where the string names a link.
        let object: FileIdentity?
        /// The directory directly above the last component, links followed,
        /// where the kernel answered for it as a directory.
        let parent: AncestryIdentity?

        /// The name a gate's rules about places may judge, which only an object
        /// and a path to nothing have.
        var judgedName: String? {
            standing == .object || standing == .nothingThere ? name : nil
        }

        fileprivate static func unnamed(_ typed: String) -> Reading {
            Reading(asked: typed, name: typed, standing: .noName, object: nil, parent: nil)
        }
    }

    /// The reading a removal gate judges: `reading(of:)`, and no name for a
    /// string that begins with a kernel prefix — as typed, before the kernel is
    /// asked, and as named, after.
    ///
    /// Before, because the path the kernel returns behind `/.nofollow` and
    /// `/.resolve/<n>` keeps the prefix, so what would come back is no name of
    /// the object; such a reading holds no object, the kernel was not asked.
    /// After, because a name composed below a link to `/` starts in a prefix
    /// the typed string does not (`beginsWithAKernelPrefix` says how each is
    /// read).
    ///
    /// The name is tested without the `/private` in front of it
    /// (`withoutPrivate`), so a prefix behind `/private` is a prefix too. The
    /// kernel answers `/private/.vol/…` with `ENOENT`, which makes that string
    /// its own name, but where `/.vol/…` names an object `standardizingPath`,
    /// `resolvingSymlinksInPath`, `URL.standardizedFileURL` and
    /// `URL.resolvingSymlinksInPath()` give `/.vol/…` for it (`URL.standardized`
    /// and `URL.path` keep the string). This is a test of the letters of the
    /// kernel's own name, and it can only turn an answer false.
    static func readingForRemoval(_ typed: String) -> Reading {
        guard !beginsWithAKernelPrefix(typed, resolved: typed) else { return .unnamed(typed) }
        let read = reading(of: typed)
        guard beginsWithAKernelPrefix(typed, resolved: withoutPrivate(read.name)) else { return read }
        return Reading(asked: typed, name: read.name, standing: .noName,
                       object: read.object, parent: read.parent)
    }

    /// The reading of what `typed` names (`Reading` says what is asked).
    ///
    /// Each string the kernel is handed has had its trailing separators taken
    /// off, each level of the climb included: told not to follow a last link,
    /// the kernel follows it all the same when a separator comes after it.
    static func reading(of typed: String) -> Reading {
        guard typed.utf8.first == separator, !typed.utf8.contains(0) else { return .unnamed(typed) }
        let path = withoutTrailingSeparators(typed)
        let parts = components(of: path)
        // The typed string up to its first `count` components.
        func level(_ count: Int) -> String {
            count < parts.count
                ? withoutTrailingSeparators(String(Substring(path.utf8[..<parts[count].startIndex])))
                : path
        }

        let direct = ask(path, following: false)
        if let object = direct.answer {
            let above = ask(level(max(parts.count - 1, 0)), following: true).answer
                .flatMap { $0.isDirectory ? $0 : nil }
            let name = object.isDirectory
                ? object.path
                : above.flatMap { folder in parts.last.map { ScanPath.child(of: folder.path, name: String($0)) } }
            let named = name != nil && object.type != UInt32(VNON.rawValue)
                && !(parts.last.map(isDot) ?? false)
            return Reading(asked: typed, name: name ?? path, standing: named ? .object : .noName,
                           object: FileIdentity(device: object.deviceID, inode: object.fileID),
                           parent: above.map { AncestryIdentity(device: $0.deviceID, inode: $0.fileID) })
        }

        // Nothing answered as typed: up the string until a directory does. A
        // level longer than the kernel takes is not asked, so a long string
        // costs no ask per level; a level that answers and is no directory is
        // what the kernel calls `ENOTDIR` for everything below it.
        var errors = [direct.error]
        let fits = parts.prefix(while: {
            path.utf8.distance(from: path.utf8.startIndex, to: $0.endIndex) < Int(MAXPATHLEN)
        }).count
        var depth = min(parts.count - 1, fits)
        var top: Answer?
        while depth >= 0 {
            let above = ask(level(depth), following: true)
            if let answer = above.answer, answer.isDirectory { top = answer; break }
            errors.append(above.answer == nil ? above.error : ENOTDIR)
            depth -= 1
        }
        guard let top = top else { return .unnamed(typed) }
        // The first missing level is asked as itself: a link to nothing answers
        // there, and the string then names a place under the link's target, not
        // under the directory above.
        if errors.allSatisfy({ $0 == ENOENT }), depth + 1 < parts.count {
            let missing = ask(level(depth + 1), following: false)
            errors.append(missing.answer == nil ? missing.error : ENOTDIR)
        }
        let standing: Reading.Standing
        if errors.contains(where: { $0 == EACCES || $0 == EPERM }) {
            standing = .noAccess
        } else if errors.allSatisfy({ $0 == ENOENT }), !parts[depth...].contains(where: isDot) {
            standing = .nothingThere
        } else {
            standing = .noName
        }
        let tail = String(Substring(path.utf8[parts[depth].startIndex...]))
        return Reading(asked: typed, name: ScanPath.child(of: top.path, name: tail), standing: standing,
                       object: nil,
                       parent: depth == parts.count - 1
                           ? AncestryIdentity(device: top.deviceID, inode: top.fileID) : nil)
    }

    private static func isDot(_ part: Substring) -> Bool { part == "." || part == ".." }

    /// What the kernel answers for one path.
    private struct Answer {
        var device: dev_t = 0
        var type = UInt32(VNON.rawValue)
        var fileID: UInt64 = 0
        var path = ""

        var isDirectory: Bool { type == UInt32(VDIR.rawValue) }
        /// The device as `identity(of:)` spells it, sign kept.
        var deviceID: UInt64 { UInt64(bitPattern: Int64(device)) }
    }

    /// Room for the fields in front of the path and for the longest path the
    /// kernel returns.
    private static let answerSize = 2 * Int(MAXPATHLEN)

    /// One question to the kernel: the device, the type, the file id and the
    /// full path of what `path` names, the last link followed or not.
    ///
    /// `BulkWalk.entry(at:)`'s call with the attributes of a name in place of
    /// those of a weight, and the same parse: unaligned, in attribute bit
    /// order, each field only if the kernel says it returned it. The error is
    /// read beside the status, before anything else can set it.
    private static func ask(_ path: String, following: Bool) -> (answer: Answer?, error: Int32) {
        guard path.utf8.count < Int(MAXPATHLEN) else { return (nil, ENAMETOOLONG) }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_FILEID)
            | attrgroup_t(ATTR_CMN_FULLPATH)
        var buffer = [UInt8](repeating: 0, count: answerSize)
        let (status, error) = buffer.withUnsafeMutableBytes { raw -> (Int32, Int32) in
            let status = getattrlist(path, &request, raw.baseAddress, raw.count,
                                     following ? 0 : UInt32(FSOPT_NOFOLLOW))
            return (status, errno)
        }
        guard status == 0 else { return (nil, error) }
        return buffer.withUnsafeBytes { raw -> (answer: Answer?, error: Int32) in
            var field = MemoryLayout<UInt32>.size
            let returned = raw.loadUnaligned(fromByteOffset: field, as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size
            var answer = Answer()

            if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                answer.device = raw.loadUnaligned(fromByteOffset: field, as: dev_t.self)
                field += MemoryLayout<dev_t>.size
            }
            if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                answer.type = raw.loadUnaligned(fromByteOffset: field, as: fsobj_type_t.self)
                field += MemoryLayout<fsobj_type_t>.size
            }
            if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                answer.fileID = raw.loadUnaligned(fromByteOffset: field, as: UInt64.self)
                field += MemoryLayout<UInt64>.size
            }
            // No path returned is no answer: there is nothing to name it by.
            guard returned.commonattr & attrgroup_t(ATTR_CMN_FULLPATH) != 0 else { return (nil, ENOTSUP) }
            let reference = raw.loadUnaligned(fromByteOffset: field, as: attrreference_t.self)
            let start = field + Int(reference.attr_dataoffset)
            // The length counts the NUL that ends the path.
            let end = start + Int(reference.attr_length) - 1
            guard start <= end, end <= raw.count else { return (nil, ENAMETOOLONG) }
            answer.path = String(decoding: raw[start..<end], as: UTF8.self)
            return (answer, 0)
        }
    }
}
