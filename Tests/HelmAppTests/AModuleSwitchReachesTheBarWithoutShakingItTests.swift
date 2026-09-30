import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_UI
import Module_VPN_UI
@testable import HelmApp
@testable import HelmUI

/// **What the `.helmModuleEnabled`/`.helmModuleDisabled` pair on
/// `SettingsToolbar` does to every bar it was not written for** — tester's
/// confirmation pass on the repair that made `helm.status` follow a module
/// switched on or off under its own page.
///
/// The pair is deliberately unfiltered: a switch of *any* module reaches the
/// bar on screen, whichever page that is. Three questions the repair's own
/// cases never asked:
///
/// - A switch of some other module while a tab page is showing (Homebrew's
///   shape: tabs, actions, search) — the menu-bar panel's «Turn On»
///   (`PanelChrome.swift`) and the sidebar composer's toggle both reach it with
///   the settings window open — must attach no new toolbar, rewrite no
///   identifier, reseat no item, evict nothing and move no fold, at a pane
///   where the tabs are full and at one where they are folded.
/// - The page's own module flipped off and on faster than its page can
///   withdraw and redeclare must end on the page's own bar, live.
/// - A `SettingsToolbar` let go of — including in the middle of the very post
///   it observes — must neither be kept alive by its observers nor answer one.
///
/// Every "nothing moved" case first proves the post reached the toolbar at
/// all, through a `selectedTab` binding that counts its reads: a bar that
/// never heard the switch would pass every absence below for nothing.
@MainActor
final class AModuleSwitchReachesTheBarWithoutShakingItTests: XCTestCase {

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let vpn = VPNDescriptor.id.rawValue
    /// `SettingsSplitViewController`'s own `sidebarDefault`, as
    /// `AnUnfoldIsPredictedNeverTrialledTests` duplicates it.
    private static let sidebarWidth: CGFloat = 214

    private var savedPageBar: Any?
    private var savedSwitcher: Any?
    private var savedCollapse: Any?
    private var fixtures: [LivePageToolbarFixture] = []

    override func setUp() {
        super.setUp()
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedSwitcher = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        AppSettings.pageBarStyle = .moduleName
        AppSettings.toolbarSwitcherStyle = .text
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in [Self.keepAwake, Self.vpn] {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedSwitcher, for: ToolbarSwitcherStyle.storageKey)
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        super.tearDown()
    }

    // MARK: - Rig

    /// Counts every read of the declared `selectedTab` — `patchTabs` and
    /// `settle` both read it, so a count that moved is the proof a post
    /// reached the bar.
    @MainActor private final class Reads { var count = 0 }

    /// Homebrew's own shape (`AnUnfoldIsPredictedNeverTrialledTests
    /// .homebrewContent()`), with a selected-tab binding that counts.
    private func tabPageContent(_ reads: Reads) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [
                HelmToolbarTab(id: "installed", title: L("Installed"), symbol: "shippingbox"),
                HelmToolbarTab(id: "updates", title: L("Updates"), symbol: "arrow.up.circle"),
                HelmToolbarTab(id: "health", title: L("Health"), symbol: "stethoscope")
            ],
            selectedTab: Binding(get: { MainActor.assumeIsolated { reads.count += 1 }; return "installed" },
                                 set: { _ in }),
            actions: [
                HelmToolbarAction(id: "upgradeAll", title: L("Upgrade all"), symbol: "arrow.down.to.line",
                                  isEnabled: false, isVisible: false) {},
                HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}
            ],
            search: HelmToolbarSearch(prompt: L("Search packages"), text: .constant("")))
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let keepAlive: [AnyObject]
    }

    /// The split-view shape `SettingsSplitViewController` builds, so
    /// `offeredRoom()` reads a detail pane and the fold is the real one.
    /// Never ordered on screen.
    private func mountSplit(pane: CGFloat, selection: SettingsSelection) -> Rig {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let detail = NSViewController()
        detail.view = NSView(frame: NSRect(x: 0, y: 0, width: pane, height: 700))
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420
        let sidebar = NSViewController()
        sidebar.view = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: 700))
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        sidebarItem.allowsFullHeightLayout = true
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
        window.layoutIfNeeded()
        split.splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
        window.layoutIfNeeded()
        let got = detail.view.bounds.width
        if abs(got - pane) > 0.5 {
            window.setContentSize(NSSize(width: window.frame.width + (pane - got), height: 700))
            window.layoutIfNeeded()
        }
        model.selection = selection
        toolbar.window = window
        return Rig(window: window, toolbar: toolbar, model: model, channel: channel, keepAlive: [split])
    }

    private func settle(_ window: NSWindow, turns: Int = 20) {
        for _ in 0..<turns {
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - What the bar is showing

    /// Everything a switch elsewhere could move on the attached bar: which
    /// toolbar, its identifier list, the item objects themselves, the tabs'
    /// hosted view, what AppKit shows of each watched item, the fold (the
    /// segment count of the one segmented control the tabs host draws, nil
    /// when folded into a menu), and whether the controls are live.
    private struct BarState: Equatable, CustomStringConvertible {
        let toolbar: ObjectIdentifier?
        let identifiers: [String]
        let items: [ObjectIdentifier]
        let tabsView: ObjectIdentifier?
        let segments: Int?
        let visible: [String]
        let searchEnabled: Bool?
        let actionsInteractive: Bool?

        var description: String {
            "toolbar=\(toolbar.map { "\($0.hashValue)" } ?? "nil") ids=\(identifiers) "
                + "segments=\(segments.map(String.init) ?? "nil") visible=\(visible) "
                + "search=\(searchEnabled.map(String.init) ?? "nil") "
                + "actions=\(actionsInteractive.map(String.init) ?? "nil")"
        }
    }

    private func state(_ window: NSWindow) -> BarState {
        let toolbar = window.toolbar
        let items = toolbar?.items ?? []
        let tabs = items.first { $0.itemIdentifier.rawValue == "helm.tabs" }
        let actions = items.first { $0.itemIdentifier.rawValue == "helm.actions" }?.view
            as? NSHostingView<HelmToolbarActionsCapsule>
        let search = items.compactMap { $0 as? NSSearchToolbarItem }.first
        return BarState(
            toolbar: toolbar.map(ObjectIdentifier.init),
            identifiers: toolbar?.itemIdentifiers.map(\.rawValue) ?? [],
            items: items.map(ObjectIdentifier.init),
            tabsView: tabs?.view.map(ObjectIdentifier.init),
            segments: tabs?.view?.everyView(ofType: NSSegmentedControl.self).first?.segmentCount,
            visible: items.filter { $0.isVisible }.map(\.itemIdentifier.rawValue),
            searchEnabled: search?.searchField.isEnabled,
            actionsInteractive: actions?.rootView.model.isInteractive)
    }

    /// `willAddItem`/`didRemoveItem` on any toolbar, and every `isVisible`
    /// going false on the items of the bar attached when it started.
    @MainActor private final class ChurnWatch {
        var added = 0
        var removed = 0
        var evicted: [String] = []
        private var tokens: [NSObjectProtocol] = []
        private var kvo: [NSKeyValueObservation] = []

        init(_ toolbar: NSToolbar?) {
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.added += 1 }
            })
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSToolbar.didRemoveItemNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.removed += 1 }
            })
            for item in toolbar?.items ?? [] {
                let name = item.itemIdentifier.rawValue
                kvo.append(item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                    guard change.newValue == false else { return }
                    MainActor.assumeIsolated { self?.evicted.append(name) }
                })
            }
        }

        func stop() {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens = []
            kvo = []
        }
    }

    // MARK: - 1. Another module's switch, under a tab page

    /// **Keep Awake switched off and on six times while a Homebrew-shaped page
    /// is on screen**, at a pane where the tabs are full (English, 1060) and
    /// one where they are folded (Russian, 560). The bar is read after every
    /// single switch, before anything settles, and again after the settle
    /// each switch schedules — a blink that comes and goes inside one
    /// switch is the one a before/after pair would miss.
    func testAnotherModulesSwitchMovesNothingOnATabPage() {
        let cases: [(AppLanguage, CGFloat, String)] = [(.en, 1060, "full"), (.ru, 560, "folded")]
        for (language, pane, fold) in cases {
            AppLanguage.only(language) {
                ModuleHost.shared.shutdown()
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                let reads = Reads()
                let rig = mountSplit(pane: pane, selection: .module("test.tabPage"))
                rig.channel.declare(tabPageContent(reads), token: "test.tabPage",
                                    generation: rig.channel.nextGeneration())
                settle(rig.window, turns: 40)
                let before = state(rig.window)
                XCTAssertNotNil(before.toolbar, "\(language) \(pane): no toolbar attached")
                XCTAssertTrue(before.identifiers.contains("helm.tabs"),
                              "\(language) \(pane): the tab page's own bar is not the one attached — \(before)")
                // The subject: the fold state this case is named for really is
                // the one on screen, or "the fold did not move" is about
                // nothing.
                if fold == "full" {
                    XCTAssertEqual(before.segments, 3, "\(language) \(pane): tabs not full to begin with — \(before)")
                } else {
                    XCTAssertNotEqual(before.segments, 3,
                                      "\(language) \(pane): tabs not folded to begin with — \(before)")
                }

                let watch = ChurnWatch(rig.window.toolbar)
                let readsBefore = reads.count
                var seen: [String] = []
                for round in 0..<6 {
                    ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), round % 2 == 1)
                    let now = state(rig.window)
                    if now != before { seen.append("round \(round), at once: \(now)") }
                    settle(rig.window, turns: 12)
                    let settled = state(rig.window)
                    if settled != before { seen.append("round \(round), settled: \(settled)") }
                }
                watch.stop()

                XCTAssertGreaterThan(reads.count, readsBefore, """
                    \(language) \(pane): six module switches never reached the bar at all — every \
                    absence below would pass for a toolbar that did not hear them
                    """)
                XCTAssertEqual(seen, [], """
                    \(language) \(pane) (\(fold)): another module's switch moved the tab page's bar; \
                    before: \(before)
                    """)
                XCTAssertEqual(watch.added, 0, "\(language) \(pane): \(watch.added) willAddItem during the switches")
                XCTAssertEqual(watch.removed, 0,
                               "\(language) \(pane): \(watch.removed) didRemoveItem during the switches")
                XCTAssertEqual(watch.evicted, [], "\(language) \(pane): items evicted during the switches")
                _ = rig
            }
        }
    }

    // MARK: - 2. Another module's switch, under the shared name-only bar

    /// **General, and Keep Awake's own page, while VPN is switched off and on**
    /// — the shared bar keeps its toolbar, its items and its status host, and
    /// Keep Awake's word stays the page's own reading.
    func testAnotherModulesSwitchMovesNothingOnTheSharedBar() {
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            ModuleHost.shared.setEnabled(VPNDescriptor(), true)
            for selection in [SettingsSelection.general, .module(Self.keepAwake)] {
                let fx = LivePageToolbarFixture(EmptyView(), selection: selection, width: 1060, height: 700)
                fx.settle(30)
                fixtures.append(fx)
                guard let window = fx.mount.window else { return XCTFail("\(selection): no window") }
                let before = state(window)
                let statusBefore = statusHost(window.toolbar)
                XCTAssertTrue(before.identifiers.contains("helm.status"),
                              "\(selection): not the shared name-only bar — \(before)")
                let expected: String? = selection == .general ? nil : liveWord(Self.keepAwake)
                if selection != .general {
                    XCTAssertNotNil(expected, "Keep Awake is on and reports no activity")
                }
                XCTAssertEqual(statusBefore?.rootView.status?.word, expected,
                               "\(selection): the status to begin with")

                let watch = ChurnWatch(window.toolbar)
                var seen: [String] = []
                for round in 0..<6 {
                    ModuleHost.shared.setEnabled(VPNDescriptor(), round % 2 == 1)
                    fx.settle(8)
                    let now = state(window)
                    if now != before { seen.append("round \(round): \(now)") }
                    let host = statusHost(window.toolbar)
                    if host !== statusBefore { seen.append("round \(round): a different status host") }
                    if host?.rootView.status?.word != expected {
                        seen.append("round \(round): status «\(host?.rootView.status?.word ?? "nothing")»")
                    }
                }
                watch.stop()
                XCTAssertEqual(seen, [], "\(selection): VPN's switch moved the shared bar; before: \(before)")
                XCTAssertEqual(watch.added + watch.removed, 0, "\(selection): items added or removed")
                XCTAssertEqual(watch.evicted, [], "\(selection): items evicted")
                // The subject: this same bar does hear a switch — its own
                // module's — so the stillness above is not deafness.
                if selection != .general {
                    ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                    fx.settle(8)
                    XCTAssertNil(statusHost(window.toolbar)?.rootView.status, """
                        Keep Awake's own switch never reached this bar — every stillness above \
                        is about a toolbar that hears nothing
                        """)
                    ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                }
            }
        }
    }

    /// The page's own reading, the way `ModuleDetailView` takes it.
    private func liveWord(_ id: String) -> String? {
        guard let live = ModuleHost.shared.liveModule(id),
              let activity = ModuleRegistry.descriptor(id)?.activity(live.vm) else { return nil }
        switch activity {
        case .active: return AppStr.moduleActive
        case .idle: return AppStr.moduleIdle
        }
    }

    private func statusHost(_ toolbar: NSToolbar?) -> NSHostingView<StatusZoneView>? {
        toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.status" }?.view
            as? NSHostingView<StatusZoneView>
    }

    // MARK: - 3. The page's own module, flipped faster than the page follows

    /// **Off and on again, in the order the app delivers it** — the post from
    /// `ModuleHost.setEnabled` first and synchronously, the page's withdraw or
    /// redeclare a turn later — eight times, inside the grace period; then
    /// the same flip with no withdraw at all (the page's re-render coalesced);
    /// then one that outlives the grace period. Each must end on the page's
    /// own bar, the same toolbar object it had, with its controls live.
    ///
    /// Keep Awake's id stands for a tab page here: `SettingsToolbar` keys the
    /// bar on the page and asks the host only whether that id is live, so a
    /// real descriptor is what `isModuleSwitchedOff()` needs and the content
    /// is what the channel carries.
    func testThePagesOwnModuleFlippedFastEndsLiveOnItsOwnBar() {
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            let reads = Reads()
            let rig = mountSplit(pane: 1060, selection: .module(Self.keepAwake))
            var generation = rig.channel.nextGeneration()
            rig.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
            settle(rig.window, turns: 40)
            let live = state(rig.window)
            XCTAssertEqual(live.segments, 3, "the page's bar is not the one attached — \(live)")
            XCTAssertEqual(live.actionsInteractive, true, "the page's bar is not live to begin with")

            // Inside the grace period.
            for _ in 0..<8 {
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                rig.channel.withdraw(token: Self.keepAwake, generation: generation)
                settle(rig.window, turns: 2)
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                generation = rig.channel.nextGeneration()
                rig.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
                settle(rig.window, turns: 2)
            }
            settle(rig.window, turns: 30)
            XCTAssertEqual(state(rig.window), live, "eight fast flips inside the grace period")

            // No withdraw at all between the two posts.
            for _ in 0..<8 {
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            }
            settle(rig.window, turns: 30)
            XCTAssertEqual(state(rig.window), live, "eight flips the page never withdrew for")

            // Off long enough to fall back, then on again.
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
            rig.channel.withdraw(token: Self.keepAwake, generation: generation)
            let fellBack = expectation(description: "grace period runs out")
            DispatchQueue.main.asyncAfter(deadline: .now() + SettingsToolbar.graceInterval + 0.3) {
                fellBack.fulfill()
            }
            wait(for: [fellBack], timeout: 3)
            settle(rig.window, turns: 5)
            let off = state(rig.window)
            XCTAssertTrue(off.identifiers.contains("helm.status"),
                          "switched off past the grace period and still not on the shared bar — \(off)")
            XCTAssertNil(statusHost(rig.window.toolbar)?.rootView.status,
                         "the shared bar says a status for a module that is off")
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            generation = rig.channel.nextGeneration()
            rig.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
            settle(rig.window, turns: 30)
            XCTAssertEqual(state(rig.window), live, "back on after a fall-back")
            _ = rig
        }
    }

    // MARK: - 4. A toolbar let go of

    /// **Let go of with its window still up, then both posts** — nothing kept
    /// it alive (the observers capture it weakly), and the window's bar does
    /// not move for a post nobody is left to answer.
    func testADroppedToolbarIsNotKeptAliveAndAnswersNoPost() {
        weak var weakToolbar: SettingsToolbar?
        var window: NSWindow?
        var keep: [AnyObject] = []
        autoreleasepool {
            let rig = mountSplit(pane: 1060, selection: .general)
            settle(rig.window, turns: 10)
            weakToolbar = rig.toolbar
            window = rig.window
            keep = rig.keepAlive
        }
        settle(window!, turns: 5)
        XCTAssertNil(weakToolbar, "a SettingsToolbar nobody holds is still alive — something retains it")
        let before = window.map(state)
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
        settle(window!, turns: 5)
        XCTAssertEqual(window.map(state), before, "a post moved the bar of a toolbar already gone")
        _ = keep
    }

    /// **Let go of inside the post itself** — an observer registered before
    /// the toolbar's drops the last reference while `.helmModuleDisabled` is
    /// being delivered, so the toolbar's own block, already scheduled, runs
    /// against an object that no longer exists.
    func testAToolbarDroppedMidPostAnswersNothingAndDoesNotCrash() {
        ModuleHost.shared.shutdown()
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        @MainActor final class Holder { var rig: AnyObject? }
        let holder = Holder()
        weak var weakToolbar: SettingsToolbar?
        var dropped = 0
        let dropper = NotificationCenter.default.addObserver(
            forName: .helmModuleDisabled, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if holder.rig != nil { dropped += 1 }
                holder.rig = nil
            }
        }
        defer { NotificationCenter.default.removeObserver(dropper) }
        var window: NSWindow?
        autoreleasepool {
            let rig = mountSplit(pane: 1060, selection: .module(Self.keepAwake))
            settle(rig.window, turns: 10)
            weakToolbar = rig.toolbar
            window = rig.window
            holder.rig = rig.toolbar
        }
        XCTAssertNotNil(weakToolbar, "the toolbar was gone before the post — the case never ran")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
        settle(window!, turns: 5)
        XCTAssertEqual(dropped, 1, "the dropping observer never ran")
        XCTAssertNil(weakToolbar, "the toolbar outlived the post that let it go")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        settle(window!, turns: 5)
    }
}
