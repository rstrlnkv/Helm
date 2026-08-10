import Foundation

/// What the top of the page is showing, and therefore what it offers to do.
///
/// The page used to open with three metric cells — `OFF · — · 0` before
/// anything is configured — and not one control that could start or stop a
/// session: the screen that reported the state was the only screen that could
/// not change it. Two of those three cells were unreadable figures, which the
/// house's own rule says are not drawn at all.
///
/// Four states rather than a `Bool` and some optionals, because each one wants
/// different verbs: nothing running offers durations; a countdown offers more
/// time and an end; a session with no deadline offers only an end; a session
/// held by a rule names the rule instead of pretending a person set it.
public enum SessionHero: Equatable, Sendable {
    /// Nothing is holding the Mac. The hero offers the ways to start.
    case idle
    /// A deadline in the future: a countdown, «+15», «+1 h», stop.
    case timed(until: Date)
    /// Held with no deadline — the module's spelling of «until I say stop».
    case indefinite
    /// Held only by rules, which are named. Stopping suppresses them, which is
    /// why stopping is still offered here.
    case automatic(Set<ActiveCondition>)

    public static func of(isActive: Bool, endDate: Date?,
                          conditions: Set<ActiveCondition>, now: Date) -> SessionHero {
        guard isActive else { return .idle }
        // A deadline in the past is not a countdown. The engine's expiry may
        // not have run yet — the view has only the clock — and «-0:03» is the
        // module reporting a session that has ended.
        if let endDate, endDate > now { return .timed(until: endDate) }
        // Manual outranks the rules: a person who pressed start is not told
        // that a display is why their Mac is awake. Only when nobody pressed
        // anything are the reasons the answer.
        if conditions.contains(.manual) { return .indefinite }
        let automatic = conditions.intersection(ActiveCondition.automatic)
        return automatic.isEmpty ? .indefinite : .automatic(automatic)
    }

    /// What will still be holding the Mac when the countdown reaches zero, or
    /// nil when nothing will.
    ///
    /// The one question a countdown cannot answer about itself. A rule that is
    /// met now is met then, so the session does not end with the timer — unless
    /// the person has asked the timer to end automation as well, which is the
    /// only way this returns nil while a rule is plainly holding.
    ///
    /// One condition, not the set: the line under the figure is a sentence, and
    /// «then the external display and the charger and Final Cut keep it awake»
    /// is a list where a reason was wanted. `allCases` order decides which,
    /// so the answer does not change between two runs on one machine.
    public static func holderAfterTimer(conditions: Set<ActiveCondition>,
                                 timerEndsAutomation: Bool) -> ActiveCondition? {
        guard !timerEndsAutomation else { return nil }
        return ActiveCondition.allCases.first {
            ActiveCondition.automatic.contains($0) && conditions.contains($0)
        }
    }
}
