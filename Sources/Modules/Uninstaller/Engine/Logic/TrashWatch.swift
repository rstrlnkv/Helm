import Foundation

/// What the Trash-offer switch is actually doing, as against what it says.
///
/// Two things can make «on» false: FSEvents refusing the stream, and the Full
/// Disk Access every local install takes away
/// (Architecture/Release.md § Signing and grants). A stored flag alone would
/// stand in for those live facts (Architecture/TheGates.md § The gates).
///
/// One value rather than three booleans: `on: false` with `watching: true` is
/// a state nothing can produce, and a struct of flags invites writing it down.
/// Every reading comes from `state(...)`.
public enum TrashWatch: String, Sendable, CaseIterable {
    /// Nobody asked for the offer.
    case off
    /// On, and nothing is known against it.
    case on
    /// On, and the Trash itself could not be read (Full Disk Access, almost
    /// always), from a real refused read rather than a probe of the grant.
    case cannotReadTrash
    /// On, and FSEvents refused the stream, so no change will ever arrive. The
    /// watcher is rebuilt on the next `activate`; there is nothing for a person to
    /// press.
    case notWatching

    /// Whether the person asked for the offer, which is what the switch draws.
    public var isOn: Bool { self != .off }

    /// The state from the three things that decide it.
    ///
    /// `nil` for either fact means "no answer yet, and nothing against it": both
    /// answers arrive a moment later, and an unknown read as a failure would show
    /// a permission note to everybody who has just turned the switch on.
    static func state(on: Bool, watching: Bool?, trashReadable: Bool?) -> TrashWatch {
        guard on else { return .off }
        // A stream that never started is the stronger fact: with nothing watching,
        // whether the Trash reads decides nothing.
        guard watching != false else { return .notWatching }
        return trashReadable == false ? .cannotReadTrash : .on
    }
}
