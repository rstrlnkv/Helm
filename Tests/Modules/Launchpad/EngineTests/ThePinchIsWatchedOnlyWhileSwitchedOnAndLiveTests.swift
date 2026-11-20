import XCTest
import HelmRuntime
import HelmTestSupport
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
        Hand.completedPinch().forEach(port.send)
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

    func testAHandPinchingWhileWatchedReachesTheModelAsOneScrubOnMain() {
        let port = FakeTouchPort()
        let engine = engine(port, on: true)
        let ended = expectation(description: "one scrub, ended complete")
        ended.assertForOverFulfill = true
        let heard = Locked<[PinchEvent]>([])
        MainActor.assumeIsolated {
            engine.onPinch = { event in
                XCTAssertTrue(Thread.isMainThread)
                heard.withLock { $0.append(event) }
                if event == .ended(.complete) { ended.fulfill() }
            }
        }
        engine.activate()
        Hand.completedPinch().forEach(port.send)
        wait(for: [ended], timeout: 2)
        let events = heard.withLock { $0 }
        guard case .began(.pinch, _)? = events.first else { return XCTFail("the first event is not a began: \(events)") }
        XCTAssertEqual(events.completed, [.pinch])
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
