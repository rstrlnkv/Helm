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

    /// Whether what is holding the Mac is a session somebody started — the
    /// engine's `manualOn`, read back off the state it published.
    ///
    /// Answered here rather than by whoever draws, because a session is exactly
    /// what the first press of a two-step Stop ends (`StopPress`): with none
    /// running there is no first step left to take, and the button is the
    /// second one. Exhaustive on purpose — a fifth state would be a build error
    /// here rather than a button quietly reading as the wrong step.
    public var sessionRunning: Bool {
        switch self {
        case .idle, .automatic: return false
        case .timed, .indefinite: return true
        }
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
    /// What happens when the countdown reaches zero.
    ///
    /// Three answers, not two. It used to be an optional condition, and `nil`
    /// folded together the two cases that differ most: «nothing is holding this
    /// Mac, so it goes to sleep» and «a rule is holding it and this timer is
    /// about to pause that rule». The second is the whole point of «The timer
    /// pauses the automation rules when it finishes» — and with that switch on,
    /// the one state where it matters was the one state the page said nothing
    /// in, because the note degenerated to «Timer until 16:03» and stopped
    /// there.
    public enum AfterTimer: Equatable, Sendable {
        /// No rule applies; the session simply ends.
        case nothing
        /// The timer ends and this condition goes on holding the Mac.
        case heldBy(ActiveCondition)
        /// A rule applies **and** the person asked a timer to end automation,
        /// so zero stops the rule as well.
        case rulePaused
    }

    public static func afterTimer(conditions: Set<ActiveCondition>,
                                  timerEndsAutomation: Bool) -> AfterTimer {
        let holder = ActiveCondition.allCases.first {
            ActiveCondition.automatic.contains($0) && conditions.contains($0)
        }
        guard let holder else { return .nothing }
        return timerEndsAutomation ? .rulePaused : .heldBy(holder)
    }

    /// The older shape, kept for the callers that only ask «and then what holds
    /// it» — `nil` covers both «nothing» and «the rule is being paused», which
    /// is why anything drawing a sentence uses `afterTimer` instead.
    public static func holderAfterTimer(conditions: Set<ActiveCondition>,
                                        timerEndsAutomation: Bool) -> ActiveCondition? {
        if case .heldBy(let condition) = afterTimer(conditions: conditions,
                                                    timerEndsAutomation: timerEndsAutomation) {
            return condition
        }
        return nil
    }
}
