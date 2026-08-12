import Foundation

/// What the line under a rule's title says, as a case rather than a string.
///
/// It was an expression written in the row's own body — a nested ternary over
/// `enabled` and `satisfied` — and it had no third input, so it could not
/// express the state the page actually gets into: a rule that is switched on,
/// whose trigger holds, and which has been **paused** because somebody pressed
/// Stop. `satisfied` reads from `activeConditions`, and a paused rule
/// contributes nothing to that set, so the row fell to «Not applying right
/// now» — two hundred points below a banner reading «Paused until the rule
/// applies again». One screen, two accounts of one rule, and the row's was the
/// one that sounded like nothing was wrong.
///
/// Pure, and out here where a test can reach it: the fix inside a `@ViewBuilder`
/// would have been the same three lines with no way to pin them.
public enum RuleNote: Equatable, Sendable {
    /// Switched off — so the note explains what switching it on would do.
    /// The one moment somebody needs to know what a rule means is before they
    /// turn it on, which was the state the row used to say nothing in.
    case meaning
    /// On, and holding the Mac awake right now.
    case applies
    /// On, and its trigger is not true at the moment.
    case waiting
    /// On, its trigger *is* true, and it is being ignored until the trigger
    /// drops and comes back.
    case paused
    /// On, and the battery guard has everything stopped: nothing this module does
    /// will run until the charge comes back or the charger goes in, whatever this
    /// rule's own trigger says.
    ///
    /// The fifth case, and the second one added for the same reason as the
    /// fourth: `satisfied` is false under the veto — `releaseForBattery` empties
    /// `activeConditions` — so a rule whose trigger was still true fell to «Not
    /// applying right now», which is true and is the least useful of the three
    /// things the screen knew.
    case vetoed

    /// - Parameter satisfied: the rule is in `activeConditions` — which a
    ///   paused rule never is, hence the separate flag below.
    /// - Parameter batteryStopped: the guard is vetoing everything. A property of
    ///   the *Mac* rather than of this rule, so unlike `suppressed` it does not
    ///   ask whether the rule's own trigger holds — and it outranks the pause,
    ///   because both can be true and only one of them explains why nothing at
    ///   all is happening.
    /// - Parameter suppressed: the module as a whole is suppressed. It applies
    ///   to this row only when the rule's own trigger holds; a rule that is
    ///   merely waiting is not the one that was paused, and marking it so would
    ///   put «Paused» on every switched-on rule on the page.
    public static func of(enabled: Bool, satisfied: Bool, batteryStopped: Bool,
                          suppressed: Bool, triggerHolds: Bool) -> RuleNote {
        guard enabled else { return .meaning }
        if batteryStopped { return .vetoed }
        if satisfied { return .applies }
        return suppressed && triggerHolds ? .paused : .waiting
    }
}
