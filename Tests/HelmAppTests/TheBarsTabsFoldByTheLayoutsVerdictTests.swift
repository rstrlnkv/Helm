import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The bar's tabs zone folds exactly when `ShellBarLayout` says, answers both of its natural widths whether
/// or not it is folded, reads each width once per shape, and runs a page's handler only for a live, enabled
/// press.**
///
/// No window is ordered anywhere and no row sends an action to a folded control (that pops a menu up): hosts and
/// the bar's view are laid out windowless, and a press goes through the seam the switcher itself uses, the
/// control's action when the strip is whole and an item of the coordinator's tabs menu when it is folded. A
/// width is never read back from the zone to be compared with itself: the oracle is this file's own mount of
/// `HelmToolbarSwitcher` with the same inputs, whose control's fitting width is read for the whole strip and for
/// the folded one. The zone is built with a label style handed in, so no row writes a stored setting.
///
/// **Not seen on a screen:** the fold as a person sees it, and a press that lands on the strip through the bar.
@MainActor
final class TheBarsTabsFoldByTheLayoutsVerdictTests: XCTestCase {

    // MARK: - The page, the zone and the oracle

    /// What a page's selected-tab binding was asked to write, and what it holds now.
    private final class Box {
        var value: String
        var sets: [String] = []
        init(_ value: String) { self.value = value }
    }

    private final class StyleBox { var style = ToolbarSwitcherStyle.text }

    /// Everything a row varies, one field at a time.
    private struct Params {
        var ids = ["installed", "updates", "search"]
        var titles = ["Installed", "Updates", "Search"]
        var symbols = ["circle", "circle", "circle"]
        var attention = [false, false, false]
        var notes: [String?] = [nil, nil, nil]
        var selected: String? = "updates"
        var style = ToolbarSwitcherStyle.text
        var appearance = HelmBarAppearance.flat
        var isLive = true
        var isDimmed = false
        var tabsEnabled = true
        var appearsActive = true
    }

    private struct OracleView: View {
        let segments: [HelmSwitcherSegment<String>]
        let selected: String
        let compact: Bool
        let style: ToolbarSwitcherStyle
        let appearance: HelmBarAppearance

        var body: some View {
            HelmToolbarSwitcher("Probe", selection: .constant(selected), segments: segments,
                                compact: compact, appearance: appearance)
                .environment(\.helmSwitcherStyle, style)
        }
    }

    /// The natural width of the whole strip and of the folded one, from a switcher mounted here with the
    /// same inputs. The folded width is 0 when the selection names no tab, as the zone answers.
    private func oracle(_ p: Params) throws -> (full: CGFloat, folded: CGFloat) {
        let segments = p.ids.indices.map { index in
            HelmSwitcherSegment(p.ids[index], p.titles[index], symbol: p.symbols[index],
                                needsAttention: p.attention[index], attentionNote: p.notes[index])
        }
        func width(compact: Bool) throws -> CGFloat {
            let host = NSHostingView(rootView: OracleView(segments: segments, selected: p.selected ?? "",
                                                          compact: compact, style: p.style,
                                                          appearance: p.appearance))
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
            host.layoutSubtreeIfNeeded()
            let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                        "the oracle mounted no segmented control")
            return control.fittingSize.width
        }
        let full = try width(compact: false)
        let named = p.selected.map { p.ids.contains($0) } ?? false
        return (full, named ? try width(compact: true) : 0)
    }

    @MainActor
    private final class Rig {
        var params = Params()
        let styleBox = StyleBox()
        let zone: ShellBarTabs
        private(set) var box = Box("")

        init() {
            let styleBox = styleBox
            zone = ShellBarTabs(titlebarIsTransparent: true, labelStyle: { styleBox.style })
        }

        func content(_ box: Box) -> HelmPageToolbarContent {
            let tabs = params.ids.indices.map { index in
                HelmToolbarTab(id: params.ids[index], title: params.titles[index], symbol: params.symbols[index],
                               needsAttention: params.attention[index], attentionNote: params.notes[index])
            }
            let binding: Binding<String>? = params.selected == nil ? nil
                : Binding(get: { box.value }, set: { box.sets.append($0); box.value = $0 })
            return HelmPageToolbarContent(tabs: tabs, selectedTab: binding, tabsEnabled: params.tabsEnabled)
        }

        func state(_ content: HelmPageToolbarContent?) -> ShellBarZoneState {
            ShellBarZoneState(content: content, isLive: params.isLive, isDimmed: params.isDimmed,
                              appearsActive: params.appearsActive, appearance: params.appearance, animated: false)
        }

        /// Shows the params with a binding of their own, new each time, as a page republishing does.
        @discardableResult
        func show() -> Box {
            styleBox.style = params.style
            box = Box(params.selected ?? "")
            zone.show(state(content(box)))
            return box
        }

        func widths() -> (tabs: CGFloat, folded: CGFloat) {
            var m = ShellPageBarView.Measures(tabs: 999, tabsFolded: 999)
            zone.measure(into: &m)
            return (m.tabs, m.tabsFolded)
        }

        func fold(_ folded: Bool) { zone.apply(ShellPageBarView.Verdicts(tabsFolded: folded)) }

        var plate: ShellBarPlate? { zone.view as? ShellBarPlate }
    }

    private func control(of plate: ShellBarPlate?, _ what: String = "the zone") throws -> NSSegmentedControl {
        try XCTUnwrap(plate?.content?.everyView(ofType: NSSegmentedControl.self).first,
                      "no segmented control under the plate of \(what)")
    }

    /// The whole strip's control and the folded one's, in that order; the zone is left unfolded.
    private func bothControls(_ rig: Rig) throws -> (full: NSSegmentedControl, folded: NSSegmentedControl) {
        rig.fold(false)
        let full = try control(of: rig.plate, "the whole strip")
        rig.fold(true)
        let folded = try control(of: rig.plate, "the folded strip")
        rig.fold(false)
        XCTAssertFalse(full === folded, "the whole strip and the folded one are one control")
        return (full, folded)
    }

    private func glasses(in plate: NSView?) -> [NSGlassEffectView] {
        plate?.subviews.compactMap { $0 as? NSGlassEffectView } ?? []
    }

    // MARK: - 1. The fold follows the layout

    func testTheTabsFoldExactlyWhenTheLayoutSaysAndAnswerBothWidthsWhileFolded() throws {
        let rig = Rig()
        rig.show()
        let bar = ShellPageBarView()
        var measures = ShellPageBarView.Measures()
        rig.zone.measure(into: &measures)
        guard measures.tabs != 0 || measures.tabsFolded != 0 else {
            XCTFail("the switcher was never mounted: its width read 0 folded and unfolded, and 0 fits")
            return
        }

        let want = try oracle(rig.params)
        XCTAssertEqual(measures.tabs, want.full, accuracy: 0.5, "the whole strip's width is not the oracle's")
        XCTAssertEqual(measures.tabs, 242, accuracy: 0.5, "the whole flat strip of three words moved from its reading")
        XCTAssertEqual(measures.tabsFolded, want.folded, accuracy: 0.5, "the folded width is not the oracle's")
        XCTAssertGreaterThan(measures.tabsFolded, 0, "the folded width is 0")
        XCTAssertLessThan(measures.tabsFolded, measures.tabs, "the folded strip is not narrower than the whole one")

        bar.measures = measures
        let plate0 = try XCTUnwrap(rig.plate, "the zone placed no plate for a page with tabs")
        bar.setView(plate0, for: .tabs)
        let zone = rig.zone
        bar.verdictsChanged = { [weak bar] verdicts in
            zone.apply(verdicts)
            bar?.setView(zone.view, for: .tabs)
        }

        let widths: [CGFloat] = Array(stride(from: 700, through: 120, by: -7))
            + Array(stride(from: 120, through: 700, by: 7))
        var sawFolded = false, sawWhole = false, checkedFolded = 0, checkedWhole = 0
        for width in widths {
            bar.place = ShellPageBarView.Place(cardMinX: 0, windowWidth: width, buttons: .null)
            bar.frame = NSRect(x: 0, y: 0, width: width, height: ShellBarLayout.height)
            bar.layoutSubtreeIfNeeded()

            let m = bar.measures
            let answer = ShellBarLayout.frames(for: ShellBarLayout.Input(
                barWidth: width, cardMinX: 0, windowWidth: width, nameWidth: m.name, tabsWidth: m.tabs,
                tabsFoldedWidth: m.tabsFolded, actionsWidth: m.actions, statusWidth: m.status,
                hasSearch: m.hasSearch, alwaysCollapseSearch: m.alwaysCollapseSearch,
                searchInUse: m.searchInUse, buttons: .null))
            XCTAssertEqual(zone.isFolded, answer.tabsFolded, "W \(width): the zone's fold is not the layout's verdict")
            XCTAssertTrue(zone.view === plate0, "W \(width): the fold changed the zone's plate")
            XCTAssertFalse(bar.needsLayout, "W \(width): the pass left a layout pending")
            if answer.tabsFolded { sawFolded = true } else { sawWhole = true }

            var again = ShellPageBarView.Measures(tabs: 999, tabsFolded: 999)
            zone.measure(into: &again)
            XCTAssertEqual(again.tabs, measures.tabs, accuracy: 0.001, "W \(width): the whole width moved with the fold")
            XCTAssertEqual(again.tabsFolded, measures.tabsFolded, accuracy: 0.001,
                           "W \(width): the folded width moved with the fold")

            guard answer.tabs.width > 0 else { continue }
            XCTAssertEqual(plate0.frame, answer.tabs, "W \(width): the plate is not where the layout put the tabs")
            XCTAssertEqual(plate0.content?.frame, plate0.bounds,
                           "W \(width): the strip was not laid out to its plate in the pass that swapped it")
            let strip = try control(of: plate0)
            let hosts = plate0.subviews.filter { !($0 is NSGlassEffectView) }
            XCTAssertEqual(hosts.count, 1, "W \(width): the plate holds \(hosts.count) hosts")
            if answer.tabsFolded {
                checkedFolded += 1
                XCTAssertEqual(strip.segmentCount, 1, "W \(width): the folded strip draws \(strip.segmentCount) segments")
                XCTAssertEqual(strip.label(forSegment: 0), "Updates", "W \(width): the folded strip's label")
                XCTAssertTrue(strip.showsMenuIndicator(forSegment: 0), "W \(width): the folded strip has no menu indicator")
                XCTAssertEqual(plate0.frame.width, measures.tabsFolded, accuracy: 0.5,
                               "W \(width): the plate is not as wide as the folded strip")
            } else {
                checkedWhole += 1
                XCTAssertEqual(strip.segmentCount, 3, "W \(width): the whole strip draws \(strip.segmentCount) segments")
                for index in 0..<strip.segmentCount {
                    XCTAssertFalse(strip.showsMenuIndicator(forSegment: index),
                                   "W \(width): segment \(index) keeps a menu indicator")
                }
                XCTAssertEqual(plate0.frame.width, measures.tabs, accuracy: 0.5,
                               "W \(width): the plate is not as wide as the whole strip")
            }
        }
        XCTAssertTrue(sawFolded, "the bar was wide enough at every width: nothing folded")
        XCTAssertTrue(sawWhole, "the bar was too narrow at every width: nothing stayed whole")
        XCTAssertGreaterThan(checkedFolded, 0, "no folded width gave the tabs room: the folded form was never read")
        XCTAssertGreaterThan(checkedWhole, 0, "no whole width gave the tabs room: the whole form was never read")
    }

    // MARK: - 2. Once per shape

    func testBothWidthsAreReadOncePerShapeAndARepublicationReadsNothing() throws {
        let rig = Rig()
        for _ in 0..<10 { rig.show() }
        XCTAssertEqual(rig.zone.measureCount, 1, "ten equal shows measured \(rig.zone.measureCount) times")
        XCTAssertEqual(rig.zone.redrawCount, 1, "ten equal shows re-rooted the hosts \(rig.zone.redrawCount) times")
        let base = rig.widths()
        XCTAssertGreaterThan(base.tabs, 0, "precondition: the base measured nothing")

        /// A change that moves a width: one more measure, one more redraw, the widths the oracle gives.
        func measuring(_ name: String, base prepare: (inout Params) -> Void = { _ in },
                       change: (Rig) -> Void,
                       check: ((_ before: (tabs: CGFloat, folded: CGFloat), _ after: (tabs: CGFloat, folded: CGFloat)) -> Void)? = nil) throws {
            let rig = Rig()
            prepare(&rig.params)
            rig.show()
            XCTAssertEqual(rig.zone.measureCount, 1, "\(name): precondition")
            let before = rig.widths()
            change(rig)
            XCTAssertEqual(rig.zone.measureCount, 2, "\(name): measured \(rig.zone.measureCount - 1) times after the change")
            XCTAssertEqual(rig.zone.redrawCount, 2, "\(name): re-rooted \(rig.zone.redrawCount - 1) times after the change")
            let after = rig.widths()
            let want = try oracle(rig.params)
            XCTAssertEqual(after.tabs, want.full, accuracy: 0.5, "\(name): the whole width is not the oracle's")
            XCTAssertEqual(after.folded, want.folded, accuracy: 0.5, "\(name): the folded width is not the oracle's")
            check?(before, after)
        }

        try measuring("a title", change: { $0.params.titles[1] = "Updates available"; $0.show() },
                      check: { XCTAssertGreaterThan($1.tabs, $0.tabs, "a longer title did not widen the strip") })
        try measuring("a symbol", base: { $0.style = .icons },
                      change: { $0.params.symbols[0] = "star"; $0.show() })
        try measuring("a dot", change: { $0.params.attention[2] = true; $0.show() },
                      check: { XCTAssertGreaterThan($1.tabs, $0.tabs, "a raised dot did not widen the strip") })
        try measuring("the style", change: { $0.params.style = .icons; $0.show() },
                      check: { XCTAssertLessThan($1.tabs, $0.tabs, "the glyph-only strip is not narrower than the words") })
        try measuring("the selected tab", change: { $0.params.selected = "search"; $0.show() },
                      check: { before, after in
                          XCTAssertEqual(after.tabs, before.tabs, accuracy: 0.5, "the selection moved the whole width")
                          XCTAssertNotEqual(after.folded, before.folded, accuracy: 0.5,
                                            "the folded width did not follow the selection")
                      })
        try measuring("the look", change: { $0.params.appearance = .liquidGlass; $0.show() },
                      check: { before, after in
                          XCTAssertEqual(before.tabs, 242, accuracy: 0.5, "the flat reading moved")
                          XCTAssertEqual(after.tabs, 254, accuracy: 0.5, "the glass reading moved")
                      })

        /// A change that moves no width: no measure, and a redraw only where something drawn moved.
        func still(_ name: String, redraws: Bool, base prepare: (inout Params) -> Void = { _ in },
                   change: (Rig) -> Void) {
            let rig = Rig()
            prepare(&rig.params)
            rig.show()
            let before = rig.widths()
            change(rig)
            XCTAssertEqual(rig.zone.measureCount, 1, "\(name): measured again")
            XCTAssertEqual(rig.zone.redrawCount, redraws ? 2 : 1,
                           "\(name): \(redraws ? "did not re-root" : "re-rooted") the hosts (\(rig.zone.redrawCount))")
            let after = rig.widths()
            XCTAssertEqual(after.tabs, before.tabs, accuracy: 0.001, "\(name): the whole width moved")
            XCTAssertEqual(after.folded, before.folded, accuracy: 0.001, "\(name): the folded width moved")
        }

        still("the page leaving its live state", redraws: false, change: { $0.params.isLive = false; $0.show() })
        still("the page dimming", redraws: true, base: { $0.isLive = false },
              change: { $0.params.isDimmed = true; $0.show() })
        still("the tabs disabled", redraws: true, change: { $0.params.tabsEnabled = false; $0.show() })
        still("the window going inactive", redraws: false, change: { $0.params.appearsActive = false; $0.show() })
        still("the bar's menu", redraws: true, change: { $0.zone.barMenu = NSMenu(title: "bar") })
        // The selected tab keeps its id: a selection that moved with the id would be a change of shape.
        still("new ids under the same words", redraws: true,
              change: { $0.params.ids = ["other", "updates", "else"]; $0.show() })
        still("a note under a raised dot", redraws: true, base: { $0.attention[2] = true },
              change: { $0.params.notes[2] = "Needs a look"; $0.show() })
    }

    // MARK: - 3. A press

    private func press(_ rig: Rig, segment index: Int) throws {
        let strip = try control(of: rig.plate)
        if rig.zone.isFolded {
            let coordinator = try XCTUnwrap(strip.target as? HelmToolbarSwitcher<String>.Coordinator,
                                            "the folded control's target is not the switcher's coordinator")
            let menu = try XCTUnwrap(coordinator.tabsMenu, "the folded strip has no tabs menu")
            XCTAssertEqual(menu.items.count, 3, "the tabs menu does not name every tab")
            let item = menu.items[index]
            let action = try XCTUnwrap(item.action, "a tabs menu item has no action")
            NSApplication.shared.sendAction(action, to: item.target, from: item)
        } else {
            strip.selectedSegment = index
            strip.sendAction(strip.action, to: strip.target)
        }
    }

    func testAPressRunsThePagesHandlerOnlyWhileLiveAndEnabled() throws {
        struct Row {
            let name: String
            let live: Bool
            let dimmed: Bool
            let tabsEnabled: Bool
            let taken: Bool
            let enabled: Bool
        }
        let rows = [
            Row(name: "live and enabled", live: true, dimmed: false, tabsEnabled: true, taken: true, enabled: true),
            Row(name: "live, tabs disabled", live: true, dimmed: false, tabsEnabled: false, taken: false, enabled: false),
            Row(name: "not live, not dimmed", live: false, dimmed: false, tabsEnabled: true, taken: false, enabled: true),
            Row(name: "not live, dimmed", live: false, dimmed: true, tabsEnabled: true, taken: false, enabled: false),
        ]
        for folded in [false, true] {
            for row in rows {
                let form = folded ? "folded" : "whole"
                let rig = Rig()
                rig.params.isLive = row.live
                rig.params.isDimmed = row.dimmed
                rig.params.tabsEnabled = row.tabsEnabled
                let box = rig.show()
                rig.fold(folded)
                let strip = try control(of: rig.plate)
                XCTAssertEqual(strip.isEnabled, row.enabled, "\(row.name), \(form): the control's enabled state")

                try press(rig, segment: 2)
                if row.taken {
                    XCTAssertEqual(box.sets, ["search"], "\(row.name), \(form): the press did not write the tab once")
                } else {
                    XCTAssertEqual(box.sets, [], "\(row.name), \(form): a refused press wrote \(box.sets)")
                    let host = try XCTUnwrap(rig.plate?.content)
                    host.layoutSubtreeIfNeeded()
                    if folded {
                        XCTAssertEqual(strip.label(forSegment: 0), "Updates", "\(row.name), \(form): the folded label moved")
                    } else {
                        XCTAssertEqual(strip.selectedSegment, 1, """
                            \(row.name), \(form): the strip keeps showing the refused tab \(strip.selectedSegment)
                            """)
                    }
                    // The next live show with the old selection must not leave the refused tab showing.
                    rig.params.isLive = true
                    rig.params.isDimmed = false
                    rig.params.tabsEnabled = true
                    rig.show()
                    if !folded {
                        XCTAssertEqual(try control(of: rig.plate).selectedSegment, 1,
                                       "\(row.name): a later live show kept the refused tab")
                    }
                }
            }
        }

        // A page republishing with a binding of its own and an equal drawing: a press reaches the new one.
        for folded in [false, true] {
            let rig = Rig()
            let old = rig.show()
            let new = rig.show()
            rig.fold(folded)
            try press(rig, segment: 2)
            XCTAssertEqual(new.sets, ["search"], "\(folded ? "folded" : "whole"): the newest binding was not written")
            XCTAssertEqual(old.sets, [], "\(folded ? "folded" : "whole"): the press went to a binding the page replaced")
        }
    }

    /// AppKit has already moved the selected segment when the action fires, so a press the zone refuses has to
    /// put the strip back before it returns: read here with no layout call of the test's own in between, which
    /// would otherwise let the host catch up by itself.
    func testARefusedPressPutsTheStripBackBeforeItReturns() throws {
        let rows: [(name: String, live: Bool, dimmed: Bool, tabsEnabled: Bool)] = [
            ("not live", false, false, true),
            ("live, tabs disabled", true, false, false),
        ]
        for row in rows {
            let rig = Rig()
            rig.params.isLive = row.live
            rig.params.isDimmed = row.dimmed
            rig.params.tabsEnabled = row.tabsEnabled
            let box = rig.show()
            let strip = try control(of: rig.plate)
            XCTAssertEqual(strip.selectedSegment, 1, "\(row.name): precondition: the strip does not show the selected tab")

            try press(rig, segment: 2)
            XCTAssertEqual(box.sets, [], "\(row.name): a refused press wrote \(box.sets)")
            XCTAssertEqual(strip.selectedSegment, 1, "\(row.name): the strip kept showing the refused tab on return")
        }
    }

    /// A press on a control or a menu item kept from the page before reaches no handler of the page on show:
    /// a show without tabs returns before the hosts are re-rooted, so the old segments stay alive in them and
    /// their binding reads the newest state, whose handler is live and enabled.
    func testAPressNamingATabThePageOnShowDoesNotHoldReachesNoHandler() throws {
        for folded in [false, true] {
            let form = folded ? "folded menu item" : "whole strip"
            let rig = Rig()
            let first = rig.show()
            let (full, foldedControl) = try bothControls(rig)
            let coordinator = try XCTUnwrap(foldedControl.target as? HelmToolbarSwitcher<String>.Coordinator,
                                            "\(form): the folded control's target is not the switcher's coordinator")
            let menu = try XCTUnwrap(coordinator.tabsMenu, "\(form): the folded strip has no tabs menu")
            XCTAssertEqual(menu.items.count, 3, "\(form): the tabs menu does not name every tab")
            let kept = menu.items

            func pressKept(_ index: Int) {
                if folded {
                    let item = kept[index]
                    NSApplication.shared.sendAction(item.action!, to: item.target, from: item)
                } else {
                    full.selectedSegment = index
                    full.sendAction(full.action, to: full.target)
                }
            }

            // The subject: on the page that holds the tabs the same press writes its box.
            pressKept(2)
            XCTAssertEqual(first.sets, ["search"], "\(form): precondition: the press on the page with the tabs wrote \(first.sets)")

            // A live page with no tabs and a selection binding of its own.
            let next = Box("updates")
            let binding = Binding<String>(get: { next.value }, set: { next.sets.append($0); next.value = $0 })
            rig.zone.show(rig.state(HelmPageToolbarContent(tabs: [], selectedTab: binding, tabsEnabled: true)))
            XCTAssertNil(rig.zone.view, "\(form): precondition: a page with an empty tab list kept a view")

            pressKept(0)
            XCTAssertEqual(next.sets, [], "\(form): a press naming a tab the page does not hold wrote \(next.sets) to its binding")
        }
    }

    /// A refused press on a page whose selection names no tab leaves no segment lit: AppKit has already lit the
    /// pressed one, and the zone puts the strip back before it returns, read here with no layout call of the test's own.
    func testARefusedPressOnAPageWhoseSelectionNamesNoTabLeavesNoSegmentLit() throws {
        let rows: [(name: String, selected: String?, live: Bool)] = [
            ("no selected tab", nil, true),
            ("not live, a selection naming no tab", "nonesuch", false),
        ]
        for row in rows {
            let rig = Rig()
            rig.params.selected = row.selected
            rig.params.isLive = row.live
            let box = rig.show()
            XCTAssertFalse(rig.zone.isFolded, "\(row.name): precondition: the strip is folded")
            let strip = try control(of: rig.plate)
            XCTAssertEqual(strip.segmentCount, 3, "\(row.name): precondition: the strip does not draw every tab")
            XCTAssertEqual(strip.selectedSegment, -1, "\(row.name): precondition: a segment is lit before the press")

            try press(rig, segment: 2)
            XCTAssertEqual(box.sets, [], "\(row.name): a refused press wrote \(box.sets)")
            XCTAssertEqual(strip.selectedSegment, -1, "\(row.name): the strip kept the refused tab lit on return")
        }
    }

    // MARK: - 4. No tabs

    func testAPageWithoutTabsPlacesNothingAndAnswersZero() throws {
        let rig = Rig()
        rig.show()
        let plate = try XCTUnwrap(rig.plate, "precondition: a page with tabs placed no plate")
        XCTAssertGreaterThan(rig.widths().tabs, 0, "precondition: a page with tabs measured 0")

        rig.zone.show(rig.state(nil))
        XCTAssertNil(rig.zone.view, "a page with no content kept a view")
        var empty = rig.widths()
        XCTAssertEqual(empty.tabs, 0, "a page with no content kept a width")
        XCTAssertEqual(empty.folded, 0, "a page with no content kept a folded width")

        rig.params.ids = []; rig.params.titles = []; rig.params.symbols = []
        rig.params.attention = []; rig.params.notes = []; rig.params.selected = nil
        rig.zone.show(rig.state(rig.content(Box(""))))
        XCTAssertNil(rig.zone.view, "a page with an empty tab list kept a view")
        empty = rig.widths()
        XCTAssertEqual(empty.tabs, 0, "an empty tab list kept a width")
        XCTAssertEqual(empty.folded, 0, "an empty tab list kept a folded width")

        let redraws = rig.zone.redrawCount
        rig.params = Params()
        rig.show()
        XCTAssertTrue(rig.zone.view === plate, "coming back to a page with tabs built another plate")
        XCTAssertGreaterThan(rig.widths().tabs, 0, "coming back measured no width")
        XCTAssertGreaterThan(rig.widths().folded, 0, "coming back measured no folded width")
        XCTAssertGreaterThan(rig.zone.redrawCount, redraws, "coming back drew nothing: the zone kept the old drawing")

        // No selection, and a selection that names no tab: the strip is whole and never folds.
        for (name, selected) in [("no selected tab", String?.none), ("a selection naming no tab", "nonesuch")] {
            let rig = Rig()
            rig.params.selected = selected
            rig.show()
            XCTAssertNotNil(rig.zone.view, "\(name): the zone placed nothing")
            let widths = rig.widths()
            XCTAssertGreaterThan(widths.tabs, 0, "\(name): the whole width is 0")
            XCTAssertEqual(widths.folded, 0, "\(name): the folded width is not 0, so the layout could fold to nothing")
        }
    }

    // MARK: - 5. The look and the window

    func testTheZoneDrawsByTheLookItIsHandedAndThePlateFollowsTheWindow() throws {
        let rig = Rig()
        rig.show()
        let plate = try XCTUnwrap(rig.plate, "no plate")
        let (full, folded) = try bothControls(rig)
        XCTAssertEqual(plate.barAppearance, .flat)
        XCTAssertTrue(full.cell is HelmFlatSegmentedCell, "the whole strip's cell is \(String(describing: full.cell))")
        XCTAssertTrue(folded.cell is HelmFlatSegmentedCell, "the folded strip's cell is \(String(describing: folded.cell))")
        XCTAssertEqual(glasses(in: plate).count, 0, "a flat plate holds glass")

        rig.params.appearance = .liquidGlass
        rig.show()
        let again = try bothControls(rig)
        XCTAssertTrue(rig.plate === plate, "the look flip built another plate")
        XCTAssertTrue(again.full === full && again.folded === folded, "the look flip built other controls")
        XCTAssertEqual(plate.barAppearance, .liquidGlass)
        for (name, strip) in [("whole", again.full), ("folded", again.folded)] {
            let cell = try XCTUnwrap(strip.cell, "the \(name) strip has no cell")
            XCTAssertTrue(type(of: cell) == NSSegmentedCell.self,
                          "the \(name) strip wears \(type(of: cell)) under the glass look, not exactly NSSegmentedCell")
        }
        XCTAssertEqual(glasses(in: plate).count, 1, "a glass plate of an active window holds \(glasses(in: plate).count) glass views")

        rig.params.appearance = .flat
        rig.show()
        let back = try bothControls(rig)
        XCTAssertTrue(back.full === full && back.folded === folded, "flipping back built other controls")
        XCTAssertTrue(back.full.cell is HelmFlatSegmentedCell && back.folded.cell is HelmFlatSegmentedCell,
                      "flipping back did not return the flat cell")
        XCTAssertEqual(glasses(in: plate).count, 0)

        // An inactive window dims the plate by the name zone's number under both looks.
        for look in HelmBarAppearance.allCases {
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let rig = Rig()
                rig.params.appearance = look
                rig.show()
                let plate = try XCTUnwrap(rig.plate)
                plate.appearance = NSAppearance(named: name)
                XCTAssertTrue(plate.isActive, "\(look), \(name.rawValue): precondition, the plate starts inactive")
                XCTAssertEqual(plate.alphaValue, 1, accuracy: 0.0001, "\(look), \(name.rawValue): an active plate is dimmed")
                XCTAssertEqual(glasses(in: plate).count, look == .liquidGlass ? 1 : 0)

                rig.params.appearsActive = false
                rig.show()
                let dim = CGFloat(helmNameZoneInactiveOpacity(dark: name == .darkAqua, titlebarIsTransparent: true))
                XCTAssertLessThan(dim, 1, "precondition: the name zone's number is 1")
                XCTAssertFalse(plate.isActive, "\(look), \(name.rawValue): the plate was not told the window is inactive")
                XCTAssertEqual(plate.alphaValue, dim, accuracy: 0.0001,
                               "\(look), \(name.rawValue): an inactive plate is not dimmed by the name zone's number")
                XCTAssertEqual(glasses(in: plate).count, 0, "\(look), \(name.rawValue): an inactive plate holds glass")
            }
        }
    }

    // MARK: - 6. The bar's menu

    func testTheBarsMenuReachesBothFormsAndAChangeWhileFoldedReachesTheFoldedOne() throws {
        let rig = Rig()
        rig.show()
        let (full, folded) = try bothControls(rig)
        XCTAssertNil(full.menu, "precondition: the strip has a menu before it was handed one")
        XCTAssertNil(folded.menu, "precondition: the folded strip has a menu before it was handed one")

        let menu = NSMenu(title: "bar")
        rig.zone.barMenu = menu
        XCTAssertTrue(full.menu === menu, "the whole strip did not get the bar's menu")
        XCTAssertTrue(folded.menu === menu, "the folded strip did not get the bar's menu")

        rig.zone.barMenu = nil
        XCTAssertNil(full.menu, "the whole strip kept the menu after it was withdrawn")
        XCTAssertNil(folded.menu, "the folded strip kept the menu after it was withdrawn")

        // While folded, a change of a title and of the selection reaches the folded control in the same show.
        rig.fold(true)
        XCTAssertEqual(folded.label(forSegment: 0), "Updates", "precondition: the folded label")
        rig.params.titles[1] = "Renewed"
        rig.show()
        XCTAssertTrue(rig.plate?.content?.everyView(ofType: NSSegmentedControl.self).first === folded,
                      "precondition: the folded control is not the one on the plate")
        XCTAssertEqual(folded.label(forSegment: 0), "Renewed", "a title changed while folded did not reach the folded label")
        rig.params.selected = "search"
        rig.show()
        XCTAssertEqual(folded.label(forSegment: 0), "Search", "a selection changed while folded did not reach the folded label")
    }

    // MARK: - 7. No pass of its own

    @MainActor
    private final class InertZone: ShellBarZone {
        var view: NSView?
        var measuresMoved: (() -> Void)?
        func show(_ state: ShellBarZoneState) {}
        func measure(into measures: inout ShellPageBarView.Measures) {}
        func apply(_ verdicts: ShellPageBarView.Verdicts) {}
    }

    func testTheZoneAsksForNoPassOfItsOwn() throws {
        let zone = ShellBarTabs(titlebarIsTransparent: true, labelStyle: { .text })
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let bar = ShellPageBar(model: model, channel: channel, tabs: zone, actions: InertZone(),
                               search: InertZone(), titlebarIsTransparent: true)
        var calls = 0
        zone.measuresMoved = { calls += 1 }

        let selected = Box("updates")
        func declare(_ titles: [String]) {
            let tabs = zip(["installed", "updates", "search"], titles).map {
                HelmToolbarTab(id: $0, title: $1, symbol: "circle")
            }
            let binding = Binding(get: { selected.value }, set: { selected.value = $0 })
            channel.declare(HelmPageToolbarContent(tabs: tabs, selectedTab: binding),
                            token: "general", generation: channel.nextGeneration())
        }
        declare(["Installed", "Updates", "Search"])
        XCTAssertEqual(bar.presentation, ShellPageBar.Presentation.page(key: "general", isLive: true, isDimmed: false), "precondition: the page is not shown")
        let plate = try XCTUnwrap(zone.view, "the page's tabs reached no zone view")
        XCTAssertTrue(bar.view.view(for: .tabs) === plate, "precondition: the bar does not hold the zone's view")
        XCTAssertGreaterThan(bar.view.measures.tabs, 0, "the bar collected no tabs width")

        var foldedPass = false
        for width in stride(from: 900, through: 150, by: -50) {
            bar.view.place = ShellPageBarView.Place(cardMinX: 0, windowWidth: CGFloat(width), buttons: .null)
            bar.view.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: ShellBarLayout.height)
            bar.view.layoutSubtreeIfNeeded()
            if zone.isFolded, !foldedPass {
                foldedPass = true
                XCTAssertFalse(bar.view.needsLayout, "the pass that folded left a layout pending")
                XCTAssertTrue(bar.view.view(for: .tabs) === zone.view, "the bar does not hold the zone's view after the fold")
            }
        }
        XCTAssertTrue(foldedPass, "the bar was wide enough at every width: nothing folded")

        declare(["Installed", "Updates available", "Search"])
        bar.setWindowAppearsActive(false)
        bar.setWindowAppearsActive(true)
        bar.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(bar.view.needsLayout, "a republication left a layout pending")
        XCTAssertTrue(bar.view.view(for: .tabs) === zone.view, "the bar lost the zone's view")
        XCTAssertEqual(calls, 0, "the zone asked for a pass of its own \(calls) times")
    }
}
