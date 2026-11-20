import XCTest
@testable import Module_Launchpad_Engine

/// Four or five fingers coming together or going apart, from frames alone. The numbers are untuned guesses (`PinchThresholds`).
final class PinchRecognizerTests: XCTestCase {
    private func feed(_ frames: [TouchFrame], into recognizer: inout PinchRecognizer) -> [PinchDirection] {
        frames.compactMap { recognizer.feed($0) }
    }

    func testAHandThatLandsAndClosesFiresAPinchOnce() {
        var recognizer = PinchRecognizer()
        let close = [0.15, 0.12, 0.1, 0.08, 0.05].enumerated().map { Hand.frame(0.11 + Double($0.offset) / 100, radius: $0.element) }
        XCTAssertEqual(feed(Hand.landing() + close, into: &recognizer), [.pinch])
    }

    func testAHandThatLandsAndOpensFiresASpread() {
        var recognizer = PinchRecognizer()
        let open = [0.25, 0.3, 0.35].enumerated().map { Hand.frame(0.11 + Double($0.offset) / 100, radius: $0.element) }
        XCTAssertEqual(feed(Hand.landing() + open, into: &recognizer), [.spread])
    }

    func testFourFingersCountAndThreeDoNot() {
        var four = PinchRecognizer(), three = PinchRecognizer()
        let close = [Hand.frame(0.11, radius: 0.1), Hand.frame(0.12, radius: 0.05)]
        XCTAssertEqual(feed(Hand.landing(fingers: 4) + close.map { Hand.frame($0.time, radius: 0.08, fingers: 4) }, into: &four), [.pinch])
        XCTAssertTrue(feed(Hand.landing(fingers: 3) + close.map { Hand.frame($0.time, radius: 0.08, fingers: 3) }, into: &three).isEmpty)
    }

    func testAfterAFireNothingMoreUntilEveryFingerLifts() {
        var recognizer = PinchRecognizer()
        _ = feed(Hand.landing() + [Hand.frame(0.11, radius: 0.05)], into: &recognizer)
        XCTAssertTrue(feed([Hand.frame(0.12, radius: 0.3), Hand.frame(0.13, radius: 0.02)], into: &recognizer).isEmpty)
        let empty = TouchFrame(device: 0, time: 0.2, count: 0) { _ in (0, 0, 0) }!
        _ = recognizer.feed(empty)
        let again = (0...10).map { Hand.frame(1 + Double($0) / 100, radius: 0.2) } + [Hand.frame(1.11, radius: 0.05)]
        XCTAssertEqual(feed(again, into: &recognizer), [.pinch])
    }

    func testAHandThatHasNotSettledFiresNothing() {
        var recognizer = PinchRecognizer()
        let moving = (0...10).map { Hand.frame(Double($0) / 100, radius: 0.2, centre: (0.3 + Double($0) * 0.03, 0.5)) }
        XCTAssertTrue(feed(moving + [Hand.frame(0.11, radius: 0.05, centre: (0.6, 0.5))], into: &recognizer).isEmpty)
    }

    func testAFingerCountThatLeavesFourToFiveForLongerThanTheGraceEndsTheSession() {
        var recognizer = PinchRecognizer()
        let dropped = (0..<30).map { Hand.frame(0.11 + Double($0) / 100, radius: 0.2, fingers: 3) }
        XCTAssertTrue(feed(Hand.landing() + dropped + [Hand.frame(0.5, radius: 0.2), Hand.frame(0.51, radius: 0.05)], into: &recognizer).isEmpty)
    }

    func testAShortFlickerOfTheCountDoesNotEndIt() {
        var recognizer = PinchRecognizer()
        let flicker = [Hand.frame(0.11, radius: 0.2, fingers: 3), Hand.frame(0.12, radius: 0.2, fingers: 3), Hand.frame(0.13, radius: 0.2), Hand.frame(0.14, radius: 0.05)]
        XCTAssertEqual(feed(Hand.landing() + flicker, into: &recognizer), [.pinch])
    }

    func testASwipeTravelsWithoutChangingTheSpreadAndFiresNothingEvenIfItThenCloses() {
        var recognizer = PinchRecognizer()
        let swipe = (0..<20).map { Hand.frame(0.11 + Double($0) / 100, radius: 0.1, centre: (0.5 + Double($0 + 1) * 0.02, 0.5)) }
        XCTAssertTrue(feed(Hand.landing(radius: 0.1) + swipe + [Hand.frame(0.4, radius: 0.03, centre: (0.9, 0.5))], into: &recognizer).isEmpty)
    }

    func testAHandHeldLongerThanTheLimitWithoutFiringIsResting() {
        var recognizer = PinchRecognizer()
        let resting = (0..<30).map { Hand.frame(0.11 + Double($0) / 10, radius: 0.2) }
        XCTAssertTrue(feed(Hand.landing() + resting + [Hand.frame(4, radius: 0.05)], into: &recognizer).isEmpty)
    }

    func testAnInchOfSpreadChangeIsNotEnough() {
        var recognizer = PinchRecognizer()
        XCTAssertTrue(feed(Hand.landing(radius: 0.06) + [Hand.frame(0.11, radius: 0.03)], into: &recognizer).isEmpty, "a drop of 0.03 is under minChange")
    }
}
