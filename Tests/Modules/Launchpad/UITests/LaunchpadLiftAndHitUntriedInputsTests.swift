import XCTest
@testable import Module_Launchpad_UI

/// What nobody fed the lift's machine and the hit test: time that goes backward or stands still, points that are not
/// places, events out of order, a held edge that must make one page per dwell, a card left and entered again, cells' exact
/// boundaries, a screen too small for its edges, a top inset bigger than the screen.
final class LaunchpadLiftAndHitUntriedInputsTests: XCTestCase {
    private typealias Lift = LaunchpadLift
    private let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
    private func surface(page: Int = 0, counts: [Int] = [10], gap: Int? = nil) -> LaunchpadSurface {
        LaunchpadSurface(geometry: g, page: page, pageCounts: counts, gap: gap)
    }
    private func core(_ slot: Int) -> CGPoint { g.center(ofSlot: slot) }
    private func margin(_ slot: Int) -> CGPoint { let c = core(slot); return CGPoint(x: c.x + g.cellWidth * 0.42, y: c.y) }
    private var rightEdge: CGPoint { CGPoint(x: g.size.width - 10, y: g.gridTop + 20) }

    private func lifted(_ s: LaunchpadSurface, slot: Int = 2) -> Lift {
        var m = Lift()
        var before = s
        before.gap = nil
        let from = core(slot)
        _ = m.feed(.down, at: from, surface: before, time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: from.x + 6, y: from.y), surface: before, time: 0.01), .lift(address: slot))
        return m
    }

    // MARK: Time

    func testTimeGoingBackwardNeverFiresEarlyAndTheWakeStaysAheadOfTheDwell() {
        let s = surface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 10), .none)
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 5), .none, "a clock that went back has waited nothing")
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: -1000), .none)
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 10.119), .none)
        XCTAssertEqual(m.wake ?? 0, 10 + LaunchpadLiftTiming.marginDebounce, accuracy: 1e-9)
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 10.13), .moveGap(to: 5), "the control: the dwell does end")
    }

    func testEqualTimestampsAreNoTimeAtAll() {
        let s = surface(gap: 2)
        var m = lifted(s)
        for _ in 0..<50 { XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 7), .none) }
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 7), .none)
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 7 + LaunchpadLiftTiming.marginDebounce), .moveGap(to: 5), "and then it fires once")
    }

    func testAHeldEdgeOnTheLastPageSaysNewPageOncePerRepeatNotOncePerTick() {
        let s = surface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: rightEdge, surface: s, time: 1), .none)
        var pages = 0
        // Ticks every 10 ms for five seconds: the first dwell at 0.6 s, then one per 0.9 s.
        var t = 1.0
        while t < 6 {
            t += 0.01
            if m.feed(.tick, at: rightEdge, surface: s, time: t) == .newPage { pages += 1 }
        }
        XCTAssertEqual(pages, 1 + Int((5 - 0.6) / 0.9), "one per dwell: at 1.6, 2.5, 3.4, 4.3, 5.2: \(pages)")
        XCTAssertEqual(m.feed(.tick, at: rightEdge, surface: s, time: t), .none, "the same instant again is no second page")
    }

    func testLeavingTheCardAndEnteringItAgainWithinTheDelayClosesNothingAndTheSecondLeaveWaitsItsOwnDelay() {
        var s = surface(gap: 0)
        s.card = LaunchpadSurface.Card(geometry: g, count: 3)
        let rect = s.card!.rect
        var m = Lift()
        let from = s.card!.center(ofSlot: 0)
        var plain = s
        plain.gap = nil
        _ = m.feed(.down, at: from, surface: plain, time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: from.x + 6, y: from.y), surface: plain, time: 0.01), .lift(address: 0))
        let outside = CGPoint(x: rect.minX - LaunchpadLiftTiming.cardMargin - 20, y: rect.midY)
        let inside = s.card!.center(ofSlot: 2)
        XCTAssertEqual(m.feed(.moved, at: outside, surface: s, time: 1.0), .none)
        XCTAssertEqual(m.feed(.moved, at: inside, surface: s, time: 1.2), .none, "back in before 0.25 s")
        XCTAssertEqual(m.feed(.tick, at: inside, surface: s, time: 1.26), .none, "the first leave's delay is void")
        XCTAssertEqual(m.feed(.moved, at: outside, surface: s, time: 1.3), .none)
        XCTAssertEqual(m.feed(.tick, at: outside, surface: s, time: 1.54), .none, "0.25 s from the first leave, 0.24 from the second")
        XCTAssertEqual(m.feed(.tick, at: outside, surface: s, time: 1.55), .closeFolder)
    }

    // MARK: Order of events

    func testEventsOutOfOrderDoNothingAndLeaveNoWake() {
        let s = surface()
        var m = Lift()
        for input in [Lift.Input.up, .moved, .tick, .escape, .abort] {
            XCTAssertEqual(m.feed(input, at: core(2), surface: s, time: 1), .none, "\(input) with nothing down")
        }
        XCTAssertFalse(m.isEngaged)
        XCTAssertNil(m.wake)
        // Two downs: the second is not a second press.
        _ = m.feed(.down, at: core(2), surface: s, time: 1)
        XCTAssertEqual(m.feed(.down, at: core(5), surface: s, time: 1.1), .none)
        XCTAssertEqual(m.feed(.up, at: core(5), surface: s, time: 1.2), .click(address: 2), "the first press is the one let go")
        XCTAssertEqual(m.feed(.up, at: core(5), surface: s, time: 1.3), .none, "a second up")
        // A down while carried changes nothing.
        var carried = lifted(surface(gap: 2))
        XCTAssertEqual(carried.feed(.down, at: core(6), surface: surface(gap: 2), time: 1), .none)
        XCTAssertTrue(carried.isLifted)
        XCTAssertEqual(carried.feed(.up, at: core(6), surface: surface(gap: 2), time: 1.1), .release(.gap))
    }

    func testNoEndOfAPressLeavesAWake() {
        let s = surface(gap: 2)
        for end in [Lift.Input.up, .escape, .abort] {
            var m = lifted(s)
            _ = m.feed(.moved, at: margin(5), surface: s, time: 1)
            XCTAssertNotNil(m.wake, "the control: a dwell is waited for")
            _ = m.feed(end, at: margin(5), surface: s, time: 1.01)
            XCTAssertNil(m.wake, "\(end)")
            XCTAssertFalse(m.isEngaged)
            XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 9), .none, "\(end): a late tick")
        }
    }

    func testAPointThatIsNotAPlaceLiftsNothing() {
        let s = surface()
        for bad in [CGPoint(x: CGFloat.nan, y: CGFloat.nan), CGPoint(x: CGFloat.infinity, y: 0), CGPoint(x: 0, y: -CGFloat.infinity), CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)] {
            var m = Lift()
            _ = m.feed(.down, at: core(2), surface: s, time: 0)
            XCTAssertEqual(m.feed(.moved, at: bad, surface: s, time: 0.1), .none, "\(bad)")
            XCTAssertFalse(m.isLifted, "\(bad)")
        }
    }

    // MARK: The hit test

    func testTheExactBoundariesBelongToTheCellThatBeginsThere() {
        let s = surface(counts: [g.capacity])
        let x0 = g.origin(ofSlot: 0).x
        for column in 0..<g.columns {
            let x = x0 + CGFloat(column) * g.cellWidth
            guard case .tile(let a, _) = LaunchpadHit.at(CGPoint(x: x, y: g.gridTop + 1), in: s) else { XCTFail("column \(column)"); continue }
            XCTAssertEqual(a, column, "a cell's own left edge is its")
        }
        for row in 0..<g.rows {
            let y = g.gridTop + CGFloat(row) * g.cellHeight
            guard case .tile(let a, _) = LaunchpadHit.at(CGPoint(x: x0 + g.cellWidth / 2, y: y), in: s) else { XCTFail("row \(row)"); continue }
            XCTAssertEqual(a, row * g.columns, "a cell's own top edge is its")
        }
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: x0 + g.cellWidth / 2, y: g.gridTop + CGFloat(g.rows) * g.cellHeight), in: s), .none, "the bottom edge is outside")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: x0 + CGFloat(g.columns) * g.cellWidth + 0.01, y: g.gridTop + 1), in: s), .none, "the right edge of the last column is outside")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: x0 - 0.001, y: g.gridTop + 1), in: s), .none)
    }

    func testPointsFarOutsideAndPagesThatAreNotThereAreNothingAndNeverATrap() {
        let s = surface()
        for p in [CGPoint(x: -1e9, y: -1e9), CGPoint(x: 1e300, y: 1e300), CGPoint(x: -5, y: -5), CGPoint(x: 640, y: -100),
                  CGPoint(x: CGFloat.greatestFiniteMagnitude, y: g.gridTop + 1), CGPoint(x: 640, y: CGFloat.greatestFiniteMagnitude)] {
            XCTAssertEqual(LaunchpadHit.at(p, in: s), p.y >= g.gridTop && p.y < g.gridTop + g.pageHeight ? (p.x < 40 ? .edge(-1) : .edge(1)) : .none, "\(p)")
        }
        XCTAssertEqual(LaunchpadHit.at(core(1), in: surface(page: 1)), .none, "a page that is not there")
        XCTAssertEqual(LaunchpadHit.at(core(1), in: surface(page: -1)), .none)
        XCTAssertEqual(LaunchpadHit.at(core(1), in: LaunchpadSurface(geometry: g, page: 0, pageCounts: [], gap: nil)), .none, "no page at all")
    }

    func testEverySmallScreenAndEveryInsetAnswersWithinTheGridsOwnAddresses() {
        let sizes: [CGSize] = [CGSize(width: 1, height: 1), CGSize(width: 10, height: 10), CGSize(width: 60, height: 60), CGSize(width: 79, height: 200),
                               CGSize(width: 200, height: 100), CGSize(width: 0, height: 0), CGSize(width: -5, height: CGFloat.nan), CGSize(width: 100_000, height: 100_000)]
        for size in sizes { for topSafe in [0, 30, 5000, -20, CGFloat.nan, .infinity] as [CGFloat] {
            let geo = LaunchpadGeometry.make(for: size, topSafe: topSafe)
            for counts in [[0], [1], [geo.capacity], [geo.capacity, 3]] {
                var s = LaunchpadSurface(geometry: geo, page: counts.count - 1, pageCounts: counts, gap: nil)
                for card in [nil, LaunchpadSurface.Card(geometry: geo, count: 0), LaunchpadSurface.Card(geometry: geo, count: 1000)] {
                    s.card = card
                    let w = geo.size.width, h = geo.size.height
                    for i in 0...20 { for j in 0...20 {
                        let p = CGPoint(x: -w / 4 + w * 1.5 * CGFloat(i) / 20, y: -h / 4 + h * 1.5 * CGFloat(j) / 20)
                        switch LaunchpadHit.at(p, in: s) {
                        case .tile(let a, _): XCTAssertTrue(card != nil ? (0..<1000).contains(a) : a / geo.capacity == s.page && a % geo.capacity < counts[s.page], "\(size) \(p) \(a)")
                        case .gap(let a): XCTAssertTrue(card != nil || (a / geo.capacity == s.page && a % geo.capacity >= counts[s.page]), "\(size) \(p) \(a)")
                        case .edge, .away, .none: break
                        }
                    } }
                }
            }
            XCTAssertTrue(geo.gridTop.isFinite, "\(size) \(topSafe)")
            XCTAssertGreaterThan(geo.capacity, 0)
            XCTAssertGreaterThan(geo.cellWidth, 0)
        } }
    }
}
