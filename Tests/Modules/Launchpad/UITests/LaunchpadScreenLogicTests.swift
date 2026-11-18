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
        XCTAssertEqual(LaunchpadPaging.slice(items, page: 2, capacity: 20), Array(40..<45))
        XCTAssertEqual(LaunchpadPaging.slice(items, page: 3, capacity: 20), [])
        XCTAssertEqual(LaunchpadPaging.slice(items, page: -1, capacity: 20), [])
        XCTAssertEqual(LaunchpadPaging.page(of: 39, capacity: 20), 1)
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

    func testATrackpadSwipeTurnsOnceAndMomentumNeverTurns() {
        var pager = LaunchpadScrollPager()
        XCTAssertNil(pager.feed(dx: -10, dy: 0, precise: true, phase: .began, momentum: [], time: 0))
        XCTAssertNil(pager.feed(dx: -20, dy: 0, precise: true, phase: .changed, momentum: [], time: 0.01))
        XCTAssertEqual(pager.feed(dx: -20, dy: 0, precise: true, phase: .changed, momentum: [], time: 0.02), 1)
        XCTAssertNil(pager.feed(dx: -60, dy: 0, precise: true, phase: .changed, momentum: [], time: 0.03), "once a gesture")
        XCTAssertNil(pager.feed(dx: -90, dy: 0, precise: true, phase: [], momentum: .changed, time: 0.04), "momentum")
        XCTAssertNil(pager.feed(dx: 0, dy: 0, precise: true, phase: .ended, momentum: [], time: 0.05))
        XCTAssertEqual(pager.feed(dx: 50, dy: 0, precise: true, phase: .began, momentum: [], time: 1), -1, "the next gesture turns again, back")
    }

    func testAShortSwipeAndAMomentumAloneTurnNothing() {
        var pager = LaunchpadScrollPager()
        XCTAssertNil(pager.feed(dx: -30, dy: 0, precise: true, phase: .began, momentum: [], time: 0))
        XCTAssertNil(pager.feed(dx: 0, dy: 0, precise: true, phase: .ended, momentum: [], time: 0.1))
        XCTAssertNil(pager.feed(dx: -30, dy: 0, precise: true, phase: .began, momentum: [], time: 0.2), "the sum starts again")
        XCTAssertNil(pager.feed(dx: -500, dy: 0, precise: true, phase: [], momentum: .began, time: 0.3))
    }

    func testAVerticalSwipeTurnsWhenThereIsNoHorizontalDelta() {
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: 0, dy: -45, precise: true, phase: .began, momentum: [], time: 0), 1)
    }

    func testAWheelTurnsOncePerQuarterSecondByTheEventsOwnClock() {
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: 0, dy: -1, precise: false, phase: [], momentum: [], time: 100), 1)
        XCTAssertNil(pager.feed(dx: 0, dy: -1, precise: false, phase: [], momentum: [], time: 100.1))
        XCTAssertNil(pager.feed(dx: 0, dy: 1, precise: false, phase: [], momentum: [], time: 100.2))
        XCTAssertEqual(pager.feed(dx: 0, dy: 1, precise: false, phase: [], momentum: [], time: 100.3), -1)
        XCTAssertNil(pager.feed(dx: 0, dy: 0, precise: false, phase: [], momentum: [], time: 200), "no delta, no turn")
    }

    func testANotANumberDeltaTurnsNothing() {
        var pager = LaunchpadScrollPager()
        XCTAssertNil(pager.feed(dx: .nan, dy: 0, precise: true, phase: .began, momentum: [], time: 0))
        XCTAssertNil(pager.feed(dx: .infinity, dy: 0, precise: false, phase: [], momentum: [], time: 5))
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
