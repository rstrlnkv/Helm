import XCTest
@testable import Module_Launchpad_UI
@testable import Module_Launchpad_Engine

/// `LaunchpadReveal.settled` at the fractions a display link's clock can hand it: before the start (a timestamp older than the first),
/// past the end, infinite and not a number. Every answer stays between `from` and `to` and is a number, so the window's `apply` never
/// has to refuse one.
@MainActor
final class LaunchpadRevealEdgesTests: XCTestCase {
    func testAFractionBeforeTheStartReadsTheStartAndOnesPastTheEndReadTheTarget() {
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: -0.5), 0.3)
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: -.infinity), 0.3)
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.8, to: 0, fraction: 1.0001), 0)
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.8, to: 0, fraction: .infinity), 0)
    }

    func testNotANumberLandsOnTheTargetSoATravelThatLostItsClockStillEnds() {
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.3, to: 1, fraction: .nan), 1)
        XCTAssertEqual(LaunchpadReveal.settled(from: 0.8, to: 0, fraction: .nan), 0)
    }

    func testEverySampledFractionStaysBetweenTheTwoEnds() {
        for i in -20...40 {
            let up = LaunchpadReveal.settled(from: 0.25, to: 1, fraction: Double(i) / 20)
            let down = LaunchpadReveal.settled(from: 0.75, to: 0, fraction: Double(i) / 20)
            XCTAssertTrue((0.25...1).contains(up), "\(i): \(up)")
            XCTAssertTrue((0...0.75).contains(down), "\(i): \(down)")
        }
    }

    func testASpreadFromANearlyShutWindowAndFromOneAlreadyShutStayInsideZeroToOne() {
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 0, gesture: 0.5), 0)
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 0.2, gesture: -3), 0.2, "a gesture below 0 is none of it")
        XCTAssertEqual(LaunchpadReveal.value(direction: .spread, base: 0.2, gesture: .nan), 0.2)
    }
}
