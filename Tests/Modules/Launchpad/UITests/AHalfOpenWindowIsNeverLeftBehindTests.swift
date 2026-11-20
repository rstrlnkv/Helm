import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A scrub that began a window must end it: the window opened by the fingers' pinch is shown without a `present()`, and it is
/// closed, kept or detached on every way the scrub ends or the model goes. The window stands in as a fake that counts what it was told.
@MainActor
final class AHalfOpenWindowIsNeverLeftBehindTests: XCTestCase {
    private typealias Fake = ALaunchpadWindowIsOneDoorTests.FakeWindow

    private func rig(_ label: String, reduced: Bool = false) -> (LaunchpadRig, built: () -> [Fake]) {
        let rig = LaunchpadRig(self, label: label)
        rig.model.reduceMotion = { reduced }
        var made: [Fake] = []
        rig.model.present = { _ in let w = Fake(); made.append(w); return w }
        return (rig, { made })
    }

    func testAPinchBeginsOneWindowWithAScrubAndNeverPresentsIt() {
        let (rig, built) = rig("half-begin")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(0.4))
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].begun, [.pinch])
        XCTAssertEqual(built()[0].scrubbed, [0.1, 0.4])
        XCTAssertEqual(built()[0].presents, 0, "a window the fingers hold is not presented (made key) until they complete")
    }

    func testACompletedPinchEndsTheScrubCompleteAndStillNeverPresents() {
        let (rig, built) = rig("half-complete")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built()[0].ends, [.complete])
        XCTAssertEqual(built()[0].presents, 0)
        XCTAssertEqual(built()[0].closes, 0)
        rig.model.pinched(.moved(0.5))
        XCTAssertEqual(built()[0].scrubbed, [0.1], "after the end the fingers say nothing to it")
        rig.model.showLaunchpad()
        XCTAssertEqual(built().count, 1, "the window is kept: the next press brings it forward")
        XCTAssertEqual(built()[0].forwards, 1)
    }

    func testARevertedPinchDetachesTheWindowAndTheNextPressMakesAnother() {
        let (rig, built) = rig("half-revert")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.ended(.revert))
        XCTAssertEqual(built()[0].ends, [.revert])
        rig.model.showLaunchpad()
        XCTAssertEqual(built().count, 2, "the half-open window was forgotten before it was reverted")
        XCTAssertEqual(built()[0].forwards, 0)
        XCTAssertEqual(built()[1].presents, 1)
    }

    func testASpreadScrubsTheOpenWindowAndRevertingItKeepsIt() {
        let (rig, built) = rig("half-spread-revert")
        rig.model.showLaunchpad()
        rig.model.pinched(.began(.spread, progress: 0.2))
        rig.model.pinched(.moved(0.3))
        XCTAssertEqual(built()[0].begun, [.spread])
        XCTAssertEqual(built()[0].scrubbed, [0.2, 0.3])
        rig.model.pinched(.ended(.revert))
        XCTAssertEqual(built()[0].ends, [.revert])
        rig.model.showLaunchpad()
        XCTAssertEqual(built().count, 1, "a closing that was reverted left the window open")
    }

    func testACompletedSpreadDetachesTheWindowBeforeItEnds() {
        let (rig, built) = rig("half-spread-complete")
        rig.model.showLaunchpad()
        rig.model.pinched(.began(.spread, progress: 0.2))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built()[0].ends, [.complete])
        rig.model.showLaunchpad()
        XCTAssertEqual(built().count, 2, "the closing window was forgotten at once")
    }

    func testASpreadWithNoWindowAndAPinchOverAnOpenOneScrubNothing() {
        let (rig, built) = rig("half-nothing")
        rig.model.pinched(.began(.spread, progress: 0.2))
        rig.model.pinched(.moved(0.5))
        rig.model.pinched(.ended(.complete))
        XCTAssertTrue(built().isEmpty)
        rig.model.showLaunchpad()
        rig.model.pinched(.began(.pinch, progress: 0.2))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].forwards, 1, "a completed pinch over an open window brings it forward")
        XCTAssertTrue(built()[0].begun.isEmpty)
    }

    func testStopInsideAScrubClosesTheWindowOnceAndTheFingersAreIgnoredAfter() {
        let (rig, built) = rig("half-stop")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.stop()
        XCTAssertEqual(built()[0].closes, 1)
        rig.model.pinched(.moved(0.9))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built()[0].scrubbed, [0.1])
        XCTAssertTrue(built()[0].ends.isEmpty)
        XCTAssertEqual(built()[0].closes, 1)
    }

    func testTheShortcutClosingInsideAScrubEndsItForTheWindowThatOpensNext() {
        let (rig, built) = rig("half-shortcut")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.closeLaunchpad()
        rig.model.showLaunchpad()
        rig.model.pinched(.moved(0.9))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built().count, 2, "the subject: a window opened after the close")
        XCTAssertEqual(built()[0].closes, 1)
        XCTAssertTrue(built()[1].scrubbed.isEmpty, "the old scrub reached the new window")
        XCTAssertTrue(built()[1].ends.isEmpty)
    }

    func testAWindowThatClosedItselfInsideAScrubIsNotScrubbedFurther() {
        let (rig, built) = rig("half-onclose")
        rig.model.pinched(.began(.pinch, progress: 0.1))
        built()[0].onClose?()
        rig.model.showLaunchpad()
        rig.model.pinched(.moved(0.9))
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built().count, 2, "the subject: the press opened another window")
        XCTAssertEqual(built()[0].scrubbed, [0.1])
        XCTAssertTrue(built()[0].ends.isEmpty)
        XCTAssertTrue(built()[1].scrubbed.isEmpty, "the old scrub reached the new window")
        XCTAssertTrue(built()[1].ends.isEmpty)
    }

    func testWithReducedMotionNothingFollowsTheHandAndTheEndOfTheGestureActsOnce() {
        let (rig, built) = rig("half-reduced", reduced: true)
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(0.6))
        XCTAssertTrue(built().isEmpty, "nothing opens before the threshold")
        rig.model.pinched(.moved(1))
        rig.model.pinched(.moved(1))
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].presents, 1)
        XCTAssertTrue(built()[0].begun.isEmpty)
        rig.model.pinched(.ended(.complete))
        rig.model.pinched(.began(.spread, progress: 0.1))
        rig.model.pinched(.moved(1))
        XCTAssertEqual(built()[0].closes, 1)
    }

    /// Owner: under Reduce Motion a gesture that completes below 1 (released past the midpoint or flicked) acts at once, once.
    func testWithReducedMotionAReleaseThatCompletesBelowOneActsAtOnce() {
        let (rig, built) = rig("half-reduced-release", reduced: true)
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(0.6))
        XCTAssertTrue(built().isEmpty, "the subject: nothing acted before the release")
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].presents, 1)
        rig.model.pinched(.began(.spread, progress: 0.1))
        rig.model.pinched(.moved(0.6))
        XCTAssertEqual(built()[0].closes, 0)
        rig.model.pinched(.ended(.complete))
        XCTAssertEqual(built()[0].closes, 1)
    }

    func testWithReducedMotionAReleaseThatRevertsDoesNothing() {
        let (rig, built) = rig("half-reduced-revert", reduced: true)
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(0.3))
        rig.model.pinched(.ended(.revert))
        XCTAssertTrue(built().isEmpty)
    }

    func testAScrubWithNoWindowBuilderDoesNothingAndDoesNotCrash() {
        let rig = LaunchpadRig(self, label: "half-nobuilder")
        rig.model.reduceMotion = { false }
        rig.model.pinched(.began(.pinch, progress: 0.1))
        rig.model.pinched(.moved(0.5))
        rig.model.pinched(.ended(.complete))
    }
}
