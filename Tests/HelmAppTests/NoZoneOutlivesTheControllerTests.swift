import AppKit
@testable import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **No zone outlives the controller holding a page's closures.**
///
/// `ShellPageBar` removes its observers when it is released and tells the zones once more, with no content
/// and not live. Without that last `show` a zone that is still alive after it (somebody holds the zone
/// object, or the zone's views are still subviews of the bar's view, which the window holds and the
/// controller does not) keeps the last content it was shown, and with it the page's closures and everything
/// they capture.
///
/// Each row but one builds one REAL zone (`ShellBarTabs`, `ShellBarActions` or `ShellBarSearch`; the other two are
/// `MuteBarZone`) in a bar, declares a live page whose closures capture a sentinel, and **asserts first that
/// the zone drew from that content live** (its view exists and is placed in the bar's view, and the
/// sentinel's own state or handler was reached through the zone). Then the controller and its channel are
/// released while one thing that can lawfully outlive them stays held: the zone object, or the bar's view.
/// The sentinel must be gone at once and after a turn of the run loop.
///
/// The control rows release everything, zone and view included: the sentinel must die there, or the harness
/// itself holds it and no red above means anything.
///
/// One row builds no real zone: a fake zone calls `measuresMoved` from inside the last `show`, and the row
/// holds that nothing is collected, laid out or shown after the release. Three more rows read what a held
/// bar view still holds.
///
/// Not measured: a bar in a window that is shown.
@MainActor
final class NoZoneOutlivesTheControllerTests: XCTestCase {

    enum Hold { case theZone, theBarsView, nothing }

    private struct Built {
        weak var sentinel: PageSentinel?
        weak var controller: ShellPageBar?
        var zone: (any ShellBarZone)?
        var barView: ShellPageBarView?
    }

    /// Everything is local; what returns is a weak sentinel, a weak controller and the one thing `hold` names.
    private func build(_ kind: PageKind, hold: Hold, file: StaticString = #filePath, line: UInt = #line) -> Built {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let tabs = ShellBarTabs(titlebarIsTransparent: true, labelStyle: { .text })
        let actions = ShellBarActions(titlebarIsTransparent: true)
        let search = ShellBarSearch(titlebarIsTransparent: true)
        let bar = ShellPageBar(
            model: model, channel: channel,
            tabs: kind == .tabs ? tabs : MuteBarZone(),
            actions: kind == .actions ? actions : MuteBarZone(),
            search: kind == .search ? search : MuteBarZone(),
            titlebarIsTransparent: true)
        bar.graceInterval = 30
        bar.view.frame = NSRect(x: 0, y: 0, width: 856, height: 52)

        var sentinel: PageSentinel? = PageSentinel()
        let token = ShellPageBar.pageKey(for: model.selection)
        channel.declare(pageContent(kind, sentinel!), token: token, generation: channel.nextGeneration())
        bar.view.layoutSubtreeIfNeeded()

        // The subject: the zone drew this content, live, and its view is in the bar's view.
        let zone: any ShellBarZone = {
            switch kind {
            case .tabs: return tabs
            case .actions: return actions
            case .search: return search
            }
        }()
        XCTAssertEqual(bar.presentation, .page(key: token, isLive: true, isDimmed: false),
                       "\(kind): the bar must show the page live before the release", file: file, line: line)
        XCTAssertNotNil(zone.view, "\(kind): the zone has a view", file: file, line: line)
        XCTAssertTrue(zone.view?.isDescendant(of: bar.view) ?? false,
                      "\(kind): the zone's view is placed in the bar's view", file: file, line: line)
        switch kind {
        case .tabs:
            var measures = ShellPageBarView.Measures()
            tabs.measure(into: &measures)
            XCTAssertGreaterThan(measures.tabsFolded, 0,
                                 "tabs: the zone read the sentinel's selection through the page's binding",
                                 file: file, line: line)
        case .actions:
            actions.model.press("go")
            XCTAssertEqual(sentinel?.hits, 1, "actions: a press reached the page's perform", file: file, line: line)
        case .search:
            XCTAssertEqual(search.field.stringValue, "from the page",
                           "search: the field shows the text the page's binding reads", file: file, line: line)
        }

        let built = Built(
            sentinel: sentinel, controller: bar,
            zone: hold == .theZone ? zone : nil,
            barView: hold == .theBarsView ? bar.view : nil)
        sentinel = nil
        return built
    }

    private func turn(_ seconds: TimeInterval = 0.3) { SettingsWindowRig.pump(seconds) }

    private func check(_ kind: PageKind, hold: Hold, file: StaticString = #filePath, line: UInt = #line) {
        var built: Built? = nil
        autoreleasepool { built = build(kind, hold: hold, file: file, line: line) }
        guard let built else { return XCTFail("nothing built", file: file, line: line) }
        XCTAssertNil(built.controller, "\(kind): the controller is gone, so what follows is about the zone",
                     file: file, line: line)
        XCTAssertNil(built.sentinel,
                     "\(kind), holding \(hold): the page's closures outlive the controller at once",
                     file: file, line: line)
        turn()
        XCTAssertNil(built.sentinel,
                     "\(kind), holding \(hold): the page's closures outlive the controller after a run-loop turn",
                     file: file, line: line)
        withExtendedLifetime(built.zone) {}
        withExtendedLifetime(built.barView) {}
    }

    // MARK: - The zone object outlives the controller

    func testTabsZoneHeldAfterTheControllerHoldsNoPageClosure() { check(.tabs, hold: .theZone) }
    func testActionsZoneHeldAfterTheControllerHoldsNoPageClosure() { check(.actions, hold: .theZone) }
    func testSearchZoneHeldAfterTheControllerHoldsNoPageClosure() { check(.search, hold: .theZone) }

    // MARK: - The bar's view (and the zones' views in it) outlives the controller

    func testTabsViewHeldAfterTheControllerHoldsNoPageClosure() { check(.tabs, hold: .theBarsView) }
    func testActionsViewHeldAfterTheControllerHoldsNoPageClosure() { check(.actions, hold: .theBarsView) }
    func testSearchViewHeldAfterTheControllerHoldsNoPageClosure() { check(.search, hold: .theBarsView) }

    // MARK: - Control: nothing is held, so the harness itself must not hold the sentinel

    func testTabsControlReleasesEverything() { check(.tabs, hold: .nothing) }
    func testActionsControlReleasesEverything() { check(.actions, hold: .nothing) }
    func testSearchControlReleasesEverything() { check(.search, hold: .nothing) }

    // MARK: - A zone that reports new measures from inside the last `show`

    /// A fake of the zone's side of the boundary: it holds no view, and once `reenter` is set it answers every
    /// `show` by calling `measuresMoved` at once and writes a poison into the measures it is asked for. If the
    /// controller's closure ran (a layout of the bar's view follows), the poison lands in the bar view.
    @MainActor private final class ReentrantZone: ShellBarZone {
        var view: NSView? { nil }
        var measuresMoved: (() -> Void)?
        var reenter = false
        var shows: [(hasContent: Bool, isLive: Bool)] = []
        func show(_ state: ShellBarZoneState) {
            shows.append((state.content != nil, state.isLive))
            if reenter { measuresMoved?() }
        }
        func measure(into measures: inout ShellPageBarView.Measures) { measures.tabsFolded = 77 }
        func apply(_ verdicts: ShellPageBarView.Verdicts) {}
    }

    /// The release itself: the last `show` runs in `isolated deinit`, the zone calls `measuresMoved` from
    /// inside it, and nothing happens: no crash, no `collect` (the poison never reaches the bar view's
    /// measures), no layout request on the bar view, no further `show` after the release.
    func testAZoneCallingMeasuresMovedInsideTheLastShowChangesNothing() {
        let zone = ReentrantZone()
        var barView: ShellPageBarView?
        weak var controller: ShellPageBar?
        autoreleasepool {
            let bar = ShellPageBar(model: SettingsModel(host: ModuleHost.shared), channel: HelmWindowToolbarChannel(),
                                   tabs: zone, actions: MuteBarZone(), search: MuteBarZone(),
                                   titlebarIsTransparent: true)
            bar.graceInterval = 30
            bar.view.frame = NSRect(x: 0, y: 0, width: 856, height: 52)
            bar.view.layoutSubtreeIfNeeded()
            barView = bar.view
            controller = bar
            // The subject: before the release the closure IS live, so the same call does reach the bar. The
            // fake writes 77 into the measures it is asked for, and the bar has asked it already, so the
            // number is zeroed first: only a call that reaches the bar can bring it back.
            zone.reenter = true
            bar.view.measures.tabsFolded = 0
            zone.measuresMoved?()
            XCTAssertEqual(bar.view.measures.tabsFolded, 77, "while the controller lives the zone's report reaches the bar")
            bar.view.measures.tabsFolded = 0
            bar.view.layoutSubtreeIfNeeded()
        }
        guard let barView else { return XCTFail("no bar view") }
        XCTAssertNil(controller, "the controller is released")
        XCTAssertEqual(zone.shows.last?.hasContent, false, "the last show carried no content")
        XCTAssertEqual(zone.shows.last?.isLive, false, "the last show was not live")
        XCTAssertEqual(barView.measures.tabsFolded, 0, "the report made inside the release collected nothing")
        XCTAssertFalse(barView.needsLayout, "the report made inside the release asked for no layout")
        let showsAfter = zone.shows.count
        turn()
        XCTAssertEqual(zone.shows.count, showsAfter, "nothing is shown after the release")
        XCTAssertEqual(barView.measures.tabsFolded, 0, "nothing is written after the release")
    }

    /// A bar view outliving the controller, for each real zone: after the release the view holds none of
    /// the three zones' views. It keeps the page's name host, which carries no page closure; by reading it
    /// keeps the status host too when the page has a status word, and no row uses such a page.
    private func checkTheViewHoldsNoZoneView(_ kind: PageKind) {
        var built: Built? = nil
        autoreleasepool { built = build(kind, hold: .theBarsView) }
        guard let barView = built?.barView else { return XCTFail("\(kind): no bar view held") }
        XCTAssertNil(built?.controller, "\(kind): the controller is gone")
        for zone in ShellPageBarView.Zone.allCases where zone != .name && zone != .status {
            XCTAssertNil(barView.view(for: zone), "\(kind): the held bar view still holds the \(zone) view")
        }
        XCTAssertFalse(barView.subviews.contains { $0 is NSSegmentedControl || $0 is NSSearchField || $0 is ShellBarPlate },
                       "\(kind): a zone's control is still a subview: \(barView.subviews.map { String(describing: type(of: $0)) })")
        XCTAssertEqual(barView.subviews.count, ShellPageBarView.Zone.allCases.filter { barView.view(for: $0) != nil }.count,
                       "\(kind): every subview is one of the views the bar view's table names")
        let held = ShellPageBarView.Zone.allCases.filter { barView.view(for: $0) != nil }
        XCTAssertEqual(held, [.name], "\(kind): what the bar view holds is the name only (this page has no status word); the status host would be the other thing it may keep")
    }

    func testTabsHeldBarViewHoldsNoZoneView() { checkTheViewHoldsNoZoneView(.tabs) }
    func testActionsHeldBarViewHoldsNoZoneView() { checkTheViewHoldsNoZoneView(.actions) }
    func testSearchHeldBarViewHoldsNoZoneView() { checkTheViewHoldsNoZoneView(.search) }
}
