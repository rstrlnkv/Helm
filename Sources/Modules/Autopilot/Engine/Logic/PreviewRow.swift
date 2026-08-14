import Foundation

/// One line of a dry run: the file, and the one thing that would happen to it.
public struct PreviewRow: Codable, Equatable, Identifiable, Sendable {
    /// The path, not the name. `ForEach` draws one row per identity, and two
    /// files called `report.pdf` in two folders were two plans and one row — so
    /// the screen a person reads before letting a rule loose hid a file the
    /// rule was about to touch. Ordinary at any depth above one.
    public var id: String { path }
    /// Shown as the name; carried as the path for exactly the reason above.
    public var name: String { (path as NSString).lastPathComponent }
    public let path: String
    /// Which rule takes this file, by identity rather than by name — the dry run
    /// is of the whole folder now, and two rules a person wrote may perfectly
    /// well be called the same thing. The editor dims what an earlier rule takes
    /// first, and dimming the wrong row is the drift this exists to prevent.
    public let ruleID: String
    public let ruleName: String
    public let action: RuleAction
    /// Where it lands, when the action has a where. The preview named the
    /// action — "sort into subfolders by kind" — and left the person to work
    /// out which subfolder, which is the only part they could not have known
    /// from the rule they had just written.
    ///
    /// The folder, not the final filename: a name already taken gets numbered
    /// at the moment of the move, and touching the disk to find out on every
    /// keystroke of the editor is not worth knowing it a second early.
    public let destination: String?

    public init(_ plan: RulePlan) {
        path = plan.facts.path
        ruleID = plan.rule.id
        ruleName = plan.rule.name
        action = plan.action
        destination = PlannedDestination.describe(plan)
    }
}
