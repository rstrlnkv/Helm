import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI
@testable import Module_Hosts_UI

/// **`helm.actions` is in the bar's `NSToolbar.centeredItemIdentifiers`
/// exactly when the bar has centre tabs and declares a `.segmented` action**
/// — Hosts on both of its tabs, and no other shape: not a bar without tabs,
/// and not a bar with tabs whose actions are buttons, toggles or menus.
///
/// The owner asked for Hosts' Table / Plain-text switcher to move the way the
/// centre tabs move (2026-09-26): the selection lifts on the press and slides
/// to the new segment. What decides that was measured by engineer
/// (2026-09-26), not by this file. In a reference app built outside this
/// tree, AppKit gave a toolbar segmented control the lift-and-slide tracking
/// only while its item was listed in `NSToolbar.centeredItemIdentifiers`;
/// the glass around it, the tabs' label style and its binding made no
/// difference, and the centre tabs' own switcher stopped sliding when its
/// item was left out of the set — except hosting: wrapping the item in an
/// AppKit platter of its own tracked neither way cleanly
/// (`SettingsToolbar.centredIdentifiers(_:)`'s own header carries those
/// counts), a hosting this capsule's own item never takes. Listed on its own the
/// capsule's item was moved to the middle of the bar; listed beside the
/// tabs it stayed where it was — on every module page (`ls Sources/Modules |
/// wc -l`), in English and Russian, at 1060 and 860 pt and in the fold
/// tests' split rig, the frames
/// of `helm.tabs`, `helm.actions` and `helm.search` read the same to a tenth
/// of a point with and without the capsule in the set. Filmed in Helm Dev by
/// engineer, counted in frames per press — both segments lit at once (the
/// classic tracking), the selection between the two segments' centres (the
/// slide), and the old segment unlit while a long press is still held (the
/// lift): before, 4–6 lit together, 0 sliding, 0 lifted; with the capsule in
/// the set, 0–1, 5–8 and 7–9 in Dark, 0, 3–7 and 7–8 in Light.
///
/// **This file cannot see motion.** It reads the one structural fact the
/// films were measured to depend on, off the toolbar AppKit is actually
/// handed, so a set that loses the capsule — or gains it on a page where it
/// was not measured — is red here without anybody filming anything.
///
/// Red against the working tree it was written for (tester, 2026-09-26),
/// where `buildBar` centred `helm.tabs` alone on every bar with tabs.
@MainActor
final class ASwitcherInTheCapsuleIsCentredWithTheTabsTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data { Data() }
    }

    /// Homebrew declares its bar only once brew is known to be installed —
    /// with nothing answering, the page draws its install prompt and no
    /// toolbar at all.
    private final class InstalledBrew: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    private static let tabsID = NSToolbarItem.Identifier("helm.tabs")
    private static let actionsID = NSToolbarItem.Identifier("helm.actions")

    private var fixtures: [LivePageToolbarFixture] = []
    private var windows: [NSWindow] = []
    private var toolbars: [SettingsToolbar] = []

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        windows.forEach { $0.toolbar = nil }
        windows = []
        toolbars = []
        super.tearDown()
    }

    private func hasSegmented(_ content: HelmPageToolbarContent) -> Bool {
        content.actions.contains { if case .segmented = $0.kind { return true } else { return false } }
    }

    // MARK: - The real pages

    /// Hosts declares the switcher on both tabs — shown on SSH, out of the
    /// capsule's visible set on Keys — so the capsule is centred on both.
    func testHostsCentresTheCapsuleBesideTheTabsOnBothOfItsTabs() throws {
        let hosts = LivePageToolbarFixture(HostsSettingsPage(vm: ModuleViewModel(transport: Mute())),
                                           selection: .module(HostsDescriptor.id.rawValue),
                                           width: 1060, height: 700)
        fixtures.append(hosts)
        hosts.settle(30)
        for tab in ["keys", "ssh"] {
            let content = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue),
                                        "Hosts declared nothing onto the channel")
            try XCTUnwrap(content.selectedTab, "Hosts declared no tabs").wrappedValue = tab
            hosts.settle(30)
            let now = try XCTUnwrap(hosts.channel.content(for: HostsDescriptor.id.rawValue))
            // The subject: the shape this file is about is what Hosts declares.
            XCTAssertEqual(now.selectedTab?.wrappedValue, tab, "precondition: Hosts did not move to \(tab)")
            XCTAssertFalse(now.tabs.isEmpty, "precondition: Hosts declared no centre tabs on \(tab)")
            XCTAssertTrue(hasSegmented(now), "precondition: Hosts declared no .segmented action on \(tab)")
            let toolbar = try XCTUnwrap(hosts.mount.window?.toolbar, "no toolbar on the window on \(tab)")
            XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier == Self.actionsID },
                          "precondition: no helm.actions item on the bar on \(tab)")
            XCTAssertEqual(toolbar.centeredItemIdentifiers, [Self.tabsID, Self.actionsID], """
                Hosts on \(tab): the bar centres \(toolbar.centeredItemIdentifiers.map(\.rawValue).sorted()) — \
                the view-mode switcher's item is not centred beside the tabs, and AppKit tracks it the classic \
                way rather than lifting and sliding it
                """)
        }
    }

    /// Homebrew: centre tabs, and only buttons in the capsule.
    func testHomebrewCentresItsTabsAlone() async throws {
        let mvm = ModuleViewModel(transport: InstalledBrew())
        await HomebrewViewModel.shared(vm: mvm).loadIfNeeded()
        let homebrew = LivePageToolbarFixture(HomebrewSettingsPage(vm: mvm),
                                              selection: .module(HomebrewDescriptor.id.rawValue),
                                              width: 1060, height: 700)
        fixtures.append(homebrew)
        homebrew.settle(30)
        let content = try XCTUnwrap(homebrew.channel.content(for: HomebrewDescriptor.id.rawValue),
                                    "Homebrew declared nothing onto the channel")
        XCTAssertFalse(content.tabs.isEmpty, "precondition: Homebrew declared no centre tabs")
        XCTAssertFalse(content.actions.isEmpty, "precondition: Homebrew declared no actions")
        XCTAssertFalse(hasSegmented(content), "precondition: Homebrew now declares a .segmented action")
        let toolbar = try XCTUnwrap(homebrew.mount.window?.toolbar)
        XCTAssertEqual(toolbar.centeredItemIdentifiers, [Self.tabsID], """
            Homebrew centres \(toolbar.centeredItemIdentifiers.map(\.rawValue).sorted()) — a capsule with \
            nothing to slide was moved into the centred set
            """)
    }

    // MARK: - Every shape, declared

    private func bar(_ token: String) -> (SettingsToolbar, HelmWindowToolbarChannel, NSWindow) {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        toolbar.window = window
        model.selection = .module(token)
        windows.append(window)
        toolbars.append(toolbar)
        return (toolbar, channel, window)
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<10 {
            window.layoutIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private static let twoTabs = [HelmToolbarTab(id: "first", title: "Alpha", symbol: "circle"),
                                  HelmToolbarTab(id: "second", title: "Beta", symbol: "square")]

    private static func segmented(_ id: String = "mode", visible: Bool = true) -> HelmToolbarAction {
        HelmToolbarAction(id: id, title: "Mode", isVisible: visible,
                          options: [HelmToolbarTab(id: "table", title: "Table", symbol: "tablecells"),
                                    HelmToolbarTab(id: "text", title: "Text", symbol: "text.alignleft")],
                          selection: .constant("table"))
    }

    private static func button(_ id: String = "mode") -> HelmToolbarAction {
        HelmToolbarAction(id: id, title: "Refresh", symbol: "arrow.clockwise") {}
    }

    private static func toggle(_ id: String = "mode") -> HelmToolbarAction {
        HelmToolbarAction(id: id, title: "Pin", symbol: "pin", isOn: true) {}
    }

    private static func menu(_ id: String = "mode") -> HelmToolbarAction {
        HelmToolbarAction(id: id, title: "Filter", symbol: "line.3.horizontal.decrease",
                          menu: [HelmToolbarMenuItem(id: "all", title: "All", isOn: true) {}])
    }

    private static func content(tabs: Bool, actions: [HelmToolbarAction],
                                search: Bool = false) -> HelmPageToolbarContent {
        HelmPageToolbarContent(tabs: tabs ? twoTabs : [], selectedTab: tabs ? .constant("first") : nil,
                               actions: actions,
                               search: search ? HelmToolbarSearch(prompt: "Search", text: .constant("")) : nil)
    }

    func testTheCapsuleIsCentredOnlyBesideTabsAndOnlyWithASwitcherInIt() {
        let both: Set<NSToolbarItem.Identifier> = [Self.tabsID, Self.actionsID]
        let tabsAlone: Set<NSToolbarItem.Identifier> = [Self.tabsID]
        let cases: [(String, HelmPageToolbarContent, Set<NSToolbarItem.Identifier>)] = [
            ("tabs, a shown switcher", Self.content(tabs: true, actions: [Self.segmented()]), both),
            ("tabs, a hidden switcher beside a button",
             Self.content(tabs: true, actions: [Self.segmented(visible: false), Self.button("add")]), both),
            ("tabs, a switcher, search",
             Self.content(tabs: true, actions: [Self.segmented()], search: true), both),
            ("tabs, a button", Self.content(tabs: true, actions: [Self.button()]), tabsAlone),
            ("tabs, a toggle", Self.content(tabs: true, actions: [Self.toggle()]), tabsAlone),
            ("tabs, a menu", Self.content(tabs: true, actions: [Self.menu()]), tabsAlone),
            ("tabs, search, no actions", Self.content(tabs: true, actions: [], search: true), tabsAlone),
            ("no tabs, a switcher", Self.content(tabs: false, actions: [Self.segmented()]), []),
            ("no tabs, a switcher beside a button",
             Self.content(tabs: false, actions: [Self.segmented(), Self.button("add")]), []),
            ("no tabs, a button, search", Self.content(tabs: false, actions: [Self.button()], search: true), []),
            ("nothing", Self.content(tabs: false, actions: []), []),
        ]
        for (index, (name, content, expected)) in cases.enumerated() {
            let token = "test.centred.\(index)"
            let (_, channel, window) = bar(token)
            channel.declare(content, token: token, generation: channel.nextGeneration())
            settle(window)
            guard let toolbar = window.toolbar else { XCTFail("\(name): no toolbar on the window"); continue }
            // The subject: the bar on the window is the one built for this
            // declaration, and carries the capsule wherever there are actions.
            XCTAssertEqual(toolbar.items.contains { $0.itemIdentifier == Self.actionsID }, !content.actions.isEmpty,
                           "precondition \(name): the bar on the window is not the one this shape builds")
            XCTAssertEqual(toolbar.centeredItemIdentifiers, expected, """
                \(name): the bar centres \(toolbar.centeredItemIdentifiers.map(\.rawValue).sorted()), \
                expected \(expected.map(\.rawValue).sorted())
                """)
        }
    }

    /// **An action that changes kind under the same id** — a shape
    /// `ShapeSignature`'s action ids cannot tell apart — moves the centred set
    /// both ways on the same page.
    func testAnActionThatBecomesASwitcherUnderTheSameIdJoinsTheSetAndLeavesIt() {
        let token = "test.centred.kind"
        let (_, channel, window) = bar(token)
        let steps: [(String, HelmToolbarAction, Set<NSToolbarItem.Identifier>)] = [
            ("a button", Self.button(), [Self.tabsID]),
            ("the same id as a switcher", Self.segmented(), [Self.tabsID, Self.actionsID]),
            ("the same id as a button again", Self.button(), [Self.tabsID]),
            ("the same id as a menu", Self.menu(), [Self.tabsID]),
            ("the same id as a switcher again", Self.segmented(), [Self.tabsID, Self.actionsID]),
        ]
        for (name, action, expected) in steps {
            channel.declare(Self.content(tabs: true, actions: [action]), token: token,
                            generation: channel.nextGeneration())
            settle(window)
            guard let toolbar = window.toolbar else { XCTFail("\(name): no toolbar on the window"); continue }
            XCTAssertEqual(toolbar.centeredItemIdentifiers, expected, """
                \(name): the bar centres \(toolbar.centeredItemIdentifiers.map(\.rawValue).sorted()), \
                expected \(expected.map(\.rawValue).sorted())
                """)
        }
    }
}
