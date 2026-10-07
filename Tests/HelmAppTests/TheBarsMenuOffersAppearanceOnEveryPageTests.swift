import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The bar's one menu offers Appearance (Flat, Liquid Glass) on every kind of page, writes it once,
/// and the General row that mirrors it follows a choice made there.**
///
/// No window is ordered anywhere. The items are read through `ShellBarMenu.items`, the new bar's menu
/// through its own view's `NSView.menu` and that menu's delegate, the way AppKit fills it, and the General row
/// is hosted in an `NSHostingView` that never meets a window. The bar is built on three zones that
/// show nothing, so what a menu is filled from is what the channel declared and nothing else.
///
/// The settings the menu touches are kept raw in `setUp` and put back in `tearDown`, so a key the domain did
/// not hold is removed again rather than written back as a typed default.
@MainActor
final class TheBarsMenuOffersAppearanceOnEveryPageTests: XCTestCase {

    private static let collapseKey = "alwaysCollapseSearch"

    private var savedPageBar: Any?
    private var savedSwitcher: Any?
    private var savedCollapse: Any?
    private var savedAppearance: Any?

    override func setUp() async throws {
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedSwitcher = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        savedCollapse = AppSettings.store.object(Self.collapseKey)
        savedAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        AppSettings.pageBarStyle = .moduleName
        AppSettings.toolbarSwitcherStyle = .text
        AppSettings.alwaysCollapseSearch = false
        AppSettings.barAppearance = .flat
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedSwitcher, for: ToolbarSwitcherStyle.storageKey)
        AppSettings.store.set(savedCollapse, for: Self.collapseKey)
        AppSettings.store.set(savedAppearance, for: HelmBarAppearance.storageKey)
    }

    // MARK: - Rig

    /// A zone that shows nothing and measures nothing: the port's states only.
    @MainActor
    private final class MuteZone: ShellBarZone {
        var view: NSView?
        var measuresMoved: (() -> Void)?
        func show(_ state: ShellBarZoneState) {}
        func measure(into measures: inout ShellPageBarView.Measures) {}
        func apply(_ verdicts: ShellPageBarView.Verdicts) {}
    }

    private enum Kind: CaseIterable, CustomStringConvertible {
        case tabsAndSearch, tabsOnly, searchOnly, nameOnly
        var hasTabs: Bool { self == .tabsAndSearch || self == .tabsOnly }
        var hasSearch: Bool { self == .tabsAndSearch || self == .searchOnly }
        var description: String {
            switch self {
            case .tabsAndSearch: "tabs and search"
            case .tabsOnly: "tabs only"
            case .searchOnly: "search only"
            case .nameOnly: "name only"
            }
        }
    }

    private func menuItems(_ kind: Kind) -> [NSMenuItem] {
        ShellBarMenu.items(pageBarStyle: AppSettings.pageBarStyle,
                           tabLabels: kind.hasTabs ? AppSettings.toolbarSwitcherStyle : nil,
                           appearance: AppSettings.barAppearance,
                           alwaysCollapseSearch: kind.hasSearch ? AppSettings.alwaysCollapseSearch : nil)
    }

    private func appearanceItems(in items: [NSMenuItem]) -> [NSMenuItem] {
        guard let header = items.firstIndex(where: { $0.isSectionHeader && $0.title == AppStr.appearance })
        else { return [] }
        return Array(items[(header + 1)...].prefix { !$0.isSeparatorItem && !$0.isSectionHeader })
    }

    private func press(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }
        // `NSApp` is nil until something makes the shared application; nothing here opens a window.
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    /// Counts what the appearance setting announces, until released.
    private final class Hearing {
        private(set) var count = 0
        private var watch: NSObjectProtocol?
        init() {
            watch = NotificationCenter.default.addObserver(forName: .helmBarAppearanceChanged, object: nil,
                                                           queue: nil) { [weak self] _ in self?.count += 1 }
        }
        deinit { if let watch { NotificationCenter.default.removeObserver(watch) } }
    }

    private func pump(_ seconds: TimeInterval = 0.2) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    // MARK: - Every page, the stored one ticked

    func testTheMenuOffersAppearanceOnEveryPageWithTheStoredOneTicked() {
        for stored in HelmBarAppearance.allCases {
            AppSettings.barAppearance = stored
            for kind in Kind.allCases {
                let context = "\(kind), stored \(stored)"
                let items = menuItems(kind)
                guard !items.isEmpty else {
                    XCTFail("\(context): the menu has no items at all: no page was offered anything")
                    continue
                }
                let headers = items.filter(\.isSectionHeader).map(\.title)
                let expectedHeaders = [AppStr.pageBar] + (kind.hasTabs ? [AppStr.tabLabels] : [])
                    + [AppStr.appearance]
                XCTAssertEqual(headers, expectedHeaders, "\(context): the sections read \(headers)")

                let section = appearanceItems(in: items)
                XCTAssertEqual(section.map { $0.representedObject as? String },
                               HelmBarAppearance.allCases.map(\.rawValue),
                               "\(context): the Appearance section does not offer each choice once, in order")
                XCTAssertEqual(section.map(\.title), [AppStr.barAppearanceFlat, AppStr.barAppearanceLiquidGlass],
                               "\(context): the Appearance titles are not Flat and Liquid Glass")
                XCTAssertEqual(section.filter { $0.state == .on }.map { $0.representedObject as? String },
                               [stored.rawValue], "\(context): the tick is not on the stored choice alone")
                for item in section {
                    XCTAssertTrue(item.target === ShellBarMenu.actions,
                                  "\(context): «\(item.title)» is not answered by the shared actions")
                    XCTAssertNotNil(item.action, "\(context): «\(item.title)» sends nothing")
                    XCTAssertTrue(item.isEnabled, "\(context): «\(item.title)» is offered disabled")
                }

                // The section sits after Tab labels and before Always Collapse Search.
                guard let appearanceAt = items.firstIndex(where: { $0.isSectionHeader && $0.title == AppStr.appearance })
                else { continue }
                XCTAssertTrue(items[appearanceAt - 1].isSeparatorItem,
                              "\(context): no separator before the Appearance header")
                if let tabsAt = items.firstIndex(where: { $0.isSectionHeader && $0.title == AppStr.tabLabels }) {
                    XCTAssertLessThan(tabsAt, appearanceAt, "\(context): Appearance comes before Tab labels")
                }
                let toggleAt = items.firstIndex { $0.title == AppStr.alwaysCollapseSearch && !$0.isSectionHeader }
                XCTAssertEqual(toggleAt != nil, kind.hasSearch, "\(context): Always Collapse Search is wrongly present or absent")
                if let toggleAt {
                    XCTAssertGreaterThan(toggleAt, appearanceAt + section.count,
                                         "\(context): Always Collapse Search comes before the Appearance section's end")
                    XCTAssertEqual(toggleAt, items.count - 1, "\(context): Always Collapse Search is not last")
                } else {
                    XCTAssertEqual(appearanceAt + section.count + 1, items.count,
                                   "\(context): something follows Appearance on a page without a search field")
                }
            }
        }
    }

    // MARK: - A choice is written once

    func testChoosingAnAppearanceWritesItOnceAndAnEqualOneWritesNothing() {
        let section = appearanceItems(in: menuItems(.tabsAndSearch))
        guard let glass = section.first(where: {
            ($0.representedObject as? String) == HelmBarAppearance.liquidGlass.rawValue
        }), let flat = section.first(where: {
            ($0.representedObject as? String) == HelmBarAppearance.flat.rawValue
        }) else {
            return XCTFail("no Appearance item to press: nothing was written and nothing was refused")
        }
        let hearing = Hearing()
        let others = (AppSettings.pageBarStyle, AppSettings.toolbarSwitcherStyle, AppSettings.alwaysCollapseSearch)

        XCTAssertTrue(press(glass), "Liquid Glass found nobody to answer it")
        XCTAssertEqual(AppSettings.barAppearance, .liquidGlass, "Liquid Glass did not store Liquid Glass")
        XCTAssertEqual(AppSettings.store.string(HelmBarAppearance.storageKey, default: ""), "liquidGlass",
                       "the stored value is not the raw value")
        XCTAssertEqual(hearing.count, 1, "choosing a new appearance announced it \(hearing.count) times")
        XCTAssertEqual(AppSettings.pageBarStyle, others.0, "Liquid Glass moved the page header")
        XCTAssertEqual(AppSettings.toolbarSwitcherStyle, others.1, "Liquid Glass moved the tab labels")
        XCTAssertEqual(AppSettings.alwaysCollapseSearch, others.2, "Liquid Glass moved Always Collapse Search")

        XCTAssertTrue(press(glass), "Liquid Glass pressed again found nobody to answer it")
        XCTAssertEqual(hearing.count, 1, "an equal choice was written and announced again")
        XCTAssertEqual(AppSettings.barAppearance, .liquidGlass)

        XCTAssertTrue(press(flat), "Flat found nobody to answer it")
        XCTAssertEqual(AppSettings.barAppearance, .flat, "Flat did not store Flat")
        XCTAssertEqual(hearing.count, 2, "going back announced \(hearing.count - 1) more times, not one")
    }

    // MARK: - The new bar's menu

    func testTheNewBarsMenuIsFilledFromWhatTheBarShows() {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let bar = ShellPageBar(model: model, channel: channel, tabs: MuteZone(), actions: MuteZone(),
                               search: MuteZone(), titlebarIsTransparent: true)
        guard let menu = bar.view.menu else {
            return XCTFail("the bar's view carries no menu: a right-click opens nothing")
        }
        XCTAssertTrue(menu.delegate === bar, "the bar's menu is not filled by the bar")

        func opened() -> [NSMenuItem] {
            menu.delegate?.menuNeedsUpdate?(menu)
            return menu.items
        }
        func headers() -> [String] { opened().filter(\.isSectionHeader).map(\.title) }
        func hasToggle() -> Bool { opened().contains { $0.title == AppStr.alwaysCollapseSearch && !$0.isSectionHeader } }
        func declare(_ content: HelmPageToolbarContent) {
            channel.declare(content, token: "general", generation: channel.nextGeneration())
        }
        let refresh = HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}
        let tabs = [HelmToolbarTab(id: "one", title: "One", symbol: "shippingbox"),
                    HelmToolbarTab(id: "two", title: "Two", symbol: "arrow.up.circle")]
        let search = HelmToolbarSearch(prompt: "Search", text: .constant(""))

        model.selection = .general
        XCTAssertEqual(headers(), [AppStr.pageBar, AppStr.appearance],
                       "before any page declared, the menu offers more than the page header and Appearance")
        XCTAssertFalse(hasToggle(), "a page that declared nothing is offered Always Collapse Search")
        XCTAssertEqual(appearanceItems(in: opened()).count, 2, "the Appearance section is not Flat and Liquid Glass")

        declare(HelmPageToolbarContent(tabs: tabs, selectedTab: .constant("one"), actions: [refresh], search: search))
        XCTAssertEqual(headers(), [AppStr.pageBar, AppStr.tabLabels, AppStr.appearance],
                       "a page with tabs is not offered Tab labels")
        XCTAssertTrue(hasToggle(), "a page with a search field is not offered Always Collapse Search")

        declare(HelmPageToolbarContent(tabs: tabs, selectedTab: .constant("one"), actions: [refresh]))
        XCTAssertEqual(headers(), [AppStr.pageBar, AppStr.tabLabels, AppStr.appearance])
        XCTAssertFalse(hasToggle(), "a page without a search field is offered Always Collapse Search")

        declare(HelmPageToolbarContent(actions: [refresh], search: search))
        XCTAssertEqual(headers(), [AppStr.pageBar, AppStr.appearance],
                       "a page without tabs is offered Tab labels")
        XCTAssertTrue(hasToggle(), "a search-only page is not offered Always Collapse Search")

        AppSettings.barAppearance = .liquidGlass
        XCTAssertEqual(appearanceItems(in: opened()).filter { $0.state == .on }.map { $0.representedObject as? String },
                       [HelmBarAppearance.liquidGlass.rawValue], "the menu opened on a stale tick")
    }

    // MARK: - General's row

    private func segments(in host: NSView) -> [NSSegmentedControl] {
        host.everyView(ofType: NSSegmentedControl.self)
    }

    func testTheGeneralRowFollowsAChoiceMadeInTheMenu() {
        let host = NSHostingView(rootView: BarAppearanceRow())
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 60)
        host.layoutSubtreeIfNeeded()
        pump()
        guard let control = segments(in: host).first else {
            return XCTFail("no segmented control in the hosted row: nothing was read")
        }
        XCTAssertEqual(control.selectedSegment, 0, "precondition: the row does not start on Flat")

        let hearing = Hearing()
        let section = appearanceItems(in: menuItems(.nameOnly))
        guard section.count == 2 else {
            return XCTFail("no Appearance item to press: nothing was written and nothing was refused")
        }
        XCTAssertTrue(press(section[1]), "Liquid Glass found nobody to answer it")
        pump()
        XCTAssertEqual(segments(in: host).first?.selectedSegment, 1,
                       "Liquid Glass chosen in the menu, and General's row still shows Flat")
        XCTAssertEqual(hearing.count, 1, "the row wrote the choice back: \(hearing.count) announcements, not one")

        XCTAssertTrue(press(appearanceItems(in: menuItems(.nameOnly))[0]), "Flat found nobody to answer it")
        pump()
        XCTAssertEqual(segments(in: host).first?.selectedSegment, 0,
                       "Flat chosen in the menu, and General's row still shows Liquid Glass")
        XCTAssertEqual(hearing.count, 2, "going back announced \(hearing.count - 1) more times, not one")
    }

    // MARK: - The words

    func testTheRowsTitleIsEachLanguagesOwn() {
        var read = 0
        AppLanguage.each { language in
            guard let path = Localized.stringsFile(for: language)?.path,
                  let file = NSDictionary(contentsOfFile: path) as? [String: String] else {
                return XCTFail("no Localizable.strings for \(language.rawValue)")
            }
            read += 1
            let own = file["Toolbar style"]
            if language == .en {
                XCTAssertEqual(AppStr.barAppearanceTitle, "Toolbar style")
                return
            }
            XCTAssertNotNil(own, "\(language.rawValue): «Toolbar style» is missing from its file")
            XCTAssertNotEqual(own, "Toolbar style", "\(language.rawValue): «Toolbar style» is English in its file")
            XCTAssertEqual(AppStr.barAppearanceTitle, own,
                           "\(language.rawValue): the row's title is not its file's entry")
        }
        XCTAssertEqual(read, AppLanguage.allCases.count, "not every language's file was read")
        AppLanguage.only(.ru) {
            XCTAssertEqual(AppStr.barAppearanceTitle, "Оформление панели инструментов", "ru: the title is not the owner's words")
        }
    }
}
