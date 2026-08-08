import Foundation
import HelmRuntime

/// What the module believes about a timed session: how long one may be, what
/// happens when it runs out, and what the panel's "+15" asks for.
public enum TimerPolicy {
    public enum Action: Equatable, Sendable { case deactivate, continueAsAuto }
    /// On timer expiry: if an auto condition still holds and not suppressed, keep going as auto.
    public static func onExpiry(hasAutoCondition: Bool, suppressed: Bool) -> Action {
        (hasAutoCondition && !suppressed) ? .continueAsAuto : .deactivate
    }

    /// The longest session anything in this module can start, and so the longest
    /// one that can come back from the store.
    ///
    /// One ceiling for the whole module — the durations a person picks, the
    /// deadline found on disk, the countdown that is drawn — because "longer
    /// than a person could have asked for" is one question however the number
    /// arrives.
    public static let longestSessionMinutes = 24 * 60

    /// The same ceiling in seconds, which is the shape everything holding a
    /// deadline wants it in; `minutes * 60` was being spelled at each of them.
    public static let longestSession = TimeInterval(longestSessionMinutes * 60)

    /// The session the panel tile's "+15" asks for: what is left of the
    /// countdown, rounded up to the whole minute it shows, plus fifteen.
    ///
    /// Here rather than in the tile because the countdown is drawn from an
    /// `endDate` the engine restored from the store, which makes this
    /// arithmetic on a `Double` that came off disk. `Int(ceil(remaining / 60))`
    /// **traps** on anything past `Int.max` — the app terminating when somebody
    /// presses a button on a countdown they can see — and the sum can overrun
    /// what `startSession` will take.
    ///
    /// A remaining time no session could have produced is refused rather than
    /// brought down to the ceiling: it is not a long session, it is not a
    /// session, and the button then asks for its own fifteen minutes — the
    /// shortest answer, and one the person can see and change.
    public static func extendedMinutes(remaining: TimeInterval, adding minutes: Int) -> Int {
        // Both halves are inside the ceiling before they are added, so the sum
        // is arithmetic rather than a second overflow one layer along.
        let added = minutes.clamped(to: 0...longestSessionMinutes)
        guard remaining.isFinite, remaining >= 0, remaining <= longestSession else { return added }
        return (Int(ceil(remaining / 60)) + added).clamped(to: 0...longestSessionMinutes)
    }
}
