import Foundation

/// One thing that is going to happen to one file, and the rule that decided it.
///
/// The plan is what the dry run shows and what the runner executes, and it is
/// the same value in both cases — so what someone was shown and what happened
/// cannot drift apart.
public struct RulePlan: Equatable, Sendable {
    public let facts: FileFacts
    public let rule: Rule
    public var action: RuleAction { rule.action }

    public init(facts: FileFacts, rule: Rule) {
        self.facts = facts
        self.rule = rule
    }
}

public extension RulePlan {

    /// The first enabled rule whose conditions hold. Nothing, if none do.
    ///
    /// First match wins, as in Hazel: the list reads top to bottom as a single
    /// decision rather than as a set of independent things that may collide,
    /// and exactly one thing happens to a file. Hazel then offers a "continue
    /// matching" action to escape that — a second mechanism to explain, and one
    /// this does not have.
    static func decide(_ facts: FileFacts, rules: [Rule]) -> RulePlan? {
        for rule in rules where rule.enabled {
            // A disabled rule steps aside rather than matching nothing, so the
            // rule below it gets its turn — which is what switching one off to
            // see what the next one does is for. Same for a rule with no
            // conditions: `RuleMatcher` refuses it, and the search continues.
            // And the same for a folder this rule made, which steps aside for
            // the rule below rather than swallowing it: a bucket is not an item
            // *of this rule*, not "not an item".
            guard !sortsItsOwnBucket(facts, rule) else { continue }
            if RuleMatcher.matches(facts, rule) { return RulePlan(facts: facts, rule: rule) }
        }
        return nil
    }

    /// **A folder a sorting rule makes is not one of the things it sorts.**
    ///
    /// `sortIntoSubfolder(.kind)` calls a directory a `.folder`, whose bucket is
    /// `Folders` — so once the rule has made `~/Downloads/Folders`, every sweep
    /// planned to move that folder inside itself. `RuleRunner.move` refused it
    /// `outOfScope`, correctly and for ever: an hourly warning in the log and an
    /// hourly row in the history, about a folder nobody had asked to move.
    ///
    /// Decided here rather than in the runner because the plan is the one value
    /// the dry run shows and the runner executes. A refusal would be the wrong
    /// word anyway — it says something was going to happen and could not, and
    /// this was never going to happen.
    ///
    /// Only a sorting rule, and only a directory: a *file* called `Folders` is
    /// an ordinary file, and a `2026-07/` met by a `.kind` rule is somebody's
    /// folder, which that rule may honestly move.
    private static func sortsItsOwnBucket(_ facts: FileFacts, _ rule: Rule) -> Bool {
        guard facts.isDirectory, case let .sortIntoSubfolder(scheme) = rule.action
        else { return false }
        return SortBucket.isBucket(facts.name, of: scheme)
    }

    /// The whole folder, in one pass. Files nothing matches are absent rather
    /// than present with no action: this is a list of what will happen, not a
    /// list of files.
    static func decide(_ files: [FileFacts], rules: [Rule]) -> [RulePlan] {
        files.compactMap { decide($0, rules: rules) }
    }
}
