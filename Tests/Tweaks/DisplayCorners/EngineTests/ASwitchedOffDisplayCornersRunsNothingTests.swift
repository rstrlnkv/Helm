import CoreGraphics
import XCTest
@testable import Tweak_DisplayCorners_Engine

/// **Display Corners with nothing switched on opens no window, starts no timer and listens to no pointer, and
/// one that is stopped leaves nothing running.**
///
/// The engine reaches the machine in `activate()` (a timer, an event tap, mask windows), and does it from one
/// place that asks whether anything is on. Written over fakes that record every start and stop, because the
/// real ports would be whatever it does to this Mac while the suite runs. Each test first shows the subject
/// happened (the engine read its settings, a control run started everything), so a "nothing started" is not
/// the answer of an engine that never ran.
@MainActor
final class ASwitchedOffDisplayCornersRunsNothingTests: XCTestCase {

    private func rig(builtIn: Bool, external: Bool = false) -> Rig {
        let rig = Rig()
        rig.store.set(builtIn, for: "builtIn")
        rig.store.set(external, for: "external")
        return rig
    }

    private func assertNothingRuns(_ rig: Rig, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(rig.events.running, "events: \(message)", file: file, line: line)
        XCTAssertFalse(rig.ticker.isRunning, "ticker: \(message)", file: file, line: line)
        XCTAssertFalse(rig.pointer.running, "pointer: \(message)", file: file, line: line)
        XCTAssertTrue(rig.masks.standing.isEmpty, "masks: \(message)", file: file, line: line)
    }

    func testBothSwitchesOffStartNothing() {
        let rig = rig(builtIn: false)
        rig.engine.activate()
        XCTAssertNotEqual(rig.engine.state, CornerState(), "the subject did not happen: activate() said nothing")
        XCTAssertFalse(rig.engine.state.builtIn)
        XCTAssertEqual(rig.events.starts, 0)
        XCTAssertEqual(rig.ticker.starts, 0)
        XCTAssertEqual(rig.pointer.starts, 0)
        XCTAssertTrue(rig.masks.shows.isEmpty, "a mask was asked for with both switches off")
        XCTAssertEqual(rig.displays.reads, 0, "the displays were read for nothing")
    }

    func testTurningTheSwitchOnStartsAllFourAndOffStopsThemAll() {
        let rig = rig(builtIn: false)
        rig.engine.activate()
        rig.engine.setBuiltIn(true)
        XCTAssertEqual(rig.masks.shows.count, 1, "the control run did not open masks")
        XCTAssertEqual(rig.events.starts, 1)
        XCTAssertEqual(rig.ticker.starts, 1)
        XCTAssertEqual(rig.pointer.starts, 1)
        XCTAssertTrue(rig.events.running && rig.ticker.isRunning && rig.pointer.running)
        XCTAssertEqual(rig.masks.standing.count, 2, "the built-in display's two bottom corners")

        let removals = rig.masks.removals
        rig.engine.setBuiltIn(false)
        assertNothingRuns(rig, "still running after the switch went off")
        XCTAssertEqual(rig.masks.removals, removals + 1, "the masks were not ordered out")
    }

    func testDeactivateStopsEverythingAndIsSafeTwiceAndWithoutActivate() {
        let rig = rig(builtIn: true)
        rig.engine.deactivate()
        rig.engine.deactivate()
        XCTAssertEqual(rig.events.starts + rig.ticker.starts + rig.pointer.starts, 0)

        rig.engine.activate()
        XCTAssertTrue(rig.events.running && rig.ticker.isRunning && rig.pointer.running, "the subject did not happen")
        rig.engine.deactivate()
        assertNothingRuns(rig, "running after deactivate()")
        rig.engine.deactivate()
        assertNothingRuns(rig, "running after the second deactivate()")
        XCTAssertEqual(rig.events.starts, 1)
        XCTAssertEqual(rig.ticker.starts, 1)
        XCTAssertEqual(rig.pointer.starts, 1)
    }

    func testCalibrationAloneOpensTheTopMasksAndNoPointerListener() {
        let rig = rig(builtIn: false)
        rig.engine.activate()
        rig.engine.beginCalibration()
        let added = rig.masks.shows.last?.added ?? []
        XCTAssertEqual(added.count, 2, "the subject did not happen: no preview masks")
        XCTAssertTrue(added.allSatisfy { $0.key.corner.isTop }, "a preview mask on a bottom corner")
        XCTAssertTrue(rig.engine.state.calibrating)
        XCTAssertTrue(rig.ticker.isRunning)
        XCTAssertEqual(rig.pointer.starts, 0, "a coloured preview mask held the pointer")

        rig.engine.endCalibration()
        assertNothingRuns(rig, "running after the preview ended")
        XCTAssertFalse(rig.engine.state.calibrating)
    }

    func testACommandOnAnEngineThatIsNotActiveWritesTheStoreAndNothingElse() {
        let rig = rig(builtIn: false)
        rig.engine.setBuiltIn(true)
        rig.engine.beginCalibration()
        XCTAssertEqual(rig.store.object("builtIn") as? Bool, true, "the subject did not happen: nothing was written")
        XCTAssertEqual(rig.events.starts + rig.ticker.starts + rig.pointer.starts, 0)
        XCTAssertTrue(rig.masks.shows.isEmpty)
        XCTAssertEqual(rig.engine.state, CornerState(), "an engine that is not active said something")
    }

    func testACallbackThatArrivesAfterDeactivateDoesNothing() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        rig.settle()
        rig.ticker.tick()
        XCTAssertEqual(rig.windows.asked.count, 1, "the subject did not happen: the tick sampled nothing")
        rig.pointer.position = CGPoint(x: 0.5, y: 981.5)
        rig.ticker.tick()
        rig.pointer.move(to: CGPoint(x: 0.5, y: 981.5))
        XCTAssertEqual(rig.pointer.warps.count, 1, "the subject did not happen: no correction while active")
        rig.engine.deactivate()

        let shows = rig.masks.shows.count, reads = rig.displays.reads, asked = rig.windows.asked.count
        let locations = rig.pointer.locationReads, warps = rig.pointer.warps.count, starts = rig.ticker.starts
        rig.events.fire(.screensChanged)
        rig.events.fire(.displaysWoke)
        rig.events.fire(.spaceChanged)
        rig.ticker.tick()
        rig.pointer.move(to: CGPoint(x: 0.5, y: 981.5))
        rig.pointer.drop()
        XCTAssertEqual(rig.masks.shows.count, shows)
        XCTAssertEqual(rig.displays.reads, reads)
        XCTAssertEqual(rig.windows.asked.count, asked)
        XCTAssertEqual(rig.pointer.locationReads, locations)
        XCTAssertEqual(rig.pointer.warps.count, warps)
        XCTAssertEqual(rig.ticker.starts, starts)
        assertNothingRuns(rig, "a late callback started something")
    }

    func testALateCallbackAfterDeactivateLeavesWhatTheCardReadsAsItWas() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        rig.settle()
        rig.ticker.tick()
        XCTAssertEqual(rig.engine.state.pointer, .tap, "the subject did not happen: no pointer mode was said")
        rig.engine.deactivate()

        let said = rig.engine.state
        rig.pointer.drop()
        XCTAssertEqual(rig.engine.state, said, "a late mode change from the pointer was taken after deactivate()")
        rig.events.fire(.displaysSlept)
        rig.events.fire(.displaysWoke)
        rig.events.fire(.screensChanged)
        XCTAssertEqual(rig.engine.state, said, "a late system event was taken after deactivate()")
        assertNothingRuns(rig, "a late event started something")
    }

    func testSleepThenDeactivateThenWakeStartsNothing() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        XCTAssertTrue(rig.events.running, "the subject did not happen")
        rig.events.fire(.displaysSlept)
        XCTAssertFalse(rig.ticker.isRunning || rig.pointer.running || !rig.masks.standing.isEmpty, "running through the sleep")
        XCTAssertTrue(rig.events.running, "asleep, the engine must still hear the wake")
        rig.engine.deactivate()
        rig.events.fire(.displaysWoke)
        assertNothingRuns(rig, "the wake after deactivate() started something")
        XCTAssertEqual(rig.events.starts, 1)
    }

    func testActivatingTwiceStartsEachPortOnce() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        rig.engine.activate()
        XCTAssertTrue(rig.events.running && rig.ticker.isRunning && rig.pointer.running, "the subject did not happen")
        XCTAssertEqual(rig.events.starts, 1)
        XCTAssertEqual(rig.ticker.starts, 1)
        XCTAssertEqual(rig.pointer.starts, 1)
        XCTAssertEqual(rig.masks.shows.count, 1)
        rig.engine.beginCalibration()
        rig.engine.activate()
        XCTAssertTrue(rig.engine.state.calibrating, "a second activate() ended a preview that was running")
        rig.engine.deactivate()
        assertNothingRuns(rig, "running after one deactivate() of two activate()")
    }

    func testActivatingAgainAfterDeactivateStartsTheEventsAgain() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        rig.engine.deactivate()
        XCTAssertFalse(rig.events.running, "the subject did not happen")
        rig.engine.activate()
        XCTAssertEqual(rig.events.starts, 2, "the second activation did not listen for system events")
        XCTAssertTrue(rig.events.running && rig.ticker.isRunning && rig.pointer.running)
        XCTAssertEqual(rig.masks.standing.count, 2)
    }

    func testASwitchTurnedOnWhileTheDisplaysSleepStartsNothingUntilTheyWake() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        rig.events.fire(.displaysSlept)
        rig.engine.setBuiltIn(false)
        let shows = rig.masks.shows.count, ticks = rig.ticker.starts, pointers = rig.pointer.starts
        rig.engine.setBuiltIn(true)
        XCTAssertTrue(rig.engine.state.builtIn, "the subject did not happen: the switch was not taken")
        XCTAssertEqual(rig.masks.shows.count, shows, "a mask was opened for sleeping displays")
        XCTAssertEqual(rig.ticker.starts, ticks)
        XCTAssertEqual(rig.pointer.starts, pointers)
        XCTAssertTrue(rig.masks.standing.isEmpty)
        rig.events.fire(.displaysWoke)
        XCTAssertEqual(rig.masks.standing.count, 2, "the wake did not open the masks")
        XCTAssertTrue(rig.ticker.isRunning && rig.pointer.running)
    }

    func testTheSwitchGoingOffDuringACalibrationLeavesOnlyThePreviewAndNoPointerListener() {
        let rig = rig(builtIn: true)
        rig.engine.activate()
        rig.engine.beginCalibration()
        XCTAssertTrue(rig.pointer.running, "the subject did not happen: no listener to drop")
        rig.engine.setBuiltIn(false)
        XCTAssertTrue(rig.engine.state.calibrating)
        XCTAssertFalse(rig.pointer.running, "the pointer listener outlived the masks that held the pointer")
        XCTAssertTrue(rig.masks.standing.keys.allSatisfy { $0.corner.isTop })
        XCTAssertFalse(rig.masks.standing.isEmpty)
        rig.engine.endCalibration()
        assertNothingRuns(rig, "running after the preview ended with both switches off")
    }

    func testACalibrationDoesNotSurviveDeactivate() {
        let rig = rig(builtIn: false)
        rig.engine.activate()
        rig.engine.beginCalibration()
        XCTAssertTrue(rig.engine.state.calibrating, "the subject did not happen")
        rig.engine.deactivate()
        assertNothingRuns(rig, "a preview outlived deactivate()")
        rig.engine.activate()
        XCTAssertFalse(rig.engine.state.calibrating)
        assertNothingRuns(rig, "the old preview came back on activation")
    }

    func testEveryCommandOnAnEngineThatIsNotActiveWritesTheStoreAndNothingElse() {
        let rig = rig(builtIn: false)
        rig.engine.setExternal(true)
        rig.engine.setPreset(points: 20)
        rig.engine.stepRadius(direction: 1)
        rig.engine.setCalibration(r: 1, g: 0, b: 0)
        rig.engine.endCalibration()
        XCTAssertEqual(rig.store.object("external") as? Bool, true, "the subject did not happen: nothing was written")
        XCTAssertNotNil(rig.store.object("radiusPixels") as? Double)
        XCTAssertEqual(rig.events.starts + rig.ticker.starts + rig.pointer.starts, 0)
        XCTAssertTrue(rig.masks.shows.isEmpty)
        XCTAssertEqual(rig.displays.reads, 0)
        XCTAssertEqual(rig.engine.state, CornerState())
    }

    /// The radius is stored in pixels of the built-in display, so an inactive engine converts at the scale
    /// it remembered, not at 1.
    func testARadiusCommandOnAnEngineThatIsNotActiveConvertsAtTheRememberedScale() {
        let store = Rig.store()
        store.set(3.0, for: "builtInScale")
        let rig = Rig(store: store)
        rig.engine.setPreset(points: 20)
        XCTAssertEqual(rig.store.object("radiusPixels") as? Double, 60, "the subject did not happen, or it used another scale")
        XCTAssertEqual(rig.displays.reads, 0)
        XCTAssertEqual(rig.engine.state, CornerState())
    }

    func testNoDisplaysAtAllOpenNoWindowStartNoTimerAndAStepDoesNotTrap() {
        let rig = Rig(displays: [])
        rig.engine.activate()
        XCTAssertGreaterThan(rig.displays.reads, 0, "the subject did not happen: the displays were not read")
        rig.engine.stepRadius(direction: 1)
        rig.engine.stepRadius(direction: -1)
        rig.engine.setPreset(points: 20)
        rig.engine.beginCalibration()
        XCTAssertTrue(rig.masks.standing.isEmpty)
        XCTAssertFalse(rig.ticker.isRunning, "a timer for no window")
        XCTAssertFalse(rig.pointer.running, "a pointer listener for no window")
        XCTAssertTrue(RadiusMath.bounds.contains(rig.engine.state.radiusPixels))
        rig.engine.deactivate()
        assertNothingRuns(rig, "running after deactivate()")
    }
}
