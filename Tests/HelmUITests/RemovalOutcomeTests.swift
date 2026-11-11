import XCTest
@testable import HelmUI

/// The verdict a removal ends on, and which sentence it draws: nothing removed
/// and nothing refused says nothing, any refusal is said.
final class RemovalOutcomeTests: XCTestCase {

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
