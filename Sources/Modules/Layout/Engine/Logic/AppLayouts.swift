import Foundation

/// Which layout an application is typed in, when the person has said so.
///
/// The module does not learn this: the person sets it, in the row the lists
/// window already draws per application. A binding cannot mis-learn; it can
/// only go out of date, and then it is changed where it was set.
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
