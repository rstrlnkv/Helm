import XCTest
@testable import Module_Launchpad_Engine

/// Four or five fingers coming together or going apart, from frames alone: the scrub's events follow the hand and it ends complete
/// or reverted. The numbers are untuned guesses (`PinchThresholds`).
final class PinchRecognizerTests: XCTestCase {
    private func feed(_ frames: [TouchFrame], into recognizer: inout PinchRecognizer) -> [PinchEvent] {
        frames.compactMap { recognizer.feed($0) }
    }
    /// The frames, then every finger up, so a scrub that was begun has ended.
    private func run(_ frames: [TouchFrame]) -> [PinchEvent] {
        var recognizer = PinchRecognizer()
        return feed(frames + [Hand.lift(at: (frames.last?.time ?? 0) + 0.01)], into: &recognizer)
    }

    func testAHandThatLandsAndClosesScrubsAPinchThatCompletes() {
        let events = run(Hand.landing() + Hand.sweep(from: 0.2, to: 0.05, steps: 60))
        guard case .began(.pinch, let first)? = events.first else { return XCTFail("no began: \(events)") }
        XCTAssertGreaterThanOrEqual(first, 0.08)
        XCTAssertEqual(events.last, .ended(.complete))
        XCTAssertEqual(events.completed, [.pinch])
        let moved = events.compactMap { event -> Double? in if case .moved(let p) = event { return p } else { return nil } }
        XCTAssertEqual(moved.last, 1, "progress reaches 1 where the one-shot pinch fired")
        XCTAssertEqual(moved, moved.sorted(), "a hand closing steadily only goes up")
    }

    func testAHandThatLandsAndOpensScrubsASpreadThatCompletes() {
        XCTAssertEqual(run(Hand.landing() + Hand.sweep(from: 0.2, to: 0.32, steps: 20)).completed, [.spread])
    }

    func testFourFingersCountAndThreeDoNot() {
        XCTAssertEqual(run(Hand.landing(fingers: 4) + Hand.sweep(from: 0.2, to: 0.05, steps: 20, fingers: 4)).completed, [.pinch])
        XCTAssertTrue(run(Hand.landing(fingers: 3) + Hand.sweep(from: 0.2, to: 0.05, steps: 20, fingers: 3)).isEmpty)
    }

    func testAfterAnEndNothingMoreUntilEveryFingerLifts() {
        var recognizer = PinchRecognizer()
        // A finger more ends the scrub; the hand then closes and opens again with no event until it lifts.
        let first = feed(Hand.landing() + Hand.sweep(from: 0.2, to: 0.1, steps: 12) + [Hand.frame(0.23, radius: 0.1, fingers: 4)], into: &recognizer)
        XCTAssertEqual(first.last, .ended(.complete))
        XCTAssertTrue(feed(Hand.sweep(from: 0.3, to: 0.02, steps: 10, after: 0.23, fingers: 4), into: &recognizer).isEmpty)
        _ = recognizer.feed(Hand.lift(at: 0.4))
        let again = Hand.landing().map { Hand.frame($0.time + 1, radius: 0.2) } + Hand.sweep(from: 0.2, to: 0.05, steps: 20, after: 1.10)
        XCTAssertEqual(feed(again + [Hand.lift(at: 1.4)], into: &recognizer).completed, [.pinch])
    }

    func testAHandThatHasNotSettledScrubsNothing() {
        let moving = (0...10).map { Hand.frame(Double($0) / 100, radius: 0.2, centre: (0.3 + Double($0) * 0.03, 0.5)) }
        XCTAssertTrue(run(moving + [Hand.frame(0.11, radius: 0.05, centre: (0.6, 0.5))]).isEmpty)
    }

    func testAFingerCountThatLeavesFourToFiveForLongerThanTheGraceEndsTheSession() {
        let dropped = (0..<30).map { Hand.frame(0.11 + Double($0) / 100, radius: 0.2, fingers: 3) }
        XCTAssertTrue(run(Hand.landing() + dropped + Hand.sweep(from: 0.2, to: 0.05, steps: 20, after: 0.5)).isEmpty)
    }

    func testAShortFlickerOfTheCountDoesNotEndIt() {
        let flicker = [Hand.frame(0.11, radius: 0.2, fingers: 3), Hand.frame(0.12, radius: 0.2, fingers: 3), Hand.frame(0.13, radius: 0.2)]
        XCTAssertEqual(run(Hand.landing() + flicker + Hand.sweep(from: 0.2, to: 0.05, steps: 20, after: 0.13)).completed, [.pinch])
    }

    func testASwipeTravelsWithoutChangingTheSpreadAndScrubsNothingEvenIfItThenCloses() {
        let swipe = (0..<20).map { Hand.frame(0.11 + Double($0) / 100, radius: 0.1, centre: (0.5 + Double($0 + 1) * 0.02, 0.5)) }
        XCTAssertTrue(run(Hand.landing(radius: 0.1) + swipe + [Hand.frame(0.4, radius: 0.03, centre: (0.9, 0.5))]).isEmpty)
    }

    func testAHandHeldLongerThanTheLimitWithoutScrubbingIsResting() {
        let resting = (0..<30).map { Hand.frame(0.11 + Double($0) / 10, radius: 0.2) }
        XCTAssertTrue(run(Hand.landing() + resting + [Hand.frame(4, radius: 0.05)]).isEmpty)
    }

    func testAnInchOfSpreadChangeIsNotEnough() {
        XCTAssertTrue(run(Hand.landing(radius: 0.06) + Hand.sweep(from: 0.06, to: 0.03, steps: 20)).completed.isEmpty, "a drop of 0.03 is under minChange")
    }
}
