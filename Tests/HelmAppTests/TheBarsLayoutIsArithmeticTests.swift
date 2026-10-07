import CoreGraphics
import XCTest
@testable import HelmApp

/// **`ShellBarLayout` is the bar's arithmetic and nothing else: from the widths of
/// the name, the tabs, the page's actions, the search and the status, the bar's own
/// width, where the card sits in the window and where the window's buttons end, it
/// answers one frame per zone and two verdicts, whether the tabs are folded to one
/// item and whether the search is folded to its magnifier.**
///
/// No window, no screen, no view: the function takes numbers and returns numbers,
/// and this class is deliberately not `@MainActor`, so an isolated function would
/// not compile here.
///
/// What is an input and what is arithmetic. "Homebrew" below is a page's worth of
/// natural widths fed in as numbers: a name 130 wide, tabs 310 wide unfolded and
/// 136 folded, an actions capsule reserving 72, a search field. No test here
/// measures a view; the widths are assumptions these tests feed, and every
/// expected frame is arithmetic on them. The window of 1060 is the Settings
/// window's default width and the card's minX of 200 is the default sidebar; the
/// buttons' rect (19, 19, 60, 14) in the window stands for where the system puts the three
/// window buttons, the 14-point button size an assumption, as an input. A frame is written `minX…maxX` in the bar's own
/// coordinates, whose x 0 is the card's minX in the window.
///
/// Every number the rows expect was recomputed from the rules: the
/// tabs' centre is the window's centre (window width / 2 less the card's minX), the
/// trailing chain is counted from the bar's right edge, 8 in, or 4 before a status, and each verdict is a
/// threshold in the width that is crossed once along a sweep.
final class TheBarsLayoutIsArithmeticTests: XCTestCase {

    // MARK: - inputs

    private typealias Input = ShellBarLayout.Input
    private typealias Frames = ShellBarLayout.Frames

    private static let nan = CGFloat.nan
    private static let inf = CGFloat.infinity
    private static let huge = CGFloat.greatestFiniteMagnitude

    /// Every kind of number a width or an offset could arrive as.
    private static let awkward: [CGFloat] = [
        0, -1, -200, 1, 3.5, nan, inf, -inf, huge, -huge, .leastNonzeroMagnitude,
    ]

    /// The window buttons' union, x 19...79 in the window moved into the bar's coordinates, y left as the window's; the 14-point button size is an assumption.
    private static func windowButtons(cardMinX: CGFloat) -> CGRect {
        CGRect(x: 19 - cardMinX, y: 19, width: 60, height: 14)
    }

    /// A page with a name, tabs, an actions capsule and a search; every default is
    /// the page's natural width, every override is what a row varies.
    private static func homebrew(
        bar: CGFloat, cardMinX: CGFloat = 200, window: CGFloat,
        name: CGFloat = 130, tabs: CGFloat = 310, folded: CGFloat = 136,
        actions: CGFloat = 72, status: CGFloat = 0,
        search: Bool = true, resting: Bool = false, inUse: Bool = false,
        buttons: CGRect = .zero
    ) -> Input {
        Input(barWidth: bar, cardMinX: cardMinX, windowWidth: window, nameWidth: name,
              tabsWidth: tabs, tabsFoldedWidth: folded, actionsWidth: actions,
              statusWidth: status, hasSearch: search, alwaysCollapseSearch: resting,
              searchInUse: inUse, buttons: buttons)
    }

    private static func isFiniteRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }

    // MARK: - reading a frame

    /// A zone's frame is non-empty: it was given a place.
    private func assertAnswered(_ zone: String, _ frame: CGRect, line: UInt = #line) {
        XCTAssertFalse(frame.isEmpty || frame.isNull || frame == .zero,
                       "the layout answered no frame for the \(zone): every comparison below would have compared nothing",
                       line: line)
    }

    private func assertSpan(_ zone: String, _ frame: CGRect, _ minX: CGFloat, _ maxX: CGFloat,
                            line: UInt = #line) {
        XCTAssertEqual(frame.minX, minX, "\(zone) starts at", line: line)
        XCTAssertEqual(frame.maxX, maxX, "\(zone) ends at", line: line)
    }

    /// Every present zone stands on the bar's row: 8 down, 36 high.
    private func assertOnTheRow(_ zone: String, _ frame: CGRect, line: UInt = #line) {
        XCTAssertEqual(frame.minY, 8, "\(zone) row start", line: line)
        XCTAssertEqual(frame.height, 36, "\(zone) row height", line: line)
    }

    // MARK: - the zones at the default width

    func testTheBarIs52HighAndTheDefaultRowStandsInsideItsHeight() {
        XCTAssertEqual(ShellBarLayout.height, 52)
        XCTAssertEqual(ShellBarLayout.controlTop + ShellBarLayout.controlHeight + ShellBarLayout.controlBottom,
                       ShellBarLayout.height)

        let f = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, buttons: Self.windowButtons(cardMinX: 200)))
        let zones = [("name", f.name), ("tabs", f.tabs), ("actions", f.actions), ("search", f.search)]
        for (zone, frame) in zones { assertAnswered(zone, frame) }
        for (zone, frame) in zones {
            XCTAssertGreaterThanOrEqual(frame.minY, 0, "\(zone) starts above the bar's top")
            XCTAssertLessThanOrEqual(frame.maxY, ShellBarLayout.height, "\(zone) ends below the bar's bottom")
        }
    }

    func testAt1060NothingFoldsAndEveryZoneStandsWhereTheRulesPutIt() {
        let f = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, buttons: Self.windowButtons(cardMinX: 200)))

        // The subject happened: every zone was given a frame.
        assertAnswered("name", f.name)
        assertAnswered("tabs", f.tabs)
        assertAnswered("actions", f.actions)
        assertAnswered("search", f.search)

        assertSpan("name", f.name, 16, 146)
        assertSpan("tabs", f.tabs, 175, 485)
        XCTAssertEqual(f.tabs.midX + 200, 530, "the tabs' centre is the window's centre, 1060 / 2")
        assertSpan("actions", f.actions, 489, 561)
        assertSpan("search", f.search, 565, 848)
        XCTAssertEqual(f.search.width, 283)
        XCTAssertEqual(856 - f.search.maxX, 8, "the search ends 8 from the bar's right edge")
        XCTAssertEqual(f.search.minX - f.actions.maxX, 4, "the actions end 4 before the search")
        for (zone, frame) in [("name", f.name), ("tabs", f.tabs), ("actions", f.actions), ("search", f.search)] {
            assertOnTheRow(zone, frame)
        }
        XCTAssertFalse(f.tabsFolded)
        XCTAssertFalse(f.searchFolded)
        XCTAssertTrue(f.fits)
    }

    func testATabScopedActionMovesNeitherTheTabsNorTheSearch() {
        let buttons = Self.windowButtons(cardMinX: 200)
        let wide = ShellBarLayout.frames(for: Self.homebrew(bar: 856, window: 1060, buttons: buttons))
        let narrow = ShellBarLayout.frames(for: Self.homebrew(bar: 856, window: 1060, actions: 36, buttons: buttons))

        assertAnswered("actions with a tab-scoped capsule", narrow.actions)
        assertAnswered("tabs", narrow.tabs)
        assertSpan("actions", narrow.actions, 525, 561)
        XCTAssertEqual(narrow.tabs, wide.tabs, "the tabs did not move when the capsule shrank")
        XCTAssertEqual(narrow.search, wide.search, "the search did not move when the capsule shrank")
        XCTAssertEqual(narrow.name, wide.name)
    }

    func testTheLastGroupEndsEightFromTheEdgeWithAndWithoutSearch() {
        let buttons = Self.windowButtons(cardMinX: 200)
        let with = ShellBarLayout.frames(for: Self.homebrew(bar: 856, window: 1060, buttons: buttons))
        let without = ShellBarLayout.frames(for: Self.homebrew(bar: 856, window: 1060, search: false, buttons: buttons))

        assertAnswered("actions", without.actions)
        assertAnswered("tabs", without.tabs)
        assertSpan("actions", without.actions, 776, 848)
        assertSpan("tabs", without.tabs, 175, 485)
        XCTAssertEqual(without.actions.maxX, with.search.maxX, "both groups end where the search ended")
        XCTAssertEqual(without.search, .zero, "no search is no frame")
        XCTAssertFalse(without.searchFolded)
    }

    // MARK: - the tabs clamp, they do not centre

    func testAtTheFloorTheTabsClampAgainstTheNameAndDoNotCentre() {
        let f = ShellBarLayout.frames(for: Self.homebrew(bar: 656, window: 860, search: false))

        assertAnswered("tabs", f.tabs)
        assertAnswered("actions", f.actions)
        assertSpan("tabs", f.tabs, 154, 464)
        XCTAssertNotEqual(f.tabs.minX, 75, "centred on the window the tabs would start at 75, left of the name's end")
        XCTAssertEqual(f.name.maxX + 8, 154, "the tabs start one name gap after the name")
        assertSpan("actions", f.actions, 576, 648)
        XCTAssertFalse(f.tabsFolded, "310 of tabs still fit here")
        XCTAssertTrue(f.fits)
    }

    // MARK: - the order things give way in

    func testTheTabsFoldBeforeTheSearchShrinksBelowItsFloor() {
        let f = ShellBarLayout.frames(for: Self.homebrew(bar: 656, window: 860))

        assertAnswered("tabs", f.tabs)
        assertAnswered("search", f.search)
        XCTAssertTrue(f.tabsFolded, "the tabs fold first")
        XCTAssertFalse(f.searchFolded, "the search is still a field")
        assertSpan("tabs", f.tabs, 162, 298)
        assertSpan("actions", f.actions, 302, 374)
        assertSpan("search", f.search, 378, 648)
        XCTAssertEqual(f.search.width, 270, "the search gave way from 283 to keep the tabs centred")
        XCTAssertTrue(f.fits)
    }

    func testTheFoldIsOneThresholdInTheWidthAndTheSearchIsAtItsFloorThere() {
        let at876 = ShellBarLayout.frames(for: Self.homebrew(bar: 672, window: 876))
        assertAnswered("tabs", at876.tabs)
        assertAnswered("search", at876.search)
        XCTAssertFalse(at876.tabsFolded)
        XCTAssertFalse(at876.searchFolded)
        assertSpan("tabs", at876.tabs, 154, 464)
        assertSpan("search", at876.search, 544, 664)
        XCTAssertEqual(at876.search.width, 120, "exactly the floor: one point less does not fit")

        let at875 = ShellBarLayout.frames(for: Self.homebrew(bar: 671, window: 875))
        assertAnswered("tabs", at875.tabs)
        XCTAssertTrue(at875.tabsFolded)
        XCTAssertFalse(at875.searchFolded)
        assertSpan("tabs", at875.tabs, 169.5, 305.5)
        assertSpan("search", at875.search, 385.5, 663)
        XCTAssertEqual(at875.search.width, 277.5)
    }

    func testTheSearchFoldsToItsMagnifierBeforeAnythingIsClipped() {
        let f = ShellBarLayout.frames(for: Self.homebrew(bar: 536, cardMinX: 320, window: 860, name: 200))

        assertAnswered("name", f.name)
        assertAnswered("tabs", f.tabs)
        assertAnswered("actions", f.actions)
        assertAnswered("search", f.search)
        XCTAssertTrue(f.tabsFolded)
        XCTAssertTrue(f.searchFolded)
        assertSpan("name", f.name, 16, 216)
        XCTAssertEqual(f.name.width, 200, "the name is whole: the search gave way, not the name")
        assertSpan("tabs", f.tabs, 224, 360)
        assertSpan("actions", f.actions, 416, 488)
        assertSpan("search", f.search, 492, 528)
        XCTAssertEqual(f.search.width, 36, "the magnifier")
        XCTAssertTrue(f.fits)
    }

    func testASearchInUseIsNeverFoldedForRoom() {
        let f = ShellBarLayout.frames(for: Self.homebrew(
            bar: 536, cardMinX: 320, window: 860, name: 200, inUse: true))

        assertAnswered("search", f.search)
        assertAnswered("name", f.name)
        XCTAssertFalse(f.searchFolded, "text in the field, or the field being edited, keeps it open")
        XCTAssertTrue(f.tabsFolded)
        assertSpan("search", f.search, 408, 528)
        XCTAssertEqual(f.search.width, 120)
        assertSpan("actions", f.actions, 332, 404)
        assertSpan("tabs", f.tabs, 192, 328)
        assertSpan("name", f.name, 16, 184)
        XCTAssertEqual(200 - f.name.width, 32, "the name gave up 32: the open field takes 84 more than the magnifier and 52 stood free")
        XCTAssertTrue(f.fits)
    }

    func testTheNameIsTheOnlyZoneThatTruncatesAndOnlyAfterBothFolds() {
        let f = ShellBarLayout.frames(for: Self.homebrew(bar: 536, cardMinX: 320, window: 860, name: 300))

        assertAnswered("name", f.name)
        assertAnswered("tabs", f.tabs)
        assertAnswered("actions", f.actions)
        assertAnswered("search", f.search)
        XCTAssertTrue(f.tabsFolded)
        XCTAssertTrue(f.searchFolded)
        assertSpan("name", f.name, 16, 268)
        XCTAssertEqual(300 - f.name.width, 48, "the name was cut by 48")
        assertSpan("tabs", f.tabs, 276, 412)
        XCTAssertEqual(f.tabs.width, 136, "the tabs kept their folded width")
        assertSpan("actions", f.actions, 416, 488)
        XCTAssertEqual(f.actions.width, 72, "the actions kept their reserved width")
        assertSpan("search", f.search, 492, 528)
        XCTAssertEqual(f.search.width, 36, "the magnifier kept its width")
        XCTAssertLessThan(f.name.maxX, f.tabs.minX, "the name and the tabs do not meet")
        XCTAssertLessThan(f.tabs.maxX, f.actions.minX, "the tabs and the actions do not meet")
        XCTAssertLessThan(f.actions.maxX, f.search.minX, "the actions and the search do not meet")
        XCTAssertTrue(f.fits)
    }

    func testWhenEvenAZeroWidthNameLeavesNoRoomTheNameKeepsItsPlaceAndFitsIsFalse() {
        let f = ShellBarLayout.frames(for: Self.homebrew(bar: 250, cardMinX: 320, window: 574, name: 300))

        assertAnswered("tabs", f.tabs)
        assertAnswered("actions", f.actions)
        assertAnswered("search", f.search)
        XCTAssertEqual(f.name.minX, 16, "a present name with no room stays at its start")
        XCTAssertEqual(f.name.width, 0)
        XCTAssertNotEqual(f.name, .zero, "a name of width 0 is not an absent name")
        XCTAssertEqual(f.name.minY, 8, "it keeps its row")
        assertSpan("tabs", f.tabs, -10, 126)
        assertSpan("actions", f.actions, 130, 202)
        assertSpan("search", f.search, 206, 242)
        XCTAssertEqual(f.search.width, 36)
        XCTAssertTrue(f.tabsFolded)
        XCTAssertTrue(f.searchFolded)
        XCTAssertFalse(f.fits, "the tabs start left of where the name would end: nothing fits")
    }

    // MARK: - the window's buttons

    func testTheNameStartsRightOfTheWindowButtonsWhenTheyAreOverTheCard() {
        let rail = ShellBarLayout.frames(for: Self.homebrew(
            bar: 1000, cardMinX: 56, window: 1060, buttons: CGRect(x: -37, y: 15, width: 60, height: 14)))

        assertAnswered("name", rail.name)
        assertAnswered("tabs", rail.tabs)
        assertAnswered("actions", rail.actions)
        assertAnswered("search", rail.search)
        assertSpan("name", rail.name, 31, 161)
        XCTAssertEqual(rail.name.minX, 23 + 8, "the buttons end at 23 and the name stands 8 clear")
        assertSpan("tabs", rail.tabs, 319, 629)
        assertSpan("actions", rail.actions, 633, 705)
        assertSpan("search", rail.search, 709, 992)

        // The same buttons beside the default sidebar end at -121 in the bar, left of it, and leave the name alone.
        let sidebar = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, cardMinX: 200, window: 1060, buttons: Self.windowButtons(cardMinX: 200)))
        assertAnswered("name", sidebar.name)
        XCTAssertEqual(sidebar.name.minX, 16, "buttons that end left of the bar leave the name at its own start")
    }

    func testARectThatIsNotAPlaceIsNoObstacleAndTheRowItStandsOnDoesNotMatter() {
        let reference = ShellBarLayout.frames(for: Self.homebrew(bar: 856, window: 1060)).name
        assertAnswered("name", reference)
        XCTAssertEqual(reference.minX, 16, "no buttons: the name starts at its own 16")

        let notPlaces: [CGRect] = [
            .zero, .null, .infinite,
            CGRect(x: Self.nan, y: 19, width: 60, height: 14),
            CGRect(x: 100, y: 19, width: Self.nan, height: 14),
            CGRect(x: Self.inf, y: 19, width: 60, height: 14),
            CGRect(x: 100, y: 19, width: 0, height: 14),
            CGRect(x: 100, y: 19, width: 60, height: 0),
        ]
        for rect in notPlaces {
            XCTAssertEqual(ShellBarLayout.frames(for: Self.homebrew(bar: 856, window: 1060, buttons: rect)).name,
                           reference, "buttons \(rect) are not an obstacle")
        }
        XCTAssertEqual(notPlaces.count, 8, "every shape was fed in")

        // A real obstacle, then the same one on another row: only the x counts.
        let high = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, buttons: CGRect(x: 40, y: 2, width: 60, height: 14))).name
        let low = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, buttons: CGRect(x: 40, y: 700, width: 60, height: 14))).name
        XCTAssertEqual(high.minX, 108, "the buttons end at 100 and the name stands 8 clear")
        XCTAssertEqual(low.minX, 108, "the buttons' row is ignored")

        // Buttons that end before the name's own start clear it: 16 wins over 0 + 8.
        let near = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, buttons: CGRect(x: -60, y: 19, width: 60, height: 14))).name
        XCTAssertEqual(near.minX, 16, "the name starts at the later of 16 and the buttons' end plus 8")
    }

    // MARK: - the status

    func testAStatusAloneStandsAtTheRightEdgeBesideTheName() {
        let f = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, name: 130, tabs: 0, folded: 0, actions: 0, status: 70, search: false))

        // The subject happened: both zones that exist were given a frame.
        assertAnswered("name", f.name)
        assertAnswered("status", f.status)

        assertSpan("status", f.status, 786, 856)
        assertSpan("name", f.name, 16, 146)
        assertOnTheRow("status", f.status)
        XCTAssertEqual(f.tabs, .zero, "no tabs, no frame")
        XCTAssertEqual(f.actions, .zero, "no actions, no frame")
        XCTAssertEqual(f.search, .zero, "no search, no frame")
        XCTAssertFalse(f.tabsFolded)
        XCTAssertFalse(f.searchFolded)
        XCTAssertTrue(f.fits)
    }

    // MARK: - the setting that keeps the search at rest

    func testASearchThatRestsIsAMagnifierUntilItIsUsedAndThenReturnsToRest() {
        let atFloor = Self.homebrew(bar: 656, window: 860, resting: true)
        let resting = ShellBarLayout.frames(for: atFloor)

        assertAnswered("tabs", resting.tabs)
        assertAnswered("actions", resting.actions)
        assertAnswered("search", resting.search)
        XCTAssertFalse(resting.tabsFolded, "the freed room keeps the tabs open")
        XCTAssertTrue(resting.searchFolded)
        assertSpan("tabs", resting.tabs, 154, 464)
        assertSpan("actions", resting.actions, 536, 608)
        assertSpan("search", resting.search, 612, 648)

        var used = atFloor
        used.searchInUse = true
        let open = ShellBarLayout.frames(for: used)
        let notResting = ShellBarLayout.frames(for: Self.homebrew(bar: 656, window: 860))
        assertAnswered("search", open.search)
        XCTAssertFalse(open.searchFolded)
        XCTAssertEqual(open, notResting, "a search in use is the search of a bar whose search never rests")
        XCTAssertTrue(open.tabsFolded)
        assertSpan("search", open.search, 378, 648)

        XCTAssertEqual(ShellBarLayout.frames(for: atFloor), resting, "resting again equals the first rest")

        let wide = ShellBarLayout.frames(for: Self.homebrew(
            bar: 856, window: 1060, resting: true, buttons: Self.windowButtons(cardMinX: 200)))
        assertAnswered("search", wide.search)
        XCTAssertTrue(wide.searchFolded, "a resting search is a magnifier whatever the room")
        assertSpan("search", wide.search, 812, 848)
        assertSpan("actions", wide.actions, 736, 808)
        assertSpan("tabs", wide.tabs, 175, 485)
    }

    // MARK: - one threshold per verdict

    func testAcrossAOnePointSweepEachVerdictChangesExactlyOnce() {
        var rows: [(window: CGFloat, nameCut: Bool, searchFolded: Bool, tabsFolded: Bool)] = []
        for window in stride(from: CGFloat(500), through: 1100, by: 1) {
            let f = ShellBarLayout.frames(for: Self.homebrew(bar: window - 204, window: window))
            assertAnswered("name", f.name)
            rows.append((window, f.name.width < 130, f.searchFolded, f.tabsFolded))
        }
        XCTAssertEqual(rows.count, 601, "every width was swept")

        func changes(_ verdict: ((window: CGFloat, nameCut: Bool, searchFolded: Bool, tabsFolded: Bool)) -> Bool)
            -> (count: Int, firstAfter: CGFloat?)
        {
            var count = 0
            var first: CGFloat?
            for (before, after) in zip(rows, rows.dropFirst()) where verdict(before) != verdict(after) {
                count += 1
                first = first ?? after.window
            }
            return (count, first)
        }
        let cut = changes { $0.nameCut }
        let search = changes { $0.searchFolded }
        let tabs = changes { $0.tabsFolded }

        // A verdict that never changes is as wrong as one that flaps.
        XCTAssertEqual(cut.count, 1, "the name's truncation changed \(cut.count) times along the sweep")
        XCTAssertEqual(search.count, 1, "the search's fold changed \(search.count) times along the sweep")
        XCTAssertEqual(tabs.count, 1, "the tabs' fold changed \(tabs.count) times along the sweep")
        XCTAssertEqual(cut.firstAfter, 618, "the name is whole from a window of 618")
        XCTAssertEqual(search.firstAfter, 702, "the search is a field from a window of 702")
        XCTAssertEqual(tabs.firstAfter, 876, "the tabs are open from a window of 876")

        // The order they give way in, narrow to wide: all three, then tabs and
        // search, then tabs alone, then nothing.
        let first = rows[0], last = rows[rows.count - 1]
        XCTAssertTrue(first.nameCut && first.searchFolded && first.tabsFolded, "at 500 everything has given way")
        XCTAssertFalse(last.nameCut || last.searchFolded || last.tabsFolded, "at 1100 nothing has")
        for row in rows {
            XCTAssertTrue(!row.searchFolded || row.tabsFolded, "the search folded while the tabs were open at \(row.window)")
            XCTAssertTrue(!row.nameCut || row.searchFolded, "the name was cut while the search was a field at \(row.window)")
        }
    }

    func testWithoutASearchTheTabsUnfoldAsSoonAsTheyFitWithNoMargin() {
        var verdicts: [(window: CGFloat, folded: Bool)] = []
        for window in stride(from: CGFloat(860), through: 900, by: 1) {
            let f = ShellBarLayout.frames(for: Self.homebrew(
                bar: window - 324, cardMinX: 320, window: window, search: false))
            assertAnswered("tabs", f.tabs)
            verdicts.append((window, f.tabsFolded))
        }
        XCTAssertEqual(verdicts.count, 41, "every width was swept")

        let changed = zip(verdicts, verdicts.dropFirst()).filter { $0.folded != $1.folded }
        XCTAssertEqual(changed.count, 1, "the tabs' fold changed \(changed.count) times along the sweep")
        XCTAssertEqual(verdicts.first { $0.window == 871 }?.folded, true, "folded up to 871")
        XCTAssertEqual(verdicts.first { $0.window == 872 }?.folded, false, "unfolded from 872")
        XCTAssertEqual(verdicts.first?.folded, true)
        XCTAssertEqual(verdicts.last?.folded, false)
    }

    // MARK: - what a bad number reads as

    func testNoInputOfAnyKindMakesAFrameThatIsNotANumber() {
        let base = Self.homebrew(bar: 856, window: 1060, status: 70,
                                 buttons: Self.windowButtons(cardMinX: 200))
        let reference = ShellBarLayout.frames(for: base)
        assertAnswered("name", reference.name)
        assertAnswered("tabs", reference.tabs)
        assertAnswered("status", reference.status)

        var tried = 0
        func check(_ input: Input, _ label: String) {
            let f = ShellBarLayout.frames(for: input)
            tried += 1
            for (zone, frame) in [("name", f.name), ("tabs", f.tabs), ("actions", f.actions),
                                  ("search", f.search), ("status", f.status)] {
                XCTAssertTrue(Self.isFiniteRect(frame), "\(label): \(zone) is \(frame)")
            }
        }

        for value in Self.awkward {
            let fields: [(String, WritableKeyPath<Input, CGFloat>)] = [
                ("barWidth", \.barWidth), ("cardMinX", \.cardMinX), ("windowWidth", \.windowWidth),
                ("nameWidth", \.nameWidth), ("tabsWidth", \.tabsWidth),
                ("tabsFoldedWidth", \.tabsFoldedWidth), ("actionsWidth", \.actionsWidth),
                ("statusWidth", \.statusWidth),
            ]
            for (field, path) in fields {
                var input = base
                input[keyPath: path] = value
                check(input, "\(field) \(value)")
            }
            let rects: [(String, CGRect)] = [
                ("buttons x", CGRect(x: value, y: 19, width: 60, height: 14)),
                ("buttons y", CGRect(x: 19, y: value, width: 60, height: 14)),
                ("buttons width", CGRect(x: 19, y: 19, width: value, height: 14)),
                ("buttons height", CGRect(x: 19, y: 19, width: 60, height: value)),
            ]
            for (field, rect) in rects {
                var input = base
                input.buttons = rect
                check(input, "\(field) \(value)")
            }
        }
        XCTAssertEqual(tried, Self.awkward.count * 12, "every field was fed every awkward number in turn")

        // Every switch with every extreme at once.
        for search in [false, true] {
            for resting in [false, true] {
                for inUse in [false, true] {
                    for value in [Self.nan, Self.inf, -Self.inf, Self.huge, -Self.huge] {
                        var input = Input(barWidth: value, cardMinX: value, windowWidth: value, nameWidth: value,
                                          tabsWidth: value, tabsFoldedWidth: value, actionsWidth: value,
                                          statusWidth: value, hasSearch: search, alwaysCollapseSearch: resting,
                                          searchInUse: inUse, buttons: .infinite)
                        check(input, "all fields \(value), search \(search), resting \(resting), in use \(inUse)")
                        input.buttons = CGRect(x: value, y: value, width: value, height: value)
                        check(input, "all fields and buttons \(value)")
                    }
                }
            }
        }
        XCTAssertEqual(tried, Self.awkward.count * 12 + 8 * 5 * 2)
    }

    /// How many zones were given a frame.
    private func present(_ f: Frames) -> Int {
        [f.name, f.tabs, f.actions, f.search, f.status].filter { $0 != .zero }.count
    }

    func testANumberThatIsNotANumberReadsAsZeroAndOneBeyondTheCeilingReadsAsTheCeiling() {
        let ceiling: CGFloat = 1_000_000
        let base = Self.homebrew(bar: 856, window: 1060, status: 70,
                                 buttons: Self.windowButtons(cardMinX: 200))
        XCTAssertGreaterThan(present(ShellBarLayout.frames(for: base)), 3, "the base page was laid out")

        let fields: [(String, WritableKeyPath<Input, CGFloat>)] = [
            ("barWidth", \.barWidth), ("windowWidth", \.windowWidth), ("nameWidth", \.nameWidth),
            ("tabsWidth", \.tabsWidth), ("tabsFoldedWidth", \.tabsFoldedWidth),
            ("actionsWidth", \.actionsWidth), ("statusWidth", \.statusWidth),
        ]
        var differing = 0
        var compared = 0
        func frames(_ path: WritableKeyPath<Input, CGFloat>, _ value: CGFloat) -> Frames {
            var input = base
            input[keyPath: path] = value
            return ShellBarLayout.frames(for: input)
        }
        for (field, path) in fields {
            let atZero = frames(path, 0)
            let atCeiling = frames(path, ceiling)
            XCTAssertGreaterThan(present(atZero), 0, "\(field) 0: nothing was laid out")
            XCTAssertGreaterThan(present(atCeiling), 0, "\(field) at the ceiling: nothing was laid out")
            if atZero != atCeiling { differing += 1 }
            for value in [Self.nan, -1, -Self.inf, -Self.huge] {
                XCTAssertEqual(frames(path, value), atZero, "\(field) \(value) reads as 0")
                compared += 1
            }
            for value in [ceiling + 1, 2 * ceiling, Self.inf, Self.huge] {
                XCTAssertEqual(frames(path, value), atCeiling, "\(field) \(value) reads as the ceiling")
                compared += 1
            }
        }
        XCTAssertEqual(compared, fields.count * 8, "every width was fed every kind")
        XCTAssertEqual(differing, 6, "the ceiling and zero differ for every width but the folded one, which a fitting bar never reads")

        // The card's offset is bounded on both sides, and not a number reads 0.
        func atCard(_ value: CGFloat) -> Frames {
            var input = base
            input.cardMinX = value
            return ShellBarLayout.frames(for: input)
        }
        XCTAssertGreaterThan(present(atCard(0)), 3)
        XCTAssertNotEqual(atCard(ceiling), atCard(0), "the ceiling is a place of its own")
        XCTAssertEqual(atCard(Self.nan), atCard(0), "an offset that is not a number reads 0")
        XCTAssertEqual(atCard(ceiling + 1), atCard(ceiling))
        XCTAssertEqual(atCard(Self.inf), atCard(ceiling))
        XCTAssertEqual(atCard(-ceiling - 1), atCard(-ceiling))
        XCTAssertEqual(atCard(-Self.inf), atCard(-ceiling))

        // Buttons that end past the ceiling are read as ending at it.
        func nameStart(_ rect: CGRect) -> CGFloat {
            var input = base
            input.buttons = rect
            return ShellBarLayout.frames(for: input).name.minX
        }
        XCTAssertEqual(nameStart(CGRect(x: ceiling - 60, y: 19, width: 60, height: 14)), ceiling + 8)
        XCTAssertEqual(nameStart(CGRect(x: 5 * ceiling, y: 19, width: 60, height: 14)), ceiling + 8,
                       "buttons beyond the ceiling end at the ceiling")
        XCTAssertEqual(nameStart(CGRect(x: -5 * ceiling, y: 19, width: 60, height: 14)), 16,
                       "buttons far to the left leave the name at its own start")
    }

    func testWithNoTabsFitsIsWhetherTheNameCouldStandAtItsStart() {
        func name(_ bar: CGFloat) -> Frames {
            ShellBarLayout.frames(for: Self.homebrew(
                bar: bar, window: bar + 204, name: 100, tabs: 0, folded: 0, actions: 0, search: false))
        }
        let at23 = name(23)
        XCTAssertNotEqual(at23.name, .zero, "a present name keeps its frame")
        XCTAssertEqual(at23.name.minX, 16)
        XCTAssertEqual(at23.name.width, 0)
        XCTAssertFalse(at23.fits, "the chain ends at 15, left of where the name starts")

        let at24 = name(24)
        XCTAssertNotEqual(at24.name, .zero)
        XCTAssertEqual(at24.name.width, 0)
        XCTAssertTrue(at24.fits, "the chain ends at 16, exactly where the name starts")

        assertSpan("name", name(123).name, 16, 115)
        XCTAssertTrue(name(123).fits)
        assertSpan("name", name(124).name, 16, 116)
        XCTAssertTrue(name(124).fits)

        // With a search and actions to its right and no room at all.
        let none = ShellBarLayout.frames(for: Self.homebrew(
            bar: 100, window: 304, name: 100, tabs: 0, folded: 0))
        XCTAssertNotEqual(none.name, .zero)
        XCTAssertEqual(none.name.minX, 16)
        XCTAssertEqual(none.name.width, 0)
        assertSpan("search", none.search, 56, 92)
        assertSpan("actions", none.actions, -20, 52)
        XCTAssertTrue(none.searchFolded)
        XCTAssertFalse(none.fits)
    }

    func testWithNoTabsASearchOutOfRoomFoldsToSpareTheName() {
        let narrow = ShellBarLayout.frames(for: Self.homebrew(
            bar: 300, window: 504, name: 100, tabs: 0, folded: 0))
        assertAnswered("name", narrow.name)
        assertAnswered("search", narrow.search)
        XCTAssertTrue(narrow.searchFolded, "the open field would have cost the name 24")
        XCTAssertFalse(narrow.tabsFolded)
        assertSpan("name", narrow.name, 16, 116)
        assertSpan("search", narrow.search, 256, 292)
        assertSpan("actions", narrow.actions, 180, 252)
        XCTAssertEqual(narrow.tabs, .zero)
        XCTAssertTrue(narrow.fits)

        let used = ShellBarLayout.frames(for: Self.homebrew(
            bar: 300, window: 504, name: 100, tabs: 0, folded: 0, inUse: true))
        assertAnswered("search", used.search)
        XCTAssertFalse(used.searchFolded, "a search in use is never folded for room")
        assertSpan("name", used.name, 16, 92)
        assertSpan("search", used.search, 172, 292)
        assertSpan("actions", used.actions, 96, 168)
        XCTAssertTrue(used.fits)

        let wide = ShellBarLayout.frames(for: Self.homebrew(
            bar: 500, window: 704, name: 100, tabs: 0, folded: 0))
        assertAnswered("search", wide.search)
        XCTAssertFalse(wide.searchFolded, "with room the field stays open")
        assertSpan("name", wide.name, 16, 116)
        assertSpan("search", wide.search, 209, 492)
        assertSpan("actions", wide.actions, 133, 205)
        XCTAssertTrue(wide.fits)
    }

    func testTabsAloneStandCentredAndThenAgainstTheRightEdge() {
        func page(_ bar: CGFloat) -> Frames {
            ShellBarLayout.frames(for: Self.homebrew(
                bar: bar, window: 1060, actions: 0, search: false,
                buttons: Self.windowButtons(cardMinX: 200)))
        }
        let wide = page(856)
        assertAnswered("name", wide.name)
        assertAnswered("tabs", wide.tabs)
        assertSpan("name", wide.name, 16, 146)
        assertSpan("tabs", wide.tabs, 175, 485)
        XCTAssertEqual(wide.actions, .zero)
        XCTAssertEqual(wide.search, .zero)
        XCTAssertEqual(wide.status, .zero)
        XCTAssertFalse(wide.tabsFolded)
        XCTAssertTrue(wide.fits)

        let edge = page(472)
        assertAnswered("tabs", edge.tabs)
        assertSpan("name", edge.name, 16, 146)
        assertSpan("tabs", edge.tabs, 154, 464)
        XCTAssertFalse(edge.tabsFolded, "464 is exactly the room")
        XCTAssertTrue(edge.fits)

        let folded = page(471)
        assertAnswered("tabs", folded.tabs)
        XCTAssertTrue(folded.tabsFolded)
        assertSpan("name", folded.name, 16, 146)
        assertSpan("tabs", folded.tabs, 262, 398)
        XCTAssertTrue(folded.fits)
    }

    func testTabsThatCannotFoldNeverFoldWhateverTheBarOverflowsBy() {
        func page(folded: CGFloat, search: Bool) -> Frames {
            ShellBarLayout.frames(for: Self.homebrew(bar: 500, window: 800, folded: folded, search: search))
        }
        let reference = page(folded: 136, search: false)
        assertAnswered("tabs", reference.tabs)
        XCTAssertTrue(reference.tabsFolded, "a capsule narrower than the tabs folds them")
        assertSpan("tabs", reference.tabs, 154, 290)
        assertSpan("name", reference.name, 16, 146)

        for folded in [0, -5, 310, 400, Self.nan, Self.inf] as [CGFloat] {
            let f = page(folded: folded, search: false)
            assertAnswered("tabs", f.tabs)
            XCTAssertFalse(f.tabsFolded, "folded width \(folded) offers nothing to fold to")
            assertSpan("tabs", f.tabs, 106, 416)
            assertSpan("name", f.name, 16, 98)
            assertSpan("actions", f.actions, 420, 492)
            XCTAssertTrue(f.fits)

            let s = page(folded: folded, search: true)
            assertAnswered("search", s.search)
            XCTAssertFalse(s.tabsFolded, "folded width \(folded) with a search")
            XCTAssertTrue(s.searchFolded, "the search gives way instead")
            assertSpan("tabs", s.tabs, 66, 376)
            assertSpan("name", s.name, 16, 58)
            assertSpan("actions", s.actions, 380, 452)
            assertSpan("search", s.search, 456, 492)
            XCTAssertTrue(s.fits)
        }
    }

    func testARestingSearchStaysTheMagnifierWhenTheTabsMustFold() {
        func page(bar: CGFloat, name: CGFloat = 130) -> Frames {
            ShellBarLayout.frames(for: Self.homebrew(bar: bar, window: 800, name: name, resting: true))
        }
        let folded = page(bar: 500)
        assertAnswered("tabs", folded.tabs)
        assertAnswered("search", folded.search)
        XCTAssertTrue(folded.tabsFolded)
        XCTAssertTrue(folded.searchFolded)
        assertSpan("tabs", folded.tabs, 154, 290)
        assertSpan("search", folded.search, 456, 492)
        XCTAssertEqual(folded.search.width, 36, "the room the fold freed does not open the field")
        assertSpan("actions", folded.actions, 380, 452)
        assertSpan("name", folded.name, 16, 146)
        XCTAssertTrue(folded.fits)

        let cut = page(bar: 500, name: 300)
        assertAnswered("name", cut.name)
        XCTAssertTrue(cut.tabsFolded)
        assertSpan("name", cut.name, 16, 232)
        assertSpan("tabs", cut.tabs, 240, 376)
        assertSpan("actions", cut.actions, 380, 452)
        assertSpan("search", cut.search, 456, 492)
        XCTAssertTrue(cut.fits)

        let open = page(bar: 600)
        assertAnswered("tabs", open.tabs)
        XCTAssertFalse(open.tabsFolded, "the magnifier leaves the tabs room the field would not")
        XCTAssertTrue(open.searchFolded)
        assertSpan("tabs", open.tabs, 154, 464)
        assertSpan("actions", open.actions, 480, 552)
        assertSpan("search", open.search, 556, 592)
    }

    func testAStatusStandsAtTheEdgeAndTheSearchAndTheActionsStandBeforeIt() {
        func page(bar: CGFloat = 856, window: CGFloat = 1060, actions: CGFloat = 72, search: Bool = true) -> Frames {
            ShellBarLayout.frames(for: Self.homebrew(
                bar: bar, window: window, actions: actions, status: 70, search: search,
                buttons: Self.windowButtons(cardMinX: 200)))
        }
        let all = page()
        assertAnswered("status", all.status)
        assertAnswered("search", all.search)
        assertAnswered("actions", all.actions)
        assertAnswered("tabs", all.tabs)
        assertSpan("status", all.status, 786, 856)
        assertSpan("search", all.search, 565, 782)
        XCTAssertEqual(all.search.width, 217, "the field gave 66 to keep the tabs centred")
        assertSpan("actions", all.actions, 489, 561)
        assertSpan("tabs", all.tabs, 175, 485)
        assertSpan("name", all.name, 16, 146)
        XCTAssertTrue(all.fits)

        let actions = page(search: false)
        assertAnswered("actions", actions.actions)
        assertSpan("status", actions.status, 786, 856)
        assertSpan("actions", actions.actions, 710, 782)
        assertSpan("tabs", actions.tabs, 175, 485)
        XCTAssertEqual(actions.search, .zero)
        XCTAssertTrue(actions.fits)

        let search = page(actions: 0)
        assertAnswered("search", search.search)
        assertSpan("status", search.status, 786, 856)
        assertSpan("search", search.search, 499, 782)
        XCTAssertEqual(search.search.width, 283)
        assertSpan("tabs", search.tabs, 175, 485)
        XCTAssertEqual(search.actions, .zero)
        XCTAssertTrue(search.fits)

        let squeezed = page(bar: 656, window: 860)
        assertAnswered("tabs", squeezed.tabs)
        XCTAssertTrue(squeezed.tabsFolded)
        XCTAssertFalse(squeezed.searchFolded)
        assertSpan("status", squeezed.status, 586, 656)
        assertSpan("search", squeezed.search, 378, 582)
        assertSpan("actions", squeezed.actions, 302, 374)
        assertSpan("tabs", squeezed.tabs, 162, 298)
        assertSpan("name", squeezed.name, 16, 146)
        XCTAssertTrue(squeezed.fits)
    }

    func testWhereverTheBarFitsNothingOverlapsNothingLeavesTheBarAndOnlyTheNameAndTheSearchChangeWidth() {
        var violations: [String] = []
        var rowsFitting = 0
        var rowsNotFitting = 0
        var framesChecked = 0
        var pairsChecked = 0

        let searches: [(has: Bool, resting: Bool, inUse: Bool)] = [
            (false, false, false), (true, false, false), (true, true, false), (true, false, true),
        ]
        for bar in stride(from: CGFloat(0), through: 1400, by: 1) {
            for cardMinX in [CGFloat(200), 56] {
                let start: CGFloat = cardMinX == 56 ? 31 : 16
                for name in [CGFloat(0), 130, 300] {
                    for tabs in [CGFloat(0), 310] {
                        for actions in [CGFloat(0), 36, 72] {
                            for status in [CGFloat(0), 70] {
                                for s in searches {
                                    let input = Input(
                                        barWidth: bar, cardMinX: cardMinX, windowWidth: bar + cardMinX + 4,
                                        nameWidth: name, tabsWidth: tabs, tabsFoldedWidth: tabs == 0 ? 0 : 136,
                                        actionsWidth: actions, statusWidth: status, hasSearch: s.has,
                                        alwaysCollapseSearch: s.resting, searchInUse: s.inUse,
                                        buttons: Self.windowButtons(cardMinX: cardMinX))
                                    let f = ShellBarLayout.frames(for: input)
                                    guard f.fits else { rowsNotFitting += 1; continue }
                                    rowsFitting += 1
                                    let label = "bar \(bar) card \(cardMinX) name \(name) tabs \(tabs) actions \(actions) status \(status) search \(s)"
                                    let zones: [(String, CGRect)] = [
                                        ("name", f.name), ("tabs", f.tabs), ("actions", f.actions),
                                        ("search", f.search), ("status", f.status),
                                    ].filter { $0.1 != .zero }
                                    for (zone, frame) in zones {
                                        framesChecked += 1
                                        if frame.minX < 0 || frame.maxX > bar {
                                            violations.append("\(label): \(zone) \(frame.minX)…\(frame.maxX) leaves 0…\(bar)")
                                        }
                                    }
                                    let wide = zones.filter { $0.1.width > 0 }
                                    for i in wide.indices {
                                        for j in wide.indices where j > i {
                                            pairsChecked += 1
                                            if wide[i].1.maxX > wide[j].1.minX && wide[j].1.maxX > wide[i].1.minX {
                                                violations.append("\(label): \(wide[i].0) \(wide[i].1.minX)…\(wide[i].1.maxX) overlaps \(wide[j].0) \(wide[j].1.minX)…\(wide[j].1.maxX)")
                                            }
                                        }
                                    }
                                    if tabs > 0, f.tabs.width != (f.tabsFolded ? 136 : tabs) {
                                        violations.append("\(label): tabs are \(f.tabs.width) wide")
                                    }
                                    if actions > 0, f.actions.width != actions {
                                        violations.append("\(label): actions are \(f.actions.width) wide")
                                    }
                                    if status > 0, f.status.width != status {
                                        violations.append("\(label): status is \(f.status.width) wide")
                                    }
                                    if name > 0, f.name.minX != start || f.name.width > name {
                                        violations.append("\(label): name is \(f.name.minX)…\(f.name.maxX)")
                                    }
                                    if s.has {
                                        let ok = f.searchFolded
                                            ? f.search.width == 36
                                            : (120...283).contains(f.search.width)
                                        if !ok { violations.append("\(label): search is \(f.search.width) wide, folded \(f.searchFolded)") }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // The subject happened, and both sides of `fits` were exercised.
        XCTAssertGreaterThan(rowsFitting, 10_000, "too few fitting rows were laid out")
        XCTAssertGreaterThan(rowsNotFitting, 100, "too few rows failed to fit: the guard `fits` hardly filtered")
        XCTAssertGreaterThan(framesChecked, 50_000, "too few frames were compared")
        XCTAssertGreaterThan(pairsChecked, 50_000, "too few pairs were compared")
        XCTAssertEqual(rowsFitting + rowsNotFitting, 1401 * 2 * 3 * 2 * 3 * 2 * 4, "every row was laid out")
        XCTAssertEqual(violations.count, 0, "\(violations.count) violations, first: \(violations.prefix(5))")
    }
}
