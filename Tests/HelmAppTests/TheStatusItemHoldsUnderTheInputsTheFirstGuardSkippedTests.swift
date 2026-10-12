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
/// the trailing `helm.status` item** — the owner's 2026-09-28
/// «Давай вернем его в правую часть».
///
/// That file mounts a fresh window per page, so no bar is carried from one
/// page to the next. In the app the shared name-only bar is built on whichever
/// name-only page is opened first and then reused; this fixture mounts an
/// empty page, so General, which carries tabs in the app, is name-only here.
/// Every case here reads what AppKit actually laid out
/// and what the hosted view actually drew, never the constant the fix itself
/// introduced: the badge's ink is read off a `cacheDisplay` of the hosted
/// view, not derived from `HelmToolbarActionsCapsule.edgeMargin`.
///
/// **The bar read here** is the `SettingsToolbar` of `LivePageInTheToolbarFixture`, built with the
/// `.sidebarSeparator` lead. The status item is made by `makeStatusItem`, the name item by `makeNameItem`, and
/// both are patched by `patchName` whichever lead the toolbar wears; the lead enters the list of identifiers ahead of the status
/// and the name item's container, and neither changes what these rows read. What does depend on the lead is
/// whether the name is listed at all under "Without Icon" (`identifiers(content:style:lead:)`), which the last
/// two rows read on the window the app builds.
@MainActor
final class TheStatusItemHoldsUnderTheInputsTheFirstGuardSkippedTests: XCTestCase {

    /// `SettingsWindow.minSize.width` (860) minus the widest of `ShellGeometry.sidebarRange` (320): narrower than the window reaches, where the sidebar is 200 or the rail.
    private static let minPaneWidth: CGFloat = 860 - 320

    private var fixtures: [LivePageInTheToolbarFixture] = []

    /// The toolbar reads the page bar style when it is built and the pin puts every setting back after the
    /// test; with the style on the window title the toolbar lists no `helm.status`.
    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in Self.moduleIDs {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
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
                       appearance: NSAppearance.Name = .aqua) -> LivePageInTheToolbarFixture {
        let fx = LivePageInTheToolbarFixture(EmptyView(), selection: selection, width: width, height: 700,
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
            let toolbar = try XCTUnwrap(window.toolbar, "\(name): no toolbar on the fixture's window")
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
    /// seldom a whole number (see the reading's own comment below). An empty page is read after a status page
    /// on the same fixture, so the absence is the bar having let go of a status it held.
    func testTheSharedBarBuiltOnGeneralCarriesEachPagesOwnStatusUnclipped() throws {
        enableTheStatusModules()
        AppLanguage.each { language in
            let fx = mount(.general, width: Self.minPaneWidth)
            guard let window = fx.mount.window, let firstBar = window.toolbar else {
                return XCTFail("\(language): no toolbar on the fixture's window on General")
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
            var shownAStatus = false
            for (name, selection, moduleID) in route {
                fx.model.selection = selection
                fx.settle(30)
                guard let toolbar = window.toolbar else {
                    XCTFail("\(language) — \(name): no toolbar on the fixture's window any more"); continue
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
                    XCTAssertTrue(shownAStatus, "\(language) — \(name): no status page came first on this bar")
                    // An empty status takes no height: read on General and About in all eight languages,
                    // the host is 4 pt wide (the trailing inset) and 0 pt tall, so there is nothing to
                    // photograph and the height is what is asserted. `ink` answers nil for a view of no
                    // size and for a bitmap it could not take: a host that does have a size is
                    // photographed, or the row fails, so "no ink" is never an unread picture.
                    XCTAssertEqual(host.bounds.height, 0, accuracy: 0.01, """
                        \(language) — \(name): an empty status page leaves helm.status \(host.bounds.height) pt \
                        tall — a status it still holds, or a host that takes room for nothing
                        """)
                    if host.bounds.width > 0, host.bounds.height > 0 {
                        guard let empty = ink(host) else {
                            XCTFail("\(language) — \(name): the empty status host could not be photographed")
                            continue
                        }
                        XCTAssertEqual(empty.maxX, 0,
                                       "\(language) — \(name): an empty status page drew ink in helm.status")
                    }
                    continue
                }
                shownAStatus = true
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
                guard let drawn = ink(host) else {
                    XCTFail("\(language) — \(name): the status host could not be photographed"); continue
                }
                XCTAssertGreaterThan(drawn.maxX, 0, "\(language) — \(name): the status host drew nothing at all")
                guard let nameView = item(toolbar, "helm.name")?.view else {
                    XCTFail("\(language) — \(name): no helm.name view to measure the badge against"); continue
                }
                let right = windowX(host, drawn.maxX)
                let left = windowX(host, drawn.minX)
                XCTAssertLessThanOrEqual(right, Self.minPaneWidth,
                                         "\(language) — \(name): the badge's ink runs past the window edge")
                XCTAssertGreaterThanOrEqual(left, windowX(nameView, nameView.bounds.width), """
                    \(language) — \(name): the badge's ink starts under the module's name
                    """)
            }
        }
    }

    /// **The module switched off while its own page is the one on screen** —
    /// the sidebar's own arrangement toggle (`SidebarComposerList`) reaches
    /// `ModuleHost.setEnabled` with no page switch and no declaration. The
    /// page reads as General (`ShellSidebarRows.settled`), so the status must go with it: a module that is not running
    /// at all has no "Not running" to report.
    ///
    /// `SettingsToolbar` re-reads the status on `.helmModuleDisabled`
    /// (`moduleEnabledWatch`'s header).
    func testTheStatusClearsWhenTheModuleIsSwitchedOffUnderItsOwnPage() {
        enableTheStatusModules()
        AppLanguage.only(.en) {
            let fx = mount(.module(Self.keepAwake), width: 1060)
            guard fx.mount.window?.toolbar != nil else { return XCTFail("no toolbar on the fixture's window") }
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

    /// **The other direction: the module switched on while its own page is
    /// selected** (`ModuleHost.setEnabled`, no page switch) — nil to a word, so a stale
    /// reading cannot pass for a fresh one the way it can between two
    /// readings that happen to spell the same.
    func testTheStatusArrivesWhenTheModuleIsTurnedOnUnderItsOwnPage() {
        ModuleHost.shared.shutdown()
        AppLanguage.only(.en) {
            let fx = mount(.module(Self.keepAwake), width: 1060)
            guard fx.mount.window?.toolbar != nil else { return XCTFail("no toolbar on the fixture's window") }
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
    /// and held against the one opacity `helmNameZoneInactiveOpacity` names. The title bar is the fixture
    /// window's `titlebarAppearsTransparent`, which the toolbar reads off the window.
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
                let toolbar = try XCTUnwrap(window.toolbar, "\(label): no toolbar on the fixture's window")
                let status = try XCTUnwrap(statusHost(toolbar), "\(label): no status host")
                let nameView = try XCTUnwrap(item(toolbar, "helm.name")?.view, "\(label): no name view")
                XCTAssertEqual(status.rootView.titlebarIsTransparent, band.titlebarAppearsTransparent,
                               "\(label): the status host read the wrong title bar")
                let nameHost = nameView.everyView(ofType: NSHostingView<NameZoneView>.self).first
                XCTAssertEqual(nameHost?.rootView.titlebarIsTransparent, band.titlebarAppearsTransparent,
                               "\(label): the name host read the wrong title bar")
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

    private func body(of marker: String, until end: String, in file: String) throws -> Substring {
        let source = SwiftSource.uncommented(try RepoSource.text(of: file))
        let start = try XCTUnwrap(source.range(of: marker), "\(marker) is gone from \(file)")
        let rest = source[start.upperBound...]
        let stop = rest.range(of: end)?.lowerBound ?? rest.endIndex
        return rest[..<stop]
    }

    /// **The owner's "nothing falls into »", on the status item** — a
    /// visibility priority does nothing observable while the name-only bar
    /// has room (measured: `.low` left `isVisible` true at the narrowest pane
    /// in all eight languages), so the rule is held where it is written.
    func testTheStatusItemCarriesNoVisibilityPriority() throws {
        let maker = try body(of: "private func makeStatusItem(", until: "\n    }\n", in: Self.toolbarFile)
        XCTAssertTrue(maker.contains("Self.statusID"), "the scan did not land in makeStatusItem's body: it read \(maker.count) characters")
        XCTAssertFalse(maker.contains("visibilityPriority"), """
            makeStatusItem sets a visibility priority on helm.status — the owner's rule is that \
            nothing on this bar is ever offered to the overflow menu
            """)
    }

    // MARK: - 5. "Without Icon", and switching style while the window is up

    /// **`.windowTitle` ("Without Icon") carries no `helm.status` at all, and a style switch at runtime adds
    /// and removes it** — both ways, on the page that is on screen, without a remount. Read on the fixture's
    /// `.sidebarSeparator` toolbar; that lead drops the name as well under this style, which the window the
    /// app builds does not (it lists the name without its icon: see
    /// `TheWindowWearsTheToolbarTests.testWithoutIconTheNameIsDrawnWithoutItsIconAndTheTitleStaysHidden`),
    /// so the name is not asserted here. The sidebar's separator is listed first, so a toolbar that never
    /// listed anything cannot pass the status's absence.
    func testWithoutIconHasNoStatusItemAndAStyleSwitchBothWaysFollows() throws {
        enableTheStatusModules()
        AppSettings.pageBarStyle = .windowTitle
        let fx = mount(.module(Self.keepAwake), width: 1060)
        let window = try XCTUnwrap(fx.mount.window)
        let first = try XCTUnwrap(window.toolbar, "Without Icon: no toolbar on the fixture's window")
        // The sidebar's tracking separator is what this lead lists whatever the style, so a toolbar that
        // listed nothing cannot pass the absence of the status.
        let separator = NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue
        var ids = first.itemIdentifiers.map(\.rawValue)
        XCTAssertTrue(ids.contains(separator), "Without Icon: the toolbar lists no sidebar separator — \(ids)")
        XCTAssertFalse(ids.contains("helm.status"), "Without Icon: the bar carries helm.status — \(ids)")

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
        let last = try XCTUnwrap(window.toolbar, "With → Without Icon: the window lost its toolbar")
        ids = last.itemIdentifiers.map(\.rawValue)
        XCTAssertTrue(ids.contains(separator), "With → Without Icon: the toolbar lists no sidebar separator — \(ids)")
        XCTAssertFalse(ids.contains("helm.status"), "With → Without Icon: helm.status stayed — \(ids)")
    }

    /// The window the app builds, on Keep Awake's page (a name-only page with a status) with the style stored
    /// before the window is built, and its toolbar's identifiers. The name must be listed under either style,
    /// or the status's absence or place proves nothing about a toolbar that was built.
    private func appsToolbarIdentifiers(style: PageBarStyle) -> [String]? {
        enableTheStatusModules()
        AppSettings.pageBarStyle = style
        guard let rig = SettingsWindowRig.buildAsTheAppDoes(in: self, failure: SettingsWindowRig.noShell) else {
            return nil
        }
        rig.model.selection = .module(Self.keepAwake)
        rig.settle()
        guard let toolbar = rig.worn("Keep Awake's identifiers were not read") else { return nil }
        let ids = toolbar.itemIdentifiers.map(\.rawValue)
        XCTAssertTrue(ids.contains("helm.name"), "the app's window lists no helm.name under \(style): \(ids)")
        return ids
    }

    /// **On the window the app builds, a name-only page with a status lists no `helm.status` under "Without
    /// Icon"**: the name is listed, drawn without its icon, and the status stays out, because the title that
    /// would carry it is hidden.
    func testOnTheAppsOwnWindowWithoutIconListsNoStatusOnAStatusPage() {
        guard let ids = appsToolbarIdentifiers(style: .windowTitle) else { return }
        XCTAssertFalse(ids.contains("helm.status"), "Without Icon: the app's window lists helm.status — \(ids)")
    }

    /// **On the window the app builds, the same page lists `helm.status` last under the module's name**, right
    /// after a flexible space — the control half of the row above.
    func testOnTheAppsOwnWindowTheModuleNameListsTheStatusLastOnAStatusPage() {
        guard let ids = appsToolbarIdentifiers(style: .moduleName) else { return }
        XCTAssertEqual(ids.last, "helm.status", "the module's name: the app's window does not end on helm.status — \(ids)")
    }
}
