import Foundation

/// Whether `ssh` will use a key, read off its mode — and the `chmod` that fixes
/// it when it will not.
///
/// This is the module's reason for existing on many Macs. `ssh` refuses a
/// private key that anyone but its owner can read, with a message that names
/// «UNPROTECTED PRIVATE KEY FILE» and stops; the fix is one `chmod` nobody
/// remembers the number for. A verdict plus a button is the whole feature.
///
/// **The directory matters as much as the file.** `~/.ssh` at 0755 is not
/// refused by `ssh` today, and `sshd` refuses an `authorized_keys` under one —
/// so the verdict is drawn for both, and the wording on screen says which is
/// which rather than lumping them together.
public enum KeyPermissions {

    /// What a mode comes to.
    public enum Verdict: Equatable, Sendable {
        case ok
        /// Too open, and what it should be. The number is carried rather than
        /// recomputed at the call site, because the caller that draws the
        /// sentence and the caller that runs the `chmod` must not disagree.
        case tooOpen(fix: mode_t)
    }

    /// **There is no masking here, and that is a measurement rather than an
    /// oversight.** The first draft had a `bits(_:)` helper that took
    /// `mode & 0o777` before every comparison, on the reasoning that `st_mode`
    /// carries `S_IFREG`/`S_IFDIR` in its high bits. Deleting it changed no
    /// answer in any test — because the type bits are `0o170000` and every
    /// question below is asked with `0o077` or `0o022`, which they do not
    /// touch. A helper whose removal changes nothing is a helper that was
    /// doing nothing, and a comment claiming it was load-bearing is worse
    /// than none: it tells the next reader a mask is required where it is not.

    /// A private key: readable and writable by its owner, by nobody else.
    /// 0600 is what `ssh-keygen` writes; 0400 is what a careful person writes,
    /// and `ssh` accepts it.
    public static func privateKey(_ mode: mode_t) -> Verdict {
        mode & 0o077 == 0 ? .ok : .tooOpen(fix: 0o600)
    }

    /// The directory: nobody but the owner may write it, because a directory
    /// somebody else can write is a directory somebody else can replace a key
    /// in. Group and other **read** is what `ssh` tolerates here and `sshd`
    /// does not, so the fix is the tighter one.
    public static func directory(_ mode: mode_t) -> Verdict {
        mode & 0o077 == 0 ? .ok : .tooOpen(fix: 0o700)
    }

    /// The public half is meant to be readable by anyone — it is public — so
    /// only writability by others is a fault.
    public static func publicKey(_ mode: mode_t) -> Verdict {
        mode & 0o022 == 0 ? .ok : .tooOpen(fix: 0o644)
    }
}
