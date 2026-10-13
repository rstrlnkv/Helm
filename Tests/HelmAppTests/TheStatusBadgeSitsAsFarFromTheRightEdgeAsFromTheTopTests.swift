import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_Engine
import Module_KeepAwake_UI
import Module_VPN_UI
@testable import HelmApp
@testable import HelmUI

/// **The owner, 2026-09-29: «Бейдж "Активно" / "Не активно" слишком близко
/// находится к правому краю экрана. Отступ сверху и справа должны быть
/// одинаковые».** The gap from the window's right edge to what the status
/// draws — the green badge's fill, the quiet word's ink — is held to the gap
/// from the window's top edge to the top of the same drawing, both read off
/// the real `SettingsWindow` (its own `window`, `model` and `settingsToolbar`,
/// reached through `Mirror`, on screen), never derived from `StatusZoneView`'s
/// inset.
///
/// **What each gap is read from.** The top gap is the item's frame in the
/// window plus the ink's own offset inside the hosted view; the right gap the
/// same on the other axis. The ink is a `cacheDisplay` of the hosted view
/// alone at alpha 24/255 — not the 12/255 `StatusZoneView.trailingInset`
/// itself reads, so the two do not agree by sharing a threshold.
///
/// **Which state comes from where — both through the bar's own path.** Keep
/// Awake is idle in a test process (nothing here starts it), so the quiet word
/// is the bar's own. The badge is Keep Awake's engine state published on the
/// module's own transport with `isActive` set — the wire the page and the bar
/// both read, so the bar's activity watch patches the item exactly as a
/// session starting would, while no engine starts and no power assertion is
/// taken. Nothing in this file puts a `StatusZoneView` into the item by hand.
///
/// **The window read here is the one the app builds** — `SettingsWindow(host:band:)` with its default bar,
/// so the window wears a `SettingsToolbar` built with the `.spacer` lead (`SettingsWindow.init`) and the
/// status is the toolbar's `helm.status` item, found through `window.toolbar`.
///
/// **The inputs the fix did not name** each have a case: the first frame the
/// window is shown with (no language change to re-patch it first), a page
/// route that crosses a page with no status and back, the window gone
/// inactive, a style under which the toolbar lists no status, the macOS 26
/// title bar, the app drawn in the other appearance than the window, and a
/// bar whose height changes under a page that stays.
///
/// **The machine's settings the toolbar reads when it is built** — the page bar style, the search's
/// collapse, the bar's appearance and the switcher style — are pinned in `setUp` by `PinnedBarSettings`
/// and put back when the test ends; a row that flips the page bar style sets it after the pin.
@MainActor
final class TheStatusBadgeSitsAsFarFromTheRightEdgeAsFromTheTopTests: XCTestCase {

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let vpn = VPNDescriptor.id.rawValue
    private static let frameKey = "NSWindow Frame HelmSettingsWindow.v4"

    private var owner: SettingsWindow?
    private var window: NSWindow?
    private var model: SettingsModel?
    private var bar: SettingsToolbar?
    private var foundFrame: String?
    private var savedAppAppearance: NSAppearance?

    override func setUp() async throws {
        try await super.setUp()
        foundFrame = UserDefaults.standard.string(forKey: Self.frameKey)
        savedAppAppearance = NSApplication.shared.appearance
        PinnedBarSettings.pin(in: self)
    }

    override func tearDown() {
        NSApplication.shared.appearance = savedAppAppearance
        window?.orderOut(nil)
        window?.toolbar = nil
        window = nil
        model = nil
        bar = nil
        owner = nil
        NSWindow.removeFrame(usingName: "HelmSettingsWindow.v4")
        ModuleHost.shared.shutdown()
        UserDefaults.standard.removeObject(forKey: "module.\(Self.keepAwake).enabled")
        UserDefaults.standard.removeObject(forKey: "module.\(Self.vpn).enabled")
        UserDefaults.standard.set(foundFrame, forKey: Self.frameKey)
        super.tearDown()
    }

    // MARK: - The window

    /// The real window, built and pointed at Keep Awake but **not yet shown**
    /// — `show(_:)` is a separate step so the first-frame case can read what
    /// the item carries before the window is ever on screen.
    private func build(band: HelmBandChoice = .onMacOS(27), _ appearance: NSAppearance.Name,
                       modules: [any ModuleDescriptor] = [KeepAwakeDescriptor()],
                       activeAtOpen: Bool = false) throws -> NSWindow {
        if let window {
            window.appearance = NSAppearance(named: appearance)
            return window
        }
        ModuleHost.shared.shutdown()
        for module in modules { ModuleHost.shared.setEnabled(module, true) }
        if activeAtOpen {
            // The page's own view model has to exist to hear it — the bar
            // reads the same shared one through the descriptor.
            let live = try XCTUnwrap(ModuleHost.shared.liveModule(Self.keepAwake), "Keep Awake is not live")
            _ = KeepAwakeDescriptor().activity(live.vm)
            try publishKeepAwake(active: true)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        let settings = SettingsWindow(host: ModuleHost.shared, band: band)
        owner = settings
        let fields = Mirror(reflecting: settings).children
        let real = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                                 "SettingsWindow no longer holds `window` as an NSWindow")
        let model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                                  "SettingsWindow no longer holds `model` as a SettingsModel")
        bar = try XCTUnwrap(fields.first { $0.label == "settingsToolbar" }?.value as? SettingsToolbar,
                            "SettingsWindow no longer holds `settingsToolbar` as a SettingsToolbar")
        real.appearance = NSAppearance(named: appearance)
        model.selection = .module(Self.keepAwake)
        self.model = model
        window = real
        return real
    }

    /// One language named for a claim about geometry rather than words; a
    /// throw inside fails the test instead of leaving the override behind.
    private func inEnglish(_ body: () throws -> Void) {
        AppLanguage.only(.en) {
            do { try body() } catch { XCTFail("\(error)") }
        }
    }

    private func show(_ window: NSWindow) {
        window.orderFront(nil)
        settle(window)
    }

    private func open(band: HelmBandChoice = .onMacOS(27), _ appearance: NSAppearance.Name,
                      modules: [any ModuleDescriptor] = [KeepAwakeDescriptor()]) throws -> NSWindow {
        let fresh = window == nil
        let window = try build(band: band, appearance, modules: modules)
        if fresh {
            show(window)
            lit(window)
        }
        return window
    }

    private func settle(_ window: NSWindow, _ seconds: TimeInterval = 0.4) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            autoreleasepool {
                window.layoutIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }
    }

    private func statusHost(_ window: NSWindow) -> NSHostingView<StatusZoneView>? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.status" }?.view
            as? NSHostingView<StatusZoneView>
    }

    /// The hosting view of the name zone in the toolbar's name item, wherever the item keeps it: the item's
    /// own view or a view inside it.
    private func nameHost(_ window: NSWindow) -> NSHostingView<NameZoneView>? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.name" }?.view?
            .everyView(ofType: NSHostingView<NameZoneView>.self).first
    }

    /// **The window as the person sees it while using it — key, so the bar
    /// draws at full ink.** A test process never becomes the active app, so
    /// the window is never key and every item dims (`NameSnapshot
    /// .appearsActive`); the badge's fill at that opacity falls under the
    /// reading's threshold and the case would measure the word inside it.
    /// Set through the toolbar's own entry, which is what `SettingsWindow`'s
    /// key notifications call.
    private func lit(_ window: NSWindow) {
        bar?.setWindowAppearsActive(true)
        settle(window)
    }

    /// The language the app's own picker posts, then Keep Awake's state
    /// published again: the engine is live and may publish its own reading
    /// at any turn, so the state a case is about is re-stated right before
    /// it is read — and `assertGapsAgree` fails, rather than passes, where
    /// the engine got in between.
    private func relanguage(_ window: NSWindow, active: Bool) {
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        settle(window)
        do { try publishKeepAwake(active: active) } catch { XCTFail("\(error)") }
        settle(window)
    }

    /// Keep Awake's own state event, `isActive` as given, on the module's own
    /// transport — the reading `KeepAwakeViewModel` decodes and the bar's
    /// activity watch follows. Encoded by the engine's own payload type, so
    /// the two sides of the hop are the real ones.
    private func publishKeepAwake(active: Bool) throws {
        let live = try XCTUnwrap(ModuleHost.shared.liveModule(Self.keepAwake), "Keep Awake is not live")
        let wire = try XCTUnwrap(live.vm.transport as? LocalTransport, "Keep Awake's transport is not local")
        try waitForTheEnginesOwnState(on: wire)
        let payload = KeepAwakeEngine.StatePayload(isActive: active, conditions: [], clamshellActive: false,
                                                   endDate: nil, startDate: nil, suppressed: false)
        wire.emit(EngineEvent(name: KeepAwakeEvent.state.rawValue, payload: try JSONEncoder().encode(payload)))
    }

    /// Engines whose own first state has already been seen, by transport.
    private var heardFrom: Set<ObjectIdentifier> = []

    /// **Waits until the live engine has published a state of its own** —
    /// its activation publishes one from a task, so a state stated before it
    /// lands is overwritten by the engine's idle reading a turn later (seen:
    /// the first language after a fresh window read «Not running» under a
    /// published «Active»). The transport replays its last event to a new
    /// subscriber, so an engine that has already spoken answers at once.
    private func waitForTheEnginesOwnState(on wire: LocalTransport) throws {
        guard !heardFrom.contains(ObjectIdentifier(wire)) else { return }
        var heard = false
        let listener = Task { @MainActor in
            for await event in wire.events where event.name == KeepAwakeEvent.state.rawValue {
                heard = true
                break
            }
        }
        defer { listener.cancel() }
        let end = Date().addingTimeInterval(5)
        while !heard, Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(heard, "Keep Awake's engine published no state of its own within 5 s")
        heardFrom.insert(ObjectIdentifier(wire))
    }

    /// Distances from the window's top and right edges to the top and right of
    /// what the hosted view drew, in points; `nil` where it drew nothing.
    private func gaps(_ host: NSHostingView<StatusZoneView>, in window: NSWindow,
                      threshold: Int = 24) -> (top: CGFloat, right: CGFloat)? {
        host.layoutSubtreeIfNeeded()
        guard host.bounds.width > 0, host.bounds.height > 0,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        var top = Int.max, right = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where Int(data[y * rep.bytesPerRow + x * 4 + alphaOffset]) > threshold {
                top = min(top, y)
                right = max(right, x)
            }
        }
        guard right >= 0 else { return nil }
        let frame = host.convert(host.bounds, to: nil)
        return (top: window.frame.height - frame.maxY + CGFloat(top) / scale,
                right: window.frame.width - frame.maxX + host.bounds.width - CGFloat(right + 1) / scale)
    }

    /// The one assertion every case makes: the item carries the state the
    /// case is about (so an empty or wrong item cannot pass), and what it drew
    /// sits as far from the right edge as from the top.
    private func assertGapsAgree(_ window: NSWindow, active: Bool, _ label: String,
                                 minTop: CGFloat = 15,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let host = statusHost(window) else {
            return XCTFail("\(label): no helm.status host", file: file, line: line)
        }
        XCTAssertEqual(host.rootView.status?.word, active ? AppStr.moduleActive : AppStr.moduleIdle,
                       "\(label): the bar does not carry the word this reading is about", file: file, line: line)
        XCTAssertEqual(host.rootView.status?.active, active,
                       "\(label): the bar does not carry the state this reading is about", file: file, line: line)
        guard let gap = gaps(host, in: window) else {
            return XCTFail("\(label): the status drew nothing", file: file, line: line)
        }
        XCTAssertGreaterThan(gap.top, minTop, "\(label): top gap \(gap.top) pt — not a reading of the bar",
                             file: file, line: line)
        XCTAssertEqual(gap.right, gap.top, accuracy: 0.5, """
            \(label): «\(host.rootView.status?.word ?? "")» ends \(gap.right) pt from the window's \
            right edge and starts \(gap.top) pt under its top edge — the two gaps must be one
            """, file: file, line: line)
    }

    // MARK: - The quiet word, through the bar's own path

    /// **The real bar's own «Не активно» / «Not running» …, in each language
    /// and appearance.** Nothing is set by hand here: the language changes,
    /// the bar patches its status, and the ink is where the top gap says.
    /// The old inset (`HelmToolbarActionsCapsule.edgeMargin`, so 9 pt of ink
    /// gap against a 21–22 pt top gap) reads red in every language.
    func testTheQuietWordsInkIsAsFarFromTheRightEdgeAsFromTheTop() throws {
        for appearance in RenderedInk.bothAppearances {
            let window = try open(appearance)
            AppLanguage.each { language in
                // What the app's own language picker posts; setting the
                // override alone tells no window anything.
                relanguage(window, active: false)
                assertGapsAgree(window, active: false, "\(language), \(RenderedInk.label(of: appearance))")
            }
        }
    }

    // MARK: - The green badge, through the bar's own path

    /// **The badge's fill, in each language and appearance, put there by the
    /// bar itself** — Keep Awake's state goes active on its own wire, the
    /// activity watch patches the item, and the fill's right edge and top are
    /// read from pixels. The language change after it re-derives the inset for
    /// the new word, which is the second route into `patchName`.
    func testTheBadgesFillIsAsFarFromTheRightEdgeAsFromTheTop() throws {
        for appearance in RenderedInk.bothAppearances {
            let window = try open(appearance)
            try publishKeepAwake(active: true)
            settle(window)
            AppLanguage.each { language in
                relanguage(window, active: true)
                assertGapsAgree(window, active: true, "\(language), \(RenderedInk.label(of: appearance))")
            }
            try publishKeepAwake(active: false)
            settle(window)
        }
    }

    // MARK: - The first frame

    /// **The inset the window is first shown with is the one it settles on**
    /// — no language change, no page switch, nothing re-patching the item
    /// after it is built, the module idle and already running a session when
    /// the window opens. Read twice: before the window is ever ordered on
    /// screen (what the first frame draws) and after it has settled there; a
    /// fallback inset replaced by the measured one a turn later is a status
    /// that visibly jumps when the window opens.
    func testTheFirstFrameAlreadyCarriesTheSettledInset() throws {
        for appearance in RenderedInk.bothAppearances {
            for active in [false, true] {
                inEnglish {
                    let label = "\(active ? "badge" : "word"), \(RenderedInk.label(of: appearance))"
                    let window = try build(appearance, activeAtOpen: active)
                    settle(window, 0.2)
                    let before = try XCTUnwrap(statusHost(window), "\(label): no helm.status host before showing")
                    let first = before.rootView.trailingInset
                    XCTAssertEqual(before.rootView.status?.active, active,
                                   "\(label): before showing, the item does not carry this state")
                    show(window)
                    lit(window)
                    let after = try XCTUnwrap(statusHost(window), "\(label): no helm.status host once shown")
                    XCTAssertEqual(first, after.rootView.trailingInset, accuracy: 0.01, """
                        \(label): the status is built with a \(first) pt inset and settles at \
                        \(after.rootView.trailingInset) pt once the window is on screen — it jumps
                        """)
                    assertGapsAgree(window, active: active, "first frame, \(label)")
                    try publishKeepAwake(active: false)
                    settle(window, 0.1)
                    tearDownWindow()
                }
            }
        }
    }

    private func tearDownWindow() {
        window?.orderOut(nil)
        window?.toolbar = nil
        window = nil
        model = nil
        bar = nil
        owner = nil
        NSWindow.removeFrame(usingName: "HelmSettingsWindow.v4")
    }

    // MARK: - A page route

    /// **Keep Awake active → General → VPN → Keep Awake, on the name-only bar,
    /// with General's own tabbed bar between.**
    /// The badge leaves an inset behind for a status with a different box and
    /// ink; VPN's quiet word has to get its own, General's bar lists no status,
    /// and the badge on the way back has to get its own again.
    func testAPageRouteReDerivesTheInsetAtEveryStop() throws {
        inEnglish {
            let window = try open(.aqua, modules: [KeepAwakeDescriptor(), VPNDescriptor()])
            let model = try XCTUnwrap(self.model)
            try publishKeepAwake(active: true)
            settle(window)
            assertGapsAgree(window, active: true, "Keep Awake, active")

            model.selection = .general
            settle(window)
            // General carries its three tabs (`SettingsTabs.all`, shown by `SettingsWindow`'s detail content),
            // and a bar with tabs lists no `helm.status` — the subject first,
            // then the absence.
            XCTAssertNotNil(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.tabs" },
                            "General: its bar with the three tabs is not on the window, so the line below proves nothing")
            XCTAssertNotNil(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.name" },
                            "General: the toolbar lists no name item")
            XCTAssertNil(statusHost(window), "General: a bar that carries tabs lists helm.status")

            model.selection = .module(Self.vpn)
            settle(window)
            let vpnActive = statusHost(window)?.rootView.status?.active
            let vpnHost = try XCTUnwrap(statusHost(window))
            XCTAssertNotNil(vpnHost.rootView.status, "VPN: helm.status carries no status")
            assertGapsAgree(window, active: vpnActive ?? false, "VPN")

            model.selection = .module(Self.keepAwake)
            settle(window)
            assertGapsAgree(window, active: true, "Keep Awake again, active")
            try publishKeepAwake(active: false)
            settle(window)
            assertGapsAgree(window, active: false, "Keep Awake, back to idle under its own page")
        }
    }

    // MARK: - The window gone inactive

    /// **Dimmed, both states stay exactly where the lit ones were** — the
    /// item is re-patched on the key change (`NameSnapshot.appearsActive`),
    /// and neither the inset it is handed nor the frame AppKit gives it may
    /// move with the opacity. Where the lit item's two gaps agree is the case
    /// above; read here from pixels, the dimmed badge's fill falls under the
    /// reading's threshold, so the geometry is what is held, and the dimmed
    /// word's gaps are read as well since its ink still clears it.
    func testAnInactiveWindowKeepsTheGapsOne() throws {
        for appearance in RenderedInk.bothAppearances {
            inEnglish {
                let window = try open(appearance)
                let bar = try XCTUnwrap(self.bar)
                for active in [false, true] {
                    let label = "inactive, \(active ? "badge" : "word"), \(RenderedInk.label(of: appearance))"
                    try publishKeepAwake(active: active)
                    settle(window)
                    let litHost = try XCTUnwrap(statusHost(window))
                    XCTAssertTrue(litHost.rootView.appearsActive, "\(label): the lit item reads inactive")
                    XCTAssertEqual(litHost.rootView.status?.active, active, "\(label): the lit item has another state")
                    let lit = (inset: litHost.rootView.trailingInset, frame: litHost.convert(litHost.bounds, to: nil))
                    bar.setWindowAppearsActive(false)
                    settle(window)
                    let host = try XCTUnwrap(statusHost(window))
                    XCTAssertFalse(host.rootView.appearsActive, "\(label): the item did not take the inactive state")
                    XCTAssertEqual(host.rootView.status?.active, active, "\(label): the item changed state")
                    XCTAssertEqual(host.rootView.trailingInset, lit.inset, accuracy: 0.01,
                                   "\(label): the inset moved from \(lit.inset) to \(host.rootView.trailingInset)")
                    XCTAssertEqual(host.convert(host.bounds, to: nil), lit.frame,
                                   "\(label): the item moved when the window went inactive")
                    if !active { assertGapsAgree(window, active: false, label) }
                    bar.setWindowAppearsActive(true)
                    settle(window)
                }
                try publishKeepAwake(active: false)
                settle(window)
            }
        }
    }

    // MARK: - A bar that has no place for a status

    /// **Under "Without Icon" the toolbar lists no status and keeps the name, drawn without its icon; with
    /// the module name again it lists the status, which sits where the rule says** — the subject first
    /// (the item is there and measured), then the absence, then the item back at equal gaps. On the `.spacer`
    /// lead the window wears, the name is listed under both styles and `helm.status` only under the module's
    /// name (`SettingsToolbar.identifiers(content:style:lead:)`); the window's own title stays hidden under
    /// both, so the status has nowhere to be drawn.
    func testAStatusIsOnlyWhereTheBarHasAPlaceForIt() throws {
        inEnglish {
            let window = try open(.aqua)
            try publishKeepAwake(active: true)
            settle(window)
            assertGapsAgree(window, active: true, "module name")
            XCTAssertEqual(window.titleVisibility, .hidden, "module name: the window's title is visible")
            XCTAssertTrue(nameHost(window)?.rootView.showsIcon ?? false,
                          "module name: the toolbar holds no name zone, or it is drawn without its icon")

            AppSettings.pageBarStyle = .windowTitle
            settle(window)
            let ids = (window.toolbar?.itemIdentifiers ?? []).map(\.rawValue)
            XCTAssertTrue(ids.contains("helm.name"), "window title: the toolbar lists no name item — \(ids)")
            XCTAssertFalse(ids.contains("helm.status"), "window title: the toolbar lists helm.status — \(ids)")
            XCTAssertNil(statusHost(window), "window title: the toolbar holds a status host")
            XCTAssertEqual(window.titleVisibility, .hidden, "window title: the window's title is visible")
            XCTAssertFalse(nameHost(window)?.rootView.showsIcon ?? true,
                           "window title: the toolbar holds no name zone, or it is drawn with its icon")

            AppSettings.pageBarStyle = .moduleName
            settle(window)
            assertGapsAgree(window, active: true, "module name again")
            XCTAssertTrue(nameHost(window)?.rootView.showsIcon ?? false,
                          "module name again: the toolbar holds no name zone, or it is drawn without its icon")
            try publishKeepAwake(active: false)
            settle(window)
        }
    }

    // MARK: - The macOS 26 title bar

    /// **The opaque title bar `SettingsWindow` builds for macOS 26** — the bar
    /// height is read off the window rather than assumed, so the same rule
    /// has to hold under the other band, both states, every language.
    func testTheOpaqueTitleBarKeepsTheGapsOne() throws {
        for appearance in RenderedInk.bothAppearances {
            let window = try open(band: .onMacOS(26), appearance)
            XCTAssertFalse(window.titlebarAppearsTransparent, "the macOS 26 band built a transparent title bar")
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                AppLanguage.each { language in
                    relanguage(window, active: active)
                    assertGapsAgree(window, active: active,
                                    "opaque bar, \(language), \(RenderedInk.label(of: appearance))")
                }
            }
            try publishKeepAwake(active: false)
            settle(window)
        }
    }

    // MARK: - The app in the other appearance than the window

    /// **The window Dark over an app drawn Light, and the reverse** — the
    /// inset's own measurement renders in a window of its own that is never
    /// shown, which draws in whatever the app's appearance is (on this Mac,
    /// the hour's), while the item draws in the window's.
    func testTheGapsHoldWhenTheAppIsDrawnInTheOtherAppearance() throws {
        for appearance in RenderedInk.bothAppearances {
            let other: NSAppearance.Name = appearance == .aqua ? .darkAqua : .aqua
            NSApplication.shared.appearance = NSAppearance(named: other)
            let window = try open(appearance)
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                AppLanguage.each { language in
                    relanguage(window, active: active)
                    assertGapsAgree(window, active: active, """
                        \(language), window \(RenderedInk.label(of: appearance)) in an app drawn \
                        \(RenderedInk.label(of: other))
                        """)
                }
            }
            try publishKeepAwake(active: false)
            settle(window)
            tearDownWindow()
        }
    }

    // MARK: - A bar that changes height under a page that stays

    /// **The bar's height changes and the page does not** — the compact
    /// unified style, reached here by setting `toolbarStyle`, stands in for
    /// what full screen does to the bar, as far as this test can say it (not
    /// entered here: a full-screen Space takes the whole display from anything
    /// else on it). What follows it is a resize — the test posts it itself by
    /// calling `setFrame`, so it does not show that AppKit posts one on a
    /// style change — and nothing else: no language change, no page switch,
    /// no key change.
    func testABarThatChangesHeightTakesTheInsetWithIt() throws {
        inEnglish {
            let window = try open(.aqua)
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                let tall = window.frame.height - window.contentLayoutRect.height
                let style = window.toolbarStyle
                window.toolbarStyle = .unifiedCompact
                var frame = window.frame
                frame.size.width -= 2
                window.setFrame(frame, display: true)
                settle(window)
                let short = window.frame.height - window.contentLayoutRect.height
                XCTAssertNotEqual(tall, short, accuracy: 1, """
                    the compact style left the bar \(short) pt tall — this case changes nothing it could read
                    """)
                assertGapsAgree(window, active: active, "\(active ? "badge" : "word"), bar \(tall) → \(short) pt",
                                minTop: 8)
                window.toolbarStyle = style
                frame.size.width += 2
                window.setFrame(frame, display: true)
                settle(window)
                assertGapsAgree(window, active: active, "\(active ? "badge" : "word"), bar back to \(tall) pt")
            }
            try publishKeepAwake(active: false)
            settle(window)
        }
    }

    // MARK: - The macOS 26 title bar in an app drawn the other way

    /// **The opaque bar, the window in one appearance and the app in the
    /// other** — the two inputs the band case and the appearance case each
    /// took alone, together: the inset is measured in a window of its own
    /// that takes the app's appearance, while the item draws in this one's.
    func testTheOpaqueBarHoldsWhenTheAppIsDrawnInTheOtherAppearance() throws {
        for appearance in RenderedInk.bothAppearances {
            let other: NSAppearance.Name = appearance == .aqua ? .darkAqua : .aqua
            NSApplication.shared.appearance = NSAppearance(named: other)
            let window = try open(band: .onMacOS(26), appearance)
            XCTAssertFalse(window.titlebarAppearsTransparent, "the macOS 26 band built a transparent title bar")
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                AppLanguage.each { language in
                    relanguage(window, active: active)
                    assertGapsAgree(window, active: active, """
                        opaque bar, \(language), window \(RenderedInk.label(of: appearance)) in an app drawn \
                        \(RenderedInk.label(of: other))
                        """)
                }
            }
            try publishKeepAwake(active: false)
            settle(window)
            tearDownWindow()
        }
    }

    // MARK: - The app's appearance flips under an open window

    /// **Light turns Dark (and back) under a window that stays open, with
    /// nothing else changing** — this Mac switches by the sun and Helm sets
    /// only the app's appearance, which the window follows. The measurement
    /// renders in the app's appearance and `NameSnapshot` carries none, so
    /// the inset taken before the flip is the one drawn after it (an earlier
    /// tester's reading, not re-run for this comment: fr, ja and pt quiet
    /// words 0.5 pt apart between the two). The drawn gaps still have to be
    /// one.
    func testAnAppearanceFlipUnderAnOpenWindowKeepsTheGapsOne() throws {
        for start in RenderedInk.bothAppearances {
            let flipped: NSAppearance.Name = start == .aqua ? .darkAqua : .aqua
            NSApplication.shared.appearance = NSAppearance(named: start)
            let window = try open(start)
            window.appearance = nil
            settle(window)
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                AppLanguage.each { language in
                    relanguage(window, active: active)
                    NSApplication.shared.appearance = NSAppearance(named: flipped)
                    settle(window)
                    XCTAssertEqual(window.effectiveAppearance.name, flipped, "the window did not follow the app")
                    assertGapsAgree(window, active: active, """
                        \(language), app flipped \(RenderedInk.label(of: start)) → \(RenderedInk.label(of: flipped))
                        """)
                    NSApplication.shared.appearance = NSAppearance(named: start)
                    settle(window)
                }
            }
            try publishKeepAwake(active: false)
            settle(window)
            tearDownWindow()
        }
    }

    // MARK: - What a resize costs, and what a measurement leaves behind

    /// Counts every offscreen ink measurement — a `cacheDisplay` of a status
    /// host outside any titled window, which only `StatusZoneView`'s own
    /// measurement makes (the settings window is titled, and this file's
    /// `gaps` reads the host placed there) — holding each probe window weakly,
    /// so what is still alive after a drain is what a measurement left behind.
    private func countInkProbes() throws {
        let selector = #selector(NSView.cacheDisplay(in:to:))
        let method = try XCTUnwrap(class_getInstanceMethod(NSView.self, selector),
                                   "NSView has no cacheDisplayInRect:toBitmapImageRep: to count")
        let original = method_getImplementation(method)
        typealias Call = @convention(c) (NSView, Selector, NSRect, NSBitmapImageRep) -> Void
        let call = unsafeBitCast(original, to: Call.self)
        let counting: @convention(block) (NSView, NSRect, NSBitmapImageRep) -> Void = { view, rect, rep in
            MainActor.assumeIsolated {
                if view is NSHostingView<StatusZoneView>, !(view.window?.styleMask.contains(.titled) ?? false) {
                    InkProbes.seen.append(InkProbes.Seen(window: view.window))
                }
            }
            call(view, selector, rect, rep)
        }
        InkProbes.seen = []
        method_setImplementation(method, imp_implementationWithBlock(counting))
        addTeardownBlock { method_setImplementation(method, original) }
    }

    private func toolbarIdentity(_ window: NSWindow) -> [ObjectIdentifier] {
        guard let toolbar = window.toolbar else { return [] }
        return [ObjectIdentifier(toolbar)] + toolbar.items.map { ObjectIdentifier($0) }
            + toolbar.items.compactMap { $0.view.map { ObjectIdentifier($0) } }
    }

    /// **A live resize patches on every step and measures on none** — the
    /// resize handler re-reads the attached bar on each `didResize` (the
    /// notification AppKit posts per step of a drag as well), and the
    /// snapshot gate is what keeps that from being an offscreen window and a
    /// render per step. The drag is stood in for by frame steps between the
    /// live-resize start and end notifications (a test process cannot drag
    /// its own window); one step then changes the bar's height, which has to
    /// measure exactly once. Nothing in the attached toolbar may be rebuilt.
    func testALiveResizeMeasuresOnlyWhenTheBarsHeightMoves() throws {
        try countInkProbes()
        inEnglish {
            let window = try open(.aqua)
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                let before = toolbarIdentity(window)
                XCTAssertGreaterThan(before.count, 1, "\(active ? "badge" : "word"): the window wears no toolbar with items, so the identity compared below is of nothing")
                let identifiers = window.toolbar?.itemIdentifiers
                InkProbes.resizes = 0
                let watch = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: nil) { _ in
                    MainActor.assumeIsolated { InkProbes.resizes += 1 }
                }
                defer { NotificationCenter.default.removeObserver(watch) }
                InkProbes.seen = []
                NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: window)
                var frame = window.frame
                for step in 0..<60 {
                    frame.size.width += step < 30 ? -3 : 3
                    frame.size.height += step < 30 ? -2 : 2
                    window.setFrame(frame, display: true)
                    RunLoop.current.run(mode: .default, before: Date())
                }
                NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
                settle(window)
                let resizes = InkProbes.resizes
                XCTAssertGreaterThanOrEqual(resizes, 60, "the steps posted \(resizes) resizes — nothing was resized")
                XCTAssertEqual(InkProbes.seen.count, 0, """
                    \(active ? "badge" : "word"): \(InkProbes.seen.count) ink measurements over \(resizes) resizes \
                    that left the bar \(window.frame.height - window.contentLayoutRect.height) pt tall
                    """)
                XCTAssertEqual(toolbarIdentity(window), before, "a live resize rebuilt the attached toolbar's items")
                XCTAssertEqual(window.toolbar?.itemIdentifiers, identifiers, "a live resize rewrote the identifiers")
                assertGapsAgree(window, active: active, "\(active ? "badge" : "word"), after a live resize")

                let style = window.toolbarStyle
                window.toolbarStyle = .unifiedCompact
                frame.size.width -= 3
                window.setFrame(frame, display: true)
                settle(window)
                for step in 0..<20 {
                    frame.size.width += step.isMultiple(of: 2) ? 3 : -3
                    window.setFrame(frame, display: true)
                    RunLoop.current.run(mode: .default, before: Date())
                }
                settle(window)
                XCTAssertEqual(InkProbes.seen.count, 1, """
                    \(active ? "badge" : "word"): \(InkProbes.seen.count) ink measurements for one change of the \
                    bar's height and twenty resizes after it
                    """)
                assertGapsAgree(window, active: active, "\(active ? "badge" : "word"), after a compact live resize",
                                minTop: 8)
                XCTAssertEqual(toolbarIdentity(window), before, "a height change rebuilt the attached toolbar's items")
                window.toolbarStyle = style
                frame.size.width += 3
                window.setFrame(frame, display: true)
                settle(window)
            }
            try publishKeepAwake(active: false)
            settle(window)
        }
    }

    /// **No measurement's window is kept, one per patch, for good** — the
    /// measurement builds a window per call, never shown, so a reference that
    /// outlives the call is a window per patch for the life of the app. Many
    /// calls straight, each in its own autorelease pool, must leave none
    /// alive; then many patches through the real bar, where some probe
    /// windows may still be alive after a drain, but the count after the
    /// last round must not exceed the count after the first. Each probe window
    /// is held weakly; the app's window list is not held at all, it is read as
    /// `NSApplication.shared.windows.count`. In the first half the count is
    /// read right after the autorelease-pool loops, without draining the run
    /// loop; only the second half turns it.
    func testNoMeasurementLeavesAWindowBehind() throws {
        try countInkProbes()
        let windowsBefore = NSApplication.shared.windows.count
        AppLanguage.each { _ in
            for active in [false, true] {
                let status = (word: active ? AppStr.moduleActive : AppStr.moduleIdle, active: active)
                for _ in 0..<25 {
                    autoreleasepool { _ = StatusZoneView.trailingInset(for: status, barHeight: 52) }
                }
            }
        }
        XCTAssertEqual(InkProbes.seen.count, 8 * 2 * 25, "the calls did not all measure — the count reads nothing")
        XCTAssertTrue(InkProbes.seen.allSatisfy { $0.hadWindow }, "a measurement ran with no window of its own")
        XCTAssertEqual(InkProbes.seen.filter { $0.window != nil }.count, 0, "probe windows alive after a drain")
        XCTAssertEqual(NSApplication.shared.windows.count, windowsBefore, "the app's window list grew by the calls")

        InkProbes.seen = []
        let window = try open(.aqua)
        let listed = NSApplication.shared.windows.count
        var alive: [Int] = []
        for _ in 1...3 {
            for active in [false, true] {
                AppLanguage.each { _ in autoreleasepool { relanguage(window, active: active) } }
            }
            autoreleasepool { settle(window) }
            alive.append(InkProbes.seen.filter { $0.window != nil }.count)
        }
        XCTAssertGreaterThanOrEqual(InkProbes.seen.count, 3 * 16, "the patches measured \(InkProbes.seen.count) times")
        XCTAssertLessThanOrEqual(alive[2], alive[0], """
            probe windows alive after each round of patches: \(alive) — a window kept per patch
            """)
        XCTAssertLessThanOrEqual(NSApplication.shared.windows.count - listed, alive[2],
                                 "the app's window list grew by more than the probe windows still alive")
        try publishKeepAwake(active: false)
        settle(window)
    }
}

/// The measurements `countInkProbes` saw, each probe window held weakly.
@MainActor
private enum InkProbes {
    @MainActor
    final class Seen {
        weak var window: NSWindow?
        let hadWindow: Bool
        init(window: NSWindow?) {
            self.window = window
            hadWindow = window != nil
        }
    }
    static var seen: [Seen] = []
    static var resizes = 0
}
