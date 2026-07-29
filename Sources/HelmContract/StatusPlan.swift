import Foundation

/// Which module's appearance the menu bar draws, and whether it moves.
///
/// Pulled out of `StatusItemController` so it can be asked questions without a
/// status bar, a run loop or a real module. It lives beside `StatusAppearance`
/// rather than in `HelmRuntime` because `HelmRuntime` does not depend on
/// `HelmContract`, and one decision function is not worth that edge.
public enum StatusPlan {
    /// How long a spin lasts. The module that asks for one uses this to compute
    /// `spinUntil`; the host needs it to know which frame belongs to now. One
    /// number, so the two cannot drift.
    public static let spinDuration: TimeInterval = 1.2

    /// A module whose spin is still running takes the icon; otherwise the first
    /// module that tints it, which is the rule that was always here. A spin
    /// lasts about a second and ends by itself, so the borrow is brief.
    ///
    /// When two spins overlap the **newest** wins, which is why this is a `max`
    /// and not a `first`. Taking the first would settle the question by
    /// `ModuleOrder` — a module's own feedback would sit invisible behind an
    /// unrelated module that happened to sort earlier, which is the failure a
    /// spin borrowing the icon at all exists to prevent, one level up. The
    /// newest spin also ends last, so deferring to it truncates nothing.
    public static func choose(_ appearances: [StatusAppearance], now: Date) -> StatusAppearance {
        let spinEnd = { (a: StatusAppearance) in a.spinUntil ?? .distantPast }
        if let newest = appearances.filter({ spinEnd($0) > now }).max(by: { spinEnd($0) < spinEnd($1) }) {
            return newest
        }
        return appearances.first { $0.tintToken != nil } ?? .inactive
    }

    /// Whether the chosen appearance should actually move right now.
    public static func spins(_ appearance: StatusAppearance,
                             now: Date, reduceMotion: Bool) -> Bool {
        guard !reduceMotion else { return false }
        // A countdown owns this ring while it runs.
        guard appearance.timerProgress == nil else { return false }
        return (appearance.spinUntil ?? .distantPast) > now
    }
}
