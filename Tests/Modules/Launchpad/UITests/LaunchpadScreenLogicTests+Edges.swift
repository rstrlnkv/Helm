import AppKit
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Inputs the first pass of `LaunchpadScreenLogicTests` did not feed: the screens at both ends, every edge of the
/// arrow keys, the pager's odd clocks, and the state's Esc/Return paths. Same class, so the same optional-tests row.
extension LaunchpadScreenLogicTests {

    // MARK: - Geometry

    func testA1024By640ScreenGetsSixColumnsAndThreeRows() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1024, height: 640), topSafe: 0)
        XCTAssertEqual(g.columns, 6)
        XCTAssertEqual(g.rows, 3)
        XCTAssertEqual(g.capacity, 18)
        XCTAssertEqual(g.gridTop, 96, accuracy: 0.001)
        XCTAssertEqual(g.cellWidth, 1024 * 0.84 / 6, accuracy: 0.001)
        XCTAssertLessThanOrEqual(g.gridTop + g.pageHeight + LaunchpadMetrics.dotsRoom, 640, "the dots keep their room")
    }

    func testAnEightKScreenStopsAtEightColumnsAndSixRows() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 6016, height: 3384), topSafe: 0)
        XCTAssertEqual(g.columns, 8)
        XCTAssertEqual(g.rows, 6)
        XCTAssertEqual(g.capacity, 48)
        XCTAssertEqual(g.pageWidth, 6016)
    }

    func testNoScreenFromAWholeSweepHasAGridOverlappingItsDots() {
        for width in stride(from: CGFloat(1024), through: 7000, by: 111) {
            for height in stride(from: CGFloat(640), through: 4000, by: 97) {
                for topSafe in [CGFloat(0), 24, 38, 64] {
                    let g = LaunchpadGeometry.make(for: CGSize(width: width, height: height), topSafe: topSafe)
                    XCTAssertGreaterThanOrEqual(g.cellWidth, LaunchpadMetrics.tileMinimum, "\(width)x\(height)")
                    XCTAssertLessThanOrEqual(g.gridTop + g.pageHeight + LaunchpadMetrics.dotsRoom, height, "\(width)x\(height) top \(topSafe)")
                }
            }
        }
    }

    func testANegativeTopSafeIsNoTopSafeAndAnInfiniteOneToo() {
        let plain = LaunchpadGeometry.make(for: CGSize(width: 1440, height: 900), topSafe: 0)
        XCTAssertEqual(LaunchpadGeometry.make(for: CGSize(width: 1440, height: 900), topSafe: -50), plain)
        XCTAssertEqual(LaunchpadGeometry.make(for: CGSize(width: 1440, height: 900), topSafe: .infinity), plain)
        let capped = LaunchpadGeometry.make(for: CGSize(width: 1440, height: 900), topSafe: 10_000)
        XCTAssertEqual(capped.searchTop, 225 + LaunchpadMetrics.searchTop, accuracy: 0.001, "a quarter of the height at most")
    }

    func testAOnePointWideScreenStillMakesAGridOfThreeColumns() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1, height: 1), topSafe: 0)
        XCTAssertEqual(g.columns, 3)
        XCTAssertEqual(g.rows, 2)
        XCTAssertTrue(g.cellWidth.isFinite && g.cellWidth > 0)
    }

    // MARK: - Paging

    func testPageCountAtEveryBoundary() {
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 1, capacity: 18), 1)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 18, capacity: 18), 1)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 19, capacity: 18), 2)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 36, capacity: 18), 2)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 37, capacity: 18), 3)
        XCTAssertEqual(LaunchpadPaging.pageCount(items: 0, capacity: -3), 1)
    }

    func testASliceAtTheBoundaryHoldsExactlyTheCapacityAndNoMore() {
        let items = Array(0..<19)
        XCTAssertEqual(LaunchpadPaging.slice(items, page: 0, capacity: 18), Array(0..<18))
        XCTAssertEqual(LaunchpadPaging.slice(items, page: 1, capacity: 18), [18])
        XCTAssertEqual(LaunchpadPaging.slice([Int](), page: 0, capacity: 18), [])
        XCTAssertEqual(LaunchpadPaging.slice(Array(0..<18), page: 1, capacity: 18), [])
        XCTAssertEqual(LaunchpadPaging.slice(items, page: 0, capacity: 0), [])
    }

    func testOneTileCanMoveNowhereAndSelectsItselfOnTheFirstPress() {
        XCTAssertEqual(LaunchpadPaging.moved(nil, dx: 0, dy: 1, columns: 6, count: 1), 0)
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)] {
            XCTAssertEqual(LaunchpadPaging.moved(0, dx: dx, dy: dy, columns: 6, count: 1), 0, "\(dx),\(dy)")
        }
    }

    func testTheChoiceStopsAtEveryEdgeOfAFullAndOfAShortGrid() {
        // 4 columns, 10 tiles: rows 0-3, 4-7, 8-9.
        XCTAssertEqual(LaunchpadPaging.moved(2, dx: 0, dy: -1, columns: 4, count: 10), 2, "up from the top row stays")
        XCTAssertEqual(LaunchpadPaging.moved(8, dx: 0, dy: 1, columns: 4, count: 10), 8, "down from the last row stays")
        XCTAssertEqual(LaunchpadPaging.moved(3, dx: 1, dy: 0, columns: 4, count: 10), 4, "right off a row's end is the next row's first")
        XCTAssertEqual(LaunchpadPaging.moved(4, dx: -1, dy: 0, columns: 4, count: 10), 3)
        XCTAssertEqual(LaunchpadPaging.moved(6, dx: 0, dy: 1, columns: 4, count: 10), 9, "a short last row is reached at its end")
        XCTAssertEqual(LaunchpadPaging.moved(1, dx: 1, dy: 1, columns: 4, count: 10), 6, "a diagonal")
        XCTAssertEqual(LaunchpadPaging.moved(9, dx: 1, dy: 1, columns: 4, count: 10), 9, "a diagonal off the end")
        XCTAssertEqual(LaunchpadPaging.moved(-1, dx: 0, dy: 0, columns: 4, count: 10), 0, "a negative choice is not kept")
        XCTAssertNil(LaunchpadPaging.moved(3, dx: 1, dy: 0, columns: 0, count: 10), "no columns, no move")
        XCTAssertNil(LaunchpadPaging.moved(3, dx: 1, dy: 0, columns: 4, count: -1))
    }

    func testTheChoiceCrossesAPageBoundaryBothWays() {
        XCTAssertEqual(LaunchpadPaging.moved(17, dx: 1, dy: 0, columns: 6, count: 40), 18)
        XCTAssertEqual(LaunchpadPaging.page(of: 18, capacity: 18), 1)
        XCTAssertEqual(LaunchpadPaging.moved(18, dx: -1, dy: 0, columns: 6, count: 40), 17)
        XCTAssertEqual(LaunchpadPaging.page(of: 17, capacity: 18), 0)
        XCTAssertEqual(LaunchpadPaging.page(of: -4, capacity: 18), 0)
        XCTAssertEqual(LaunchpadPaging.page(of: 5, capacity: 0), 0)
    }

    // MARK: - The pager

    func testAFlickTurnsFromTheFortiethPointAndNotBefore() {
        for (events, step) in [(9, 0), (10, 1)] {
            var swipe = LaunchpadSwipe()
            _ = fed(&swipe, -4, .began, 0)
            for i in 1..<events { _ = fed(&swipe, -4, .changed, Double(i) / 240) }
            guard case .release(let got, _) = fed(&swipe, 0, .ended, 0.1) else { return XCTFail("\(events)") }
            XCTAssertEqual(got, step, "\(events * 4) pt at 960 pt/s")
        }
    }

    func testASwipeThatGoesBackAndForthIsJudgedByWhereItEnded() {
        var swipe = LaunchpadSwipe()
        _ = fed(&swipe, -30, .began, 0)
        XCTAssertEqual(fed(&swipe, 25, .changed, 0.004), .drag(raw: -5))
        XCTAssertEqual(releasedStep(fed(&swipe, 0, .ended, 0.01)), 0, "-5 net: nothing, the path was 55")
        XCTAssertEqual(fed(&swipe, -30, .began, 1), .drag(raw: -30))
        XCTAssertEqual(fed(&swipe, 25, .changed, 1.004), .drag(raw: -5))
        XCTAssertEqual(fed(&swipe, -30, .changed, 1.008), .drag(raw: -35))
        XCTAssertEqual(fed(&swipe, -20, .changed, 1.012), .drag(raw: -55))
        guard case .release(let step, _) = fed(&swipe, 0, .ended, 1.02) else { return XCTFail("the lift") }
        XCTAssertEqual(step, 1, "-55 travelled, and leaving fast")
    }

    func testMomentumAfterATurnAndAfterASnapBackNeverTurnsAndNextGestureStillDoes() {
        var swipe = LaunchpadSwipe()
        _ = fed(&swipe, -25, .began, 0)
        _ = fed(&swipe, -25, .changed, 0.004)
        XCTAssertEqual(releasedStep(fed(&swipe, 0, .ended, 0.1)), 1)
        for i in 0..<10 { XCTAssertEqual(fed(&swipe, -80, [], 0.2 + Double(i) * 0.01, momentum: .changed), .none) }
        XCTAssertEqual(fed(&swipe, 0, [], 0.5, momentum: .ended), .none)
        _ = fed(&swipe, -25, .began, 3)
        _ = fed(&swipe, -25, .changed, 3.004)
        XCTAssertEqual(releasedStep(fed(&swipe, 0, .ended, 3.1)), 1)
    }

    func testAWheelAtTheSameTimestampOrAnEarlierOneTurnsOnceAndTheQuarterSecondEdgeIsExact() {
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: 0, dy: -1, precise: false, time: 10), 1)
        XCTAssertNil(pager.feed(dx: 0, dy: -1, precise: false, time: 10), "equal timestamp")
        XCTAssertNil(pager.feed(dx: 0, dy: -1, precise: false, time: 5), "the clock went back")
        XCTAssertNil(pager.feed(dx: 0, dy: -1, precise: false, time: 10.249))
        XCTAssertEqual(pager.feed(dx: 0, dy: -1, precise: false, time: 10.25), 1, "exactly 250 ms is a turn")
    }

    func testAWheelAtTimeZeroAndANegativeTimeTurnBecauseNothingTurnedBefore() {
        var a = LaunchpadScrollPager()
        XCTAssertEqual(a.feed(dx: 0, dy: -1, precise: false, time: 0), 1)
        var b = LaunchpadScrollPager()
        XCTAssertEqual(b.feed(dx: 0, dy: 1, precise: false, time: -100), -1)
    }

    func testAWheelAndAPhaselessSwipeDoNotSpendEachOthersAllowance() {
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: 0, dy: -1, precise: false, time: 1), 1)
        XCTAssertEqual(pager.feed(dx: -50, dy: 0, precise: true, time: 1.01), 1, "the swipe is not held by the wheel's pause")
        XCTAssertNil(pager.feed(dx: 0, dy: -1, precise: false, time: 1.1), "the wheel's pause holds")
        XCTAssertEqual(pager.feed(dx: 0, dy: -1, precise: false, time: 1.3), 1)
    }

    func testAWheelNotchesBothDirectionsFollowTheSign() {
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: 3, dy: 0, precise: false, time: 1), -1, "a horizontal notch wins over vertical")
        XCTAssertEqual(pager.feed(dx: 0, dy: .infinity, precise: false, time: 9), nil)
    }

    func testACancelledGestureSnapsBackAndStartsTheSumAgain() {
        var swipe = LaunchpadSwipe()
        XCTAssertEqual(fed(&swipe, -30, .changed, 0), .drag(raw: -30))
        XCTAssertEqual(fed(&swipe, 0, .cancelled, 0.1), .release(step: 0, velocity: 0), "the page goes back, it is not left held")
        XCTAssertEqual(fed(&swipe, -30, .began, 1), .drag(raw: -30), "30 + 30 across a cancel is not 60")
    }

    func testAMayBeginResetsAGestureThatHadNoEnd() {
        var swipe = LaunchpadSwipe()
        XCTAssertEqual(fed(&swipe, -50, .began, 0), .drag(raw: -50))
        XCTAssertEqual(fed(&swipe, 0, .mayBegin, 1), .none)
        XCTAssertEqual(fed(&swipe, -50, .changed, 1.1), .drag(raw: -50), "not -100")
    }

    // MARK: - The state

    private static let names = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"]

    private func snapshot(_ ids: [String], items: [LaunchpadLayout.Item]? = nil, hidden: Set<String> = []) -> LaunchpadSnapshot {
        let apps = ids.map { CatalogApp(id: $0, name: $0.capitalized, path: "/Applications/\($0).app") }
        var layout = LaunchpadLayout(items: items ?? ids.map { .app($0) })
        layout.hidden = hidden
        return LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: ids,
                                 layout: layout, catalogComplete: true, layoutRead: .absent)
    }

    /// A 1024 x 640 screen: 6 columns, 18 to a page.
    @MainActor private func state(_ snap: LaunchpadSnapshot?) -> LaunchpadScreenState {
        let state = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1024, height: 640), topSafe: 0))
        state.update(snapshot: snap)
        return state
    }

    private func folder(_ name: String, _ apps: [String]) -> (UUID, LaunchpadLayout.Item) {
        let id = UUID()
        return (id, .folder(.init(id: id, name: name, apps: apps)))
    }

    @MainActor func testSearchWithNoHitsSaysSoAndClearingItBringsTheGridBack() {
        let s = state(snapshot(["alpha", "bravo"]))
        XCTAssertEqual(s.mode, .grid)
        s.search = "zzz"
        XCTAssertEqual(s.mode, .noMatch)
        XCTAssertNil(s.selection)
        s.move(dx: 1, dy: 0)
        XCTAssertNil(s.selection, "nothing to choose among no hits")
        s.activate()
        s.search = ""
        XCTAssertEqual(s.mode, .grid)
        XCTAssertEqual(s.pages.first?.count, 2)
        XCTAssertNil(s.selection)
    }

    @MainActor func testASearchWithHitsSelectsTheFirstAndReturnLaunchesIt() {
        let s = state(snapshot(["alpha", "bravo"]))
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        s.search = "brav"
        XCTAssertEqual(s.selection, 0)
        s.activate()
        XCTAssertEqual(launched, ["bravo"])
    }

    @MainActor func testTwoSearchesThenASnapshotKeepTheChoiceOnTheCurrentFirstHitAndReturnLaunchesIt() {
        let s = state(snapshot(["alpha", "cab"]))
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        s.search = "a"
        XCTAssertEqual(s.pages.first?.map(\.id), ["alpha", "cab"])
        s.search = "ab"
        XCTAssertEqual(s.pages.first?.map(\.id), ["cab"])
        XCTAssertEqual(s.selection, 0)
        s.update(snapshot: snapshot(["alpha", "cab"]))
        XCTAssertEqual(s.selection, 0, "the highlight is on cab, a snapshot does not send it back to alpha")
        s.activate()
        XCTAssertEqual(launched, ["cab"])
    }

    @MainActor func testASearchGoesBackToTheFirstPage() {
        let ids = Self.names + (0..<20).map { "app\($0)" }
        let s = state(snapshot(ids))
        s.go(to: 1)
        XCTAssertEqual(s.page, 1)
        s.search = "app1"
        XCTAssertEqual(s.page, 0)
    }

    @MainActor func testASearchOfOnlySpacesIsNoSearchAndEscapeClosesTheWindowThroughIt() {
        let s = state(snapshot(["alpha"]))
        var closed = 0
        s.onClose = { closed += 1 }
        s.search = "   "
        XCTAssertEqual(s.mode, .grid)
        XCTAssertNil(s.selection)
        s.escape()
        XCTAssertEqual(closed, 1, "spaces are no search to clear")
    }

    @MainActor func testEscapeClearsTheSearchThenClosesTheWindow() {
        let s = state(snapshot(["alpha", "bravo"]))
        var closed = 0
        s.onClose = { closed += 1 }
        s.search = "al"
        s.escape()
        XCTAssertEqual(s.search, "")
        XCTAssertEqual(closed, 0, "the first Esc only clears")
        s.escape()
        XCTAssertEqual(closed, 1)
    }

    @MainActor func testEscapeClosesTheFolderBeforeAnythingElseAndGivesTheChoiceBackToItsTile() {
        let (id, item) = folder("F", ["bravo", "charlie"])
        let s = state(snapshot(["alpha", "bravo", "charlie"], items: [.app("alpha"), item]))
        var closed = 0
        s.onClose = { closed += 1 }
        s.open(folder: id)
        XCTAssertEqual(s.openFolder, id)
        XCTAssertEqual(s.folderApps.map(\.id), ["bravo", "charlie"])
        s.escape()
        XCTAssertNil(s.openFolder)
        XCTAssertEqual(s.folderApps, [])
        XCTAssertEqual(s.selection, 1, "the folder's own tile")
        XCTAssertEqual(closed, 0)
        s.escape()
        XCTAssertEqual(closed, 1)
    }

    @MainActor func testTypingInTheSearchWithAFolderOpenClosesTheFolder() {
        let (id, item) = folder("F", ["bravo", "charlie"])
        let s = state(snapshot(["alpha", "bravo", "charlie"], items: [.app("alpha"), item]))
        s.open(folder: id)
        s.search = "a"
        XCTAssertNil(s.openFolder)
        XCTAssertEqual(s.folderName, "")
    }

    @MainActor func testABackgroundClickClosesTheFolderFirstAndTheWindowOnlyWithNoFolder() {
        let (id, item) = folder("F", ["bravo", "charlie"])
        let s = state(snapshot(["alpha", "bravo", "charlie"], items: [.app("alpha"), item]))
        var closed = 0
        s.onClose = { closed += 1 }
        s.backgroundClicked()
        XCTAssertEqual(closed, 1, "no folder: the window")
        s.open(folder: id)
        s.backgroundClicked()
        XCTAssertNil(s.openFolder)
        XCTAssertEqual(closed, 1, "a folder open: only the folder")
        s.backgroundClicked()
        XCTAssertEqual(closed, 2)
    }

    @MainActor func testReturnWithNoChoiceDoesNothingAndOnAFolderOpensItsCard() {
        let (id, item) = folder("F", ["bravo", "charlie"])
        let s = state(snapshot(["alpha", "bravo", "charlie"], items: [.app("alpha"), item]))
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        s.activate()
        XCTAssertTrue(launched.isEmpty)
        XCTAssertNil(s.openFolder)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 0)
        s.move(dx: 1, dy: 0)
        s.activate()
        XCTAssertEqual(s.openFolder, id)
        XCTAssertTrue(launched.isEmpty, "a folder is not launched")
        XCTAssertNil(s.selection)
        s.activate()
        XCTAssertTrue(launched.isEmpty, "Return in a fresh card with no choice does nothing")
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 1)
        s.activate()
        XCTAssertEqual(launched, ["charlie"])
    }

    @MainActor func testTheArrowKeysInAFolderStayInsideItAndDoNotTurnThePage() {
        let ids = (0..<30).map { "app\($0)" }
        let (id, item) = folder("F", ["app1", "app2", "app3"])
        let items: [LaunchpadLayout.Item] = [item] + ids.filter { !["app1", "app2", "app3"].contains($0) }.map { .app($0) }
        let s = state(snapshot(ids, items: items))
        s.go(to: 1)
        s.open(folder: id) // the first tile is on page 0, so it cannot be opened by id from page 1's view: the state still can
        s.turn(1)
        XCTAssertEqual(s.page, 1, "a folder open holds the page")
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        XCTAssertNotNil(s.selection)
        XCTAssertLessThan(s.selection ?? 99, 3, "the choice is among the folder's three")
        XCTAssertEqual(s.page, 1)
    }

    @MainActor func testASnapshotThatShrinksBelowTheShownPageBringsThePageAndTheChoiceBack() {
        let ids = (0..<40).map { "app\($0)" }
        let s = state(snapshot(ids))
        XCTAssertEqual(s.pageCount, 3)
        s.go(to: 2)
        XCTAssertEqual(s.page, 2)
        s.update(snapshot: snapshot(Array(ids.prefix(25))))
        XCTAssertEqual(s.pageCount, 2)
        XCTAssertEqual(s.page, 1, "the last page there is, not the one that went")
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 0)
        s.move(dx: 0, dy: 1)
        s.move(dx: 0, dy: 1)
        s.move(dx: 0, dy: 1)
        XCTAssertEqual(s.selection, 18, "three rows down from 0 on a six-column grid is the next page's first row")
        s.update(snapshot: snapshot(Array(ids.prefix(5))))
        XCTAssertEqual(s.pageCount, 1)
        XCTAssertEqual(s.page, 0)
        XCTAssertNil(s.selection, "the chosen app is gone: no choice, not its neighbour")
        s.update(snapshot: snapshot([]))
        XCTAssertEqual(s.mode, .noApps)
        XCTAssertNil(s.selection)
        XCTAssertEqual(s.pages.count, 1)
        XCTAssertEqual(s.page, 0)
    }

    @MainActor func testTheFolderVanishingUnderAnOpenCardClosesTheCardAndLeavesNoChoice() {
        let (id, item) = folder("F", ["bravo", "charlie"])
        let s = state(snapshot(["alpha", "bravo", "charlie"], items: [.app("alpha"), item]))
        s.open(folder: id)
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 1, "the second app of the folder")
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        s.update(snapshot: snapshot(["alpha", "bravo", "charlie"]))
        XCTAssertNil(s.openFolder)
        XCTAssertEqual(s.folderApps, [])
        s.activate()
        XCTAssertTrue(launched.isEmpty, "an index into the folder is not an index into the grid: Return launches nothing the person chose")
    }

    @MainActor func testAChosenAppStaysChosenWhenAnAppBeforeItIsHidden() {
        let s = state(snapshot(["alpha", "bravo", "charlie", "delta"]))
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        for _ in 0..<3 { s.move(dx: 1, dy: 0) }
        XCTAssertEqual(s.selection, 2, "charlie")
        s.update(snapshot: snapshot(["alpha", "bravo", "charlie", "delta"], items: [.app("bravo"), .app("charlie"), .app("delta")], hidden: ["alpha"]))
        XCTAssertEqual(s.pages.first?.map(\.id), ["bravo", "charlie", "delta"])
        XCTAssertEqual(s.selection, 1, "charlie moved up one, the choice with it")
        s.activate()
        XCTAssertEqual(launched, ["charlie"])
    }

    @MainActor func testAChosenAppThatIsRemovedLeavesNoChoiceAndReturnLaunchesNothing() {
        let s = state(snapshot(["alpha", "bravo", "charlie"]))
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 1, "bravo")
        s.update(snapshot: snapshot(["alpha", "charlie"]))
        XCTAssertNil(s.selection)
        s.activate()
        XCTAssertTrue(launched.isEmpty)
        s.update(snapshot: snapshot(["alpha", "bravo", "charlie"]))
        XCTAssertNil(s.selection, "it does not come back when the app does")
    }

    @MainActor func testAResetThatReordersTheTilesKeepsTheSameAppChosen() {
        let s = state(snapshot(["alpha", "bravo", "charlie"], items: [.app("charlie"), .app("alpha"), .app("bravo")]))
        var launched: [String] = []
        s.onLaunch = { id, _ in launched.append(id) }
        s.move(dx: 1, dy: 0)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 1, "alpha")
        s.update(snapshot: snapshot(["alpha", "bravo", "charlie"]))
        XCTAssertEqual(s.selection, 0, "alpha is first again")
        s.activate()
        XCTAssertEqual(launched, ["alpha"])
    }

    @MainActor func testAFolderLosingItsAppsUnderAnOpenCardKeepsTheCardOnTheOnesLeft() {
        let (id, item) = folder("F", ["bravo", "charlie", "delta"])
        let s = state(snapshot(["alpha", "bravo", "charlie", "delta"], items: [.app("alpha"), item]))
        s.open(folder: id)
        s.update(snapshot: snapshot(["alpha", "bravo", "charlie", "delta"], items: [.app("alpha"), .folder(.init(id: id, name: "F2", apps: ["bravo"]))]))
        XCTAssertEqual(s.openFolder, id)
        XCTAssertEqual(s.folderApps.map(\.id), ["bravo"])
        XCTAssertEqual(s.folderName, "F2")
        XCTAssertEqual(s.folderColumns, 1)
    }

    @MainActor func testAFolderOfOnlyHiddenOrMissingAppsIsNoTile() {
        let (_, item) = folder("F", ["ghost", "phantom"])
        let s = state(snapshot(["alpha"], items: [.app("alpha"), item, .app("nobody")]))
        XCTAssertEqual(s.pages.first?.map(\.id), ["alpha"])
    }

    @MainActor func testOpeningAFolderThatIsNotThereDoesNothing() {
        let s = state(snapshot(["alpha"]))
        s.open(folder: UUID())
        XCTAssertNil(s.openFolder)
        XCTAssertNil(s.selection)
    }

    @MainActor func testEveryAppHiddenIsSaidInWords() {
        let s = state(snapshot(["alpha", "bravo"], items: [], hidden: ["alpha", "bravo"]))
        XCTAssertNotEqual(s.mode, .grid, "a window of nothing and no word about why is a blank screen")
    }

    @MainActor func testTheFirstSnapshotIsReportedOnceEvenWhenItIsNotTheFirstUpdate() {
        let s = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1024, height: 640), topSafe: 0))
        var loaded = 0
        s.onLoaded = { _, _ in loaded += 1 }
        s.update(snapshot: nil)
        XCTAssertEqual(loaded, 0)
        s.update(snapshot: snapshot(["alpha"]))
        s.update(snapshot: snapshot(["alpha", "bravo"]))
        s.update(snapshot: nil)
        XCTAssertEqual(loaded, 1)
        XCTAssertEqual(s.mode, .busy)
    }

    @MainActor func testTurnAndGoClampAndDropAChoiceLeftOnAnotherPage() {
        let ids = (0..<40).map { "app\($0)" }
        let s = state(snapshot(ids))
        s.turn(-1)
        XCTAssertEqual(s.page, 0)
        s.turn(5)
        XCTAssertEqual(s.page, 2)
        s.go(to: -9)
        XCTAssertEqual(s.page, 0)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 0)
        s.turn(1)
        XCTAssertNil(s.selection, "the choice was on page 0")
        XCTAssertEqual(s.page, 1)
    }

    // MARK: - A precise device that sends no phases

    func testAPreciseDeviceThatSendsNoPhasesTurnsAgainOnItsNextSwipe() {
        // Some mice and third-party drivers send precise deltas with `phase` and `momentumPhase` both empty.
        var pager = LaunchpadScrollPager()
        XCTAssertEqual(pager.feed(dx: -50, dy: 0, precise: true, time: 0), 1)
        XCTAssertEqual(pager.feed(dx: -50, dy: 0, precise: true, time: 5), 1, "five seconds later, a second swipe")
    }
}
