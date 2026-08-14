import XCTest
import Module_Leftovers_Engine

/// **The all-clear is this module's strongest claim about somebody's Mac, and it
/// was drawn over items nobody had judged.**
///
/// A scan reaches `.undetermined` when a reading its verdict depends on did not
/// happen — `systemextensionsctl` did not answer, or the program a job points at
/// sits somewhere this process may not search — and `.unreadable` when the file
/// itself would not open. Both of those already choose the safe direction and
/// both already reach the log. Neither reached the screen: the rows are not
/// `.orphaned`, so the default filter drops them, `visible` falls to zero and the
/// page drew a green check over «No leftovers found».
///
/// So there is a fourth reason for an empty list, and it carries its own count —
/// the sentence about it cannot be built from a number fetched separately.
final class AScanThatCouldNotJudgeItAllSaysSoTests: XCTestCase {

    /// The three statuses that are a verdict, and the two that are the absence of
    /// one. Exhaustive at the property rather than here, so a sixth status is a
    /// build error and not a row silently counted as judged.
    func testAVerdictIsToldFromTheAbsenceOfOne() {
        XCTAssertTrue(ItemStatus.orphaned.judged)
        XCTAssertTrue(ItemStatus.inUse.judged)
        XCTAssertTrue(ItemStatus.protectedItem.judged)
        XCTAssertFalse(ItemStatus.undetermined.judged, """
            «Not checked» is the badge on a row whose verdict was never reached, and counting it \
            as judged is what lets the all-clear be drawn over it.
            """)
        XCTAssertFalse(ItemStatus.unreadable.judged,
                       "a file Helm never got to read was not judged either")
    }

    /// The state this exists for: nothing left over, nothing hidden, and three
    /// items the scan could not reach a verdict on.
    func testAnEmptyListWithItemsUnjudgedDoesNotClaimAllClear() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: true, visible: 0,
                                             hiddenByKind: 0, unchecked: 3),
                       .notEverythingChecked(3), """
                       a scan that could not judge three items drew the green check over «No \
                       leftovers found» — the one claim on this page about the state of \
                       somebody's Mac, made while three items sat unjudged.
                       """)
    }

    /// And the count travels with the reason, because the sentence interpolates
    /// it: a `Reason` that carried no number would have the page fetch one from
    /// somewhere else, which is two answers to one question.
    func testTheCountTravelsWithTheReason() {
        XCTAssertNotEqual(LeftoversEmpty.reason(scanned: true, visible: 0,
                                                hiddenByKind: 0, unchecked: 1),
                          LeftoversEmpty.reason(scanned: true, visible: 0,
                                                hiddenByKind: 0, unchecked: 3))
    }

    /// The half that keeps the new reason from being the only one: a scan that
    /// judged everything and found nothing still says so.
    func testAScanThatJudgedEverythingStillSaysNothingWasFound() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: true, visible: 0,
                                             hiddenByKind: 0, unchecked: 0),
                       .nothingFound)
    }

    /// The filter keeps its precedence. «Everything found is hidden by the
    /// filter» is a claim about a menu on screen directly above the message, and
    /// it is not the claim the unjudged items contradict — nothing about a clean
    /// Mac is being said there.
    func testTheFilterStillSpeaksFirst() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: true, visible: 0,
                                             hiddenByKind: 7, unchecked: 3),
                       .hiddenByFilter)
    }

    /// And a list with rows in it is not an empty state, whatever went unjudged —
    /// the toolbar's own line is what carries the count there.
    func testARowToDrawIsStillNotAnEmptyList() {
        XCTAssertNil(LeftoversEmpty.reason(scanned: true, visible: 2,
                                           hiddenByKind: 0, unchecked: 3))
    }

    /// Before the first scan nothing has been asked of the machine, so nothing
    /// went unanswered either.
    func testAnUnscannedPageStillInvites() {
        XCTAssertEqual(LeftoversEmpty.reason(scanned: false, visible: 0,
                                             hiddenByKind: 0, unchecked: 4),
                       .notScanned)
    }

    /// **It invites.** A statement gets no button, and this one is not a
    /// statement about the Mac — it says Helm did not finish, and the verb that
    /// answers that is on the Scan button. `LeftoversSettingsPage` asks the same
    /// function to decide whether the toolbar draws one instead, so the two
    /// cannot come apart.
    func testTheScanAgainButtonIsOfferedForIt() {
        XCTAssertTrue(LeftoversEmpty.invites(.notEverythingChecked(3)), """
            the screen that says Helm could not check everything offered no way to try again: \
            the empty state draws no verb and the toolbar hides its Scan behind the same rule.
            """)
    }
}
