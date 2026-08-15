import Foundation

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
/// **No cache from before the press, ever, on this path.** That is the whole
/// point: a digest older than the offer is exactly what this exists to
/// distrust. The one memo `Batch` keeps — the survivor's reading, taken from
/// disk inside the same removal — is bounded by the press itself; its comment
/// says why that is not the cache this rule refuses.
enum DuplicateVerification {

    enum Verdict: Equatable, Sendable {
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

    /// One pair, read fresh on both sides — `Batch` with a memo nobody shares.
    static func verify(remove: String, keep: String) -> Verdict {
        Batch().verify(remove: remove, keep: keep)
    }

    /// One removal's verifications, with the survivor read once per batch.
    ///
    /// A group of N copies names the same survivor N−1 times, and reading it
    /// fresh for every pair re-hashed one unchanging file N−1 times — tens of
    /// seconds on a real video group, for readings that could only ever agree
    /// with each other.
    ///
    /// **What is memoised, and why it does not weaken the check.** Only the
    /// *surviving* copy's reading — inode, size, digest — and only for the life
    /// of one `Batch`, which one `trash` call creates and drops. The copy being
    /// removed is read from disk in full on every call, always: that is the
    /// guarantee the module advertises, and it is about the file whose contents
    /// are about to stop existing anywhere else. The survivor stays on disk
    /// whatever happens, so the freshness its reading needs is "within the
    /// operation the person pressed the button for" — the memo's first pair
    /// reads it from disk inside this same removal, seconds at most before the
    /// last pair asks. The cache the doc comment above refuses is the *scan's*
    /// — a digest older than the offer, standing in for a file nobody re-read —
    /// and nothing here outlives the press.
    /// `@unchecked Sendable` because the engine's default `verifying` closure
    /// is `@Sendable` and captures one: the memo is mutated from the one serial
    /// loop of the removal that made it, which the compiler cannot see.
    /// A survivor's one reading — or the fact that it could not be taken,
    /// remembered so an unreadable survivor is not retried per copy.
    private enum Survivor {
        case unreadable
        case read(fileNumber: UInt64?, bytes: Int, digest: String)
    }

    final class Batch: @unchecked Sendable {
        private var survivors: [String: Survivor] = [:]
        private let hash: (_ path: String, _ expecting: Int) -> String?

        /// `hash` is injectable so a test can count which paths were read —
        /// "the survivor is read once" is a claim about calls, not about time.
        /// The default is the search's own hasher: a verification that hashes
        /// differently verifies something else.
        init(hash: @escaping (_ path: String, _ expecting: Int) -> String? = {
            DuplicateScanner.hash($0, limit: nil, expecting: $1)
        }) {
            self.hash = hash
        }

        /// Reads the pair and compares — the removed side in full from disk,
        /// the surviving side through the batch's one reading of it.
        ///
        /// Full, not the prefix: the prefix hash exists to *thin the field*
        /// cheaply during a search, and two files agreeing on their first
        /// 128 KB is the reason to look further rather than a reason to delete
        /// one of them.
        ///
        /// A size difference short-circuits the read — two files of unequal
        /// length cannot hold the same bytes, and this is the common case when
        /// something has been edited.
        func verify(remove: String, keep: String) -> Verdict {
            guard let removeAttributes = try? FileManager.default
                .attributesOfItem(atPath: remove)
            else { return .unreadable }
            guard case .read(let keepFileNumber, let keepBytes, let keepDigest)
                    = reading(of: keep)
            else { return .unreadable }

            // The same file under two names is not a duplicate pair at all,
            // and trashing "one of them" would remove the only copy.
            // `FileFacts` carries the inode for this reason during a search;
            // here the two paths arrive alone, so it is asked directly.
            if let a = removeAttributes[.systemFileNumber] as? UInt64,
               let b = keepFileNumber, a == b {
                return .changed
            }

            guard let removeBytes = removeAttributes[.size] as? Int
            else { return .unreadable }
            guard removeBytes == keepBytes else { return .changed }

            guard let digest = hash(remove, removeBytes) else { return .unreadable }
            return digest == keepDigest ? .identical : .changed
        }

        private func reading(of keep: String) -> Survivor {
            if let cached = survivors[keep] { return cached }
            let fresh = readSurvivor(keep)
            survivors[keep] = fresh
            return fresh
        }

        private func readSurvivor(_ keep: String) -> Survivor {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: keep),
                  let bytes = attributes[.size] as? Int,
                  let digest = hash(keep, bytes)
            else { return .unreadable }
            return .read(fileNumber: attributes[.systemFileNumber] as? UInt64,
                         bytes: bytes, digest: digest)
        }
    }
}
