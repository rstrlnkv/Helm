import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_UI
import Module_Layout_UI
import Module_VPN_UI
@testable import HelmApp
@testable import HelmUI

/// **The inputs `TheStatusBadgeMovesToTheWindowsTrailingEdgeTests` never fed
/// the bar's status zone** — tester's pass on the owner's 2026-09-28
/// «Давай вернем его в правую часть».
///
/// That file mounts a fresh window per status page, so the bar is always
/// *built* on a page that has a status. In the app one bar is built on
/// whichever page is opened first — General, as often as not — and then kept
/// while the selection moves. Every case here reads what the bar laid out and
/// what the hosted view actually drew: the badge's ink is read off a
/// `cacheDisplay` of the hosted view, and its gaps are measured from the bar's
/// own edges. The one layout constant read is in the first case, which holds
/// the status zone's box to `ShellBarLayout.controlTop` and `controlHeight`
/// before reading the ink inside it.
///
/// **The machine's settings the bar reads when it is built** — the page bar
/// style, the sidebar style, the search's collapse and the bar's appearance —
/// are pinned in `setUp` and put back in `tearDown`; with the page bar style
/// on the window title the bar draws no status at all. Every fixture is dropped
/// in `tearDown`: its search zone holds a process-wide event monitor until then.
@MainActor
final class TheStatusItemHoldsUnderTheInputsTheFirstGuardSkippedTests: XCTestCase {

    /// `SettingsWindow.minSize.width` (860) minus the widest of `ShellGeometry.sidebarRange` (320): narrower than the window reaches, where the sidebar is 200 or the rail.
    /// `LivePageToolbarFixture`'s own `width:` sets the window's content width, which is the bar's width.
    private static let minPaneWidth: CGFloat = 860 - 320

    private var fixtures: [LivePageToolbarFixture] = []
    private var savedStyle: PageBarStyle = .moduleName
    private var savedSidebarStyle: SidebarStyle = .colour
    private var savedCollapse = false
    private var savedBarAppearance: HelmBarAppearance = .flat

    override func setUp() {
        super.setUp()
        savedStyle = AppSettings.pageBarStyle
        savedSidebarStyle = AppSettings.sidebarStyle
        savedCollapse = AppSettings.alwaysCollapseSearch
        savedBarAppearance = AppSettings.barAppearance
        AppSettings.pageBarStyle = .moduleName
        AppSettings.sidebarStyle = .colour
        AppSettings.alwaysCollapseSearch = false
        AppSettings.barAppearance = .flat
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in Self.moduleIDs {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        AppSettings.pageBarStyle = savedStyle
        AppSettings.sidebarStyle = savedSidebarStyle
        AppSettings.alwaysCollapseSearch = savedCollapse
        AppSettings.barAppearance = savedBarAppearance
        super.tearDown()
    }

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let vpn = VPNDescriptor.id.rawValue
    private static let moduleIDs = [keepAwake, vpn, LayoutDescriptor.id.rawValue]

    private func enableTheStatusModules() {
        ModuleHost.shared.shutdown()
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        ModuleHost.shared.setEnabled(VPNDescriptor(), true)
        ModuleHost.shared.setEnabled(LayoutDescriptor(), true)
    }

    private func mount(_ selection: SettingsSelection, width: CGFloat,
                       appearance: NSAppearance.Name = .aqua,
                       titlebarIsTransparent: Bool = true) -> LivePageToolbarFixture {
        let fx = LivePageToolbarFixture(EmptyView(), selection: selection, width: width, height: 700,
                                        appearance: appearance, titlebarIsTransparent: titlebarIsTransparent)
        fx.settle(30)
        fixtures.append(fx)
        return fx
    }

    private func statusHost(_ fx: LivePageToolbarFixture) -> NSHostingView<StatusZoneView>? {
        fx.bar.view.view(for: .status) as? NSHostingView<StatusZoneView>
    }

    private func nameHost(_ fx: LivePageToolbarFixture) -> NSHostingView<NameZoneView>? {
        fx.bar.view.view(for: .name) as? NSHostingView<NameZoneView>
    }

    /// What `ShellPageBar.status` must answer for `id` right now, read the
    /// way `ModuleDetailView` reads it — the page's own truth, not the bar's
    /// copy of it.
    private func expectedWord(_ id: String) -> String? {
        guard let live = ModuleHost.shared.liveModule(id),
              let activity = ModuleRegistry.descriptor(id)?.activity(live.vm) else { return nil }
        switch activity {
        case .active: return AppStr.moduleActive
        case .idle: return AppStr.moduleIdle
        }
    }

    // MARK: - Reading what was drawn

    private struct Ink {
        /// Leftmost and rightmost column carrying ink, in the view's own points.
        let minX: CGFloat
        let maxX: CGFloat
        /// The topmost row carrying ink, in points down from the view's top.
        let top: CGFloat
        /// The strongest alpha anywhere in the drawing, 0…255.
        let peakAlpha: Int
    }

    /// Where the view actually put ink — a `cacheDisplay` of the hosted view
    /// alone, whose untouched pixels stay fully transparent.
    private func ink(_ view: NSView) -> Ink? {
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        var minColumn = Int.max, maxColumn = -1, minRow = Int.max, peak = 0
        for y in 0..<rep.pixelsHigh {
            let row = y * rep.bytesPerRow
            for x in 0..<rep.pixelsWide {
                let alpha = Int(data[row + x * 4 + alphaOffset])
                if alpha > peak { peak = alpha }
                if alpha > 24 {
                    if y < minRow { minRow = y }
                    if x < minColumn { minColumn = x }
                    if x > maxColumn { maxColumn = x }
                }
            }
        }
        guard maxColumn >= 0 else { return Ink(minX: 0, maxX: 0, top: 0, peakAlpha: peak) }
        return Ink(minX: CGFloat(minColumn) / scale, maxX: CGFloat(maxColumn + 1) / scale,
                   top: CGFloat(minRow) / scale, peakAlpha: peak)
    }

    // MARK: - 1. The ink's right gap is its top gap

    /// **The owner, 2026-09-29: «Бейдж "Активно" / "Не активно" слишком
    /// близко находится к правому краю экрана. Отступ сверху и справа должны
    /// быть одинаковые»** — read off the status's own ink on each status page,
    /// Keep Awake's and VPN's. Both gaps are measured from the bar's own edges
    /// (the fixture's window carries an ordinary title above the bar, so the
    /// window's edge is not the bar's). The zone's box ends where the layout
    /// puts it whatever the view pads its content by; only the ink says where
    /// the drawing ends, and only its top row says where the gap it has to
    /// match begins. `TheStatusBadgeSitsAsFarFromTheRightEdgeAsFromTheTopTests`
    /// holds the same rule on the real `SettingsWindow` in every language and
    /// state.
    func testTheStatusInkEndsAsFarFromTheRightEdgeAsItStartsUnderTheTop() throws {
        enableTheStatusModules()
        for (name, id) in [("Keep Awake", Self.keepAwake), ("VPN", Self.vpn)] {
            let fx = mount(.module(id), width: 1060)
            let bar = fx.bar.view
            let host = try XCTUnwrap(statusHost(fx), "\(name): no status zone")
            let expected = expectedWord(id)
            XCTAssertNotNil(expected, "\(name): the module reports no activity to draw")
            XCTAssertEqual(host.rootView.status?.word, expected,
                           "\(name): the status zone does not carry the page's own status")
            let drawn = try XCTUnwrap(ink(host), "\(name): the status host could not be photographed")
            XCTAssertGreaterThan(drawn.maxX, 0, "\(name): the status host drew nothing at all")
            let box = host.convert(host.bounds, to: bar)
            let rightGap = bar.bounds.maxX - host.convert(NSPoint(x: drawn.maxX, y: 0), to: bar).x
            let topGap = box.minY - bar.bounds.minY + drawn.top
            // The zone was placed by the layout: its box starts at the layout's top and is the layout's
            // height, so what is left of `topGap` is the ink's own distance from the box's top.
            XCTAssertEqual(box.minY, ShellBarLayout.controlTop, accuracy: 0.01,
                           "\(name): the status zone's box starts \(box.minY) pt under the bar's top")
            XCTAssertEqual(box.height, ShellBarLayout.controlHeight, accuracy: 0.01,
                           "\(name): the status zone's box is \(box.height) pt high")
            // Ink that stood in the box's top row would not clear this: `topGap` is the box's top plus the
            // ink's distance from it, so the floor is "the ink starts below the box's top". The reading is
            // of the host's own bounds, so ink outside the box is not something it can see.
            XCTAssertGreaterThan(drawn.top, 0, "\(name): the ink starts in the zone's top row")
            XCTAssertEqual(rightGap, topGap, accuracy: 0.5, """
                \(name): «\(host.rootView.status?.word ?? "")» ends \(rightGap) pt from the bar's \
                trailing edge and starts \(topGap) pt under its top edge — the two gaps must be one
                """)
        }
    }

    // MARK: - 2. One bar, built on a page with nothing to say

    /// **The bar built on General, then carried through Keep Awake → General →
    /// VPN → About on the same fixture.** The status follows the page on every
    /// stop; on a status page the zone is laid out at least as wide as what it
    /// draws, trailing inset included, and no more than a point wider — a width
    /// the bar never re-read after General would clip the badge while the zone
    /// still reads as reachable. "What it draws" is the content's own fitting
    /// width in this same window (see the reading's own comment below). An empty page is read after a status page
    /// on the same fixture, so the absence is the bar having let go of a
    /// status it held.
    func testTheSharedBarBuiltOnGeneralCarriesEachPagesOwnStatusUnclipped() throws {
        enableTheStatusModules()
        AppLanguage.each { language in
            let fx = mount(.general, width: Self.minPaneWidth)
            let bar = fx.bar.view
            XCTAssertTrue(bar.reachableZones.contains(.name), "\(language): General's bar has no name")

            let route: [(String, SettingsSelection, String?)] = [
                ("Keep Awake", .module(Self.keepAwake), Self.keepAwake),
                ("General", .general, nil),
                ("VPN", .module(Self.vpn), Self.vpn),
                ("About", .about, nil),
            ]
            var shownAStatus = false
            for (name, selection, moduleID) in route {
                fx.model.selection = selection
                fx.settle(30)
                XCTAssertTrue(bar.reachableZones.contains(.name), "\(language) — \(name): the bar lost its name")
                let expected = moduleID.flatMap(expectedWord)
                guard moduleID != nil else {
                    XCTAssertTrue(shownAStatus, "\(language) — \(name): no status page came first on this bar")
                    XCTAssertNil(bar.view(for: .status), """
                        \(language) — \(name): the bar still holds a status zone, «\
                        \(statusHost(fx)?.rootView.status?.word ?? "")» from the previous page
                        """)
                    continue
                }
                XCTAssertNotNil(expected, "\(language) — \(name): the module reports no activity to draw")
                guard let host = statusHost(fx) else {
                    XCTFail("\(language) — \(name): no status zone"); continue
                }
                shownAStatus = true
                XCTAssertEqual(host.rootView.status?.word, expected, """
                    \(language) — \(name): the status draws «\(host.rootView.status?.word ?? "nothing")» \
                    where the page's own reading is «\(expected ?? "nothing")» — a stale status from the \
                    previous page
                    """)
                XCTAssertEqual(host.accessibilityLabel(), expected,
                               "\(language) — \(name): the status zone's accessibility label is stale")
                XCTAssertTrue(bar.reachableZones.contains(.status), "\(language) — \(name): the status is not reachable")
                // What the same content needs on its own, in a host nobody
                // has constrained. The loose host sits in the same
                // window for the reading; see the comment above the width assertion
                // below for how far the zone was measured from it.
                let loose = NSHostingView(rootView: host.rootView)
                loose.appearance = fx.mount.window?.appearance
                fx.mount.window?.contentView?.addSubview(loose)
                let needed = loose.fittingSize.width
                loose.removeFromSuperview()
                XCTAssertGreaterThan(needed, 1, "\(language) — \(name): the loose host measured nothing")
                // The zone was measured up to a point wider than a loose host in the window needs (83.0
                // against 82.5, 53.0 against 52.0); the first is a window-less host rounding up to a whole
                // point, the second is not explained. Never narrower.
                XCTAssertGreaterThanOrEqual(host.frame.width, needed - 0.01, """
                    \(language) — \(name): the status zone is laid out \(host.frame.width) pt wide and its \
                    content needs \(needed) pt — the badge is clipped
                    """)
                XCTAssertLessThanOrEqual(host.frame.width, needed + 1.01, """
                    \(language) — \(name): the status zone is laid out \(host.frame.width) pt wide and its \
                    content needs \(needed) pt — wider than the one point measured
                    """)
                guard let drawn = ink(host) else {
                    XCTFail("\(language) — \(name): the status could not be photographed"); continue
                }
                XCTAssertGreaterThan(drawn.maxX, 0, "\(language) — \(name): the status drew no ink")
                let right = host.convert(NSPoint(x: drawn.maxX, y: 0), to: bar).x
                let left = host.convert(NSPoint(x: drawn.minX, y: 0), to: bar).x
                XCTAssertLessThanOrEqual(right, bar.bounds.maxX,
                                         "\(language) — \(name): the badge's ink runs past the bar's edge")
                if let nameView = bar.view(for: .name) {
                    XCTAssertGreaterThanOrEqual(left, nameView.convert(NSPoint(x: nameView.bounds.width, y: 0), to: bar).x, """
                        \(language) — \(name): the badge's ink starts under the module's name
                        """)
                } else {
                    XCTFail("\(language) — \(name): no name zone to hold the badge against")
                }
            }
        }
    }

    /// **The module switched off while its own page is the one on screen** —
    /// the sidebar's own arrangement toggle (`SidebarComposerList`) reaches
    /// `ModuleHost.setEnabled` with no page switch and no declaration. A module
    /// that is not running at all has no "Not running" to report, so the status
    /// zone goes. Whether the selection stays on the page or the model moves it
    /// to General is not this row's question: either way the bar holds no
    /// status, after it held one on the same fixture.
    func testTheStatusClearsWhenTheModuleIsSwitchedOffUnderItsOwnPage() {
        enableTheStatusModules()
        AppLanguage.only(.en) {
            let fx = mount(.module(Self.keepAwake), width: 1060)
            XCTAssertNotNil(statusHost(fx)?.rootView.status, "Keep Awake: no status to begin with")

            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
            fx.settle(30)
            XCTAssertNil(expectedWord(Self.keepAwake), "Keep Awake still reads live after being switched off")
            XCTAssertTrue(fx.bar.view.reachableZones.contains(.name), "switched off: the bar lost its name")
            XCTAssertNil(fx.bar.view.view(for: .status), """
                Keep Awake switched off under its own page: the bar still holds a status zone, \
                «\(statusHost(fx)?.rootView.status?.word ?? "")», for a module that is not running at all
                """)
        }
    }

    /// **The other direction: "Turn On" pressed on the module's own empty
    /// page** (`SettingsWindow`'s own `page`) — no status zone to a word, so a
    /// stale reading cannot pass for a fresh one the way it can between two
    /// readings that happen to spell the same. The selection is not set again
    /// after the switch: with the re-selection taken out the status still
    /// arrived, so the bar hears the module being switched on by itself.
    func testTheStatusArrivesWhenTheModuleIsTurnedOnUnderItsOwnPage() {
        ModuleHost.shared.shutdown()
        AppLanguage.only(.en) {
            let fx = mount(.module(Self.keepAwake), width: 1060)
            XCTAssertTrue(fx.bar.view.reachableZones.contains(.name), "Keep Awake off: the bar has no name")
            XCTAssertNil(fx.bar.view.view(for: .status), "Keep Awake off: the bar holds a status zone")

            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            fx.settle(30)
            let expected = expectedWord(Self.keepAwake)
            XCTAssertNotNil(expected, "Keep Awake turned on reports no activity")
            XCTAssertEqual(statusHost(fx)?.rootView.status?.word, expected, """
                Keep Awake turned on under its own page: the status draws \
                «\(statusHost(fx)?.rootView.status?.word ?? "nothing")» where the page reads «\(expected ?? "nothing")»
                """)
        }
    }

    // MARK: - 3. Dims as one unit with the name, on both title bars

    /// **Inactive window: the name and the status lose the same share of
    /// their ink**, under the transparent bar (`HelmBandChoice.onMacOS(27)`)
    /// and the opaque one (`.onMacOS(26)`), light and dark — read off the
    /// photographed peak alpha of each hosted view, active against inactive,
    /// and held against the one opacity `helmNameZoneInactiveOpacity` names.
    /// The title bar is the bar's own constructor argument, not a property of
    /// the fixture's window.
    func testTheStatusAndTheNameDimByOneOpacityOnBothTitleBars() throws {
        enableTheStatusModules()
        for band in [HelmBandChoice.onMacOS(27), .onMacOS(26)] {
            for appearance in RenderedInk.bothAppearances {
                let label = "\(band.titlebarAppearsTransparent ? "transparent" : "opaque") bar, " +
                    RenderedInk.label(of: appearance)
                let fx = mount(.module(Self.keepAwake), width: 1060, appearance: appearance,
                               titlebarIsTransparent: band.titlebarAppearsTransparent)
                fx.bar.setWindowAppearsActive(false)
                fx.settle(10)
                let status = try XCTUnwrap(statusHost(fx), "\(label): no status host")
                let name = try XCTUnwrap(nameHost(fx), "\(label): no name host")
                XCTAssertEqual(status.rootView.titlebarIsTransparent, band.titlebarAppearsTransparent,
                               "\(label): the status host read the wrong title bar")
                XCTAssertEqual(name.rootView.titlebarIsTransparent, band.titlebarAppearsTransparent,
                               "\(label): the name host read the wrong title bar")
                let dimStatus = try XCTUnwrap(ink(status)).peakAlpha
                let dimName = try XCTUnwrap(ink(name)).peakAlpha
                fx.bar.setWindowAppearsActive(true)
                fx.settle(10)
                let litStatus = try XCTUnwrap(ink(try XCTUnwrap(statusHost(fx)))).peakAlpha
                let litName = try XCTUnwrap(ink(try XCTUnwrap(nameHost(fx)))).peakAlpha
                XCTAssertGreaterThan(litStatus, 0, "\(label): the status drew nothing while active")
                XCTAssertGreaterThan(litName, 0, "\(label): the name drew nothing while active")
                let statusRatio = Double(dimStatus) / Double(max(1, litStatus))
                let nameRatio = Double(dimName) / Double(max(1, litName))
                let expected = helmNameZoneInactiveOpacity(dark: appearance == .darkAqua,
                                                           titlebarIsTransparent: band.titlebarAppearsTransparent)
                XCTAssertEqual(statusRatio, nameRatio, accuracy: 0.04, """
                    \(label): inactive, the status keeps \(statusRatio) of its ink and the name \
                    \(nameRatio) — they do not dim as one unit
                    """)
                XCTAssertEqual(statusRatio, expected, accuracy: 0.04, """
                    \(label): inactive, the status keeps \(statusRatio) of its ink; the name zone's \
                    opacity for this bar is \(expected)
                    """)
            }
        }
    }

    // MARK: - 4. "Without Icon", and switching style while the window is up

    /// **`.windowTitle` ("Without Icon") keeps the name zone and drops the
    /// status zone, and a style switch at runtime changes both ways, on the
    /// page that is on screen, without a remount.** The name zone stays in
    /// both styles but without the plate in one: it is narrower without the
    /// icon, which is what tells the two styles apart on a name that did not
    /// change. The absence of the status is read after the name was there on
    /// the same fixture, and the status arrives on the switch to
    /// `.moduleName` and goes on the switch back.
    func testWithoutIconKeepsTheNameDropsTheStatusAndAStyleSwitchBothWaysFollows() throws {
        enableTheStatusModules()
        AppSettings.pageBarStyle = .windowTitle
        let fx = mount(.module(Self.keepAwake), width: 1060)
        let bar = fx.bar.view
        XCTAssertNotNil(expectedWord(Self.keepAwake), "Keep Awake reports no activity: nothing for the style to drop")
        XCTAssertTrue(bar.reachableZones.contains(.name), "Without Icon: the bar has no name zone")
        let bare = try XCTUnwrap(nameHost(fx), "Without Icon: no name host").frame.width
        XCTAssertGreaterThan(bare, 0, "Without Icon: the name was given no room")
        XCTAssertFalse(nameHost(fx)?.rootView.showsIcon ?? true, "Without Icon: the name zone draws the plate")
        XCTAssertNil(bar.view(for: .status), "Without Icon: the bar holds a status zone")

        AppSettings.pageBarStyle = .moduleName
        fx.settle(30)
        // `reachableZones` is filtered from `Zone.allCases`, so this says the status is reachable, not that it
        // stands last.
        XCTAssertTrue(bar.reachableZones.contains(.status), "Without → With Icon: the status did not arrive")
        XCTAssertEqual(statusHost(fx)?.rootView.status?.word, expectedWord(Self.keepAwake),
                       "Without → With Icon: the status draws a word the page does not have")
        XCTAssertTrue(nameHost(fx)?.rootView.showsIcon ?? false, "Without → With Icon: the name zone has no plate")
        XCTAssertGreaterThan(nameHost(fx)?.frame.width ?? 0, bare + 20,
                             "Without → With Icon: the name zone is no wider with the plate")

        AppSettings.pageBarStyle = .windowTitle
        fx.settle(30)
        XCTAssertTrue(bar.reachableZones.contains(.name), "With → Without Icon: the name zone went")
        XCTAssertNil(bar.view(for: .status), "With → Without Icon: the status zone stayed")
        XCTAssertFalse(nameHost(fx)?.rootView.showsIcon ?? true, "With → Without Icon: the plate stayed")
        // Within a point; see the comment above the status zone's width assertion in the status-page test for what is known of why.
        XCTAssertEqual(nameHost(fx)?.frame.width ?? 0, bare, accuracy: 1,
                       "With → Without Icon: the name zone is not as wide as it was without the plate")
    }
}
