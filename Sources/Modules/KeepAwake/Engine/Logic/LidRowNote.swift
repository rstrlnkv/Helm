import Foundation

/// What the line under «Stay awake with the lid closed» says, as a case rather
/// than a string.
///
/// Four states, two of them something *attempted that did not work*:
///
/// - **macOS refused.** `reallyEngage` reads `setDisableSleep(true)`, and
///   `sudo -n` fails whenever the NOPASSWD rule is not what Helm wrote — removed
///   by an admin, edited by a migration, tidied out of `/etc/sudoers.d`. The
///   engine holds `active` false; a row describing what the password would buy
///   would tell somebody a lid is safe to close.
/// - **The rule outlived the feature.** Switching the option off asks for the
///   grant back; a declined dialog is an answer, and the rule stays.
public enum LidRowNote: Equatable, Sendable {
    /// macOS was asked to turn sleep off and said no.
    case refused
    /// The option is off and its `/etc/sudoers.d` rule is still there.
    case grantRemains
    /// It worked: sleep is off for the whole Mac right now.
    case sleepIsOff
    /// Nothing is wrong, so the row explains what the grant costs.
    case whatItCosts

    /// - Parameter refused: outranks everything. It is the only one of the four
    ///   in which the switch says one thing and the machine does another, and the
    ///   cost of missing it is a Mac that was supposed to stay awake in a bag.
    /// - Parameter grantRemains: cannot coexist with `holding` — the grant is only
    ///   asked back once the setting is false — and the order is stated rather
    ///   than left to whichever `if` happens to be written first.
    public static func of(refused: Bool, grantRemains: Bool, holding: Bool) -> LidRowNote {
        if refused { return .refused }
        if holding { return .sleepIsOff }
        return grantRemains ? .grantRemains : .whatItCosts
    }
}
