import XCTest
@testable import Module_Autopilot_Engine

/// The preview said what would happen and not where.
///
/// Seen on a live folder: the editor listed two invoices and "sort into
/// subfolders by kind" against each, and the only thing the person could not
/// have worked out for themselves — which subfolder — was the part left out.
final class PlannedDestinationTests: XCTestCase {

    private let moment = Date(timeIntervalSince1970: 1_780_000_000)

    private func facts(_ name: String) -> FileFacts {
        FileFacts(name: name, path: "/tmp/\(name)", kind: .document, bytes: 10,
                  added: moment, modified: moment)
    }

    private func plan(_ name: String, _ action: RuleAction) -> RulePlan {
        RulePlan(facts: facts(name), rule: Rule(name: "r", action: action))
    }

    func testSortingNamesTheBucketItWouldUse() {
        let described = PlannedDestination.describe(plan("invoice.pdf", .sortIntoSubfolder(.kind)))
        XCTAssertEqual(described, SortBucket.name(for: facts("invoice.pdf"), scheme: .kind),
                       "the same answer the runner will get")
        XCTAssertNotNil(described)
    }

    func testMovingNamesTheFolderNotTheWholePath() {
        XCTAssertEqual(PlannedDestination.describe(plan("a.pdf", .move(to: "/Users/x/Papers"))),
                       "Papers")
    }

    func testRenamingShowsTheNameItWouldGet() {
        let described = PlannedDestination.describe(plan("a.pdf", .rename(pattern: "{name}-copy")))
        XCTAssertEqual(described, RenamePattern.apply("{name}-copy", to: facts("a.pdf")))
    }

    /// Trashing and tagging do not relocate anything, and a destination
    /// invented for them would read as if they did.
    func testActionsWithNoDestinationSayNothing() {
        XCTAssertNil(PlannedDestination.describe(plan("a.pdf", .trash)))
        XCTAssertNil(PlannedDestination.describe(plan("a.pdf", .addTag("Red"))))
    }
}
