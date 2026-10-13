import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_UI
import Module_VPN_UI
@testable import HelmApp
@testable import HelmUI

/// **What the `.helmModuleEnabled`/`.helmModuleDisabled` pair on
/// `SettingsToolbar` does to every bar it was not written for** — the
/// `NSToolbar` the Settings window wears, read through its items.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator`, on a split-view rig of its own or on a
/// `LivePageInTheToolbarFixture`, not the `lead: .spacer` bar the app's window
/// builds: it has no `helm.tabsLead` and no capped search field. `helm.name` is
/// on it under both looks (the style is pinned to `.moduleName`); `helm.status`
/// is on the shared name-only bar alone.
///
/// **The look.** It is read when a bar is built (`AppSettings.barAppearance`)
/// and decides what the tabs item is: a `ShellBarPlate` around the hosting view
/// under Flat, the hosting view itself under Liquid Glass, and the tabs are
/// wider under Flat. The tab-page row (two fold cases), the shared-bar row and
/// the row of the page's own module run under each look (`underEachLook`); the
/// first and the third say in their precondition which look the tabs item
/// wears, the shared bar has no tabs item to say it. The two rows about a
/// toolbar let go of read no cell and run under Flat, the look `PinnedBarSettings`
/// writes. The bars of one look are dropped before the next look is written: a look
/// written reaches every toolbar still alive (`.helmBarAppearanceChanged`) and each
/// would rebuild under it, inside the other case's watch.
///
/// The pair is deliberately unfiltered: a switch of *any* module reaches the
/// bar on screen, whichever page that is. Three questions:
///
/// - A switch of some other module while a tab page is showing (Homebrew's
///   shape: tabs, actions, search) — the menu-bar panel's «Turn on»
///   (`PanelChrome.swift`) and the sidebar composer's toggle both reach it with
///   the settings window open — must attach no new toolbar, rewrite no
///   identifier, reseat no item, evict nothing and move no fold, at a pane
///   where the tabs are full and at one where they are folded.
/// - The page's own module flipped off and on faster than its page can
///   withdraw and redeclare must leave the shared name-only bar this rig shows at General (where the
///   selection goes for good) still, and the page selected again must have its own bar, live.
/// - A `SettingsToolbar` let go of — including in the middle of the very post
///   it observes — must neither be kept alive by its observers nor answer one.
///
/// The tab-page row proves the post reached the toolbar at all, through a
/// `selectedTab` binding that counts its reads: a bar that never heard the
/// switch would pass every absence below for nothing. The shared-bar row has
/// no such count and says so. Every watch of items added, removed or evicted
/// is shown to see items removed and added in every case, and one evicted in
/// the full cases and on the shared bar (`assertTheWatchSeesChurn`).
@MainActor
final class AModuleSwitchReachesTheBarWithoutShakingItTests: XCTestCase {

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let vpn = VPNDescriptor.id.rawValue
    /// The rig's sidebar width, as `AnUnfoldIsPredictedNeverTrialledTests` has it.
    private static let sidebarWidth: CGFloat = 214

    private var fixtures: [LivePageInTheToolbarFixture] = []

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
        // Runs before the settings `pin` put back (teardown blocks run last-in first). A teardown override is
        // nonisolated and warns on every main-actor property it touches.
        addTeardownBlock { @MainActor [self] in
            dropFixtures()
            ModuleHost.shared.shutdown()
            for id in [Self.keepAwake, Self.vpn] {
                UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
            }
        }
    }

    /// Runs `body` once under each look; the bars it builds wear that look. What the body built on a fixture is
    /// dropped (`dropFixtures`) before the next look is written, see the header; a split rig takes its toolbar
    /// off itself at the end of a case.
    private func underEachLook(_ body: (HelmBarAppearance) -> Void) {
        for look in HelmBarAppearance.allCases {
            AppSettings.barAppearance = look
            body(look)
            dropFixtures()
        }
    }

    private func dropFixtures() {
        for fx in fixtures {
            fx.mount.window?.toolbar = nil
            fx.drop()
        }
        fixtures = []
    }

    /// What the tabs item's view says of the look the bar was built under: a `ShellBarPlate` under Flat, the
    /// hosting view under Liquid Glass. Nil when the bar has no tabs item. Folded or full alike, the item's
    /// view is the same one (`SettingsToolbar.makeTabsItem`).
    private func lookDrawn(_ window: NSWindow) -> HelmBarAppearance? {
        guard let view = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "helm.tabs" })?.view
        else { return nil }
        return view is ShellBarPlate ? .flat : .liquidGlass
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

    /// A split-view rig, so `offeredRoom()` reads a detail pane and the fold is the rig's.
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
    /// segment count of the one segmented control the tabs host draws: three
    /// when the tabs are full, one when they are folded, nil when the bar has no
    /// tabs control), and whether the controls are live.
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

    /// The bar's reading. The actions capsule is read through `ActionsCapsuleReading`, which records a failure
    /// that names what it could not find; it is asked only when the bar holds a `helm.actions` item, so a bar
    /// with none (the name-only bar) reads `nil` and a bar whose item holds no capsule fails.
    private func state(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) -> BarState {
        let toolbar = window.toolbar
        let items = toolbar?.items ?? []
        let tabs = items.first { $0.itemIdentifier.rawValue == "helm.tabs" }
        let capsule: HelmToolbarActionsCapsule? = toolbar.flatMap { bar in
            SettingsWindowRig.item("helm.actions", in: bar) == nil ? nil
                : try? ActionsCapsuleReading.read(bar, context: "the bar's state", file: file, line: line).capsule
        }
        let search = items.compactMap { $0 as? NSSearchToolbarItem }.first
        return BarState(
            toolbar: toolbar.map(ObjectIdentifier.init),
            identifiers: toolbar?.itemIdentifiers.map(\.rawValue) ?? [],
            items: items.map(ObjectIdentifier.init),
            tabsView: tabs?.view.map(ObjectIdentifier.init),
            segments: tabs?.view?.everyView(ofType: NSSegmentedControl.self).first?.segmentCount,
            visible: items.filter { $0.isVisible }.map(\.itemIdentifier.rawValue),
            searchEnabled: search?.searchField.isEnabled,
            actionsInteractive: capsule?.model.isInteractive)
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

    /// The watch can see: on the bar the window wears, an item taken out and put back is counted as removed
    /// and added, and a window made too narrow for its items evicts one of them
    /// (`isVisible` going false) unless `seesEviction` is false, for a bar the window cannot overflow. Last in
    /// a case, because it leaves the bar changed.
    private func assertTheWatchSeesChurn(_ window: NSWindow, _ label: String, seesEviction: Bool = true,
                                         settle: () -> Void,
                                         file: StaticString = #filePath, line: UInt = #line) {
        guard let toolbar = window.toolbar, let last = toolbar.itemIdentifiers.last else {
            return XCTFail("\(label): the window wears no toolbar with an item in it, nothing to watch", file: file, line: line)
        }
        let control = ChurnWatch(toolbar)
        toolbar.removeItem(at: toolbar.itemIdentifiers.count - 1)
        toolbar.insertItem(withItemIdentifier: last, at: toolbar.itemIdentifiers.count)
        window.setContentSize(NSSize(width: 120, height: 700))
        settle()
        control.stop()
        XCTAssertGreaterThan(control.removed, 0, "\(label): the watch saw no didRemoveItem when an item was taken out — the zero above is about a deaf watch", file: file, line: line)
        XCTAssertGreaterThan(control.added, 0, "\(label): the watch saw no willAddItem when an item was put in — the zero above is about a deaf watch", file: file, line: line)
        if seesEviction {
            XCTAssertFalse(control.evicted.isEmpty, "\(label): the watch saw no item evicted when the window was made 120 pt wide — the empty list above is about a deaf watch", file: file, line: line)
        }
    }

    // MARK: - 1. Another module's switch, under a tab page

    /// **VPN switched off and on six times while a Homebrew-shaped page, held
    /// by Keep Awake (which stays on), is on screen**, at a pane where the tabs are full (English, 1060) and
    /// one where they are folded (Russian, 560), under each look. The bar is read after every
    /// single switch, before anything settles, and again after the settle
    /// each switch schedules — a blink that comes and goes inside one
    /// switch is the one a before/after pair would miss.
    ///
    /// The precondition of each case reads the look the tabs item wears, the toolbar it is, the fold it is
    /// named for (three segments in one control, or one) and that the page's actions are live; the six
    /// switches must reach the bar (the declared `selectedTab` counts its reads). A bar that heard nothing, or
    /// one that never held the page, prints one of those sentences, and the watch itself is shown to see
    /// an item removed and added, and in the full cases evicted (`assertTheWatchSeesChurn`).
    func testAnotherModulesSwitchMovesNothingOnATabPage() {
        let cases: [(AppLanguage, CGFloat, String)] = [(.en, 1060, "full"), (.ru, 560, "folded")]
        underEachLook { look in
            for (spoken, pane, fold) in cases {
                AppLanguage.only(spoken) {
                    ModuleHost.shared.shutdown()
                    ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                    let reads = Reads()
                    let rig = mountSplit(pane: pane, selection: .module(Self.keepAwake))
                    rig.channel.declare(tabPageContent(reads), token: Self.keepAwake,
                                        generation: rig.channel.nextGeneration())
                    settle(rig.window, turns: 40)
                    let before = state(rig.window)
                    let language = "\(look) \(spoken)"
                    XCTAssertNotNil(before.toolbar, "\(language) \(pane): no toolbar attached")
                    XCTAssertTrue(before.identifiers.contains("helm.tabs"),
                                  "\(language) \(pane): the tab page's own bar is not the one attached — \(before)")
                    XCTAssertEqual(lookDrawn(rig.window), look, """
                        \(language) \(pane): the tabs item wears \
                        \(lookDrawn(rig.window).map { String(describing: $0) } ?? "no view at all"), not the look \
                        the bar was built under — the fold below would be read under the wrong cell
                        """)
                    XCTAssertEqual(before.actionsInteractive, true,
                                   "\(language) \(pane): the tab page's actions are not live to begin with — \(before)")
                    // The subject: the fold state this case is named for really is
                    // the one on screen, or "the fold did not move" is about
                    // nothing.
                    if fold == "full" {
                        XCTAssertEqual(before.segments, 3, "\(language) \(pane): tabs not full to begin with — \(before)")
                    } else {
                        XCTAssertEqual(before.segments, 1,
                                       "\(language) \(pane): tabs not folded to begin with — \(before)")
                    }

                    let watch = ChurnWatch(rig.window.toolbar)
                    let readsBefore = reads.count
                    var seen: [String] = []
                    for round in 0..<6 {
                        ModuleHost.shared.setEnabled(VPNDescriptor(), round % 2 == 1)
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
                    // The folded bar's window cannot be made narrower than the split rig's panes, and a bar
                    // whose tabs are already a menu overflows nothing: eviction is shown on the full cases.
                    assertTheWatchSeesChurn(rig.window, "\(language) \(pane)", seesEviction: fold == "full") {
                        settle(rig.window, turns: 20)
                    }
                    rig.window.toolbar = nil
                    _ = rig
                }
            }
        }
    }

    // MARK: - 2. Another module's switch, under the shared name-only bar

    /// **General, and Keep Awake's own page, while VPN is switched off and on**
    /// — the shared bar keeps its toolbar, its items and its status host, and
    /// Keep Awake's word stays the page's own reading. Under each look: the look is written before the bar
    /// is built, and this bar has no tabs item to read it back from, so what is read is the bar's stillness
    /// under both and not the look it wears.
    ///
    /// The precondition is a bar with `helm.status` whose host is the one this row reads, saying the word
    /// the page says (nothing, at General); a bar that is not the name-only one, or whose status item is
    /// something else, prints that sentence. The watch is shown to see an item come and go
    /// (`assertTheWatchSeesChurn`). **Nothing in this row shows that VPN's switch reached the bar**: Keep
    /// Awake switched off moves the selection to General (`SettingsModel`) and the bar follows the selection,
    /// so a bar deaf to both notifications passes the last check too; the tab-page row counts reads for that.
    func testAnotherModulesSwitchMovesNothingOnTheSharedBar() {
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            ModuleHost.shared.setEnabled(VPNDescriptor(), true)
            underEachLook { look in
                for selection in [SettingsSelection.general, .module(Self.keepAwake)] {
                    let label = "\(look) \(selection)"
                    let fx = LivePageInTheToolbarFixture(EmptyView(), selection: selection, width: 1060, height: 700)
                    fx.settle(30)
                    fixtures.append(fx)
                    guard let window = fx.mount.window else { return XCTFail("\(label): no window") }
                    let before = state(window)
                    let statusBefore = statusHost(window.toolbar)
                    XCTAssertTrue(before.identifiers.contains("helm.status"),
                                  "\(label): not the shared name-only bar — \(before)")
                    XCTAssertNotNil(statusBefore,
                                    "\(label): the status item's view is not a StatusZoneView host — \(before)")
                    let expected: String? = selection == .general ? nil : liveWord(Self.keepAwake)
                    if selection != .general {
                        XCTAssertNotNil(expected, "Keep Awake is on and reports no activity")
                    }
                    XCTAssertEqual(statusBefore?.rootView.status?.word, expected,
                                   "\(label): the status to begin with")

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
                    XCTAssertEqual(seen, [], "\(label): VPN's switch moved the shared bar; before: \(before)")
                    XCTAssertEqual(watch.added + watch.removed, 0, "\(label): items added or removed")
                    XCTAssertEqual(watch.evicted, [], "\(label): items evicted")
                    // Keep Awake's own switch takes its word off this bar: the word was there to be taken.
                    if selection != .general {
                        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                        fx.settle(8)
                        XCTAssertNil(statusHost(window.toolbar)?.rootView.status,
                                     "\(label): Keep Awake was switched off and its word is still on this bar")
                        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                    }
                    assertTheWatchSeesChurn(window, label) { fx.settle(20) }
                    dropFixtures()
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

    /// **Off and on again.** The first switch-off is in the order the app
    /// delivers it — the post from `ModuleHost.setEnabled` first and
    /// synchronously, the page's withdraw after it. Every declare in the eight
    /// rounds, the first one's included, and the seven later withdraws land
    /// under a selection that is already General: the app sends none of those,
    /// because the page is no longer mounted (`SettingsDetail`), so they are
    /// stray writes the bar must ignore. The eight flips after them are the two
    /// posts alone, which the app does send with General selected. Then one
    /// switch-off held longer than `SettingsToolbar.graceInterval`; no grace is
    /// armed on this route, so that wait tells nothing apart. A module that is off reads as
    /// General (`ShellSidebarRows.settled`, applied by `SettingsModel` at every
    /// change of `live`) and nothing brings the selection back, so the first
    /// switch-off moves the selection to General for good. What the bar owes
    /// is that, from then on, the flips shake nothing: it is the bar the rig
    /// shows at General after the first switch — the shared name-only one,
    /// since nothing here declares General's tabs as `SettingsDetail` does in
    /// the app — and the same toolbar with the same items after every later one, and the selection is still General at the end. Then
    /// the person selects the module again, the page declares afresh, and the
    /// bar equals the one the page had at the start, with its controls live.
    ///
    /// Under each look. The precondition is the page's own bar, live, in the look under test (the tabs item
    /// wears it, three segments, the capsule interactive); and the first switch-off must leave the selection
    /// at General and a bar with `helm.status` and no `helm.tabs`, different from the page's: a module that
    /// was never switched off, or a bar that never left the page, prints those sentences.
    ///
    /// Keep Awake's id stands for a tab page here: `SettingsToolbar` keys the
    /// bar on the page and asks the host only whether that id is live, so a
    /// real descriptor is what `isModuleSwitchedOff()` needs and the content
    /// is what the channel carries.
    func testThePagesOwnModuleSwitchedOffLeavesTheSharedNameOnlyBarStillAndReselectingItRestoresItsBar() {
        underEachLook { look in pagesOwnModuleSwitchedOff(look) }
    }

    private func pagesOwnModuleSwitchedOff(_ look: HelmBarAppearance) {
        let tag = "\(look): "
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            let reads = Reads()
            let rig = mountSplit(pane: 1060, selection: .module(Self.keepAwake))
            var generation = rig.channel.nextGeneration()
            rig.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
            settle(rig.window, turns: 40)
            let live = state(rig.window)
            XCTAssertEqual(lookDrawn(rig.window), look, "\(tag)the tabs item does not wear the look the bar was built under")
            XCTAssertEqual(live.segments, 3, "\(tag)the page's bar is not the one attached — \(live)")
            XCTAssertEqual(live.actionsInteractive, true, "\(tag)the page's bar is not live to begin with")

            // Eight fast flips. The first round moves the selection to
            // General; the bar it settles on (the shared name-only bar this
            // rig shows at General) is the one every later round must leave
            // untouched.
            var general: BarState?
            for round in 0..<8 {
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                rig.channel.withdraw(token: Self.keepAwake, generation: generation)
                settle(rig.window, turns: 2)
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                generation = rig.channel.nextGeneration()
                rig.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
                settle(rig.window, turns: 2)
                if round == 0 {
                    settle(rig.window, turns: 30)
                    general = state(rig.window)
                    XCTAssertEqual(rig.model.selection, .general,
                                   "\(tag)switched off under its own page and the selection did not move to General")
                    XCTAssertTrue(general?.identifiers.contains("helm.status") == true
                                  && general?.identifiers.contains("helm.tabs") == false,
                                  "\(tag)the first switch-off did not leave the shared name-only bar this rig shows at General — \(String(describing: general))")
                    XCTAssertNotEqual(general, live, "\(tag)the shared name-only bar this rig shows at General is the page's bar")
                } else if let general {
                    let now = state(rig.window)
                    XCTAssertEqual(now, general, "\(tag)round \(round) moved the shared name-only bar this rig shows at General")
                }
            }
            settle(rig.window, turns: 30)
            XCTAssertEqual(state(rig.window), general, "\(tag)eight fast flips with the rig's own withdraw and declare")
            XCTAssertEqual(rig.model.selection, .general, "\(tag)a switch-on brought the selection back by itself")

            // No withdraw at all between the two posts.
            for _ in 0..<8 {
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            }
            settle(rig.window, turns: 30)
            XCTAssertEqual(state(rig.window), general, "\(tag)eight flips the page never withdrew for")

            // Off, and held longer than `SettingsToolbar.graceInterval`. No
            // grace is armed on this route — the selection is already General
            // and this rig caches no bar for it — so the wait tells nothing
            // apart: deleting `assignNameOnly()` from `armGrace`'s closure
            // leaves this family green. What is read is that the bar still
            // carries `helm.status` and says nothing about the module that
            // is off.
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
            rig.channel.withdraw(token: Self.keepAwake, generation: generation)
            let fellBack = expectation(description: "longer than the grace interval")
            DispatchQueue.main.asyncAfter(deadline: .now() + SettingsToolbar.graceInterval + 0.3) {
                fellBack.fulfill()
            }
            wait(for: [fellBack], timeout: 3)
            settle(rig.window, turns: 5)
            let off = state(rig.window)
            XCTAssertTrue(off.identifiers.contains("helm.status"),
                          "\(tag)switched off, held longer than the grace interval, and the bar carries no helm.status — \(off)")
            XCTAssertNil(statusHost(rig.window.toolbar)?.rootView.status,
                         "\(tag)the shared bar says a status for a module that is off")

            // On again, and the person selects it again: the page declares
            // afresh, as the rig does it, and the bar is the page's own.
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            settle(rig.window, turns: 5)
            XCTAssertEqual(rig.model.selection, .general, "\(tag)a switch-on brought the selection back by itself")
            rig.model.selection = .module(Self.keepAwake)
            generation = rig.channel.nextGeneration()
            rig.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
            settle(rig.window, turns: 40)
            XCTAssertEqual(state(rig.window), live, "\(tag)the module selected again does not show its own bar")
            rig.window.toolbar = nil
            _ = rig
        }
    }

    // MARK: - 4. A toolbar let go of

    /// **Let go of with its window still up, then both posts** — nothing kept
    /// it alive (the observers capture it weakly), and the window's bar does
    /// not move for a post nobody is left to answer. Under Flat, the look `PinnedBarSettings` writes: what is
    /// read is the object's lifetime and the bar's items, not a cell. The precondition is that the window
    /// still wears a toolbar with items in it after the `SettingsToolbar` is gone (a window that lost its
    /// bar would pass the equality below for nothing); a toolbar kept alive prints the first sentence.
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
        let before = window.map { state($0) }
        XCTAssertFalse(before?.identifiers.isEmpty ?? true,
                       "the window wears no bar with items once its SettingsToolbar is gone — \(String(describing: before))")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
        settle(window!, turns: 5)
        XCTAssertEqual(window.map { state($0) }, before, "a post moved the bar of a toolbar already gone")
        window?.toolbar = nil
        _ = keep
    }

    /// **Let go of inside the post itself** — an observer registered before
    /// the toolbar's drops the last reference while `.helmModuleDisabled` is
    /// being delivered, so the toolbar's own block, already scheduled, runs
    /// against an object that no longer exists. Under Flat, as the row above. The observer must have run and
    /// the toolbar must have been alive at the post (both asserted), so that "nothing happened" is about a
    /// toolbar that was let go of inside the post and not about one that never was.
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
