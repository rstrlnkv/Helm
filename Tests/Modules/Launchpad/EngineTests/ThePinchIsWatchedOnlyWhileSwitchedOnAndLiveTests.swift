import XCTest
import HelmRuntime
@testable import Module_Launchpad_Engine

/// A trackpad watch is work done while nobody looks: it runs a hundred frames a second per pad for as long as it is started.
/// It starts only when the switch is on and the module is active, never twice, and ends with `deactivate()` and with the engine.
final class ThePinchIsWatchedOnlyWhileSwitchedOnAndLiveTests: XCTestCase {
    private func engine(_ port: FakeTouchPort, on: Bool) -> LaunchpadEngine {
        LaunchpadEngine(catalog: FakeAppCatalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory("pinch")),
                        touches: port, pinchEnabled: { on })
    }

    func testNothingStartsWhileTheSwitchIsOff() {
        let port = FakeTouchPort()
        let engine = engine(port, on: false)
        engine.activate()
        XCTAssertEqual(port.starts, 0)
        XCTAssertNil(engine.pinchWatch)
    }

    func testActivatingWithTheSwitchOnStartsOneWatchAndASecondActivationDoesNotStartAnother() {
        let port = FakeTouchPort()
        let engine = engine(port, on: true)
        engine.activate()
        engine.activate()
        XCTAssertEqual(port.starts, 1)
        XCTAssertTrue(port.running)
        XCTAssertEqual(engine.pinchWatch, .watching(devices: 1))
    }

    func testDeactivatingStopsItAndFramesAfterwardsFireNothing() {
        let port = FakeTouchPort()
        let engine = engine(port, on: true)
        engine.activate()
        engine.deactivate()
        XCTAssertFalse(port.running)
        XCTAssertNil(engine.pinchWatch)
        let fired = expectation(description: "a pinch after deactivate")
        fired.isInverted = true
        MainActor.assumeIsolated { engine.onPinch = { _ in fired.fulfill() } }
        (Hand.landing() + [Hand.frame(0.11, radius: 0.1), Hand.frame(0.12, radius: 0.08)]).forEach(port.send)
        wait(for: [fired], timeout: 0.3)
    }

    func testTheSwitchIsHeardOnlyWhileTheModuleIsActive() {
        let port = FakeTouchPort()
        let engine = engine(port, on: false)
        XCTAssertNil(engine.setPinchWatching(true), "an inactive engine watches nothing")
        XCTAssertEqual(port.starts, 0)
        engine.activate()
        XCTAssertEqual(engine.setPinchWatching(true), .watching(devices: 1))
        XCTAssertNil(engine.setPinchWatching(false))
        XCTAssertFalse(port.running)
    }

    func testLettingTheEngineGoStopsTheWatch() {
        let port = FakeTouchPort()
        var engine: LaunchpadEngine? = self.engine(port, on: true)
        engine?.activate()
        XCTAssertTrue(port.running, "the subject: a watch was running")
        engine = nil
        XCTAssertFalse(port.running)
    }

    func testAWatchThatFoundNoTrackpadIsSaidAndHoldsNothing() {
        let port = FakeTouchPort()
        port.answer = .noTrackpad
        let engine = engine(port, on: true)
        engine.activate()
        XCTAssertEqual(engine.pinchWatch, .noTrackpad)
        XCTAssertFalse(port.running)
    }

    func testAHandPinchingWhileWatchedReachesTheModelOnceOnMain() {
        let port = FakeTouchPort()
        let engine = engine(port, on: true)
        let fired = expectation(description: "one pinch")
        fired.assertForOverFulfill = true
        MainActor.assumeIsolated { engine.onPinch = { direction in XCTAssertEqual(direction, .pinch); fired.fulfill() } }
        engine.activate()
        (Hand.landing() + [Hand.frame(0.11, radius: 0.1), Hand.frame(0.12, radius: 0.08), Hand.frame(0.13, radius: 0.05)]).forEach(port.send)
        wait(for: [fired], timeout: 2)
    }

    func testAPortThatStandsDownEndsTheWatchAndSaysWhy() {
        let port = FakeTouchPort()
        let engine = engine(port, on: true)
        engine.activate()
        port.standDown()
        let deadline = Date().addingTimeInterval(2)
        while engine.pinchWatch != .layoutRefused || port.running, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertEqual(engine.pinchWatch, .layoutRefused)
        XCTAssertFalse(port.running)
    }
}
