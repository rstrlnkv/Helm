import XCTest
import HelmRuntime
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A fire lands on the main queue some time after it was recognized: by then the model may be stopped, the window already open
/// or never built. A pinch is the shortcut's press split in two, so each half is idempotent and nothing outlives `stop()`.
@MainActor
final class APinchReachesTheWindowOnlyThroughTheModelTests: XCTestCase {
    private func rig(_ label: String) -> (LaunchpadRig, built: () -> [ALaunchpadWindowIsOneDoorTests.FakeWindow]) {
        let rig = LaunchpadRig(self, label: label)
        var made: [ALaunchpadWindowIsOneDoorTests.FakeWindow] = []
        rig.model.present = { _ in let w = ALaunchpadWindowIsOneDoorTests.FakeWindow(); made.append(w); return w }
        return (rig, { made })
    }

    func testTwoPinchesAreOneWindowAndASpreadClosesItOnce() {
        let (rig, built) = rig("pinch-door")
        rig.model.pinched(.pinch)
        rig.model.pinched(.pinch)
        XCTAssertEqual(built().count, 1)
        rig.model.pinched(.spread)
        rig.model.pinched(.spread)
        XCTAssertEqual(built()[0].closes, 1)
    }

    func testASpreadWithNothingOpenDoesNothing() {
        let (rig, built) = rig("pinch-spread-closed")
        rig.model.pinched(.spread)
        XCTAssertTrue(built().isEmpty)
    }

    func testAFireThatLandsAfterStopOpensNothingEitherWay() {
        let (rig, built) = rig("pinch-stopped")
        rig.model.stop()
        rig.model.pinched(.pinch)
        rig.model.pinched(.spread)
        XCTAssertTrue(built().isEmpty)
    }

    func testAFireWithNoWindowBuilderOpensNothingAndDoesNotCrash() {
        let rig = LaunchpadRig(self, label: "pinch-nobuilder")
        rig.model.pinched(.pinch)
        rig.model.pinched(.spread)
    }

    func testTheSwitchAfterStopChangesNothingAndWritesNothing() {
        let rig = LaunchpadRig(self, label: "pinch-switch-stopped")
        rig.model.stop()
        rig.model.setPinch(on: true)
        XCTAssertFalse(rig.model.pinchOn)
        XCTAssertFalse(rig.model.store.bool(LaunchpadPinchKey.on, default: false))
    }

    func testTheSwitchIsWrittenOnceAndTheSameValueTwiceIsNotAChange() {
        let rig = LaunchpadRig(self, label: "pinch-switch-twice")
        rig.model.setPinch(on: true)
        XCTAssertTrue(rig.model.store.bool(LaunchpadPinchKey.on, default: false))
        rig.model.setPinch(on: true)
        rig.model.setPinch(on: false)
        XCTAssertFalse(rig.model.store.bool(LaunchpadPinchKey.on, default: false))
        XCTAssertFalse(rig.model.pinchOn)
    }

    func testReloadingAfterStopTouchesNothing() async {
        let rig = LaunchpadRig(self, label: "pinch-reload-stopped")
        rig.model.stop()
        rig.model.store.set(true, for: LaunchpadPinchKey.on)
        await rig.model.reloadPinch()
        XCTAssertFalse(rig.model.pinchOn)
    }

    func testAnEngineThatIsNotActiveShowsTheSwitchOnWithNothingWatchedAsOffNotAsAHolePage() {
        let rig = LaunchpadRig(self, label: "pinch-inactive")
        rig.model.setPinch(on: true)
        XCTAssertTrue(rig.model.pinchOn)
        XCTAssertEqual(rig.model.pinchState, .off, "nothing watches, and the state line says so")
    }
}
