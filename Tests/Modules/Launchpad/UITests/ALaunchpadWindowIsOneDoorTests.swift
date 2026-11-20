import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The window opens only through the model: two presses of «open» are one window, the shortcut opens then closes, a
/// window that closed itself is forgotten, a stopped model opens nothing, and a model nobody gave a window builder opens none.
@MainActor
final class ALaunchpadWindowIsOneDoorTests: XCTestCase {

    final class FakeWindow: LaunchpadWindowHandle {
        var onClose: (@MainActor () -> Void)?
        var closes = 0
        var forwards = 0
        var presents = 0
        var begun: [PinchDirection] = []
        var scrubbed: [Double] = []
        var ends: [PinchOutcome] = []
        func present() { presents += 1 }
        func close() { closes += 1; onClose?() }
        func bringForward() { forwards += 1 }
        func beginScrub(_ direction: PinchDirection) { begun.append(direction) }
        func scrub(to progress: Double) { scrubbed.append(progress) }
        func endScrub(_ outcome: PinchOutcome) { ends.append(outcome) }
    }

    private func rig(_ label: String) -> (LaunchpadRig, built: () -> [FakeWindow]) {
        let rig = LaunchpadRig(self, label: label)
        var made: [FakeWindow] = []
        rig.model.present = { _ in let w = FakeWindow(); made.append(w); return w }
        return (rig, { made })
    }

    func testTwoShowsAreOneWindow() {
        let (rig, built) = rig("door-two")
        rig.model.showLaunchpad()
        rig.model.showLaunchpad()
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].forwards, 1, "the second press brings the open one forward")
    }

    func testToggleOpensThenCloses() {
        let (rig, built) = rig("door-toggle")
        rig.model.toggleLaunchpad()
        XCTAssertEqual(built().count, 1)
        XCTAssertEqual(built()[0].closes, 0)
        rig.model.toggleLaunchpad()
        XCTAssertEqual(built()[0].closes, 1)
        rig.model.toggleLaunchpad()
        XCTAssertEqual(built().count, 2, "after a close the next press opens a new one")
    }

    func testAWindowThatClosedItselfIsForgotten() {
        let (rig, built) = rig("door-forget")
        rig.model.showLaunchpad()
        built()[0].onClose?()
        rig.model.showLaunchpad()
        XCTAssertEqual(built().count, 2)
        XCTAssertEqual(built()[0].forwards, 0)
    }

    func testStopClosesAndNothingOpensAfterIt() {
        let (rig, built) = rig("door-stop")
        rig.model.showLaunchpad()
        rig.model.stop()
        XCTAssertEqual(built()[0].closes, 1)
        rig.model.showLaunchpad()
        rig.model.toggleLaunchpad()
        XCTAssertEqual(built().count, 1)
    }

    func testWithoutAWindowBuilderNothingOpens() {
        let rig = LaunchpadRig(self, label: "door-nil")
        rig.model.showLaunchpad()
        rig.model.toggleLaunchpad()
        rig.model.closeLaunchpad()
    }
}
