import AppKit
import SwiftUI
import XCTest
@testable import HelmApp

/// **`ShellPageBarView` puts each of the bar's five zone views in the frame
/// `ShellBarLayout` answers, hides a zone the layout calls absent, and tells its
/// receiver about a folded zone before it moves anything.**
///
/// No window is ordered anywhere: the view stands at (0, 0, W, 52) and
/// `layoutSubtreeIfNeeded()` runs its `layout()`. The zones' views are plain
/// `NSView`s, except in the row that hosts the real name and status.
///
/// Every expected frame is typed as a literal, `minX…maxX` on the row at y 8, 36
/// high, worked by hand from the layout's own rules for the measures its row
/// names; the test never calls `ShellBarLayout.frames` to learn what to expect.
@MainActor
final class TheBarPlacesItsZonesWhereTheLayoutSaysTests: XCTestCase {

    private typealias Bar = ShellPageBarView

    private static let homebrew = Bar.Measures(name: 130, tabs: 310, tabsFolded: 136, actions: 72,
                                               status: 0, hasSearch: true)

    @MainActor
    private final class Stage {
        let bar = Bar()
        let views: [Bar.Zone: NSView]

        init() {
            var made: [Bar.Zone: NSView] = [:]
            for zone in Bar.Zone.allCases {
                let view = NSView()
                made[zone] = view
                bar.setView(view, for: zone)
            }
            views = made
        }

        subscript(_ zone: Bar.Zone) -> NSView { views[zone]! }

        /// One pass at the given width, as the owner of the bar would run it.
        func lay(width: CGFloat,
                 buttons: CGRect = .null, measures: Bar.Measures) {
            bar.measures = measures
            bar.place = Bar.Place(buttons: buttons)
            bar.frame = NSRect(x: 0, y: 0, width: width, height: 52)
            bar.layoutSubtreeIfNeeded()
        }
    }

    private func row(_ minX: CGFloat, _ maxX: CGFloat) -> CGRect {
        CGRect(x: minX, y: 8, width: maxX - minX, height: 36)
    }

    private func assertFrame(_ view: NSView, _ expected: CGRect, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(view.frame, expected, what, file: file, line: line)
        XCTAssertFalse(view.isHidden, "\(what) is hidden", file: file, line: line)
    }

    // MARK: - Where the views stand

    func testEveryZonesViewStandsInTheFrameTheLayoutAnswers() {
        let stage = Stage()
        // The window's three buttons where `TheCardIsConcentricWithTheWindowTests` puts them, x 19...79 in the window: -181...-121 in a bar whose card starts at 200.
        stage.lay(width: 856, buttons: CGRect(x: -181, y: 19, width: 60, height: 14),
                  measures: Self.homebrew)

        XCTAssertFalse(Bar.Zone.allCases.allSatisfy { stage[$0].frame == .zero }, """
            the view set no frame: all five zone views are still at .zero — layout() never ran or never \
            asked the layout, and every comparison below would be of what was never placed
            """)
        assertFrame(stage[.name], row(16, 146), "the name")
        assertFrame(stage[.tabs], row(273, 583), "the tabs")
        assertFrame(stage[.actions], row(587, 659), "the actions")
        assertFrame(stage[.search], row(663, 848), "the search")
        XCTAssertTrue(stage[.status].isHidden, "no status was asked for, and its view is shown")
        XCTAssertNotNil(stage.bar.frames, "the view keeps no answer after a pass")
    }

    func testAZoneTheLayoutCallsAbsentIsHiddenAndTheRestStand() {
        let stage = Stage()
        stage.lay(width: 856, measures: Bar.Measures(name: 130, status: 70))

        XCTAssertFalse(Bar.Zone.allCases.allSatisfy { stage[$0].frame == .zero }, """
            the view set no frame: all five zone views are still at .zero — layout() never ran or never \
            asked the layout, and every comparison below would be of what was never placed
            """)
        assertFrame(stage[.status], row(786, 856), "the status")
        assertFrame(stage[.name], row(16, 146), "the name")
        for zone in [Bar.Zone.tabs, .actions, .search] {
            XCTAssertTrue(stage[zone].isHidden, "\(zone) has no width and its view is shown")
        }
    }

    // MARK: - The verdicts

    func testAFoldedZoneIsToldBeforeAnythingMovesAndOnlyWhenTheVerdictChanged() {
        let stage = Stage()
        var calls: [Bar.Verdicts] = []
        var framesInside: ShellBarLayout.Frames?
        var tabsViewInside: CGRect?
        stage.bar.verdictsChanged = { [unowned stage] verdicts in
            calls.append(verdicts)
            framesInside = stage.bar.frames
            tabsViewInside = stage[.tabs].frame
        }

        stage.lay(width: 856, measures: Self.homebrew)
        XCTAssertEqual(calls.count, 0, "a first pass that answers nothing folded told the receiver")
        XCTAssertEqual(stage[.tabs].frame, row(273, 583))

        stage.lay(width: 656, measures: Self.homebrew)
        XCTAssertEqual(calls.count, 1, "the tabs folded and the receiver was told \(calls.count) times")
        XCTAssertEqual(calls.first, Bar.Verdicts(tabsFolded: true, searchFolded: false))
        XCTAssertEqual(framesInside?.tabs, row(260, 396),
                       "inside the call the new answer was not stored yet")
        XCTAssertEqual(tabsViewInside, row(273, 583),
                       "a frame of this pass was set before the receiver was told")
        assertFrame(stage[.tabs], row(260, 396), "the tabs after the pass")
        assertFrame(stage[.actions], row(400, 472), "the actions after the pass")
        assertFrame(stage[.search], row(476, 648), "the search after the pass")

        stage.lay(width: 650, measures: Self.homebrew)
        XCTAssertEqual(calls.count, 1, "the same verdict told the receiver again")
    }

    // MARK: - A change of input lays out again, an equal one does not

    func testAChangedPlaceMovesTheNameAndAnEqualOneAndAnEqualMeasureAskForNothing() {
        let stage = Stage()
        stage.lay(width: 1000, buttons: .null, measures: Self.homebrew)
        assertFrame(stage[.name], row(16, 146), "the name with no buttons")

        stage.lay(width: 1000,
                  buttons: CGRect(x: -37, y: 15, width: 60, height: 14), measures: Self.homebrew)
        assertFrame(stage[.name], row(31, 161), "the name beside the buttons")
        assertFrame(stage[.tabs], row(345, 655), "the tabs beside the buttons")
        assertFrame(stage[.actions], row(659, 731), "the actions beside the buttons")
        assertFrame(stage[.search], row(735, 992), "the search beside the buttons")

        XCTAssertFalse(stage.bar.needsLayout, "a pass left the view asking for another")
        stage.bar.place = stage.bar.place
        XCTAssertFalse(stage.bar.needsLayout, "writing an equal place asked for a layout")
        stage.bar.measures = stage.bar.measures
        XCTAssertFalse(stage.bar.needsLayout, "writing equal measures asked for a layout")
        stage.bar.measures.name = 131
        XCTAssertTrue(stage.bar.needsLayout, "writing other measures asked for nothing")
    }

    // MARK: - The order and the ownership of the subviews

    func testSubviewsStandInZoneOrderWhateverOrderTheyWereGivenInAndAReplacedViewLeaves() {
        let bar = Bar()
        var given: [Bar.Zone: NSView] = [:]
        for zone in [Bar.Zone.status, .search, .name, .actions, .tabs] {
            let view = NSView()
            given[zone] = view
            bar.setView(view, for: zone)
        }
        let expected = Bar.Zone.allCases.map { given[$0]! }
        XCTAssertEqual(bar.subviews, expected, "the subviews are not in zone order")
        XCTAssertTrue(bar.view(for: .tabs) === given[.tabs])

        let replacement = NSView()
        bar.setView(replacement, for: .search)
        XCTAssertNil(given[.search]?.superview, "the replaced view is still in the bar")
        XCTAssertTrue(bar.view(for: .search) === replacement)
        XCTAssertEqual(bar.subviews.count, 5)
        XCTAssertEqual(bar.subviews.firstIndex(of: replacement), 3, "the replacement is out of order")

        bar.setView(nil, for: .actions)
        XCTAssertNil(given[.actions]?.superview, "a view set to nil is still in the bar")
        XCTAssertNil(bar.view(for: .actions))
        XCTAssertEqual(bar.subviews.count, 4)
    }

    // MARK: - The real name and status

    func testTheRealNameAndStatusHostsStandInTheFramesTheLayoutAnswers() {
        let bar = Bar()
        let name = NSHostingView(rootView: NameZoneView(
            symbol: "gearshape", tint: .blue, title: "Homebrew", iconStyle: .colour,
            appearsActive: true, titlebarIsTransparent: true))
        let status = NSHostingView(rootView: StatusZoneView(
            status: (word: "Running", active: true), appearsActive: true,
            titlebarIsTransparent: true, trailingInset: 0))
        bar.setView(name, for: .name)
        bar.setView(status, for: .status)
        bar.measures = Bar.Measures(name: 130, status: 70)
        bar.frame = NSRect(x: 0, y: 0, width: 856, height: 52)
        bar.layoutSubtreeIfNeeded()

        XCTAssertNotEqual(name.frame, .zero, """
            the view set no frame: the hosted name is still at .zero — layout() never ran or never \
            asked the layout
            """)
        XCTAssertEqual(name.frame, row(16, 146), "the hosted name")
        XCTAssertEqual(status.frame, row(786, 856), "the hosted status")
    }

    // MARK: - What the rows above never reach

    /// A bar too narrow for the name beside the tabs, the actions and a search:
    /// both folded, the search is only its magnifier.
    private func layBothFolded(_ stage: Stage) {
        stage.lay(width: 536,
                  measures: Bar.Measures(name: 200, tabs: 310, tabsFolded: 136, actions: 72,
                                         status: 0, hasSearch: true))
    }

    func testABarThatFoldsTheSearchTooTellsItsReceiverBothVerdictsAndPlacesTheMagnifier() {
        let stage = Stage()
        var calls: [Bar.Verdicts] = []
        stage.bar.verdictsChanged = { calls.append($0) }
        layBothFolded(stage)

        XCTAssertEqual(calls, [Bar.Verdicts(tabsFolded: true, searchFolded: true)],
                       "the receiver was not told once that both zones folded")
        XCTAssertEqual(stage.bar.verdicts, Bar.Verdicts(tabsFolded: true, searchFolded: true))
        assertFrame(stage[.name], row(16, 216), "the name")
        assertFrame(stage[.tabs], row(224, 360), "the folded tabs")
        assertFrame(stage[.actions], row(416, 488), "the actions")
        assertFrame(stage[.search], row(492, 528), "the magnifier")
    }

    func testAViewSwappedInsideTheCallStandsInTheAnsweredFrameAndTheOldOneIsGone() {
        let stage = Stage()
        let magnifier = NSView()
        let field = stage[.search]
        stage.bar.verdictsChanged = { [unowned stage] verdicts in
            if verdicts.searchFolded { stage.bar.setView(magnifier, for: .search) }
        }
        layBothFolded(stage)

        XCTAssertFalse(stage.bar.needsLayout, """
            the pass that swapped a view in left a layout request pending: setView inside \
            layout() marked the bar dirty, so the next display cycle lays out again
            """)
        XCTAssertNotEqual(magnifier.frame, .zero, """
            the swapped-in view was never placed: it is still at .zero — the receiver was told \
            after the frames were set, or the pass did not reach a view set inside it
            """)
        assertFrame(magnifier, row(492, 528), "the swapped-in magnifier")
        XCTAssertNil(field.superview, "the replaced field is still in the bar")
        XCTAssertTrue(magnifier.superview === stage.bar)
        XCTAssertTrue(stage.bar.view(for: .search) === magnifier)
        XCTAssertEqual(stage.bar.subviews.count, 5)
        XCTAssertEqual(stage.bar.subviews.firstIndex(of: magnifier), 3, "the swapped-in view is out of order")
    }

    func testAZoneShownOnOnePassAndAnsweredNoWidthOnALaterOneIsHiddenAndShownAgain() {
        let stage = Stage()
        stage.lay(width: 856, measures: Self.homebrew)
        assertFrame(stage[.tabs], row(273, 583), "the tabs on the first pass")
        assertFrame(stage[.search], row(663, 848), "the search on the first pass")

        stage.lay(width: 856, measures: Bar.Measures(name: 130, status: 70))
        for zone in [Bar.Zone.tabs, .actions, .search] {
            XCTAssertTrue(stage[zone].isHidden, "\(zone) was shown before and has no width now, and its view is shown")
        }
        assertFrame(stage[.name], row(16, 146), "the name on the second pass")

        stage.lay(width: 856, measures: Self.homebrew)
        assertFrame(stage[.tabs], row(273, 583), "the tabs when they come back")
        assertFrame(stage[.search], row(663, 848), "the search when it comes back")
    }

    func testTheSameViewAgainDoesNothingAndANewViewAsksForALayout() {
        let stage = Stage()
        stage.lay(width: 856, measures: Self.homebrew)
        let before = stage.bar.subviews
        XCTAssertFalse(stage.bar.needsLayout, "a pass left the view asking for another")

        stage.bar.setView(stage[.tabs], for: .tabs)
        XCTAssertFalse(stage.bar.needsLayout, "setting the same view again asked for a layout")
        XCTAssertEqual(stage.bar.subviews, before, "setting the same view again moved the subviews")
        XCTAssertTrue(stage[.tabs].superview === stage.bar)

        let other = NSView()
        stage.bar.setView(other, for: .tabs)
        XCTAssertTrue(stage.bar.needsLayout, "a new view was set and no layout was asked for")
        stage.bar.layoutSubtreeIfNeeded()
        assertFrame(other, row(273, 583), "the new view after the layout it asked for")
    }

    func testAFrameWithAHalfPointIsSetExactly() {
        let stage = Stage()
        // Bar 671: the tabs fold and the bar's centre 335.5 less half their width puts them on a half point.
        stage.lay(width: 671, measures: Self.homebrew)

        assertFrame(stage[.tabs], row(267.5, 403.5), "the folded tabs")
        assertFrame(stage[.search], row(483.5, 663), "the search")
        XCTAssertEqual(stage[.tabs].frame.minX, 267.5, "the half point was rounded")
    }

    // MARK: - Coordinates

    func testTheBarIsFlippedSoItsRowsCountFromTheTop() {
        XCTAssertTrue(Bar().isFlipped)
    }
}
