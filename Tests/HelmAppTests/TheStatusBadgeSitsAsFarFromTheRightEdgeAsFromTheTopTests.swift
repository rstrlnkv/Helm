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
/// the real `SettingsWindow` (its own `window`, `model` and `pageBar`,
/// reached through `Mirror`, on screen), never derived from `StatusZoneView`'s
/// inset.
///
/// **What each gap is read from.** The top gap is the status zone's frame in
/// the window plus the ink's own offset inside the hosted view; the right gap
/// the same on the other axis. The zone is the one `ShellPageBarView` holds
/// for `.status`. The ink is a `cacheDisplay` of the hosted view
/// alone at alpha 24/255 — not the 12/255 `StatusZoneView.trailingInset`
/// itself reads, so the two do not agree by sharing a threshold.
///
/// **Which state comes from where — both through the bar's own path.** Keep
/// Awake is idle in a test process (nothing here starts it), so the quiet word
/// is the bar's own. The badge is Keep Awake's engine state published on the
/// module's own transport with `isActive` set — the wire the page and the bar
/// both read, so the bar's activity watch patches the zone exactly as a
/// session starting would, while no engine starts and no power assertion is
/// taken. Nothing in this file puts a `StatusZoneView` into the bar by hand.
///
/// **The inputs the fix did not name** each have a case: the first frame the
/// window is shown with (no language change to re-patch it first), a page
/// route that crosses a page with no status and back, the window gone
/// inactive, the macOS 26 title bar, the app drawn in the other appearance
/// than the window, a live resize that must not measure, and a status word
/// that is not shown when the machine's bar settings say it has no place.
///
/// **The machine's settings the bar reads when it is built** — the page bar
/// style, the sidebar style, the search's collapse and the bar's appearance —
/// are pinned in `setUp` and put back in `tearDown`; with the page bar style
/// on the window title the bar draws no status at all.
@MainActor
final class TheStatusBadgeSitsAsFarFromTheRightEdgeAsFromTheTopTests: XCTestCase {

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let vpn = VPNDescriptor.id.rawValue
    private static let frameKey = "NSWindow Frame HelmSettingsWindow.v4"

    private var owner: SettingsWindow?
    private var window: NSWindow?
    private var model: SettingsModel?
    private var bar: ShellPageBar?
    private var foundFrame: String?
    private var savedStyle: PageBarStyle = .moduleName
    private var savedSidebarStyle: SidebarStyle = .colour
    private var savedCollapse = false
    private var savedBarAppearance: HelmBarAppearance = .flat
    private var savedAppAppearance: NSAppearance?

    override func setUp() {
        super.setUp()
        foundFrame = UserDefaults.standard.string(forKey: Self.frameKey)
        savedStyle = AppSettings.pageBarStyle
        savedSidebarStyle = AppSettings.sidebarStyle
        savedCollapse = AppSettings.alwaysCollapseSearch
        savedBarAppearance = AppSettings.barAppearance
        savedAppAppearance = NSApplication.shared.appearance
        AppSettings.pageBarStyle = .moduleName
        AppSettings.sidebarStyle = .colour
        AppSettings.alwaysCollapseSearch = false
        AppSettings.barAppearance = .flat
    }

    override func tearDown() {
        NSApplication.shared.appearance = savedAppAppearance
        window?.orderOut(nil)
        window = nil
        model = nil
        bar = nil
        owner = nil
        NSWindow.removeFrame(usingName: "HelmSettingsWindow.v4")
        ModuleHost.shared.shutdown()
        UserDefaults.standard.removeObject(forKey: "module.\(Self.keepAwake).enabled")
        UserDefaults.standard.removeObject(forKey: "module.\(Self.vpn).enabled")
        UserDefaults.standard.set(foundFrame, forKey: Self.frameKey)
        AppSettings.pageBarStyle = savedStyle
        AppSettings.sidebarStyle = savedSidebarStyle
        AppSettings.alwaysCollapseSearch = savedCollapse
        AppSettings.barAppearance = savedBarAppearance
        super.tearDown()
    }

    // MARK: - The window

    /// The real window, built and pointed at Keep Awake but **not yet shown**
    /// — `show(_:)` is a separate step so the first-frame case can read what
    /// the zone carries before the window is ever on screen.
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
        let settings = SettingsWindow(host: ModuleHost.shared, band: band, bar: .pageBar)
        owner = settings
        let fields = Mirror(reflecting: settings).children
        let real = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                                 "SettingsWindow no longer holds `window` as an NSWindow")
        let model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                                  "SettingsWindow no longer holds `model` as a SettingsModel")
        bar = try XCTUnwrap(fields.first { $0.label == "pageBar" }?.value as? ShellPageBar,
                            "SettingsWindow no longer holds `pageBar` as a ShellPageBar")
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

    /// The hosted view the bar's `.status` zone holds; `nil` where the bar has no status.
    private func statusHost(_ window: NSWindow) -> NSHostingView<StatusZoneView>? {
        bar?.view.view(for: .status) as? NSHostingView<StatusZoneView>
    }

    /// **The window as the person sees it while using it — key, so the bar
    /// draws at full ink.** A test process never becomes the active app, so
    /// the window is never key and every zone dims (`ShellPageBar.Snapshot
    /// .appearsActive`); the badge's fill at that opacity falls under the
    /// reading's threshold and the case would measure the word inside it.
    /// Set through the bar's own entry, which is what `SettingsWindow`'s
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

    /// The one assertion every case makes: the zone carries the state the
    /// case is about (so an empty or wrong zone cannot pass), and what it drew
    /// sits as far from the right edge as from the top.
    private func assertGapsAgree(_ window: NSWindow, active: Bool, _ label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let host = statusHost(window) else {
            return XCTFail("\(label): no status zone", file: file, line: line)
        }
        XCTAssertEqual(host.rootView.status?.word, active ? AppStr.moduleActive : AppStr.moduleIdle,
                       "\(label): the bar does not carry the word this reading is about", file: file, line: line)
        XCTAssertEqual(host.rootView.status?.active, active,
                       "\(label): the bar does not carry the state this reading is about", file: file, line: line)
        guard let gap = gaps(host, in: window) else {
            return XCTFail("\(label): the status drew nothing", file: file, line: line)
        }
        XCTAssertGreaterThan(gap.top, 15, "\(label): top gap \(gap.top) pt — not a reading of the bar",
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
    /// The old inset (`HelmToolbarActionsCapsule.edgeMargin`) reads red in
    /// every language.
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
    /// activity watch patches the zone, and the fill's right edge and top are
    /// read from pixels. The language change after it re-derives the inset for
    /// the new word, which is the second route into `ShellPageBar.drawIdentity`: through
    /// `present`, not through `draw`.
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
    /// — no language change, no page switch, nothing re-patching the zone
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
                    let before = try XCTUnwrap(statusHost(window), "\(label): no status zone before showing")
                    let first = before.rootView.trailingInset
                    XCTAssertEqual(before.rootView.status?.active, active,
                                   "\(label): before showing, the zone does not carry this state")
                    show(window)
                    lit(window)
                    let after = try XCTUnwrap(statusHost(window), "\(label): no status zone once shown")
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
            // and a bar with tabs holds no status zone — the subject first,
            // then the absence.
            XCTAssertNotNil(bar?.view.view(for: .tabs),
                            "General: its bar with the three tabs is not on the window, so the line below proves nothing")
            XCTAssertNotNil(bar?.view.view(for: .name), "General: the bar holds no name zone")
            XCTAssertNil(statusHost(window), "General: a bar that carries tabs holds a status zone")

            model.selection = .module(Self.vpn)
            settle(window)
            let vpnActive = statusHost(window)?.rootView.status?.active
            let vpnHost = try XCTUnwrap(statusHost(window))
            XCTAssertNotNil(vpnHost.rootView.status, "VPN: the status zone carries no status")
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
    /// zone is re-patched on the key change (`ShellPageBar.Snapshot.appearsActive`),
    /// and neither the inset it is handed nor the frame the bar's layout gives it may
    /// move with the opacity. Where the lit zone's two gaps agree is the case
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
                    XCTAssertTrue(litHost.rootView.appearsActive, "\(label): the lit zone reads inactive")
                    XCTAssertEqual(litHost.rootView.status?.active, active, "\(label): the lit zone has another state")
                    let lit = (inset: litHost.rootView.trailingInset, frame: litHost.convert(litHost.bounds, to: nil))
                    bar.setWindowAppearsActive(false)
                    settle(window)
                    let host = try XCTUnwrap(statusHost(window))
                    XCTAssertFalse(host.rootView.appearsActive, "\(label): the zone did not take the inactive state")
                    XCTAssertEqual(host.rootView.status?.active, active, "\(label): the zone changed state")
                    XCTAssertEqual(host.rootView.trailingInset, lit.inset, accuracy: 0.01,
                                   "\(label): the inset moved from \(lit.inset) to \(host.rootView.trailingInset)")
                    XCTAssertEqual(host.convert(host.bounds, to: nil), lit.frame,
                                   "\(label): the zone moved when the window went inactive")
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

    /// **With the page bar on the window's title the bar holds no status
    /// zone, and with the module name again it holds one that sits where the
    /// rule says** — the subject first (the zone is there and measured), then
    /// the absence, then the zone back at equal gaps.
    func testAStatusIsOnlyWhereTheBarHasAPlaceForIt() throws {
        inEnglish {
            let window = try open(.aqua)
            try publishKeepAwake(active: true)
            settle(window)
            assertGapsAgree(window, active: true, "module name")
            AppSettings.pageBarStyle = .windowTitle
            settle(window)
            XCTAssertNotNil(bar?.view.view(for: .name), "window title: the bar holds no name zone")
            XCTAssertNil(statusHost(window), "window title: the bar holds a status zone")
            AppSettings.pageBarStyle = .moduleName
            settle(window)
            assertGapsAgree(window, active: true, "module name again")
            try publishKeepAwake(active: false)
            settle(window)
        }
    }

    // MARK: - The macOS 26 title bar

    /// **The opaque title bar `SettingsWindow` builds for macOS 26** — the bar's
    /// height is `ShellBarLayout.height` under either band, and the same rule
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
    /// the hour's), while the zone draws in the window's.
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

    // MARK: - The macOS 26 title bar in an app drawn the other way

    /// **The opaque bar, the window in one appearance and the app in the
    /// other** — the two inputs the band case and the appearance case each
    /// took alone, together: the inset is measured in a window of its own
    /// that takes the app's appearance, while the zone draws in this one's.
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
    /// renders in the app's appearance and `ShellPageBar.Snapshot` carries none, so
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

    /// **A live resize measures nothing** — `ShellPageBar` hears no resize: a
    /// step reaches the bar only as a layout pass of its view, and the inset
    /// is taken only where the snapshot changes (`drawIdentity`). Since the
    /// bar has no path from a resize to a measurement, the zero count is a
    /// guard for one that may be added; the identity of the hosted view
    /// below is what holds today. The drag is stood in for by frame steps
    /// between the live-resize start and end notifications (a test process
    /// cannot drag its own window). Nothing in the bar may be rebuilt: the
    /// status zone's hosted view is the one it was before, and it still
    /// carries the state.
    func testALiveResizeTakesNoInkMeasurement() throws {
        try countInkProbes()
        inEnglish {
            let window = try open(.aqua)
            for active in [false, true] {
                try publishKeepAwake(active: active)
                settle(window)
                let before = try XCTUnwrap(statusHost(window), "no status zone before the resize")
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
                    \(active ? "badge" : "word"): \(InkProbes.seen.count) ink measurements over \(resizes) resizes
                    """)
                let after = try XCTUnwrap(statusHost(window), "no status zone after the resize")
                XCTAssertTrue(after === before, "a live resize rebuilt the status zone's hosted view")
                assertGapsAgree(window, active: active, "\(active ? "badge" : "word"), after a live resize")
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
                    autoreleasepool { _ = StatusZoneView.trailingInset(for: status, barHeight: ShellBarLayout.height) }
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
