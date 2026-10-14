import Foundation

/// Writing a file that names somebody's files.
///
/// **Three places did this by hand and each carried a comment naming the other
/// two** — the scan journal, the disk scan's cache and the duplicate finder's
/// digest cache. A comment that names its own duplicates is the duplication
/// confessing.
///
/// What they were all working around: **the mode belongs to the write, not to
/// the file.** `.atomic` writes a temporary file and renames it over the
/// target, so a fresh write takes its mode from the process umask and a rewrite
/// takes it from the file it replaced — measured at 0644 both ways in a plain
/// process. A single missed `setAttributes` in a file holding an index of every
/// filename on a volume makes the privacy of that list an accident of whichever
/// umask the app happened to run under.
///
/// Directories have the matching trap one level up: the `attributes:` argument
/// applies only to directories *this call* creates, so a folder an earlier build
/// left at 0755 stays there for ever unless it is set again.
///
/// **Every call here answers, and none of them is `@discardableResult`.** It
/// was, on all four, and eight callers took the invitation — the tree Disk
/// reopens on, the salt the log's tags are derived from, the note that says an
/// update is in flight, the scan journal, the digest cache, a marker and the log
/// itself. A refusal that is not a success is a defect this house already names
/// for `pmset`, for `launchctl` and for a removal that got no answer; it had
/// simply not reached the filesystem, because `write(x, to: y)` and
/// `_ = write(x, to: y)` differ by four characters and nothing could tell a
/// decision from an oversight. So the compiler objects now, and
/// `ARefusalFromTheDiskIsNotASuccessTests` reads `Sources` for the rest: use the
/// answer, or discard it with `_ =` and write beside it why the refusal does not
/// matter there.
public enum PrivateFile {

    /// **What a symlink at the destination means to this write**, which is a
    /// question the caller owns and no default can answer for both kinds of
    /// file this app writes.
    ///
    /// An atomic write is a temporary file `rename`d over the destination, and
    /// `rename` replaces the *name*. For Helm's own caches and journals that is
    /// exactly right — a link planted where a cache goes is not an arrangement
    /// to honour, and replacing the name is what stops a write being redirected
    /// out of the support folder. For a file that belongs to the person it is
    /// wrong in a way nothing reports: `~/.ssh/config` is very often a link
    /// into a dotfiles checkout, and the first Apply turned it into an ordinary
    /// file — the checkout kept the old text, `git status` said nothing, and
    /// every later edit there silently stopped reaching `ssh`.
    ///
    /// **A hard link is the other half of the same question and answers the
    /// other way.** A second name for one inode is not a redirection anybody
    /// arranged and no resolution can see it, so the rename stays a rename:
    /// `.theName` and `.whatItLeadsTo` both write through a new inode at the
    /// name they end on, and neither ever writes into a file a hard link
    /// reaches out of the home directory.
    public enum Destination: Sendable {
        /// The name is the file. A symlink there is replaced by this write.
        case theName
        /// The name may only point at the file, and then the file is the
        /// target. The folders above the name are read as the kernel reads them,
        /// and the name is then followed link by link to its end, a link whose
        /// target is not there yet too, so the link survives the write and what
        /// it points at receives it. A loop of links, a chain too long to
        /// follow, a folder that is not there (a link in the middle of the path
        /// that points at nothing too) and a link whose text ends in `.`, `..` or a
        /// slash lead to no file to write: the write is refused and the link
        /// stays as it was.
        case whatItLeadsTo
    }

    /// Encode, and write it the way `write(_ data:to:)` below does: into a file
    /// created 0600, renamed into place.
    ///
    /// - Returns: whether it landed. These files are caches, journals and
    ///   salts — a write that cannot happen is a missed optimisation, never a
    ///   reason to fail the work that asked for it — so the caller is told and
    ///   decides, rather than being thrown at. Deciding is not optional: see the
    ///   type's own note above.
    public static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return write(data, to: url)
    }

    /// The folder first, then the file.
    ///
    /// **Six call sites had spelled this pair out, and each carried the same
    /// comment explaining the `&&`** — Disk's saved tree, the Duplicates digest
    /// cache, the Homebrew and VPN markers, the log's salt and the update note.
    /// That is the shape this whole type was extracted for the first time: the
    /// note at the top of the file says three places hand-rolled the write and
    /// each named the other two. A pairing repeated six times under one repeated
    /// sentence is the same confession.
    ///
    /// Both answers spent on one, because they are one question: a folder that
    /// could not be made is a write that cannot land, so `&&` short-circuits and
    /// the caller has a single thing to decide about.
    ///
    /// `HelmLog.append` keeps its own pair and is not a seventh: it makes the
    /// folder once and then writes in either of two branches, so there is no one
    /// answer for the two to share.
    public static func writeMakingTheFolder<T: Encodable>(_ value: T, at url: URL) -> Bool {
        return directory(at: url.deletingLastPathComponent()) && write(value, to: url)
    }

    /// The same for bytes that are not JSON.
    public static func writeMakingTheFolder(_ data: Data, at url: URL) -> Bool {
        return directory(at: url.deletingLastPathComponent()) && write(data, to: url)
    }

    /// The same for bytes that are not JSON — the log's redaction salt, and the
    /// two files in `~/.ssh` that may be links into somebody's dotfiles.
    ///
    /// With `.whatItLeadsTo` the scratch inode is born beside the file the link
    /// leads to, not beside the link, and that file's folder has to exist: a
    /// refusal there leaves the link alone, which a rename onto the link's own
    /// name would not. The bytes land in the file the kernel reaches through the
    /// link, or the write is refused — except for a chain the kernel refuses as
    /// too long, which `linkHops` can still follow (its own comment says why).
    public static func write(_ data: Data, to url: URL,
                             destination: Destination = .theName) -> Bool {
        let path: String
        switch destination {
        case .theName: path = url.path
        case .whatItLeadsTo:
            guard let leads = whereTheKernelFollows(url.path) else { return false }
            path = leads
        }
        guard let scratch = bornPrivate(beside: path) else { return false }
        do {
            let file = FileHandle(fileDescriptor: scratch.descriptor, closeOnDealloc: true)
            try file.write(contentsOf: data)
            try file.close()
            // The rename an atomic write does, spelled out — because the
            // *creation* above is the half `Data.write(options: .atomic)` does
            // not let anybody choose. `rename` moves this inode, and its mode,
            // on to the name.
            guard rename(scratch.path, path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(atPath: scratch.path)
            return false
        }
        return true
    }

    /// How many links at the name `whereTheKernelFollows` follows before it
    /// takes the chain for a loop. `getconf SYMLOOP_MAX` answers 32 on this
    /// system; no header of the SDK defines `SYMLOOP_MAX`, and the SDK's
    /// sys/param.h has the kernel's own `MAXSYMLINKS`, 32 as well. The kernel
    /// counts every link of the path against its limit, the links in the
    /// folders above the name too; this counts only the links at the name, so
    /// a chain under a folder that is itself a link can be followed here and
    /// refused by the kernel.
    private static let linkHops = 32

    /// The file a name leads to, followed one link at a time: the folder above
    /// the name, then the name in it, then the text of the link if it is one.
    ///
    /// **The folder comes from the kernel, never from the letters of a path.**
    /// The kernel follows a link before a `..` that comes after it, so in `d/../t`
    /// with `d` a link to `p/q` the file is `p/t`, while folding the `..` by its
    /// letters gives `t` beside `d` — a place no gate that asked the kernel judged.
    /// `realpath` is the kernel's reading of a folder that is there; a folder that
    /// is not there, or that a link in the middle of its path leads nowhere, has
    /// no such reading and the answer is `nil`. A name with nothing at it yet ends
    /// the walk, spelled in the folder the kernel reads, whether it was handed in
    /// or reached through a link, and the bytes are written there.
    ///
    /// `nil` also for a name that is still a link after `linkHops` hops (a loop
    /// looks like that), and for a name that ends in nothing, `.` or `..` — there
    /// is no file to put bytes in.
    ///
    /// Private, and not a resolver for anybody else: it answers what a write needs
    /// and nothing a gate could judge by.
    private static func whereTheKernelFollows(_ start: String) -> String? {
        var name = start
        for _ in 0...linkHops {
            let slash = name.lastIndex(of: "/")
            let leaf = slash.map { String(name[name.index(after: $0)...]) } ?? name
            guard !leaf.isEmpty, leaf != ".", leaf != ".." else { return nil }
            var folder = slash.map { String(name[..<$0]) } ?? "."
            if folder.isEmpty { folder = "/" }
            guard let real = realpath(folder, nil) else { return nil }
            defer { free(real) }
            let there = String(cString: real)
            name = there == "/" ? "/" + leaf : there + "/" + leaf
            var info = stat()
            guard lstat(name, &info) == 0, info.st_mode & S_IFMT == S_IFLNK else { return name }
            guard let link = try? FileManager.default.destinationOfSymbolicLink(atPath: name),
                  !link.isEmpty else { return nil }
            name = link.hasPrefix("/") ? link : (there == "/" ? "/" : there + "/") + link
        }
        return nil
    }

    /// The inode the bytes go into: 0600 from the `open` that makes it, beside
    /// the file it is about to become.
    ///
    /// **This is the repair of 2026-09-08, and the window it closes is the one
    /// this whole type was written to close, one level down.** `Data.write` with
    /// `.atomic` writes a temporary file and renames it, and the temporary is
    /// created with the process umask on it — 0644 here. So the bytes lay in the
    /// destination folder readable by anything running as this user for the
    /// length of the write, and then under the destination *name* until the
    /// `setAttributes` that used to follow. Nothing was reported and nothing
    /// looked wrong: `PrivateFile.directory` makes the folder above 0700, which
    /// covers it — a second defence standing in for a missing first one, and it
    /// covers nothing at all the day a caller writes into a folder somebody else
    /// made.
    ///
    /// `O_EXCL` because the name is ours or the write does not happen: an
    /// attacker who can guess it must not be able to have it point somewhere
    /// first. `fchmod` on the descriptor rather than a `chmod` on the path,
    /// because the umask can only take bits away from the mode `open` was given
    /// and a hostile one (0o200) would leave a file this process cannot write —
    /// on the descriptor there is no name to race, and it happens before the
    /// file has a byte in it or the name it will end on.
    ///
    /// The caller owns the descriptor from here: it is closed by the
    /// `FileHandle` above on the way out of either branch.
    ///
    /// Not `private`, and that is the only reason it is a function of its own:
    /// «the mode arrives with the file» is the whole claim of this repair, and a
    /// claim inside a `do` block cannot be asserted about. `TheModeBelongsToTheWriteTests`
    /// names it.
    static func bornPrivate(beside path: String) -> (descriptor: Int32, path: String)? {
        let folder = (path as NSString).deletingLastPathComponent
        let scratch = (folder as NSString)
            .appendingPathComponent(".helm-write-\(UUID().uuidString)")
        let descriptor = open(scratch, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else { return nil }
        guard fchmod(descriptor, 0o600) == 0 else {
            close(descriptor)
            try? FileManager.default.removeItem(atPath: scratch)
            return nil
        }
        return (descriptor, scratch)
    }

    /// 0600 on a file that is already there, without rewriting it.
    ///
    /// For the one file this app **appends** to rather than replaces: the log
    /// never passes through `write`, so its mode is whatever the umask gave it
    /// the day it was created — measured 0644 on the machine it was found on,
    /// where ARCHITECTURE.md § Diagnostics log says 0700 and the folder was
    /// doing all the work. Called once at launch, never per line: the mode of an
    /// open file is not a question worth asking of every write to it.
    ///
    /// - Returns: whether there was a file to tighten. Absent is not a failure —
    ///   the log is hardened before anything has been written to it.
    public static func harden(at url: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return false }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    /// Create at 0700, and re-apply it to what was already there.
    ///
    /// - Returns: whether there is a private directory there now. A caller that
    ///   is about to write into it usually spends this on the write's own answer
    ///   — a folder that could not be made is a write that cannot land — which
    ///   is why so many sites read `directory(at:) && write(…)`.
    public static func directory(at url: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return true
    }
}
