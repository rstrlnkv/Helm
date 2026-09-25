import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Three shapes an action can take beyond a plain button, read off the real
/// window rather than off the source** — the same reason
/// `TheAttachedToolbarNeverChurnsOnAPageSwitchTests` gives for going through
/// `SettingsToolbar` and the channel rather than constructing
/// `HelmToolbarActionsModel.Entry` by hand: `SettingsToolbar.actionEntries(for:)`
/// is the one place `HelmToolbarAction.Kind` is turned into
/// `HelmToolbarActionsModel.EntryKind`, and a test that skips it would prove
/// nothing about whether that translation is actually wired in.
@MainActor
final class AnActionsKindShapesWhatTheCapsuleDrawsTests: XCTestCase {

    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func makeToolbar() -> Fixture {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Fixture(toolbar: toolbar, model: model, channel: channel, window: window)
    }

    private func actionsItem(_ window: NSWindow) -> NSToolbarItem? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" }
    }

    private func declaredEntry(_ id: String, in item: NSToolbarItem?) -> HelmToolbarActionsModel.Entry? {
        (item?.view as? NSHostingView<HelmToolbarActionsCapsule>)?.rootView.model.declared
            .first { $0.id == id }
    }

    // MARK: - Toggle

    /// **The model entry is `.toggle(isOn:)`, and the overflow menu form's own
    /// `state` follows it** — Hosts' Table/Plain-text pair is the first
    /// caller, one glyph on when its own mode is showing.
    func testAToggleActionsEntryCarriesIsOnAndTheOverflowFormsStateFollowsIt() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.toggle")
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "mode", title: "Plain text", symbol: "text.alignleft",
                              isOn: true) {}
        ]), token: "test.toggle", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let item = try XCTUnwrap(actionsItem(fixture.window), "no single actions item on the toolbar")
        let entry = try XCTUnwrap(declaredEntry("mode", in: item), "the toggle action never reached the capsule")
        XCTAssertEqual(entry.kind, .toggle(isOn: true), """
            a toggle action's own kind lost isOn on the way into the capsule's model — read \
            \(entry.kind) instead
            """)

        // One visible action: the overflow floor is that action's own item,
        // whose `state` has to answer for `isOn` the way a plain button's
        // never had to.
        XCTAssertEqual(item.menuFormRepresentation?.state, .on, """
            the overflow menu form for a toggle action does not read the toggle's own state
            """)
        _ = fixture.toolbar
    }

    // MARK: - Menu

    /// **A menu action's own submenu carries each item's check, and pressing
    /// one runs its own `perform` and nothing else's** — Leftovers' kind
    /// filter is the first caller, one checkmark per `StaleKind`.
    func testAMenuActionsItemsCarryTheirOwnChecksAndPressTheirOwnClosure() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.menu")

        final class Pressed { var ids: [String] = [] }
        let pressed = Pressed()
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease", menu: [
                HelmToolbarMenuItem(id: "cache", title: "Cache", isOn: true) { pressed.ids.append("cache") },
                HelmToolbarMenuItem(id: "log", title: "Log", isOn: false) { pressed.ids.append("log") }
            ])
        ]), token: "test.menu", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let item = try XCTUnwrap(actionsItem(fixture.window), "no single actions item on the toolbar")
        let entry = try XCTUnwrap(declaredEntry("kinds", in: item), "the menu action never reached the capsule")
        XCTAssertEqual(entry.kind, .menu([
            .init(id: "cache", title: "Cache", isOn: true, isEnabled: true),
            .init(id: "log", title: "Log", isOn: false, isEnabled: true)
        ]), "a menu action's own items lost their checks on the way into the capsule's model")

        let submenu = try XCTUnwrap(item.menuFormRepresentation?.submenu,
                                    "one visible menu action should answer as its own submenu")
        XCTAssertEqual(submenu.items.map(\.title), ["Cache", "Log"])
        XCTAssertEqual(submenu.items.map(\.state), [.on, .off], """
            the overflow submenu's own ticks do not follow each item's isOn
            """)

        let logItem = try XCTUnwrap(submenu.items.first { $0.title == "Log" })
        if let action = logItem.action { _ = logItem.target?.perform(action, with: logItem) }
        XCTAssertEqual(pressed.ids, ["log"], "pressing one item in the submenu ran the wrong closure")
        _ = fixture.toolbar
    }

    /// **The capsule's own route into a menu item — `model.pressItem`, not
    /// only the overflow submenu's `actionMenuSubitemPressed` — runs the
    /// item's closure on a live bar and drops it once the bar is frozen.**
    /// This is how a person actually picks a kind in Leftovers' filter: the
    /// button drawn in the toolbar itself, never the «»» overflow.
    func testPressItemRunsOnALiveBarAndIsSilentOnceTheBarIsFrozen() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.pressItem")

        final class Pressed { var ids: [String] = [] }
        let pressed = Pressed()
        let generation = fixture.channel.nextGeneration()
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease", menu: [
                HelmToolbarMenuItem(id: "log", title: "Log", isOn: false) { pressed.ids.append("log") }
            ])
        ]), token: "test.pressItem", generation: generation)
        fixture.window.layoutIfNeeded()

        let item = try XCTUnwrap(actionsItem(fixture.window), "no single actions item on the toolbar")
        let hosting = try XCTUnwrap(item.view as? NSHostingView<HelmToolbarActionsCapsule>,
                                    "the actions item has no hosted capsule")
        hosting.rootView.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["log"], """
            model.pressItem did not run the item's own closure on a live bar — the capsule's \
            own route into a menu item, distinct from the overflow submenu, is untested without \
            this
            """)

        fixture.channel.withdraw(token: "test.pressItem", generation: generation)
        hosting.rootView.model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["log"], """
            model.pressItem ran an item's closure after its bar was withdrawn — a frozen bar's \
            capsule must refuse a press the same way its overflow submenu already does
            """)
        _ = fixture.toolbar
    }

    // MARK: - Busy

    /// **`isBusy` reaches the capsule's own entry whatever the kind is** —
    /// Uninstaller's Refresh is the first caller that spins.
    func testIsBusyReachesTheDeclaredEntry() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.busy")
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                              isBusy: true) {}
        ]), token: "test.busy", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let item = try XCTUnwrap(actionsItem(fixture.window), "no single actions item on the toolbar")
        let entry = try XCTUnwrap(declaredEntry("refresh", in: item), "the busy action never reached the capsule")
        XCTAssertTrue(entry.isBusy, "isBusy: true at declaration did not reach the capsule's own entry")
        _ = fixture.toolbar
    }

    // MARK: - A menu entry's own size

    /// **A `.menu` entry must cost the reserve exactly what every other kind
    /// does — one `HelmToolbarActionsCapsule.side` square — never AppKit's
    /// own bordered pull-down bezel.** The reserve is every *declared*
    /// action laid out at that one size regardless of which are visible
    /// (`HelmToolbarActionsCapsule`'s own header); a `Menu` with no
    /// `.menuStyle(.button)` draws as a 60×44 pull-down instead of a 36×36
    /// glyph, so the hosted item's intrinsic size moved with `visibleIDs`
    /// exactly the way the whole capsule exists to prevent. Mutation: drop
    /// `.menuStyle(.button)` (and `.buttonStyle(.plain)`) from the `.menu`
    /// case in `HelmToolbarActionsCapsule.entryControl(_:)`, and this test
    /// goes red — confirmed by running that mutant.
    func testAMenuEntryCostsTheSameReserveAsEveryOtherKindAcrossVisibility() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.menuSize")
        let token = "test.menuSize"

        func declare(menuVisible: Bool, buttonVisible: Bool) {
            fixture.channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "scan", title: "Scan", symbol: "arrow.clockwise",
                                  isVisible: buttonVisible) {},
                HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease",
                                  isVisible: menuVisible, menu: [
                    HelmToolbarMenuItem(id: "one", title: "One", isOn: true) {}
                ])
            ]), token: token, generation: fixture.channel.nextGeneration())
            fixture.window.layoutIfNeeded()
        }

        declare(menuVisible: true, buttonVisible: true)
        let hosting = try XCTUnwrap(
            actionsItem(fixture.window)?.view as? NSHostingView<HelmToolbarActionsCapsule>,
            "no hosted capsule on the toolbar")
        let bothVisible = hosting.fittingSize

        declare(menuVisible: false, buttonVisible: true)
        let onlyButtonVisible = hosting.fittingSize
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
        let onlyMenuVisible = hosting.fittingSize
        XCTAssertEqual(onlyMenuVisible.width, bothVisible.width, accuracy: 0.5, """
            showing only the menu action changed the capsule's own width \
            (\(onlyMenuVisible.width) vs \(bothVisible.width)) — a bare `Menu` draws as AppKit's \
            own 60×44 pull-down without `.menuStyle(.button)`, not the 36×36 glyph every other \
            entry costs
            """)
        XCTAssertEqual(onlyMenuVisible.height, bothVisible.height, accuracy: 0.5, """
            showing only the menu action changed the capsule's own height \
            (\(onlyMenuVisible.height) vs \(bothVisible.height))
            """)

        declare(menuVisible: false, buttonVisible: false)
        let neitherVisible = hosting.fittingSize
        XCTAssertEqual(neitherVisible.width, bothVisible.width, accuracy: 0.5, """
            hiding both actions changed the capsule's own width \
            (\(neitherVisible.width) vs \(bothVisible.width)) — the reserve is the *declared* \
            set, not the visible one
            """)
        _ = fixture.toolbar
    }
}
