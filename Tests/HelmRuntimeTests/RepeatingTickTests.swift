import XCTest
@testable import HelmRuntime

/// The menu bar's spin runs a 30 Hz redraw for 1.2 seconds. A timer left armed
/// after it redraws the status item for the life of the app, and nothing on
/// screen says so — which is why these assert on the timer itself rather than
/// on anything the tick produces.
@MainActor final class RepeatingTickTests: XCTestCase {
    func testTheTimerIsInvalidatedWhenTheTickIsNoLongerWanted() {
        let tick = RepeatingTick(interval: 1.0 / 30) {}
        tick.set(active: true)
        let armed = tick.timer
        XCTAssertNotNil(armed)
        XCTAssertTrue(tick.isRunning)

        tick.set(active: false)

        XCTAssertFalse(tick.isRunning)
        XCTAssertEqual(armed?.isValid, false,
                       "the tick was dropped but the run loop still holds a live timer")
    }

    /// Every redraw asks again. Arming an armed tick must not stack a second
    /// timer on the run loop — thirty times a second, that is a leak with a
    /// visible symptom only much later.
    func testAskingTwiceKeepsTheOneTimer() {
        let tick = RepeatingTick(interval: 1.0 / 30) {}
        tick.set(active: true)
        let first = tick.timer
        tick.set(active: true)
        XCTAssertTrue(first === tick.timer)
    }

    func testStoppingATickThatNeverStartedIsHarmless() {
        let tick = RepeatingTick(interval: 1.0 / 30) {}
        tick.set(active: false)
        XCTAssertFalse(tick.isRunning)
    }

    /// The run loop owns the timer, so a tick whose owner is gone would keep
    /// firing with nobody to stop it. It has to notice and stop itself.
    func testATickNobodyOwnsStopsItself() {
        var tick: RepeatingTick? = RepeatingTick(interval: 0.01) {}
        tick?.set(active: true)
        let armed = tick?.timer
        XCTAssertNotNil(armed)

        tick = nil

        let deadline = Date().addingTimeInterval(2)
        while armed?.isValid == true, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(armed?.isValid, false, "an orphaned tick fires forever")
    }

    func testTheTickRuns() {
        var fired = 0
        let tick = RepeatingTick(interval: 0.01) { fired += 1 }
        tick.set(active: true)
        let deadline = Date().addingTimeInterval(2)
        while fired == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        tick.set(active: false)
        XCTAssertGreaterThan(fired, 0)
    }
}
