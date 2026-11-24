import Foundation

/// Writing a file that names somebody's files.
///
/// **The mode belongs to the write, not to the file.** `.atomic` writes a
/// temporary file and renames it over the target, so a fresh write takes its
/// mode from the process umask (0644 in a plain process). A missed
/// `setAttributes` on a file indexing every filename on a volume makes its
/// privacy an accident of the umask.
///
/// Directories have the matching trap one level up: the `attributes:` argument
/// applies only to directories *this call* creates, so a folder an earlier build
/// left at 0755 stays there for ever unless it is set again.
///
/// **Every call here answers, and none of them is `@discardableResult`**, so a
/// refusal cannot pass for a success by oversight. The package makes the
/// unused-result warning an error: use the answer, or discard it with `_ =`
/// and write beside it why the refusal does not matter there.
public enum PrivateFile {

    /// Encode, and write it the way `write(_ data:to:)` below does: into a file
    /// created 0600, renamed into place.
    ///
    /// - Returns: whether it landed. These files are caches, journals and
    ///   salts — a write that cannot happen is a missed optimisation, never a
    ///   reason to fail the work that asked for it — so the caller is told and
    ///   decides, rather than being thrown at.
    static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return write(data, to: url)
    }

    /// The folder first, then the file.
    ///
    /// Both answers spent on one, because they are one question: a folder that
    /// could not be made is a write that cannot land, so `&&` short-circuits and
    /// the caller has a single thing to decide about.
    ///
    /// `HelmLog.append` keeps its own pair: it makes the folder once and writes
    /// in either of two branches, so there is no one answer to share.
    public static func writeMakingTheFolder<T: Encodable>(_ value: T, at url: URL) -> Bool {
        return directory(at: url.deletingLastPathComponent()) && write(value, to: url)
    }

    /// The same for bytes that are not JSON.
    public static func writeMakingTheFolder(_ data: Data, at url: URL) -> Bool {
        return directory(at: url.deletingLastPathComponent()) && write(data, to: url)
    }

    /// The same for bytes that are not JSON — the log's redaction salt among them.
    static func write(_ data: Data, to url: URL) -> Bool {
        let path = url.path
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

    /// The inode the bytes go into: 0600 from the `open` that makes it, beside
    /// the file it is about to become.
    ///
    /// `Data.write` with `.atomic` creates its temporary with the process umask
    /// on it, so the bytes would lie readable by anything running as this user
    /// until a later `setAttributes`. A 0700 folder above is a second defence,
    /// and covers nothing the day a caller writes into a folder somebody else
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
    /// A function of its own, and not `private`, so «the mode arrives with the
    /// file» can be asserted (`TheModeBelongsToTheWriteTests`).
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
    /// the day it was created (Architecture/DiagnosticsLog.md § Diagnostics log).
    /// Called once at launch, never per line.
    ///
    /// - Returns: whether there was a file to tighten. Absent is not a failure —
    ///   the log is hardened before anything has been written to it.
    static func harden(at url: URL) -> Bool {
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
    static func directory(at url: URL) -> Bool {
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
