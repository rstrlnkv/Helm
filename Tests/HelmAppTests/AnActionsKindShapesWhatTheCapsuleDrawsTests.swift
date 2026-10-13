import AppKit
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Three shapes an action can take beyond a plain button, read off a window
/// wearing a `SettingsToolbar` rather than off the source** — the same reason
/// `TheAttachedToolbarNeverChurnsOnAPageSwitchTests` gives for going through
/// `SettingsToolbar` and the channel rather than constructing
/// `HelmToolbarActionsModel.Entry` by hand: `SettingsToolbar.actionEntries(for:look:)`
/// is the one place `HelmToolbarAction.Kind` is turned into
/// `HelmToolbarActionsModel.EntryKind`, and a test that skips it would prove
/// nothing about whether that translation is actually wired in.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds: it has no `helm.tabsLead` and no capped search field.
///
/// **The capsule is read through `ActionsCapsuleReading`**, which walks the
/// root of the item's view: the item hosts the capsule under the look's
/// environment writes, so the view is no `NSHostingView<HelmToolbarActionsCapsule>`
/// and a cast to that type answers nil whatever the bar holds.
///
/// **The look.** The bar's look is read when the bar is built
/// (`AppSettings.barAppearance`). The settings are pinned in `setUp`
/// (`PinnedBarSettings`, Flat), so the rows about a model's content and a
/// closure's run are pinned to Flat and not run under Liquid Glass; the one
/// row that reads a `fittingSize` builds a bar under each look, asserts from
/// the item's root that the look reached it, and prints the look with each
/// reading.
@MainActor
final class AnActionsKindShapesWhatTheCapsuleDrawsTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func makeToolbar(_ look: HelmBarAppearance = .flat) -> Fixture {
        AppSettings.barAppearance = look
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

    private func actionsReading(_ window: NSWindow, context: String) throws -> ActionsCapsuleReading.Read {
        try ActionsCapsuleReading.read(try XCTUnwrap(window.toolbar, "\(context): the window wears no toolbar"),
                                       context: context)
    }

    private func declaredEntry(_ id: String, in window: NSWindow, context: String) throws -> HelmToolbarActionsModel.Entry? {
        try actionsReading(window, context: context).capsule.model.declared.first { $0.id == id }
    }

    /// Every look the item's hosted root carries, read through the root's value types (the walk stops at
    /// a reference type, whose fields are somebody's state and not a view's description).
    private func looks(in host: NSView) -> [HelmBarAppearance] {
        func walk(_ value: Any, _ depth: Int) -> [HelmBarAppearance] {
            guard depth < 12 else { return [] }
            if let look = value as? HelmBarAppearance { return [look] }
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle != .class else { return [] }
            return mirror.children.flatMap { walk($0.value, depth + 1) }
        }
        guard let root = Mirror(reflecting: host).children.first(where: { $0.label == "_rootView" })?.value else { return [] }
        return walk(root, 0)
    }

    // MARK: - Toggle

    /// **The model entry is `.toggle(isOn:)`, and the overflow menu form's own
    /// `state` follows it** — no page declares one today (`command grep -rn
    /// -A3 'HelmToolbarAction(' Sources/Modules | command grep -c 'isOn:'`;
    /// Hosts' Table/Plain-text pair moved to `.segmented`, the owner's
    /// report, 2026-09-25), so this proves the wiring itself:
    /// `SettingsToolbar.actionEntries(for:look:)` still has to carry `isOn`
    /// through and the overflow floor still has to read it, for whichever
    /// page reaches for a toggle next.
    func testAToggleActionsEntryCarriesIsOnAndTheOverflowFormsStateFollowsIt() throws {
        let fixture = makeToolbar()
        fixture.model.selection = .module("test.toggle")
        fixture.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "mode", title: "Plain text", symbol: "text.alignleft",
                              isOn: true) {}
        ]), token: "test.toggle", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let item = try XCTUnwrap(actionsItem(fixture.window), "no single actions item on the toolbar")
        let entry = try XCTUnwrap(declaredEntry("mode", in: fixture.window, context: "toggle"), "the toggle action never reached the capsule")
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
        let entry = try XCTUnwrap(declaredEntry("kinds", in: fixture.window, context: "menu"), "the menu action never reached the capsule")
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

        let model = try actionsReading(fixture.window, context: "pressItem").capsule.model
        model.pressItem("kinds", "log")
        XCTAssertEqual(pressed.ids, ["log"], """
            model.pressItem did not run the item's own closure on a live bar — the capsule's \
            own route into a menu item, distinct from the overflow submenu, is untested without \
            this
            """)

        fixture.channel.withdraw(token: "test.pressItem", generation: generation)
        model.pressItem("kinds", "log")
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

        let entry = try XCTUnwrap(declaredEntry("refresh", in: fixture.window, context: "busy"), "the busy action never reached the capsule")
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
    /// goes red under both looks, confirmed by running that mutant: the
    /// `[menu size]` lines read 91.0 × 44.0 pt where they read 76.0 × 36.0 pt
    /// with the two modifiers in place.
    func testAMenuEntryCostsTheSameReserveAsEveryOtherKindAcrossVisibility() throws {
        for look in [HelmBarAppearance.flat, .liquidGlass] {
            try assertAMenuEntryCostsTheSameReserve(under: look)
        }
    }

    private func assertAMenuEntryCostsTheSameReserve(under look: HelmBarAppearance) throws {
        let fixture = makeToolbar(look)
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
        let hosting = try actionsReading(fixture.window, context: "\(look)").host
        XCTAssertEqual(looks(in: hosting), [look], """
            \(look): precondition — the capsule's root carries \(looks(in: hosting)), not the look the bar was \
            built under
            """)
        let bothVisible = hosting.fittingSize
        print("[menu size] \(look): capsule \(bothVisible.width) x \(bothVisible.height) pt")

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
