import XCTest
@testable import HelmUI

/// The verdict a removal ends on, and which sentence it draws: nothing removed
/// and nothing refused says nothing, any refusal is said, a reply that never
/// came is not silence, and one whose rescan was lost too is not the same
/// verdict as one whose rescan answered.
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

    /// The fourth verdict: a reply that never came.
    ///
    /// Not derivable from the numbers, which is why it cannot come from
    /// `verdict(removed:failed:)` — a lost reply has no numbers, and folding it
    /// to zeroes is exactly how three modules turned it into `.silent`. It comes
    /// from its own entry point instead, so «nothing came back, and five moved»
    /// is not a state anybody can build.
    func testAReplyThatNeverCameIsNotSilence() {
        XCTAssertEqual(HelmRemovalOutcome.unanswered.verdict, .unanswered)
        XCTAssertNotEqual(HelmRemovalOutcome.unanswered.verdict, .silent,
                          "a removal nobody answered draws nothing at all")
    }

    /// And a reply that did come never reads as one that did not, whatever it
    /// carried — the half that keeps the new verdict from swallowing the others.
    func testAReplyThatArrivedIsNeverReadAsLost() {
        for (removed, failed) in [(0, 0), (3, 0), (0, 1), (3, 1)] {
            XCTAssertNotEqual(HelmRemovalOutcome.verdict(removed: removed, failed: failed),
                              .unanswered,
                              "a reply carrying \(removed)/\(failed) read as no reply at all")
        }
    }

    /// The fifth verdict, and it is not the fourth: a round where the rescan
    /// answered and one where it did not are different states, and the sentence
    /// is the only thing that can tell the person which they are in.
    func testAStaleListIsNotTheSameVerdictAsAFreshOne() {
        XCTAssertEqual(HelmRemovalOutcome.unansweredWithStaleList.verdict, .unansweredStaleList)
        XCTAssertNotEqual(HelmRemovalOutcome.unansweredWithStaleList.verdict,
                          HelmRemovalOutcome.unanswered.verdict, """
                          a removal whose rescan was also lost draws the sentence promising the \
                          list above is where the files are now.
                          """)
    }
}
