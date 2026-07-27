import Foundation
import XCTest
@testable import Module_Rules_Engine

/// Which rule wins.
///
/// The whole reason a folder holds an *ordered* list rather than a set: the
/// list is read top to bottom as one decision, and exactly one thing happens to
/// a file. Every question about that ordering is answerable here, without a
/// folder to answer it in.
final class RulePlanTests: XCTestCase {

    private func facts(_ name: String, bytes: Int = 1_000_000) -> FileFacts {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return FileFacts(name: name, kind: .document, bytes: bytes,
                         added: now, modified: now, now: now)
    }

    private func rule(_ id: String, _ conditions: [RuleCondition],
                      _ action: RuleAction, enabled: Bool = true) -> Rule {
        Rule(id: id, name: id, enabled: enabled, match: .all,
             conditions: conditions, action: action)
    }

    /// The first rule whose conditions hold is the one that runs, and the rest
    /// are skipped — even when a later one would also have matched.
    func testTheFirstMatchWins() {
        let rules = [
            rule("a", [.name(.contains, "report")], .addTag("A")),
            rule("b", [.fileExtension(["pdf"])], .addTag("B")),
        ]
        let plan = RulePlan.decide(facts("report.pdf"), rules: rules)
        XCTAssertEqual(plan?.rule.id, "a")
        XCTAssertEqual(plan?.action, .addTag("A"))
    }

    /// Order is the setting. The same two rules the other way round give the
    /// other answer, and that has to be true or the list is decoration.
    func testOrderIsTheSetting() {
        let rules = [
            rule("b", [.fileExtension(["pdf"])], .addTag("B")),
            rule("a", [.name(.contains, "report")], .addTag("A")),
        ]
        XCTAssertEqual(RulePlan.decide(facts("report.pdf"), rules: rules)?.rule.id, "b")
    }

    func testNoMatchIsNoPlan() {
        let rules = [rule("a", [.name(.contains, "invoice")], .trash)]
        XCTAssertNil(RulePlan.decide(facts("holiday.jpg"), rules: rules))
    }

    /// A disabled rule is not a rule that matches nothing — it is skipped, so
    /// the one below it gets its turn. Switching a rule off to see what the
    /// next one does is the reason the switch exists.
    func testADisabledRuleStepsAside() {
        let rules = [
            rule("a", [.fileExtension(["pdf"])], .addTag("A"), enabled: false),
            rule("b", [.fileExtension(["pdf"])], .addTag("B")),
        ]
        XCTAssertEqual(RulePlan.decide(facts("x.pdf"), rules: rules)?.rule.id, "b")
    }

    func testAnEmptyFolderOfRulesDecidesNothing() {
        XCTAssertNil(RulePlan.decide(facts("x.pdf"), rules: []))
    }

    /// A half-written rule must not act on everything below it, and must not
    /// swallow the file either: it matches nothing and the next rule runs.
    func testARuleWithNoConditionsIsSkippedRatherThanMatching() {
        let rules = [
            rule("empty", [], .trash),
            rule("b", [.fileExtension(["pdf"])], .addTag("B")),
        ]
        XCTAssertEqual(RulePlan.decide(facts("x.pdf"), rules: rules)?.rule.id, "b")
    }

    // MARK: - The whole folder

    /// The dry run's shape: every file, and the one thing that would happen to
    /// it. Files nothing matches are absent rather than present-and-empty —
    /// the screen is a list of what will happen, not a list of files.
    func testPlanningAFolderReturnsOnlyTheFilesSomethingHappensTo() {
        let rules = [rule("a", [.fileExtension(["pdf"])], .trash)]
        let plans = RulePlan.decide([facts("a.pdf"), facts("b.jpg"), facts("c.pdf")],
                                    rules: rules)
        XCTAssertEqual(plans.map(\.facts.name), ["a.pdf", "c.pdf"])
        XCTAssertTrue(plans.allSatisfy { $0.action == .trash })
    }
}
