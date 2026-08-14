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
public enum PrivateFile {

    /// Encode, write atomically, set 0600.
    ///
    /// - Returns: whether it landed. These files are caches, journals and
    ///   salts — a write that cannot happen is a missed optimisation, never a
    ///   reason to fail the work that asked for it — so the caller is told and
    ///   decides, rather than being thrown at.
    @discardableResult
    public static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return write(data, to: url)
    }

    /// The same for bytes that are not JSON — the log's redaction salt.
    @discardableResult
    public static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        // Every write. The file this replaced may have been private; the one
        // that just took its place is a different inode with the umask's mode.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
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
    @discardableResult
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
    @discardableResult
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
