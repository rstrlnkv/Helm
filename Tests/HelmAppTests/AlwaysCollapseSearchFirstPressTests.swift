import AppKit
import QuartzCore
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The first press on a resting magnifier, with "Always Collapse Search"
/// on, measured against what the opened bar actually leaves.** The owner's
/// report was about the first press in a window: «при нажатии на него тулбар
/// сворачивается в список». `settle(_:)` records a verdict at rest
/// (`PageBar.rest.openFits`) and M1/M2 read it back; this file checks that
/// verdict against the bar AppKit actually lays out once the field is open,
/// with no warm-up round in front of the press it asserts on.
@MainActor
final class AlwaysCollapseSearchFirstPressTests: XCTestCase {

    private static let sidebarWidth: CGFloat = 214
    private static let collapseKey = "alwaysCollapseSearch"
    private var savedPageBar: Any?
    private var savedSwitcher: Any?
    private var savedCollapse: Any?

    override func setUp() async throws {
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedSwitcher = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        savedCollapse = AppSettings.store.object(Self.collapseKey)
        AppSettings.pageBarStyle = .moduleName
        AppSettings.toolbarSwitcherStyle = .text
        AppSettings.alwaysCollapseSearch = true
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedSwitcher, for: ToolbarSwitcherStyle.storageKey)
        AppSettings.store.set(savedCollapse, for: Self.collapseKey)
    }

    // MARK: - Rig

    private final class Query {
        var text = ""
        var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
        /// The selected tab, part of the key a settle pass measures the
        /// tabs under — a change here, posted to nobody, is news to the next
        /// pass and moves nothing else.
        var selected = "installed"
        var selection: Binding<String> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
    }

    /// Homebrew's own shape; `actions: false` drops the actions item, which
    /// leaves `currentToolbarSlack(_:)` nothing to anchor its trailing gap on.
    private func content(_ query: Query, actions: Bool = true) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [
                HelmToolbarTab(id: "installed", title: L("Installed"), symbol: "shippingbox"),
                HelmToolbarTab(id: "updates", title: L("Updates"), symbol: "arrow.up.circle"),
                HelmToolbarTab(id: "health", title: L("Health"), symbol: "stethoscope")
            ],
            selectedTab: query.selection,
            actions: actions ? [
                HelmToolbarAction(id: "upgradeAll", title: L("Upgrade all"), symbol: "arrow.down.to.line",
                                  isEnabled: false, isVisible: false) {},
                HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}
            ] : [],
            search: HelmToolbarSearch(prompt: L("Search packages"), text: query.binding))
    }

    /// Uninstaller's own shape: two tabs, one action, a search.
    private func uninstallerContent(_ query: Query) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [
                HelmToolbarTab(id: "apps", title: L("Apps"), symbol: "square.grid.2x2"),
                HelmToolbarTab(id: "orphans", title: L("Leftovers"), symbol: "doc.badge.ellipsis")
            ],
            selectedTab: .constant("apps"),
            actions: [
                HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}
            ],
            search: HelmToolbarSearch(prompt: L("Search apps"), text: query.binding))
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let query: Query
        let split: NSSplitViewController
    }

    /// The window's title is drawn before the bar attaches, the order
    /// `SettingsWindow` itself gives it (its title sink runs at init, before
    /// any page's bar exists) — so `settle(_:)`'s first pass under
    /// `.windowTitle` already has a title to anchor on.
    private func mount(pane: CGFloat, token: String = "test.firstpress", actions: Bool = true,
                       title: (String, String)? = nil, uninstaller: Bool = false,
                       appearance: NSAppearance? = nil, transparentTitlebar: Bool = true) -> Rig {
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
        window.titlebarAppearsTransparent = transparentTitlebar
        if AppSettings.pageBarStyle == .windowTitle {
            window.title = title?.0 ?? "Homebrew"
            window.subtitle = title?.1 ?? "3"
            window.titleVisibility = .visible
        } else {
            window.titleVisibility = .hidden
        }
        window.isReleasedWhenClosed = false
        if let appearance { window.appearance = appearance }
        window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        split.splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
        window.layoutIfNeeded()
        resize(window, detail: detail, to: pane)
        toolbar.window = window
        let rig = Rig(window: window, toolbar: toolbar, model: model, channel: channel, query: Query(),
                      split: split)
        rig.model.selection = .module(token)
        rig.channel.declare(uninstaller ? uninstallerContent(rig.query) : content(rig.query, actions: actions),
                            token: token,
                            generation: rig.channel.nextGeneration())
        settle(window, turns: 30)
        return rig
    }

    private func resize(_ window: NSWindow, detail: NSViewController, to pane: CGFloat) {
        let got = detail.view.bounds.width
        if abs(got - pane) > 0.5 {
            window.setContentSize(NSSize(width: window.frame.width + (pane - got), height: 700))
            window.layoutIfNeeded()
        }
    }

    private func resize(_ rig: Rig, to pane: CGFloat) {
        guard let detail = rig.split.splitViewItems.last?.viewController else { return }
        resize(rig.window, detail: detail, to: pane)
    }

    private func close(_ rig: Rig) {
        rig.window.makeFirstResponder(nil)
        rig.window.toolbar = nil
        rig.window.close()
    }

    private func settle(_ window: NSWindow, turns: Int = 20) {
        for _ in 0..<turns {
            window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private func settleUntil(_ window: NSWindow, turns: Int = 150, _ condition: () -> Bool) {
        for _ in 0..<turns {
            if condition() { return }
            settle(window, turns: 1)
        }
    }

    private func searchItem(_ window: NSWindow) -> NSSearchToolbarItem? {
        window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first
    }

    private func item(_ window: NSWindow, _ id: String) -> NSToolbarItem? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == id }
    }

    private func segmentCount(_ window: NSWindow) -> Int? {
        item(window, "helm.tabs")?.view?.everyView(ofType: NSSegmentedControl.self).first?.segmentCount
    }

    private func waitForEditor(_ searchItem: NSSearchToolbarItem, present: Bool = true) -> Bool {
        let end = Date().addingTimeInterval(2)
        while (searchItem.searchField.currentEditor() != nil) != present, Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return (searchItem.searchField.currentEditor() != nil) == present
    }

    private func magnifierPress(_ rig: Rig, _ searchItem: NSSearchToolbarItem) -> Bool {
        guard let superview = searchItem.searchField.superview else { return false }
        let point = superview.convert(NSPoint(x: superview.bounds.midX, y: superview.bounds.midY), to: nil)
        return press(rig, at: point)
    }

    private func press(_ rig: Rig, at point: NSPoint) -> Bool {
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                             timestamp: 0, windowNumber: rig.window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return false }
        return rig.toolbar.tookMagnifierPress(event)
    }

    private func describe(_ rig: Rig) -> String {
        guard let field = searchItem(rig.window)?.searchField else { return "no field" }
        return "field hidden=\(field.isHidden) width=\(field.frame.width) "
            + "editing=\(field.currentEditor() != nil) text=«\(field.stringValue)» "
            + "tabs=\(segmentCount(rig.window).map(String.init) ?? "none")"
    }

    @MainActor
    private final class EvictionWatch {
        private(set) var evicted: Set<String> = []
        private var tokens: [NSKeyValueObservation] = []
        init(_ toolbar: NSToolbar?) {
            for item in toolbar?.items ?? [] {
                let name = item.itemIdentifier.rawValue
                guard ["helm.name", "helm.tabs", "helm.actions"].contains(name) else { continue }
                tokens.append(item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                    guard change.newValue == false else { return }
                    MainActor.assumeIsolated { _ = self?.evicted.insert(name) }
                })
            }
        }
    }

    // MARK: - Geometry, read the way `currentToolbarSlack(_:)` reads it

    /// The leading edge the slack is measured from: the name item's
    /// trailing edge, or the drawn title's fitting edge under `.windowTitle`.
    private func leadingMaxX(_ window: NSWindow) -> CGFloat? {
        if let nameView = item(window, "helm.name")?.view, !(item(window, "helm.name")?.isHidden ?? true) {
            return nameView.convert(NSPoint(x: nameView.bounds.width, y: 0), to: nil).x
        }
        guard let frame = window.contentView?.superview,
              let title = frame.everyView(named: "NSToolbarTitleView").first
        else { return nil }
        return title.convert(.zero, to: nil).x + title.fittingSize.width
    }

    /// The two flexible gaps around the tabs, as laid out right now; nil
    /// when an anchor is missing or evicted.
    private func liveSlack(_ window: NSWindow) -> CGFloat? {
        guard let tabs = item(window, "helm.tabs"), tabs.isVisible, let tabsView = tabs.view,
              let actions = item(window, "helm.actions"), actions.isVisible, let actionsView = actions.view,
              let lead = leadingMaxX(window)
        else { return nil }
        let tabsMinX = tabsView.convert(.zero, to: nil).x
        let tabsMaxX = tabsView.convert(NSPoint(x: tabsView.bounds.width, y: 0), to: nil).x
        let actionsMinX = actionsView.convert(.zero, to: nil).x
        return (tabsMinX - lead) + (actionsMinX - tabsMaxX)
    }

    /// The search item's footprint in the bar: from the actions item's
    /// trailing edge to the search item's own outermost view's trailing
    /// edge — whatever AppKit puts between them is what the open field
    /// actually adds.
    private func searchFootprint(_ window: NSWindow) -> (minX: CGFloat, maxX: CGFloat)? {
        guard let field = searchItem(window)?.searchField else { return nil }
        var view: NSView = field
        var outer: NSView = field
        while let parent = view.superview {
            if "\(type(of: parent))".contains("ToolbarItemViewer") { outer = parent; break }
            view = parent
            outer = parent
            if "\(type(of: parent))".contains("NSToolbarView") { break }
        }
        let minX = outer.convert(.zero, to: nil).x
        return (minX, minX + outer.bounds.width)
    }

    private func chain(_ window: NSWindow) -> String {
        guard let field = searchItem(window)?.searchField else { return "-" }
        var parts: [String] = ["field=\(field.frame.width)\(field.isHidden ? "h" : "")"]
        var view: NSView = field
        var depth = 0
        while let parent = view.superview, depth < 5 {
            parts.append("\(type(of: parent))=\(parent.frame.width)")
            view = parent; depth += 1
        }
        return parts.joined(separator: " > ")
    }

    /// The title container under `.windowTitle`: its laid-out width and its
    /// fitting width, "-" under `.moduleName`.
    private func titleReading(_ window: NSWindow) -> String {
        guard AppSettings.pageBarStyle == .windowTitle, let frame = window.contentView?.superview,
              let title = frame.everyView(named: "NSToolbarTitleView").first
        else { return "-" }
        return String(format: "minX=%.1f w=%.1f fit=%.1f", title.convert(.zero, to: nil).x,
                      title.bounds.width, title.fittingSize.width)
    }

    // MARK: - The measurement (a report: its numbers are this Mac's)

    /// **Predicted open slack against the slack the opened bar leaves.**
    /// One fresh mount per pane, no warm-up, the first press only. Printed
    /// as one line per pane; the assertion is the invariant the owner's
    /// report needs at every pane: a press that kept the tabs full evicted
    /// nothing.
    func testThePredictedOpenSlackAgainstTheOpenedBar() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] != nil,
                          "a sweep of this Mac's own toolbar geometry — HELM_BENCH=1 to run")
        let panes: [CGFloat] = (ProcessInfo.processInfo.environment["HELM_PANES"] ?? "")
            .split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        let sweep = panes.isEmpty ? [646, 700, 746, 800, 860, 960, 1060] : panes
        let env = ProcessInfo.processInfo.environment
        let styles: [PageBarStyle] = env["HELM_STYLE"] == "windowTitle"
            ? [.windowTitle] : env["HELM_STYLE"] == "moduleName" ? [.moduleName] : [.moduleName, .windowTitle]
        let languages: [AppLanguage] = env["HELM_LANG"] == "en" ? [.en] : env["HELM_LANG"] == "ru" ? [.ru] : [.en, .ru]
        var broken: [String] = []
        for style in styles {
            AppSettings.pageBarStyle = style
            for language in languages {
                AppLanguage.only(language) {
                    for pane in sweep {
                        let rig = mount(pane: pane)
                        defer { close(rig) }
                        guard let searchItem = searchItem(rig.window) else { broken.append("\(pane) no item"); return }
                        let full = searchItem.preferredWidthForSearchField
                        // The bar's own first settle pass: armed by `show()`
                        // `settleInterval` after the bar attached — a person's
                        // first press comes later than that, so wait for it by
                        // the clock, not by a count of turns.
                        let mounted = Date()
                        settleUntil(rig.window) {
                            rig.toolbar.lastOpenSlack != nil && Date().timeIntervalSince(mounted) > 0.4
                        }
                        let restLive = liveSlack(rig.window)
                        let predicted = rig.toolbar.lastOpenSlack
                        let restFoot = searchFootprint(rig.window)
                        let restChain = chain(rig.window)
                        let restTabs = segmentCount(rig.window)
                        let restTitle = titleReading(rig.window)
                        let watch = EvictionWatch(rig.window.toolbar)
                        let took = magnifierPress(rig, searchItem)
                        let tabsRightAfter = segmentCount(rig.window)
                        _ = waitForEditor(searchItem)
                        settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
                        settle(rig.window, turns: 15)
                        let openTabs = segmentCount(rig.window)
                        let openLive = liveSlack(rig.window)
                        let openTitle = titleReading(rig.window)
                        let openFoot = searchFootprint(rig.window)
                        let growth = (openFoot.map { $0.maxX - $0.minX } ?? .nan)
                            - (restFoot.map { $0.maxX - $0.minX } ?? .nan)
                        let derived = (restLive ?? .nan) - growth
                        func f(_ value: CGFloat?) -> String { value.map { String(format: "%.1f", $0) } ?? "nil" }
                        let line = """
                            SWEEP \(style) \(language) pane=\(pane) restTabs=\(f(restTabs.map(CGFloat.init))) \
                            predictedOpenSlack=\(f(predicted)) restLiveSlack=\(f(restLive)) \
                            took=\(took) tabsAfterPress=\(f(tabsRightAfter.map(CGFloat.init))) \
                            openTabs=\(f(openTabs.map(CGFloat.init))) openLiveSlack=\(f(openLive)) \
                            searchGrowth=\(f(growth)) derivedOpenSlack=\(f(derived)) \
                            evicted=\(watch.evicted.sorted()) preferred=\(f(full)) \
                            restTitle=[\(restTitle)] openTitle=[\(openTitle)] restChain=[\(restChain)]
                            """
                        print(line)
                        if tabsRightAfter == 3, !watch.evicted.isEmpty {
                            broken.append("\(style) \(language) \(pane): kept full, then \(watch.evicted.sorted()) evicted")
                        }
                        searchItem.endSearchInteraction()
                        settleUntil(rig.window, turns: 200) {
                            searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                        }
                    }
                }
            }
        }
        XCTAssertTrue(broken.isEmpty, "a first press kept the tabs full and AppKit evicted: \(broken)")
    }

    // MARK: - Gates

    /// **Closed while the field is still growing, with the tabs kept full**
    /// — four press-and-close rounds back to back, each press the moment the
    /// last close has put the magnifier back, the way
    /// `AlwaysCollapseSearchRestsAsTheMagnifierTests
    /// .testClosingEmptyBringsBackTheMagnifierAndTheFullTabsEveryTime` runs
    /// them. A reopen from the tail of a collapse grows back over several
    /// frames, so the close can land mid-growth. Every failing close measured
    /// before `searchFieldFrameChanged`'s `closing` guard existed had the same shape: the field one frame wider after
    /// `endSearchInteraction()` than at it (218.5 → 222.0, 212.0 → 217.0,
    /// 220.5 → 224.0), then stopped visible, idle and empty (183.0 pt at
    /// en 760, 182.5 at ru 860, 282.5 at ru 1060, 325.0 at en 1060 — the
    /// last is the width the option-off bar rests at there), and the next
    /// press was not M1's: engineer's intermittent "closed empty, the search
    /// did not return to its magnifier". Red in 2 of 7 alone runs before
    /// that guard existed; the same sequence never failed with both fold
    /// sites put back to unconditional (0 of 96 closes).
    func testACloseThatLandsWhileTheFieldIsStillGrowingComesBackToItsMagnifier() {
        for (language, pane): (AppLanguage, CGFloat) in [(.en, 760), (.en, 1060), (.ru, 860), (.ru, 1060)] {
            AppLanguage.only(language) {
                let rig = mount(pane: pane)
                defer { close(rig) }
                rest(rig)
                guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
                for round in 0..<4 {
                    let label = "\(language) \(pane) round \(round)"
                    XCTAssertTrue(magnifierPress(rig, searchItem), "\(label): M1 did not take the press (\(describe(rig)))")
                    _ = waitForEditor(searchItem)
                    settle(rig.window, turns: 30)
                    var trace: [String] = []
                    var last = ""
                    searchItem.endSearchInteraction()
                    for _ in 0..<250 {
                        let field = searchItem.searchField
                        let now = "\(field.frame.width)\(field.isHidden ? "h" : "")"
                        if now != last { trace.append(now); last = now }
                        if field.isHidden && segmentCount(rig.window) == 3 { break }
                        settle(rig.window, turns: 1)
                    }
                    XCTAssertTrue(searchItem.searchField.isHidden, """
                        \(label): closed empty, the search did not come back to its magnifier — field width \
                        from the close on: \(trace.joined(separator: " → ")) (\(describe(rig)))
                        """)
                    guard searchItem.searchField.isHidden else { break }
                }
            }
        }
    }

    /// **The same close, with the late growth frame driven rather than hoped
    /// for.** `endSearchInteraction()` ends the edit in the same turn, and the
    /// frame one step wider than the field at that moment is delivered before
    /// the run loop turns — the frame the collapse animation delivered one run
    /// in several (218.5 → 222.0). Taken as a new opening, it re-arms
    /// `searchOpening` with no editor behind it, the turn-later rest predicate
    /// then releases the cap, and the field stays open, idle and empty for
    /// good. Every run, not one in seven.
    func testAGrowthFrameAfterAnEmptyCloseIsNotANewOpening() {
        for (language, pane): (AppLanguage, CGFloat) in [(.en, 1060), (.ru, 1060)] {
            AppLanguage.only(language) {
                let label = "\(language) \(pane)"
                let rig = mount(pane: pane)
                defer { close(rig) }
                rest(rig)
                guard let searchItem = searchItem(rig.window) else { return XCTFail("\(label): no search item") }
                let field = searchItem.searchField
                let full = searchItem.preferredWidthForSearchField
                XCTAssertTrue(magnifierPress(rig, searchItem), "\(label): M1 did not take the press")
                XCTAssertEqual(segmentCount(rig.window), 3, "\(label): precondition, the press folded the tabs")
                XCTAssertTrue(waitForEditor(searchItem), "\(label): no field editor arrived")
                settleUntil(rig.window) { field.frame.width >= full - 1 }
                settle(rig.window, turns: 10)
                searchItem.endSearchInteraction()
                XCTAssertNil(field.currentEditor(), """
                    \(label): precondition, the edit did not end in the same turn — the driven frame below would \
                    land while the opening is still marked and prove nothing
                    """)
                field.setFrameSize(NSSize(width: field.frame.width + 3.5, height: field.frame.height))
                settleUntil(rig.window, turns: 250) { field.isHidden && segmentCount(rig.window) == 3 }
                XCTAssertTrue(field.isHidden, """
                    \(label): a growth frame after an empty close was taken as a new opening — the search did not \
                    come back to its magnifier (\(describe(rig)))
                    """)
            }
        }
    }

    /// **The same frame after a close that leaves a query behind.** The
    /// query releases the cap and the field stays open — correct; but a
    /// growth frame landing between the end of the edit and the turn-later
    /// rest predicate must not be taken as a new opening here either: M2
    /// reads `PageBar.searchEditEndedDeadline`, which every end of an edit
    /// arms, not the empty-only `searchClosingDeadline`. Taken as one, it
    /// would leave `searchOpening` set with no editor, so every `settle(_:)`
    /// would return at its `searchOpening` guard — narrowed until the tabs
    /// fold and widened
    /// back, they never unfold — and the query cleared without focus (the
    /// field's own clear button) leaves the field open and empty with the
    /// option on. Control first: the same steps without the driven frame.
    func testAGrowthFrameAfterACloseWithAQueryIsNotANewOpening() {
        AppLanguage.only(.en) {
            for driven in [false, true] {
                let label = driven ? "en 1060, growth frame after the close" : "en 1060, control"
                let rig = mount(pane: 1060)
                defer { close(rig) }
                rest(rig)
                guard let searchItem = searchItem(rig.window) else { return XCTFail("\(label): no search item") }
                let field = searchItem.searchField
                let full = searchItem.preferredWidthForSearchField
                XCTAssertTrue(magnifierPress(rig, searchItem), "\(label): M1 did not take the press")
                XCTAssertEqual(segmentCount(rig.window), 3, "\(label): precondition, the press folded the tabs")
                XCTAssertTrue(waitForEditor(searchItem), "\(label): no field editor arrived")
                settleUntil(rig.window) { field.frame.width >= full - 1 }
                (field.currentEditor() as? NSTextView)?.insertText("wget", replacementRange: NSRange(location: 0, length: 0))
                XCTAssertEqual(field.stringValue, "wget", "\(label): precondition, the query did not reach the field")
                rig.window.makeFirstResponder(nil)
                XCTAssertNil(field.currentEditor(), "\(label): precondition, the edit did not end in the same turn")
                if driven {
                    field.setFrameSize(NSSize(width: field.frame.width + 3.5, height: field.frame.height))
                }
                rest(rig)
                resize(rig, to: 420)
                rest(rig)
                settleUntil(rig.window, turns: 250) { segmentCount(rig.window) == 1 }
                XCTAssertEqual(segmentCount(rig.window), 1, "\(label): precondition, at 420 the tabs did not fold")
                resize(rig, to: 1060)
                rest(rig, seconds: 1)
                settleUntil(rig.window, turns: 250) { segmentCount(rig.window) == 3 }
                XCTAssertEqual(segmentCount(rig.window), 3, """
                    \(label): narrowed until the tabs folded and widened back, the tabs never unfolded \
                    (\(describe(rig)))
                    """)
                field.stringValue = ""
                _ = field.sendAction(field.action, to: field.target)
                settleUntil(rig.window, turns: 250) { field.isHidden && segmentCount(rig.window) == 3 }
                XCTAssertTrue(field.isHidden, """
                    \(label): the query cleared with no editor, the search did not come back to its magnifier \
                    (\(describe(rig)))
                    """)
            }
        }
    }

    /// **A sweep of the first press, one fresh window per pane — a report.**
    /// `HELM_STYLE` (moduleName|windowTitle), `HELM_LANG`, `HELM_WAY`
    /// (press|interaction), `HELM_PANES` ("from:to:step" or a list),
    /// `HELM_TITLE`/`HELM_SUB` (the drawn title and subtitle, default the
    /// rig's), `HELM_SHAPE` (homebrew|uninstaller), `HELM_APPEARANCE`
    /// (light|dark). One line per pane; fails when a pane kept the full tabs
    /// and AppKit evicted anything with the field open.
    func testTheFirstPressBoundarySweep() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["HELM_BENCH"] != nil, "a sweep of this Mac's own toolbar geometry — HELM_BENCH=1 to run")
        let style: PageBarStyle = env["HELM_STYLE"] == "moduleName" ? .moduleName : .windowTitle
        AppSettings.pageBarStyle = style
        if env["HELM_COLLAPSE"] == "off" { AppSettings.alwaysCollapseSearch = false }
        let language = AppLanguage(rawValue: env["HELM_LANG"] ?? "en") ?? .en
        let way = env["HELM_WAY"] ?? "press"
        let uninstaller = env["HELM_SHAPE"] == "uninstaller"
        let fullCount = uninstaller ? 2 : 3
        var panes: [CGFloat] = []
        let spec = env["HELM_PANES"] ?? "640:1100:20"
        let range = spec.split(separator: ":").compactMap { Double($0) }
        if range.count == 3 {
            var pane = range[0]
            while pane <= range[1] + 0.001 { panes.append(CGFloat(pane)); pane += range[2] }
        } else {
            panes = spec.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
        }
        let appearance = env["HELM_APPEARANCE"].flatMap { NSAppearance(named: $0 == "dark" ? .darkAqua : .aqua) }
        var broken: [String] = []
        var firstKept: String?
        AppLanguage.only(language) {
            let title: (String, String)? = env["HELM_TITLE"].map { raw in
                let text = raw == "module" ? (uninstaller ? L("Uninstaller") : L("Homebrew")) : raw
                let sub = env["HELM_SUB"].map { $0 == "active" ? L("Active") : $0 == "idle" ? L("Not running") : $0 } ?? ""
                return (text, sub)
            }
            for pane in panes {
                let rig = mount(pane: pane, title: title, uninstaller: uninstaller, appearance: appearance,
                                transparentTitlebar: env["HELM_OPAQUE"] == nil)
                defer { close(rig) }
                rest(rig)
                guard let searchItem = searchItem(rig.window) else { broken.append("\(pane): no search item"); continue }
                let field = searchItem.searchField
                let full = searchItem.preferredWidthForSearchField
                let restTabs = segmentCount(rig.window)
                let restTitle = titleReading(rig.window)
                let predicted = rig.toolbar.lastOpenSlack
                let watch = EvictionWatch(rig.window.toolbar)
                var atPress: Int?
                if way == "press" {
                    _ = magnifierPress(rig, searchItem)
                    atPress = segmentCount(rig.window)
                } else {
                    searchItem.beginSearchInteraction()
                }
                _ = waitForEditor(searchItem)
                settleUntil(rig.window) { field.frame.width >= full - 1 }
                settle(rig.window, turns: 15)
                let openTabs = segmentCount(rig.window)
                let openTitle = titleReading(rig.window)
                let shown = ["helm.tabs", "helm.actions"].allSatisfy { item(rig.window, $0)?.isVisible ?? true }
                let evictedOpen = watch.evicted.sorted()
                searchItem.endSearchInteraction()
                settleUntil(rig.window, turns: 250) { field.isHidden && segmentCount(rig.window) == fullCount }
                let back = field.isHidden && segmentCount(rig.window) == fullCount
                func f(_ value: CGFloat?) -> String { value.map { String(format: "%.1f", $0) } ?? "nil" }
                let kept = (way == "press" ? atPress : openTabs) == fullCount
                print("""
                    BOUNDARY \(style) \(language) \(way) \(uninstaller ? "uninstaller" : "homebrew") \
                    pane=\(pane) restTabs=\(restTabs.map(String.init) ?? "nil") predicted=\(f(predicted)) \
                    verdict=\(kept ? "KEPT" : "FOLDED") atPress=\(atPress.map(String.init) ?? "-") \
                    openTabs=\(openTabs.map(String.init) ?? "nil") shown=\(shown) evictedOpen=\(evictedOpen) \
                    evictedCycle=\(watch.evicted.sorted()) back=\(back) restTitle=[\(restTitle)] openTitle=[\(openTitle)] \
                    appearance=\(rig.window.effectiveAppearance.name.rawValue) \
                    transparent=\(rig.window.titlebarAppearsTransparent)
                    """)
                if kept, firstKept == nil { firstKept = "\(pane) predicted=\(f(predicted))" }
                if kept, !evictedOpen.isEmpty || !shown {
                    broken.append("\(pane): kept the full tabs and AppKit evicted \(evictedOpen)")
                }
                if !back { broken.append("\(pane): closed empty, did not come back (\(describe(rig)))") }
            }
        }
        print("BOUNDARY-SUMMARY \(style) \(language) \(way) first kept pane: \(firstKept ?? "none")")
        XCTAssertTrue(broken.isEmpty, "\(broken)")
    }
    /// **Across the band where the title container meets its floor, a press
    /// that keeps the full tabs evicts nothing** — `.windowTitle`, one fresh
    /// window per pane, the first press. Read on this Mac: with the field
    /// open and the tabs full, AppKit shrinks `NSToolbarTitleView` one point
    /// per point of pane down to 160–161 pt whatever the title says (en 714,
    /// ru 814), and one step narrower evicts the actions item; the rest
    /// verdict keeps the tabs from en 720 and ru 822. The panes below run
    /// from inside that band to past the verdict's edge, so a floor charged
    /// short by more than a point or two keeps the tabs where AppKit evicts
    /// — which ru 746 and en 700, far below the band, cannot see. Asserts the invariant, never where the edge is — and
    /// that a kept press happened at all in each language, at a pane (en 740,
    /// ru 840) wide enough to keep on any reading near this one, so the
    /// absence asserted below has a subject.
    func testAcrossTheTitleFloorBandAKeptPressEvictsNothing() {
        AppSettings.pageBarStyle = .windowTitle
        for (language, panes): (AppLanguage, [CGFloat]) in [(.en, [704, 708, 712, 713, 716, 720, 740]),
                                                            (.ru, [804, 808, 812, 813, 816, 822, 840])] {
            AppLanguage.only(language) {
                var kept = 0
                defer { XCTAssertGreaterThan(kept, 0, "\(language): no pane in the band kept the tabs — nothing was checked") }
                for pane in panes {
                    let label = "\(language) \(pane) .windowTitle, the first press"
                    let rig = mount(pane: pane)
                    defer { close(rig) }
                    rest(rig)
                    guard let searchItem = searchItem(rig.window) else { return XCTFail("\(label): no search item") }
                    let full = searchItem.preferredWidthForSearchField
                    let watch = EvictionWatch(rig.window.toolbar)
                    XCTAssertTrue(magnifierPress(rig, searchItem), "\(label): M1 did not take the press")
                    let atPress = segmentCount(rig.window)
                    XCTAssertTrue(waitForEditor(searchItem), "\(label): no field editor arrived")
                    settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
                    settle(rig.window, turns: 15)
                    if atPress == 3 {
                        kept += 1
                        XCTAssertEqual(watch.evicted.sorted(), [], """
                            \(label): the press kept the full tabs and AppKit evicted \(watch.evicted.sorted()) — \
                            the title container's floor was charged short (\(titleReading(rig.window)))
                            """)
                    }
                    searchItem.endSearchInteraction()
                    settleUntil(rig.window, turns: 250) {
                        searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                    }
                }
            }
        }
    }

    /// Lets the bar sit still the way a window does before anybody reaches
    /// for it: `show()` arms `settle(_:)` `settleInterval` after the bar
    /// attaches, and a count of run-loop turns is not a time — measured, the
    /// thirty turns in `mount(pane:)` returned in 0.13 s on some mounts,
    /// before that first pass had run at all.
    private func rest(_ rig: Rig, seconds: TimeInterval = 0.5) {
        let until = Date().addingTimeInterval(seconds)
        settleUntil(rig.window, turns: 400) { Date() >= until }
    }

    private struct Round {
        let tabsAtPress: Int?
        let tabsOpen: Int?
        let evicted: [String]
        let allShownWhileOpen: Bool
    }

    /// One magnifier press, the field opened to its full width, then closed
    /// empty — what the tabs were the instant M1 returned, what they were
    /// with the field open, and whatever AppKit evicted along the way.
    private func pressAndClose(_ rig: Rig, _ searchItem: NSSearchToolbarItem, _ label: String) -> Round {
        let full = searchItem.preferredWidthForSearchField
        let watch = EvictionWatch(rig.window.toolbar)
        XCTAssertTrue(magnifierPress(rig, searchItem), "\(label): M1 did not take the press (\(describe(rig)))")
        let tabsAtPress = segmentCount(rig.window)
        XCTAssertTrue(waitForEditor(searchItem), "\(label): no field editor arrived (\(describe(rig)))")
        settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
        settle(rig.window, turns: 15)
        let tabsOpen = segmentCount(rig.window)
        let shown = ["helm.tabs", "helm.actions"].allSatisfy { item(rig.window, $0)?.isVisible ?? true }
        searchItem.endSearchInteraction()
        settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
        XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
            \(label): closed empty, the magnifier and the full tabs did not return (\(describe(rig)))
            """)
        return Round(tabsAtPress: tabsAtPress, tabsOpen: tabsOpen, evicted: watch.evicted.sorted(),
                     allShownWhileOpen: shown)
    }

    /// **The boundary invariant, in the owner's own shape** — `.windowTitle`,
    /// the text switcher, a fresh window, the first press and two more.
    /// Either verdict is allowed at these panes; an eviction is not, and the
    /// first press is the one the owner's report is about. ru 746 and en 700
    /// sat inside the band where the rest verdict over-credited a
    /// `.windowTitle` bar before `PageBar.titleOpenFloorCharge` existed: it
    /// predicted 17.5 pt (ru 746) and 73 pt (en 700) of open slack there,
    /// kept the tabs, and AppKit evicted the actions item on the first press
    /// at both; with the charge both fold at the press.
    func testTheFirstPressInTheOwnersShapeEvictsNothing() {
        AppSettings.pageBarStyle = .windowTitle
        for (language, pane): (AppLanguage, CGFloat) in [(.ru, 746), (.en, 700)] {
            AppLanguage.only(language) {
                let rig = mount(pane: pane)
                defer { close(rig) }
                rest(rig)
                guard let searchItem = searchItem(rig.window) else { return XCTFail("\(language) \(pane): no search item") }
                XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                    \(language) \(pane): precondition, not resting beside the full tabs (\(describe(rig)))
                    """)
                for round in 0..<3 {
                    let label = "\(language) \(pane) .windowTitle round \(round)\(round == 0 ? " (the first press)" : "")"
                    let result = pressAndClose(rig, searchItem, label)
                    XCTAssertEqual(result.evicted, [], """
                        \(label): the press left the tabs at \(result.tabsAtPress.map(String.init) ?? "none") \
                        segment(s) and AppKit evicted \(result.evicted) with the field open — a kept opening the \
                        bar had no room for
                        """)
                    if result.tabsOpen == 3 {
                        XCTAssertTrue(result.allShownWhileOpen, "\(label): full tabs kept, but not every item is shown")
                    }
                }
            }
        }
    }

    /// **Where the open field leaves the full tabs no room, the press folds
    /// them, and nothing is evicted** — both ways in, twice each: the
    /// magnifier press (M1) folds before the field grows, so the tabs read
    /// compact the instant it returns; `beginSearchInteraction()` (M2) folds
    /// on the first growth frame. `.moduleName`, the panes where the fold is
    /// a real need in both languages.
    func testTheNarrowPanesFoldAtThePressAndEvictNothing() {
        for (language, pane): (AppLanguage, CGFloat) in [(.en, 646), (.ru, 646), (.ru, 700)] {
            AppLanguage.only(language) {
                for wayIn in ["press", "interaction"] {
                    let rig = mount(pane: pane)
                    defer { close(rig) }
                    rest(rig)
                    guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
                    let full = searchItem.preferredWidthForSearchField
                    XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                        \(language) \(pane) \(wayIn): precondition, not resting beside the full tabs (\(describe(rig)))
                        """)
                    for round in 0..<2 {
                        let label = "\(language) \(pane) \(wayIn) round \(round)"
                        let watch = EvictionWatch(rig.window.toolbar)
                        if wayIn == "press" {
                            XCTAssertTrue(magnifierPress(rig, searchItem), "\(label): M1 did not take the press")
                            XCTAssertEqual(segmentCount(rig.window), 1, """
                                \(label): M1 returned without folding the tabs, at a pane the open field leaves \
                                them no room (\(describe(rig)))
                                """)
                        } else {
                            searchItem.beginSearchInteraction()
                        }
                        XCTAssertTrue(waitForEditor(searchItem), "\(label): no field editor arrived (\(describe(rig)))")
                        settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
                        settle(rig.window, turns: 15)
                        XCTAssertEqual(segmentCount(rig.window), 1, "\(label): open, the tabs are not folded (\(describe(rig)))")
                        searchItem.endSearchInteraction()
                        settleUntil(rig.window, turns: 250) {
                            searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                        }
                        XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                            \(label): closed empty, the magnifier and the full tabs did not return (\(describe(rig)))
                            """)
                        XCTAssertEqual(watch.evicted.sorted(), [], "\(label): AppKit evicted across the cycle")
                        rest(rig)
                    }
                }
            }
        }
    }

    /// **Narrowed while a kept search is open, then pressed again at the same
    /// room.** At 1060 the press keeps the tabs; the window narrows under the
    /// open field to 746, where AppKit refuses the full tabs
    /// beside it and `checkOverflow()` folds them. Closed, widened and
    /// narrowed back to the same pane, the next press folds at the press and
    /// AppKit evicts nothing. ru `.windowTitle`. Nothing remembers the
    /// refusal any more: the rest verdict itself folds at 746 now that the
    /// title container's floor is charged, so this is the owner's-shape
    /// check again, reached through a refusal rather than a fresh window.
    func testAPressAtTheRoomAKeptSearchWasRefusedAtFolds() {
        AppSettings.pageBarStyle = .windowTitle
        AppLanguage.only(.ru) {
            let rig = mount(pane: 1060)
            defer { close(rig) }
            rest(rig)
            guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
            let full = searchItem.preferredWidthForSearchField
            XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press at 1060")
            XCTAssertEqual(segmentCount(rig.window), 3, "precondition: the press at 1060 folded the tabs")
            XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived (\(describe(rig)))")
            settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
            let narrowing = EvictionWatch(rig.window.toolbar)
            resize(rig, to: 746)
            settleUntil(rig.window, turns: 100) { segmentCount(rig.window) == 1 }
            settle(rig.window, turns: 10)
            XCTAssertNotNil(searchItem.searchField.currentEditor(), "precondition: the narrowing ended the edit")
            XCTAssertEqual(segmentCount(rig.window), 1, "narrowed to 746 under the open field, the tabs did not fold")
            XCTAssertFalse(narrowing.evicted.isEmpty, """
                precondition: narrowing to 746 under the open field evicted nothing, so nothing was refused here \
                and the second press below proves nothing
                """)
            searchItem.endSearchInteraction()
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden }
            resize(rig, to: 1060)
            rest(rig)
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
            resize(rig, to: 746)
            rest(rig)
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
            XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                precondition: back at 746 the bar is not resting beside the full tabs (\(describe(rig)))
                """)
            let second = pressAndClose(rig, searchItem, "ru 746 .windowTitle, the press after the refusal")
            XCTAssertEqual(second.tabsAtPress, 1, "the press at the room a kept opening was refused at did not fold")
            XCTAssertEqual(second.evicted, [], "AppKit evicted \(second.evicted) again at the room it had refused")
        }
    }

    /// **A press that lands between a resize and the settle that follows it**
    /// — the rest verdict belongs to the old room, so the press folds (the
    /// safe direction) rather than reading 1060's "fits" at 646, and nothing
    /// is evicted; the empty close brings the full tabs back.
    func testAPressRightAfterAResizeFolds() {
        AppLanguage.only(.en) {
            let rig = mount(pane: 1060)
            defer { close(rig) }
            rest(rig)
            guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
            let watch = EvictionWatch(rig.window.toolbar)
            resize(rig, to: 646)
            XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                precondition: resized to 646, the bar is not resting beside the full tabs (\(describe(rig)))
                """)
            let round = pressAndClose(rig, searchItem, "en 1060→646, pressed before the settle")
            XCTAssertEqual(round.tabsAtPress, 1, """
                pressed right after a resize, M1 kept the tabs on the old room's verdict
                """)
            XCTAssertEqual(watch.evicted.sorted(), [], "pressed right after a resize, AppKit evicted")
        }
    }

    /// **The keyboard's way in (M2) right after a resize, before the settle
    /// that follows it** — the same unknown `testAPressRightAfterAResizeFolds`
    /// covers for the mouse: the rest verdict belongs to the old room, so the
    /// safe answer is to fold. `beginSearchInteraction()` is what the
    /// keyboard and VoiceOver call; at 646 the open field leaves the full
    /// tabs no room in Russian.
    func testTheKeyboardsWayInRightAfterAResizeFolds() {
        AppLanguage.only(.ru) {
            let rig = mount(pane: 1060)
            defer { close(rig) }
            rest(rig)
            guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
            let full = searchItem.preferredWidthForSearchField
            let watch = EvictionWatch(rig.window.toolbar)
            resize(rig, to: 646)
            XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                precondition: resized to 646, the bar is not resting beside the full tabs (\(describe(rig)))
                """)
            searchItem.beginSearchInteraction()
            XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived (\(describe(rig)))")
            settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
            settle(rig.window, turns: 15)
            XCTAssertEqual(segmentCount(rig.window), 1, "open at 646, the tabs are not folded (\(describe(rig)))")
            XCTAssertEqual(watch.evicted.sorted(), [], """
                opened by the keyboard right after a resize, AppKit evicted — M2 did not fold ahead of the \
                field's growth
                """)
            searchItem.endSearchInteraction()
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
        }
    }

    /// **A fold the window forced, then undone by widening — then the
    /// press.** Under `.windowTitle`, the `settle(_:)` pass that unfolds the
    /// tabs is also the pass that records `rest.openFits`, and by that
    /// method's own order it computes the verdict before the unfold, with the
    /// tabs still folded — so that pass's verdict charges `PageBar.titleGrowth`
    /// against the open slack, which is why `settle(_:)` discards it there
    /// and arms another pass.
    /// At panes where the open field fits beside the full tabs (read off the
    /// option's own first press on a fresh mount, never assumed), a narrowing
    /// and a widening in between must not turn the press into a fold.
    /// Measured with the re-arm `settle(_:)` now makes after such an unfold
    /// taken out (one run, this Mac): red at ru 824, 836, 846, 860, 880 and
    /// 900 and at en 736 and 760, green at ru 940 and 1000 and at en 800 and
    /// 860; on a 2-pt grid a fresh mount's first press keeps the tabs from
    /// ru 822 and en 720. Every pane here sits at least 14 pt inside both
    /// ends of that band, so a couple of points of somebody else's geometry
    /// can neither fail the control nor carry the pane out of what the
    /// re-arm protects — ru 824, two points above the lower end, moved to 846.
    func testAPressAfterTheWindowWasNarrowedAndWidenedKeepsTheTabsWhereTheyFit() {
        AppSettings.pageBarStyle = .windowTitle
        for (language, pane): (AppLanguage, CGFloat) in [(.ru, 836), (.ru, 846), (.ru, 860), (.en, 736)] {
            AppLanguage.only(language) {
                let label = "\(language) \(pane) .windowTitle"
                let control = mount(pane: pane)
                rest(control)
                guard let controlItem = searchItem(control.window) else { close(control); return XCTFail("no search item") }
                let fresh = pressAndClose(control, controlItem, "\(label) control")
                close(control)
                guard fresh.tabsAtPress == 3, fresh.evicted.isEmpty else {
                    return XCTFail("\(label): precondition, a fresh mount's first press does not keep the tabs here")
                }
                let rig = mount(pane: pane)
                defer { close(rig) }
                rest(rig)
                guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
                // A kept cycle first: the settle after its close must run
                // again, or the narrowing below folds through M3 alone and
                // the widening never unfolds.
                let kept = pressAndClose(rig, searchItem, "\(label) before the narrowing")
                XCTAssertEqual(kept.tabsAtPress, 3, "\(label): precondition, the first press here folded")
                rest(rig)
                resize(rig, to: 420)
                rest(rig)
                settleUntil(rig.window, turns: 250) { segmentCount(rig.window) == 1 }
                XCTAssertEqual(segmentCount(rig.window), 1, "\(label): precondition, at 420 the tabs did not fold")
                resize(rig, to: pane)
                rest(rig, seconds: 1)
                settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
                XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                    \(label): precondition, widened back the bar is not resting beside the full tabs (\(describe(rig)))
                    """)
                let round = pressAndClose(rig, searchItem, "\(label) after 420 and back")
                XCTAssertEqual(round.tabsAtPress, 3, """
                    \(label): after the window was narrowed until the tabs folded and widened back, the press \
                    folded the tabs where a fresh window's press keeps them
                    """)
                XCTAssertEqual(round.evicted, [], "\(label): AppKit evicted after the narrowing and widening")
            }
        }
    }

    /// **With the option off, an unfold under a grown title arms no settle
    /// of its own.** `settle(_:)` calls a verdict computed with the tabs
    /// still folded stale when the `.windowTitle` container had grown into
    /// the fold's room, and re-arms itself to read the bar again — for the
    /// rest verdict M1 and M2 consult, which only the option's cap reads.
    /// With the cap inactive that re-arm is a pass nobody asked for. The
    /// pass is counted, not inferred: the selected tab is part of the tabs
    /// measurement's key and only a settle pass measures, so a selection
    /// changed behind the toolbar's back after the unfold is measured again
    /// exactly when a pass runs (`SettingsToolbar.measurementsTaken`), and a
    /// resize after that is the control that proves a pass would have been
    /// counted. en
    /// 1060 is the pane where the unfold leaves the field's frame where it
    /// was (325 pt on both sides, measured) — anywhere the unfold moves the field, M2
    /// re-arms a pass of its own at the same moment and the two cannot be
    /// told apart, so that is a precondition here rather than an
    /// assumption. The settle interval is stretched to 0.3 s so the change
    /// lands well inside the gap before a re-armed pass could fire.
    func testWithTheOptionOffAnUnfoldUnderAGrownTitleArmsNoFurtherSettle() {
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.alwaysCollapseSearch = false
        let savedInterval = SettingsToolbar.settleInterval
        defer { SettingsToolbar.settleInterval = savedInterval }
        AppLanguage.only(.en) {
            let label = "en 1060 .windowTitle, option off"
            let rig = mount(pane: 1060)
            defer { close(rig) }
            rest(rig, seconds: 1)
            guard let field = searchItem(rig.window)?.searchField else { return XCTFail("\(label): no search item") }
            let titleView = { rig.window.contentView?.superview?.everyView(named: "NSToolbarTitleView").first }
            XCTAssertTrue(!field.isHidden && segmentCount(rig.window) == 3, """
                \(label): precondition, not resting open beside the full tabs (\(describe(rig)))
                """)
            guard let resting = titleView()?.bounds.width else { return XCTFail("\(label): no title container") }
            resize(rig, to: 420)
            rest(rig)
            settleUntil(rig.window, turns: 250) { segmentCount(rig.window) == 1 }
            rest(rig)
            XCTAssertEqual(segmentCount(rig.window), 1, "\(label): precondition, at 420 the tabs did not fold")
            SettingsToolbar.settleInterval = 0.3
            let unfolds = rig.toolbar.gateUnfoldFieldWidths.count
            resize(rig, to: 1060)
            var grown: CGFloat = 0
            var fieldBefore = field.frame
            let deadline = Date().addingTimeInterval(3)
            while rig.toolbar.gateUnfoldFieldWidths.count == unfolds, Date() < deadline {
                grown = titleView()?.bounds.width ?? 0
                fieldBefore = field.frame
                settle(rig.window, turns: 1)
            }
            XCTAssertEqual(rig.toolbar.gateUnfoldFieldWidths.count, unfolds + 1, """
                \(label): precondition, widened back the settle did not unfold the tabs (\(describe(rig)))
                """)
            XCTAssertGreaterThan(grown, resting + 1, """
                \(label): precondition, the title container had not grown into the fold's room by the unfold \
                (\(grown) against \(resting) at rest) — the re-arm this checks is keyed on that growth
                """)
            XCTAssertEqual(field.frame, fieldBefore, """
                \(label): precondition, the unfold moved the field, so M2 re-arms a settle of its own and a \
                re-armed pass cannot be told from it
                """)
            rig.query.selected = "updates"
            let beforeQuiet = SettingsToolbar.measurementsTaken
            rest(rig, seconds: 4 * SettingsToolbar.settleInterval)
            XCTAssertEqual(SettingsToolbar.measurementsTaken - beforeQuiet, 0, """
                \(label): the unfold under a grown title armed another settle pass with the option off
                """)
            rig.query.selected = "health"
            let beforeControl = SettingsToolbar.measurementsTaken
            resize(rig, to: 1062)
            rest(rig, seconds: 4 * SettingsToolbar.settleInterval)
            XCTAssertEqual(SettingsToolbar.measurementsTaken - beforeControl, 1, """
                \(label): control, a resize's settle after a selection change was not counted — the count \
                above cannot see a pass
                """)
        }
    }

    /// **A reproduction, not a gate: a second way to the same signature.** The
    /// test tool's defaults domain (`com.apple.dt.xctest.tool`) is one per
    /// machine, and every case here and in
    /// `AlwaysCollapseSearchRestsAsTheMagnifierTests` writes
    /// `module.app.alwaysCollapseSearch` in its `setUp`; a write from another
    /// run posts no notification in this process, and `restSearch(_:)` reads
    /// the value fresh at the end of the edit — so a concurrent run leaves the
    /// field open at the option-off width, as the close that lands mid-growth
    /// does (`testACloseThatLandsWhileTheFieldIsStillGrowingComesBackToItsMagnifier`).
    /// Measured: 325.0 pt at en 1060 both ways.
    func testAnOutsideWriteOfTheOptionLeavesTheFieldOpen() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] != nil,
                          "reproduces a flake signature, not a gate — HELM_BENCH=1 to run")
        AppLanguage.only(.en) {
            AppSettings.alwaysCollapseSearch = false
            let control = mount(pane: 1060)
            rest(control)
            print("OUTSIDE control, option off at rest: " + describe(control))
            close(control)
            AppSettings.alwaysCollapseSearch = true
            let rig = mount(pane: 1060)
            defer { close(rig) }
            rest(rig)
            guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
            let full = searchItem.preferredWidthForSearchField
            XCTAssertTrue(magnifierPress(rig, searchItem))
            _ = waitForEditor(searchItem)
            settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
            UserDefaults.standard.set(false, forKey: "module.app.alwaysCollapseSearch")
            searchItem.endSearchInteraction()
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
            print("OUTSIDE after an outside write mid-edit, closed empty: " + describe(rig))
            let rested = searchItem.searchField.isHidden
            UserDefaults.standard.set(true, forKey: "module.app.alwaysCollapseSearch")
            XCTAssertFalse(rested, """
                an outside write of the option mid-edit no longer leaves the field open — the flake signature \
                this reproduces has another cause now
                """)
        }
    }

    /// **A click outside a search the press kept beside the full tabs** —
    /// M1's second branch ends the edit and returns false, the field goes
    /// back to its magnifier, and the full tabs never moved.
    func testAClickOutsideAKeptSearchClosesItBesideTheFullTabs() {
        AppLanguage.only(.en) {
            let rig = mount(pane: 1060)
            defer { close(rig) }
            rest(rig)
            guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
            let full = searchItem.preferredWidthForSearchField
            let watch = EvictionWatch(rig.window.toolbar)
            XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press")
            XCTAssertEqual(segmentCount(rig.window), 3, "precondition: the press at 1060 folded the tabs")
            XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived")
            settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
            let content = rig.window.contentLayoutRect
            XCTAssertFalse(press(rig, at: NSPoint(x: content.maxX - 60, y: content.midY)),
                           "a press in the page was taken as M1's")
            XCTAssertTrue(waitForEditor(searchItem, present: false), "a press outside did not end the edit")
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
            XCTAssertTrue(searchItem.searchField.isHidden, "after a press outside, the search is not the magnifier (\(describe(rig)))")
            XCTAssertEqual(segmentCount(rig.window), 3, "after a press outside, the tabs are not full (\(describe(rig)))")
            XCTAssertEqual(watch.evicted.sorted(), [], "AppKit evicted across the open and the outside press")
        }
    }

    /// **Nothing to anchor the prediction on folds** — a bar with tabs and a
    /// search but no actions item leaves `currentToolbarSlack(_:)` nil, and
    /// an unanchored reading must never be taken as room, so the press folds
    /// even at 1060.
    func testAnUnanchoredBarFoldsAtThePress() {
        AppLanguage.only(.en) {
            let rig = mount(pane: 1060, actions: false)
            defer { close(rig) }
            rest(rig)
            guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
            XCTAssertNil(item(rig.window, "helm.actions"), "precondition: the bar has an actions item")
            XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                precondition: not resting beside the full tabs (\(describe(rig)))
                """)
            XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press")
            XCTAssertEqual(segmentCount(rig.window), 1, "an unanchored bar kept the tabs full at the press")
            _ = waitForEditor(searchItem)
            searchItem.endSearchInteraction()
            settleUntil(rig.window, turns: 250) { searchItem.searchField.isHidden }
        }
    }

    /// **A page left while a kept search was open, then come back to** — the
    /// bar must not stay believing a search is opening: narrowed until the
    /// tabs fold and widened again, they come back full. Before the fix the
    /// press itself folded here and `AlwaysCollapseSearchRestsAsTheMagnifierTests
    /// .testAPageLeftMidSearchComesBackResting` read the unfold; with the
    /// tabs kept full that case no longer needs `settle(_:)` to run at all.
    func testAPageLeftWhileAKeptSearchWasOpenUnfoldsAgainLater() {
        AppLanguage.only(.ru) {
            let rig = mount(pane: 1060, token: "test.firstpress")
            defer { close(rig) }
            rest(rig)
            guard let first = searchItem(rig.window) else { return XCTFail("no search item") }
            XCTAssertTrue(magnifierPress(rig, first), "M1 did not take the press")
            XCTAssertEqual(segmentCount(rig.window), 3, "precondition: the press at 1060 folded the tabs")
            XCTAssertTrue(waitForEditor(first), "no field editor arrived")
            settle(rig.window, turns: 20)
            rig.model.selection = .module("test.firstpress.second")
            rig.channel.declare(content(rig.query), token: "test.firstpress.second",
                                generation: rig.channel.nextGeneration())
            rest(rig)
            rig.model.selection = .module("test.firstpress")
            rig.channel.declare(content(rig.query), token: "test.firstpress", generation: rig.channel.nextGeneration())
            rest(rig)
            XCTAssertTrue(searchItem(rig.window) === first, "precondition: the first page's bar was rebuilt, not cached")
            resize(rig, to: 540)
            settleUntil(rig.window, turns: 250) { segmentCount(rig.window) == 1 }
            XCTAssertEqual(segmentCount(rig.window), 1, "precondition: at 540 the ru tabs did not fold (\(describe(rig)))")
            resize(rig, to: 1060)
            rest(rig, seconds: 1)
            settleUntil(rig.window, turns: 250) { first.searchField.isHidden && segmentCount(rig.window) == 3 }
            XCTAssertEqual(segmentCount(rig.window), 3, """
                back on a page left while a kept search was open, narrowed and widened again, the tabs never \
                unfolded — the bar still believes a search is opening (\(describe(rig)))
                """)
            XCTAssertTrue(first.searchField.isHidden, "the search does not rest as the magnifier (\(describe(rig)))")
        }
    }
}
