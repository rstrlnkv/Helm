import AppKit
import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The toast's clocks — the row's fold, the scroll's snap and bar, the lives — end on the step that adds up to
/// their delay, in the steps the running app takes (a tenth of a second) and in a frame's.** The delays are judged
/// by `ShotShelf.isOver(left:)` (`TheShelfClockIsOverAtTheExactStepTests` reads that function); this reads that the
/// toast asks it everywhere a delay is: `advance(by:)` for `away` and `remaining`, `settle(after:)` for the snap
/// and the bar. A comparison left bare in one of them ends one step late, and the step count shows it.
///
/// The shrink after a fold (`shrinkIn`) is not read here: it is seen only in the panel's size, and the toast has
/// no window in these tests.
///
/// Total failure of the subject prints: a fold, a snap, a bar or a life that comes one step after the one that adds
/// up to its delay.
@MainActor
final class TheShelfClocksEndOnTheExactStepOfTheRunningClockTests: XCTestCase {

    private var toasts: [ShotToast] = []

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        toasts = []
        super.tearDown()
    }

    private func quiet(shots count: Int) throws -> ShotToast {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        for i in 0..<count { toast.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
        return toast
    }

    func testTheFoldComesOnTheStepThatAddsUpToASecond() throws {
        for (step, exact) in [(0.1, 10), (1.0 / 60, 60), (1.0 / 3, 3)] {
            let toast = try quiet(shots: 3)
            toast.unfold()
            XCTAssertTrue(toast.model.unfolded, "the control: the row is open")
            var taken = 0
            while toast.model.unfolded, taken < exact + 5 { _ = toast.advance(by: step); taken += 1 }
            XCTAssertEqual(taken, exact, "the fold, in steps of \(step), came on step \(taken)")
        }
    }

    func testTheScrollSnapsOnTheSecondTenthAndItsBarGoesOnTheTenth() throws {
        let toast = try quiet(shots: 7)
        toast.pointerIsOver = { true }
        toast.unfold()
        toast.scroll(by: 50)
        XCTAssertEqual(toast.model.offset, 50)
        _ = toast.advance(by: 0.1)
        XCTAssertEqual(toast.model.offset, 50, "snapped before the wheel had been still for a fifth of a second")
        _ = toast.advance(by: 0.1)
        XCTAssertEqual(toast.model.offset, 0, "not snapped at the second tenth")
        for step in 3...9 {
            _ = toast.advance(by: 0.1)
            XCTAssertTrue(toast.model.barShown, "the bar went at step \(step), before a second")
        }
        _ = toast.advance(by: 0.1)
        XCTAssertFalse(toast.model.barShown, "the bar was still there at the tenth tenth")
    }

    func testTheBarAfterNMoreGoesOnTheEighthTenthAndNothingSnaps() throws {
        for count in [7, 12] {
            let toast = try quiet(shots: count)
            toast.pointerIsOver = { true }
            toast.unfold()
            toast.showOldest()
            let rest = toast.model.offset
            XCTAssertEqual(rest, ShotShelf.farthest(count: count))
            XCTAssertTrue(toast.model.barShown)
            for step in 1...7 {
                _ = toast.advance(by: 0.1)
                XCTAssertTrue(toast.model.barShown, "(\(count) shots) the bar went at step \(step), before eight tenths")
                XCTAssertEqual(toast.model.offset, rest, "(\(count) shots) the row moved after a click on «N more»")
            }
            _ = toast.advance(by: 0.1)
            XCTAssertFalse(toast.model.barShown, "(\(count) shots) the bar stayed past the eighth tenth")
            XCTAssertEqual(toast.model.offset, rest)
        }
    }

    func testALifeOfFiveSecondsEndsOnTheFiftiethTenthAndOnTheThreeHundredthFrame() throws {
        for (step, exact) in [(0.1, 50), (1.0 / 60, 300)] {
            let toast = try quiet(shots: 1)
            var taken = 1
            while !toast.advance(by: step), taken < exact + 5 { taken += 1 }
            XCTAssertEqual(taken, exact, "a life of 5 s in steps of \(step) ended on step \(taken)")
        }
    }

    func testARefusalsLifeEndsOnTheNinetiethTenth() throws {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toasts.append(toast)
        toast.showRefusal(.noPermission)
        var taken = 1
        while !toast.advance(by: 0.1), taken < 100 { taken += 1 }
        XCTAssertEqual(taken, 90, "a refusal's 9 s ended on step \(taken)")
    }
}
