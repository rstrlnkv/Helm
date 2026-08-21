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
        /// target. Every symlink in the path is resolved first, so the link
        /// survives the write and what it points at receives it.
        case whatItLeadsTo
    }

    /// Encode, write atomically, set 0600.
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
    public static func write(_ data: Data, to url: URL,
                             destination: Destination = .theName) -> Bool {
        let path: String
        switch destination {
        case .theName: path = url.path
        case .whatItLeadsTo: path = PathCanonical.resolvingWholePath(url.path)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return false
        }
        // Every write. The file this replaced may have been private; the one
        // that just took its place is a different inode with the umask's mode.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: path)
        return true
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
