import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Every delay of the after-shot window is judged by `ShotShelf.isOver(left:)`, and a clock that adds up small
/// steps ends on the step that adds up to the delay, not the one after it.** Ten steps of 0.1 are
/// 0.9999999999999999 and not 1; a delay compared with a bare `>= 0` waits one step more, and a tolerance wide
/// enough to swallow a step ends it one step early. Read here: the function itself, by its edges and by the sums
/// the running clock really makes (a step taken from what is left, and a step added to what has passed, the two
/// forms the toast uses), for the delays of the window (1, 5, 6, 9 s) and for steps that are not exact in binary
/// (0.1, 1/3, 1/60).
///
/// Total failure of the subject prints: a delay that ends one step late (tolerance nought) or early (a tolerance of
/// a frame's size), a negative or an endless remainder that is not over.
final class TheShelfClockIsOverAtTheExactStepTests: XCTestCase {

    func testTheEdgesOfTheTolerance() {
        let tolerance = ShotShelf.clockTolerance
        XCTAssertTrue(ShotShelf.isOver(left: 0))
        XCTAssertTrue(ShotShelf.isOver(left: tolerance), "exactly at the tolerance is over")
        XCTAssertTrue(ShotShelf.isOver(left: tolerance.nextDown))
        XCTAssertFalse(ShotShelf.isOver(left: tolerance.nextUp), "just past the tolerance is not over")
        XCTAssertFalse(ShotShelf.isOver(left: tolerance * 2))
        XCTAssertFalse(ShotShelf.isOver(left: 0.01), "a hundredth of a second is not nothing")
        XCTAssertFalse(ShotShelf.isOver(left: 1.0 / 60 / 2), "half a frame is not nothing")
        XCTAssertTrue(ShotShelf.isOver(left: -tolerance))
        XCTAssertTrue(ShotShelf.isOver(left: -1))
        XCTAssertTrue(ShotShelf.isOver(left: -Double.infinity))
        XCTAssertFalse(ShotShelf.isOver(left: Double.infinity))
        XCTAssertTrue(ShotShelf.isOver(left: -Double.greatestFiniteMagnitude))
        XCTAssertFalse(ShotShelf.isOver(left: Double.greatestFiniteMagnitude))
        // The tolerance is far under any step a clock takes: a frame is 1/60 s.
        XCTAssertLessThan(tolerance, 1.0 / 60 / 1000)
        XCTAssertGreaterThan(tolerance, 0)
    }

    /// Not a number is not over: `nan <= x` is false. Nothing in the window feeds it one (`advance(by:)` clamps a step
    /// that is not a number to nothing); this says what would happen if something did: the delay would not end.
    func testANumberThatIsNoNumberIsNotOver() {
        XCTAssertFalse(ShotShelf.isOver(left: .nan))
    }

    func testEveryDelayEndsOnTheExactStepWhateverTheStep() {
        let delays: [Double] = [ShotShelf.foldDelay, ShotShelf.barLinger, 5, 6, 9]
        for step in [0.1, 1.0 / 3, 1.0 / 60, 0.125, 0.25] {
            for delay in delays {
                let exact = Int((delay / step).rounded())
                // The form `remaining -= step` and the test `isOver(left: remaining)`.
                var left = delay, taken = 0
                while !ShotShelf.isOver(left: left), taken < exact + 5 { left -= step; taken += 1 }
                XCTAssertEqual(taken, exact, "\(delay) s in steps of \(step), taken from what is left, ended on step \(taken)")
                // The form `away += step` and the test `isOver(left: delay - away)`.
                var away = 0.0
                taken = 0
                while !ShotShelf.isOver(left: delay - away), taken < exact + 5 { away += step; taken += 1 }
                XCTAssertEqual(taken, exact, "\(delay) s in steps of \(step), added up, ended on step \(taken)")
            }
        }
    }

    /// The delays of the window by the tenth, spelt out: 10, 50, 60 and 90 steps of the running clock.
    func testTheWindowsLivesInTenthsEndOnTenFiftySixtyNinety() {
        for (delay, steps) in [(1.0, 10), (5.0, 50), (6.0, 60), (9.0, 90)] {
            var left = delay
            for step in 1..<steps {
                left -= 0.1
                XCTAssertFalse(ShotShelf.isOver(left: left), "\(delay) s was over at step \(step) of \(steps)")
            }
            left -= 0.1
            XCTAssertTrue(ShotShelf.isOver(left: left), "\(delay) s was not over at step \(steps): \(left) left")
        }
    }

    /// The bar after a click on «N more» starts with the snap's fifth of a second already spent (`showOldest`), so
    /// it goes after eight tenths more, not ten, and not nine.
    func testTheBarAfterNMoreStartsAtTwoTenthsAndEndsOnTheEighthTenth() {
        var idle = ShotShelf.snapDelay
        var steps = 0
        while !ShotShelf.isOver(left: ShotShelf.barLinger - idle), steps < 20 { idle += 0.1; steps += 1 }
        XCTAssertEqual(steps, 8)
        // And the snap's own delay is already over at the start: nothing snaps after a click on «N more».
        XCTAssertTrue(ShotShelf.isOver(left: ShotShelf.snapDelay - ShotShelf.snapDelay))
    }

    /// One step as long as the world: whatever is left is over.
    func testASingleHugeStepEndsEveryDelay() {
        for delay in [1.0, 5, 6, 9] {
            XCTAssertTrue(ShotShelf.isOver(left: delay - 1e300))
            XCTAssertTrue(ShotShelf.isOver(left: delay - Double.greatestFiniteMagnitude))
            XCTAssertTrue(ShotShelf.isOver(left: delay - Double.infinity))
        }
    }
}
