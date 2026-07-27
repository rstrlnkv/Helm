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
            if RuleMatcher.matches(facts, rule) { return RulePlan(facts: facts, rule: rule) }
        }
        return nil
    }

    /// The whole folder, in one pass. Files nothing matches are absent rather
    /// than present with no action: this is a list of what will happen, not a
    /// list of files.
    static func decide(_ files: [FileFacts], rules: [Rule]) -> [RulePlan] {
        files.compactMap { decide($0, rules: rules) }
    }
}
