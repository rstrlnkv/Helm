import Foundation

/// Whether what a background scan found is worth interrupting somebody for.
///
/// Three modules walk the volume twice a day and the whole product of it was a
/// relative date on a settings page: `ScanJournal.change(module:)` computed the
/// delta and nothing in `Sources/` called it. This is the half that was missing,
/// and it is pure for the usual reason — every refusal below is a banner
/// somebody would otherwise have been shown for nothing, and each is a test
/// rather than an argument.
///
/// **It answers about the delta, never about the finding.** A scan's total is
/// the same 40 GB every morning; saying it again is «we looked», which is not
/// news and is exactly the sentence that teaches a person to turn a channel off.
public enum ScanNews {

    /// Below this, an appearance is the disk working rather than something that
    /// happened. A gigabyte between two scans of the same folder is a download,
    /// an unpacked archive or a virtual machine — something with a cause the
    /// person can name — and a hundred megabytes is not.
    public static let floorBytes = 1_000_000_000

    /// What a banner may say, in the two numbers every module can answer for.
    ///
    /// Deliberately not words. `L()` lives in `HelmUI`, which no engine may
    /// import and which this target sits below; the sentence is written by
    /// whoever draws it, from these.
    public struct Finding: Equatable, Sendable {
        /// How many items appeared or grew since the previous scan.
        public let count: Int
        /// What they add together: a new item whole, a grown one by its growth.
        public let bytes: Int

        public init(count: Int, bytes: Int) {
            self.count = count
            self.bytes = bytes
        }
    }

    /// The delta a banner may be posted about, or nil for silence.
    ///
    /// **A first scan is silent**, and that is `hadPrevious` doing the work it
    /// exists for: the journal refuses to invent a previous list, so the whole
    /// of a full disk would otherwise arrive as news the first time a module
    /// ever ran.
    ///
    /// **Space that *went* is silent too.** The floor is asked of what appeared
    /// and of what grew, never of what went, so somebody who emptied their
    /// Downloads folder is not congratulated for it by an app that had nothing
    /// to do with it — a rule written against `ScanChange.isSomething` gets that
    /// case wrong.
    ///
    /// **A path on both sides is measured by its difference.** The journal's
    /// identity is path and size, so a folder that grew a megabyte sits in both
    /// `appeared` and `went`, and its whole new size in `appearedBytes` would
    /// announce six gigabytes of a folder that gained one. Here such a path
    /// counts once, by what it grew, and a path that shrank counts nothing and
    /// takes nothing off what else appeared. A path with no earlier size, in
    /// `went` or `stayed`, is new and counts whole. The pairing is by path
    /// here rather than a property of `ScanChange` because only the banner asks
    /// the question; the journal keeps both sizes whole. A path repeated with
    /// two sizes in one list is one item at its largest size on each side.
    ///
    /// There is deliberately no `startedByHand` parameter. The journal has one
    /// writer, `ScanCoordinator`, and it is the unattended path — so anything
    /// read back out of it is by construction about work nobody watched, and a
    /// flag standing in for a fact the structure already guarantees is the shape
    /// this codebase keeps paying for.
    public static func finding(in change: ScanChange, floor: Int = floorBytes) -> Finding? {
        guard change.hadPrevious else { return nil }
        let news = measured(change)
        guard news.bytes >= floor else { return nil }
        return news
    }

    /// What appeared, with each path that was already there counted by its growth.
    private static func measured(_ change: ScanChange) -> Finding {
        func largest(_ items: [ScanItem]) -> [String: Int] {
            items.reduce(into: [:]) { $0[$1.path] = max($0[$1.path] ?? 0, $1.bytes) }
        }
        let before = largest(change.went + change.stayed)
        var count = 0
        var bytes = 0
        for (path, now) in largest(change.appeared) {
            let grew = now - (before[path] ?? 0)
            guard grew > 0 || before[path] == nil else { continue }
            count += 1
            bytes += grew
        }
        return Finding(count: count, bytes: bytes)
    }
}
