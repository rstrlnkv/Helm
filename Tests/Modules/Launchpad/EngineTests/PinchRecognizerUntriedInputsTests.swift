import XCTest
@testable import Module_Launchpad_Engine

/// What nobody fed `PinchRecognizer`: hands of the wrong size, a count that changes inside the gesture, a clock that stands
/// still or runs backwards, hovering fingers, a pad whose frames restart from zero. None of them is a pinch unless the
/// hand closed; each case says what it must not do.
final class PinchRecognizerUntriedInputsTests: XCTestCase {
    private typealias P = (x: Double, y: Double)

    /// A frame whose fingers sit at `points` (all touching unless `state` says otherwise).
    private func frame(_ t: Double, _ points: [P], state: Int = TouchFrame.touchingState) -> TouchFrame {
        TouchFrame(device: 0, time: t, count: points.count) { i in (points[i].x, points[i].y, state) }!
    }
    private func ring(_ n: Int, r: Double, c: P = (0.5, 0.5)) -> [P] {
        (0..<n).map { (c.x + r * cos(2 * .pi * Double($0) / Double(n)), c.y + r * sin(2 * .pi * Double($0) / Double(n))) }
    }
    /// The directions of the scrubs that ended complete, the hand lifting after the last frame.
    private func run(_ frames: [TouchFrame]) -> [PinchDirection] { events(frames).completed }
    /// Every event the frames make, then every finger up.
    private func events(_ frames: [TouchFrame]) -> [PinchEvent] {
        var recognizer = PinchRecognizer()
        return (frames + [frame((frames.last?.time ?? 0) + 0.01, [])]).compactMap { recognizer.feed($0) }
    }
    /// A hand of 5 fingers from `from` in steps of `step` (one every 0.01 s from `after`), `count` frames.
    private func steps(from: Double, step: Double, count: Int, after: Double = 0.10, fingers: Int = 5) -> [TouchFrame] {
        (1...count).map { frame(after + Double($0) / 100, ring(fingers, r: from + step * Double($0))) }
    }
    private func progress(_ events: [PinchEvent]) -> Double? {
        events.reversed().lazy.compactMap { event -> Double? in
            switch event { case .began(_, let p): p; case .moved(let p): p; case .ended: nil }
        }.first
    }
    /// Holds a hand of `n` fingers at `r` from 0 to 0.1 s.
    private func hold(_ n: Int, r: Double) -> [TouchFrame] { (0...10).map { frame(Double($0) / 100, ring(n, r: r)) } }
    private func close(_ n: Int, from: Double, to: Double, at t0: Double = 0.11) -> [TouchFrame] {
        (1...20).map { frame(t0 + Double($0) / 100, ring(n, r: from + (to - from) * Double($0) / 20)) }
    }

    func testTheSubjectItselfFiresForFourAndFive() {
        XCTAssertEqual(run(hold(4, r: 0.2) + close(4, from: 0.2, to: 0.05)), [.pinch])
        XCTAssertEqual(run(hold(5, r: 0.05) + close(5, from: 0.05, to: 0.3)), [.spread])
    }

    func testThreeFingersAndSixToTenFingersFireNothingEitherWay() {
        for n in [1, 2, 3, 6, 7, 10] {
            XCTAssertTrue(run(hold(n, r: 0.2) + close(n, from: 0.2, to: 0.05)).isEmpty, "\(n) fingers closing")
            XCTAssertTrue(run(hold(n, r: 0.05) + close(n, from: 0.05, to: 0.3)).isEmpty, "\(n) fingers opening")
        }
    }

    func testFiveFingersThatAreOnlyHoveringFireNothing() {
        for hover in [0, 1, 2, 3, 5, 6, 7] {
            let frames = (0...10).map { frame(Double($0) / 100, ring(5, r: 0.2), state: hover) }
                + (1...20).map { frame(0.11 + Double($0) / 100, ring(5, r: 0.2 - 0.0075 * Double($0)), state: hover) }
            XCTAssertTrue(run(frames).isEmpty, "state \(hover)")
        }
    }

    func testAHandWhoseFingersAllSitOnOnePointIsNotAHandAndDoesNotCrash() {
        let same = (0...10).map { frame(Double($0) / 100, Array(repeating: (0.5, 0.5), count: 5)) }
        XCTAssertTrue(run(same + [frame(0.2, ring(5, r: 0.3))]).isEmpty)
    }

    /// 4 to 5 and back inside the range is the same hand: a finger that lands or lifts changes the mean distance by itself,
    /// and the others have not moved.
    func testAFifthFingerLandingInTheMiddleOfAHeldHandIsNotAPinch() {
        let four = ring(4, r: 0.2)
        let frames = hold(4, r: 0.2) + (0..<10).map { frame(0.11 + Double($0) / 100, four + [(0.5, 0.5)]) }
        XCTAssertTrue(run(frames).isEmpty)
    }

    func testTheThumbLiftingFromAHeldFiveFingerHandIsNotAPinch() {
        let hand: [P] = [(0.45, 0.5), (0.5, 0.52), (0.55, 0.5), (0.5, 0.48), (0.9, 0.5)] // four fingers together, a thumb far off
        let lifted = Array(hand.prefix(4))
        let frames = (0...10).map { frame(Double($0) / 100, hand) } + (0..<10).map { frame(0.11 + Double($0) / 100, lifted) }
        XCTAssertTrue(run(frames).isEmpty, "nobody moved a finger; one lifted")
    }

    func testAFingerLandingLateOnAThreeFingerHandStartsAFreshSessionNotAFire() {
        let frames = hold(3, r: 0.2) + (0..<20).map { frame(0.11 + Double($0) / 100, ring(4, r: 0.2)) }
        XCTAssertTrue(run(frames).isEmpty)
    }

    func testASwipeWithASlightSpreadChangeFiresNothing() {
        let swipe = (0..<30).map { frame(0.11 + Double($0) / 100, ring(4, r: 0.2 - 0.001 * Double($0), c: (0.3 + Double($0) * 0.015, 0.5))) }
        XCTAssertTrue(run(hold(4, r: 0.2) + swipe).isEmpty)
    }

    func testAPinchSlowerThanTheArmedLimitFiresNothingAndOneJustInsideItFires() {
        func slow(_ seconds: Double) -> [PinchDirection] {
            let steps = Int(seconds * 50)
            let frames = (1...steps).map { frame(0.1 + seconds * Double($0) / Double(steps), ring(5, r: 0.2 - 0.15 * Double($0) / Double(steps))) }
            return run(hold(5, r: 0.2) + frames)
        }
        XCTAssertEqual(slow(1.5), [.pinch], "inside the limit")
        XCTAssertEqual(slow(8), [.pinch], "the limit is for beginning: a scrub already going may take its time")
        XCTAssertTrue(slow(40).isEmpty, "so slow that it had not begun by the limit")
    }

    func testFramesWithOneTimestampNeverLandAndNeverFire() {
        let frames = (0..<50).map { frame(0.5, ring(5, r: 0.2 - 0.003 * Double($0))) }
        XCTAssertTrue(run(frames).isEmpty)
    }

    func testAClockRunningBackwardsFiresNothing() {
        let frames = (0..<60).map { frame(1 - Double($0) / 100, ring(5, r: 0.2 - 0.002 * Double($0))) }
        XCTAssertTrue(run(frames).isEmpty)
    }

    func testAJitteringClockStillGivesAtMostOneFire() {
        let times = [0.0, 0.01, 0.01, 0.005, 0.02, 0.02, 0.06, 0.05, 0.12, 0.11, 0.13, 0.13, 0.14, 0.15, 0.16, 0.17]
        let frames = times.enumerated().map { frame($0.element, ring(5, r: 0.2 - 0.008 * Double($0.offset))) }
        XCTAssertLessThanOrEqual(run(frames).count, 1)
    }

    /// The pad's clock restarting from zero (a device that came back after sleep) while a count is out of range must not keep
    /// the dead session alive: three fingers for twenty seconds, then a hand that closes with no landing of its own.
    func testAClockThatRestartsWhileTheCountIsOutDoesNotKeepADeadSessionAlive() {
        var recognizer = PinchRecognizer()
        let base = 100_000.0
        _ = (0...10).map { frame(base + Double($0) / 100, ring(5, r: 0.2)) }.compactMap { recognizer.feed($0) }
        _ = recognizer.feed(frame(base + 0.12, ring(3, r: 0.2)))
        _ = (0..<200).map { frame(Double($0) / 10, ring(3, r: 0.2)) }.compactMap { recognizer.feed($0) }
        let fresh = [frame(20.1, ring(5, r: 0.3)), frame(20.11, ring(5, r: 0.1))]
        XCTAssertTrue(fresh.compactMap { recognizer.feed($0) }.isEmpty, "a new hand fired without having landed")
    }

    func testEveryFingerLiftingAtAnyPointResetsTheSessionSoAnotherCanFire() {
        var recognizer = PinchRecognizer()
        let empty = frame(0.5, [])
        let first = (hold(5, r: 0.2) + close(5, from: 0.2, to: 0.05) + [empty]).compactMap { recognizer.feed($0) }
        let second = (hold(5, r: 0.2).map { frame($0.time + 1, $0.touches.map { P($0.x, $0.y) }) } + close(5, from: 0.2, to: 0.05, at: 1.11) + [frame(2, [])])
            .compactMap { recognizer.feed($0) }
        XCTAssertEqual(first.completed, [.pinch])
        XCTAssertEqual(second.completed, [.pinch])
    }

    // MARK: - The scrub

    func testAHandThatStaysInsideTheDeadZoneNeverBegins() {
        XCTAssertTrue(events(hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 30)).isEmpty, "a drop of 0.015 is under the dead zone")
    }

    func testAHandThatTravelsMoreThanItClosesNeverBeginsAndThenClosingFiresNothing() {
        let travelling = (1...30).map { frame(0.10 + Double($0) / 100, ring(5, r: 0.2 - 0.002 * Double($0), c: (0.5 + 0.01 * Double($0), 0.5))) }
        let closed = (1...20).map { frame(0.40 + Double($0) / 100, ring(5, r: 0.14 - 0.004 * Double($0), c: (0.8, 0.5))) }
        XCTAssertTrue(events(hold(5, r: 0.2) + travelling + closed).isEmpty)
    }

    func testAQuickFlickCompletesBelowTheMidpointAndTheSameDistanceSlowlyDoesNot() {
        // Both end at a radius of 0.1625, a progress of about 0.44.
        let fast = events(hold(5, r: 0.2) + steps(from: 0.2, step: -0.0015, count: 25))
        let slow = events(hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 75))
        XCTAssertLessThan(progress(fast) ?? 1, 0.5)
        XCTAssertLessThan(progress(slow) ?? 1, 0.5)
        XCTAssertEqual(fast.last, .ended(.complete), "a flick")
        XCTAssertEqual(slow.last, .ended(.revert), "the same distance slowly")
    }

    func testAScrubThatBarelyBeganAndWasLiftedIsReverted() {
        let frames = hold(5, r: 0.2) + steps(from: 0.2, step: -0.002, count: 12) + (1...8).map { frame(0.22 + Double($0) / 100, ring(5, r: 0.176)) }
        let events = events(frames)
        XCTAssertEqual(events.first.map { if case .began = $0 { true } else { false } }, true, "the subject: it began")
        XCTAssertEqual(events.last, .ended(.revert))
    }

    func testTheMidpointDecidesASlowScrub() {
        XCTAssertEqual(events(hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 84)).last, .ended(.complete), "0.158 is past it")
        XCTAssertEqual(events(hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 76)).last, .ended(.revert), "0.162 is short of it")
    }

    func testAHandThatStopsBeforeLiftingIsNotAFlick() {
        let frames = hold(5, r: 0.2) + steps(from: 0.2, step: -0.002, count: 17) + (1...30).map { frame(0.27 + Double($0) / 100, ring(5, r: 0.166)) }
        XCTAssertEqual(events(frames).last, .ended(.revert), "the speed is of the last moments, not of the whole")
    }

    func testAHandThatOpensBackToItsStartRevertsAndAClosingThenOpeningOneFollows() {
        let there = steps(from: 0.2, step: -0.0005, count: 76)
        let back = (1...76).map { frame(0.86 + Double($0) / 100, ring(5, r: 0.162 + 0.0005 * Double($0))) }
        let all = events(hold(5, r: 0.2) + there + back)
        XCTAssertEqual(all.last, .ended(.revert))
        XCTAssertTrue(all.contains(.moved(0)), "progress went back to 0 and said so")
    }

    func testALiftAndACountChangeBothEndAndAfterEitherNothingMoreUntilEveryFingerLifts() {
        let scrub = hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 84)
        var recognizer = PinchRecognizer()
        let fed = (scrub + [frame(0.97, ring(4, r: 0.158))] + steps(from: 0.158, step: -0.005, count: 10, after: 0.97, fingers: 4)).compactMap { recognizer.feed($0) }
        XCTAssertEqual(fed.filter { if case .ended = $0 { true } else { false } }, [.ended(.complete)], "one end, at the finger's landing")
        XCTAssertNil(recognizer.feed(frame(1.2, [])), "a lift after an end says nothing more")
    }

    func testTheCountLeavingFourToFiveIsFrozenForTheGraceAndResumesIfItComesBack() {
        let scrub = hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 60)
        var recognizer = PinchRecognizer()
        let before = scrub.compactMap { recognizer.feed($0) }
        XCTAssertNotNil(progress(before), "the subject: it began")
        let away = (1...5).compactMap { recognizer.feed(frame(0.70 + Double($0) / 100, ring(3, r: 0.17))) }
        XCTAssertTrue(away.isEmpty, "frozen: nothing said while the count is out")
        let back = (1...20).compactMap { recognizer.feed(frame(0.75 + Double($0) / 100, ring(5, r: 0.17 - 0.002 * Double($0)))) }
        XCTAssertFalse(back.isEmpty)
        XCTAssertFalse(back.contains { if case .ended = $0 { true } else { false } }, "back inside the grace it goes on")
    }

    func testTheCountStayingOutPastTheGraceEndsTheScrubOnceWithTheOutcomeOfWhenItLeft() {
        let scrub = hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 84)
        var recognizer = PinchRecognizer()
        _ = scrub.compactMap { recognizer.feed($0) }
        let out = (1...30).compactMap { recognizer.feed(frame(0.94 + Double($0) / 100, ring(3, r: 0.158))) }
        XCTAssertEqual(out, [.ended(.complete)])
    }

    func testAScrubHeldLongerThanTheLimitIsRevertedOnce() {
        var recognizer = PinchRecognizer()
        let began = (hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 70)).compactMap { recognizer.feed($0) }
        XCTAssertNotNil(progress(began), "the subject: it began")
        let held = (1...130).compactMap { recognizer.feed(frame(0.80 + Double($0) / 10, ring(5, r: 0.165))) }
        XCTAssertEqual(held.filter { $0 == .ended(.revert) }.count, 1)
        XCTAssertEqual(held.last, .ended(.revert))
    }

    func testAClockThatRunsBackwardsInsideAScrubRevertsItAndASessionFollows() {
        var recognizer = PinchRecognizer()
        _ = (hold(5, r: 0.2) + steps(from: 0.2, step: -0.0005, count: 70)).compactMap { recognizer.feed($0) }
        XCTAssertEqual(recognizer.feed(frame(0.05, ring(5, r: 0.165))), .ended(.revert))
        let again = (hold(5, r: 0.2).map { frame($0.time + 0.1, $0.touches.map { P($0.x, $0.y) }) } + close(5, from: 0.2, to: 0.05, at: 0.21)).compactMap { recognizer.feed($0) }
        XCTAssertEqual(again.first.map { if case .began = $0 { true } else { false } }, true, "a new session may scrub")
    }

    func testAtMostOneEventComesFromAFrameAndMovedFollowsOnlyRealChange() {
        var recognizer = PinchRecognizer()
        let frames = hold(5, r: 0.2) + close(5, from: 0.2, to: 0.05) + (1...20).map { frame(0.31 + Double($0) / 100, ring(5, r: 0.05)) }
        let events = frames.compactMap { recognizer.feed($0) }
        let moved = events.compactMap { event -> Double? in if case .moved(let p) = event { return p } else { return nil } }
        XCTAssertEqual(moved.last, 1)
        XCTAssertEqual(moved.filter { $0 == 1 }.count, 1, "a hand held at 1 says it once")
    }
}
