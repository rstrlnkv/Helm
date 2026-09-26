import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI

/// **Hosts' Table / Plain-text switcher draws only glyphs, and each glyph
/// still says what it is** — aloud, as a tooltip and in the overflow menu,
/// in every language — read off the real page through a real
/// `SettingsToolbar`.
///
/// The owner asked for these tabs to be glyphs whatever the tabs' label
/// style is (2026-09-25). Once the word is gone from the face, the name that
/// `HostsSettingsPage.toolbarContent` gives each option (`HostsStr.tableView`,
/// `HostsStr.textView`) survives in three places only: the segment's
/// accessibility element (AppKit reads it from the glyph's accessibility
/// description), its tooltip, and the capsule's overflow menu form.
/// `AGlyphSwitcherFollowsALanguageChangeTests` also reads the first two, but
/// against a language change rather than a value at rest, and never the
/// overflow form; this file is what proves all three at rest, on the real
/// page. A `.segmented` entry mounted on its own
/// (`ASegmentedActionIsAlwaysGlyphsTests`) proves the face and not the name.
///
/// Two more inputs the change never fed in: a label-style change while the
/// page is up (the switcher must stay glyphs on the same control, and the
/// centre tabs — the subject the change is proved to have reached — must
/// follow it), and a bar that is not interactive (frozen) or an entry the
/// page declares disabled. And a language change, both with the page up and
/// made on another page while Hosts' bar waits in the toolbar's cache: the
/// group's own name (`HostsStr.viewGroup`) and the overflow form's title
/// have to follow it, and were only ever read at rest (tester, 2026-09-26).
@MainActor
final class TheViewModeSwitcherKeepsItsNamesTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    private var fixtures: [LivePageToolbarFixture] = []

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
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

    private func item(_ id: String, in window: NSWindow?) -> NSToolbarItem? {
        window?.toolbar?.items.first { $0.itemIdentifier.rawValue == id }
    }

    private func switcher(in window: NSWindow?) -> NSSegmentedControl? {
        item("helm.actions", in: window)?.view?.everyView(ofType: NSSegmentedControl.self).first
    }

    /// What VoiceOver reads for each segment — the segmented cell's own
    /// accessibility children, one radio button per segment.
    private func spokenNames(_ control: NSSegmentedControl) -> [String?] {
        (control.cell?.accessibilityChildren() ?? []).map { ($0 as? NSAccessibilityProtocol)?.accessibilityLabel() }
    }

    // MARK: - Names

    func testEachGlyphIsNamedAloudAsATooltipAndInTheOverflowMenuInEveryLanguage() {
        AppLanguage.each { language in
            guard let hosts = mountHostsOnSSH() else { return }
            let window = hosts.mount.window
            // Read out of the table, not through `HostsStr` — see
            // `expectedNames(_:)` for why the page's own accessor cannot be
            // the expectation.
            let expected = expectedNames(language).options ?? []
            guard let control = switcher(in: window) else {
                return XCTFail("\(language.rawValue): no view-mode switcher in helm.actions on the SSH tab")
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

            // The overflow form: one visible action, so the item's own menu
            // form is that action's submenu.
            let form = item("helm.actions", in: window)?.menuFormRepresentation
            XCTAssertEqual(form?.submenu?.items.map(\.title), expected, """
                \(language.rawValue): the overflow menu does not carry each option's name
                """)
            XCTAssertEqual(form?.submenu?.items.map(\.state), [.on, .off], """
                \(language.rawValue): the overflow menu does not tick the option on show (Table)
                """)
            hosts.drop()
            fixtures.removeAll { $0.mount === hosts.mount }
        }
    }

    /// **The switcher is read aloud as a group under a name of its own.** It
    /// was declared under `HelmA11y.whatToShow` — the centre tabs' own name on
    /// the same bar — so VoiceOver named two switchers alike. Read off the real
    /// page on its SSH tab, per language: the control's own label is
    /// `HostsStr.viewGroup`, the overflow form's submenu carries the same
    /// word, and the centre tabs' label (the subject: read first, and required
    /// to be what they declare) is a different string.
    func testTheSwitcherIsNamedApartFromTheCentreTabsInEveryLanguage() {
        AppLanguage.each { language in
            guard let hosts = mountHostsOnSSH() else { return }
            let window = hosts.mount.window
            guard let tabs = item("helm.tabs", in: window)?.view?.everyView(ofType: NSSegmentedControl.self).first
            else { return XCTFail("\(language.rawValue): no centre tabs on the SSH tab") }
            XCTAssertEqual(tabs.accessibilityLabel(), HelmA11y.whatToShow, """
                \(language.rawValue): the centre tabs are not named what they declare — nothing below compares \
                against the right control
                """)
            guard let control = switcher(in: window) else {
                return XCTFail("\(language.rawValue): no view-mode switcher in helm.actions on the SSH tab")
            }
            XCTAssertEqual(control.accessibilityLabel(), expectedNames(language).group, """
                \(language.rawValue): the view-mode switcher is not named as its own group
                """)
            XCTAssertNotEqual(control.accessibilityLabel(), tabs.accessibilityLabel(), """
                \(language.rawValue): the view-mode switcher and the centre tabs are read aloud under one name
                """)
            XCTAssertEqual(item("helm.actions", in: window)?.menuFormRepresentation?.title,
                           expectedNames(language).menuTitle, """
                \(language.rawValue): the overflow menu names the view modes under another word
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

    /// Everything that names the view-mode switcher, read off the bar.
    private struct Names: Equatable {
        let group: String?
        let menuTitle: String?
        let submenuTitle: String?
        let options: [String]?
    }

    private func names(in window: NSWindow?) -> Names {
        let form = item("helm.actions", in: window)?.menuFormRepresentation
        return Names(group: switcher(in: window)?.accessibilityLabel(), menuTitle: form?.title,
                     submenuTitle: form?.submenu?.title, options: form?.submenu?.items.map(\.title))
    }

    /// What the page must name things in `language` — read out of the table
    /// for that language rather than through `HostsStr`, which is what the
    /// page itself reads: an expectation read through the same accessor
    /// agrees with a name frozen at its first reading.
    private func expectedNames(_ language: AppLanguage) -> Names {
        let group = L("View", language: language)
        return Names(group: group, menuTitle: group, submenuTitle: group,
                     options: [L("Table", language: language), L("Plain text", language: language)])
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

    /// **The group's name and the overflow menu's title follow a language
    /// change made while the page is up.** In every language, one after
    /// another on the same bar: the page is rebuilt in the new language, put
    /// back on SSH, and the switcher's accessibility label, the overflow
    /// form's title and submenu title, and each option in it are read against
    /// that language's table. The subject first — the page did redeclare in
    /// the new language (its tabs' own words) — so a stale name is not a page
    /// that never heard about the change.
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
            XCTAssertEqual(names(in: hosts.mount.window), expectedNames(.pt), "precondition: pt, before any change")

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
                XCTAssertEqual(names(in: hosts.mount.window), expectedNames(language), """
                    \(language.rawValue): the view-mode switcher's group name or its overflow menu stayed in \
                    another language
                    """)
            }
        }
    }

    /// **The same, by the route a language change actually takes in the
    /// app**: the language is chosen on another page, and Hosts' bar — kept
    /// in the toolbar's cache from the visit before, its shape unchanged —
    /// is handed the page's declaration in the new language on the way back.
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
            let hostsBar = hosts.mount.window?.toolbar
            XCTAssertEqual(names(in: hosts.mount.window), expectedNames(.pt), "precondition: pt, before any change")

            AppLanguage.each { language in
                // Away to General, where the language is chosen.
                hosts.model.selection = .general
                route.showsHosts = false
                hosts.settle(30)
                XCTAssertNotIdentical(hosts.mount.window?.toolbar, hostsBar,
                                      "precondition \(language.rawValue): Hosts' bar is still on the window")
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                hosts.settle(30)
                // And back.
                hosts.model.selection = .module(HostsDescriptor.id.rawValue)
                route.showsHosts = true
                hosts.settle(30)
                XCTAssertIdentical(hosts.mount.window?.toolbar, hostsBar, """
                    precondition \(language.rawValue): Hosts came back on a rebuilt bar — this reads a fresh bar, \
                    not the cached one the change has to reach
                    """)
                guard selectSSH(hosts, language.rawValue) else { return }
                XCTAssertEqual(names(in: hosts.mount.window), expectedNames(language), """
                    \(language.rawValue): after a language change on another page, Hosts' cached bar still names \
                    the view-mode switcher or its overflow menu in another language
                    """)
            }
        }
    }

    // MARK: - A label-style change while the page is up

    /// The identity assertions catch a bar, item or hosted view rebuilt for a
    /// label style (a `ShapeSignature` that carried the style went red here).
    /// They do not catch `patchActions` handing the hosted view a fresh
    /// `HelmToolbarActionsCapsule` as its root — the rebuild the change
    /// removed — and nothing behavioural can: measured with that assignment
    /// put back on every patch, the switcher stayed the same
    /// `NSSegmentedControl`, the hosted view the same object and the width
    /// the same, so this test stayed green.
    func testALabelStyleChangeLeavesTheSwitcherGlyphsOnTheSameControlAndTheCentreTabsFollowIt() throws {
        let store = AppSettings.store
        let saved = store.object(ToolbarSwitcherStyle.storageKey)
        addTeardownBlock { @MainActor in
            store.set(saved, for: ToolbarSwitcherStyle.storageKey)
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
        }
        let hosts = try XCTUnwrap(mountHostsOnSSH())
        let window = hosts.mount.window
        let control = try XCTUnwrap(switcher(in: window), "no view-mode switcher on the SSH tab")
        let hosting = try XCTUnwrap(item("helm.actions", in: window)?.view)
        let width = hosting.frame.width

        for style in ToolbarSwitcherStyle.allCases {
            AppSettings.toolbarSwitcherStyle = style
            hosts.settle(30)

            // The subject: the change reached the bar at all.
            let tabs = try XCTUnwrap(item("helm.tabs", in: window)?.view?
                .everyView(ofType: NSSegmentedControl.self).first, "\(style): no centre tabs")
            let tabsWords = (0..<tabs.segmentCount).map { tabs.label(forSegment: $0) ?? "" }
            XCTAssertEqual(tabsWords.allSatisfy { !$0.isEmpty }, style != .icons, """
                \(style): the centre tabs read \(tabsWords) — they no longer follow the label style, so \
                nothing below says anything about the view-mode switcher
                """)

            let now = try XCTUnwrap(switcher(in: window), "\(style): the view-mode switcher is gone")
            XCTAssertIdentical(now, control, "\(style): the view-mode switcher was rebuilt for a label style")
            XCTAssertIdentical(item("helm.actions", in: window)?.view, hosting,
                               "\(style): helm.actions' hosted view was replaced for a label style")
            for index in 0..<now.segmentCount {
                XCTAssertEqual(now.label(forSegment: index), "", """
                    \(style): view-mode segment \(index) draws a word — it follows the tabs' label style
                    """)
                XCTAssertNotNil(now.image(forSegment: index), "\(style): view-mode segment \(index) lost its glyph")
            }
            XCTAssertEqual(hosting.frame.width, width, accuracy: 0.5, """
                \(style): helm.actions changed width for a label style it does not draw in
                """)
        }
    }

    // MARK: - Not interactive

    private struct Bare {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func bareToolbar() -> Bare {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Bare(toolbar: toolbar, model: model, channel: channel, window: window)
    }

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

    private func settle(_ window: NSWindow) {
        for _ in 0..<10 {
            window.layoutIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    func testTheSwitcherIsDimmedOnAFrozenBarAndWhenThePageDisablesIt() throws {
        let live = bareToolbar()
        live.model.selection = .module("test.viewModeFrozen")
        let generation = live.channel.nextGeneration()
        live.channel.declare(viewMode(isEnabled: true), token: "test.viewModeFrozen", generation: generation)
        settle(live.window)
        let control = try XCTUnwrap(switcher(in: live.window), "no view-mode switcher on the bar")
        XCTAssertTrue(control.isEnabled, "precondition: the switcher is dimmed on a live bar that enables it")

        live.channel.withdraw(token: "test.viewModeFrozen", generation: generation)
        settle(live.window)
        XCTAssertFalse(control.isEnabled, "the view-mode switcher still takes presses on a frozen bar")
        let frozenForm = item("helm.actions", in: live.window)?.menuFormRepresentation
        XCTAssertEqual(frozenForm?.submenu?.items.map(\.isEnabled), [false, false],
                       "the overflow menu still offers the view modes on a frozen bar")
        _ = live.toolbar

        let dimmed = bareToolbar()
        dimmed.model.selection = .module("test.viewModeDisabled")
        dimmed.channel.declare(viewMode(isEnabled: false), token: "test.viewModeDisabled",
                               generation: dimmed.channel.nextGeneration())
        settle(dimmed.window)
        let disabled = try XCTUnwrap(switcher(in: dimmed.window), "no view-mode switcher on the second bar")
        XCTAssertFalse(disabled.isEnabled, "the page disabled the view-mode switcher and it still takes presses")
        _ = dimmed.toolbar
    }
}
