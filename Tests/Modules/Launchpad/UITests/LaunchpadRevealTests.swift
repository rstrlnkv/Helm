import XCTest
import HelmUI
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// What the window shows for a scrub and a settle: the numbers `LaunchpadWindow.apply` is given.
@MainActor
final class LaunchpadRevealTests: XCTestCase {
    func testAPinchRevealsWhatTheGestureHasDone() {
        XCTAssertEqual(LaunchpadReveal.value(direction: .pinch, base: 0, gesture: 0.3), 0.3)
        XCTAssertEqual(LaunchpadReveal.value(direction: .pinch, base: 0, gesture: 1), 1)
    }

    func testASpreadTakesWhatIsLeftOfTheWhereItBegan() {
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 1, gesture: 0.25), 0.75)
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 0.5, gesture: 1), 0)
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 0.5, gesture: 0.5), 0.25, "from half-open it closes from there")
    }

    func testAGestureOutsideZeroToOneOrNoNumberIsHeldInsideIt() {
        XCTAssertEqual(LaunchpadReveal.value(direction: .pinch, base: 0, gesture: 7), 1)
        XCTAssertEqual(LaunchpadReveal.value(direction: .pinch, base: 0, gesture: -2), 0)
        XCTAssertEqual(LaunchpadReveal.value(direction: .pinch, base: 0, gesture: .nan), 0)
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 1, gesture: .infinity), 1, "no number is taken as no gesture")
    }

    func testASettleStartsAtItsStartEndsAtItsTargetAndOnlyGoesOneWay() {
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: 0), 0.3)
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: 1), 1)
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: 7), 1, "past its end it is at its target")
        let rising = (0...20).map { LaunchpadReveal.settled(from: 0.3, to: 1, fraction: Double($0) / 20) }
        XCTAssertEqual(rising, rising.sorted())
        let falling = (0...20).map { LaunchpadReveal.settled(from: 0.8, to: 0, fraction: Double($0) / 20) }
        XCTAssertEqual(falling, falling.sorted(by: >))
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: 0.5), 0.3 + 0.7 * HelmMotion.interfaceProgress(at: 0.5), accuracy: 1e-12)
    }

    func testTheRevealStartsWholeSoAWindowNobodyScrubbedIsSeen() {
        XCTAssertEqual(LaunchpadReveal().progress, 1)
    }
}
