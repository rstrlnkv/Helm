import Foundation

/// What the line under a rule's title says, as a case rather than a string.
///
/// `enabled` and `satisfied` alone cannot say a rule is **paused** or
/// **vetoed**: a paused or vetoed rule is not in `activeConditions`, so the row
/// would read «Not applying right now» under a banner saying otherwise
/// (`Architecture/KeepAwake.md § Vetoes and the notice`).
public enum RuleNote: Equatable, Sendable {
    /// Switched off — so the note explains what switching it on would do.
    /// The one moment somebody needs to know what a rule means is before they
    /// turn it on.
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
    /// rule's own trigger says. `satisfied` is false under the veto, because
    /// `releaseForBattery` empties `activeConditions`.
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
