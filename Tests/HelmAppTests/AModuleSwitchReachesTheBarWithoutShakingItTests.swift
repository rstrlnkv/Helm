import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_UI
import Module_VPN_UI
@testable import HelmApp
@testable import HelmUI

/// **What a module switched on or off does to the page bar it was not written for** — the bar the
/// Settings window holds, mounted in a window through `LivePageToolbarFixture`.
///
/// `ShellPageBar` hears `.helmModuleEnabled` and `.helmModuleDisabled` unfiltered: a switch of any module
/// reaches the bar on screen, whichever page that is. Three questions:
///
/// - A switch of another module while a tab page is showing (Homebrew's shape: tabs, actions, search) — the
///   menu-bar panel's «Turn on» (`PanelChrome.swift`) and the sidebar composer's toggle both reach it with the
///   Settings window open — must change no zone's frame, replace no zone's view, hide none and measure the tabs
///   again not once, at a width where the tabs are full and at one where they are folded.
/// - The page's own module flipped off and on faster than its page can withdraw and redeclare must leave the
///   bar this fixture shows at General (the name alone, where the selection goes for good) still, and the page
///   selected again must have its own bar back, live.
/// - A `ShellPageBar` let go of, including in the middle of the very post it observes, must neither be kept
///   alive by its observers nor answer one.
///
/// "Nothing moved" is read two ways: a state read after every switch (on the tab page at once and again
/// after the fixture has settled, on the name-only bar once it has settled), and a watch on the zones'
/// views from the first switch to the last (every `frameDidChange` of a zone's view or the bar's, every
/// `isHidden` that flips), which sees a frame that moves and comes back inside one
/// switch. The two rows about another module's switch first prove what their absence is about: the bar
/// is in the window and laid out, and the zones the row names have a width. On the tab page the row also proves that the page is shown live, that the switch reached the bar (the
/// page's `selectedTab` binding counts its reads, `show` reads it on every republication) and that the
/// watch counts a frame that really moves; on the name-only bar nothing shows that another module's
/// switch reached it.
///
/// Where the neighbour stops: `ThePageBarAfterItsModuleIsSwitchedOffTests` posts the notification by hand to a
/// bar in no window and reads what each zone is told and whether a press reaches the page's closures. These
/// rows go through `ModuleHost.setEnabled`, a bar in a window, and the zones' frames.
@MainActor
final class AModuleSwitchReachesTheBarWithoutShakingItTests: XCTestCase {

    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let vpn = VPNDescriptor.id.rawValue

    private var fixtures: [LivePageToolbarFixture] = []

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    override func tearDown() {
        for fx in fixtures { fx.drop() }
        fixtures = []
        ModuleHost.shared.shutdown()
        for id in [Self.keepAwake, Self.vpn] {
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        super.tearDown()
    }

    // MARK: - Rig

    /// Counts every read of the declared `selectedTab`: `ShellBarTabs.show` reads it on every
    /// republication, so a count that moved is the proof a post reached the bar.
    @MainActor private final class Reads { var count = 0 }

    /// Homebrew's own shape, with a selected-tab binding that counts.
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

    /// The fixture's window holds the page's bar and nothing else; its bar is the real one.
    private func mount(selection: SettingsSelection, width: CGFloat) -> LivePageToolbarFixture {
        let fx = LivePageToolbarFixture(EmptyView(), selection: selection, width: width, height: 700)
        fixtures.append(fx)
        return fx
    }

    private func declareTabPage(_ fx: LivePageToolbarFixture, _ reads: Reads) -> Int {
        let generation = fx.channel.nextGeneration()
        fx.channel.declare(tabPageContent(reads), token: Self.keepAwake, generation: generation)
        return generation
    }

    // MARK: - What the bar is showing

    /// One zone as the window holds it.
    private struct ZoneRead: Equatable {
        let zone: ShellPageBarView.Zone
        let view: ObjectIdentifier
        let frame: CGRect
        let hidden: Bool
    }

    /// Everything a switch elsewhere could move on the attached bar: each zone's view, frame and visibility,
    /// the bar view's own frame and its subviews in order. The zones are read through `view(for:)` in
    /// `Zone.allCases` order, so two reads are equal only when the same zones hold the same views.
    private struct ZoneFrames: Equatable {
        let bar: CGRect
        let subviews: [ObjectIdentifier]
        let zones: [ZoneRead]

        @MainActor init(_ bar: ShellPageBarView) {
            self.bar = bar.frame
            subviews = bar.subviews.map(ObjectIdentifier.init)
            zones = ShellPageBarView.Zone.allCases.compactMap { zone in
                bar.view(for: zone).map {
                    ZoneRead(zone: zone, view: ObjectIdentifier($0), frame: $0.frame, hidden: $0.isHidden)
                }
            }
        }

        func frame(of zone: ShellPageBarView.Zone) -> CGRect? { zones.first { $0.zone == zone }?.frame }
        var present: Set<ShellPageBarView.Zone> { Set(zones.filter { !$0.hidden }.map(\.zone)) }
    }

    /// The zones plus what the controller and the zones say of themselves.
    private struct BarState: Equatable, CustomStringConvertible {
        let frames: ZoneFrames
        let presentation: ShellPageBar.Presentation
        let tabsFolded: Bool
        let actionsInteractive: Bool
        let statusWord: String?

        var description: String {
            "presentation=\(presentation) tabsFolded=\(tabsFolded) actionsInteractive=\(actionsInteractive) "
                + "status=\(statusWord ?? "nil") bar=\(frames.bar) "
                + "zones=\(frames.zones.map { "\($0.zone):\($0.frame)\($0.hidden ? " hidden" : "")" })"
        }
    }

    private func state(_ fx: LivePageToolbarFixture) -> BarState {
        BarState(frames: ZoneFrames(fx.bar.view), presentation: fx.bar.presentation,
                 tabsFolded: fx.bar.view.verdicts.tabsFolded,
                 actionsInteractive: fx.pageBar.actions.model.isInteractive,
                 statusWord: statusWord(fx.bar.view))
    }

    private func statusWord(_ bar: ShellPageBarView) -> String? {
        (bar.view(for: .status) as? NSHostingView<StatusZoneView>)?.rootView.status?.word
    }

    /// The bar is in the fixture's window, found from the window and not from the fixture, and has been
    /// laid out.
    private func assertBarIsLive(_ fx: LivePageToolbarFixture, _ label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let found = fx.mount.window?.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        XCTAssertTrue(found === fx.bar.view, "\(label): the fixture's bar is in no window", file: file, line: line)
        XCTAssertNotNil(fx.bar.view.frames, "\(label): the bar was never laid out", file: file, line: line)
        XCTAssertGreaterThan(fx.bar.view.view(for: .name)?.frame.width ?? 0, 0,
                             "\(label): the name has no room", file: file, line: line)
    }

    /// Every frame change of the bar or of a zone's view that was there when it started, and every
    /// `isHidden` that flips on one of them.
    @MainActor private final class ZoneWatch {
        var frameChanges: [String] = []
        var visibilityChanges: [String] = []
        private var tokens: [NSObjectProtocol] = []
        private var kvo: [NSKeyValueObservation] = []

        @MainActor init(_ bar: ShellPageBarView) {
            var watched: [(String, NSView)] = [("bar", bar)]
            for zone in ShellPageBarView.Zone.allCases {
                if let view = bar.view(for: zone) { watched.append(("\(zone)", view)) }
            }
            for (name, view) in watched {
                view.postsFrameChangedNotifications = true
                tokens.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: view, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.frameChanges.append(name) }
                })
                kvo.append(view.observe(\.isHidden, options: [.old, .new]) { [weak self] _, change in
                    guard change.oldValue != change.newValue else { return }
                    MainActor.assumeIsolated { self?.visibilityChanges.append(name) }
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

    /// **VPN switched off and on six times while a Homebrew-shaped page, held by Keep Awake (which stays
    /// on), is on screen**, at a width where the tabs are full (English, 1060) and one where they are folded
    /// (Russian, 560). The bar is read after every single switch, before the fixture settles, and
    /// again after it has settled; the watch sees a frame that moves and returns inside one switch.
    func testAnotherModulesSwitchMovesNoZoneOnATabPage() {
        let cases: [(AppLanguage, CGFloat, Bool)] = [(.en, 1060, false), (.ru, 560, true)]
        for (language, width, folded) in cases {
            AppLanguage.only(language) {
                let label = "\(language) \(width) (\(folded ? "folded" : "full"))"
                ModuleHost.shared.shutdown()
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                let reads = Reads()
                let fx = mount(selection: .module(Self.keepAwake), width: width)
                _ = declareTabPage(fx, reads)
                fx.settle(40)
                let before = state(fx)

                // The subject: a bar in the window showing the tab page live, with the fold this case is
                // named for, and the zones a switch could move holding a width.
                assertBarIsLive(fx, label)
                XCTAssertEqual(before.presentation, .page(key: Self.keepAwake, isLive: true, isDimmed: false),
                               "\(label): the tab page is not the one shown live — \(before)")
                XCTAssertTrue(before.frames.present.isSuperset(of: [.name, .tabs, .actions]),
                              "\(label): a zone of the tab page is missing — \(before)")
                for zone in [ShellPageBarView.Zone.name, .tabs, .actions] {
                    XCTAssertGreaterThan(before.frames.frame(of: zone)?.width ?? 0, 0, "\(label): \(zone) has no width")
                }
                XCTAssertEqual(before.tabsFolded, folded, "\(label): the tabs are not \(folded ? "folded" : "full") to begin with")
                XCTAssertTrue(before.actionsInteractive, "\(label): the page is not live to begin with")

                let watch = ZoneWatch(fx.bar.view)
                let readsBefore = reads.count
                let measuredBefore = fx.pageBar.tabs.measureCount
                let redrawnBefore = fx.pageBar.tabs.redrawCount
                var seen: [String] = []
                for round in 0..<6 {
                    ModuleHost.shared.setEnabled(VPNDescriptor(), round % 2 == 1)
                    let now = state(fx)
                    if now != before { seen.append("round \(round), at once: \(now)") }
                    fx.settle(12)
                    let settled = state(fx)
                    if settled != before { seen.append("round \(round), settled: \(settled)") }
                }
                watch.stop()

                XCTAssertGreaterThan(reads.count, readsBefore, """
                    \(label): six module switches never reached the bar at all — every absence below \
                    would pass for a bar that did not hear them
                    """)
                XCTAssertEqual(seen, [], "\(label): another module's switch moved the tab page's bar; before: \(before)")
                XCTAssertEqual(watch.frameChanges, [], "\(label): a frame changed during the switches")
                XCTAssertEqual(watch.visibilityChanges, [], "\(label): a zone was hidden or shown during the switches")
                XCTAssertEqual(fx.pageBar.tabs.measureCount, measuredBefore, "\(label): the tabs were measured again")
                XCTAssertEqual(fx.pageBar.tabs.redrawCount, redrawnBefore, "\(label): the tabs were redrawn")

                // The watch can see: a frame that really moves is counted.
                let control = ZoneWatch(fx.bar.view)
                fx.bar.view.measures.name += 40
                fx.settle(2)
                control.stop()
                XCTAssertTrue(control.frameChanges.contains("name"),
                              "\(label): the watch saw no frame move when the name was widened — the zero above is about a deaf watch")
            }
        }
    }

    // MARK: - 2. Another module's switch, under the name-only bar

    /// **General, and Keep Awake's own page, while VPN is switched off and on** — General shows the name
    /// alone and Keep Awake's page the name and Keep Awake's word; both keep their zones' views and frames,
    /// and the word stays the page's own reading.
    func testAnotherModulesSwitchMovesNoZoneOnTheNameOnlyBar() {
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            ModuleHost.shared.setEnabled(VPNDescriptor(), true)
            for selection in [SettingsSelection.general, .module(Self.keepAwake)] {
                let fx = mount(selection: selection, width: 1060)
                fx.settle(30)
                let before = state(fx)
                assertBarIsLive(fx, "\(selection)")
                let expected: String? = selection == .general ? nil : liveWord(Self.keepAwake)
                if selection != .general {
                    XCTAssertNotNil(expected, "Keep Awake is on and reports no activity")
                }
                XCTAssertEqual(before.statusWord, expected, "\(selection): the status to begin with")
                XCTAssertEqual(before.frames.present, selection == .general ? [.name] : [.name, .status],
                               "\(selection): not the name-only bar — \(before)")
                for zone in before.frames.present {
                    XCTAssertGreaterThan(before.frames.frame(of: zone)?.width ?? 0, 0, "\(selection): \(zone) has no width")
                }

                let watch = ZoneWatch(fx.bar.view)
                var seen: [String] = []
                for round in 0..<6 {
                    ModuleHost.shared.setEnabled(VPNDescriptor(), round % 2 == 1)
                    fx.settle(8)
                    let now = state(fx)
                    if now != before { seen.append("round \(round): \(now)") }
                }
                watch.stop()
                XCTAssertEqual(seen, [], "\(selection): VPN's switch moved the bar; before: \(before)")
                XCTAssertEqual(watch.frameChanges, [], "\(selection): a frame changed")
                XCTAssertEqual(watch.visibilityChanges, [], "\(selection): a zone was hidden or shown")

                // Keep Awake switched off takes its word off this bar. This does not show that the bar hears
                // a module's switch: the selection moves to General when its module goes off (`SettingsModel`)
                // and the bar follows the selection, so a bar deaf to both notifications passes here too.
                // Nothing in this row shows that VPN's switch reached the bar.
                if selection != .general {
                    ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                    fx.settle(8)
                    XCTAssertNil(statusWord(fx.bar.view),
                                 "Keep Awake was switched off and its word is still on this bar")
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

    // MARK: - 3. The page's own module, flipped faster than the page follows

    /// **Off and on again.** The first switch-off is in the order the app delivers it — the post from
    /// `ModuleHost.setEnabled` first and synchronously, the page's withdraw after it. Every declare in the
    /// eight rounds, the first one's included, and the seven later withdraws land under a selection that is
    /// already General: the app sends none of those, because the page is no longer mounted
    /// (`SettingsDetail`), so they are stray writes the bar must ignore. The eight flips after them are the
    /// two posts alone, which the app does send with General selected. Then one switch-off held longer than
    /// `ShellPageBar.graceInterval`; no grace is armed on this route, so that wait tells nothing apart.
    /// A module that is off reads as General (`ShellSidebarRows.settled`, applied by `SettingsModel` at every
    /// change of `live`) and nothing brings the selection back, so the first switch-off moves the selection
    /// to General for good. What the bar owes is that, from then on, the flips move no zone: it is the name
    /// alone after the first switch, in the same views and frames after every later one, and the selection
    /// is still General at the end. Then the person selects the module again, the page declares afresh, and
    /// the bar equals the one the page had at the start, with its controls live.
    ///
    /// Keep Awake's id stands for a tab page here: the bar keys the page on its id and asks the host only
    /// whether that id is live, so a real descriptor is what `isModuleSwitchedOff()` needs and the content is
    /// what the channel carries.
    func testThePagesOwnModuleSwitchedOffLeavesTheNameOnlyBarStillAndReselectingItRestoresItsBar() {
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            let reads = Reads()
            let fx = mount(selection: .module(Self.keepAwake), width: 1060)
            var generation = declareTabPage(fx, reads)
            fx.settle(40)
            let live = state(fx)
            assertBarIsLive(fx, "the tab page")
            XCTAssertEqual(live.presentation, .page(key: Self.keepAwake, isLive: true, isDimmed: false),
                           "the page's bar is not the one attached — \(live)")
            XCTAssertFalse(live.tabsFolded, "the tabs are not full to begin with — \(live)")
            XCTAssertTrue(live.actionsInteractive, "the page's bar is not live to begin with")
            XCTAssertTrue(live.frames.present.isSuperset(of: [.name, .tabs, .actions]), "\(live)")

            // Eight fast flips. The first round moves the selection to General; the bar it settles on
            // is the one every later round must leave untouched.
            var general: BarState?
            for round in 0..<8 {
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                fx.channel.withdraw(token: Self.keepAwake, generation: generation)
                fx.settle(2)
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
                generation = declareTabPage(fx, reads)
                fx.settle(2)
                if round == 0 {
                    fx.settle(30)
                    let now = state(fx)
                    general = now
                    XCTAssertEqual(fx.model.selection, .general,
                                   "switched off under its own page and the selection did not move to General")
                    XCTAssertEqual(now.frames.present, [.name],
                                   "the first switch-off did not leave the name alone — \(now)")
                    XCTAssertEqual(now.presentation, .nameOnly, "\(now)")
                    XCTAssertNotEqual(now, live, "the name-only bar is the page's bar")
                } else if let general {
                    let now = state(fx)
                    XCTAssertEqual(now, general, "round \(round) moved the name-only bar")
                }
            }
            fx.settle(30)
            XCTAssertEqual(state(fx), general, "eight fast flips with the rig's own withdraw and declare")
            XCTAssertEqual(fx.model.selection, .general, "a switch-on brought the selection back by itself")

            // No withdraw at all between the two posts.
            for _ in 0..<8 {
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
                ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            }
            fx.settle(30)
            XCTAssertEqual(state(fx), general, "eight flips the page never withdrew for")

            // Off, and held longer than `ShellPageBar.graceInterval`. No grace is armed on this route:
            // the selection is already General and the bar holds no page for it. What is read is that the
            // bar is still the name alone and says nothing about the module that is off.
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
            fx.channel.withdraw(token: Self.keepAwake, generation: generation)
            let fellBack = expectation(description: "longer than the grace interval")
            DispatchQueue.main.asyncAfter(deadline: .now() + fx.bar.graceInterval + 0.3) {
                fellBack.fulfill()
            }
            wait(for: [fellBack], timeout: 3)
            fx.settle(5)
            let off = state(fx)
            XCTAssertEqual(off.frames.present, [.name], "switched off and held, and the bar is not the name alone — \(off)")
            XCTAssertNil(off.statusWord, "the bar says a status for a module that is off")
            XCTAssertEqual(off.frames.frame(of: .name), general?.frames.frame(of: .name), "the name moved")

            // On again, and the person selects it again: the page declares afresh, as the rig does it,
            // and the bar is the page's own.
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            fx.settle(5)
            XCTAssertEqual(fx.model.selection, .general, "a switch-on brought the selection back by itself")
            fx.model.selection = .module(Self.keepAwake)
            generation = declareTabPage(fx, reads)
            fx.settle(40)
            // Read as frames, word and liveness: the actions zone builds a new view when the page comes back after the name alone, measured.
            let again = state(fx)
            XCTAssertEqual(again.description, live.description, "the module selected again does not show its own bar")
            XCTAssertEqual(again.frames.zones.map(\.frame), live.frames.zones.map(\.frame))
            XCTAssertEqual(again.frames.subviews.count, live.frames.subviews.count)
        }
    }

    // MARK: - 4. A bar let go of

    /// **Let go of with its view still in the window, then both posts** — nothing kept the controller alive
    /// (its observers capture it weakly), and the view it left behind does not move for a post nobody is left
    /// to answer. The page is Keep Awake's, live, so a controller that survived would answer Keep Awake's
    /// switch by taking the word off the bar; the word is on the view before the release and is asserted.
    func testADroppedBarIsNotKeptAliveAndAnswersNoPost() {
        AppLanguage.only(.en) {
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            weak var weakBar: ShellPageBar?
            var barView: ShellPageBarView?
            var mounted: MountedRender?
            autoreleasepool {
                let fx = LivePageToolbarFixture(EmptyView(), selection: .module(Self.keepAwake), width: 1060, height: 700)
                fx.settle(30)
                weakBar = fx.bar
                barView = fx.bar.view
                mounted = fx.mount
            }
            defer { barView?.removeFromSuperview(); mounted?.drop() }
            guard let barView else { return XCTFail("no bar view") }
            // The subject: the view is in the window, shows the word, and the controller is the one thing gone.
            XCTAssertNotNil(barView.window, "the bar's view is in no window")
            XCTAssertNotNil(statusWord(barView), "the page's word is not on the view before the posts")
            for _ in 0..<5 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
            XCTAssertNil(weakBar, "a ShellPageBar nobody holds is still alive — something retains it")
            let before = ZoneFrames(barView)
            let wordBefore = statusWord(barView)
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
            for _ in 0..<5 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
            XCTAssertEqual(ZoneFrames(barView), before, "a post moved the view of a bar already gone")
            XCTAssertEqual(statusWord(barView), wordBefore, "a post redrew the word on the view of a bar already gone")
        }
    }

    /// **Let go of inside the post itself** — an observer registered before the bar's drops the last
    /// reference while `.helmModuleDisabled` is being delivered, so the bar's own block, already scheduled,
    /// runs against an object that no longer exists.
    func testABarDroppedMidPostAnswersNothingAndDoesNotCrash() {
        ModuleHost.shared.shutdown()
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        @MainActor final class Holder { var bar: ShellPageBar? }
        let holder = Holder()
        weak var weakBar: ShellPageBar?
        var dropped = 0
        let dropper = NotificationCenter.default.addObserver(
            forName: .helmModuleDisabled, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if holder.bar != nil { dropped += 1 }
                holder.bar = nil
            }
        }
        defer { NotificationCenter.default.removeObserver(dropper) }
        var barView: ShellPageBarView?
        var mounted: MountedRender?
        autoreleasepool {
            let fx = LivePageToolbarFixture(EmptyView(), selection: .module(Self.keepAwake), width: 1060, height: 700)
            fx.settle(10)
            weakBar = fx.bar
            barView = fx.bar.view
            mounted = fx.mount
            holder.bar = fx.bar
        }
        defer { barView?.removeFromSuperview(); mounted?.drop() }
        XCTAssertNotNil(weakBar, "the bar was gone before the post — the case never ran")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
        for _ in 0..<5 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(dropped, 1, "the dropping observer never ran")
        XCTAssertNil(weakBar, "the bar outlived the post that let it go")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        for _ in 0..<5 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }
}
