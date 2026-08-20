import XCTest
@testable import Module_Autopilot_Engine

/// **«.pdf» is what people type, and it used to be a rule that matched
/// nothing.**
///
/// `RuleCondition.fileExtension` documents its own contents — "Lowercase, no
/// dots" — and `RuleMatcher` compares the list against `FileFacts.fileExtension`,
/// which never carries one. Nothing enforced the second half of that sentence:
/// the editor's field lowercased and trimmed the text and kept the dot, so a
/// person who typed the extension the way Finder shows it got a condition that
/// is `isComplete`, may be switched on, and can never match a file. It fails
/// safe and it fails silently, which is the pair that keeps a rule looking like
/// it works.
///
/// **The repair is where the text is entered, and deliberately not in
/// `storable`.** `storable` runs over the stored rules on the way out as well as
/// in, so putting it there would change what a rule already on somebody's Mac
/// *does* — a condition that has been inert since the day it was written would
/// begin moving or trashing files at the next launch, with nobody at the desk
/// and nothing said. This module's own repair policy is that a value it cannot
/// use matches nothing rather than something; making one match more than it did
/// yesterday is the direction that needs a person's press behind it, and typing
/// is that press.
///
/// So the parse moved out of `ConditionRow`'s binding and into the engine, where
/// it can be read back: the view calls `RuleCondition.fileExtension(typed:)` and
/// this is what that answers.
final class ADotTypedIntoTheExtensionFieldTests: XCTestCase {

    private func typed(_ text: String) -> [String] {
        guard case let .fileExtension(list) = RuleCondition.fileExtension(typed: text) else {
            return ["not a fileExtension condition"]
        }
        return list
    }

    /// The premise: what the field already did, which this must go on doing.
    func testTheListItAlreadyTookIsUnchanged() {
        XCTAssertEqual(typed("pdf, png, zip"), ["pdf", "png", "zip"])
        XCTAssertEqual(typed("PDF , Png"), ["pdf", "png"], "the field has always lowercased")
        XCTAssertEqual(typed("pdf,,png"), ["pdf", "png"], "an empty entry is not an extension")
        XCTAssertEqual(typed(""), [], "an empty field is an unfinished condition, not a wildcard")
    }

    /// The finding.
    func testAnExtensionTypedWithItsDotIsTheExtension() {
        XCTAssertEqual(typed(".pdf"), ["pdf"])
        XCTAssertEqual(typed(" .PDF , .png"), ["pdf", "png"])
        XCTAssertEqual(typed("..pdf"), ["pdf"], "however many dots somebody typed")
    }

    /// And the half that must not be bought with it: a dot on its own is not an
    /// extension, so it cannot become the entry that matches every file in the
    /// folder.
    func testADotOnItsOwnIsNotAnExtension() {
        XCTAssertEqual(typed("."), [])
        XCTAssertEqual(typed(". , .. , .pdf"), ["pdf"])
        XCTAssertFalse(RuleCondition.fileExtension(typed: ".").isComplete,
                       "a condition of nothing must not be one a rule may be switched on with")
        XCTAssertTrue(RuleCondition.fileExtension(typed: ".pdf").isComplete)
    }

    /// The consequence, asked of the thing that decides: the rule a person typed
    /// with a dot acts on the file they meant.
    func testTheRuleAPersonTypedWithADotActsOnTheFile() {
        let rule = Rule(id: "r", name: "sort them", enabled: true, match: .all,
                        conditions: [RuleCondition.fileExtension(typed: ".pdf")],
                        action: .sortIntoSubfolder(.kind))
        let facts = FileFacts(name: "report.pdf", path: "/Users/x/Downloads/report.pdf",
                              kind: .document, bytes: 1,
                              added: Date(timeIntervalSince1970: 0),
                              modified: Date(timeIntervalSince1970: 0),
                              now: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(RuleMatcher.matches(facts, rule))
    }

    /// And the rules already stored are left exactly as they are, which is the
    /// other half of the decision above: `storable` is what every launch reads
    /// the plist through, and a condition that has never matched anything must
    /// not start matching because Helm was updated.
    func testAStoredConditionIsNotRepairedBehindAnybodysBack() {
        XCTAssertEqual(RuleCondition.fileExtension([".pdf"]).storable,
                       .fileExtension([".pdf"]))
    }
}
