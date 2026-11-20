import XCTest
import HelmRuntime
@testable import Module_Launchpad_Engine

/// A watch that runs a hundred frames a second per pad is work done while nobody looks, so the order things happen in matters
/// as much as the frames: a switch flipped inside a gesture, a pad that stands down while the module goes away and comes back,
/// two pads at once, a start still in flight when the module deactivates.
final class ThePinchWatchUnderUntriedSequencesTests: XCTestCase {
    private func engine(_ port: FakeTouchPort, on: Bool = true) -> LaunchpadEngine {
        LaunchpadEngine(catalog: FakeAppCatalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory("pinch-seq")),
                        touches: port, pinchEnabled: { on })
    }
    private final class Fires: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [PinchDirection] = []
        func add(_ d: PinchDirection) { lock.withLock { all.append(d) } }
        var list: [PinchDirection] { lock.withLock { all } }
    }
    private func listen(_ engine: LaunchpadEngine) -> Fires {
        let fires = Fires()
        MainActor.assumeIsolated { engine.onPinch = { fires.add($0) } }
        return fires
    }
    /// Lets the main queue run, where a fire lands.
    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    private let closing = [Hand.frame(0.11, radius: 0.1), Hand.frame(0.12, radius: 0.08), Hand.frame(0.13, radius: 0.05)]

    func testTheSubjectAHandPinchingOnOnePadFiresOnce() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        (Hand.landing() + closing).forEach(port.send)
        drain()
        XCTAssertEqual(fires.list, [.pinch])
    }

    /// Two pads are two hands: frames interleaved must keep their own sessions, and a pad that rests must not be read as the other's fingers.
    func testTwoPadsAtOnceKeepTheirOwnHandsAndOnlyThePinchingPadFires() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        port.answer = .watching(devices: 2)
        engine.activate()
        let still = Hand.landing(radius: 0.2, device: 0) + (0..<3).map { Hand.frame(0.11 + Double($0) / 100, radius: 0.2, device: 0) }
        let pinching = Hand.landing(radius: 0.2, device: 1) + closing.map { Hand.frame($0.time, radius: $0.touches.isEmpty ? 0 : 0.05, device: 1) }
        for i in 0..<max(still.count, pinching.count) {
            if i < still.count { port.send(still[i]) }
            if i < pinching.count { port.send(pinching[i]) }
        }
        drain()
        XCTAssertEqual(fires.list, [.pinch])
    }

    func testThreeFingersOnOnePadAndTwoOnAnotherAreNotAFiveFingerHand() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        port.answer = .watching(devices: 2)
        engine.activate()
        let a = (0...12).map { Hand.frame(Double($0) / 100, radius: 0.2 - 0.012 * Double($0), fingers: 3, device: 0) }
        let b = (0...12).map { Hand.frame(Double($0) / 100, radius: 0.2 - 0.012 * Double($0), fingers: 2, device: 1) }
        zip(a, b).forEach { port.send($0); port.send($1) }
        drain()
        XCTAssertTrue(fires.list.isEmpty)
    }

    /// The switch flipped off and on inside a gesture: what was half seen is forgotten, a hand must land again.
    func testTheSwitchFlippedInsideAGestureForgetsTheHalfSeenHand() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        Hand.landing().forEach(port.send)
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        closing.forEach(port.send)
        drain()
        XCTAssertTrue(fires.list.isEmpty, "a hand that never landed since the switch came on fired")
    }

    func testDeactivatingInsideAGestureAndActivatingAgainForgetsTheHalfSeenHand() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        Hand.landing().forEach(port.send)
        engine.deactivate()
        engine.activate()
        closing.forEach(port.send)
        drain()
        XCTAssertTrue(fires.list.isEmpty)
        XCTAssertEqual(port.starts, 2)
    }

    func testAfterAFlipTheWatchIsWholeAgainAndAPinchFiresOnce() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        (Hand.landing() + closing).forEach(port.send)
        drain()
        XCTAssertEqual(fires.list, [.pinch], "after a flip the watch is whole again and fires once")
        XCTAssertEqual(port.starts, 2)
        XCTAssertEqual(port.stops, 1)
    }

    func testAStandDownCalledTwiceOrAfterDeactivateStopsOnceAndSaysNothingMore() {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        port.standDown()
        port.standDown()
        let deadline = Date().addingTimeInterval(2)
        while engine.pinchWatch != .layoutRefused, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(engine.pinchWatch, .layoutRefused)
        XCTAssertEqual(port.stops, 1)

        let other = FakeTouchPort(), second = self.engine(other)
        second.activate()
        second.deactivate()
        other.standDown()
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertNil(second.pinchWatch, "a stand-down after the module left must not write a state")
        XCTAssertEqual(other.stops, 1)
    }

    /// A pad stood down and the person turned the switch off and on again: the watch is theirs to restart.
    func testAfterAStandDownTheSwitchOffAndOnWatchesAgain() {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        port.standDown()
        let deadline = Date().addingTimeInterval(2)
        while engine.pinchWatch != .layoutRefused, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        engine.setPinchWatching(false)
        XCTAssertEqual(engine.setPinchWatching(true), .watching(devices: 1))
        XCTAssertTrue(port.running)
    }

    /// The stand-down ends the watch on a queue of its own: a module that left and came back in between must not lose the new watch to the old stand-down.
    func testAStandDownDoesNotStopTheWatchOfAModuleThatCameBackInTheMeantime() {
        var lost = 0
        for _ in 0..<300 {
            let port = FakeTouchPort(), engine = engine(port)
            engine.activate()
            port.standDown()
            engine.deactivate()
            engine.activate()
            Thread.sleep(forTimeInterval: 0.005)
            if !port.running || engine.pinchWatch != .watching(devices: 1) { lost += 1 }
            engine.deactivate()
        }
        XCTAssertEqual(lost, 0, "a stale stand-down ended a live watch \(lost) times in 300")
    }

    /// The framework takes its time to start; if the module deactivates meanwhile, the watch that comes up must not outlive it.
    func testADeactivateWhileTheStartIsInFlightLeavesNoWatchRunning() {
        let port = FakeTouchPort(), engine = engine(port)
        let inFlight = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        port.whileStarting = { inFlight.signal(); release.wait() }
        let activating = expectation(description: "activate returned")
        DispatchQueue.global().async { engine.activate(); activating.fulfill() }
        XCTAssertEqual(inFlight.wait(timeout: .now() + 2), .success)
        port.whileStarting = nil
        engine.deactivate()
        release.signal()
        wait(for: [activating], timeout: 2)
        XCTAssertFalse(port.running, "the module is not active and a watch of the trackpad runs")
        XCTAssertNil(engine.pinchWatch)
    }

    /// A pad of an earlier watch stands down after the module came back: the new watch is not its to end, and its state is not its to write.
    func testALateStandDownOfAnEarlierWatchLeavesTheNewWatchRunning() {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        engine.deactivate()
        engine.activate()
        port.standDown(start: 0)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(engine.pinchWatch, .watching(devices: 1), "an old watch's stand-down rewrote the new watch's state")
        XCTAssertTrue(port.running)
        XCTAssertEqual(port.stops, 1, "only the deactivation stopped the port")
    }

    /// A fire is on its way to main when the switch goes off: the hop must land nothing. The test is on main, so the hop waits until `drain`.
    func testAFireOnItsWayToMainIsDroppedWhenTheSwitchGoesOffMeanwhile() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        (Hand.landing() + closing).forEach(port.send)
        engine.setPinchWatching(false)
        drain()
        XCTAssertTrue(fires.list.isEmpty, "a pinch of a watch that was switched off reached the window")
    }

    func testAFireOnItsWayToMainIsDroppedWhenTheModuleDeactivatesMeanwhile() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        (Hand.landing() + closing).forEach(port.send)
        engine.deactivate()
        drain()
        XCTAssertTrue(fires.list.isEmpty)
    }

    /// Off and on again between the fire and its hop: the watch is live and the module active, but it is another watch's pinch.
    func testAFireOfAnEarlierWatchIsDroppedWhenAnotherWatchIsLiveByTheHop() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        (Hand.landing() + closing).forEach(port.send)
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        drain()
        XCTAssertTrue(fires.list.isEmpty, "a pinch of an earlier watch landed on the later one")
    }

    /// Frames the framework still delivers to an earlier watch's callback are not the new watch's frames: the hand they landed is not the new watch's hand.
    func testLateFramesOfAnEarlierWatchAreNotFedToTheNewOne() {
        let port = FakeTouchPort(), engine = engine(port), fires = listen(engine)
        engine.activate()
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        Hand.landing().forEach { port.send($0, toStart: 0) }
        closing.forEach { port.send($0, toStart: 1) }
        drain()
        XCTAssertTrue(fires.list.isEmpty, "the earlier watch's late frames landed a hand the new watch then saw close")
    }

    /// A stop that has been decided but not yet carried out, and a switch turned on again in that gap: the late stop must not end the new watch.
    func testAStopStillInFlightWhenTheSwitchComesBackOnDoesNotEndTheNewWatch() {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        let inFlight = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        port.whileStopping = { inFlight.signal(); release.wait() }
        let stopped = expectation(description: "stop returned"), started = expectation(description: "start returned")
        DispatchQueue.global().async { engine.setPinchWatching(false); stopped.fulfill() }
        XCTAssertEqual(inFlight.wait(timeout: .now() + 2), .success)
        port.whileStopping = nil
        DispatchQueue.global().async { engine.setPinchWatching(true); started.fulfill() }
        Thread.sleep(forTimeInterval: 0.1)
        release.signal()
        wait(for: [stopped, started], timeout: 2)
        XCTAssertTrue(port.running, "a stop of the old watch ended the new one")
        XCTAssertEqual(engine.pinchWatch, .watching(devices: 1))
    }
}
