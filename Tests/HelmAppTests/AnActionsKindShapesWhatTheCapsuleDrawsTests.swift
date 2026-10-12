import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Three shapes an action can take beyond a plain button, read off the page bar's actions zone rather
/// than off the source**, through the bar and the channel rather than by constructing
/// `HelmToolbarActionsModel.Entry` by hand:
/// `ShellBarActions.entries(for:appearance:)` is where the page bar turns `HelmToolbarAction.Kind` into
/// `HelmToolbarActionsModel.EntryKind` (the earlier toolbar's `SettingsToolbar.actionEntries(for:look:)` is a
/// second copy, which this file does not read), and a test that skips it would prove nothing about whether
/// that translation is actually wired in.
///
/// The page is declared on the channel of a real page bar in a window (`LivePageToolbarFixture`), and what
/// the zone holds is read from the zone's own model. The zone has no overflow form: the bar folds its tabs
/// and its search when room runs short and never the capsule, and the bar's menu (`ShellBarMenu.fill`)
/// carries no page actions, so a toggle's state and a menu action's ticks are read from the model's entries.
@MainActor
final class AnActionsKindShapesWhatTheCapsuleDrawsTests: XCTestCase {

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var fixtures: [LivePageToolbarFixture] = []

    /// The bar reads these when it is built, so they are pinned before a fixture is and put back after.
    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.barAppearance = .flat
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
    }

    private func makeBar(_ token: String) -> LivePageToolbarFixture {
        let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: 1060, height: 700)
        fixtures.append(fx)
        return fx
    }

    /// The actions zone's view, found by a walk of the bar the window holds and held to be the fixture's
    /// own zone, so a zone that drew into no window cannot be read by accident.
    private func capsule(_ fx: LivePageToolbarFixture) -> NSView? {
        let found = fx.mount.window?.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        guard let view = found?.view(for: .actions), view === fx.pageBar.actions.view else { return nil }
        return view
    }

    private func declaredEntry(_ id: String, in fx: LivePageToolbarFixture) -> HelmToolbarActionsModel.Entry? {
        fx.pageBar.actions.model.declared.first { $0.id == id }
    }

    // MARK: - Toggle

    /// **The model entry is `.toggle(isOn:)` and follows the page's own `isOn` both ways** — no page declares
    /// one today (`command grep -rn -A3 'HelmToolbarAction(' Sources/Modules | command grep -c 'isOn:'`;
    /// Hosts' Table/Plain-text pair moved to `.segmented`, the owner's report, 2026-09-25), so this proves
    /// the wiring itself: `ShellBarActions.entries(for:appearance:)` still has to carry `isOn` through for
    /// whichever page reaches for a toggle next. Declared on, then off: a translation that always said one
    /// of them would pass the first read alone.
    func testAToggleActionsEntryCarriesIsOn() throws {
        let fx = makeBar("test.toggle")
        for isOn in [true, false] {
            fx.channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "mode", title: "Plain text", symbol: "text.alignleft",
                                  isOn: isOn) {}
            ]), token: "test.toggle", generation: fx.channel.nextGeneration())
            fx.settle(10)

            XCTAssertNotNil(capsule(fx), "the bar in the window holds no actions zone")
            let entry = try XCTUnwrap(declaredEntry("mode", in: fx), "the toggle action never reached the capsule")
            XCTAssertEqual(entry.kind, .toggle(isOn: isOn), """
                a toggle action's own kind lost isOn on the way into the capsule's model — read \
                \(entry.kind) instead
                """)
        }
    }

    // MARK: - Menu

    /// **A menu action's items carry their own checks into the model, and pressing one runs its own
    /// `perform` and nothing else's** — Leftovers' kind filter is the first caller, one checkmark per
    /// `StaleKind`.
    func testAMenuActionsItemsCarryTheirOwnChecksAndPressTheirOwnClosure() throws {
        let fx = makeBar("test.menu")

        final class Pressed { var ids: [String] = [] }
        let pressed = Pressed()
        fx.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease", menu: [
                HelmToolbarMenuItem(id: "cache", title: "Cache", isOn: true) { pressed.ids.append("cache") },
                HelmToolbarMenuItem(id: "log", title: "Log", isOn: false) { pressed.ids.append("log") }
            ])
        ]), token: "test.menu", generation: fx.channel.nextGeneration())
        fx.settle(10)

        XCTAssertNotNil(capsule(fx), "the bar in the window holds no actions zone")
        let entry = try XCTUnwrap(declaredEntry("kinds", in: fx), "the menu action never reached the capsule")
        XCTAssertEqual(entry.kind, .menu([
            .init(id: "cache", title: "Cache", isOn: true, isEnabled: true),
            .init(id: "log", title: "Log", isOn: false, isEnabled: true)
        ]), "a menu action's own items lost their checks on the way into the capsule's model")

        fx.pageBar.actions.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["log"], "pressing one item ran the wrong closure")
        fx.pageBar.actions.model.pressItem("kinds", "cache")
        XCTAssertEqual(pressed.ids, ["log", "cache"], "pressing the other item ran the wrong closure")
    }

    /// **The capsule's route into a menu item — `model.pressItem` — runs the item's closure on a live bar and
    /// drops it once the bar is frozen.** This is how a person actually picks a kind in Leftovers' filter.
    /// The frozen bar holds a closure-free copy of the page, so a press there has no closure to run whatever
    /// the zone decides; the zone's own refusal is held below, with the live closures still in the zone.
    func testPressItemRunsOnALiveBarAndIsSilentOnceTheBarIsFrozen() throws {
        let fx = makeBar("test.pressItem")

        final class Pressed { var ids: [String] = [] }
        let pressed = Pressed()
        let generation = fx.channel.nextGeneration()
        fx.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease", menu: [
                HelmToolbarMenuItem(id: "log", title: "Log", isOn: false) { pressed.ids.append("log") }
            ])
        ]), token: "test.pressItem", generation: generation)
        fx.settle(10)

        XCTAssertNotNil(capsule(fx), "the bar in the window holds no actions zone")
        fx.pageBar.actions.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["log"], """
            model.pressItem did not run the item's own closure on a live bar — the capsule's own route \
            into a menu item is untested without this
            """)

        fx.channel.withdraw(token: "test.pressItem", generation: generation)
        fx.pageBar.layout()
        XCTAssertEqual(fx.bar.presentation,
                       .page(key: "test.pressItem", isLive: false, isDimmed: true),
                       "precondition: the bar does not show the frozen copy of the page")
        XCTAssertNotNil(declaredEntry("kinds", in: fx), "precondition: the frozen zone no longer holds the entry")
        fx.pageBar.actions.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["log"], """
            model.pressItem ran an item's closure after its bar was withdrawn — a frozen bar's capsule must \
            refuse a press
            """)
    }

    /// **A zone told its page is not live runs nothing, even with the page's own closures still in it.** The
    /// bar hands a frozen zone a stripped copy, so the test above cannot tell the zone's refusal from the
    /// copy's missing closure; this hands the zone the live closures with `isLive: false`.
    func testAZoneToldThePageIsNotLiveRunsNoItemAndNoButton() throws {
        let zone = ShellBarActions(titlebarIsTransparent: true)
        final class Pressed { var ids: [String] = [] }
        let pressed = Pressed()
        let content = HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "go", title: "Go", symbol: "play") { pressed.ids.append("go") },
            HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease", menu: [
                HelmToolbarMenuItem(id: "log", title: "Log", isOn: false) { pressed.ids.append("log") }
            ])
        ])
        func state(isLive: Bool) -> ShellBarZoneState {
            ShellBarZoneState(content: content, isLive: isLive, isDimmed: !isLive, appearsActive: true,
                              appearance: .flat, animated: false)
        }
        zone.show(state(isLive: true))
        zone.model.press("go")
        zone.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["go", "log"], "precondition: a live zone does not run its page's closures")

        zone.show(state(isLive: false))
        zone.model.press("go")
        zone.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["go", "log"], "a zone told its page is not live still ran a closure")
    }

    // MARK: - Busy

    /// **`isBusy` reaches the capsule's own entry whatever the kind is** — Uninstaller's Refresh is the
    /// first caller that spins.
    func testIsBusyReachesTheDeclaredEntry() throws {
        let fx = makeBar("test.busy")
        fx.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                              isBusy: true) {}
        ]), token: "test.busy", generation: fx.channel.nextGeneration())
        fx.settle(10)

        XCTAssertNotNil(capsule(fx), "the bar in the window holds no actions zone")
        let entry = try XCTUnwrap(declaredEntry("refresh", in: fx), "the busy action never reached the capsule")
        XCTAssertTrue(entry.isBusy, "isBusy: true at declaration did not reach the capsule's own entry")
    }

    // MARK: - A menu entry's own size

    /// **A `.menu` entry must cost the reserve exactly what every other kind does — one
    /// `HelmToolbarActionsCapsule.side` square — never AppKit's own bordered pull-down bezel.** The reserve is
    /// every *declared* action laid out at that one size regardless of which are visible
    /// (`HelmToolbarActionsCapsule`'s own header); in the earlier toolbar, `SettingsToolbar`, a `Menu` with no
    /// `.menuStyle(.button)` drew as a 60×44 pull-down instead of a 36×36 glyph, so the hosted view's
    /// intrinsic size moved with `visibleIDs` exactly the way the whole capsule exists to prevent. On the
    /// page bar, removing both `.menuStyle(.button)` and `.buttonStyle(.plain)` from the `.menu` case in
    /// `HelmToolbarActionsCapsule.entryControl(_:)` turned this test red (72.0 against 96.0 and 36.0 against
    /// 44.0); removing only `.menuStyle(.button)` left it green.
    func testAMenuEntryCostsTheSameReserveAsEveryOtherKindAcrossVisibility() throws {
        let fx = makeBar("test.menuSize")
        let token = "test.menuSize"

        func declare(menuVisible: Bool, buttonVisible: Bool) {
            fx.channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "scan", title: "Scan", symbol: "arrow.clockwise",
                                  isVisible: buttonVisible) {},
                HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease",
                                  isVisible: menuVisible, menu: [
                    HelmToolbarMenuItem(id: "one", title: "One", isOn: true) {}
                ])
            ]), token: token, generation: fx.channel.nextGeneration())
            fx.settle(10)
        }
        func size() throws -> NSSize {
            try XCTUnwrap(capsule(fx), "the bar in the window holds no actions zone").fittingSize
        }

        declare(menuVisible: true, buttonVisible: true)
        XCTAssertEqual(fx.pageBar.actions.model.visibleIDs, ["scan", "kinds"], "precondition: both actions visible")
        let bothVisible = try size()
        XCTAssertGreaterThan(bothVisible.width, 0, "precondition: the capsule has no width")

        declare(menuVisible: false, buttonVisible: true)
        XCTAssertEqual(fx.pageBar.actions.model.visibleIDs, ["scan"], "precondition: only the button visible")
        let onlyButtonVisible = try size()
        XCTAssertEqual(onlyButtonVisible.width, bothVisible.width, accuracy: 0.5, """
            hiding the menu action changed the capsule's own width \
            (\(onlyButtonVisible.width) vs \(bothVisible.width)) — the reserve is meant to hold \
            it constant regardless of which declared actions are visible
            """)
        XCTAssertEqual(onlyButtonVisible.height, bothVisible.height, accuracy: 0.5, """
            hiding the menu action changed the capsule's own height \
            (\(onlyButtonVisible.height) vs \(bothVisible.height))
            """)

        declare(menuVisible: true, buttonVisible: false)
        XCTAssertEqual(fx.pageBar.actions.model.visibleIDs, ["kinds"], "precondition: only the menu visible")
        let onlyMenuVisible = try size()
        XCTAssertEqual(onlyMenuVisible.width, bothVisible.width, accuracy: 0.5, """
            showing only the menu action changed the capsule's own width \
            (\(onlyMenuVisible.width) vs \(bothVisible.width)) — on the page bar this test was red \
            with both `.menuStyle(.button)` and `.buttonStyle(.plain)` removed from the `.menu` \
            case, and green with `.menuStyle(.button)` alone removed
            """)
        XCTAssertEqual(onlyMenuVisible.height, bothVisible.height, accuracy: 0.5, """
            showing only the menu action changed the capsule's own height \
            (\(onlyMenuVisible.height) vs \(bothVisible.height))
            """)

        declare(menuVisible: false, buttonVisible: false)
        let neitherVisible = try size()
        XCTAssertEqual(neitherVisible.width, bothVisible.width, accuracy: 0.5, """
            hiding both actions changed the capsule's own width \
            (\(neitherVisible.width) vs \(bothVisible.width)) — the reserve is the *declared* \
            set, not the visible one
            """)
    }
}
