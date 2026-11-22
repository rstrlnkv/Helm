import AppKit
import HelmUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// One event into a swipe, as the panel hands it: a horizontal delta, a phase, a time.
func fed(_ swipe: inout LaunchpadSwipe, _ dx: CGFloat, _ phase: NSEvent.Phase, _ time: TimeInterval,
         momentum: NSEvent.Phase = []) -> LaunchpadSwipe.Output {
    swipe.feed(dx: dx, dy: 0, phase: phase, momentum: momentum, time: time)
}

/// The step a release says, nil for anything that is not a release.
func releasedStep(_ output: LaunchpadSwipe.Output) -> Int? {
    if case .release(let step, _) = output { return step }
    return nil
}

/// The page follows the fingers and, let go, settles on the nearest page: the arithmetic of what turns, how far the rubber
/// band gives, and where a slot's tile sits. A swipe that never turned would read as a window with paging broken, so each
/// claim here has a turn that happened first.
final class ASwipeSettlesOnTheNearestPageTests: XCTestCase {
    func testAFlickTurnsAndASlowOrOpposedOrShortOneDoesNot() {
        let w: CGFloat = 1000
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -50, velocity: -400, width: w), 1, "a flick forward")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: 50, velocity: 400, width: w), -1, "a flick back")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -50, velocity: -299, width: w), 0, "too slow")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -50, velocity: 400, width: w), 0, "the fingers came back")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -39, velocity: -5000, width: w), 0, "a nudge, however fast")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -40, velocity: -300, width: w), 1, "the edges are in")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -500, velocity: 0, width: w), 1, "half the page, held")
        XCTAssertEqual(LaunchpadSwipe.step(travelled: 500, velocity: 0, width: w), -1)
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -499, velocity: 0, width: w), 0)
    }

    func testNothingThatIsNotANumberTurnsOrMovesAPage() {
        XCTAssertEqual(LaunchpadSwipe.step(travelled: .nan, velocity: -400, width: 1000), 0)
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -50, velocity: .infinity, width: 1000), 0)
        XCTAssertEqual(LaunchpadSwipe.step(travelled: -50, velocity: -400, width: .nan), 0)
        XCTAssertEqual(LaunchpadSwipe.offset(raw: .nan, canBack: true, canForward: true, width: 1000), 0)
        XCTAssertEqual(LaunchpadSwipe.offset(raw: 10, canBack: true, canForward: true, width: 0), 0)
        var swipe = LaunchpadSwipe()
        XCTAssertEqual(fed(&swipe, .nan, .began, 0), .none)
        XCTAssertEqual(fed(&swipe, -10, .changed, 0.01), .drag(raw: -10), "and the swipe goes on")
    }

    func testTheRubberBandGivesLessAndLessAndNeverReachesAPage() {
        let w: CGFloat = 1000
        var last: CGFloat = 0
        for raw in stride(from: CGFloat(10), through: 20_000, by: 10) {
            let at = LaunchpadSwipe.offset(raw: raw, canBack: false, canForward: true, width: w)
            XCTAssertGreaterThan(at, last, "\(raw) moves it further")
            XCTAssertLessThan(at, raw, "it gives less than the fingers")
            XCTAssertLessThan(at, w, "never a whole page")
            XCTAssertEqual(LaunchpadSwipe.offset(raw: -raw, canBack: true, canForward: false, width: w), -at, "the other end is the mirror")
            last = at
        }
        XCTAssertEqual(LaunchpadSwipe.offset(raw: 120, canBack: true, canForward: true, width: w), 120, "with a page to go to, the fingers' own")
        XCTAssertEqual(LaunchpadSwipe.offset(raw: -4000, canBack: true, canForward: true, width: w), -w, "and never more than a page")
        XCTAssertEqual(LaunchpadSwipe.offset(raw: -120, canBack: false, canForward: true, width: w), -120, "toward the one page there is")
    }

    func testATouchDuringTheSettleIsIgnoredUntilItEnds() {
        var swipe = LaunchpadSwipe()
        _ = fed(&swipe, -25, .began, 0)
        _ = fed(&swipe, -25, .changed, 0.004)
        guard case .release(let step, _) = fed(&swipe, 0, .ended, 1) else { return XCTFail("the lift") }
        XCTAssertEqual(step, 1, "the release that locks")
        XCTAssertEqual(fed(&swipe, -30, .began, 1.1), .none, "the page is still settling")
        XCTAssertEqual(fed(&swipe, -30, .changed, 1.2), .none)
        XCTAssertEqual(fed(&swipe, 0, .ended, 1.3), .none, "its end is spent, and moves nothing")
        XCTAssertEqual(fed(&swipe, -30, .began, 1.4), .drag(raw: -30), "the next touch, the lock was only for that one")
        var later = LaunchpadSwipe()
        _ = fed(&later, -25, .began, 0)
        _ = fed(&later, -25, .changed, 0.004)
        _ = fed(&later, 0, .ended, 1)
        XCTAssertEqual(fed(&later, -30, .began, 1 + HelmMotion.pageSettleDuration), .drag(raw: -30), "after the settle, at once")
    }

    func testEverySlotSitsOnItsColumnAndRowOfTheFixedGrid() {
        for size in [CGSize(width: 1024, height: 640), CGSize(width: 1920, height: 1080), CGSize(width: 3840, height: 2160)] {
            let g = LaunchpadGeometry.make(for: size, topSafe: 30)
            let left = (g.pageWidth - CGFloat(g.columns) * g.cellWidth) / 2
            XCTAssertEqual(g.origin(ofSlot: 0), CGPoint(x: left, y: 0), "\(size)")
            XCTAssertEqual(g.origin(ofSlot: g.columns - 1).x, left + CGFloat(g.columns - 1) * g.cellWidth, accuracy: 0.001)
            XCTAssertEqual(g.origin(ofSlot: g.columns), CGPoint(x: left, y: g.cellHeight), "the next row starts at the left again")
            let last = g.origin(ofSlot: g.capacity - 1)
            XCTAssertEqual(last.y, CGFloat(g.rows - 1) * g.cellHeight, accuracy: 0.001)
            XCTAssertLessThanOrEqual(last.x + g.cellWidth, g.pageWidth + 0.001, "inside the page")
            let c = g.center(ofSlot: g.columns + 1)
            let o = g.origin(ofSlot: g.columns + 1)
            XCTAssertEqual(c.x, o.x + g.cellWidth / 2, accuracy: 0.001, "the window's coordinates, below the search")
            XCTAssertEqual(c.y, g.gridTop + o.y + g.cellHeight / 2, accuracy: 0.001, "the window's coordinates, below the search")
        }
    }

    @MainActor func testTheDragFollowsAndSettlesAtOnceWithoutRepublishingTheState() throws {
        let ids = (0..<(2 * LaunchpadGeometry.make(for: CGSize(width: 1024, height: 640), topSafe: 0).capacity + 10)).map { "app\($0)" }
        let apps = ids.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }
        let snap = LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: ids,
                                     layout: LaunchpadLayout(items: ids.map { .app($0) }), catalogComplete: true, layoutRead: .absent)
        let s = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1024, height: 640), topSafe: 0))
        s.update(snapshot: snap)
        XCTAssertEqual(s.pageCount, 3)
        var published = 0
        let watch = s.objectWillChange.sink { published += 1 }
        defer { watch.cancel() }
        s.drag(raw: 300)
        XCTAssertGreaterThan(s.drag.offset, 0)
        XCTAssertLessThan(s.drag.offset, 300, "the first page gives like rubber")
        s.drag(raw: -300)
        XCTAssertEqual(s.drag.offset, -300)
        XCTAssertEqual(published, 0, "a swipe's frames are the drag object's, not the state's")
        s.settle(step: 1, velocity: -900)
        XCTAssertEqual(s.page, 1)
        XCTAssertEqual(s.drag.offset, 0)
        s.drag(raw: 200)
        s.settle(step: -1, velocity: 0)
        XCTAssertEqual(s.page, 0)
        s.drag(raw: 200)
        s.settle(step: -1, velocity: 0)
        XCTAssertEqual(s.page, 0, "no page before the first")
        XCTAssertEqual(s.drag.offset, 0)
        s.go(to: 1)
        s.search = "app1"
        XCTAssertEqual(s.page, 0, "typing goes to the first page")
    }
}
