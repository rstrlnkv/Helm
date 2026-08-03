import Foundation
import HelmRuntime

/// Is this pair still what the scan said it was?
///
/// **Why anything asks.** The offer on screen is always older than the press
/// that acts on it. Today that gap is minutes — a scan at 14:00, «Освободить»
/// at 14:05 — and the engine trashes on the strength of the older reading. A
/// background scan widens the gap to a day, and a hash cache widens it again by
/// letting yesterday's digest stand in for today's file.
///
/// The cost of being wrong here is not an inaccurate figure. Two files declared
/// identical when they are no longer identical means one of them goes to the
/// Trash and its contents are not preserved anywhere else. So the pair is read
/// again, from disk, immediately before anything moves — a handful of files
/// rather than the 70 GB a full search reads, which is a fraction of a second.
///
/// **No cache, ever, on this path.** That is the whole point: a cached digest is
/// exactly what this exists to distrust.
public enum DuplicateVerification {

    public enum Verdict: Equatable, Sendable {
        /// Both files are still there and still identical. The removal may go
        /// ahead.
        case identical
        /// They differ now. Whatever the scan saw, it is not true any more.
        case changed
        /// One of them could not be read — it moved, it vanished, permission
        /// was withdrawn. Not a licence to delete: an answer that could not be
        /// obtained is not an answer in favour.
        case unreadable
    }

    /// Reads both files in full and compares.
    ///
    /// Full, not the prefix: the prefix hash exists to *thin the field* cheaply
    /// during a search, and two files agreeing on their first 128 KB is the
    /// reason to look further rather than a reason to delete one of them.
    ///
    /// A size difference short-circuits the read — two files of unequal length
    /// cannot hold the same bytes, and this is the common case when something
    /// has been edited.
    public static func verify(remove: String, keep: String) -> Verdict {
        // The same file under two names is not a duplicate pair at all, and
        // trashing "one of them" would remove the only copy. `FileFacts`
        // carries the inode for this reason during a search; here the two paths
        // arrive alone, so it is asked directly.
        let fm = FileManager.default
        guard let removeAttributes = try? fm.attributesOfItem(atPath: remove),
              let keepAttributes = try? fm.attributesOfItem(atPath: keep)
        else { return .unreadable }

        if let a = removeAttributes[.systemFileNumber] as? UInt64,
           let b = keepAttributes[.systemFileNumber] as? UInt64, a == b {
            return .changed
        }

        guard let removeBytes = removeAttributes[.size] as? Int,
              let keepBytes = keepAttributes[.size] as? Int
        else { return .unreadable }
        guard removeBytes == keepBytes else { return .changed }

        guard let a = DuplicateScanner.hash(remove, limit: nil, expecting: removeBytes),
              let b = DuplicateScanner.hash(keep, limit: nil, expecting: keepBytes)
        else { return .unreadable }
        return a == b ? .identical : .changed
    }
}
