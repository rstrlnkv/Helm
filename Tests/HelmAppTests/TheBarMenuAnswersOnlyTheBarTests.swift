import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Which presses open the settings toolbar's own menu, and which must not.**
///
/// `SettingsToolbar.opensBarMenu(_:)` is the decision its one local monitor
/// asks before anything else (`watchBarPresses()`); the pop-up itself is modal
/// and is not raised here. Every press is built at a point read off what the
/// bar actually laid out — an item's own view, AppKit's own title view, a
/// window button's own frame — so a moved item moves the press with it rather
/// than leaving it on empty glass that happens to answer the same way.
///
/// The gesture is the right button, or the left one with Control held; a
/// plain click at the same point must never open it, and neither may a press
/// in the page, on the window's own buttons, in another window, or inside the
/// search field while somebody is typing in it — the field's own Cut, Copy
/// and Paste are what a person reaches for there.
@MainActor
final class TheBarMenuAnswersOnlyTheBarTests: XCTestCase {

    private static let sidebarWidth: CGFloat = 214
    private static let collapseKey = "alwaysCollapseSearch"

    /// Raw, so a key the domain did not hold is removed again rather than
    /// written back as the typed getter's default.
    private var savedPageBar: Any?
    private var savedCollapse: Any?

    override func setUp() async throws {
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedCollapse = AppSettings.store.object(Self.collapseKey)
        AppSettings.pageBarStyle = .moduleName
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedCollapse, for: Self.collapseKey)
    }

    // MARK: - Rig

    private func content() -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [
                HelmToolbarTab(id: "installed", title: L("Installed"), symbol: "shippingbox"),
                HelmToolbarTab(id: "updates", title: L("Updates"), symbol: "arrow.up.circle"),
                HelmToolbarTab(id: "health", title: L("Health"), symbol: "stethoscope")
            ],
            selectedTab: .constant("installed"),
            actions: [HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}],
            search: HelmToolbarSearch(prompt: L("Search packages"), text: .constant("")))
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let keepAlive: [AnyObject]
    }

    /// Key, not merely ordered back: the editing case needs a real field
    /// editor, which only a key window hands out.
    private func mount(pane: CGFloat) -> Rig {
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
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        toolbar.window = window
        model.selection = .module("test.barPress")
        channel.declare(content(), token: "test.barPress", generation: channel.nextGeneration())
        pump(window, turns: 30)
        return Rig(window: window, toolbar: toolbar, keepAlive: [model, channel])
    }

    private func close(_ rig: Rig) {
        rig.window.makeFirstResponder(nil)
        rig.window.toolbar = nil
        rig.window.close()
    }

    private func pump(_ window: NSWindow, turns: Int = 10) {
        for _ in 0..<turns {
            window.layoutIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private func item(_ window: NSWindow, _ id: String) -> NSToolbarItem? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == id }
    }

    private func searchItem(_ window: NSWindow) -> NSSearchToolbarItem? {
        window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first
    }

    private func centre(of view: NSView) -> NSPoint {
        view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }

    private enum Press: CaseIterable, CustomStringConvertible {
        case right, controlClick, plain
        var description: String {
            switch self {
            case .right: "right-click"
            case .controlClick: "Control-click"
            case .plain: "plain click"
            }
        }
        var type: NSEvent.EventType { self == .right ? .rightMouseDown : .leftMouseDown }
        var flags: NSEvent.ModifierFlags { self == .controlClick ? [.control] : [] }
    }

    private func event(_ press: Press, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: press.type, location: point, modifierFlags: press.flags, timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    /// The window's own title container, which AppKit draws in the bar
    /// instead of the name item under `.windowTitle` — found by class name,
    /// the way `SettingsToolbar.windowTitleMaxX` finds it.
    private func titleView(_ window: NSWindow) -> NSView? {
        window.contentView?.superview?.everyView(named: "NSToolbarTitleView").first
    }

    /// A point on the bar that no item covers: between the name (or the
    /// window's own title) and the tabs, at the tabs' own height.
    private func emptyBar(_ window: NSWindow, after leading: NSView) -> NSPoint? {
        guard let tabs = item(window, "helm.tabs")?.view else { return nil }
        let leadingEdge = leading.convert(leading.bounds, to: nil).maxX
        let tabsFrame = tabs.convert(tabs.bounds, to: nil)
        guard tabsFrame.minX - leadingEdge > 16 else { return nil }
        return NSPoint(x: (leadingEdge + tabsFrame.minX) / 2, y: tabsFrame.midY)
    }

    private func assertOpens(_ rig: Rig, _ place: String, at point: NSPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(rig.window.contentLayoutRect.contains(point),
                       "precondition: \(place) at \(point) is inside the page, not on the bar",
                       file: file, line: line)
        for press in [Press.right, .controlClick] {
            XCTAssertTrue(rig.toolbar.opensBarMenu(event(press, at: point, in: rig.window)),
                          "a \(press) on \(place) does not open the bar's menu", file: file, line: line)
        }
        XCTAssertFalse(rig.toolbar.opensBarMenu(event(.plain, at: point, in: rig.window)),
                       "a plain click on \(place) opens the bar's menu", file: file, line: line)
    }

    private func assertStaysShut(_ rig: Rig, _ place: String, at point: NSPoint,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for press in Press.allCases {
            XCTAssertFalse(rig.toolbar.opensBarMenu(event(press, at: point, in: rig.window)),
                           "a \(press) on \(place) opens the bar's menu", file: file, line: line)
        }
    }

    // MARK: - Everywhere on the bar

    /// **Every part of the bar under `.moduleName`**: the name, the glass
    /// between it and the tabs, the tabs, the capsule and the search field
    /// resting open — the gesture opens the menu on each, a plain click on
    /// none.
    func testTheGestureOpensTheMenuOnEveryPartOfTheBar() {
        let rig = mount(pane: 1060)
        defer { close(rig) }
        guard let name = item(rig.window, "helm.name")?.view,
              let tabs = item(rig.window, "helm.tabs")?.view,
              let actions = item(rig.window, "helm.actions")?.view,
              let field = searchItem(rig.window)?.searchField
        else { return XCTFail("the bar is missing an item — nothing below is pressed") }
        XCTAssertFalse(field.isHidden, "precondition: the field is not resting open at 1060 pt")
        assertOpens(rig, "the name", at: centre(of: name))
        guard let gap = emptyBar(rig.window, after: name) else {
            return XCTFail("no empty glass between the name and the tabs to press")
        }
        assertOpens(rig, "the empty bar", at: gap)
        assertOpens(rig, "the tabs", at: centre(of: tabs))
        assertOpens(rig, "the actions capsule", at: centre(of: actions))
        assertOpens(rig, "the resting search field", at: centre(of: field))
    }

    /// **Under `.windowTitle` the name item is gone and AppKit's own title
    /// sits there instead** — a monitor that only knew the items it built
    /// would lose the gesture on the very title that replaced them.
    func testTheGestureOpensTheMenuOnAppKitsOwnTitle() {
        AppSettings.pageBarStyle = .windowTitle
        let rig = mount(pane: 1060)
        defer { close(rig) }
        rig.window.title = "Homebrew"
        rig.window.titleVisibility = .visible
        pump(rig.window, turns: 20)
        XCTAssertNil(item(rig.window, "helm.name"), "precondition: the name item is still on a .windowTitle bar")
        guard let title = titleView(rig.window) else {
            return XCTFail("no NSToolbarTitleView on a .windowTitle bar — nothing to press")
        }
        assertOpens(rig, "AppKit's own title", at: centre(of: title))
        if let gap = emptyBar(rig.window, after: title) {
            assertOpens(rig, "the empty bar beside the title", at: gap)
        }
    }

    /// **The magnifier the search rests as**, with Always Collapse Search on:
    /// the gesture opens the menu, and a plain press is not the menu's —
    /// it is M1's, which opens the field, so the menu
    /// taking it would be the magnifier doing nothing.
    func testTheRestingMagnifierOpensTheMenuOnlyToTheGesture() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: 1060)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window), let superview = searchItem.searchField.superview else {
            return XCTFail("no search field on the bar")
        }
        XCTAssertTrue(searchItem.searchField.isHidden, "precondition: the search does not rest as its magnifier")
        let point = centre(of: superview)
        assertOpens(rig, "the resting magnifier", at: point)
        XCTAssertTrue(rig.toolbar.tookMagnifierPress(event(.plain, at: point, in: rig.window)),
                      "a plain press on the resting magnifier is no longer M1's")
    }

    /// **The tabs folded into their compact capsule**: a plain press there
    /// is the tabs' own menu, the gesture is the bar's. Mounted at 646 pt,
    /// not 1060 — a pane neither language has room for the full tabs beside
    /// an open field at (`AlwaysCollapseSearchRestsAsTheMagnifierTests
    /// .testTheFoldPredictionChargesTheMagnifierAtTheNarrowestPanes`'s own
    /// reading), so the magnifier press folding here is a real need and not
    /// M1's old, unconditional fold.
    func testTheCompactSwitcherGivesTheGestureToTheBar() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: 646)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window), let superview = searchItem.searchField.superview
        else { return XCTFail("no search field on the bar") }
        // The open field leaves the full tabs no room at this pane, so
        // `openingKeepsTheTabs(_:)` answers no and the press folds them —
        // see this method's own header for why 646, not 1060.
        XCTAssertTrue(rig.toolbar.tookMagnifierPress(event(.plain, at: centre(of: superview), in: rig.window)),
                      "precondition: M1 did not take the magnifier press")
        pump(rig.window, turns: 20)
        guard let tabs = item(rig.window, "helm.tabs")?.view,
              let control = tabs.everyView(ofType: NSSegmentedControl.self).first
        else { return XCTFail("no tabs to press") }
        XCTAssertEqual(control.segmentCount, 1, "precondition: the tabs did not fold")
        let point = centre(of: control)
        for press in [Press.right, .controlClick] {
            XCTAssertTrue(rig.toolbar.opensBarMenu(event(press, at: point, in: rig.window)),
                          "a \(press) on the compact tabs does not open the bar's menu")
        }
        XCTAssertFalse(rig.toolbar.opensBarMenu(event(.plain, at: point, in: rig.window)),
                       "a plain press on the compact tabs opens the bar's menu instead of the tabs'")
    }

    // MARK: - Where it must stay shut

    /// **The page, the window's own buttons, another window**: nothing opens,
    /// whatever the press.
    func testThePageTheWindowButtonsAndAnotherWindowStayShut() {
        let rig = mount(pane: 1060)
        defer { close(rig) }
        let page = rig.window.contentLayoutRect
        assertStaysShut(rig, "the page", at: NSPoint(x: page.midX, y: page.midY))
        assertStaysShut(rig, "the page's top edge", at: NSPoint(x: page.midX, y: page.maxY - 2))
        for (kind, name) in [(NSWindow.ButtonType.closeButton, "close button"),
                             (.miniaturizeButton, "minimise button"), (.zoomButton, "zoom button")] {
            guard let button = rig.window.standardWindowButton(kind) else {
                XCTFail("no \(name) on the window"); continue
            }
            XCTAssertFalse(page.contains(centre(of: button)), "precondition: the \(name) sits inside the page")
            assertStaysShut(rig, "the \(name)", at: centre(of: button))
        }

        guard let name = item(rig.window, "helm.name")?.view else { return XCTFail("no name item") }
        let other = NSWindow(contentRect: rig.window.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.orderBack(nil)
        defer { other.close() }
        for press in Press.allCases {
            let foreign = NSEvent.mouseEvent(with: press.type, location: centre(of: name),
                                             modifierFlags: press.flags, timestamp: 0,
                                             windowNumber: other.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1)!
            XCTAssertFalse(rig.toolbar.opensBarMenu(foreign),
                           "a \(press) in another window, at the name's point, opens this bar's menu")
        }
    }

    /// **Inside the field while it is being edited, the field's own text menu
    /// wins; anywhere else on the bar, the bar's menu still opens** — the
    /// exemption is the field, not the whole bar for as long as a search is
    /// open.
    func testTheFieldBeingEditedKeepsItsOwnMenuAndOnlyThere() {
        let rig = mount(pane: 1060)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window),
              let name = item(rig.window, "helm.name")?.view
        else { return XCTFail("the bar is missing an item") }
        searchItem.beginSearchInteraction()
        let deadline = Date().addingTimeInterval(2)
        while searchItem.searchField.currentEditor() == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(searchItem.searchField.currentEditor(), "precondition: no field editor arrived")
        pump(rig.window, turns: 10)
        let field = searchItem.searchField
        assertStaysShut(rig, "the field being edited", at: centre(of: field))
        let leadingText = field.convert(NSPoint(x: 30, y: field.bounds.midY), to: nil)
        assertStaysShut(rig, "the text end of the field being edited", at: leadingText)
        assertOpens(rig, "the name, while the field is being edited", at: centre(of: name))
    }
}
