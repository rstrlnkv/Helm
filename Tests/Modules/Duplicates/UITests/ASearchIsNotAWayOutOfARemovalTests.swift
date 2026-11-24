import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_UI

/// «Search again» during a removal is refused, like Clear the marks
/// (`ClearSelectionIsNotAWayOutOfRemovalTests`).
///
/// `search()` empties the groups, the basket and the removal report. The
/// toolbar's Search button is drawn for `phase != .searching`, which during a
/// removal is `.result`, so it is live for the whole removal — minutes here,
/// because `DuplicatesEngine.trash` verifies every pair before anything moves.
///
/// Two things would go with the basket: the count and the marks the request is
/// out with, and **the way out** — the page draws the removal's tick and the
/// Stop button inside `basketBar`, which is drawn only for a non-empty basket,
/// a report or a marks note, so a removal would run on with no control on
/// screen that reaches it.
///
/// Parked, never answered on the spot: a removal that returns before the press
/// under test is a window nothing can be inside, and every assertion here would
/// hold with the gate deleted.
@MainActor
final class ASearchIsNotAWayOutOfARemovalTests: XCTestCase {


    /// The request is out with those paths in it, so nothing on screen may say
    /// they are unmarked.
    func testSearchingWhileTheFilesAreGoingKeepsTheSelectionTheRequestIsOutWith() async {
        let (dvm, work) = await removalInFlight()
        XCTAssertEqual(work.parkedCount, 1, "precondition: the removal is really in flight")
        XCTAssertTrue(dvm.busy, "precondition: the model knows a removal is running")
        XCTAssertEqual(dvm.basket, [extraCopy], "precondition: the selection is what was sent")

        dvm.search()

        XCTAssertEqual(dvm.basket, [extraCopy], """
            «Search again» emptied the basket while the removal was still out with those paths \
            in it — the same press `clearBasket` grew a `guard !busy` for, in the control next \
            to it
            """)
        await releaseRemoval(dvm, work)
    }

    /// `DuplicatesSettingsPage`'s own condition for drawing `basketBar` — the
    /// one place on the page that reads `dvm.busy`, and therefore the only place
    /// the removal's tick and its Stop button can appear.
    ///
    /// Mirrored rather than rendered, and spelled from the same three published
    /// values the page reads, so a page that starts drawing the bar on something
    /// else makes this read wrong at a glance instead of passing quietly.
    private func pageDrawsTheBasketBar(_ dvm: DuplicatesViewModel) -> Bool {
        let hasReport = dvm.removalStopped
            || dvm.banner != nil || !dvm.failures.isEmpty
        return !dvm.basket.isEmpty || hasReport || dvm.marksNote != nil
    }

    /// And the removal is still running, so this is not «the search cancelled
    /// it»: it is the screen forgetting a destructive act that is still under
    /// way, and taking the only way out of it with the basket.
    func testTheRemovalInFlightStillHasSomewhereToDrawItsStop() async {
        let (dvm, work) = await removalInFlight()
        XCTAssertTrue(pageDrawsTheBasketBar(dvm), "precondition: the bar is up before the press")

        dvm.search()

        XCTAssertTrue(dvm.busy, "precondition: pressing Search did not end the removal")
        XCTAssertEqual(work.parkedCount, 1, "precondition: the removal request is still parked")
        XCTAssertTrue(pageDrawsTheBasketBar(dvm), """
            the basket, the report and the marks note all went down in one press, and the page \
            draws the removal's tick and its Stop button inside the bar those three bring up — \
            so a removal the person started has no control anywhere on screen that reaches it
            """)
        await grace()
        XCTAssertTrue(dvm.busy, "precondition: still running once the search has answered")
        XCTAssertTrue(pageDrawsTheBasketBar(dvm),
                      "and the search answering does not bring the Stop control back either")
        await releaseRemoval(dvm, work)
    }
}
