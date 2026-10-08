import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' Table / Plain-text switcher draws only glyphs, and each glyph
/// still says what it is** — aloud and as a tooltip, in every language —
/// read off the real page through the page bar's actions zone
/// (`LivePageToolbarFixture`).
///
/// The owner asked for these tabs to be glyphs whatever the tabs' label
/// style is (2026-09-25). Once the word is gone from the face, the name that
/// `HostsSettingsPage.toolbarContent` gives each option (`HostsStr.tableView`,
/// `HostsStr.textView`) survives in two places only: the segment's
/// accessibility element (AppKit reads it from the glyph's accessibility
/// description) and its tooltip. The actions zone has no overflow form: the
/// bar folds its tabs and its search when room runs short and never the
/// capsule, and the bar's menu (`ShellBarMenu.fill`) carries no page actions,
/// so there is no third place for a name to live in.
/// `AGlyphSwitcherFollowsALanguageChangeTests` also reads the two, but
/// against a language change rather than a value at rest; this file is what
/// proves them at rest, on the real page. A `.segmented` entry mounted on its
/// own (`ASegmentedActionIsAlwaysGlyphsTests`) proves the face and not the name.
///
/// Two more inputs the change never fed in: a label-style change while the
/// page is up (the switcher must stay glyphs on the same control, and the
/// centre tabs — the subject the change is proved to have reached — must
/// follow it), and a bar that is not interactive (frozen) or an entry the
/// page declares disabled. And a language change, both with the page up and
/// made on another page while the bar has left Hosts and keeps its copy of
/// the page: the group's own name (`HostsStr.viewGroup`) and each option's
/// have to follow it, and were only ever read at rest (tester, 2026-09-26).
@MainActor
final class TheViewModeSwitcherKeepsItsNamesTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private var fixtures: [LivePageToolbarFixture] = []
    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var savedLabelStyle: Any?

    /// The bar reads these when it is built (its tabs zone reads the label style when it shows), so they are
    /// pinned before a fixture is and put back after.
    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        savedLabelStyle = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.barAppearance = .flat
        AppSettings.alwaysCollapseSearch = false
        AppSettings.toolbarSwitcherStyle = .text
    }

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        AppSettings.store.set(savedLabelStyle, for: ToolbarSwitcherStyle.storageKey)
        super.tearDown()
    }

    /// The real page, on its SSH tab — the one tab the switcher shows on.
    private func mountHostsOnSSH() -> LivePageToolbarFixture? {
        let hosts = LivePageToolbarFixture(HostsSettingsPage(vm: ModuleViewModel(transport: Mute())),
                                           selection: .module(HostsDescriptor.id.rawValue),
                                           width: 1060, height: 700)
        fixtures.append(hosts)
        hosts.settle(30)
        guard let selectedTab = hosts.channel.content(for: HostsDescriptor.id.rawValue)?.selectedTab else {
            XCTFail("Hosts declared no tabs onto the channel")
            return nil
        }
        selectedTab.wrappedValue = "ssh"
        hosts.settle(30)
        return hosts
    }

    /// A zone's view, found by a walk of the bar the window holds and held to be the fixture's own zone, so
    /// a zone that drew into no window cannot be read by accident.
    private func zoneView(_ zone: ShellPageBarView.Zone, of fx: LivePageToolbarFixture) -> NSView? {
        let found = fx.mount.window?.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        guard let view = found?.view(for: zone) else { return nil }
        let own: NSView? = zone == .actions ? fx.pageBar.actions.view : fx.pageBar.tabs.view
        return view === own ? view : nil
    }

    /// The view-mode switcher, in the actions zone.
    private func switcher(_ fx: LivePageToolbarFixture) -> NSSegmentedControl? {
        zoneView(.actions, of: fx)?.everyView(ofType: NSSegmentedControl.self).first
    }

    /// The centre tabs, in the tabs zone.
    private func centreTabs(_ fx: LivePageToolbarFixture) -> NSSegmentedControl? {
        zoneView(.tabs, of: fx)?.everyView(ofType: NSSegmentedControl.self).first
    }

    /// What VoiceOver reads for each segment — the segmented cell's own
    /// accessibility children, one radio button per segment.
    private func spokenNames(_ control: NSSegmentedControl) -> [String?] {
        (control.cell?.accessibilityChildren() ?? []).map { ($0 as? NSAccessibilityProtocol)?.accessibilityLabel() }
    }

    // MARK: - Names

    func testEachGlyphIsNamedAloudAndAsATooltipInEveryLanguage() {
        AppLanguage.each { language in
            guard let hosts = mountHostsOnSSH() else { return }
            // Read out of the table, not through `HostsStr` — see
            // `expectedNames(_:)` for why the page's own accessor cannot be
            // the expectation.
            let expected = expectedNames(language).tooltips.compactMap { $0 }
            guard let control = switcher(hosts) else {
                return XCTFail("\(language.rawValue): no view-mode switcher in the actions zone on the SSH tab")
            }
            XCTAssertEqual(control.segmentCount, 2, "\(language.rawValue): the switcher has the wrong segments")
            for index in 0..<min(control.segmentCount, expected.count) {
                XCTAssertEqual(control.label(forSegment: index), "", """
                    \(language.rawValue): segment \(index) draws a word — the view-mode tabs are glyphs only
                    """)
                XCTAssertNotNil(control.image(forSegment: index),
                                "\(language.rawValue): segment \(index) has no glyph")
                XCTAssertEqual(control.toolTip(forSegment: index), expected[index], """
                    \(language.rawValue): segment \(index)'s tooltip is not the name the page gives it
                    """)
            }
            XCTAssertEqual(spokenNames(control), expected.map(Optional.some), """
                \(language.rawValue): VoiceOver does not read each glyph by the name the page gives it
                """)
            XCTAssertEqual(control.selectedSegment, 0, """
                \(language.rawValue): the switcher does not show the option the page selects on show (Table)
                """)
            hosts.drop()
            fixtures.removeAll { $0.mount === hosts.mount }
        }
    }

    /// **The switcher is read aloud as a group under a name of its own.** It
    /// was declared under `HelmA11y.whatToShow` — the centre tabs' own name on
    /// the same bar — so VoiceOver named two switchers alike. Read off the real
    /// page on its SSH tab, per language: the control's own label is the
    /// table's word for `HostsStr.viewGroup`, and the centre tabs' label (the
    /// subject: read first, and required to be what they declare) is a
    /// different string.
    func testTheSwitcherIsNamedApartFromTheCentreTabsInEveryLanguage() {
        AppLanguage.each { language in
            guard let hosts = mountHostsOnSSH() else { return }
            guard let tabs = centreTabs(hosts)
            else { return XCTFail("\(language.rawValue): no centre tabs on the SSH tab") }
            XCTAssertEqual(tabs.accessibilityLabel(), HelmA11y.whatToShow, """
                \(language.rawValue): the centre tabs are not named what they declare — nothing below compares \
                against the right control
                """)
            guard let control = switcher(hosts) else {
                return XCTFail("\(language.rawValue): no view-mode switcher in the actions zone on the SSH tab")
            }
            XCTAssertEqual(control.accessibilityLabel(), expectedNames(language).group, """
                \(language.rawValue): the view-mode switcher is not named as its own group
                """)
            XCTAssertNotEqual(control.accessibilityLabel(), tabs.accessibilityLabel(), """
                \(language.rawValue): the view-mode switcher and the centre tabs are read aloud under one name
                """)
            hosts.drop()
            fixtures.removeAll { $0.mount === hosts.mount }
        }
    }

    // MARK: - A language change

    /// Which of the two views is mounted — the page, or nothing in its place,
    /// the way the detail pane swaps a page out for the next one.
    private final class Route: ObservableObject {
        @Published var showsHosts = true
    }

    /// **The page mounted the way the settings window mounts it**: rebuilt,
    /// not redrawn, on `.helmLanguageChanged` — `SettingsWindow`'s
    /// `RebuiltOnLanguageChange` re-identifies the detail pane on
    /// `SettingsModel.languageRevision`, and this does the same with a
    /// `SettingsModel` of its own. A rebuilt page starts on Keys, its first
    /// tab, as it does in the window.
    private struct MountedAsTheWindowMountsIt: View {
        @ObservedObject var model: SettingsModel
        @ObservedObject var route: Route
        let vm: ModuleViewModel
        var body: some View {
            Group {
                if route.showsHosts { HostsSettingsPage(vm: vm) } else { Color.clear }
            }
            .id(model.languageRevision)
        }
    }

    /// Everything that names the view-mode switcher, read off the bar: the group's name, and each option's
    /// tooltip and spoken name.
    private struct Names: Equatable {
        let group: String?
        let tooltips: [String?]
        let spoken: [String?]
    }

    private func names(_ fx: LivePageToolbarFixture) -> Names {
        guard let control = switcher(fx) else { return Names(group: nil, tooltips: [], spoken: []) }
        return Names(group: control.accessibilityLabel(),
                     tooltips: (0..<control.segmentCount).map { control.toolTip(forSegment: $0) },
                     spoken: spokenNames(control))
    }

    /// What the page must name things in `language` — read out of the table
    /// for that language rather than through `HostsStr`, which is what the
    /// page itself reads: an expectation read through the same accessor
    /// agrees with a name frozen at its first reading.
    private func expectedNames(_ language: AppLanguage) -> Names {
        let options = [L("Table", language: language), L("Plain text", language: language)]
        return Names(group: L("View", language: language), tooltips: options, spoken: options)
    }

    /// Puts the page on its SSH tab through its own declared binding and
    /// waits for the bar to follow.
    private func selectSSH(_ hosts: LivePageToolbarFixture, _ label: String) -> Bool {
        guard let selected = hosts.channel.content(for: HostsDescriptor.id.rawValue)?.selectedTab else {
            XCTFail("\(label): Hosts declared no tabs onto the channel")
            return false
        }
        selected.wrappedValue = "ssh"
        hosts.settle(30)
        guard hosts.channel.content(for: HostsDescriptor.id.rawValue)?.selectedTab?.wrappedValue == "ssh" else {
            XCTFail("\(label): Hosts did not move to its SSH tab")
            return false
        }
        return true
    }

    /// **The group's name and each option's name follow a language change
    /// made while the page is up.** In every language, one after another on
    /// the same bar: the page is rebuilt in the new language, put back on SSH,
    /// and the switcher's accessibility label and each option's tooltip and
    /// spoken name are read against that language's table. The subject first —
    /// the page did redeclare in the new language (its tabs' own words) — so a
    /// stale name is not a page that never heard about the change.
    func testTheGroupNameFollowsALanguageChangeWithThePageUp() {
        AppLanguage.only(.pt) {
            let model = SettingsModel(host: ModuleHost.shared)
            let route = Route()
            let hosts = LivePageToolbarFixture(
                MountedAsTheWindowMountsIt(model: model, route: route, vm: ModuleViewModel(transport: Mute())),
                selection: .module(HostsDescriptor.id.rawValue), width: 1060, height: 700)
            fixtures.append(hosts)
            hosts.settle(30)
            guard selectSSH(hosts, "pt") else { return }
            XCTAssertEqual(names(hosts), expectedNames(.pt), "precondition: pt, before any change")

            AppLanguage.each { language in
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                hosts.settle(30)
                let declared = hosts.channel.content(for: HostsDescriptor.id.rawValue)?.tabs.map(\.title)
                XCTAssertEqual(declared, [L("Keys", language: language), L("SSH hosts", language: language)], """
                    precondition \(language.rawValue): the page did not redeclare in the new language — nothing \
                    below is about the switcher's names
                    """)
                XCTAssertEqual(hosts.channel.content(for: HostsDescriptor.id.rawValue)?.selectedTab?.wrappedValue,
                               "keys", """
                    precondition \(language.rawValue): the page is not back on Keys — it was redrawn rather than \
                    rebuilt, which is not what the window does on a language change
                    """)
                guard selectSSH(hosts, language.rawValue) else { return }
                XCTAssertEqual(names(hosts), expectedNames(language), """
                    \(language.rawValue): the view-mode switcher's group name or an option's name stayed in \
                    another language
                    """)
            }
        }
    }

    /// The page the bar shows, when it shows one, and whether that page is live.
    private func shownPage(_ fx: LivePageToolbarFixture) -> (key: String, isLive: Bool)? {
        if case .page(let key, let isLive, _) = fx.bar.presentation { return (key, isLive) }
        return nil
    }

    /// **The same, by the route a language change actually takes in the
    /// app**: the language is chosen on another page, and the bar — which
    /// keeps a closure-free copy of Hosts' page from the visit before, its
    /// shape unchanged — is handed the page's declaration in the new
    /// language on the way back.
    func testTheGroupNameFollowsALanguageChangeMadeOnAnotherPage() {
        AppLanguage.only(.pt) {
            let model = SettingsModel(host: ModuleHost.shared)
            let route = Route()
            let hosts = LivePageToolbarFixture(
                MountedAsTheWindowMountsIt(model: model, route: route, vm: ModuleViewModel(transport: Mute())),
                selection: .module(HostsDescriptor.id.rawValue), width: 1060, height: 700)
            fixtures.append(hosts)
            hosts.settle(30)
            guard selectSSH(hosts, "pt") else { return }
            let hostsKey = HostsDescriptor.id.rawValue
            XCTAssertEqual(names(hosts), expectedNames(.pt), "precondition: pt, before any change")

            AppLanguage.each { language in
                // Away to General, where the language is chosen.
                hosts.model.selection = .general
                route.showsHosts = false
                hosts.settle(30)
                XCTAssertNotEqual(shownPage(hosts)?.key, hostsKey,
                                  "precondition \(language.rawValue): the bar still shows Hosts' page")
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                hosts.settle(30)
                // And back. Read before the page has declared again: the bar holds its copy of Hosts' page.
                hosts.model.selection = .module(hostsKey)
                hosts.pageBar.layout()
                let copy = shownPage(hosts)
                XCTAssertEqual(copy?.key, hostsKey, """
                    precondition \(language.rawValue): the bar did not come back to Hosts' page
                    """)
                XCTAssertEqual(copy?.isLive, false, """
                    precondition \(language.rawValue): the bar shows Hosts' page live before the page has \
                    declared — this reads a fresh declaration, not the copy the change has to reach
                    """)
                route.showsHosts = true
                hosts.settle(30)
                guard selectSSH(hosts, language.rawValue) else { return }
                XCTAssertEqual(names(hosts), expectedNames(language), """
                    \(language.rawValue): after a language change on another page, the bar's copy of Hosts' page \
                    still names the view-mode switcher or one of its options in another language
                    """)
            }
        }
    }

    // MARK: - A label-style change while the page is up

    /// The identity assertions catch a switcher or a hosted view built again
    /// for a label style: `ShellBarActions.show` builds a host again by its
    /// `rebuilds` verdict, which reads the look, the declared ids and the
    /// window's activity and not the label style. History, from the earlier
    /// toolbar, `SettingsToolbar`, and not asked of this bar: a
    /// `ShapeSignature` that carried the style went red here, and its
    /// `patchActions` handing the hosted view a fresh
    /// `HelmToolbarActionsCapsule` as its root on every patch stayed green.
    func testALabelStyleChangeLeavesTheSwitcherGlyphsOnTheSameControlAndTheCentreTabsFollowIt() throws {
        let hosts = try XCTUnwrap(mountHostsOnSSH())
        let control = try XCTUnwrap(switcher(hosts), "no view-mode switcher on the SSH tab")
        let hosting = try XCTUnwrap(zoneView(.actions, of: hosts))
        let width = hosting.frame.width

        for style in ToolbarSwitcherStyle.allCases {
            AppSettings.toolbarSwitcherStyle = style
            hosts.settle(30)

            // The subject: the change reached the bar at all.
            let tabs = try XCTUnwrap(centreTabs(hosts), "\(style): no centre tabs")
            let tabsWords = (0..<tabs.segmentCount).map { tabs.label(forSegment: $0) ?? "" }
            XCTAssertEqual(tabsWords.allSatisfy { !$0.isEmpty }, style != .icons, """
                \(style): the centre tabs read \(tabsWords) — they no longer follow the label style, so \
                nothing below says anything about the view-mode switcher
                """)

            let now = try XCTUnwrap(switcher(hosts), "\(style): the view-mode switcher is gone")
            XCTAssertIdentical(now, control, "\(style): the view-mode switcher was rebuilt for a label style")
            XCTAssertIdentical(zoneView(.actions, of: hosts), hosting,
                               "\(style): the actions zone's hosted view was replaced for a label style")
            for index in 0..<now.segmentCount {
                XCTAssertEqual(now.label(forSegment: index), "", """
                    \(style): view-mode segment \(index) draws a word — it follows the tabs' label style
                    """)
                XCTAssertNotNil(now.image(forSegment: index), "\(style): view-mode segment \(index) lost its glyph")
            }
            XCTAssertEqual(hosting.frame.width, width, accuracy: 0.5, """
                \(style): the actions zone changed width for a label style it does not draw in
                """)
        }
    }

    // MARK: - Not interactive

    /// The page's own declaration of the switcher (`HostsSettingsPage
    /// .toolbarContent`), group name included — it was the centre tabs'
    /// `HelmA11y.whatToShow` here after the page had stopped using it.
    private func viewMode(isEnabled: Bool) -> HelmPageToolbarContent {
        HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "viewMode", title: HostsStr.viewGroup, isEnabled: isEnabled, isVisible: true,
                              options: [
                                  HelmToolbarTab(id: "table", title: HostsStr.tableView, symbol: "tablecells"),
                                  HelmToolbarTab(id: "text", title: HostsStr.textView, symbol: "text.alignleft"),
                              ], selection: .constant("table"))
        ])
    }

    /// A page that declares only the view-mode switcher, on a bar of its own.
    private func bare(_ token: String) -> LivePageToolbarFixture {
        let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: 1060, height: 700)
        fixtures.append(fx)
        return fx
    }

    func testTheSwitcherIsDimmedOnAFrozenBarAndWhenThePageDisablesIt() throws {
        let live = bare("test.viewModeFrozen")
        let generation = live.channel.nextGeneration()
        live.channel.declare(viewMode(isEnabled: true), token: "test.viewModeFrozen", generation: generation)
        live.settle(3)
        XCTAssertEqual(live.bar.presentation, .page(key: "test.viewModeFrozen", isLive: true, isDimmed: false),
                       "precondition: the bar does not show the live page")
        let control = try XCTUnwrap(switcher(live), "no view-mode switcher on the bar")
        XCTAssertTrue(control.isEnabled, "precondition: the switcher is dimmed on a live bar that enables it")

        live.channel.withdraw(token: "test.viewModeFrozen", generation: generation)
        live.settle(3)
        XCTAssertEqual(live.bar.presentation, .page(key: "test.viewModeFrozen", isLive: false, isDimmed: true),
                       "precondition: the bar does not show the frozen copy of the page")
        let frozen = try XCTUnwrap(switcher(live), "the view-mode switcher is gone from the frozen bar")
        XCTAssertFalse(frozen.isEnabled, "the view-mode switcher still takes presses on a frozen bar")

        let dimmed = bare("test.viewModeDisabled")
        dimmed.channel.declare(viewMode(isEnabled: false), token: "test.viewModeDisabled",
                               generation: dimmed.channel.nextGeneration())
        dimmed.settle(3)
        XCTAssertEqual(dimmed.bar.presentation, .page(key: "test.viewModeDisabled", isLive: true, isDimmed: false),
                       "precondition: the second bar does not show a live page, so the freeze would be what dims")
        let disabled = try XCTUnwrap(switcher(dimmed), "no view-mode switcher on the second bar")
        XCTAssertFalse(disabled.isEnabled, "the page disabled the view-mode switcher and it still takes presses")
    }
}
