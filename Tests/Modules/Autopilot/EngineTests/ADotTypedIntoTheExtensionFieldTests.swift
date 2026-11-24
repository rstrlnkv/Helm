import XCTest
@testable import Module_Autopilot_Engine

/// «.pdf» is what people type, and the extension is kept without its dot.
///
/// `RuleCondition.fileExtension` holds "Lowercase, no dots", and `RuleMatcher`
/// compares the list against `FileFacts.fileExtension`, which never carries one.
/// A dot kept from the field gives a condition that is `isComplete`, may be
/// switched on, and never matches a file: it fails safe and silently.
///
/// The repair is where the text is entered (`RuleCondition.fileExtension(typed:)`,
/// which the view calls), deliberately not in `storable`. `storable` runs over
/// the stored rules too, so a repair there would make a condition inert since
/// the day it was written begin moving or trashing files at the next launch,
/// with nobody at the desk. A value the module cannot use matches nothing;
/// making a rule match more needs a person's press behind it, and typing is one.
final class ADotTypedIntoTheExtensionFieldTests: XCTestCase {

    private func typed(_ text: String) -> [String] {
        guard case let .fileExtension(list) = RuleCondition.fileExtension(typed: text) else {
            return ["not a fileExtension condition"]
        }
        return list
    }

    /// The premise: a list typed without dots is lowercased, trimmed and split.
    func testTheListItAlreadyTookIsUnchanged() {
        XCTAssertEqual(typed("pdf, png, zip"), ["pdf", "png", "zip"])
        XCTAssertEqual(typed("PDF , Png"), ["pdf", "png"], "the field has always lowercased")
        XCTAssertEqual(typed("pdf,,png"), ["pdf", "png"], "an empty entry is not an extension")
        XCTAssertEqual(typed(""), [], "an empty field is an unfinished condition, not a wildcard")
    }

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

    /// A stored condition is left as it is: every launch reads the plist through
    /// `storable`, and a condition that never matched must not start matching
    /// because Helm was updated.
    func testAStoredConditionIsNotRepairedBehindAnybodysBack() {
        XCTAssertEqual(RuleCondition.fileExtension([".pdf"]).storable,
                       .fileExtension([".pdf"]))
    }
}
