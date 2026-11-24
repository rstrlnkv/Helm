import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// A rule that cannot be carried out cannot be switched on.
///
/// An action that names nothing is reachable by design: `ActionRow.Kind.blank`
/// starts a move with an empty destination, which only ever arrives through
/// the panel. Switched on, every matching file would return
/// `.refused(.outOfScope)`, a log line and a history row on every sweep, for a
/// rule the person believes is working.
///
/// Such a rule is switched off on the way through `storable`, not dropped, so
/// the person still has their rule to finish. Being in the engine, that covers
/// a hand-edited plist as well as the editor.
final class RuleCompletenessTests: XCTestCase {

    private func rule(_ action: RuleAction, enabled: Bool = true) -> Rule {
        Rule(id: "r", name: "r", enabled: enabled,
             conditions: [.fileExtension(["pdf"])], action: action)
    }

    private func stored(_ action: RuleAction) -> Rule? {
        WatchedFolder(id: "f", path: "/Users/x/Downloads", rules: [rule(action)])
            .storable.rules.first
    }

    // MARK: - Which actions name everything they need

    func testAnActionWithNothingInItIsNotComplete() {
        XCTAssertFalse(RuleAction.move(to: "").isComplete)
        XCTAssertFalse(RuleAction.move(to: "   ").isComplete)
        XCTAssertFalse(RuleAction.addTag("").isComplete)
        XCTAssertFalse(RuleAction.rename(pattern: "").isComplete)
        XCTAssertFalse(RuleAction.rename(pattern: " ").isComplete)
    }

    func testAnActionThatNamesWhatItNeedsIsComplete() {
        XCTAssertTrue(RuleAction.move(to: "/Users/x/Invoices").isComplete)
        XCTAssertTrue(RuleAction.addTag("seen").isComplete)
        XCTAssertTrue(RuleAction.rename(pattern: "{name}").isComplete)
        // Neither of these has anything left to fill in.
        XCTAssertTrue(RuleAction.sortIntoSubfolder(.kind).isComplete)
        XCTAssertTrue(RuleAction.trash.isComplete)
    }

    // MARK: - Which conditions name everything they need

    /// «Name begins with ‹nothing›» is true of every file in the folder: with
    /// Trash beside it, an all-matcher three gestures from the editor's blank
    /// state. A condition whose text names nothing is half-written whatever the
    /// comparison: `contains ""` matches nothing under Foundation, but a popup
    /// selection away it matches everything.
    func testAConditionWithNothingInItIsNotComplete() {
        XCTAssertFalse(RuleCondition.name(.beginsWith, "").isComplete)
        XCTAssertFalse(RuleCondition.name(.endsWith, "").isComplete)
        XCTAssertFalse(RuleCondition.name(.is, "").isComplete)
        XCTAssertFalse(RuleCondition.name(.contains, "").isComplete)
        XCTAssertFalse(RuleCondition.name(.beginsWith, "   ").isComplete)
        XCTAssertFalse(RuleCondition.baseName(.beginsWith, "").isComplete)
        XCTAssertFalse(RuleCondition.fileExtension([]).isComplete)
        XCTAssertFalse(RuleCondition.fileExtension(["", " "]).isComplete)
        XCTAssertFalse(RuleCondition.downloadedFrom("").isComplete)
        XCTAssertFalse(RuleCondition.tag(" ").isComplete)
    }

    /// The editor's field refuses these, so they arrive only by hand-edited
    /// plist — the route `storable` exists for, and the same bound it reads.
    func testAConditionCarryingANumberNobodyCouldTypeIsNotComplete() {
        XCTAssertFalse(RuleCondition.size(.smallerThan, megabytes: 0).isComplete)
        XCTAssertFalse(RuleCondition.size(.largerThan, megabytes: -3).isComplete)
        XCTAssertFalse(RuleCondition.dateAdded(.olderThan, days: .infinity).isComplete)
        XCTAssertFalse(RuleCondition.dateModified(.newerThan, days: .nan).isComplete)
    }

    /// One of each case, filled in the way the editor fills it.
    func testAConditionThatNamesWhatItAsksAboutIsComplete() {
        XCTAssertTrue(RuleCondition.name(.beginsWith, "invoice").isComplete)
        XCTAssertTrue(RuleCondition.baseName(.endsWith, "draft").isComplete)
        XCTAssertTrue(RuleCondition.fileExtension(["pdf"]).isComplete)
        XCTAssertTrue(RuleCondition.kind(.image).isComplete)
        XCTAssertTrue(RuleCondition.size(.largerThan, megabytes: 10).isComplete)
        XCTAssertTrue(RuleCondition.dateAdded(.olderThan, days: 30).isComplete)
        XCTAssertTrue(RuleCondition.dateModified(.newerThan, days: 7).isComplete)
        XCTAssertTrue(RuleCondition.downloadedFrom("example.com").isComplete)
        XCTAssertTrue(RuleCondition.tag("keep").isComplete)
    }

    // MARK: - What the switch is allowed to do

    func testARuleWhoseActionNamesNothingCannotBeEnabled() {
        XCTAssertFalse(rule(.move(to: "")).canBeEnabled)
        XCTAssertTrue(rule(.move(to: "/Users/x/Invoices")).canBeEnabled)
    }

    /// Every half-written state a condition can be in keeps the switch off.
    /// `.kind` is absent because it has none: a kind is picked from a popup and
    /// every position of the popup names one.
    func testEveryHalfWrittenConditionKeepsTheSwitchOff() {
        let halfWritten: [RuleCondition] = [
            .name(.beginsWith, ""), .name(.endsWith, ""), .name(.is, ""),
            .name(.contains, ""), .baseName(.contains, ""), .fileExtension([]),
            .downloadedFrom(""), .tag(""),
            .size(.smallerThan, megabytes: 0), .dateAdded(.olderThan, days: -1),
            .dateModified(.olderThan, days: .infinity)
        ]
        for condition in halfWritten {
            let broken = Rule(id: "r", name: "r", enabled: true,
                              conditions: [condition], action: .trash)
            XCTAssertFalse(broken.canBeEnabled,
                           "\(condition) is half-written and the switch beside it is live")
        }
    }

    /// One finished condition does not buy a blank one a pass: under `.any`
    /// the blank half alone decides what matches.
    func testACompleteConditionDoesNotCarryABlankOne() {
        let mixed = Rule(id: "r", name: "r", enabled: true, match: .any,
                         conditions: [.fileExtension(["pdf"]), .name(.beginsWith, "")],
                         action: .trash)
        XCTAssertFalse(mixed.canBeEnabled)
    }

    /// The condition rule the editor already applies, stated in the same place
    /// so the switch has one predicate rather than two that drift.
    func testARuleWithNoConditionsStillCannotBeEnabled() {
        let empty = Rule(id: "r", name: "r", enabled: true, conditions: [], action: .trash)
        XCTAssertFalse(empty.canBeEnabled)
    }

    // MARK: - What reaches the engine

    func testAnIncompleteRuleArrivesSwitchedOff() {
        XCTAssertEqual(stored(.move(to: ""))?.enabled, false)
        XCTAssertEqual(stored(.addTag(""))?.enabled, false)
        XCTAssertEqual(stored(.rename(pattern: " "))?.enabled, false)
    }

    /// The condition side of the same gate: a hand-edited plist carrying the
    /// all-matcher arrives with the rule switched off, kept for the person to
    /// finish — the same repair as an action that names nothing.
    func testARuleWithAHalfWrittenConditionArrivesSwitchedOff() throws {
        let allMatcher = Rule(id: "r", name: "r", enabled: true,
                              conditions: [.name(.beginsWith, "")], action: .trash)
        let kept = try XCTUnwrap(
            WatchedFolder(id: "f", path: "/Users/x/Downloads", rules: [allMatcher])
                .storable.rules.first)
        XCTAssertFalse(kept.enabled)
        XCTAssertEqual(kept.conditions, [.name(.beginsWith, "")], "kept to finish, not dropped")
    }

    /// Switched off, not dropped. Somebody who picked "Move to" and closed the
    /// window before choosing a folder still has the rule they were writing.
    func testAnIncompleteRuleIsKeptRatherThanThrownAway() throws {
        let kept = try XCTUnwrap(stored(.move(to: "")))
        XCTAssertEqual(kept.action, .move(to: ""))
        XCTAssertEqual(kept.conditions.count, 1)
    }

    func testACompleteRuleIsLeftAlone() {
        XCTAssertEqual(stored(.move(to: "/Users/x/Invoices"))?.enabled, true)
        XCTAssertEqual(stored(.trash)?.enabled, true)
    }

    /// A rule that cannot run is never planned against a file, so the sweep has
    /// nothing to refuse and the history nothing to record. Asserted through
    /// `RulePlan.decide`, which the sweep calls, because the switch is worth
    /// something only if it reaches this.
    func testNoPlanIsMadeForARuleThatCannotRun() {
        let file = FileFacts(name: "a.pdf", path: "/Users/x/Downloads/a.pdf",
                             kind: .document, bytes: 4,
                             added: Date(timeIntervalSince1970: 0),
                             modified: Date(timeIntervalSince1970: 0),
                             now: Date(timeIntervalSince1970: 0))
        let folder = WatchedFolder(id: "f", path: "/Users/x/Downloads",
                                   rules: [rule(.move(to: ""))]).storable

        XCTAssertNil(RulePlan.decide(file, rules: folder.activeRules),
                     "the rule would refuse this file on every sweep, forever")
    }

    /// And a folder whose rules are all fine still plans, so the line above
    /// cannot be bought by planning nothing.
    func testAFolderWhoseRulesAreFineStillPlans() {
        let file = FileFacts(name: "a.pdf", path: "/Users/x/Downloads/a.pdf",
                             kind: .document, bytes: 4,
                             added: Date(timeIntervalSince1970: 0),
                             modified: Date(timeIntervalSince1970: 0),
                             now: Date(timeIntervalSince1970: 0))
        let folder = WatchedFolder(id: "f", path: "/Users/x/Downloads",
                                   rules: [rule(.move(to: "/Users/x/Invoices"))]).storable

        XCTAssertNotNil(RulePlan.decide(file, rules: folder.activeRules))
    }
}
