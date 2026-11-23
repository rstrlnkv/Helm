import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// With Reduce Motion nothing follows the hand: the window opens or closes at once where the gesture reaches 1 or, short of it, where it ends
/// complete, and never twice. A second `complete` over an open window is a `bringForward`, and over a closed one a second `present`, so
/// the counts of `forwards`, `presents` and `closes` tell. `AHalfOpenWindowIsNeverLeftBehindTests` counts presents only.
@MainActor
final class AReducedMotionHandActsOnceTests: XCTestCase {
    private typealias Fake = ALaunchpadWindowIsOneDoorTests.FakeWindow

    private func rig(_ label: String) -> (LaunchpadRig, built: () -> [Fake]) {
        let rig = LaunchpadRig(self, label: label)
        rig.model.reduceMotion = { true }
        var made: [Fake] = []
        rig.model.present = { _ in let w = Fake(); made.append(w); return w }
        return (rig, { made })
    }

    func testAPinchThatReached1AndThenEndedCompleteOpensOnceAndNeverBringsForward() {
        let (rig, built) = rig("once-pinch")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(1))
        XCTAssertEqual(built().count, 1, "the subject: it acted at 1")
        rig.model.pinched(.moved(1))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].presents, 1)
        XCTAssertEqual(built()[0].forwards, 0, "a second complete brought the new window forward")
    }

    func testAPinchThatBeganAt1AndEndedCompleteOpensOnce() {
        let (rig, built) = rig("once-began-1")
        rig.model.pinched(.began(.pinch, progress: 1))
        XCTAssertEqual(built().count, 1, "the subject: it acted at the began")
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built()[0].presents, 1)
        XCTAssertEqual(built()[0].forwards, 0)
    }

    func testASpreadThatReached1AndThenEndedCompleteClosesOnce() {
        let (rig, built) = rig("once-spread")
        rig.model.showLaunchpad()
        rig.model.pinched(.began(.spread, progress: 0.1))
        rig.model.pinched(.moved(1))
        XCTAssertEqual(built()[0].closes, 1, "the subject: it acted at 1")
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built()[0].closes, 1)
        XCTAssertEqual(built().count, 1, "a second complete would be a spread over nothing; it must not open another")
    }

    func testTheNextHandAfterAnActedOneActsAgain() {
        let (rig, built) = rig("once-next")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(1))
        rig.model.pinched(.ended(.complete))
        rig.model.pinched(.began(.spread, progress: 0.1))
        rig.model.pinched(.moved(1))
        XCTAssertEqual(built()[0].closes, 1, "the spent mark ended with the hand")
        rig.model.pinched(.ended(.complete))
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built().count, 2)
        XCTAssertEqual(built()[1].presents, 1)
    }

    func testAHandWhoseEndIsOnlyARevertAfterItActedDoesNotUndoIt() {
        let (rig, built) = rig("once-revert-after")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(1))
        rig.model.pinched(.ended(.revert))
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].closes, 0)
        XCTAssertTrue(built()[0].ends.isEmpty)
    }
}
