import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings toolbar's own right-click menu, read the way AppKit reads it
/// — through the bar on screen, not through the builder.**
///
/// `SettingsToolbar.barMenuItems` is a static a test could call with any
/// arguments it liked; what a person gets is whatever `menuNeedsUpdate(_:)`
/// hands it from the bar that is attached at the moment the menu opens. So
/// every case here mounts a real bar, reaches the one menu instance through
/// the centre switcher's own `NSView.menu` (the VoiceOver path, and the only
/// handle on the private instance a test can reach), asks the menu's own
/// delegate to fill it, and reads
/// what came out — after a page switch too, because one instance serves every
/// page and a menu filled once would go on offering the last page's sections.
///
/// The words are compared against each language's own `.lproj` table read off
/// disk (`Localized.stringsFile(for:)`), never against `L(_:)` — the menu calls
/// `L(_:)` itself, and an assertion reading the same lookup on both sides
/// passes over a key nobody translated.
@MainActor
final class TheBarMenuOffersWhatThePageHoldsTests: XCTestCase {

    private static let sidebarWidth: CGFloat = 214
    private static let collapseKey = "alwaysCollapseSearch"

    /// Raw, so a key the domain did not hold is removed again rather than
    /// written back as the typed getter's default.
    private var savedPageBar: Any?
    private var savedSwitcher: Any?
    private var savedCollapse: Any?

    override func setUp() async throws {
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedSwitcher = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        savedCollapse = AppSettings.store.object(Self.collapseKey)
        AppSettings.pageBarStyle = .moduleName
        AppSettings.toolbarSwitcherStyle = .text
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedSwitcher, for: ToolbarSwitcherStyle.storageKey)
        AppSettings.store.set(savedCollapse, for: Self.collapseKey)
    }

    // MARK: - Rig

    private func tabs() -> [HelmToolbarTab] {
        [
            HelmToolbarTab(id: "installed", title: L("Installed"), symbol: "shippingbox"),
            HelmToolbarTab(id: "updates", title: L("Updates"), symbol: "arrow.up.circle"),
            HelmToolbarTab(id: "health", title: L("Health"), symbol: "stethoscope")
        ]
    }

    private enum Kind: CaseIterable, CustomStringConvertible {
        case tabsAndSearch, tabsOnly, searchOnly, nameOnly
        var description: String {
            switch self {
            case .tabsAndSearch: "tabs and search"
            case .tabsOnly: "tabs only"
            case .searchOnly: "search only"
            case .nameOnly: "name only"
            }
        }
    }

    private func content(_ kind: Kind) -> HelmPageToolbarContent? {
        let refresh = HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}
        let search = HelmToolbarSearch(prompt: L("Search packages"), text: .constant(""))
        switch kind {
        case .tabsAndSearch:
            return HelmPageToolbarContent(tabs: tabs(), selectedTab: .constant("installed"),
                                          actions: [refresh], search: search)
        case .tabsOnly:
            return HelmPageToolbarContent(tabs: tabs(), selectedTab: .constant("installed"), actions: [refresh])
        case .searchOnly:
            return HelmPageToolbarContent(actions: [refresh], search: search)
        case .nameOnly:
            return nil
        }
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
    }

    /// `SettingsSplitViewController`'s shape — a 214 pt sidebar beside the
    /// pane — with a page of tabs and search declared, so the centre switcher
    /// (and through it the bar's menu) exists from the start.
    private func mount(pane: CGFloat = 1060) -> Rig {
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
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
        window.orderBack(nil)
        window.layoutIfNeeded()
        toolbar.window = window
        let rig = Rig(window: window, toolbar: toolbar, model: model, channel: channel)
        show(.tabsAndSearch, on: rig, token: "test.barMenu.first")
        return rig
    }

    private func close(_ rig: Rig) {
        rig.window.toolbar = nil
        rig.window.close()
    }

    /// Selects a page of `kind` and, where it has anything, declares it —
    /// a name-only page is General, which declares nothing.
    private func show(_ kind: Kind, on rig: Rig, token: String) {
        if let content = content(kind) {
            rig.model.selection = .module(token)
            rig.channel.declare(content, token: token, generation: rig.channel.nextGeneration())
        } else {
            rig.model.selection = .general
        }
        pump(rig.window)
    }

    private func pump(_ window: NSWindow, turns: Int = 10) {
        for _ in 0..<turns {
            window.layoutIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private func switcher(_ window: NSWindow) -> NSSegmentedControl? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.tabs" }?
            .view?.everyView(ofType: NSSegmentedControl.self).first
    }

    /// The menu as AppKit fills it just before drawing it.
    private func opened(_ menu: NSMenu) -> [NSMenuItem] {
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu.items
    }

    /// One line per item — a section header as `[title]`, a separator as `—`,
    /// an item as its title with `✓` when ticked — so a failure prints the
    /// whole menu a person would have seen.
    private func shape(_ items: [NSMenuItem]) -> [String] {
        items.map { item in
            if item.isSeparatorItem { return "—" }
            if item.isSectionHeader { return "[\(item.title)]" }
            return item.title + (item.state == .on ? " ✓" : "")
        }
    }

    private func expectedShape(_ kind: Kind, pageBar: PageBarStyle, labels: ToolbarSwitcherStyle,
                               collapse: Bool) -> [String] {
        func tick(_ on: Bool) -> String { on ? " ✓" : "" }
        var lines = ["[\(L("Page header"))]",
                     L("With Icon") + tick(pageBar == .moduleName),
                     L("Without Icon") + tick(pageBar == .windowTitle)]
        if kind == .tabsAndSearch || kind == .tabsOnly {
            lines += ["—", "[\(L("Tab labels"))]"]
            lines += ToolbarSwitcherStyle.allCases.map { $0.label + tick($0 == labels) }
        }
        if kind == .tabsAndSearch || kind == .searchOnly {
            lines += ["—", L("Always Collapse Search") + tick(collapse)]
        }
        return lines
    }

    // MARK: - The switcher carries the bar's menu

    /// **The centre switcher's own menu is the bar's one menu**, the same
    /// instance on every page, answering to the toolbar — VoiceOver's "show
    /// menu" on a focused switcher opens this and nothing else.
    func testTheCentreSwitcherCarriesTheBarsOneMenu() {
        let rig = mount()
        defer { close(rig) }
        guard let first = switcher(rig.window)?.menu else {
            return XCTFail("the centre switcher carries no menu — VoiceOver's show-menu opens nothing")
        }
        XCTAssertTrue(first.delegate === rig.toolbar,
                      "the switcher's menu is not filled by the toolbar — it is not the bar's menu")
        XCTAssertFalse(opened(first).isEmpty, "the switcher's menu opened empty")

        show(.tabsOnly, on: rig, token: "test.barMenu.second")
        guard let second = switcher(rig.window)?.menu else {
            return XCTFail("the second page's switcher carries no menu")
        }
        XCTAssertTrue(first === second,
                      "two pages' switchers carry two menus — the bar has one, rebuilt as it opens")
    }

    // MARK: - What each kind of page is offered

    /// **Every kind of page, reached in turn through one menu instance**: the
    /// page header everywhere, the tabs' labels only where there are tabs,
    /// Always Collapse Search only where there is a search field — and each
    /// section present exactly once, whatever page the menu last opened on.
    func testEachKindOfPageIsOfferedWhatItHoldsAndNothingElse() {
        let rig = mount()
        defer { close(rig) }
        guard let menu = switcher(rig.window)?.menu else {
            return XCTFail("no switcher menu to open — nothing below is read")
        }
        // Twice round, so every kind is also reached *from* every other kind
        // the order puts before it, and each kind is opened twice in a row.
        let order: [Kind] = [.tabsAndSearch, .nameOnly, .tabsOnly, .searchOnly, .tabsAndSearch,
                             .searchOnly, .nameOnly, .nameOnly, .tabsOnly, .tabsOnly]
        for (step, kind) in order.enumerated() {
            show(kind, on: rig, token: "test.barMenu.\(kind).\(step)")
            let got = shape(opened(menu))
            XCTAssertEqual(got, expectedShape(kind, pageBar: .moduleName, labels: .text, collapse: false), """
                step \(step), a \(kind) page: the bar's menu offered \(got)
                """)
        }
    }

    // MARK: - The ticks

    /// **One tick per group, on whatever the settings hold right now** —
    /// read after each setting moved underneath a menu that was already
    /// filled once, which is the order a person meets it in (choose in
    /// General, then right-click the bar).
    func testTheTicksAreTheSettingsOfTheMomentTheMenuOpens() {
        let rig = mount()
        defer { close(rig) }
        guard let menu = switcher(rig.window)?.menu else {
            return XCTFail("no switcher menu to open — nothing below is read")
        }
        _ = opened(menu)
        for pageBar in PageBarStyle.allCases {
            for labels in ToolbarSwitcherStyle.allCases {
                for collapse in [false, true, false] {
                    AppSettings.pageBarStyle = pageBar
                    AppSettings.toolbarSwitcherStyle = labels
                    AppSettings.alwaysCollapseSearch = collapse
                    pump(rig.window, turns: 3)
                    guard let fresh = switcher(rig.window)?.menu else {
                        XCTFail("\(pageBar)/\(labels)/\(collapse): the switcher lost its menu")
                        continue
                    }
                    XCTAssertTrue(fresh === menu, "\(pageBar)/\(labels): a rebuilt bar carries another menu")
                    let got = shape(opened(fresh))
                    XCTAssertEqual(got, expectedShape(.tabsAndSearch, pageBar: pageBar, labels: labels,
                                                      collapse: collapse), """
                        with \(pageBar), \(labels), collapse \(collapse) the menu read \(got)
                        """)
                }
            }
        }
    }

    // MARK: - Each item writes its own setting

    private func choose(_ title: String, in menu: NSMenu, _ context: String) {
        guard let item = opened(menu).first(where: { $0.title == title && !$0.isSectionHeader }) else {
            return XCTFail("\(context): no «\(title)» in the menu")
        }
        XCTAssertTrue(item.isEnabled, "\(context): «\(title)» is offered disabled")
        guard let action = item.action else { return XCTFail("\(context): «\(title)» sends nothing") }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item),
                      "\(context): «\(title)» found nobody to answer it")
    }

    /// **Pressing an item changes exactly its own setting**, pressing it
    /// again with the setting already there changes nothing, and the toggle
    /// pressed twice comes back where it started — each through the item's
    /// own action and target, as AppKit would send it.
    func testEachItemWritesItsOwnSettingAndOnlyThat() {
        let rig = mount()
        defer { close(rig) }
        guard let menu = switcher(rig.window)?.menu else {
            return XCTFail("no switcher menu to open — nothing below is read")
        }

        choose(L("Without Icon"), in: menu, "Without Icon")
        XCTAssertEqual(AppSettings.pageBarStyle, .windowTitle, "Without Icon did not choose the window title")
        XCTAssertEqual(AppSettings.toolbarSwitcherStyle, .text, "Without Icon moved the tab labels")
        XCTAssertFalse(AppSettings.alwaysCollapseSearch, "Without Icon moved Always Collapse Search")
        pump(rig.window)
        guard let menu = switcher(rig.window)?.menu else {
            return XCTFail("after Without Icon the rebuilt bar's switcher carries no menu")
        }
        choose(L("Without Icon"), in: menu, "Without Icon again")
        XCTAssertEqual(AppSettings.pageBarStyle, .windowTitle, "Without Icon chosen twice left the window title")
        choose(L("With Icon"), in: menu, "With Icon")
        XCTAssertEqual(AppSettings.pageBarStyle, .moduleName, "With Icon did not bring the name back")
        pump(rig.window)

        for style in ToolbarSwitcherStyle.allCases.reversed() {
            guard let menu = switcher(rig.window)?.menu else { return XCTFail("no switcher menu") }
            choose(style.label, in: menu, "\(style)")
            XCTAssertEqual(AppSettings.toolbarSwitcherStyle, style, "«\(style.label)» chose something else")
            XCTAssertEqual(AppSettings.pageBarStyle, .moduleName, "«\(style.label)» moved the page header")
            pump(rig.window, turns: 3)
        }

        guard let menu = switcher(rig.window)?.menu else { return XCTFail("no switcher menu") }
        choose(L("Always Collapse Search"), in: menu, "Always Collapse Search")
        XCTAssertTrue(AppSettings.alwaysCollapseSearch, "Always Collapse Search did not turn on")
        XCTAssertEqual(AppSettings.store.object(Self.collapseKey) as? Bool, true,
                       "the toggle stored something other than a Bool")
        choose(L("Always Collapse Search"), in: menu, "Always Collapse Search again")
        XCTAssertFalse(AppSettings.alwaysCollapseSearch, "Always Collapse Search pressed twice did not turn off")
    }

    // MARK: - The words

    private func table(_ language: AppLanguage) -> [String: String] {
        guard let path = Localized.stringsFile(for: language)?.path,
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("no Localizable.strings for \(language.rawValue)")
            return [:]
        }
        return dict
    }

    /// **Each title is that language's own entry for its English key**, read
    /// off the `.lproj` file on disk — a key misspelled at the call site
    /// falls back to its English text and shows up here in seven languages;
    /// and none of the new words is merely English copied into a language
    /// that has its own.
    func testTheMenusWordsAreEachLanguagesOwn() {
        let rig = mount()
        defer { close(rig) }
        guard let menu = switcher(rig.window)?.menu else {
            return XCTFail("no switcher menu to open — nothing below is read")
        }
        let keys = ["Page header", "With Icon", "Without Icon", "Tab labels"]
            + ["Text Only", "Icon Only", "Icon and Text"] + ["Always Collapse Search"]
        AppLanguage.each { language in
            let titles = opened(menu).filter { !$0.isSeparatorItem }.map(\.title)
            let file = table(language)
            let want = keys.map { key in language == .en ? key : (file[key] ?? "«\(key)» missing from the file") }
            XCTAssertEqual(titles, want, "\(language.rawValue): the menu reads \(titles)")
            if language != .en {
                for key in ["With Icon", "Without Icon", "Always Collapse Search"] {
                    XCTAssertNotEqual(file[key], key, "\(language.rawValue): «\(key)» is English in its file")
                }
            }
        }
        AppLanguage.only(.ru) {
            XCTAssertEqual(opened(menu).last?.title, "Всегда сворачивать поиск",
                           "ru: the toggle is not the owner's own words")
        }
    }

    // MARK: - A value nobody wrote as a Bool

    /// **A property list anything can write**: a string, a number other than
    /// 0 and 1, a date, an array. Each must read as off — the default — on
    /// the menu *and* on the bar, which are two separate readers of one
    /// setting and must not disagree about a value neither wrote; and the
    /// toggle pressed over it must store a real Bool, turning it on.
    func testAPlantedValueReadsAsOffOnTheMenuAndTheBarAlike() {
        let rig = mount()
        defer { close(rig) }
        guard let menu = switcher(rig.window)?.menu else {
            return XCTFail("no switcher menu to open — nothing below is read")
        }
        let planted: [(String, Any)] = [("the string YES", "YES"), ("the string 1", "1"),
                                        ("the number 2", 2), ("a date", Date()), ("an array", [true])]
        for (name, value) in planted {
            UserDefaults.standard.set(value, forKey: "module.app.\(Self.collapseKey)")
            // What a real write would have announced — the bar re-reads on it.
            NotificationCenter.default.post(name: .helmAlwaysCollapseSearchChanged, object: nil)
            pump(rig.window, turns: 20)
            XCTAssertFalse(AppSettings.alwaysCollapseSearch, "\(name) reads as on")
            let toggle = opened(menu).last
            XCTAssertEqual(toggle?.title, L("Always Collapse Search"), "\(name): no toggle last in the menu")
            XCTAssertEqual(toggle?.state, .off, "\(name): the menu ticks Always Collapse Search")
            let field = rig.window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first?.searchField
            XCTAssertNotNil(field, "\(name): no search field on the bar")
            XCTAssertEqual(field?.isHidden, false, """
                \(name): the bar rests the search as its magnifier at 1060 pt while the menu says \
                the setting is off — two readers of one value disagree
                """)

            choose(L("Always Collapse Search"), in: menu, name)
            XCTAssertEqual(AppSettings.store.object(Self.collapseKey) as? Bool, true,
                           "\(name): the toggle over it did not store a real true")
            AppSettings.alwaysCollapseSearch = false
            pump(rig.window, turns: 10)
        }
    }
}
