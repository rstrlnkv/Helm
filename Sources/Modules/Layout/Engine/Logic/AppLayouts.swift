import Foundation

/// Which layout an application is typed in, when the person has said so.
///
/// **The module does not learn this, and that was a decision rather than a
/// simplification.** An earlier design watched which layout you left each
/// application on, acted after two agreeing departures, and forgot its belief
/// if you switched back by hand within a few seconds. It was dropped because
/// the module already owns a per-application table a person fills in
/// themselves — `AppScope`, drawn as a row with a picker in the lists window —
/// and three decisions that design needed (what to learn from, how many
/// observations, what counts as a veto) stop existing once the person is asked.
/// A binding cannot mis-learn. It can only go out of date, and then it is
/// changed where it was set.
///
/// `AppScope` does **not** gate this. «Do not rewrite my text here» and «I
/// write English here» are different questions, and the second is more likely
/// to be wanted in a terminal, not less.
enum AppLayouts {

    /// The layout to select when `app` comes forward, or nothing.
    ///
    /// Nothing when the id is empty — the boundary `AppScope.allows` already
    /// draws — when the application has no binding, and when the bound layout
    /// is no longer installed. That last one is the only real logic here:
    /// somebody bound Ukrainian and then removed it in System Settings, and
    /// selecting *some other* layout because one was asked for would be worse
    /// than doing nothing.
    static func layout(for app: String,
                       bindings: [String: String],
                       installed: [String]) -> String? {
        guard !app.isEmpty, let bound = bindings[app], installed.contains(bound)
        else { return nil }
        return bound
    }
}
