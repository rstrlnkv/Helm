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
    /// The folder for a move or a sort, not the final filename: a name already
    /// taken gets numbered at the moment of the move (`FreeName`), and touching
    /// the disk to find out on every keystroke of the editor is not worth
    /// knowing it a second early. **A rename is the exception**: its file name
    /// is the destination, with the `{counter}` number the sweep would give it
    /// (`CounterBook`), which costs one listing of the folder per dry run.
    public let destination: String?
    /// Set instead of a destination when the run would refuse this rename — the
    /// same reason the sweep would log.
    public let refusal: RuleOutcome.Refusal?

    public init(_ plan: RulePlan) {
        self.init(plan, counters: CounterBook())
    }

    /// One book for the rows of one dry run, in the order the sweep walks them.
    init(_ plan: RulePlan, counters: CounterBook) {
        path = plan.facts.path
        ruleID = plan.rule.id
        ruleName = plan.rule.name
        action = plan.action
        switch PlannedDestination.describe(plan, counters: counters) {
        case .nowhere: (destination, refusal) = (nil, nil)
        case let .named(name): (destination, refusal) = (name, nil)
        case let .refused(reason): (destination, refusal) = (nil, reason)
        }
    }
}
