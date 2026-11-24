import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_UI

/// «Clear selection» during a removal is refused: `emptyBasket` captures the
/// paths at its first line, so the request is already out with them, and an
/// emptied basket would be followed by «Moved to the Trash» about the very
/// selection the person had just cleared.
///
/// `DuplicatesEngine.trash` verifies every pair before anything moves,
/// serially, so the window between the press and the reply is minutes on an
/// external drive.
///
/// The guard is on the model *and* the page dims the button — both, or neither is
/// reliable (Architecture/Removal.md § One removal at a time). And it is on the press,
/// not on the reading: `LeftoversViewModel.dropHiddenSelections` records what the
/// naive version costs, where a removal holds `busy` across its own rescan.
@MainActor
final class ClearSelectionIsNotAWayOutOfRemovalTests: XCTestCase {


    func testClearingTheSelectionIsRefusedWhileTheFilesAreGoing() async {
        let (dvm, work) = await removalInFlight()
        XCTAssertEqual(work.parkedCount, 1, "precondition: the removal is really in flight")
        XCTAssertTrue(dvm.busy, "precondition: the model knows a removal is running")
        XCTAssertEqual(dvm.basket, [extraCopy], "precondition: the selection is what was sent")

        dvm.clearBasket()

        XCTAssertEqual(dvm.basket, [extraCopy], """
            the basket emptied on screen while the request was still out with those paths in it, \
            so the app reported success about a selection the person had just cleared
            """)
        await releaseRemoval(dvm, work)
    }

    /// And it works again the moment the removal is over, or the guard has taken
    /// the control away rather than deferred it.
    func testClearingTheSelectionWorksOnceTheRemovalIsAnswered() async {
        let (dvm, work) = await removalInFlight()
        await releaseRemoval(dvm, work)
        XCTAssertFalse(dvm.busy, "precondition: the removal came back")
        // Marking is refused while the removal runs, so it is done after.
        dvm.toggleBasket(secondCopy)
        XCTAssertFalse(dvm.basket.isEmpty, "precondition: something is marked")

        dvm.clearBasket()

        XCTAssertTrue(dvm.basket.isEmpty, "the guard outlived the removal it was for")
    }
}
