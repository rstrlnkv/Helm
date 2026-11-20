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
    private func run(_ frames: [TouchFrame]) -> [PinchDirection] {
        var recognizer = PinchRecognizer()
        return frames.compactMap { recognizer.feed($0) }
    }
    /// Holds a hand of `n` fingers at `r` from 0 to 0.1 s.
    private func hold(_ n: Int, r: Double) -> [TouchFrame] { (0...10).map { frame(Double($0) / 100, ring(n, r: r)) } }
    private func close(_ n: Int, from: Double, to: Double, at t0: Double = 0.11) -> [TouchFrame] {
        (1...5).map { frame(t0 + Double($0) / 100, ring(n, r: from + (to - from) * Double($0) / 5)) }
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
                + (1...5).map { frame(0.11 + Double($0) / 100, ring(5, r: 0.2 - 0.03 * Double($0)), state: hover) }
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
        XCTAssertTrue(slow(8).isEmpty, "slower than the limit")
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
        let first = (hold(5, r: 0.2) + close(5, from: 0.2, to: 0.05)).compactMap { recognizer.feed($0) }
        _ = recognizer.feed(empty)
        let second = (hold(5, r: 0.2).map { frame($0.time + 1, $0.touches.map { P($0.x, $0.y) }) } + close(5, from: 0.2, to: 0.05, at: 1.11))
            .compactMap { recognizer.feed($0) }
        XCTAssertEqual(first, [.pinch])
        XCTAssertEqual(second, [.pinch])
    }
}
