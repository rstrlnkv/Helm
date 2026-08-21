import Foundation

/// What one press of Stop is allowed to decide, and therefore what the button
/// is called.
///
/// **Two controls in this module switch automation off, and they are not a
/// duplication to be tidied away.** The difference is where the person is.
///
/// - «The timer pauses the automation rules when it finishes» is the control
///   for *being away*. The timer runs out while somebody is asleep or out of
///   the room, and the rules stand down with nobody there to be asked.
/// - Stop is the control for *being at the Mac*. Somebody pressing it is
///   present and in charge, so it hands them the steps instead of deciding both
///   halves on their behalf: this press ends the session, and the next one — if
///   they want it — ends the rules.
///
/// With that switch off the timer never touches the rules, so there is nothing
/// for a second step to mean and Stop stays the single press it has always
/// been. Symmetry would only add a step to remember.
///
/// **Nothing here is remembered.** The three inputs are read at the moment of
/// the press, so there is no «the first press has happened» to expire, to
/// survive a relaunch, or to go on being true after the rule it was aimed at
/// has quit. The button's word is the name of what pressing it will do right
/// now, not a mode the first press put it into.
public enum StopPress: Equatable, Sendable {
    /// One press for both halves: the session ends and any rule holding the Mac
    /// is paused with it. What Stop has always done, and what it goes on doing
    /// whenever there is no second step to offer.
    case stopEverything
    /// The first of two steps. The session ends; the rules go on holding the
    /// Mac, and the button becomes the second step.
    case stopSessionOnly
    /// The second step: no session is left to end, so this press is the one
    /// that pauses the rules — and the button says so rather than saying «Stop».
    case turnAutomationOff

    /// - Parameters:
    ///   - sessionRunning: somebody started a session by hand and it has not
    ///     ended — the engine's `manualOn`. It is what the *first* step ends,
    ///     so with none running there is no first step left to take.
    ///   - ruleHolds: an automatic condition is true right now. Without one
    ///     there is nothing a second press could pause, and offering a step
    ///     would name something that is not there.
    ///   - timerEndsAutomation: the person has said that a timer running out is
    ///     what stands the rules down. That is the promise Stop declines to
    ///     keep for them while they are sitting in front of it.
    public static func next(sessionRunning: Bool, ruleHolds: Bool,
                            timerEndsAutomation: Bool) -> StopPress {
        guard ruleHolds, timerEndsAutomation else { return .stopEverything }
        return sessionRunning ? .stopSessionOnly : .turnAutomationOff
    }
}
