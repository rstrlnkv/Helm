import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' Table / Plain-text switcher sits on exactly one glass, and that
/// glass is where the switcher is** — read off the real page on its SSH tab,
/// through a real `SettingsToolbar`, never off a capsule mounted on its own.
///
/// The owner's report (2026-09-25): the view-mode tabs drew with no Liquid
/// Glass capsule at all, where the centre tabs have one. The fix gives a
/// `.segmented` entry the same glass shape every other kind takes, not the
/// same `interactive()` (`HelmToolbarActions.swift`'s `glass(for:)`). This
/// file is what proves a glass layer exists at all under a capsule that
/// carries nothing else, and asks what a bare existence check does not:
///
/// - **Where** the glass is. A glass view (`SDFLayer`, the backing layer a
///   `.glassEffect(_:)` leaves) belongs to the whole `GlassEffectContainer`
///   — measured, it spans every visible entry whether or not each carries
///   glass — so "is there one" and "does its frame cover the switcher" both
///   pass with the switcher bare and a button beside it glassy. The shape
///   itself is the `CASDFElementLayer` inside it, which spanned the button
///   alone in that case; that element is what is measured here.
/// - **How many** — one SwiftUI glass and no AppKit platter
///   (`NSGlassEffectView`, `NSToolbarPlatterView`) around or under the item,
///   because a second glass is a second silhouette. The platter walk is shown
///   to see a platter where there is one — the centre tabs' own — before its
///   absence around `helm.actions` is believed.
/// - **How far from the edge** the glass shape sits, at the three widths
///   `TheLastItemsGlassSitsAsFarFromTheEdgeTests` already uses — that file
///   reads the Keys tab, where the `+` is the visible entry, and measures
///   the item's box plus an inset rather than the glass.
///
/// And one question about the reserve: the capsule is the same width on both
/// tabs, which is the whole of what the reserve exists for.
@MainActor
final class TheViewModeSwitcherSitsOnOneGlassTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private var fixture: LivePageToolbarFixture?

    override func tearDown() {
        fixture?.drop()
        fixture = nil
        super.tearDown()
    }

    private func mountHosts(width: CGFloat) -> LivePageToolbarFixture {
        let hosts = LivePageToolbarFixture(HostsSettingsPage(vm: ModuleViewModel(transport: Mute())),
                                           selection: .module(HostsDescriptor.id.rawValue),
                                           width: width, height: 700)
        hosts.settle(30)
        fixture = hosts
        return hosts
    }

    /// Picks a tab and waits, by the clock, for the glass to come to rest.
    ///
    /// A tab switch on a live bar morphs the glass from the entry leaving to
    /// the one arriving (`HelmToolbarActionsCapsule`'s own
    /// `.glassEffectTransition`), and `settle(_:)`'s turns can all return on
    /// an event long before that morph ends: measured, the glass's trailing
    /// edge read -19.9 pt from the window's edge straight after `settle(30)`
    /// at 1400 pt and 8.0 pt from 0.3 s on. So the reading waits until the
    /// glass has held still for several samples in a row — and fails rather
    /// than measuring if it never does.
    private func pickTab(_ id: String, on hosts: LivePageToolbarFixture) throws {
        let declared = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue),
                                     "Hosts declared nothing onto the channel")
        let selectedTab = try XCTUnwrap(declared.selectedTab, "Hosts declared no tabs")
        selectedTab.wrappedValue = id
        hosts.settle(30)
        let hosting = try actionsHost(hosts)
        var last: NSRect?
        var still = 0
        let deadline = Date().addingTimeInterval(3)
        while still < 6, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            hosts.mount.window?.layoutIfNeeded()
            let reading = glassShapes(under: hosting).reduce(NSRect.null) { $0.union($1) }
            still = reading == last ? still + 1 : 0
            last = reading
        }
        XCTAssertGreaterThanOrEqual(still, 6, "the capsule's glass never came to rest within 3 s of picking \(id)")
    }

    private func item(_ id: String, in window: NSWindow?) -> NSToolbarItem? {
        window?.toolbar?.items.first { $0.itemIdentifier.rawValue == id }
    }

    private func actionsHost(_ hosts: LivePageToolbarFixture) throws -> NSHostingView<HelmToolbarActionsCapsule> {
        try actionsHost(hosts.mount.window)
    }

    private func actionsHost(_ window: NSWindow?) throws -> NSHostingView<HelmToolbarActionsCapsule> {
        try XCTUnwrap(item("helm.actions", in: window)?.view as? NSHostingView<HelmToolbarActionsCapsule>,
                      "no hosted capsule for helm.actions")
    }

    /// Every view under `root` whose backing layer is SwiftUI's glass — one
    /// per `GlassEffectContainer` that holds any glass at all.
    private func glassViews(under root: NSView) -> [NSView] {
        root.everyView.filter { $0.layer.map { "\(type(of: $0))" == "SDFLayer" } ?? false }
    }

    /// Every glass *shape* under `root`, in `root`'s own coordinates.
    private func glassShapes(under root: NSView) -> [NSRect] {
        guard let rootLayer = root.layer else { return [] }
        func elements(_ layer: CALayer) -> [CALayer] {
            ("\(type(of: layer))" == "CASDFElementLayer" ? [layer] : [])
                + (layer.sublayers ?? []).flatMap(elements)
        }
        return glassViews(under: root).compactMap(\.layer).flatMap(elements)
            .map { $0.convert($0.bounds, to: rootLayer) }
    }

    private static let appKitGlass = ["NSGlassEffectView", "NSToolbarPlatterView"]

    /// Every AppKit glass class name above `view` (to the window's frame) and
    /// under it.
    private func appKitGlass(around view: NSView) -> [String] {
        var names: [String] = []
        var cursor = view.superview
        while let ancestor = cursor {
            names.append(ancestor.appKitClassName)
            cursor = ancestor.superview
        }
        names += view.everyView.map(\.appKitClassName)
        return names.filter { name in Self.appKitGlass.contains { name.hasPrefix($0) } }
    }

    /// Whether some glass shape under `hosting` covers the switcher's frame.
    private func assertAGlassShapeCoversTheSwitcher(in hosting: NSView, _ context: String) throws {
        let switcher = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                     "\(context): precondition — no view-mode switcher in helm.actions")
        let switcherFrame = switcher.convert(switcher.bounds, to: hosting)
        let shapes = glassShapes(under: hosting)
        XCTAssertTrue(shapes.contains { $0.insetBy(dx: -0.5, dy: -0.5).contains(switcherFrame) }, """
            \(context): no glass shape covers the view-mode switcher (\(switcherFrame)); the shapes are \
            \(shapes) — the switcher is drawn bare, whatever glass sits beside it
            """)
    }

    // MARK: - One glass, around the switcher

    func testTheSwitcherSitsInsideExactlyOneGlassAndNoAppKitPlatter() throws {
        let hosts = mountHosts(width: 1060)
        try pickTab("ssh", on: hosts)
        let hosting = try actionsHost(hosts)
        try assertAGlassShapeCoversTheSwitcher(in: hosting, "Hosts' SSH tab")

        let glass = glassViews(under: hosting)
        XCTAssertEqual(glass.count, 1, """
            \(glass.count) SwiftUI glass layer(s) under helm.actions on Hosts' SSH tab — one switcher \
            wants exactly one: none is the owner's report, two is a second silhouette
            """)

        // The walk can see a platter where AppKit draws one: the centre tabs.
        let tabsView = try XCTUnwrap(item("helm.tabs", in: hosts.mount.window)?.view,
                                     "precondition: Hosts' bar has no helm.tabs view at 1060 pt")
        XCTAssertFalse(appKitGlass(around: tabsView).isEmpty, """
            precondition: no NSGlassEffectView / NSToolbarPlatterView found around helm.tabs — the \
            walk below cannot be trusted to see AppKit's glass at all
            """)
        XCTAssertEqual(appKitGlass(around: hosting), [], """
            AppKit draws its own glass around or under helm.actions — with the capsule's SwiftUI \
            glass that is two silhouettes around one switcher
            """)
    }

    /// The input Hosts does not declare today and the next page may: a
    /// glassy button visible beside the switcher. Its glass must not be the
    /// only glass there is — and the two must blend into one silhouette, not
    /// sit as two independent shapes the union failed to merge. **Counts the
    /// shapes, not the containers**: `glassViews` (`SDFLayer`) answers one
    /// per `GlassEffectContainer` regardless of how many `CASDFElementLayer`
    /// shapes it holds, so it cannot see a union that failed — measured
    /// (engineer, pass 3, this Mac): mutating `glass(for:)` to return
    /// `.clear` for `.segmented` left the switcher and the button as two
    /// separate shapes, `[(0.5, 0.0, 77.5, 36.0), (78.0, 0.0, 36.0, 36.0)]`,
    /// where the tree merges them into one, `[(0.5, 0.0, 113.5, 36.0)]`; a
    /// container count alone stays 1 in both.
    func testTheSwitcherHasItsOwnGlassBesideAGlassyButton() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        model.selection = .module("test.switcherBesideAButton")
        channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "viewMode", title: HostsStr.viewGroup, isVisible: true, options: [
                HelmToolbarTab(id: "table", title: HostsStr.tableView, symbol: "tablecells"),
                HelmToolbarTab(id: "text", title: HostsStr.textView, symbol: "text.alignleft"),
            ], selection: .constant("table")),
            HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise", isVisible: true) {},
        ]), token: "test.switcherBesideAButton", generation: channel.nextGeneration())
        window.layoutIfNeeded()

        let hosting = try actionsHost(window)
        let shapes = glassShapes(under: hosting)
        XCTAssertFalse(shapes.isEmpty,
                       "precondition: the button beside the switcher carries no glass shape either")
        try assertAGlassShapeCoversTheSwitcher(in: hosting, "beside a button")
        XCTAssertEqual(shapes.count, 1, """
            the switcher and the button beside it drew \(shapes.count) glass shape(s), \(shapes) — \
            one glassy neighbour beside the switcher must blend into a single silhouette, not split \
            into two the union failed to merge
            """)
        _ = toolbar
    }

    // MARK: - The edge

    func testTheSwitchersGlassSitsEightPointsFromTheWindowsEdgeAtEveryWidth() throws {
        for width: CGFloat in [860, 1060, 1400] {
            let hosts = mountHosts(width: width)
            try pickTab("ssh", on: hosts)
            let hosting = try actionsHost(hosts)
            try assertAGlassShapeCoversTheSwitcher(in: hosting, "\(width) pt")
            let shapes = glassShapes(under: hosting)
            let edge = try XCTUnwrap(shapes.map(\.maxX).max(), "\(width) pt: no glass shape under helm.actions")
            let glassMaxX = hosting.convert(NSPoint(x: edge, y: 0), to: nil).x
            XCTAssertEqual(width - glassMaxX, 8, accuracy: 0.5, """
                \(width) pt: the view-mode switcher's glass ends \(width - glassMaxX) pt from the \
                window's trailing edge — AppKit's own last item sits 8 pt from it
                """)
            hosts.drop()
            fixture = nil
        }
    }

    // MARK: - The reserve

    /// Keys shows the `+`, SSH shows the switcher; the capsule is declared
    /// with both, so neither tab may move its width.
    func testTheCapsuleKeepsOneWidthAcrossTheTabSwitch() throws {
        let hosts = mountHosts(width: 1060)
        let hosting = try actionsHost(hosts)
        XCTAssertNil(hosting.everyView(ofType: NSSegmentedControl.self).first,
                     "precondition: Keys is meant to open first, without the view-mode switcher")
        let onKeys = hosting.frame.width

        try pickTab("ssh", on: hosts)
        XCTAssertNotNil(hosting.everyView(ofType: NSSegmentedControl.self).first,
                        "precondition: the SSH tab shows no view-mode switcher")
        let onSSH = hosting.frame.width
        XCTAssertEqual(onSSH, onKeys, accuracy: 0.5, """
            helm.actions is \(onKeys) pt wide on Keys and \(onSSH) pt on SSH — the reserve no longer \
            covers what the switcher draws, so the capsule resizes on a tab switch
            """)

        try pickTab("keys", on: hosts)
        XCTAssertEqual(hosting.frame.width, onKeys, accuracy: 0.5,
                       "helm.actions did not come back to its Keys width after SSH")
    }
}
