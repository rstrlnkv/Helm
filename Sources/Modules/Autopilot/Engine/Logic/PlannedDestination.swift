import Foundation

/// Where a plan would put a file, said in one short phrase.
///
/// Derived from the same pieces `RuleRunner` uses: the runner asks `SortBucket`
/// and, for a rename, the pass's `CounterBook` for the same answers a line
/// later. What holds is that for one folder listing, one order of files and one
/// book per pass, preview and run give a file the same name. What does not: a
/// folder that changes between the dry run and the sweep, and a file the sweep
/// skips for a stamp, which the dry run does not read.
enum PlannedDestination {

    /// What the plan would do about the file's place: a phrase, a refusal the
    /// run would meet, or nothing to say.
    enum Place: Equatable {
        case nowhere
        case named(String)
        case refused(RuleOutcome.Refusal)
    }

    /// `.nowhere` when the action does not move or rename anything — trashing
    /// and tagging have no destination to name, and inventing one for them would
    /// make the column read as if every rule relocated something.
    static func describe(_ plan: RulePlan, counters: CounterBook) -> Place {
        switch plan.action {
        case let .move(to: destination):
            return .named((destination as NSString).lastPathComponent)
        case let .sortIntoSubfolder(scheme):
            return .named(SortBucket.name(for: plan.facts, scheme: scheme))
        case let .rename(pattern):
            let folder = (plan.facts.path as NSString).deletingLastPathComponent
            switch counters.name(for: pattern, facts: plan.facts, in: folder) {
            case let .name(name): return .named(name)
            case .unusable: return .refused(.badPattern)
            case .exhausted: return .refused(.counterNumbersUsedUp)
            case .unreadable: return .refused(.folderUnreadable)
            }
        case .addTag, .trash:
            return .nowhere
        }
    }
}
