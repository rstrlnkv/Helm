import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Launchpad_Engine

/// A watch that runs a hundred frames a second per pad is work done while nobody looks, so the order things happen in matters
/// as much as the frames: a switch flipped inside a gesture, a pad that stands down while the module goes away and comes back,
/// two pads at once, a start still in flight when the module deactivates. A scrub that main was told began is always told it ended:
/// whatever stops the watch inside one delivers `.ended(.revert)` once.
@MainActor final class ThePinchWatchUnderUntriedSequencesTests: XCTestCase {
    private func engine(_ port: FakeTouchPort, on: Bool = true) -> LaunchpadEngine {
        LaunchpadEngine(catalog: FakeAppCatalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory("pinch-seq")),
                        touches: port, pinchEnabled: { on })
    }
    private final class Heard: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [PinchEvent] = []
        func add(_ e: PinchEvent) { lock.withLock { all.append(e) } }
        var list: [PinchEvent] { lock.withLock { all } }
        var completed: [PinchDirection] { list.completed }
        var began: Int { list.filter { if case .began = $0 { true } else { false } }.count }
        var ended: [PinchOutcome] { list.compactMap { if case .ended(let o) = $0 { o } else { nil } } }
    }
    private func listen(_ engine: LaunchpadEngine) -> Heard {
        let heard = Heard()
        MainActor.assumeIsolated { engine.onPinch = { heard.add($0) } }
        return heard
    }
    /// A hand that has not landed in a hurry, and then closes: only a hand that landed first and was armed can scrub it.
    private let closing = [Hand.frame(0.11, radius: 0.1)] + Hand.still(radius: 0.05, steps: 9, after: 0.11)
    /// A hand that landed and is half way through a scrub, not lifted.
    private var scrubbing: [TouchFrame] { Hand.landing() + Hand.sweep(from: 0.2, to: 0.12, steps: 12) }

    func testTheSubjectAHandPinchingOnOnePadFiresOnce() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.completedPinch().forEach(port.send)
        await waitUntil("the pinch reached main") { heard.completed == [.pinch] }
        XCTAssertEqual(heard.completed, [.pinch])
        guard case .began(.pinch, _)? = heard.list.first else { return XCTFail("the scrub did not begin first: \(heard.list)") }
    }

    /// Two pads are two hands: frames interleaved must keep their own sessions, and a pad that rests must not be read as the other's fingers.
    func testTwoPadsAtOnceKeepTheirOwnHandsAndOnlyThePinchingPadFires() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        port.answer = .watching(devices: 2)
        engine.activate()
        let still = Hand.landing(radius: 0.2, device: 0) + Hand.still(radius: 0.2, steps: 30, after: 0.10, device: 0)
        let pinching = Hand.completedPinch(device: 1)
        for i in 0..<max(still.count, pinching.count) {
            if i < still.count { port.send(still[i]) }
            if i < pinching.count { port.send(pinching[i]) }
        }
        await waitUntil("the pinch reached main") { !heard.completed.isEmpty }
        await grace()
        XCTAssertEqual(heard.completed, [.pinch])
    }

    /// One scrub at a time: a second pad that scrubs while the first does is not heard, and neither is what it says after.
    func testASecondPadsScrubWhileTheFirstRunsIsDropped() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        port.answer = .watching(devices: 2)
        engine.activate()
        let first = Hand.completedPinch(device: 0), second = Hand.completedPinch(device: 1)
        for (a, b) in zip(first, second) { port.send(a); port.send(b) }
        await waitUntil("the first pad's scrub ended") { !heard.ended.isEmpty }
        await grace()
        XCTAssertEqual(heard.began, 1, "the second pad's began reached main")
        XCTAssertEqual(heard.ended, [.complete], "one end, the first pad's")
        XCTAssertEqual(heard.list.completed, [.pinch])
    }

    /// The main thread may be busy for seconds while the pad sends a hundred frames a second: what waits is a few events, not the frames.
    func testTenThousandFramesQueuedWhileMainIsBusyDeliverBeganMovedEndedInOrder() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.landing().forEach(port.send)
        let steps = 10_000
        for i in 1...steps {
            port.send(Hand.frame(0.1 + Double(i) / 2000, radius: 0.2 - 0.15 * Double(i) / Double(steps)))
        }
        port.send(Hand.lift(at: 0.1 + Double(steps) / 2000 + 0.01))
        XCTAssertTrue(heard.list.isEmpty, "the subject: main has not run yet")
        await waitUntil("the scrub ended on main") { !heard.ended.isEmpty }
        let events = heard.list
        XCTAssertEqual(events.count, 3, "\(events.count) events for \(steps) frames")
        guard events.count == 3, case .began(.pinch, _) = events[0], case .moved(let last) = events[1], events[2] == .ended(.complete) else {
            return XCTFail("not began, moved, ended in order: \(events)")
        }
        XCTAssertEqual(last, 1)
    }

    /// A scrub that main was told began, and the watch stops inside it: main is told it ended, once, whatever stopped the watch.
    private func assertTheScrubEndsOnce(_ label: String, _ stop: (FakeTouchPort, LaunchpadEngine) async -> Void) async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        scrubbing.forEach(port.send)
        await waitUntil("\(label): the scrub began on main") { heard.began == 1 }
        guard case .began(.pinch, _)? = heard.list.first else { return XCTFail("\(label): the scrub did not begin: \(heard.list)") }
        XCTAssertTrue(heard.ended.isEmpty, "\(label): the subject: the scrub is still going")
        await stop(port, engine)
        await waitUntil("\(label): the end reached main") { !heard.ended.isEmpty }
        XCTAssertEqual(heard.ended, [.revert], "\(label): ended once, reverted")
        XCTAssertEqual(heard.list.last, .ended(.revert), "\(label): nothing after the end")
        Hand.sweep(from: 0.12, to: 0.05, steps: 5, after: 0.22).forEach(port.send)
        await grace()
        XCTAssertEqual(heard.ended, [.revert], "\(label): a late frame said more")
    }

    func testTheSwitchOffInsideAScrubEndsItOnce() async { await assertTheScrubEndsOnce("switch off") { _, engine in engine.setPinchWatching(false) } }
    func testDeactivatingInsideAScrubEndsItOnce() async { await assertTheScrubEndsOnce("deactivate") { _, engine in engine.deactivate() } }
    func testAFlipOffAndOnInsideAScrubEndsItOnce() async {
        await assertTheScrubEndsOnce("flip") { _, engine in engine.setPinchWatching(false); engine.setPinchWatching(true) }
    }
    func testAStandDownInsideAScrubEndsItOnce() async {
        await assertTheScrubEndsOnce("stand down") { port, engine in
            port.standDown()
            await waitUntil("the pad stood down") { engine.pinchWatch == .layoutRefused }
        }
    }

    /// The scrub was begun and stopped before main ran: main was never told it began, so it is told nothing of it but an end it ignores.
    func testAScrubBegunAndStoppedBeforeMainRanSaysNothingButTheRevert() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        scrubbing.forEach(port.send)
        engine.setPinchWatching(false)
        await waitUntil("the revert reached main") { !heard.list.isEmpty }
        await grace()
        XCTAssertEqual(heard.list, [.ended(.revert)])
    }

    func testThreeFingersOnOnePadAndTwoOnAnotherAreNotAFiveFingerHand() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        port.answer = .watching(devices: 2)
        engine.activate()
        let a = (0...30).map { Hand.frame(Double($0) / 100, radius: 0.2 - 0.005 * Double($0), fingers: 3, device: 0) }
        let b = (0...30).map { Hand.frame(Double($0) / 100, radius: 0.2 - 0.005 * Double($0), fingers: 2, device: 1) }
        zip(a, b).forEach { port.send($0); port.send($1) }
        await grace()
        XCTAssertTrue(heard.list.isEmpty)
    }

    /// The switch flipped off and on inside a gesture: what was half seen is forgotten, a hand must land again.
    func testTheSwitchFlippedInsideAGestureForgetsTheHalfSeenHand() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.landing().forEach(port.send)
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        closing.forEach(port.send)
        await grace()
        XCTAssertTrue(heard.list.isEmpty, "a hand that never landed since the switch came on scrubbed")
    }

    func testDeactivatingInsideAGestureAndActivatingAgainForgetsTheHalfSeenHand() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.landing().forEach(port.send)
        engine.deactivate()
        engine.activate()
        closing.forEach(port.send)
        await grace()
        XCTAssertTrue(heard.list.isEmpty)
        XCTAssertEqual(port.starts, 2)
    }

    func testAfterAFlipTheWatchIsWholeAgainAndAPinchFiresOnce() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        Hand.completedPinch().forEach(port.send)
        await waitUntil("the pinch reached main") { heard.completed == [.pinch] }
        XCTAssertEqual(heard.completed, [.pinch], "after a flip the watch is whole again and scrubs once")
        XCTAssertEqual(port.starts, 2)
        XCTAssertEqual(port.stops, 1)
    }

    func testAStandDownCalledTwiceOrAfterDeactivateStopsOnceAndSaysNothingMore() async {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        port.standDown()
        port.standDown()
        await waitUntil("the pad stood down") { engine.pinchWatch == .layoutRefused }
        await grace()
        XCTAssertEqual(engine.pinchWatch, .layoutRefused)
        XCTAssertEqual(port.stops, 1)

        let other = FakeTouchPort(), second = self.engine(other)
        second.activate()
        second.deactivate()
        other.standDown()
        await grace()
        XCTAssertNil(second.pinchWatch, "a stand-down after the module left must not write a state")
        XCTAssertEqual(other.stops, 1)
    }

    /// A pad stood down and the person turned the switch off and on again: the watch is theirs to restart.
    func testAfterAStandDownTheSwitchOffAndOnWatchesAgain() async {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        port.standDown()
        await waitUntil("the pad stood down") { engine.pinchWatch == .layoutRefused }
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
    func testALateStandDownOfAnEarlierWatchLeavesTheNewWatchRunning() async {
        let port = FakeTouchPort(), engine = engine(port)
        engine.activate()
        engine.deactivate()
        engine.activate()
        port.standDown(start: 0)
        await grace()
        XCTAssertEqual(engine.pinchWatch, .watching(devices: 1), "an old watch's stand-down rewrote the new watch's state")
        XCTAssertTrue(port.running)
        XCTAssertEqual(port.stops, 1, "only the deactivation stopped the port")
    }

    /// A whole scrub is on its way to main when the switch goes off: the hop must land nothing, since main was never told it began. The test is on main, so the hop waits until the test suspends.
    func testAScrubOnItsWayToMainIsDroppedWhenTheSwitchGoesOffMeanwhile() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.completedPinch().forEach(port.send)
        engine.setPinchWatching(false)
        await grace()
        XCTAssertTrue(heard.list.isEmpty, "a scrub of a watch that was switched off reached the window")
    }

    func testAScrubOnItsWayToMainIsDroppedWhenTheModuleDeactivatesMeanwhile() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.completedPinch().forEach(port.send)
        engine.deactivate()
        await grace()
        XCTAssertTrue(heard.list.isEmpty)
    }

    /// Off and on again between the scrub and its hop: the watch is live and the module active, but it is another watch's scrub.
    func testAScrubOfAnEarlierWatchIsDroppedWhenAnotherWatchIsLiveByTheHop() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        Hand.completedPinch().forEach(port.send)
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        await grace()
        XCTAssertTrue(heard.list.isEmpty, "a scrub of an earlier watch landed on the later one")
    }

    /// Frames the framework still delivers to an earlier watch's callback are not the new watch's frames: the hand they landed is not the new watch's hand.
    func testLateFramesOfAnEarlierWatchAreNotFedToTheNewOne() async {
        let port = FakeTouchPort(), engine = engine(port), heard = listen(engine)
        engine.activate()
        engine.setPinchWatching(false)
        engine.setPinchWatching(true)
        Hand.landing().forEach { port.send($0, toStart: 0) }
        closing.forEach { port.send($0, toStart: 1) }
        await grace()
        XCTAssertTrue(heard.list.isEmpty, "the earlier watch's late frames landed a hand the new watch then saw close")
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
