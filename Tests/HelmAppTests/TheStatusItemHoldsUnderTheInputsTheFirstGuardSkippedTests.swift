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
/// the trailing `helm.status` item** — tester's pass on the owner's
/// 2026-09-28 «Давай вернем его в правую часть».
///
/// That file mounts a fresh window per status page, so the one shared
/// name-only bar is always *built* on a page that has a status. In the app it
/// is built on whichever name-only page is opened first — General, as often as
/// not — and then reused. Every case here reads what AppKit actually laid out
/// and what the hosted view actually drew, never the constant the fix itself
/// introduced: the badge's ink is read off a `cacheDisplay` of the hosted
/// view, not derived from `HelmToolbarActionsCapsule.edgeMargin`.
@MainActor
final class TheStatusItemHoldsUnderTheInputsTheFirstGuardSkippedTests: XCTestCase {

    /// `SettingsWindow.minSize.width` (860) minus `SettingsWindow
    /// .sidebarMaximum` (320) — the same narrowest pane the first guard uses.
    private static let minPaneWidth: CGFloat = 860 - 320

    private var fixtures: [LivePageToolbarFixture] = []
    private var savedStyle: PageBarStyle = .moduleName

    override func setUp() {
        super.setUp()
        savedStyle = AppSettings.pageBarStyle
        AppSettings.pageBarStyle = .moduleName
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in Self.moduleIDs {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        AppSettings.pageBarStyle = savedStyle
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
                       appearance: NSAppearance.Name = .aqua) -> LivePageToolbarFixture {
        let fx = LivePageToolbarFixture(EmptyView(), selection: selection, width: width, height: 700,
                                        appearance: appearance)
        fx.settle(30)
        fixtures.append(fx)
        return fx
    }

    private func item(_ toolbar: NSToolbar, _ rawID: String) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier.rawValue == rawID }
    }

    private func statusHost(_ toolbar: NSToolbar) -> NSHostingView<StatusZoneView>? {
        item(toolbar, "helm.status")?.view as? NSHostingView<StatusZoneView>
    }

    /// What `SettingsToolbar.moduleStatus` must answer for `id` right now,
    /// read the same way `ModuleDetailView` reads it — the page's own truth,
    /// not the toolbar's copy of it.
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

    private func windowX(_ view: NSView, _ x: CGFloat) -> CGFloat {
        view.convert(NSPoint(x: x, y: 0), to: nil).x
    }

    // MARK: - 1. The ink's right gap is its top gap

    /// **The owner, 2026-09-29: «Бейдж "Активно" / "Не активно" слишком
    /// близко находится к правому краю экрана. Отступ сверху и справа должны
    /// быть одинаковые»** — read off the status's own ink on each status page,
    /// Keep Awake's and VPN's, in the fixture window this file mounts. The
    /// first guard reads the *box* at 4 pt — AppKit's unbordered last-item
    /// margin — which is 4 pt whatever the view pads its content by; only the
    /// ink says where the drawing ends, and only its top row says where the
    /// gap it has to match begins. The gap from the window edge is not a
    /// fixed 8 pt like the actions capsule's, by the owner's rule: the
    /// capsule is as tall as the bar leaves room for, so its 8 pt is its top
    /// gap too, and a shorter status sits further in.
    /// `TheStatusBadgeSitsAsFarFromTheRightEdgeAsFromTheTopTests` holds the
    /// same rule on the real `SettingsWindow` in every language and state.
    func testTheStatusInkEndsAsFarFromTheRightEdgeAsItStartsUnderTheTop() throws {
        enableTheStatusModules()
        let width: CGFloat = 1060
        for (name, id) in [("Keep Awake", Self.keepAwake), ("VPN", Self.vpn)] {
            let fx = mount(.module(id), width: width)
            let window = try XCTUnwrap(fx.mount.window, "\(name): no window")
            let toolbar = try XCTUnwrap(window.toolbar, "\(name): no toolbar")
            let host = try XCTUnwrap(statusHost(toolbar), "\(name): no helm.status host")
            let expected = expectedWord(id)
            XCTAssertNotNil(expected, "\(name): the module reports no activity to draw")
            XCTAssertEqual(host.rootView.status?.word, expected,
                           "\(name): the status item does not carry the page's own status")
            let drawn = try XCTUnwrap(ink(host), "\(name): the status host could not be photographed")
            XCTAssertGreaterThan(drawn.maxX, 0, "\(name): the status host drew nothing at all")
            let rightGap = window.frame.width - windowX(host, drawn.maxX)
            let topGap = window.frame.height - host.convert(host.bounds, to: nil).maxY + drawn.top
            XCTAssertGreaterThan(topGap, 15, "\(name): top gap \(topGap) pt — not a reading of the bar")
            XCTAssertEqual(rightGap, topGap, accuracy: 0.5, """
                \(name): «\(host.rootView.status?.word ?? "")» ends \(rightGap) pt from the window's \
                trailing edge and starts \(topGap) pt under its top edge — the two gaps must be one
                """)
        }
    }

    // MARK: - 2. One shared bar, built on a page with nothing to say

    /// **The shared bar built on General, then carried through Keep Awake →
    /// General → VPN → About.** Nothing is rebuilt (same `NSToolbar`, same
    /// identifier list), the status follows the page on every stop, and on a
    /// status page the item is laid out exactly as wide as what it draws,
    /// trailing inset included — the item was first sized for an empty view,
    /// and a width AppKit never re-reads would clip the badge while
    /// `isVisible` still answers true. "Exactly" is the content's own fitting
    /// width in this same window, since the inset now follows the bar and is
    /// seldom a whole number (see the reading's own comment below).
    func testTheSharedBarBuiltOnGeneralCarriesEachPagesOwnStatusUnclipped() throws {
        enableTheStatusModules()
        AppLanguage.each { language in
            let fx = mount(.general, width: Self.minPaneWidth)
            guard let window = fx.mount.window, let firstBar = window.toolbar else {
                return XCTFail("\(language): no toolbar on General")
            }
            let firstIDs = firstBar.itemIdentifiers
            XCTAssertEqual(firstIDs.last?.rawValue, "helm.status",
                           "\(language): General's bar does not end on helm.status — \(firstIDs)")

            let route: [(String, SettingsSelection, String?)] = [
                ("Keep Awake", .module(Self.keepAwake), Self.keepAwake),
                ("General", .general, nil),
                ("VPN", .module(Self.vpn), Self.vpn),
                ("About", .about, nil),
            ]
            for (name, selection, moduleID) in route {
                fx.model.selection = selection
                fx.settle(30)
                guard let toolbar = window.toolbar else {
                    XCTFail("\(language) — \(name): the window lost its toolbar"); continue
                }
                XCTAssertTrue(toolbar === firstBar,
                              "\(language) — \(name): the shared name-only bar was replaced on a page switch")
                XCTAssertEqual(toolbar.itemIdentifiers, firstIDs,
                               "\(language) — \(name): the identifier list churned on a page switch")
                guard let host = statusHost(toolbar), let statusItem = item(toolbar, "helm.status") else {
                    XCTFail("\(language) — \(name): no helm.status host"); continue
                }
                let expected = moduleID.flatMap(expectedWord)
                XCTAssertEqual(host.rootView.status?.word, expected, """
                    \(language) — \(name): helm.status draws «\(host.rootView.status?.word ?? "nothing")» \
                    where the page's own reading is «\(expected ?? "nothing")» — a stale status from the \
                    previous page
                    """)
                XCTAssertEqual(statusItem.label, expected ?? "",
                               "\(language) — \(name): the item's label is stale")
                guard moduleID != nil else {
                    let empty = ink(host)
                    XCTAssertEqual(empty?.maxX ?? 0, 0,
                                   "\(language) — \(name): an empty status page drew ink in helm.status")
                    continue
                }
                XCTAssertNotNil(expected, "\(language) — \(name): the module reports no activity to draw")
                XCTAssertTrue(statusItem.isVisible, "\(language) — \(name): helm.status is not visible")
                // What the same content needs on its own, in a host nobody
                // has constrained — the placed host's own `fittingSize`
                // already folds in whatever width AppKit pinned it to, so it
                // cannot be the other side. The loose host sits in the same
                // window for the reading: a host with no window rounds its
                // fitting width up to a whole point (Spanish «Detenido»
                // 48.0 against 47.5 in the window, as an earlier tester read it), which read a
                // correctly sized item as a point short once its trailing
                // inset stopped being a whole number.
                let loose = NSHostingView(rootView: host.rootView)
                loose.appearance = window.appearance
                window.contentView?.addSubview(loose)
                let needed = loose.fittingSize.width
                loose.removeFromSuperview()
                XCTAssertGreaterThan(needed, 1, "\(language) — \(name): the loose host measured nothing")
                XCTAssertEqual(host.frame.width, needed, accuracy: 0.01, """
                    \(language) — \(name): helm.status is laid out \(host.frame.width) pt wide and its \
                    content needs \(needed) pt — narrower is the badge clipped (the item kept the width of \
                    the empty view it was built with on General), wider is a trailing gap the status's own \
                    inset does not account for
                    """)
                if let drawn = ink(host) {
                    let right = windowX(host, drawn.maxX)
                    let left = windowX(host, drawn.minX)
                    XCTAssertLessThanOrEqual(right, Self.minPaneWidth,
                                             "\(language) — \(name): the badge's ink runs past the window edge")
                    if let nameView = item(toolbar, "helm.name")?.view {
                        XCTAssertGreaterThanOrEqual(left, windowX(nameView, nameView.bounds.width), """
                            \(language) — \(name): the badge's ink starts under the module's name
                            """)
                    }
                }
            }
        }
    }

    /// **The module switched off while its own page is the one on screen** —
    /// the sidebar's own arrangement toggle (`SidebarComposerList`) reaches
    /// `ModuleHost.setEnabled` with no page switch and no declaration. The
    /// page itself drops to the "Turn On" empty state (`SettingsWindow`'s own
    /// `page`), so the status must go with it: a module that is not running
    /// at all has no "Not running" to report.
    ///
    /// **Predates the move.** The same two readings taken against HEAD's own
    /// `NameZoneView.status` (tester's probe, 2026-09-28) were red the same
    /// way: nothing in `SettingsToolbar` listens to `ModuleHost` switching a
    /// module, while `ModuleDetailView` — the `.windowTitle` subtitle —
    /// observes the host and follows.
    func testTheStatusClearsWhenTheModuleIsSwitchedOffUnderItsOwnPage() {
        enableTheStatusModules()
        AppLanguage.only(.en) {
            let fx = mount(.module(Self.keepAwake), width: 1060)
            guard let before = fx.mount.window?.toolbar.flatMap(statusHost) else {
                return XCTFail("no helm.status host")
            }
            XCTAssertNotNil(before.rootView.status, "Keep Awake: no status to begin with")

            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
            fx.settle(30)
            XCTAssertNil(expectedWord(Self.keepAwake), "Keep Awake still reads live after being switched off")
            guard let off = fx.mount.window?.toolbar.flatMap(statusHost) else {
                return XCTFail("switched off: no helm.status host")
            }
            XCTAssertNil(off.rootView.status, """
                Keep Awake switched off under its own page: helm.status still draws \
                «\(off.rootView.status?.word ?? "")» for a module that is not running at all
                """)
        }
    }

    /// **The other direction: "Turn On" pressed on the module's own empty
    /// page** (`SettingsWindow`'s own `page`) — nil to a word, so a stale
    /// reading cannot pass for a fresh one the way it can between two
    /// readings that happen to spell the same.
    func testTheStatusArrivesWhenTheModuleIsTurnedOnUnderItsOwnPage() {
        ModuleHost.shared.shutdown()
        AppLanguage.only(.en) {
            let fx = mount(.module(Self.keepAwake), width: 1060)
            guard let before = fx.mount.window?.toolbar.flatMap(statusHost) else {
                return XCTFail("no helm.status host")
            }
            XCTAssertNil(before.rootView.status, "Keep Awake off: helm.status draws a status")

            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            fx.settle(30)
            let expected = expectedWord(Self.keepAwake)
            XCTAssertNotNil(expected, "Keep Awake turned on reports no activity")
            guard let on = fx.mount.window?.toolbar.flatMap(statusHost) else {
                return XCTFail("turned on: no helm.status host")
            }
            XCTAssertEqual(on.rootView.status?.word, expected, """
                Keep Awake turned on under its own page: helm.status draws \
                «\(on.rootView.status?.word ?? "nothing")» where the page reads «\(expected ?? "nothing")»
                """)
        }
    }

    // MARK: - 3. Dims as one unit with the name, on both title bars

    /// **Inactive window: the name and the status lose the same share of
    /// their ink**, under the transparent bar (`HelmBandChoice.onMacOS(27)`)
    /// and the opaque one (`.onMacOS(26)`), light and dark — read off the
    /// photographed peak alpha of each hosted view, active against inactive,
    /// and held against the one opacity `helmNameZoneInactiveOpacity` names.
    func testTheStatusAndTheNameDimByOneOpacityOnBothTitleBars() throws {
        enableTheStatusModules()
        for band in [HelmBandChoice.onMacOS(27), .onMacOS(26)] {
            for appearance in RenderedInk.bothAppearances {
                let label = "\(band.titlebarAppearsTransparent ? "transparent" : "opaque") bar, " +
                    RenderedInk.label(of: appearance)
                let fx = mount(.module(Self.keepAwake), width: 1060, appearance: appearance)
                let window = try XCTUnwrap(fx.mount.window, label)
                window.titlebarAppearsTransparent = band.titlebarAppearsTransparent
                fx.toolbar.setWindowAppearsActive(false)
                fx.settle(10)
                let toolbar = try XCTUnwrap(window.toolbar, "\(label): no toolbar")
                let status = try XCTUnwrap(statusHost(toolbar), "\(label): no status host")
                let nameView = try XCTUnwrap(item(toolbar, "helm.name")?.view, "\(label): no name view")
                XCTAssertEqual(status.rootView.titlebarIsTransparent, band.titlebarAppearsTransparent,
                               "\(label): the status host read the wrong title bar")
                let dimStatus = try XCTUnwrap(ink(status)).peakAlpha
                let dimName = try XCTUnwrap(ink(nameView)).peakAlpha
                fx.toolbar.setWindowAppearsActive(true)
                fx.settle(10)
                let litStatus = try XCTUnwrap(ink(statusHost(toolbar) ?? status)).peakAlpha
                let litName = try XCTUnwrap(ink(item(toolbar, "helm.name")?.view ?? nameView)).peakAlpha
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

    // MARK: - 4. What only the source can say

    private static let toolbarFile = "Sources/HelmApp/SettingsToolbar.swift"

    private func body(of marker: String, until end: String) throws -> Substring {
        let source = SwiftSource.uncommented(try RepoSource.text(of: Self.toolbarFile))
        let start = try XCTUnwrap(source.range(of: marker), "\(marker) is gone from \(Self.toolbarFile)")
        let rest = source[start.upperBound...]
        let stop = rest.range(of: end)?.lowerBound ?? rest.endIndex
        return rest[..<stop]
    }

    /// **The empty item's VoiceOver gate, held to its line.** An offscreen
    /// `NSHostingView` in a test process answers `accessibilityChildren()`
    /// with nothing whatever it holds (`HelmAccordionTests`' own
    /// `testTheClipCannotShipWithoutTheGate` records the measurement), so no
    /// behavioural reading can tell the gate from its absence — the first
    /// guard's `…AccessibilityHidden…` case reads only `rootView.status` and
    /// stays green with the modifier deleted.
    func testTheEmptyStatusIsKeptOutOfVoiceOverInTheOnlyPlaceItCanBeRead() throws {
        let view = try body(of: "struct StatusZoneView: View", until: "\n}\n")
        XCTAssertTrue(view.contains(".accessibilityHidden(status == nil)"), """
            StatusZoneView no longer hides itself from VoiceOver when there is no status — an \
            empty toolbar item on General, About and Log reads aloud as an unnamed element
            """)
    }

    /// **The owner's "nothing falls into »", on the status item** — a
    /// visibility priority does nothing observable while the name-only bar
    /// has room (measured: `.low` left `isVisible` true at the narrowest pane
    /// in all eight languages), so the rule is held where it is written.
    func testTheStatusItemCarriesNoVisibilityPriority() throws {
        let maker = try body(of: "private func makeStatusItem(", until: "\n    }\n")
        XCTAssertFalse(maker.contains("visibilityPriority"), """
            makeStatusItem sets a visibility priority on helm.status — the owner's rule is that \
            nothing on this bar is ever offered to the overflow menu
            """)
    }

    // MARK: - 5. "Without Icon", and switching style while the window is up

    /// **`.windowTitle` carries no `helm.status` at all, and a style switch
    /// at runtime adds and removes it** — both ways, on the page that is on
    /// screen, without a remount.
    func testWithoutIconHasNoStatusItemAndAStyleSwitchBothWaysFollows() throws {
        enableTheStatusModules()
        AppSettings.pageBarStyle = .windowTitle
        let fx = mount(.module(Self.keepAwake), width: 1060)
        let window = try XCTUnwrap(fx.mount.window)
        var ids = (window.toolbar?.itemIdentifiers ?? []).map(\.rawValue)
        XCTAssertFalse(ids.contains("helm.status"), "Without Icon: the bar carries helm.status — \(ids)")
        XCTAssertFalse(ids.contains("helm.name"), "Without Icon: the bar carries helm.name — \(ids)")

        AppSettings.pageBarStyle = .moduleName
        fx.settle(30)
        ids = (window.toolbar?.itemIdentifiers ?? []).map(\.rawValue)
        XCTAssertEqual(ids.last, "helm.status", "Without → With Icon: helm.status did not arrive — \(ids)")
        if let toolbar = window.toolbar, let host = statusHost(toolbar) {
            XCTAssertEqual(host.rootView.status?.word, expectedWord(Self.keepAwake),
                           "Without → With Icon: helm.status draws a status the page does not have")
            XCTAssertTrue(item(toolbar, "helm.status")?.isVisible ?? false,
                          "Without → With Icon: helm.status is not visible")
        } else {
            XCTFail("Without → With Icon: no helm.status host")
        }

        AppSettings.pageBarStyle = .windowTitle
        fx.settle(30)
        ids = (window.toolbar?.itemIdentifiers ?? []).map(\.rawValue)
        XCTAssertFalse(ids.contains("helm.status"), "With → Without Icon: helm.status stayed — \(ids)")
        XCTAssertFalse(ids.contains("helm.name"), "With → Without Icon: helm.name stayed — \(ids)")
    }
}
