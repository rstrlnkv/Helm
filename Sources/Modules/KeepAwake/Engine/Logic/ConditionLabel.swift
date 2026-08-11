import Foundation

/// Why the Mac is being held awake, as one stable word for the log.
///
/// `activeConditions` is a `Set`, and a `Set` has no order — a line built by
/// iterating it prints its reasons in whatever order the launch's hash seed gave,
/// so two identical sessions read as two different events and a diff between two
/// triage logs is noise. This fixes the order, and the order is the one the
/// conditions are explained in rather than alphabetical: what the person asked for
/// before what their hardware happens to be doing.
///
/// No names anywhere — these are enum cases, not the app or display a rule names,
/// so the line satisfies the rule that the log carries no names by construction.
enum ConditionLabel {

    /// The fixed order. Adding a case to `ActiveCondition` without adding it here
    /// is caught by `ConditionLabelTests`, which walks `allCases`.
    private static let order: [(ActiveCondition, String)] = [
        (.manual, "manual"),
        (.timer, "timer"),
        (.externalDisplay, "display"),
        (.power, "power"),
        (.app, "app"),
    ]

    static func of(_ conditions: Set<ActiveCondition>) -> String {
        let held = order.filter { conditions.contains($0.0) }.map(\.1)
        // Not the empty string: held by nothing is a real state — it is what the
        // line says the moment a session ends — and an empty value reads in a log
        // as something missing rather than as "no reason any more".
        return held.isEmpty ? "none" : held.joined(separator: "+")
    }
}
