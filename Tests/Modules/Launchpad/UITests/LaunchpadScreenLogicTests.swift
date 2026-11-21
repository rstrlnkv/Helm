import AppKit
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The window's arithmetic: its geometry from a screen's size, the pages, the arrow keys' choice and the pager's turns.
/// No screen and no view is made.
final class LaunchpadScreenLogicTests: XCTestCase {

    // MARK: - Geometry

    func testEveryRealScreenGetsAGridThatFitsAndNoTileNarrowerThanTheLabelNeeds() {
        for size in [CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 1920, height: 1080),
                     CGSize(width: 2560, height: 1440), CGSize(width: 3840, height: 2160)] {
            let g = LaunchpadGeometry.make(for: size, topSafe: 32)
            XCTAssertGreaterThanOrEqual(g.cellWidth, LaunchpadMetrics.tileMinimum, "\(size)")
            XCTAssertTrue((3...8).contains(g.columns), "\(size)")
            XCTAssertTrue((2...6).contains(g.rows), "\(size)")
            XCTAssertEqual(g.capacity, g.columns * g.rows)
            XCTAssertLessThanOrEqual(g.gridTop + g.pageHeight, size.height, "the grid is inside the screen at \(size)")
            XCTAssertEqual(g.size, size)
        }
    }

    func testASizeThatIsNotASizeIsTheFallbackScreen() {
        let fallback = LaunchpadGeometry.make(for: LaunchpadGeometry.fallback, topSafe: 0)
        for size in [CGSize.zero, CGSize(width: -5, height: 800), CGSize(width: CGFloat.nan, height: 800),
                     CGSize(width: 1280, height: CGFloat.infinity), CGSize(width: 0.5, height: 0.5)] {
            let g = LaunchpadGeometry.make(for: size, topSafe: .nan)
            XCTAssertEqual(g, fallback, "\(size)")
            XCTAssertGreaterThan(g.columns, 0)
            XCTAssertFalse(g.cellWidth.isNaN)
        }
    }

    func testAHugeNotchDoesNotEatTheGrid() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 10_000)
        XCTAssertGreaterThanOrEqual(g.rows, 2)
        XCTAssertLessThan(g.gridTop, 800)
    }

    // MARK: - Pages

    func testPagesAreArithmeticOverOneList() {
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 0, capacity: 20), 1)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 20, capacity: 20), 1)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 21, capacity: 20), 2)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 5, capacity: 0), 1)
        let items = Array(0..<45)
        let (pages, slots) = LaunchpadPaging.pages([items], columns: 5, rows: 4, isLarge: { _ in false })
        XCTAssertEqual(pages.map(\.count), [20, 20, 5])
        XCTAssertEqual(pages[2], Array(40..<45))
        XCTAssertEqual(slots.map(\.count), [20, 20, 5])
        XCTAssertEqual(LaunchpadPaging.page(of: 39, starts: [0, 20, 40]), 1)
        XCTAssertEqual(LaunchpadPaging.clamped(9, count: 3), 2)
        XCTAssertEqual(LaunchpadPaging.clamped(-4, count: 3), 0)
    }

    func testTheArrowKeysMoveTheChoiceAndStopAtTheEdges() {
        XCTAssertNil(LaunchpadPaging.moved(nil, dx: 1, dy: 0, columns: 4, count: 0))
        XCTAssertEqual(LaunchpadPaging.moved(nil, dx: 1, dy: 0, columns: 4, count: 10), 0, "the first press selects the first tile")
        XCTAssertEqual(LaunchpadPaging.moved(0, dx: -1, dy: 0, columns: 4, count: 10), 0)
        XCTAssertEqual(LaunchpadPaging.moved(0, dx: 0, dy: -1, columns: 4, count: 10), 0)
        XCTAssertEqual(LaunchpadPaging.moved(1, dx: 1, dy: 0, columns: 4, count: 10), 2)
        XCTAssertEqual(LaunchpadPaging.moved(1, dx: 0, dy: 1, columns: 4, count: 10), 5)
        XCTAssertEqual(LaunchpadPaging.moved(9, dx: 1, dy: 0, columns: 4, count: 10), 9)
        XCTAssertEqual(LaunchpadPaging.moved(7, dx: 0, dy: 1, columns: 4, count: 10), 9, "down into a short last row lands on its last tile")
        XCTAssertEqual(LaunchpadPaging.moved(9, dx: 0, dy: 1, columns: 4, count: 10), 9)
        XCTAssertEqual(LaunchpadPaging.moved(99, dx: 0, dy: 0, columns: 4, count: 10), 0, "a choice past the end is not kept")
    }

    // MARK: - The pager

    func testATrackpadSwipeFollowsTheFingersTurnsOnTheLiftAndMomentumNeverTurns() {
        var swipe = LaunchpadSwipe()
        XCTAssertEqual(fed(&swipe, -10, .began, 0), .drag(raw: -10))
        XCTAssertEqual(fed(&swipe, -20, .changed, 0.01), .drag(raw: -30))
        XCTAssertEqual(fed(&swipe, -20, .changed, 0.02), .drag(raw: -50))
        XCTAssertEqual(fed(&swipe, -60, [], 0.03, momentum: .changed), .none, "momentum")
        guard case .release(let step, let velocity) = fed(&swipe, 0, .ended, 0.05) else { return XCTFail("the lift says how it ends") }
        XCTAssertEqual(step, 1, "50 pt at speed turns forward")
        XCTAssertLessThan(velocity, -300)
        XCTAssertEqual(fed(&swipe, -90, [], 0.06, momentum: .changed), .none, "momentum after the lift")
        XCTAssertEqual(fed(&swipe, 50, .began, 1), .drag(raw: 50), "the next gesture starts from nothing")
        guard case .release(let back, _) = fed(&swipe, 0, .ended, 1.01) else { return XCTFail("the lift says how it ends") }
        XCTAssertEqual(back, 0, "one event of 50 pt has no speed to turn on")
        XCTAssertEqual(fed(&swipe, 25, .began, 2), .drag(raw: 25))
        XCTAssertEqual(fed(&swipe, 25, .changed, 2.004), .drag(raw: 50))
        XCTAssertEqual(releasedStep(fed(&swipe, 0, .ended, 2.01)), -1, "the next gesture turns again, back")
    }

    func testAShortSwipeAndAMomentumAloneTurnNothing() {
        var swipe = LaunchpadSwipe()
        _ = fed(&swipe, -15, .began, 0)
        _ = fed(&swipe, -15, .changed, 0.004)
        XCTAssertEqual(releasedStep(fed(&swipe, 0, .ended, 0.1)), 0, "30 pt, however fast, snaps back")
        _ = fed(&swipe, -30, .began, 1)
        XCTAssertEqual(releasedStep(fed(&swipe, 0, .ended, 1.5)), 0, "a first event alone has no speed")
        XCTAssertEqual(fed(&swipe, -500, [], 1.6, momentum: .began), .none)
        XCTAssertEqual(fed(&swipe, 0, [], 1.7, momentum: .ended), .none)
    }

    func testAVerticalSwipeDragsWhenThereIsNoHorizontalDelta() {
        var swipe = LaunchpadSwipe()
        XCTAssertEqual(swipe.feed(dx: 0, dy: -45, phase: .began, momentum: [], time: 0), .drag(raw: -45))
    }

    func testAWheelTurnsOncePerQuarterSecondByTheEventsOwnClock() {
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: 0, dy: -1, precise: false, time: 100), 1)
        XCTAssertNil(pager.feed(dx: 0, dy: -1, precise: false, time: 100.1))
        XCTAssertNil(pager.feed(dx: 0, dy: 1, precise: false, time: 100.2))
        XCTAssertEqual(pager.feed(dx: 0, dy: 1, precise: false, time: 100.3), -1)
        XCTAssertNil(pager.feed(dx: 0, dy: 0, precise: false, time: 200), "no delta, no turn")
    }

    func testANotANumberDeltaTurnsNothing() {
        var pager = LaunchpadScrollPager()
        XCTAssertNil(pager.feed(dx: .nan, dy: 0, precise: true, time: 0))
        XCTAssertNil(pager.feed(dx: .infinity, dy: 0, precise: false, time: 5))
    }

    // MARK: - The state

    @MainActor func testSearchSelectsTheFirstHitAndClearingItSelectsNothing() {
        let state = LaunchpadScreenState(geometry: .make(for: LaunchpadGeometry.fallback, topSafe: 0))
        state.update(snapshot: nil)
        XCTAssertEqual(state.mode, .busy)
        state.search = "x"
        XCTAssertNil(state.selection)
        state.search = ""
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.pageCount, 1)
    }
}
