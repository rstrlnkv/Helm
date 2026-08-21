import Foundation

/// What the line under «Stay awake with the lid closed» says, as a case rather
/// than a string.
///
/// The row had two notes and four states. It said «sleep is off for the whole
/// Mac» while the lid was holding, and what the administrator password buys the
/// rest of the time — a ternary in the page's body, with nowhere for the two
/// states in which something was *attempted and did not work*:
///
/// - **macOS refused.** `reallyEngage` reads `setDisableSleep(true)`, and
///   `sudo -n` fails whenever the NOPASSWD rule is not what Helm wrote — removed
///   by an admin, edited by a migration, tidied out of `/etc/sudoers.d`. The
///   engine logs it and holds `active` false, and the row then described what the
///   password would buy, as though nothing had been tried. That is somebody being
///   told a lid is safe to close.
/// - **The rule outlived the feature.** Switching the option off asks for the
///   grant back; a declined dialog is an answer, and the rule stays. Its `Bool`
///   was discarded, so the only record was a log line accusing something else of
///   having written a rule Helm wrote itself.
///
/// Out here rather than in the `@ViewBuilder` for the reason `RuleNote` is: the
/// same four lines inside a view body are four lines nothing can pin.
/// `CaseIterable` so the guard on the row's caption length is a fact about the
/// enum rather than a list of four names in a test: a fifth state is measured
/// the day somebody writes it.
public enum LidRowNote: CaseIterable, Equatable, Sendable {
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
