import XCTest
@testable import Module_Launchpad_UI

/// The lift's machine, fed by hand with time of the test's own: no timer, no view.
final class LaunchpadLiftMachineTests: XCTestCase {
    private typealias Lift = LaunchpadLift
    private let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
    private func surface(page: Int = 0, counts: [Int] = [10], gap: Int? = nil) -> LaunchpadSurface {
        LaunchpadSurface(geometry: g, page: page, pageCounts: counts, gap: gap)
    }
    private func core(_ slot: Int) -> CGPoint { g.center(ofSlot: slot) }
    private func margin(_ slot: Int) -> CGPoint { let c = core(slot); return CGPoint(x: c.x + g.cellWidth * 0.42, y: c.y) }
    private var leftEdge: CGPoint { CGPoint(x: 10, y: g.gridTop + 20) }
    private var rightEdge: CGPoint { CGPoint(x: g.size.width - 10, y: g.gridTop + 20) }

    /// A machine that has lifted the tile at `address` of the shown page (the surface it is then fed has the gap there).
    private func lifted(_ s: LaunchpadSurface, slot: Int = 2) -> Lift {
        var m = Lift()
        var before = s
        before.gap = nil
        let from = core(slot)
        _ = m.feed(.down, at: from, surface: before, time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: from.x + 6, y: from.y), surface: before, time: 0.01),
                       .lift(address: s.page * g.capacity + slot))
        return m
    }

    func testAPressBecomesALiftOnlyPastTheThreshold() {
        var m = Lift()
        let s = surface()
        XCTAssertEqual(m.feed(.down, at: core(2), surface: s), .none)
        XCTAssertTrue(m.isEngaged)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: core(2).x + 4.9, y: core(2).y), surface: s, time: 0.01), .none)
        XCTAssertFalse(m.isLifted)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: core(2).x + 5, y: core(2).y), surface: s, time: 0.02), .lift(address: 2))
        XCTAssertTrue(m.isLifted)
    }

    func testAPressOutsideATileOrOnTheGapEngagesNothing() {
        var m = Lift()
        _ = m.feed(.down, at: core(10), surface: surface(), time: 0)
        XCTAssertFalse(m.isEngaged, "an empty cell")
        _ = m.feed(.down, at: CGPoint(x: 640, y: 10), surface: surface(), time: 0)
        XCTAssertFalse(m.isEngaged, "the search field's strip")
        _ = m.feed(.down, at: core(3), surface: surface(gap: 3), time: 0)
        XCTAssertFalse(m.isEngaged, "the gap")
    }

    func testLettingGoWithoutMovingIsAClickOnThatTile() {
        var m = Lift()
        _ = m.feed(.down, at: core(4), surface: surface())
        XCTAssertEqual(m.feed(.up, at: core(4), surface: surface(), time: 0.1), .click(address: 4))
        XCTAssertFalse(m.isEngaged)
        XCTAssertEqual(m.feed(.up, at: core(4), surface: surface(), time: 0.2), .none, "a second up is nothing")
    }

    func testTheMarginMovesTheGapOnlyAfterTheDebounce() {
        let s = surface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 1.0), .none)
        XCTAssertEqual(m.wake ?? 0, 1.0 + LaunchpadLiftTiming.marginDebounce, accuracy: 1e-9)
        XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 1.05), .none)
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 1.0 + LaunchpadLiftTiming.marginDebounce + 0.001), .moveGap(to: 5))
        XCTAssertNil(m.wake, "nothing more to wait for")
    }

    func testPassingThroughAMarginWithoutStayingMovesNothing() {
        let s = surface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 1.0), .none)
        XCTAssertEqual(m.feed(.moved, at: margin(6), surface: s, time: 1.08), .none)
        XCTAssertEqual(m.feed(.moved, at: margin(7), surface: s, time: 1.16), .none, "each tile waited on afresh")
    }

    func testStayingInTheIconArmsADropOntoItAndLeavingDisarmsIt() {
        let s = surface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: core(5), surface: s, time: 1.0), .none)
        XCTAssertEqual(m.feed(.tick, at: core(5), surface: s, time: 1.0 + LaunchpadLiftTiming.ontoArm + 0.001), .arm(address: 5))
        XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 1.5), .arm(address: nil))
        XCTAssertEqual(m.feed(.moved, at: core(5), surface: s, time: 1.6), .none)
        _ = m.feed(.tick, at: core(5), surface: s, time: 1.6 + LaunchpadLiftTiming.ontoArm + 0.001)
        XCTAssertEqual(m.feed(.up, at: core(5), surface: s, time: 2.0), .release(.onto(address: 5)))
    }

    func testPastTheLastTileTheGapGoesToTheEmptyCell() {
        let s = surface(gap: 2)
        var m = lifted(s)
        _ = m.feed(.moved, at: core(15), surface: s, time: 1.0)
        XCTAssertEqual(m.feed(.tick, at: core(15), surface: s, time: 1.2), .moveGap(to: 15))
    }

    func testTheEdgeTurnsAfterItsDwellAndRepeatsAndTheFirstPageHasNoPageBefore() {
        let s = surface(page: 1, counts: [10, 10, 10], gap: 40)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: rightEdge, surface: s, time: 2.0), .none)
        XCTAssertEqual(m.feed(.tick, at: rightEdge, surface: s, time: 2.59), .none)
        XCTAssertEqual(m.feed(.tick, at: rightEdge, surface: s, time: 2.61), .turn(1))
        XCTAssertEqual(m.feed(.tick, at: rightEdge, surface: s, time: 3.4), .none)
        XCTAssertEqual(m.feed(.tick, at: rightEdge, surface: s, time: 3.52), .turn(1), "again after the repeat")
        XCTAssertEqual(m.feed(.moved, at: leftEdge, surface: s, time: 4.0), .none)
        XCTAssertEqual(m.feed(.tick, at: leftEdge, surface: s, time: 4.61), .turn(-1))

        let first = surface(page: 0, counts: [10, 10], gap: 2)
        var f = lifted(first)
        _ = f.feed(.moved, at: leftEdge, surface: first, time: 5)
        XCTAssertEqual(f.feed(.tick, at: leftEdge, surface: first, time: 6), .none, "no turn before the first page")
    }

    func testTheRightEdgeOfTheLastPageMakesANewPage() {
        let s = surface(page: 1, counts: [10, 10], gap: 12)
        var m = lifted(s)
        _ = m.feed(.moved, at: rightEdge, surface: s, time: 2.0)
        XCTAssertEqual(m.feed(.tick, at: rightEdge, surface: s, time: 2.61), .newPage)
    }

    func testALiftEndsInExactlyOneOutcome() {
        for (end, expected) in [(Lift.Input.up, Lift.Effect.release(.gap)), (.escape, .cancel), (.abort, .cancel)] {
            let s = surface(gap: 2)
            var m = lifted(s)
            XCTAssertEqual(m.feed(end, at: core(2), surface: s, time: 1), expected, "\(end)")
            XCTAssertFalse(m.isEngaged)
            for late in [Lift.Input.up, .escape, .abort, .tick, .moved] {
                XCTAssertEqual(m.feed(late, at: core(5), surface: s, time: 2), .none, "\(late) after \(end)")
            }
        }
    }

    func testEscapeAndAbortCancelAPressToo() {
        var m = Lift()
        _ = m.feed(.down, at: core(1), surface: surface())
        XCTAssertEqual(m.feed(.escape, surface: surface()), .cancel)
        _ = m.feed(.down, at: core(1), surface: surface())
        XCTAssertEqual(m.feed(.up, at: core(1), surface: surface()), .click(address: 1), "the press was cancelled, not stuck: a new one clicks")
    }

    // MARK: Folders

    private func folderSurface(gap: Int? = nil) -> LaunchpadSurface {
        var s = surface(gap: gap)
        s.folders = [1]
        return s
    }

    func testAFolderOpensAfterItsLongerDwellAndAnAppDoesNot() {
        let s = folderSurface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: core(1), surface: s, time: 1.0), .none)
        XCTAssertEqual(m.wake ?? 0, 1.0 + LaunchpadLiftTiming.ontoArm, accuracy: 1e-9)
        XCTAssertEqual(m.feed(.tick, at: core(1), surface: s, time: 1.31), .arm(address: 1))
        XCTAssertEqual(m.wake ?? 0, 1.0 + LaunchpadLiftTiming.folderOpen, accuracy: 1e-9, "armed, and a folder: the open is next")
        XCTAssertEqual(m.feed(.tick, at: core(1), surface: s, time: 1.69), .none)
        XCTAssertEqual(m.feed(.tick, at: core(1), surface: s, time: 1.0 + LaunchpadLiftTiming.folderOpen + 0.001), .openFolder(address: 1))
        XCTAssertNil(m.wake)

        var app = lifted(s)
        XCTAssertEqual(app.feed(.moved, at: core(4), surface: s, time: 1.0), .none)
        XCTAssertEqual(app.feed(.tick, at: core(4), surface: s, time: 1.31), .arm(address: 4))
        XCTAssertEqual(app.feed(.tick, at: core(4), surface: s, time: 3), .none, "the control: an app's icon is armed and nothing more")
        XCTAssertNil(app.wake)
    }

    func testLeavingTheFolderBeforeItsDwellEndsOpensNothing() {
        let s = folderSurface(gap: 2)
        var m = lifted(s)
        XCTAssertEqual(m.feed(.moved, at: core(1), surface: s, time: 1.0), .none)
        XCTAssertEqual(m.feed(.tick, at: core(1), surface: s, time: 1.31), .arm(address: 1))
        XCTAssertEqual(m.feed(.moved, at: margin(5), surface: s, time: 1.5), .arm(address: nil), "the target is let go")
        XCTAssertEqual(m.feed(.tick, at: margin(5), surface: s, time: 1.9), .moveGap(to: 5))
    }

    private func cardSurface(count: Int = 3, gap: Int? = nil) -> LaunchpadSurface {
        var s = surface(counts: [5], gap: gap)
        s.card = LaunchpadSurface.Card(geometry: g, count: count)
        return s
    }

    /// A machine that has lifted the card's tile `slot`.
    private func liftedInCard(_ slot: Int = 0) -> Lift {
        var m = Lift()
        let s = cardSurface()
        let from = s.card!.center(ofSlot: slot)
        _ = m.feed(.down, at: from, surface: s, time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: from.x + 6, y: from.y), surface: s, time: 0.01), .lift(address: slot))
        return m
    }

    func testTheCardClosesAfterTheLeaveDelayOnceThePointerHasBeenInIt() {
        let s = cardSurface(gap: 0)
        let card = s.card!.rect
        var m = liftedInCard()
        let outside = CGPoint(x: card.minX - LaunchpadLiftTiming.cardMargin - 1, y: card.midY)
        XCTAssertEqual(m.feed(.moved, at: outside, surface: s, time: 1.0), .none)
        XCTAssertEqual(m.wake ?? 0, 1.0 + LaunchpadLiftTiming.leaveCard, accuracy: 1e-9)
        XCTAssertEqual(m.feed(.tick, at: outside, surface: s, time: 1.24), .none)
        XCTAssertEqual(m.feed(.tick, at: outside, surface: s, time: 1.251), .closeFolder)
        XCTAssertNil(m.wake)
    }

    func testTheCardsMarginIsStillTheCard() {
        let s = cardSurface(gap: 0)
        let card = s.card!.rect
        var m = liftedInCard()
        let margin = CGPoint(x: card.minX - LaunchpadLiftTiming.cardMargin + 1, y: card.midY)
        XCTAssertEqual(m.feed(.moved, at: margin, surface: s, time: 1.0), .none)
        XCTAssertEqual(m.feed(.tick, at: margin, surface: s, time: 5), .none)
        XCTAssertNil(m.wake)
    }

    func testACardThatOpenedWhereThePointerIsNotIsNotClosedByThePointerBeingThere() {
        let s = cardSurface(gap: 0)
        var m = Lift()
        _ = m.feed(.down, at: core(2), surface: surface(), time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: core(2).x + 6, y: core(2).y), surface: surface(), time: 0.01), .lift(address: 2))
        let outside = CGPoint(x: s.card!.rect.minX - 100, y: s.card!.rect.midY)
        XCTAssertEqual(m.feed(.moved, at: outside, surface: s, time: 1), .none)
        XCTAssertNil(m.wake, "never inside: nothing is waited for")
        XCTAssertEqual(m.feed(.tick, at: outside, surface: s, time: 9), .none)
    }

    func testInsideTheCardAMarginDwellMovesTheGapAmongTheApps() {
        let s = cardSurface(gap: 0)
        var m = liftedInCard()
        let at = s.card!.center(ofSlot: 2)
        XCTAssertEqual(m.feed(.moved, at: at, surface: s, time: 1), .none)
        XCTAssertEqual(m.feed(.tick, at: at, surface: s, time: 1.13), .moveGap(to: 2))
        XCTAssertNotEqual(m.feed(.moved, at: s.card!.center(ofSlot: 1), surface: s, time: 2), .arm(address: 1), "nothing is dropped onto an app in a folder")
        XCTAssertEqual(m.feed(.tick, at: s.card!.center(ofSlot: 1), surface: s, time: 3), .moveGap(to: 1))
    }

    // MARK: A card with pages

    private func pagedSurface(page: Int, count: Int? = nil) -> LaunchpadSurface {
        let cap = LaunchpadSurface.Card(geometry: g, count: 10_000).capacity
        var s = surface(counts: [5], gap: nil)
        s.card = LaunchpadSurface.Card(geometry: g, count: count ?? 2 * cap, page: page)
        return s
    }

    /// A machine that has lifted the first tile of the card's shown page; the point the pointer then goes to is a strip.
    private func liftedInPagedCard(_ s: LaunchpadSurface) -> Lift {
        var m = Lift()
        let from = s.card!.center(ofSlot: 0)
        _ = m.feed(.down, at: from, surface: s, time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: from.x + 6, y: from.y), surface: s, time: 0.01), .lift(address: s.card!.page * s.card!.capacity))
        return m
    }

    private func strips(_ s: LaunchpadSurface) -> (left: CGPoint, right: CGPoint) {
        let c = s.card!
        return (CGPoint(x: c.origin.x - 5, y: c.rect.midY), CGPoint(x: c.origin.x + c.pageWidth + 5, y: c.rect.midY))
    }

    func testACardsEdgeStripTurnsItsPageAfterTheFirstDelayAndAgainAfterTheRepeat() {
        let s = pagedSurface(page: 1, count: 3 * LaunchpadSurface.Card(geometry: g, count: 10_000).capacity)
        var m = liftedInPagedCard(s)
        let p = strips(s)
        XCTAssertEqual(m.feed(.moved, at: p.left, surface: s, time: 1), .none)
        XCTAssertEqual(m.feed(.tick, at: p.left, surface: s, time: 1.59), .none)
        XCTAssertEqual(m.feed(.tick, at: p.left, surface: s, time: 1.61), .turn(-1))
        XCTAssertEqual(m.feed(.tick, at: p.left, surface: s, time: 2.0), .none, "not again before the repeat")
        XCTAssertEqual(m.feed(.tick, at: p.left, surface: s, time: 2.52), .turn(-1))
        XCTAssertEqual(m.feed(.moved, at: p.right, surface: s, time: 3), .none)
        XCTAssertEqual(m.feed(.tick, at: p.right, surface: s, time: 3.61), .turn(1), "the middle page turns forward")
    }

    func testTheLastCardPageNeverMakesANewPageAndTheFirstHasNothingBefore() {
        let last = pagedSurface(page: 1)
        var m = liftedInPagedCard(last)
        let p = strips(last)
        XCTAssertEqual(m.feed(.moved, at: p.right, surface: last, time: 1), .none)
        for t in stride(from: 1.61, to: 12, by: 0.9) {
            XCTAssertEqual(m.feed(.tick, at: p.right, surface: last, time: t), .none, "\(t): never .newPage in a card")
        }
        let first = pagedSurface(page: 0)
        var n = liftedInPagedCard(first)
        let q = strips(first)
        XCTAssertEqual(n.feed(.moved, at: q.left, surface: first, time: 1), .none)
        XCTAssertEqual(n.feed(.tick, at: q.left, surface: first, time: 1.61), .none, "page 0's left")
        XCTAssertEqual(n.feed(.tick, at: q.right, surface: first, time: 2), .none)
        XCTAssertEqual(n.feed(.tick, at: q.right, surface: first, time: 2.7), .turn(1), "the control: its right strip does turn")
    }

    func testAnUnpagedCardHasNoStripsAndTheGridsLastPageStillMakesAPage() {
        let one = pagedSurface(page: 0, count: 3)
        var m = liftedInCard()
        let p = strips(one)
        XCTAssertEqual(m.feed(.moved, at: p.right, surface: one, time: 1), .none)
        XCTAssertEqual(m.feed(.tick, at: p.right, surface: one, time: 1.7), .none, "a card of one page has no strip")
        let grid = surface(page: 0, counts: [5], gap: 2)
        var n = lifted(grid)
        XCTAssertEqual(n.feed(.moved, at: rightEdge, surface: grid, time: 1), .none)
        XCTAssertEqual(n.feed(.tick, at: rightEdge, surface: grid, time: 1.61), .newPage, "the grid's last page, as before")
    }
}
