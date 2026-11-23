import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// An open folder's card with pages: the arrow keys, the swipe, and what the page does when the folder, the grid or the search
/// changes under it. Sizes come from the card's own capacity.
extension LaunchpadScreenLogicTests {
    private var cpScreen: CGSize { CGSize(width: 1280, height: 800) }
    private var cpCapacity: Int { LaunchpadSurface.Card(geometry: .make(for: cpScreen, topSafe: 0), count: 10_000).capacity }

    /// A folder of `count` apps in front of `gridApps` more on the grid (more than a grid page when it is large enough).
    @MainActor private func cpState(folderApps count: Int, gridApps: Int = 0) -> (LaunchpadScreenState, UUID) {
        let id = UUID()
        let inside = (0..<count).map { "f\($0)" }, outside = (0..<gridApps).map { "g\($0)" }
        let layout = LaunchpadLayout(items: [.folder(.init(id: id, name: "F", apps: inside))] + outside.map { .app($0) })
        let all = inside + outside
        let apps = all.map { CatalogApp(id: $0, name: $0.capitalized, path: "/Applications/\($0).app") }
        let snap = LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: all, layout: layout,
                                     catalogComplete: true, layoutRead: .absent)
        let s = LaunchpadScreenState(geometry: .make(for: cpScreen, topSafe: 0))
        s.update(snapshot: snap)
        s.open(folder: id)
        return (s, id)
    }

    @MainActor func testTheArrowsCrossCardPagesRightAtTheLastSlotAndDownFromTheLastRow() {
        let cap = cpCapacity
        let (s, _) = cpState(folderApps: cap + 2)
        let columns = s.columns
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 0, "the first press chooses the first app")
        for _ in 1..<cap { s.move(dx: 1, dy: 0) }
        XCTAssertEqual(s.selection, cap - 1)
        XCTAssertEqual(s.cardPage, 0)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, cap, "Right at the last slot goes on to the next page's first")
        XCTAssertEqual(s.cardPage, 1)
        s.move(dx: -1, dy: 0)
        XCTAssertEqual(s.selection, cap - 1)
        XCTAssertEqual(s.cardPage, 0, "and back")
        s.move(dx: 0, dy: -1)
        s.move(dx: 0, dy: 1)
        XCTAssertEqual(s.cardPage, 0, "inside the page nothing turns")
        // Down from the last row: the same column on the next page, or its last app when that page is short.
        let (t, _) = cpState(folderApps: cap + 2)
        t.move(dx: 1, dy: 0)
        for _ in 0..<(cap - columns) { t.move(dx: 1, dy: 0) }
        XCTAssertEqual(t.selection, cap - columns, "the last row's first")
        t.move(dx: 0, dy: 1)
        XCTAssertEqual(t.cardPage, 1)
        XCTAssertEqual(t.selection, min(cap, cap + 1), "down lands in the next page's first row (short page: its last app at most)")
        t.move(dx: 0, dy: 1)
        t.move(dx: 1, dy: 0)
        t.move(dx: 1, dy: 0)
        XCTAssertEqual(t.selection, cap + 1, "the short last page's end holds")
        XCTAssertEqual(t.cardPage, 1)
    }

    @MainActor func testTheFirstPressAfterASwipeChoosesTheShownPagesFirstApp() {
        let cap = cpCapacity
        let (s, _) = cpState(folderApps: 2 * cap + 3)
        s.settle(step: 1, velocity: 0)
        s.settle(step: 1, velocity: 0)
        XCTAssertEqual(s.cardPage, 2)
        XCTAssertNil(s.selection)
        s.move(dx: 0, dy: 1)
        XCTAssertEqual(s.selection, 2 * cap, "not the folder's first app, the shown page's")
        XCTAssertEqual(s.cardPage, 2)
        let (t, _) = cpState(folderApps: 2 * cap + 3)
        t.go(to: 1)
        t.move(dx: -1, dy: 0)
        XCTAssertEqual(t.selection, cap)
    }

    @MainActor func testDragSettleTurnAndGoActOnTheCardAndLeaveTheGridsPageAndDragAlone() {
        let cap = cpCapacity
        let (s, _) = cpState(folderApps: 2 * cap + 3, gridApps: 3 * cpCapacity)
        XCTAssertGreaterThan(s.pageCount, 1, "the control: the grid has pages to leave alone")
        s.drag(raw: -80)
        XCTAssertLessThan(s.cardDrag.offset, 0)
        XCTAssertEqual(s.drag.offset, 0)
        s.settle(step: 1, velocity: -500)
        XCTAssertEqual(s.cardPage, 1)
        XCTAssertEqual(s.cardDrag.offset, 0)
        s.turn(1)
        XCTAssertEqual(s.cardPage, 2)
        s.turn(1)
        XCTAssertEqual(s.cardPage, 2, "past the last page nothing turns")
        s.go(to: -4)
        XCTAssertEqual(s.cardPage, 0)
        s.go(to: 99)
        XCTAssertEqual(s.cardPage, 2)
        XCTAssertEqual(s.page, 0)
        XCTAssertEqual(s.drag.offset, 0)
        s.drag(raw: 90)
        XCTAssertEqual(s.drag.offset, 0, "a rubber band on the card, none on the grid")
        s.settle(step: -1, velocity: 0)
        XCTAssertEqual(s.page, 0)
    }

    @MainActor func testTheCardsPageResetsOnOpenOnCloseAndOnSearch() {
        let cap = cpCapacity
        let (s, id) = cpState(folderApps: cap + 3)
        s.go(to: 1)
        XCTAssertEqual(s.cardPage, 1)
        s.open(folder: id)
        XCTAssertEqual(s.cardPage, 0, "opened again: the first page")
        s.go(to: 1)
        s.closeFolder()
        XCTAssertEqual(s.cardPage, 0, "closed")
        XCTAssertEqual(s.cardDrag.offset, 0)
        s.open(folder: id)
        s.go(to: 1)
        s.drag(raw: -30)
        s.search = "f1"
        XCTAssertNil(s.openFolder)
        XCTAssertEqual(s.cardPage, 0, "a search closes the card and its page")
        XCTAssertEqual(s.cardDrag.offset, 0)
    }

    @MainActor func testAFolderShrinkingToOnePageUnderTheCardOnPageTwoClampsAndNeverLeavesAnEmptyPage() {
        let cap = cpCapacity
        let (s, id) = cpState(folderApps: cap + 3)
        s.go(to: 1)
        let few = (0..<2).map { "f\($0)" }
        let apps = few.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }
        s.update(snapshot: LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: few,
                                             layout: LaunchpadLayout(items: [.folder(.init(id: id, name: "F", apps: few))]),
                                             catalogComplete: true, layoutRead: .absent))
        XCTAssertEqual(s.openFolder, id)
        XCTAssertEqual(s.folderApps.count, 2)
        XCTAssertEqual(s.cardPage, 0, "one page now: the page is clamped")
        XCTAssertEqual(s.cardEntries.count, 2)
        s.move(dx: 1, dy: 0)
        XCTAssertEqual(s.selection, 0)
    }

    @MainActor func testAFolderOfExactlyACapacityAndOneMoreAreOnePageAndTwo() {
        let cap = cpCapacity
        for (count, pages) in [(cap, 1), (cap + 1, 2), (cap - 1, 1)] {
            let (s, _) = cpState(folderApps: count)
            s.go(to: 5)
            XCTAssertEqual(s.cardPage, pages - 1, "\(count)")
            s.turn(1)
            XCTAssertEqual(s.cardPage, pages - 1, "\(count): the last page holds")
        }
    }

    @MainActor func testARegridKeepsTheCardOnTheSameAppsAndATinyGridMakesAOneColumnCard() {
        let cap = cpCapacity
        let (s, _) = cpState(folderApps: 3 * cap + 5)
        s.go(to: 2)
        let anchor = 2 * cap
        s.regrid(LaunchpadGridSettings(automatic: false, rows: 3, columns: 5, iconSize: 64))
        let card = LaunchpadSurface.Card(geometry: s.geometry, count: s.cardEntries.count, page: s.cardPage)
        XCTAssertNotEqual(card.capacity, cap, "the control: the page size changed")
        XCTAssertTrue(card.range(ofPage: s.cardPage).contains(anchor), "the page shown holds the app the old page began with")
        XCTAssertEqual(s.openFolder != nil, true)
        XCTAssertEqual(s.folderApps.count, 3 * cap + 5, "the same apps")
        let began = card.range(ofPage: s.cardPage).lowerBound
        s.regrid(LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 48))
        let narrow = LaunchpadSurface.Card(geometry: s.geometry, count: s.cardEntries.count, page: s.cardPage)
        XCTAssertGreaterThanOrEqual(narrow.columns, 1)
        XCTAssertLessThan(s.cardPage, narrow.pageCount)
        XCTAssertTrue(narrow.range(ofPage: s.cardPage).contains(began), "the page holds the app the shown page began with")
        s.move(dx: 1, dy: 0)
        s.move(dx: 0, dy: 1)
        XCTAssertLessThan(s.cardPage, narrow.pageCount)
    }

    /// The grid has three columns at least, so a card has two; one column is a folder of one app, which has no pages.
    @MainActor func testARegridToTheNarrowestGridMakesTheNarrowestPagedCardAndHoldsTogether() {
        let (s, _) = cpState(folderApps: 40)
        s.go(to: 1)
        s.regrid(LaunchpadGridSettings(automatic: false, rows: 8, columns: 2, iconSize: 48))
        XCTAssertEqual(s.geometry.columns, 3, "the control: the settings reached the geometry, three columns at least")
        let card = LaunchpadSurface.Card(geometry: s.geometry, count: s.cardEntries.count, page: s.cardPage)
        XCTAssertEqual(card.columns, 2)
        XCTAssertEqual(LaunchpadSurface.Card(geometry: s.geometry, count: 1).columns, 1, "the one-column card is one app")
        XCTAssertEqual(card.capacity, 2 * card.visibleRows)
        XCTAssertLessThan(s.cardPage, card.pageCount)
        s.move(dx: 0, dy: 1)
        s.move(dx: 1, dy: 0)
        XCTAssertLessThan(s.cardPage, card.pageCount)
    }
}
