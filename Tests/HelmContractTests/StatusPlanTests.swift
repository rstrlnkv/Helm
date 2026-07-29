import XCTest
@testable import HelmContract

final class StatusPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func spinning(_ seconds: TimeInterval) -> StatusAppearance {
        StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(seconds))
    }

    func testAModuleThatIsSpinningTakesTheIcon() {
        let quiet = StatusAppearance(tintToken: "orange")
        let chosen = StatusPlan.choose([quiet, spinning(0.5)], now: now)
        XCTAssertEqual(chosen.spinUntil, spinning(0.5).spinUntil,
                       "a spin was invisible because another module sorted first")
    }

    func testWithoutASpinTheFirstTintedModuleStillWins() {
        let first = StatusAppearance(tintToken: "orange")
        let second = StatusAppearance(tintToken: "green")
        XCTAssertEqual(StatusPlan.choose([first, second], now: now).tintToken, "orange")
    }

    /// Two modules spinning at once: the newer spin wins, not whichever module
    /// the user happened to order first. Tying this to ModuleOrder would hide a
    /// module's own feedback behind an unrelated one for up to a second.
    func testTheNewestSpinWins() {
        let earlier = StatusAppearance(tintToken: "orange", spinUntil: now.addingTimeInterval(0.2))
        let later = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(1.0))
        XCTAssertEqual(StatusPlan.choose([earlier, later], now: now).tintToken, "green")
        XCTAssertEqual(StatusPlan.choose([later, earlier], now: now).tintToken, "green",
                       "the answer must not depend on the order the modules arrive in")
    }

    func testAnExpiredSpinIsNotASpin() {
        let stale = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(-1))
        let active = StatusAppearance(tintToken: "orange")
        XCTAssertEqual(StatusPlan.choose([active, stale], now: now).tintToken, "orange")
    }

    func testNothingActiveIsInactive() {
        XCTAssertEqual(StatusPlan.choose([StatusAppearance()], now: now), .inactive)
    }

    /// A countdown is continuous state; a spin is a moment. The moment must not
    /// interrupt the state — a countdown arc that jumped backwards for a second
    /// reads as a bug.
    func testACountdownSuppressesTheSpin() {
        let counting = StatusAppearance(tintToken: "green", timerProgress: 0.5,
                                        spinUntil: now.addingTimeInterval(1))
        XCTAssertFalse(StatusPlan.spins(counting, now: now, reduceMotion: false))
    }

    /// Reduce Motion removes the movement and keeps the information.
    func testReduceMotionSuppressesTheSpin() {
        XCTAssertFalse(StatusPlan.spins(spinning(1), now: now, reduceMotion: true))
        XCTAssertTrue(StatusPlan.spins(spinning(1), now: now, reduceMotion: false))
    }

    /// The spin is over the moment its window closes — nothing keeps asking.
    func testASpinThatHasEndedIsNotSpinning() {
        let ended = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(-0.01))
        XCTAssertFalse(StatusPlan.spins(ended, now: now, reduceMotion: false))
        XCTAssertEqual(StatusPlan.choose([ended], now: now).tintToken, "green",
                       "an ended spin should still be an ordinary tinted module")
    }
}
