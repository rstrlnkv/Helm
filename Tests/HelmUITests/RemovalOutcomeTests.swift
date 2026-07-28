import XCTest
@testable import HelmUI

/// The line above a removal that did not entirely work.
///
/// Disk composes its success sentence before it knows the outcome, so a batch
/// where every path refused produced "Removed — 0 bytes freed — 1 item could
/// not be moved": a claim, its own refutation, and two em-dashes, in one
/// caption. Seen on a real run against a read-only folder.
///
/// These assert the shape rather than one language's wording — the suite runs
/// in whatever language the machine is set to, and the defect was structural.
final class RemovalOutcomeTests: XCTestCase {

    private let claim = "REMOVED-CLAIM"

    func testNothingRemovedMeansNoClaimThatAnythingWas() {
        let line = HelmRemovalOutcome.heading(succeeded: nil, failed: 1)
        XCTAssertFalse(line.contains("—"), "no dash left where the claim used to be: \(line)")
        XCTAssertFalse(line.isEmpty)
    }

    func testSomethingRemovedKeepsBothHalves() {
        let line = HelmRemovalOutcome.heading(succeeded: claim, failed: 1)
        XCTAssertTrue(line.contains(claim), "the success half is still said: \(line)")
        XCTAssertTrue(line.contains("—"), "and it is joined to the failure half: \(line)")
    }

    /// The failed count is a counted noun, so the sentence has to change with it
    /// — "1 объект" and "3 объекта" are different words, not a different digit.
    func testTheCountedNounFollowsTheCount() {
        let one = HelmRemovalOutcome.heading(succeeded: nil, failed: 1)
        let three = HelmRemovalOutcome.heading(succeeded: nil, failed: 3)
        XCTAssertNotEqual(one, three)
        XCTAssertTrue(one.contains("1"))
        XCTAssertTrue(three.contains("3"))
    }

    /// The branch that was still not asking.
    ///
    /// `removed` exists because "the sentence cannot be asked whether it is
    /// true", and the failure branch does ask it — but the `failures.isEmpty`
    /// branch printed `succeededText` without ever looking. Callers build that
    /// sentence before they know the outcome and default every count to zero,
    /// so an engine reply carrying nothing at all rendered "Moved to Trash —
    /// 0 bytes freed" while the row it was about was still on screen. Reachable
    /// in the uninstaller's orphans view: paths that were already gone are
    /// deliberately counted as neither trashed nor failed, so both lists come
    /// back empty.
    ///
    /// Nothing happened, so the honest line is no line. That needs no new
    /// wording — the existing sentences are all about something that did.
    func testNothingRemovedAndNothingRefusedSaysNothing() {
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 0, failed: 0), .silent)
    }

    func testSomethingRemovedWithNoRefusalsIsTheSuccessSentence() {
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 3, failed: 0), .succeeded)
    }

    /// A refusal is always worth saying, whether or not anything else worked —
    /// that is the whole reason this component exists.
    func testAnyRefusalIsReported() {
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 0, failed: 1), .failed)
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 3, failed: 1), .failed)
    }
}
