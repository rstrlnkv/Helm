import AppKit
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The swipe and the state's drag and settle fed what a hand and a trackpad do that the happy path does not: a flick against
/// the end of the pages, two directions in one gesture, a touch with no movement, deltas past a float's range, a clock that
/// stands still or runs back, a gesture the system cancels, a folder opening under the fingers. Each claim has a turn that
/// happened first (a gesture that did release), so a swipe that answered nothing at all cannot pass.
final class ASwipeSurvivesTheInputsNobodyFedTests: XCTestCase {
    private func gesture(_ swipe: inout LaunchpadSwipe, _ deltas: [CGFloat], start: TimeInterval = 0, step: TimeInterval = 0.008,
                         end: Bool = true) -> LaunchpadSwipe.Output {
        var out = LaunchpadSwipe.Output.none
        var t = start
        for (i, d) in deltas.enumerated() {
            out = fed(&swipe, d, i == 0 ? .began : .changed, t)
            t += step
        }
        return end ? fed(&swipe, 0, .ended, t) : out
    }

    @MainActor private func state(pages: Int) -> LaunchpadScreenState {
        let ids = (0..<(18 * pages)).map { "app\($0)" }
        let apps = ids.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }
        let snap = LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: ids,
                                     layout: LaunchpadLayout(items: ids.map { .app($0) }), catalogComplete: true, layoutRead: .absent)
        let s = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1024, height: 640), topSafe: 0))
        s.update(snapshot: snap)
        return s
    }

    // MARK: the swipe

    @MainActor func testAFlickAgainstTheEndStillSaysTurnAndTheStateHoldsThePage() {
        var swipe = LaunchpadSwipe()
        guard case .release(let step, let v) = gesture(&swipe, [-30, -30, -30]) else { return XCTFail("a flick must release") }
        XCTAssertEqual(step, 1, "the swipe knows nothing of the ends; it says turn")
        do {
            let last = state(pages: 3)
            last.go(to: 2)
            last.drag(raw: -300)
            XCTAssertLessThan(last.drag.offset, 0)
            XCTAssertGreaterThan(last.drag.offset, -300, "a rubber band at the last page")
            last.settle(step: step, velocity: v)
            XCTAssertEqual(last.page, 2, "forward from the last page stays")
            XCTAssertEqual(last.drag.offset, 0)
            let single = state(pages: 1)
            single.drag(raw: -400)
            XCTAssertLessThan(single.drag.offset, 0, "the drag moved first")
            single.settle(step: 1, velocity: v)
            XCTAssertEqual(single.page, 0)
            XCTAssertEqual(single.drag.offset, 0)
            single.drag(raw: 400)
            XCTAssertGreaterThan(single.drag.offset, 0)
            single.settle(step: -1, velocity: -v)
            XCTAssertEqual(single.page, 0)
            XCTAssertEqual(single.drag.offset, 0)
        }
    }

    @MainActor func testBackwardsFromTheLastPageAndSettlingFromAMiddlePage() {
        let s = state(pages: 3)
        s.go(to: 2)
        var swipe = LaunchpadSwipe()
        guard case .release(let step, let v) = gesture(&swipe, [30, 30, 30]) else { return XCTFail("a flick back must release") }
        XCTAssertEqual(step, -1)
        s.drag(raw: 90)
        XCTAssertEqual(s.drag.offset, 90, "a page to go back to: the fingers' own")
        s.settle(step: step, velocity: v)
        XCTAssertEqual(s.page, 1)
        XCTAssertEqual(s.drag.offset, 0)
        s.settle(step: 1, velocity: -500)
        XCTAssertEqual(s.page, 2, "from the middle, forward")
        s.settle(step: -7, velocity: 0)
        XCTAssertEqual(s.page, 0, "a step past either end is held to the pages there are")
        s.settle(step: 7, velocity: .nan)
        XCTAssertEqual(s.page, 2)
        s.settle(step: 1, velocity: .infinity)
        XCTAssertEqual(s.page, 2)
        XCTAssertEqual(s.drag.offset, 0)
    }

    func testTwoDirectionsInOneGestureAreJudgedByTheNetTravel() {
        var swipe = LaunchpadSwipe()
        // out 90 left, back 80 right: net -10, whatever the speed of the turns
        XCTAssertEqual(releasedStep(gesture(&swipe, [-30, -30, -30, 40, 40], step: 0.004)), 0, "net 10 pt is a nudge")
        var again = LaunchpadSwipe()
        XCTAssertEqual(releasedStep(gesture(&again, [-30, 30, -30, 30, -30, -30, -30], step: 0.004)), 1, "net -90 and the last strokes forward")
        var back = LaunchpadSwipe()
        XCTAssertEqual(releasedStep(gesture(&back, [-30, -30, -30, 30, 30, 30, 30, 30], step: 0.004)), -1,
                       "net +60 with the last strokes back: a flick back")
        var exact = LaunchpadSwipe()
        _ = gesture(&exact, [-60], end: false)
        XCTAssertEqual(releasedStep(fed(&exact, 60, .changed, 0.01)), nil, "a drag in between")
        XCTAssertEqual(fed(&exact, 0, .ended, 0.02), .none, "back to exactly where it began: nothing to settle, no lock")
        XCTAssertEqual(fed(&exact, -50, .began, 0.03), .drag(raw: -50), "so the next touch is not ignored")
    }

    func testATouchWithNoMovementReleasesNothingAndLocksNothing() {
        var swipe = LaunchpadSwipe()
        XCTAssertEqual(fed(&swipe, 0, .began, 0), .none)
        XCTAssertEqual(fed(&swipe, 0, .ended, 0.05), .none, "began and ended, never changed")
        XCTAssertEqual(fed(&swipe, -20, .began, 0.06), .drag(raw: -20), "no lock followed")
        var one = LaunchpadSwipe()
        guard case .release(let step, let v) = ({ _ = fed(&one, -60, .began, 0); return fed(&one, 0, .ended, 0.01) })() else { return XCTFail("one delta then lift") }
        XCTAssertEqual(step, 0, "a single event has no speed: not a flick")
        XCTAssertEqual(v, 0)
        var may = LaunchpadSwipe()
        XCTAssertEqual(fed(&may, 0, .mayBegin, 0), .none)
        XCTAssertEqual(fed(&may, 0, .cancelled, 0.01), .none)
    }

    func testDeltasPastTheRangeAndClocksThatStandStillOrRunBackNeverTurnOnNonsense() {
        var huge = LaunchpadSwipe()
        _ = fed(&huge, -1e300, .began, 0)
        XCTAssertEqual(fed(&huge, -1e300, .changed, 0.01), .drag(raw: -2e300))
        XCTAssertEqual(fed(&huge, -1e308, .changed, 0.02), .drag(raw: -2e300 - 1e308))
        XCTAssertEqual(fed(&huge, -1e308, .changed, 0.03), .drag(raw: -.infinity), "the sum overflows")
        guard case .release(let step, _) = fed(&huge, 0, .ended, 0.04) else { return XCTFail("still a release") }
        XCTAssertEqual(step, 0, "an overflowed travel is not a turn")
        XCTAssertEqual(LaunchpadSwipe.offset(raw: 1e300, canBack: true, canForward: true, width: 1000), 1000)
        XCTAssertEqual(LaunchpadSwipe.offset(raw: -1e300, canBack: true, canForward: false, width: 1000), -(1 - 0.0) * LaunchpadSwipe.offset(raw: 1e300, canBack: false, canForward: true, width: 1000))
        XCTAssertLessThan(LaunchpadSwipe.offset(raw: 1e300, canBack: false, canForward: true, width: 1000), 1000.0001, "the band at the limit")

        var still = LaunchpadSwipe()
        _ = fed(&still, -20, .began, 5)
        _ = fed(&still, -20, .changed, 5)
        guard case .release(let s0, let v0) = fed(&still, 0, .ended, 5) else { return XCTFail("a release at a standing clock") }
        XCTAssertTrue(v0.isFinite, "dt of 0 is floored, not divided by")
        XCTAssertEqual(s0, 1)

        var back = LaunchpadSwipe()
        _ = fed(&back, -20, .began, 5)
        _ = fed(&back, -20, .changed, 4)
        guard case .release(let s1, let v1) = fed(&back, 0, .ended, 3) else { return XCTFail("a release at a clock running back") }
        XCTAssertTrue(v1.isFinite)
        XCTAssertLessThan(v1, 0, "the speed keeps the direction of the travel, not of the clock")
        XCTAssertEqual(s1, 1)
    }

    func testOnlyTheLastEventsOfAFastFlickCountNotTheWholeGestureAverage() {
        var slowThenFast = LaunchpadSwipe()
        let out = gesture(&slowThenFast, [-5, -5, -5, -5, -5, -5, -5, -5, -40, -40, -40], step: 0.1)
        // the closing strokes: 40 pt in 0.1 s is 400 pt/s, over the 300 line
        XCTAssertEqual(releasedStep(out), 1)
        var slow = LaunchpadSwipe()
        XCTAssertEqual(releasedStep(gesture(&slow, [-10, -10, -10, -10, -10, -10], step: 0.1)), 0, "100 pt/s over 60 pt is a nudge")
    }

    func testACancelledGestureReleasesToNothingAndTheNextSwipeWaitsOutTheSettle() {
        var swipe = LaunchpadSwipe()
        _ = gesture(&swipe, [-400, -400], end: false)
        guard case .release(let step, let v) = fed(&swipe, 0, .cancelled, 0.5) else { return XCTFail("a cancel after travel releases") }
        XCTAssertEqual(step, 0, "a cancel never turns, however far it was pulled")
        XCTAssertEqual(v, 0)
        // the release is a settle back to the page's place, and that takes HelmMotion.pageSettleDuration: a real swipe in it is dropped
        XCTAssertEqual(fed(&swipe, -50, .began, 0.5 + HelmMotion.pageSettleDuration - 0.01), .none, "inside the lock the next swipe is lost")
        XCTAssertEqual(fed(&swipe, 0, .ended, 0.9), .none)
        var next = LaunchpadSwipe()
        _ = gesture(&next, [-400, -400], end: false)
        _ = fed(&next, 0, .cancelled, 0.5)
        XCTAssertEqual(fed(&next, -50, .began, 0.5 + HelmMotion.pageSettleDuration), .drag(raw: -50), "after it, at once")
        var empty = LaunchpadSwipe()
        _ = fed(&empty, 0, .began, 0)
        XCTAssertEqual(fed(&empty, 0, .cancelled, 0.01), .none, "a cancel with no travel locks nothing")
        XCTAssertEqual(fed(&empty, -50, .began, 0.02), .drag(raw: -50))
    }

    func testABeganDuringTheLockThenEndedLeavesTheLockForTheNextTouchOnly() {
        var swipe = LaunchpadSwipe()
        _ = gesture(&swipe, [-40, -40, -40])
        XCTAssertEqual(fed(&swipe, -30, .began, 0.1), .none)
        XCTAssertEqual(fed(&swipe, 0, .ended, 0.12), .none)
        XCTAssertEqual(fed(&swipe, -30, .began, 0.15), .none, "the ignored touch's end spent only that touch: a new one inside the settle time is ignored too")
        XCTAssertEqual(fed(&swipe, 0, .ended, 0.16), .none)
        XCTAssertEqual(fed(&swipe, -30, .began, 0.5), .drag(raw: -30), "and once the settle is over the next touch is the swipe's")
        var two = LaunchpadSwipe()
        _ = gesture(&two, [-40, -40, -40])
        XCTAssertEqual(fed(&two, -30, .began, 0.1), .none, "ignored")
        XCTAssertEqual(fed(&two, -30, .began, 0.2), .none, "a second began inside the lock, no ended between: still ignored")
        XCTAssertEqual(fed(&two, -30, .began, 5), .drag(raw: -30), "a began after the lock is a new touch")
    }

    func testMomentumNeverMovesOrReleasesAndAReleaseIsNeverTwice() {
        var swipe = LaunchpadSwipe()
        XCTAssertNotNil(releasedStep(gesture(&swipe, [-40, -40, -40])))
        for t in stride(from: 0.2, to: 2, by: 0.1) {
            XCTAssertEqual(fed(&swipe, -300, [], t, momentum: .changed), .none, "momentum at \(t)")
        }
        XCTAssertEqual(fed(&swipe, 0, .ended, 3), .none, "an ended with nothing travelled")
    }

    // MARK: the state

    @MainActor func testADragWhileAFolderIsOpenDoesNothingAndASettleOnlyZeroesTheOffset() throws {
        let id = UUID()
        let ids = (0..<20).map { "app\($0)" }
        let apps = ids.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }
        let snap = LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: ids,
                                     layout: LaunchpadLayout(items: [.folder(.init(id: id, name: "F", apps: ["app0", "app1"]))] + ids.dropFirst(2).map { .app($0) }),
                                     catalogComplete: true, layoutRead: .absent)
        let s = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1024, height: 640), topSafe: 0))
        s.update(snapshot: snap)
        XCTAssertGreaterThan(s.pageCount, 1)
        s.open(folder: id)
        XCTAssertEqual(s.openFolder, id, "the folder opened first")
        s.drag(raw: -300)
        XCTAssertEqual(s.drag.offset, 0, "nothing moves under a card")
        s.settle(step: 1, velocity: -900)
        XCTAssertEqual(s.page, 0, "and no page turns under it")
        XCTAssertEqual(s.drag.offset, 0)
    }

    /// A folder that opens under the fingers (the trackpad's click, Return) while the page is held off its place: the window
    /// stops feeding the swipe once a card is open, so no release ever comes, and the offset has to be cleared by the open.
    @MainActor func testAFolderOpeningMidDragDoesNotLeaveThePageHeldOffItsPlace() throws {
        let id = UUID()
        let ids = (0..<20).map { "app\($0)" }
        let apps = ids.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }
        let snap = LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: ids,
                                     layout: LaunchpadLayout(items: [.folder(.init(id: id, name: "F", apps: ["app0", "app1"]))] + ids.dropFirst(2).map { .app($0) }),
                                     catalogComplete: true, layoutRead: .absent)
        let s = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1024, height: 640), topSafe: 0))
        s.update(snapshot: snap)
        s.drag(raw: -300)
        XCTAssertEqual(s.drag.offset, -300, "the page is held off its place first")
        s.open(folder: id)
        s.closeFolder()
        XCTAssertEqual(s.drag.offset, 0, "after a card has come and gone the page is back on its place")
    }

    @MainActor func testSearchingMidDragResetsThePageButTheDragIsTheFingersStill() {
        let s = state(pages: 3)
        s.go(to: 2)
        s.drag(raw: 200)
        s.search = "app1"
        XCTAssertEqual(s.page, 0)
        s.settle(step: -1, velocity: 0)
        XCTAssertEqual(s.page, 0)
        XCTAssertEqual(s.drag.offset, 0)
    }

    /// Typing under the fingers: the search puts the page on the first and lets go of the drag, for no release comes to a page
    /// whose tiles have gone.
    @MainActor func testASearchTypedMidDragDoesNotLeaveThePageHeldOffItsPlace() {
        let s = state(pages: 3)
        s.drag(raw: -300)
        XCTAssertEqual(s.drag.offset, -300, "the page is held off its place first")
        s.search = "app1"
        XCTAssertEqual(s.drag.offset, 0)
    }

    // MARK: the settle spring and the slot arithmetic

    /// The speed the spring starts at, not the animation: an `Animation` value reads the machine's Reduce Motion setting, the
    /// speed does not.
    func testThePageSettleTakesNoSpeedItCannotTrust() {
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: 500), 1.8, accuracy: 1e-9, "a flick carries on: the speed is over the distance")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 0, distance: 500), 0)
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: .nan, distance: 500), 0, "NaN is no speed")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: -900, distance: 500), 0, "against the move is no speed")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: 0), 0, "nothing left to travel")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: .infinity, distance: 500), 0)
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 1e9, distance: 2), 8, "held to 8 distances a second")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 16, distance: 2), 8, "and 8 itself is let through")
    }

    /// The line between a distance worth dividing by and one that is not: a point left is no distance, a point and a bit is.
    func testThePageSettleSpeedHasItsLineAtOnePointNotAtZero() {
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: 1), 0, "exactly a point left: nothing to carry on over")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: 0.5), 0)
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 1, distance: 1.25), 0.8, accuracy: 1e-9, "just past the line the speed is the ratio")
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: .nan), 0)
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: .infinity), 0)
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: -.infinity, distance: 500), 0)
        XCTAssertEqual(HelmMotion.pageSettleSpeed(velocity: 900, distance: -500), 0, "a negative distance is none")
    }

    func testUnderReduceMotionAReleaseSettlesAtOnceSoItLocksNothing() {
        var swipe = LaunchpadSwipe()
        swipe.reduceMotion = true
        XCTAssertNotNil(releasedStep(gesture(&swipe, [-40, -40, -40])), "the release happened first")
        XCTAssertEqual(fed(&swipe, -30, .began, 0.1), .drag(raw: -30), "the next touch is the swipe's at once")
        var moving = LaunchpadSwipe()
        _ = gesture(&moving, [-40, -40, -40])
        XCTAssertEqual(fed(&moving, -30, .began, 0.1), .none, "with motion the same touch is inside the settle")
    }

    func testASlotBeyondThePageOrBelowZeroIsStillAPointNotATrap() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1024, height: 640), topSafe: 0)
        let after = g.origin(ofSlot: g.capacity)
        XCTAssertEqual(after.y, CGFloat(g.rows) * g.cellHeight, accuracy: 0.001, "the first slot past the page is a row below it")
        XCTAssertEqual(g.center(ofSlot: Int.max / 4).x.isFinite, true)
        for slot in [-1, -g.columns, Int.min / 2] {
            let p = g.origin(ofSlot: slot)
            XCTAssertTrue(p.x.isFinite && p.y.isFinite, "slot \(slot)")
        }
    }
}
