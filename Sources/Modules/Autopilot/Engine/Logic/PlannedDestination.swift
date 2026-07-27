import Foundation

/// Where a plan would put a file, said in one short phrase.
///
/// Derived from the same pieces `RuleRunner` uses, so the preview and the run
/// cannot drift: the runner asks `SortBucket` and `RenamePattern` for the same
/// answers a line later.
public enum PlannedDestination {

    /// Nil when the action does not move or rename anything — trashing and
    /// tagging have no destination to name, and inventing one for them would
    /// make the column read as if every rule relocated something.
    public static func describe(_ plan: RulePlan) -> String? {
        switch plan.action {
        case let .move(to: destination):
            return (destination as NSString).lastPathComponent
        case let .sortIntoSubfolder(scheme):
            return SortBucket.name(for: plan.facts, scheme: scheme)
        case let .rename(pattern):
            return RenamePattern.apply(pattern, to: plan.facts)
        case .addTag, .trash:
            return nil
        }
    }
}
