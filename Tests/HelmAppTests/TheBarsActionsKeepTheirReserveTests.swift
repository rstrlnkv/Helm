import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The bar's actions zone keeps one capsule for every declared action, runs a press only while its page is
/// live, and stands at the right edge of the bar.**
///
/// The zone is built directly and fed its states by hand, as the controller feeds it. No window is ordered
/// anywhere and no row waits: a hosting view with no window answers `fittingSize` and takes a layout pass on
/// the main thread, and every row asserts first that its subject happened, so an empty capsule cannot pass for
/// a still one.
@MainActor
final class TheBarsActionsKeepTheirReserveTests: XCTestCase {

    private typealias Bar = ShellPageBarView

    private final class Captured {}

    private final class Log {
        var events: [String] = []
    }

    private final class Choice {
        var id: String
        init(_ id: String) { self.id = id }
        var binding: Binding<String> { Binding(get: { self.id }, set: { self.id = $0 }) }
    }

    // MARK: - Feeding the zone

    private func state(_ actions: [HelmToolbarAction], live: Bool = true, dimmed: Bool = false,
                       active: Bool = true, appearance: HelmBarAppearance = .liquidGlass,
                       animated: Bool = false) -> ShellBarZoneState {
        ShellBarZoneState(content: HelmPageToolbarContent(actions: actions), isLive: live, isDimmed: dimmed,
                          appearsActive: active, appearance: appearance, animated: animated)
    }

    private func button(_ id: String, visible: Bool = true, log: Log? = nil,
                        capturing object: Captured? = nil) -> HelmToolbarAction {
        HelmToolbarAction(id: id, title: id, symbol: "x.circle", isVisible: visible) { [object] in
            _ = object
            log?.events.append(id)
        }
    }

    private func makeZone() -> ShellBarActions { ShellBarActions(titlebarIsTransparent: true) }

    private func fitting(_ zone: ShellBarActions) -> CGFloat {
        guard let view = zone.view else { return -1 }
        view.layoutSubtreeIfNeeded()
        return view.fittingSize.width
    }

    private func measured(_ zone: ShellBarActions) -> CGFloat {
        var measures = Bar.Measures()
        zone.measure(into: &measures)
        return measures.actions
    }

    // MARK: - A hidden action and a shown one

    func testAHiddenActionLeavesTheCapsuleAndAShownOneDoesNotMoveItsNeighbours() {
        let zone = makeZone()
        var moved = 0
        zone.measuresMoved = { moved += 1 }

        zone.show(state([button("upgrade", visible: false), button("refresh")]))

        XCTAssertEqual(zone.model.declared.count, 2, """
            the capsule's model holds no entries: 'nothing moved' was an empty capsule
            """)
        XCTAssertEqual(zone.model.visibleIDs, ["refresh"])
        let view = zone.view
        XCTAssertNotNil(view, "the zone has no view for two declared actions")
        XCTAssertEqual(measured(zone), 72, accuracy: 0.01, "the reserve is not two buttons wide while one is hidden")
        XCTAssertEqual(fitting(zone), 72, accuracy: 0.01, "the host is not as wide as its reserve while one is hidden")

        zone.show(state([button("upgrade"), button("refresh")], animated: true))

        XCTAssertEqual(zone.model.visibleIDs, ["upgrade", "refresh"], "the shown action never reached the capsule")
        XCTAssertTrue(zone.view === view, "showing a declared action built the capsule again")
        XCTAssertEqual(measured(zone), 72, accuracy: 0.01, "an action appearing moved the reserve")
        XCTAssertEqual(fitting(zone), 72, accuracy: 0.01, "an action appearing moved the host's width")
        XCTAssertEqual(moved, 0, "the zone called measuresMoved though its width moved only through show")
    }

    // MARK: - A press

    private func pressable(log: Log, choice: Choice, capturing object: Captured? = nil) -> [HelmToolbarAction] {
        [
            button("b", log: log, capturing: object),
            HelmToolbarAction(id: "t", title: "t", symbol: "x.circle", isOn: false) { log.events.append("t") },
            HelmToolbarAction(id: "m", title: "m", symbol: "x.circle", menu: [
                HelmToolbarMenuItem(id: "i1", title: "i1", isOn: false) { log.events.append("m.i1") },
            ]),
            HelmToolbarAction(id: "s", title: "s", options: [
                HelmToolbarTab(id: "o1", title: "o1", symbol: "list.bullet"),
                HelmToolbarTab(id: "o2", title: "o2", symbol: "tablecells"),
            ], selection: choice.binding),
        ]
    }

    private func pressEverything(_ zone: ShellBarActions) {
        zone.model.press("b")
        zone.model.press("t")
        zone.model.press("m")
        zone.model.pressItem("m", "i1")
        zone.model.pressItem("s", "o2")
    }

    func testAPressRunsOnlyWhileThePageIsLiveAndAFrozenZoneHoldsNoneOfItsClosures() {
        let zone = makeZone()
        let log = Log()
        let choice = Choice("o1")

        zone.show(state(pressable(log: log, choice: choice)))
        pressEverything(zone)

        XCTAssertEqual(log.events, ["b", "t", "m.i1"], """
            no press reached a handler while live: 'a frozen press does nothing' was a zone that never presses
            """)
        XCTAssertEqual(choice.id, "o2", "a segment option pressed while live did not reach the page's selection")

        choice.id = "o1"
        let ran = log.events.count
        zone.model.press("nope")
        zone.model.pressItem("m", "nope")
        zone.model.pressItem("s", "nope")
        zone.model.pressItem("b", "i1")
        XCTAssertEqual(log.events.count, ran, "a press naming nothing the page declared ran a handler")
        XCTAssertEqual(choice.id, "o1", "a non-existent option changed the selection")

        // A zone told the page is not live runs nothing, whatever content it was handed.
        zone.show(state(pressable(log: log, choice: choice), live: false, dimmed: true))
        pressEverything(zone)
        XCTAssertEqual(log.events.count, ran, "a press ran a handler on a page that is not live")
        XCTAssertEqual(choice.id, "o1", "a segment option pressed on a page that is not live moved the selection")

        // The controller's frozen page: closures stripped, and nothing of the live page held.
        var captured: Captured? = Captured()
        weak var weakCaptured = captured
        zone.show(state(pressable(log: log, choice: choice, capturing: captured)))
        captured = nil
        XCTAssertNotNil(weakCaptured, """
            the captured object was never held: its release proves nothing
            """)
        let frozen = HelmPageToolbarContent(actions: pressable(log: log, choice: choice))
        zone.show(ShellBarZoneState(content: ShellPageBar.strippedOfClosures(frozen), isLive: false,
                                    isDimmed: true, appearsActive: true, appearance: .liquidGlass, animated: false))
        XCTAssertNil(weakCaptured, "the frozen zone kept the live page's closure")
        pressEverything(zone)
        XCTAssertEqual(log.events.count, ran, "a press ran a handler on a frozen page")
        XCTAssertEqual(choice.id, "o1", "a press on a frozen page moved the selection")
    }

    // MARK: - A dimmed page

    func testADimmedPageLooksInertAndAnOrdinaryReturnDoesNot() {
        let zone = makeZone()
        let actions = [button("a"), button("b")]

        zone.show(state(actions))
        XCTAssertTrue(zone.model.isInteractive, "precondition: a live page is not interactive")

        zone.show(state(actions, live: false, dimmed: true))
        XCTAssertFalse(zone.model.isInteractive, """
            isInteractive never left true: no dimmed state reached the model
            """)

        zone.show(state(actions, live: false, dimmed: false))
        XCTAssertTrue(zone.model.isInteractive, "an ordinary return visit, frozen but not dimmed, looked inert")

        zone.show(state(actions, live: true, dimmed: false))
        XCTAssertTrue(zone.model.isInteractive, "a live page looked inert")
    }

    // MARK: - A page change

    func testAnotherPagesActionsGetAFreshCapsuleAndNoActionsGetNone() {
        let zone = makeZone()

        zone.show(state([button("a"), button("b")], animated: false))
        let first = zone.view
        XCTAssertNotNil(first, """
            the zone never had a view: 'a fresh capsule' compared nil with nil
            """)
        XCTAssertEqual(zone.model.declared.map(\.id), ["a", "b"])

        zone.show(state([button("a"), button("b", visible: false)], animated: true))
        XCTAssertTrue(zone.view === first, "the same page, shown again, built another capsule")
        XCTAssertEqual(zone.model.visibleIDs, ["a"])

        zone.show(state([button("c")], animated: false))
        let second = zone.view
        XCTAssertNotNil(second, "another page's actions got no view")
        XCTAssertTrue(second !== first, "another page's actions were drawn in the previous page's capsule")
        XCTAssertEqual(zone.model.declared.map(\.id), ["c"], "the new capsule's model still holds the old page's actions")
        XCTAssertEqual(measured(zone), 36, accuracy: 0.01)

        zone.show(ShellBarZoneState(content: nil, isLive: true, isDimmed: false, appearsActive: true,
                                    appearance: .liquidGlass, animated: false))
        XCTAssertNil(zone.view, "a page with no actions kept a view")
        XCTAssertEqual(measured(zone), 0, "a page with no actions kept a width")
        XCTAssertTrue(zone.model.declared.isEmpty, "a page with no actions left entries in the model")
        XCTAssertTrue(zone.model.visibleIDs.isEmpty)
    }

    // MARK: - The window's activity

    func testTheWindowsActivityReachesTheModelAndRebuildsOnlyGlass() {
        for (look, rebuilds) in [(HelmBarAppearance.liquidGlass, true), (.flat, false)] {
            let zone = makeZone()
            let actions = [button("a"), button("b")]

            zone.show(state(actions, active: true, appearance: look))
            let before = zone.view
            XCTAssertNotNil(before, "\(look): the zone had no view")
            XCTAssertTrue(zone.model.appearsActive, """
                appearsActive never left true: both looks kept one host because nothing changed
                """)

            zone.show(state(actions, active: false, appearance: look))

            XCTAssertFalse(zone.model.appearsActive, "\(look): the window's inactivity never reached the model")
            if rebuilds {
                XCTAssertTrue(zone.view !== before, "\(look): glass kept its host through a change of activity")
            } else {
                XCTAssertTrue(zone.view === before, "\(look): a flat bar rebuilt its host for a change of activity")
            }
        }
    }

    // MARK: - Placed in a bar

    /// A segmented action stands at the right with every other action.
    func testASegmentedActionStandsAtTheRightWithEveryOtherAction() {
        let zone = makeZone()
        let choice = Choice("o1")
        zone.show(state([
            HelmToolbarAction(id: "s", title: "s", options: [
                HelmToolbarTab(id: "o1", title: "o1", symbol: "square.grid.2x2"),
                HelmToolbarTab(id: "o2", title: "o2", symbol: "text.alignleft"),
            ], selection: choice.binding),
            button("refresh"),
        ]))

        let bar = Bar()
        var measures = Bar.Measures()
        measures.name = 120
        measures.tabs = 310
        measures.tabsFolded = 136
        zone.measure(into: &measures)
        XCTAssertGreaterThan(measures.actions, 0, """
            the actions frame is .zero: the zone measured 0 and nothing was placed
            """)
        XCTAssertGreaterThan(measures.actions, 36,
                             "the zone reserved no more than one button's width for a switcher and a button")
        XCTAssertFalse(measures.hasSearch, "precondition: the bar was given a search")

        bar.setView(NSView(), for: .tabs)
        bar.setView(zone.view, for: .actions)
        bar.measures = measures
        bar.place = Bar.Place(cardMinX: 200, windowWidth: 856, buttons: .null)
        bar.frame = NSRect(x: 0, y: 0, width: 856, height: 52)
        bar.layoutSubtreeIfNeeded()

        guard let frames = bar.frames?.actions, frames.width > 0 else {
            return XCTFail("the actions frame is .zero: the zone measured 0 and nothing was placed")
        }
        XCTAssertGreaterThan(ShellBarLayout.trailing, 0, "the trailing margin is 0: the right edge proves nothing")
        XCTAssertEqual(frames.maxX, 856 - ShellBarLayout.trailing, accuracy: 0.01,
                       "the actions do not end at the bar's trailing margin")
        XCTAssertEqual(frames.width, measures.actions, accuracy: 0.01, "the bar gave the actions another width than they asked for")
        XCTAssertTrue(zone.view?.frame == frames, "the zone's view was not placed in its frame")
        XCTAssertEqual(zone.view?.isHidden, false)
    }

    // MARK: - A segmented action's reserve

    private func segmented(symbols: [String], choice: Choice) -> HelmToolbarAction {
        HelmToolbarAction(id: "s", title: "s", options: symbols.enumerated().map { index, symbol in
            HelmToolbarTab(id: "o\(index + 1)", title: "o\(index + 1)", symbol: symbol)
        }, selection: choice.binding)
    }

    /// The drawn switcher's fitting width and laid-out width in a zone's host, nil when none is drawn.
    private func drawnSwitcher(_ zone: ShellBarActions) -> (fitting: CGFloat, frame: CGFloat)? {
        guard let view = zone.view else { return nil }
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        view.layoutSubtreeIfNeeded()
        guard let control = view.everyView(ofType: NSSegmentedControl.self).first else { return nil }
        return (control.fittingSize.width, control.frame.width)
    }

    /// The glyph sets here are used by no other row: the reserve cache is static and keyed by glyphs and look,
    /// and each look is new to it once per process.
    func testASegmentedActionReservesWhatItsSwitcherDrawsUnderEachLook() throws {
        for symbols in [["externaldrive", "network"], ["bolt"]] {
            let zone = makeZone()
            let choice = Choice("o1")
            var reserves: [HelmBarAppearance: CGFloat] = [:]
            for look in [HelmBarAppearance.liquidGlass, .flat] {
                let before = ShellBarActions.reserveMeasurements
                zone.show(state([segmented(symbols: symbols, choice: choice)], appearance: look))
                let reserve = measured(zone)
                reserves[look] = reserve

                XCTAssertGreaterThan(reserve, 0, """
                    the switcher was never mounted: its reserve read 0 under both looks, and 0 covers 0
                    """)
                let widths = try XCTUnwrap(drawnSwitcher(zone),
                                           "\(look): no NSSegmentedControl in the zone's host: nothing was drawn to compare")
                XCTAssertGreaterThan(widths.fitting, 0, "\(look): the drawn control has no width, so it fits any reserve")
                XCTAssertEqual(reserve, reserve.rounded(.up), "\(look): the reserve is not a whole point: \(reserve)")
                XCTAssertLessThanOrEqual(widths.fitting, reserve + 0.01,
                    "\(look), \(symbols.count) option(s): the drawn control (\(widths.fitting) pt) is wider than its reserve (\(reserve) pt)")
                XCTAssertLessThanOrEqual(widths.frame, reserve + 0.01,
                    "\(look), \(symbols.count) option(s): the laid-out control (\(widths.frame) pt) is wider than its reserve (\(reserve) pt)")
                XCTAssertEqual(ShellBarActions.reserveMeasurements - before, 1,
                    "\(look): showing the zone under a look it had not drawn in did not measure the switcher once")
            }

            // Back to the first look: a measured key is read, not measured again.
            let before = ShellBarActions.reserveMeasurements
            zone.show(state([segmented(symbols: symbols, choice: choice)], appearance: .liquidGlass))
            XCTAssertEqual(ShellBarActions.reserveMeasurements, before, "a look already measured was measured again")
            XCTAssertEqual(measured(zone), reserves[.liquidGlass] ?? -1, accuracy: 0.01,
                           "returning to a look changed the reserve it had")
        }
    }

    // MARK: - A keystroke

    func testAKeystrokeMeasuresNoSwitcher() {
        let zone = makeZone()
        let choice = Choice("o1")
        let symbols = ["cloud", "sun.max"]
        let start = ShellBarActions.reserveMeasurements

        zone.show(state([segmented(symbols: symbols, choice: choice)]))
        let first = ShellBarActions.reserveMeasurements
        XCTAssertGreaterThan(first, start, """
            no reserve was ever measured: the count stood still because nothing was counted
            """)
        XCTAssertGreaterThan(measured(zone), 0, "the first show reserved nothing for a segmented action")

        for keystroke in 1...20 {
            choice.id = keystroke.isMultiple(of: 2) ? "o1" : "o2"
            zone.show(state([segmented(symbols: symbols, choice: choice), button("refresh")], animated: true))
        }

        XCTAssertEqual(zone.model.declared.count, 2, "the last show never reached the model: the count held because nothing ran")
        XCTAssertEqual(ShellBarActions.reserveMeasurements, first,
                       "twenty republications of one glyph set mounted a switcher again")
    }

    // MARK: - The flat ink

    /// The zone keeps the numbers private; the label is the stored property's name.
    private func flatInk(of zone: ShellBarActions) -> HelmToolbarActionsCapsule.InactiveInk? {
        Mirror(reflecting: zone).children.first { $0.label == "flatInactiveInk" }?.value
            as? HelmToolbarActionsCapsule.InactiveInk
    }

    /// The hand-over itself, photographed: a flat zone's host, in a window that stopped being active, draws
    /// well under half of what it drew while active, in both appearances. Measured about 0.35 light and about 0.30 dark
    /// with the numbers handed over; a capsule built without them drew the same ink in both states (ratio 1).
    /// The host is not in a window, so this reads the model's activity and not a window's; that the dimming
    /// reads right on a screen was not seen.
    func testAFlatHostDimsWhenTheWindowIsInactiveBecauseTheZoneHandedItsNumbers() throws {
        for name in RenderedInk.bothAppearances {
            let zone = makeZone()
            let actions = [segmented(symbols: ["star", "heart"], choice: Choice("o1"))]
            let label = RenderedInk.label(of: name)
            zone.show(state(actions, active: true, appearance: .flat))
            let view = try XCTUnwrap(zone.view, "\(label): the zone had no view")
            view.appearance = NSAppearance(named: name)
            view.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
            view.layoutSubtreeIfNeeded()
            let active = try XCTUnwrap(RenderedInk.read(view), "\(label): the active host could not be photographed")
            XCTAssertGreaterThan(active, 0, "\(label): the active host drew nothing, so 'dimmed' compares nothing")

            zone.show(state(actions, active: false, appearance: .flat))
            XCTAssertTrue(zone.view === view, "\(label): a flat zone rebuilt its host for a change of activity")
            XCTAssertFalse(zone.model.appearsActive, "\(label): precondition: the model is still active")
            view.layoutSubtreeIfNeeded()
            let inactive = try XCTUnwrap(RenderedInk.read(view), "\(label): the inactive host could not be photographed")
            XCTAssertLessThan(Double(inactive), Double(active) * 0.5,
                "\(label): an inactive window's flat capsule drew \(inactive) of \(active): the zone handed the capsule no dimming numbers")
        }
    }

    func testFlatInkDimsAsTheNameDoesAndGlassKeepsAppKitsNumbers() throws {
        typealias Capsule = HelmToolbarActionsCapsule
        for transparent in [true, false] {
            let ink = flatInk(of: ShellBarActions(titlebarIsTransparent: transparent))
            XCTAssertNotNil(ink, """
                the zone handed the capsule no flat numbers: flat read 0.25 / 0.31, AppKit's, in every case
                """)
            for dark in [true, false] {
                let name = helmNameZoneInactiveOpacity(dark: dark, titlebarIsTransparent: transparent)
                let appKits = dark ? Capsule.inactiveGlyphOpacityDark : Capsule.inactiveGlyphOpacityLight
                XCTAssertEqual(Capsule.inactiveOpacity(appearance: .flat, dark: dark, flatInactiveInk: ink), name,
                               "transparent \(transparent), dark \(dark): flat does not dim as the name zone does")
                XCTAssertEqual(Capsule.inactiveOpacity(appearance: .liquidGlass, dark: dark, flatInactiveInk: ink), appKits,
                               "transparent \(transparent), dark \(dark): glass left AppKit's number")
                XCTAssertEqual(Capsule.inactiveOpacity(appearance: .flat, dark: dark, flatInactiveInk: nil), appKits,
                               "transparent \(transparent), dark \(dark): flat with no numbers left AppKit's")
            }
        }
        XCTAssertNotEqual(helmNameZoneInactiveOpacity(dark: true, titlebarIsTransparent: true),
                          Capsule.inactiveGlyphOpacityDark,
                          "the name's number equals AppKit's: the flat ink proves nothing")

        // Both looks draw the strip with the flat cell; the look is the plate under it. A change of look
        // hands the zone a new host (the zone's own rule), which proves the second look arrived, and the
        // control in that host wears the same cell.
        func strip(_ zone: ShellBarActions, _ look: HelmBarAppearance) throws -> NSSegmentedControl {
            let view = try XCTUnwrap(zone.view, "\(look): the zone had no view")
            view.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
            view.layoutSubtreeIfNeeded()
            return try XCTUnwrap(view.everyView(ofType: NSSegmentedControl.self).first,
                                 "\(look): no NSSegmentedControl in the zone's host")
        }
        for (first, second) in [(HelmBarAppearance.flat, HelmBarAppearance.liquidGlass), (.liquidGlass, .flat)] {
            let zone = makeZone()
            let entries = [segmented(symbols: ["star", "heart"], choice: Choice("o1"))]
            zone.show(state(entries, appearance: first))
            let before = try XCTUnwrap(zone.view, "\(first): the zone had no view")
            let one = try strip(zone, first)
            XCTAssertTrue(type(of: one.cell!) == HelmFlatSegmentedCell.self,
                          "\(first): the inner control's cell is \(String(describing: one.cell)), not the flat one")

            zone.show(state(entries, appearance: second))
            XCTAssertTrue(zone.view !== before, "\(first) -> \(second): the second look never reached the zone")
            let two = try strip(zone, second)
            XCTAssertTrue(two !== one, "\(first) -> \(second): precondition: the control in the new host is the old one")
            XCTAssertTrue(type(of: two.cell!) == HelmFlatSegmentedCell.self,
                          "\(second): the inner control's cell is \(String(describing: two.cell)), not the flat one")
        }
    }
}
