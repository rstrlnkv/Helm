import Foundation

/// What the Trash-offer switch is actually doing, as against what it says.
///
/// **The switch reported itself on with no channel from either thing that can
/// make that false.** `FolderWatcher.start` discarded `FSEventStreamStart`'s
/// return and gave up silently when `FSEventStreamCreate` answered nil, and the
/// feature needs Full Disk Access to see anything at all — which every local
/// install takes away again (CLAUDE.md). So «trash offer switched on» reached the
/// log, and the row said on, whether or not anything was watching a Trash Helm
/// could read. That is the family named on 2026-08-12: a local flag standing in
/// for a live external fact, with no reverse channel from the port that knows.
///
/// One value rather than three booleans beside each other, for the reason
/// `HelmRemovalOutcome.verdict` gives about its own fourth case: `on: false` with
/// `watching: true` is a state nothing can produce, and a struct of flags is an
/// invitation to write it down. Every reading here comes from `state(...)`.
public enum TrashWatch: String, Codable, Sendable, CaseIterable {
    /// Nobody asked for the offer.
    case off
    /// On, and nothing is known against it.
    case on
    /// On, and the Trash itself could not be read — which is Full Disk Access
    /// almost every time, and the reading that says so is a real refused read
    /// rather than a probe of the grant.
    case cannotReadTrash
    /// On, and FSEvents refused the stream, so no change will ever arrive. The
    /// watcher is rebuilt on the next `activate`; there is nothing for a person to
    /// press.
    case notWatching

    /// Whether the person asked for the offer, which is what the switch draws.
    public var isOn: Bool { self != .off }

    /// The state from the three things that decide it.
    ///
    /// `nil` for either fact means "no answer yet, and nothing against it" — the
    /// watcher's own answer arrives on its queue a moment after it is asked, and
    /// the Trash read is answered by the switch's own press and by every sweep
    /// after it. Treating an unknown as a failure would put a permission note on
    /// the screen of everybody who has just turned the switch on.
    public static func state(on: Bool, watching: Bool?, trashReadable: Bool?) -> TrashWatch {
        guard on else { return .off }
        // A stream that never started is the stronger fact: with nothing watching,
        // whether the Trash reads decides nothing.
        guard watching != false else { return .notWatching }
        return trashReadable == false ? .cannotReadTrash : .on
    }
}
