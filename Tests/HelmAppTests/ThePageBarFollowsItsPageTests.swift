import AppKit
import Combine
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`ShellPageBar` hears the page's channel, the selection and the settings, tells the
/// bar's three zones what to show, and answers nothing once it is released.**
///
/// No window is ordered anywhere. The bar is built on a `SettingsModel` over the shared
/// host, and no row relies on what that host holds: the module ids the rows select are ones the registry
/// does not hold, so no module is ever live for them, whatever other tests enabled on the shared host. It is built
/// on three fake zones that record what they were told. The only waits are on the main run loop: for the
/// bar's own `graceInterval`, which each bar here shrinks to a fifth of a second, for a notification or a
/// signal the main queue delivers, and for a released bar to stay silent; every wait names its deadline.
///
/// A fake counts the states it was shown and keeps only the last one whole: a state carries the page's
/// closures, and a fake that kept every one would keep alive the very objects the rows below ask to see released.
@MainActor
final class ThePageBarFollowsItsPageTests: XCTestCase {

    private typealias Bar = ShellPageBarView

    // MARK: - The fake

    /// One zone of the port's states only: what it was shown, how often it was asked
    /// to measure and to apply a verdict, and a view it may swap.
    @MainActor
    private final class FakeZone: ShellBarZone {
        enum Field { case tabs, actions, search }
        let field: Field
        var view: NSView? = NSView()
        var width: CGFloat
        var foldedWidth: CGFloat = 136
        var measuresMoved: (() -> Void)?

        private(set) var showCount = 0
        private(set) var last: ShellBarZoneState?
        private(set) var measureCount = 0
        private(set) var applied: [Bar.Verdicts] = []

        var swapsItsViewOnApply = false
        var movesItsMeasuresOnApply = false

        init(_ field: Field, width: CGFloat) {
            self.field = field
            self.width = width
        }

        func show(_ state: ShellBarZoneState) {
            last = state
            showCount += 1
        }

        func measure(into measures: inout Bar.Measures) {
            measureCount += 1
            switch field {
            case .tabs: measures.tabs = width; measures.tabsFolded = foldedWidth
            case .actions: measures.actions = width
            case .search: measures.hasSearch = width > 0
            }
        }

        func apply(_ verdicts: Bar.Verdicts) {
            applied.append(verdicts)
            if swapsItsViewOnApply { view = NSView() }
            if movesItsMeasuresOnApply { measuresMoved?() }
        }
    }

    private final class Captured {}

    @MainActor
    private struct Parts {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let tabs = FakeZone(.tabs, width: 310)
        let actions = FakeZone(.actions, width: 72)
        let search = FakeZone(.search, width: 283)

        var zones: [FakeZone] { [tabs, actions, search] }

        func makeBar() -> ShellPageBar {
            let bar = ShellPageBar(model: model, channel: channel, tabs: tabs, actions: actions,
                                   search: search, titlebarIsTransparent: true)
            bar.graceInterval = 0.2
            return bar
        }

        /// The content is built here so nothing of it outlives the call but the channel's copy.
        @discardableResult
        func declare(_ token: String, action id: String, capturing object: Captured? = nil) -> Int {
            let generation = channel.nextGeneration()
            channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: id, title: id, symbol: "x.circle") { [object] in _ = object }
            ]), token: token, generation: generation)
            return generation
        }
    }

    // MARK: - Waiting on the main run loop

    private func runMain(for seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01))) }
    }

    /// True when `done` held before `deadline` seconds ran out.
    private func runMain(until deadline: TimeInterval, _ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if done() { return true }
            RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01)))
        }
        return done()
    }

    private func page(_ key: String, live: Bool, dimmed: Bool) -> ShellPageBar.Presentation {
        .page(key: key, isLive: live, isDimmed: dimmed)
    }

    private let eightNotifications: [Notification.Name] = [
        .helmLanguageChanged, .helmPageBarStyleChanged, .helmToolbarSwitcherStyleChanged,
        .helmAlwaysCollapseSearchChanged, .helmModuleEnabled, .helmModuleDisabled,
        .helmSidebarStyleChanged, .helmBarAppearanceChanged,
    ]

    // MARK: - A declared page and a withdrawn one

    func testADeclaredPageReachesEveryZoneAndAWithdrawnOneIsFrozenWithoutItsClosures() {
        let p = Parts()
        let bar = p.makeBar()
        let before = p.zones.map(\.showCount)
        var captured: Captured? = Captured()
        weak var weakCaptured = captured

        let generation = p.declare("general", action: "x", capturing: captured)
        captured = nil

        XCTAssertTrue(zip(p.zones, before).allSatisfy { $0.showCount > $1 }, """
            the bar never heard the channel: `onChange` was not set, so every zone is as built
            """)
        XCTAssertNotNil(weakCaptured, "precondition: the declared closure was not the object's only owner")
        for zone in p.zones {
            XCTAssertEqual(zone.last?.content?.actions.map(\.id), ["x"])
            XCTAssertEqual(zone.last?.isLive, true)
            XCTAssertEqual(zone.last?.isDimmed, false)
        }
        XCTAssertEqual(bar.presentation, page("general", live: true, dimmed: false))

        p.channel.withdraw(token: "general", generation: generation)

        XCTAssertNil(weakCaptured, "the frozen bar kept the page's live closure")
        for zone in p.zones {
            XCTAssertEqual(zone.last?.isLive, false)
            XCTAssertEqual(zone.last?.isDimmed, true)
            XCTAssertEqual(zone.last?.content?.actions.map(\.id), ["x"], "the frozen content lost its shape")
        }
        XCTAssertEqual(bar.presentation, page("general", live: false, dimmed: true))
        runMain(for: bar.graceInterval + 0.15)
        XCTAssertEqual(bar.presentation, page("general", live: false, dimmed: true),
                       "General is no module: there is no grace, and the frozen page stays")
    }

    // MARK: - A page that never declared

    func testAPageThatNeverDeclaredShowsTheNameAtOnce() {
        let p = Parts()
        let bar = p.makeBar()
        p.declare("general", action: "g")
        XCTAssertEqual(bar.presentation, page("general", live: true, dimmed: false), """
            precondition: the bar did not present the page it was built on
            """)
        let before = p.zones.map(\.showCount)

        p.model.selection = .module("test.never")

        XCTAssertTrue(zip(p.zones, before).allSatisfy { $0.showCount > $1 }, """
            the selection never reached the bar: it still presents what it was built with
            """)
        XCTAssertEqual(bar.presentation, .nameOnly)
        for zone in p.zones {
            XCTAssertNil(zone.last?.content, "a zone was told a page's content for a page that declared none")
        }
    }

    // MARK: - The return visit and its grace

    /// Selects `id`, declares under it, leaves for General, withdraws, comes back; returns the bar on
    /// the return visit with its grace running.
    private func returnVisit(_ p: Parts, _ id: String) -> ShellPageBar {
        let bar = p.makeBar()
        p.model.selection = .module(id)
        let generation = p.declare(id, action: "a")
        XCTAssertEqual(bar.presentation, page(id, live: true, dimmed: false), """
            the page was never presented as its own bar: nothing here could fall back
            """)
        p.model.selection = .general
        p.channel.withdraw(token: id, generation: generation)
        p.model.selection = .module(id)
        return bar
    }

    func testAReturnVisitStaysLitThroughTheGraceThenFallsToTheNameAndStaysThere() {
        let p = Parts()
        let bar = returnVisit(p, "test.a")

        XCTAssertEqual(bar.presentation, page("test.a", live: false, dimmed: false))
        let shown = p.tabs.showCount
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        XCTAssertTrue(runMain(until: 1) { p.tabs.showCount > shown }, "the language change never reached the bar")
        XCTAssertEqual(bar.presentation, page("test.a", live: false, dimmed: false),
                       "a language change inside the grace dimmed the return visit")

        XCTAssertTrue(runMain(until: 2) { bar.presentation == .nameOnly },
                      "the page never fell back to the name within 2 s of a 0.2 s grace")
        let afterFall = p.tabs.showCount
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        XCTAssertTrue(runMain(until: 1) { p.tabs.showCount > afterFall })
        XCTAssertEqual(bar.presentation, .nameOnly, "a language change brought the fallen page back")
    }

    func testADeclareInsideTheGraceKeepsThePage() {
        let p = Parts()
        let bar = returnVisit(p, "test.a")
        XCTAssertEqual(bar.presentation, page("test.a", live: false, dimmed: false), """
            the page was never presented as its own bar: nothing here could fall back
            """)

        p.declare("test.a", action: "again")

        XCTAssertEqual(bar.presentation, page("test.a", live: true, dimmed: false))
        XCTAssertEqual(p.tabs.last?.content?.actions.map(\.id), ["again"])
        runMain(for: bar.graceInterval + 0.15)
        XCTAssertEqual(bar.presentation, page("test.a", live: true, dimmed: false),
                       "the grace outlived the declaration and took the page away")
    }

    // MARK: - A module gone under its own page

    func testAModuleGoneUnderItsOwnPageDimsAtOnceAndFallsToTheNameAfterTheGrace() {
        let p = Parts()
        let bar = p.makeBar()
        p.model.selection = .module("test.off")
        let generation = p.declare("test.off", action: "a")
        XCTAssertEqual(bar.presentation, page("test.off", live: true, dimmed: false), """
            the page was never presented as its own bar: nothing here could fall back
            """)

        p.channel.withdraw(token: "test.off", generation: generation)

        XCTAssertEqual(bar.presentation, page("test.off", live: false, dimmed: true))
        let shown = p.tabs.showCount
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        XCTAssertTrue(runMain(until: 1) { p.tabs.showCount > shown })
        XCTAssertEqual(bar.presentation, page("test.off", live: false, dimmed: true),
                       "a second frozen pass inside the grace lit the page again")
        XCTAssertTrue(runMain(until: 2) { bar.presentation == .nameOnly },
                      "the page never fell back to the name within 2 s of a 0.2 s grace")
    }

    // MARK: - A page left behind

    func testAPageLeftBehindHoldsNoneOfItsClosures() {
        let p = Parts()
        let bar = p.makeBar()
        var captured: Captured? = Captured()
        weak var weakCaptured = captured
        p.model.selection = .module("test.pageE")
        let generation = p.declare("test.pageE", action: "x", capturing: captured)
        captured = nil
        XCTAssertNotNil(weakCaptured, "precondition: the declared closure was not the object's only owner")

        p.model.selection = .general
        p.channel.withdraw(token: "test.pageE", generation: generation)

        XCTAssertEqual(bar.presentation, .nameOnly, "precondition: General is not what is shown")
        XCTAssertNil(weakCaptured, """
            the object a live action's closure captured is still alive after its page was left \
            and withdrawn: the bar kept the page's live content for its next visit
            """)
    }

    // MARK: - The selection the signal carries

    func testTheSelectionIsTheOneTheSignalCarries() {
        let p = Parts()
        let bar = p.makeBar()
        p.declare("about", action: "about.x")
        let before = p.zones.map(\.showCount)

        p.model.selection = .about

        XCTAssertTrue(zip(p.zones, before).allSatisfy { $0.showCount > $1 }, "the selection sink never ran")
        XCTAssertEqual(p.tabs.last?.content?.actions.map(\.id), ["about.x"],
                       "the zones were told the page the model held before the signal, not the one it carried")
        XCTAssertEqual(bar.presentation, page("about", live: true, dimmed: false))
    }

    // MARK: - The name and the status by style and content

    private func identity(status: (word: String, active: Bool)?) -> ShellPageBar.Identity {
        ShellPageBar.Identity(symbol: "gearshape", tint: .gray, title: "Page", status: status)
    }

    func testNameAndStatusFollowTheStyleAndThePagesContent() {
        func snapshot(_ style: PageBarStyle, _ content: HelmPageToolbarContent?) -> ShellPageBar.Snapshot {
            ShellPageBar.Snapshot(identity: identity(status: ("Active", true)), style: style, content: content,
                                  iconStyle: .colour, appearsActive: true, titlebarIsTransparent: true)
        }
        let bare = snapshot(.moduleName, nil)
        XCTAssertEqual(bare.statusWord, "Active")
        XCTAssertTrue(bare.statusActive)

        let windowTitle = snapshot(.windowTitle, nil)
        XCTAssertFalse(windowTitle.showsIcon, "the \"without icon\" style draws the icon")
        XCTAssertNil(windowTitle.statusWord, "the \"without icon\" style draws the status badge")
        XCTAssertTrue(bare.showsIcon, "the module-name style draws no icon")
        XCTAssertTrue(snapshot(.moduleName, HelmPageToolbarContent()).showsIcon)
        let titleWithTab = snapshot(.windowTitle, HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "t", title: "T", symbol: "x")], selectedTab: .constant("t")))
        XCTAssertFalse(titleWithTab.showsIcon)

        let withTab = HelmPageToolbarContent(tabs: [HelmToolbarTab(id: "t", title: "T", symbol: "x")],
                                             selectedTab: .constant("t"))
        let withAction = HelmPageToolbarContent(actions: [HelmToolbarAction(id: "a", title: "A", symbol: "x") {}])
        let withSearch = HelmPageToolbarContent(search: HelmToolbarSearch(prompt: "P", text: .constant("")))
        for (what, content) in [("a tab", withTab), ("an action", withAction), ("a search", withSearch)] {
            let shown = snapshot(.moduleName, content)
            XCTAssertNil(shown.statusWord, "the status stayed beside \(what)")
        }
        let empty = snapshot(.moduleName, HelmPageToolbarContent())
        XCTAssertEqual(empty.statusWord, "Active", "a content with nothing in it took the status away")
    }

    /// The view, not the flag: a name zone told to draw no icon is narrower by the plate it did not draw.
    func testTheNameZoneGivenNoIconDrawsNoPlate() {
        func width(showsIcon: Bool) -> CGFloat {
            var zone = NameZoneView(symbol: "gearshape", tint: .blue, title: "Page", iconStyle: .colour,
                                    appearsActive: true, titlebarIsTransparent: true)
            zone.showsIcon = showsIcon
            let host = NSHostingView(rootView: zone)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.width
        }
        let withIcon = width(showsIcon: true)
        let without = width(showsIcon: false)
        XCTAssertGreaterThan(without, 0, "the name drew nothing at all without its icon: it was never measured")
        XCTAssertGreaterThanOrEqual(withIcon - without, 24, """
            the zone told to draw no icon is only \(withIcon - without) narrower than the one that draws it \
            (\(withIcon) against \(without)): the plate is still drawn
            """)
    }

    // MARK: - One Settings page

    func testGeneralLogAndAboutAreOneSettingsPage() {
        let host = ModuleHost.shared
        let nobody = ShellPageBar.identity(for: nil, host: host)
        XCTAssertFalse(nobody.title.isEmpty, "the identity's title is empty")
        for selection in [nil, SettingsSelection.general, .about, .log] {
            let identity = ShellPageBar.identity(for: selection, host: host)
            XCTAssertEqual(identity.title, AppStr.settingsPane)
            XCTAssertEqual(identity.symbol, "gearshape")
            XCTAssertNil(identity.status)
        }
        let unknown = ShellPageBar.identity(for: .module("test.nobody"), host: host)
        XCTAssertEqual(unknown.title, AppStr.settingsPane, "an id nobody holds is not Settings")
        XCTAssertNil(unknown.status)

        let descriptor = ModuleRegistry.all[0]
        let module = ShellPageBar.identity(for: .module(descriptor.idRaw), host: host)
        XCTAssertEqual(module.title, descriptor.moduleMetadata.name)
        XCTAssertEqual(module.symbol, descriptor.moduleMetadata.sfSymbol)

        XCTAssertEqual(ShellPageBar.pageKey(for: nil), "general")
        XCTAssertEqual(ShellPageBar.pageKey(for: .general), "general")
        XCTAssertEqual(ShellPageBar.pageKey(for: .log), "log")
        XCTAssertEqual(ShellPageBar.pageKey(for: .about), "about")
        XCTAssertEqual(ShellPageBar.pageKey(for: .module("test.id")), "test.id")
    }

    // MARK: - The widths of the name and the status

    func testNameAndStatusAreAsWideAsTheyDrawAndAbsentWhenTheyDrawNothing() {
        let p = Parts()
        let bar = p.makeBar()
        let name = bar.view.view(for: .name)
        let nameFitting = name?.fittingSize.width ?? 0
        XCTAssertGreaterThan(nameFitting, 0, """
            the name's host measured 0 wide: either it was never built or a window-less host has no \
            fitting size — it is \(name == nil ? "never built" : "built, so a window-less host has no fitting size")
            """)
        XCTAssertGreaterThanOrEqual(bar.view.measures.name, nameFitting, "the name was given less room than it draws in")
        XCTAssertEqual(bar.view.measures.status, 0, "a page with no status was given a status width")
        XCTAssertNil(bar.view.view(for: .status), "a page with no status has a status view")

        bar.draw(identity(status: ("Active", true)))

        let status = bar.view.view(for: .status)
        let statusFitting = status?.fittingSize.width ?? 0
        XCTAssertGreaterThan(statusFitting, 0, "the status's host measured 0 wide, or was never set")
        XCTAssertGreaterThanOrEqual(bar.view.measures.status, statusFitting)
        XCTAssertEqual(bar.snapshot?.statusWord, "Active")

        let snapshot = bar.snapshot
        let measuresCount = p.zones.map(\.measureCount)
        bar.view.measures.name = 999
        bar.draw(identity(status: ("Active", true)))
        XCTAssertEqual(bar.snapshot, snapshot)
        XCTAssertTrue(bar.view.view(for: .status) === status, "an equal snapshot built the status host again")
        XCTAssertEqual(bar.view.measures.name, 999, "an equal snapshot measured again")
        XCTAssertEqual(p.zones.map(\.measureCount), measuresCount, "an equal snapshot asked the zones to measure again")
    }

    // MARK: - A released bar

    func testAReleasedBarAnswersNothing() {
        let p = Parts()
        var bar: ShellPageBar? = p.makeBar()
        weak var weakBar = bar
        p.declare("general", action: "a")
        XCTAssertTrue(p.zones.allSatisfy { $0.showCount > 0 }, "the bar was never alive: the counts were 0 before it was dropped")

        bar = nil
        XCTAssertNil(weakBar, "the bar is still alive after its owner let go: something holds it strongly")
        let counts = p.zones.map(\.showCount)
        let measured = p.zones.map(\.measureCount)

        for name in eightNotifications { NotificationCenter.default.post(name: name, object: nil) }
        p.declare("general", action: "b")
        p.model.selection = .module("test.gone")
        p.model.selection = .about
        runMain(for: 0.5)

        XCTAssertEqual(p.zones.map(\.showCount), counts, "a released bar still told its zones something")
        XCTAssertEqual(p.zones.map(\.measureCount), measured, "a released bar still measured")
    }

    // MARK: - The window's activity

    func testAnEqualActivityFlagIsRefusedAndAChangedOneReachesTheZonesAndTheName() {
        let p = Parts()
        let bar = p.makeBar()
        XCTAssertTrue(p.zones.allSatisfy { $0.showCount > 0 }, "no zone was ever shown")
        XCTAssertEqual(bar.snapshot?.appearsActive, true)

        let before = p.zones.map(\.showCount)
        bar.setWindowAppearsActive(true)
        XCTAssertEqual(p.zones.map(\.showCount), before, "an equal flag re-showed the zones")

        bar.setWindowAppearsActive(false)
        XCTAssertEqual(p.zones.map(\.showCount), before.map { $0 + 1 })
        for zone in p.zones { XCTAssertEqual(zone.last?.appearsActive, false) }
        XCTAssertEqual(bar.snapshot?.appearsActive, false)

        bar.setWindowAppearsActive(false)
        XCTAssertEqual(p.zones.map(\.showCount), before.map { $0 + 1 }, "an equal flag re-showed the zones")
    }

    // MARK: - A language or a setting

    func testALanguageOrASettingReshowsEveryZoneAndAsksForOnePass() {
        let p = Parts()
        let bar = p.makeBar()
        XCTAssertTrue(p.zones.allSatisfy { $0.showCount > 0 }, "no zone was ever shown")

        for name in eightNotifications {
            let shown = p.zones.map(\.showCount)
            let measured = p.zones.map(\.measureCount)
            NotificationCenter.default.post(name: name, object: nil)
            XCTAssertTrue(runMain(until: 2) { p.tabs.showCount > shown[0] }, "\(name.rawValue) never reached the bar")
            runMain(for: 0.05)
            XCTAssertEqual(p.zones.map(\.showCount), shown.map { $0 + 1 }, "\(name.rawValue): not one re-show per zone")
            XCTAssertEqual(p.zones.map(\.measureCount), measured.map { $0 + 1 }, "\(name.rawValue): not one pass")
        }
        withExtendedLifetime(bar) {}
    }

    // MARK: - Verdicts

    func testAVerdictReachesTheZonesBeforeTheFramesAndAZoneMayNotAnswerWithNewMeasures() {
        let p = Parts()
        p.tabs.swapsItsViewOnApply = true
        p.actions.movesItsMeasuresOnApply = true
        let bar = p.makeBar()
        let oldTabsView = p.tabs.view
        let measuresBefore = bar.view.measures
        let measured = p.zones.map(\.measureCount)

        bar.view.frame = NSRect(x: 0, y: 0, width: 480, height: 52)
        bar.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(p.tabs.applied.isEmpty, """
            no verdict was ever published: the bar was wide enough for everything — the row's width is wrong
            """)
        XCTAssertEqual(p.tabs.applied.count, 1)
        XCTAssertEqual(p.tabs.applied.first?.tabsFolded, true)
        XCTAssertEqual(p.search.applied.count, 1, "a zone was not told the verdict")

        let tabsFrame = bar.view.frames?.tabs ?? CGRect.zero
        XCTAssertNotEqual(tabsFrame, CGRect.zero, "the tabs were given no frame")
        XCTAssertTrue(p.tabs.view !== oldTabsView, "precondition: the fake did not swap its view")
        XCTAssertTrue(bar.view.view(for: .tabs) === p.tabs.view, "the bar kept the view the zone swapped out")
        XCTAssertEqual(p.tabs.view?.frame, tabsFrame, "the swapped-in view was not placed in the same pass")
        XCTAssertNil(oldTabsView?.superview, "the swapped-out view is still in the bar")

        XCTAssertEqual(p.zones.map(\.measureCount), measured,
                       "a zone's answer inside the pass collected the measures again")
        XCTAssertEqual(bar.view.measures, measuresBefore, "the measures moved inside the pass")
        XCTAssertFalse(bar.view.needsLayout, "the pass left a layout pending")

        p.actions.width = 90
        p.actions.measuresMoved?()
        XCTAssertEqual(bar.view.measures.actions, 90, "a zone's width that moved outside a pass was not collected")
    }

    // MARK: - The status is read after the signal

    /// A module's `objectWillChange` fires before the value changes, so the bar must not read the status
    /// inside the signal's own call. This row switches no module on, so it observes the deferral itself: the
    /// page's identity has no status, the bar is shown one by hand, and a signal must not undo that until the
    /// main queue has turned.
    func testTheStatusIsReadAfterTheSignalHasReturnedNotInsideIt() {
        let p = Parts()
        let bar = p.makeBar()
        let signal = PassthroughSubject<Void, Never>()
        bar.watchStatus(of: signal)
        bar.draw(identity(status: ("Active", true)))
        XCTAssertEqual(bar.snapshot?.statusWord, "Active", "precondition: the status was not drawn by hand")

        signal.send()

        XCTAssertEqual(bar.snapshot?.statusWord, "Active", """
            the bar redrew inside the signal's call, where a module's own value is still the old one
            """)
        XCTAssertTrue(runMain(until: 2) { bar.snapshot?.statusWord == nil }, """
            the signal never reached the bar: the status drawn by hand is still there after 2 s
            """)
    }

    // MARK: - The status's inset

    func testTheBoxMarginMovesTheStatusInsetByItselfAndNeitherInsetIsTheFallback() {
        for status in [(word: "Active", active: true), (word: "Idle", active: false)] {
            let flush = StatusZoneView.trailingInset(for: status, barHeight: 52, boxMargin: 0)
            let inset = StatusZoneView.trailingInset(for: status, barHeight: 52, boxMargin: 4)
            let fallback = HelmToolbarActionsCapsule.edgeMargin

            XCTAssertFalse(flush == fallback && inset == fallback, """
                the render drew nothing: both insets are the fallback, and their difference is 0
                """)
            XCTAssertEqual(flush - inset, 4, "\(status.word): the box margin did not move the inset by itself")
            XCTAssertTrue((0...52).contains(flush) && (0...52).contains(inset), "\(status.word): inset outside the bar")
            XCTAssertNotEqual(flush, fallback, "\(status.word): the flush inset is the capsule's fallback")
            XCTAssertNotEqual(inset, fallback, "\(status.word): the inset is the capsule's fallback")
        }
    }
}
