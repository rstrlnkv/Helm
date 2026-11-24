import XCTest
import HelmContract
@testable import HelmRuntime

final class StatusPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - Which frame belongs to now

    private let frames = 36

    /// A clamp around a conversion does not protect it: `Int(_:)` traps outside
    /// `Int`'s range before any bound sees the number. `spinUntil` reaches the
    /// host from a module as a `Date`, a `Double` of seconds nothing bounds, and
    /// the module writing it is not the check.
    ///
    /// Asserted as the property the host needs — a subscript that exists — rather
    /// than as a particular index, so a fix may choose either end.
    func testASpinFartherOffThanIntCanHoldStillDrawsAFrame() {
        for wild in [1e300, .greatestFiniteMagnitude, Double.infinity] {
            let spinUntil = Date(timeIntervalSinceReferenceDate: wild)
            guard let frame = StatusPlan.frame(spinUntil: spinUntil, now: now,
                                               frameCount: frames) else { continue }
            XCTAssertTrue((0..<frames).contains(frame),
                          "a spinUntil of \(wild) gave \(frame), which is not an index "
                          + "of the array the host is about to subscript")
        }
    }

    /// Bounding a `Double` cannot remove a NaN, and `phase` is infinite for a
    /// wild `spinUntil`, so `phase * 0` is NaN and would trap past a clamp that
    /// looks right.
    ///
    /// An empty array has no index either way, which is the answer.
    func testAnEmptyFrameArrayHasNoFrameToDraw() {
        XCTAssertNil(StatusPlan.frame(spinUntil: now.addingTimeInterval(0.5), now: now,
                                      frameCount: 0),
                     "there is no still to draw, and -1 is not one")
        XCTAssertNil(StatusPlan.frame(spinUntil: Date(timeIntervalSinceReferenceDate: .infinity),
                                      now: now, frameCount: 0))
    }

    /// Keep Awake's text countdown is drawn from the clock at draw time and the
    /// engine emits only on a change, so the host's one-second tick is all that
    /// moves it: a title with no ring must still arm it.
    func testATitleAloneArmsTheSecondTick() {
        XCTAssertTrue(StatusPlan.wantsSecondTick(StatusAppearance(title: "12:00")))
        XCTAssertTrue(StatusPlan.wantsSecondTick(StatusAppearance(timerProgress: 0.5)))
        XCTAssertFalse(StatusPlan.wantsSecondTick(StatusAppearance()))
    }
}
