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
        /// How many items appeared since the previous scan.
        public let count: Int
        /// What they weigh together — the appeared list's own total.
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
    /// alone, so somebody who emptied their Downloads folder is not congratulated
    /// for it by an app that had nothing to do with it — a rule written against
    /// `ScanChange.isSomething` gets that case wrong.
    ///
    /// There is deliberately no `startedByHand` parameter. The journal has one
    /// writer, `ScanCoordinator`, and it is the unattended path — so anything
    /// read back out of it is by construction about work nobody watched, and a
    /// flag standing in for a fact the structure already guarantees is the shape
    /// this codebase keeps paying for.
    public static func finding(in change: ScanChange, floor: Int = floorBytes) -> Finding? {
        guard change.hadPrevious else { return nil }
        let bytes = change.appearedBytes
        guard bytes >= floor else { return nil }
        return Finding(count: change.appeared.count, bytes: bytes)
    }
}
