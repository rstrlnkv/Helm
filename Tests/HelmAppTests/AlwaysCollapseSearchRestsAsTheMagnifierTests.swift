import AppKit
import QuartzCore
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **"Always Collapse Search" (`AppSettings.alwaysCollapseSearch`) on the
/// real bar**: at every width the empty, idle search rests as AppKit's own
/// magnifier; the magnifier press (M1) and AppKit's own
/// `beginSearchInteraction()` — the keyboard's and VoiceOver's way in — both
/// open it to its full width; closing it empty brings the magnifier and the
/// full tabs back; a query left in it keeps it open; and the setting reaches
/// bars that are not on screen when it moves.
///
/// The rest case mounts the same bar with the setting off first, at the same
/// pane, so "the field is hidden" is never read at a pane where AppKit would
/// have hidden it anyway — a rest check that passes with the setting doing
/// nothing is not a check. The panes are the ones
/// `AnUnfoldIsPredictedNeverTrialledTests` swept for Homebrew's three tabs:
/// above 710 pt (English) and 810 pt (Russian) AppKit opens an idle field on
/// its own, so `snug` and `wide` sit above both; the fold prediction's own
/// case sits below them, at 646 and 700 pt, the only panes where charging the
/// open field instead of the magnifier changes what the tabs do.
@MainActor
final class AlwaysCollapseSearchRestsAsTheMagnifierTests: XCTestCase {

    private static let sidebarWidth: CGFloat = 214
    private static let collapseKey = "alwaysCollapseSearch"
    /// Wider than both languages' open-at-rest threshold, and the owner's
    /// own full-width reading.
    private static let wide: [AppLanguage: CGFloat] = [.en: 1060, .ru: 1060]
    /// Just above each language's open-at-rest threshold: the narrowest
    /// room where the setting still decides what the field does.
    private static let snug: [AppLanguage: CGFloat] = [.en: 760, .ru: 860]

    /// Each setting as the test tool's own defaults domain held it, raw —
    /// absent stays absent. Read through the typed getters, an absent key
    /// came back as the default and was written back as a value, so every
    /// run from a clean domain left `pageBarStyle` and `toolbarSwitcherStyle`
    /// behind in it (read 2026-09-28).
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

    /// The text a page's search binding holds — a box, so a test can move it
    /// the way a page does and redeclare. `writes` counts what the bar wrote
    /// through the binding; a test moving `text` itself is not counted.
    private final class Query {
        var text = ""
        var writes = 0
        var binding: Binding<String> {
            Binding(get: { self.text }, set: { self.text = $0; self.writes += 1 })
        }
    }

    /// `prompt` nil is Homebrew's own words, which the host's table does not
    /// carry and so read the same in every language; a case about a
    /// language change passes words that do change.
    private func content(_ query: Query, prompt: String? = nil) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [
                HelmToolbarTab(id: "installed", title: L("Installed"), symbol: "shippingbox"),
                HelmToolbarTab(id: "updates", title: L("Updates"), symbol: "arrow.up.circle"),
                HelmToolbarTab(id: "health", title: L("Health"), symbol: "stethoscope")
            ],
            selectedTab: .constant("installed"),
            actions: [
                HelmToolbarAction(id: "upgradeAll", title: L("Upgrade all"), symbol: "arrow.down.to.line",
                                  isEnabled: false, isVisible: false) {},
                HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}
            ],
            search: HelmToolbarSearch(prompt: prompt ?? L("Search packages"), text: query.binding))
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let query: Query
    }

    private func mount(pane: CGFloat, token: String = "test.collapse.first") -> Rig {
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
        // The window's title is drawn before the bar attaches, the order
        // `SettingsWindow` itself gives it (its title sink runs at init,
        // before any page's bar exists) — so `settle(_:)`'s first pass under
        // `.windowTitle` already has a title to anchor on, and
        // `testOwnersShapeKeepsTheFullTabsUnderWindowTitle` needs no warm-up
        // round in front of the press it asserts on.
        if AppSettings.pageBarStyle == .windowTitle {
            window.title = "Homebrew"
            window.subtitle = "3"
            window.titleVisibility = .visible
        } else {
            window.titleVisibility = .hidden
        }
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
        // Key: the field editor, and so every open and close below, needs it.
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        split.splitView.setPosition(Self.sidebarWidth, ofDividerAt: 0)
        window.layoutIfNeeded()
        let got = detail.view.bounds.width
        if abs(got - pane) > 0.5 {
            window.setContentSize(NSSize(width: window.frame.width + (pane - got), height: 700))
            window.layoutIfNeeded()
        }
        toolbar.window = window
        let rig = Rig(window: window, toolbar: toolbar, model: model, channel: channel, query: Query())
        select(token, on: rig)
        settle(window, turns: 30)
        return rig
    }

    private func select(_ token: String, on rig: Rig) {
        rig.model.selection = .module(token)
        declare(token, on: rig)
    }

    private func declare(_ token: String, on rig: Rig) {
        rig.channel.declare(content(rig.query), token: token, generation: rig.channel.nextGeneration())
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

    /// Lets the bar sit still the way a window does before anybody reaches
    /// for it: `show()` arms `settle(_:)` `settleInterval` after the bar
    /// attaches, and a count of run-loop turns is not a time — measured, a
    /// fixed twenty-turn warm-up this file used to open every "risk 6" round
    /// with returned in well under 0.1 s on some mounts, before that first
    /// pass had run at all (`AlwaysCollapseSearchFirstPressTests`'s own
    /// `rest(_:)`, the same shape).
    private func rest(_ rig: Rig, seconds: TimeInterval = 0.5) {
        let until = Date().addingTimeInterval(seconds)
        settleUntil(rig.window, turns: 400) { Date() >= until }
    }

    private func searchItem(_ window: NSWindow) -> NSSearchToolbarItem? {
        window.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem }.first
    }

    private func segmentCount(_ window: NSWindow) -> Int? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.tabs" }?
            .view?.everyView(ofType: NSSegmentedControl.self).first?.segmentCount
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
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                             timestamp: 0, windowNumber: rig.window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return false }
        return rig.toolbar.tookMagnifierPress(event)
    }

    /// The field's state in one line, for a failure message.
    private func describe(_ rig: Rig) -> String {
        guard let field = searchItem(rig.window)?.searchField else { return "no field" }
        return "field hidden=\(field.isHidden) width=\(field.frame.width) "
            + "editing=\(field.currentEditor() != nil) text=«\(field.stringValue)» "
            + "tabs=\(segmentCount(rig.window).map(String.init) ?? "none")"
    }

    /// Watches `isVisible` on the named items — AppKit's own eviction signal.
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

    // MARK: - At rest

    /// **At every width the empty, idle search rests as the magnifier, beside
    /// the full tabs** — at a pane where the same bar with the setting off
    /// rests the field open, so the setting is what hid it.
    func testTheSearchRestsAsItsMagnifierWhereAppKitWouldHaveOpenedIt() {
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                for pane in [Self.snug[language]!, Self.wide[language]!] {
                    AppSettings.alwaysCollapseSearch = false
                    let control = mount(pane: pane)
                    let openAtRest = searchItem(control.window)?.searchField.isHidden == false
                    XCTAssertTrue(openAtRest, """
                        \(language) \(pane) pt, setting off: precondition — AppKit does not rest the \
                        field open here, so a hidden field below would prove nothing (\(describe(control)))
                        """)
                    close(control)

                    AppSettings.alwaysCollapseSearch = true
                    let rig = mount(pane: pane)
                    XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, """
                        \(language) \(pane) pt, setting on: the idle search does not rest as its \
                        magnifier (\(describe(rig)))
                        """)
                    XCTAssertEqual(segmentCount(rig.window), 3, """
                        \(language) \(pane) pt, setting on: the tabs do not rest full beside the \
                        magnifier (\(describe(rig)))
                        """)
                    close(rig)
                }
            }
        }
    }

    // MARK: - Opening

    /// **The magnifier press (M1) and AppKit's own `beginSearchInteraction()`
    /// both open the field to its full, focused width** — the setting must
    /// not leave a search nobody can see, whichever way it was opened.
    func testBothWaysInOpenTheFieldToItsFullWidth() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let full = searchItem.preferredWidthForSearchField
        XCTAssertTrue(searchItem.searchField.isHidden, "precondition: not resting as the magnifier (\(describe(rig)))")

        XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press on the resting magnifier")
        XCTAssertTrue(waitForEditor(searchItem), "M1's opening brought no field editor (\(describe(rig)))")
        settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
        XCTAssertFalse(searchItem.searchField.isHidden, "opened by M1, the field is still hidden")
        XCTAssertGreaterThanOrEqual(searchItem.searchField.frame.width, full - 1, """
            opened by M1 the field is \(searchItem.searchField.frame.width) pt, not its focused \
            \(full) pt — a search held down by the rest cap (\(describe(rig)))
            """)
        searchItem.endSearchInteraction()
        settleUntil(rig.window) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
        XCTAssertTrue(searchItem.searchField.isHidden, "precondition for the second way in: \(describe(rig))")

        searchItem.beginSearchInteraction()
        XCTAssertTrue(waitForEditor(searchItem), "beginSearchInteraction brought no editor (\(describe(rig)))")
        settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
        XCTAssertFalse(searchItem.searchField.isHidden, "opened by beginSearchInteraction, the field is hidden")
        XCTAssertGreaterThanOrEqual(searchItem.searchField.frame.width, full - 1, """
            opened by beginSearchInteraction the field is \(searchItem.searchField.frame.width) pt, not \
            its focused \(full) pt (\(describe(rig)))
            """)
    }

    // MARK: - Closing empty, and the fold prediction (risk 6)

    /// **Three press-and-close-empty rounds, at the snug pane and the wide
    /// one**: each ends with the magnifier back, the tabs full, and nothing
    /// ever evicted along the way — at these panes the press itself keeps the
    /// tabs full (below), so there is nothing here for a close to unfold;
    /// which of the magnifier's or the field's own width the fold prediction
    /// charges is `testTheFoldPredictionChargesTheMagnifierAtTheNarrowestPanes`'s
    /// own subject, at the narrower panes where the two disagree.
    func testClosingEmptyBringsBackTheMagnifierAndTheFullTabsEveryTime() {
        AppSettings.alwaysCollapseSearch = true
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                for pane in [Self.snug[language]!, Self.wide[language]!] {
                    let rig = mount(pane: pane)
                    // `settle(_:)`'s own first pass on a freshly attached bar
                    // can still find `currentToolbarSlack(_:)` unanchored —
                    // AppKit inserts a toolbar's items one at a time
                    // (`checkOverflow()`'s own "Not yet laid out" comment) —
                    // so `bar.rest.openFits` is not yet trustworthy the
                    // instant `mount(pane:)` returns. `rest(_:)` waits by the
                    // clock rather than a fixed turn count — `mount(pane:)`'s
                    // own thirty turns is not a time, and returned before
                    // that first pass had run at all on some mounts
                    // (measured: round 0 alone read `segmentCount == 1`
                    // without this wait, at en 1060, ru 860 and ru 1060, with
                    // every later round already correct).
                    rest(rig)
                    guard let searchItem = searchItem(rig.window) else {
                        XCTFail("\(language) \(pane): no search item"); close(rig); return
                    }
                    XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3,
                                  "\(language) \(pane): precondition, not at rest (\(describe(rig)))")
                    for round in 0..<3 {
                        let watch = EvictionWatch(rig.window.toolbar)
                        XCTAssertTrue(magnifierPress(rig, searchItem),
                                      "\(language) \(pane) round \(round): M1 did not take the press")
                        _ = waitForEditor(searchItem)
                        settle(rig.window, turns: 30)
                        // Both `snug` and `wide` are panes where the option-off
                        // control already rests the field open beside full tabs
                        // (`testOpeningTheSearchKeepsTheFullTabsWhereTheyAlreadyFit`'s
                        // own `fitsAtRest` precondition) — the open field fits here, so
                        // keeping the tabs full is the correct verdict, the
                        // same one the option-off path already gives.
                        XCTAssertEqual(segmentCount(rig.window), 3, """
                            \(language) \(pane) round \(round): opening the search folded the tabs \
                            where the open field still fits (\(describe(rig)))
                            """)
                        searchItem.endSearchInteraction()
                        settleUntil(rig.window, turns: 200) {
                            searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                        }
                        XCTAssertTrue(searchItem.searchField.isHidden, """
                            \(language) \(pane) round \(round): closed empty, the search did not \
                            return to its magnifier (\(describe(rig)))
                            """)
                        XCTAssertEqual(segmentCount(rig.window), 3, """
                            \(language) \(pane) round \(round): closed empty, the tabs did not \
                            unfold (\(describe(rig)))
                            """)
                        XCTAssertTrue(watch.evicted.isEmpty, """
                            \(language) \(pane) round \(round): \(watch.evicted.sorted()) evicted \
                            during the cycle
                            """)
                    }
                    close(rig)
                }
            }
        }
    }

    /// **The fold prediction charges the magnifier, not the field it
    /// opens into, at the narrowest panes** — the owner's 646 pt and 700 pt,
    /// where the full tabs fit beside a magnifier and not beside a 240 pt
    /// field. A prediction that budgeted the open field there would fold the
    /// tabs at rest, and after every empty close would never unfold them.
    /// (At the wider panes above, the full tabs fit beside the open field
    /// too, so no reading there can tell the two budgets apart — a mutant
    /// charging the open width passed every case above.)
    func testTheFoldPredictionChargesTheMagnifierAtTheNarrowestPanes() {
        AppSettings.alwaysCollapseSearch = true
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                for pane: CGFloat in [646, 700] {
                    let rig = mount(pane: pane)
                    guard let searchItem = searchItem(rig.window) else {
                        XCTFail("\(language) \(pane): no search item"); close(rig); return
                    }
                    XCTAssertTrue(searchItem.searchField.isHidden, """
                        \(language) \(pane) pt: the idle search does not rest as its magnifier (\(describe(rig)))
                        """)
                    XCTAssertEqual(segmentCount(rig.window), 3, """
                        \(language) \(pane) pt: the tabs do not rest full beside the magnifier — the \
                        prediction charged more than the magnifier (\(describe(rig)))
                        """)
                    let watch = EvictionWatch(rig.window.toolbar)
                    XCTAssertTrue(magnifierPress(rig, searchItem), "\(language) \(pane): M1 did not take the press")
                    _ = waitForEditor(searchItem)
                    settle(rig.window, turns: 30)
                    searchItem.endSearchInteraction()
                    settleUntil(rig.window, turns: 250) {
                        searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                    }
                    XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                        \(language) \(pane) pt: one press and an empty close did not return to the \
                        magnifier beside the full tabs (\(describe(rig)))
                        """)
                    XCTAssertTrue(watch.evicted.isEmpty, """
                        \(language) \(pane) pt: \(watch.evicted.sorted()) evicted during the cycle
                        """)
                    close(rig)
                }
            }
        }
    }

    // MARK: - The bug: a fold must be predicted, not assumed from "collapsed"

    /// **The owner's report, made a test.** «Один баг есть, не зависимо от
    /// ширины окна, если выбрана опция сворачивать поиск, то при нажатии на
    /// него тулбар сворачивается в список» — with the option on, opening a
    /// search the rest cap alone is holding collapsed must fold the tabs
    /// only where the opened field actually leaves them no room, the same
    /// rule the option off already gives. Both ways in: the mouse (M1,
    /// `magnifierPress`) and `beginSearchInteraction()` (M2, the keyboard's
    /// and VoiceOver's own way), at the same panes and languages
    /// `testTheSearchRestsAsItsMagnifierWhereAppKitWouldHaveOpenedIt` already
    /// reads as "the field rests open with the option off" — so a "fits"
    /// verdict here is read off that control, never assumed. Before the fix,
    /// M1 and M2 each folded here unconditionally: this failed on both ways
    /// in, at every one of these panes.
    func testOpeningTheSearchKeepsTheFullTabsWhereTheyAlreadyFit() {
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                for pane in [Self.snug[language]!, Self.wide[language]!] {
                    AppSettings.alwaysCollapseSearch = false
                    let control = mount(pane: pane)
                    let fitsAtRest = searchItem(control.window)?.searchField.isHidden == false
                        && segmentCount(control.window) == 3
                    close(control)
                    guard fitsAtRest else {
                        XCTFail("""
                            \(language) \(pane) pt: precondition — the option-off control does not \
                            rest with an open field beside full tabs, so this pane cannot tell a \
                            correct fold from an unneeded one
                            """)
                        continue
                    }

                    for wayIn in ["press", "interaction"] {
                        AppSettings.alwaysCollapseSearch = true
                        let rig = mount(pane: pane)
                        // See `testClosingEmptyBringsBackTheMagnifierAndTheFullTabsEveryTime`'s
                        // own comment: a freshly attached bar's first settle
                        // pass can still be unanchored, and `rest(_:)` waits
                        // for it by the clock rather than a turn count.
                        rest(rig)
                        guard let searchItem = searchItem(rig.window) else {
                            XCTFail("\(language) \(pane) \(wayIn): no search item"); close(rig); continue
                        }
                        let full = searchItem.preferredWidthForSearchField
                        XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                            \(language) \(pane) \(wayIn): precondition, not at rest (\(describe(rig)))
                            """)
                        let watch = EvictionWatch(rig.window.toolbar)
                        if wayIn == "press" {
                            XCTAssertTrue(magnifierPress(rig, searchItem), """
                                \(language) \(pane) \(wayIn): M1 did not take the press
                                """)
                        } else {
                            searchItem.beginSearchInteraction()
                        }
                        XCTAssertTrue(waitForEditor(searchItem), """
                            \(language) \(pane) \(wayIn): no field editor arrived (\(describe(rig)))
                            """)
                        settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
                        XCTAssertEqual(segmentCount(rig.window), 3, """
                            \(language) \(pane) \(wayIn): opening the search folded the tabs where the \
                            open field still fits (\(describe(rig)))
                            """)
                        XCTAssertGreaterThanOrEqual(searchItem.searchField.frame.width, full - 1, """
                            \(language) \(pane) \(wayIn): the field is \
                            \(searchItem.searchField.frame.width) pt, not its focused \(full) pt \
                            (\(describe(rig)))
                            """)
                        XCTAssertTrue(watch.evicted.isEmpty, """
                            \(language) \(pane) \(wayIn): \(watch.evicted.sorted()) evicted while opening
                            """)
                        searchItem.endSearchInteraction()
                        settleUntil(rig.window, turns: 200) {
                            searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                        }
                        XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                            \(language) \(pane) \(wayIn): closed empty, the magnifier and the full tabs \
                            did not return (\(describe(rig)))
                            """)
                        XCTAssertTrue(watch.evicted.isEmpty, """
                            \(language) \(pane) \(wayIn): \(watch.evicted.sorted()) evicted across the \
                            whole cycle
                            """)
                        close(rig)
                    }
                }
            }
        }
    }

    /// **The owner's own shape**: `.windowTitle`, Russian, the text switcher
    /// (this file's own default, `setUp()`) — `AppKit`'s title container
    /// anchors `currentToolbarSlack(_:)` differently from the name item every
    /// other case in this file uses (`windowTitleMaxX(_:)`'s own header), so
    /// the fix needs its own reading under this style rather than trusting
    /// the `.moduleName` cases to stand in for it. Title and subtitle set the
    /// way `AnUnfoldIsPredictedNeverTrialledTests
    /// .testAMagnifierPressAndCloseUnfoldsCleanlyUnderWindowTitle` sets them —
    /// through `mount(pane:)` now, before the bar attaches, not after: a
    /// warm-up round used to stand in front of the assertion below because
    /// the title used to arrive after `mount(pane:)`'s own first settle pass
    /// had already run once with no title to anchor on, reading the very
    /// press this test is about as unanchored and folding it — a rig
    /// artifact, not a reading of the fix. With the title drawn before the
    /// bar attaches, `rest(_:)` (the same wait `mount(pane:)`'s own first
    /// settle needs, waited by the clock rather than a turn count) is enough
    /// for the first real press to read a genuinely anchored verdict.
    func testOwnersShapeKeepsTheFullTabsUnderWindowTitle() {
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.alwaysCollapseSearch = true
        AppLanguage.only(.ru) {
            for pane in [Self.snug[.ru]!, Self.wide[.ru]!] {
                let rig = mount(pane: pane)
                rest(rig)
                guard let searchItem = searchItem(rig.window) else {
                    XCTFail("ru \(pane): no search item"); close(rig); continue
                }
                let full = searchItem.preferredWidthForSearchField
                XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                    ru \(pane) .windowTitle: precondition, not at rest (\(describe(rig)))
                    """)

                let watch = EvictionWatch(rig.window.toolbar)
                XCTAssertTrue(magnifierPress(rig, searchItem), "ru \(pane) .windowTitle: M1 did not take the press")
                XCTAssertTrue(waitForEditor(searchItem), "ru \(pane) .windowTitle: no field editor arrived (\(describe(rig)))")
                settleUntil(rig.window) { searchItem.searchField.frame.width >= full - 1 }
                XCTAssertEqual(segmentCount(rig.window), 3, """
                    ru \(pane) .windowTitle: the first press folded the tabs (\(describe(rig)))
                    """)
                XCTAssertGreaterThanOrEqual(searchItem.searchField.frame.width, full - 1, """
                    ru \(pane) .windowTitle: the field is \(searchItem.searchField.frame.width) pt, \
                    not its focused \(full) pt (\(describe(rig)))
                    """)
                XCTAssertTrue(watch.evicted.isEmpty, "ru \(pane) .windowTitle: \(watch.evicted.sorted()) evicted while opening")
                searchItem.endSearchInteraction()
                settleUntil(rig.window, turns: 200) {
                    searchItem.searchField.isHidden && segmentCount(rig.window) == 3
                }
                XCTAssertTrue(searchItem.searchField.isHidden && segmentCount(rig.window) == 3, """
                    ru \(pane) .windowTitle: closed empty, the magnifier and full tabs did not return \
                    (\(describe(rig)))
                    """)
                close(rig)
            }
        }
    }

    // MARK: - A query is never hidden (risk 1)

    /// **Typed into, then left**: the field keeps the query on show rather
    /// than folding it behind a glyph — at the wide pane, where the setting
    /// is the only thing that could fold it.
    func testAQueryTypedAndLeftKeepsTheFieldOpen() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press")
        XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived")
        guard let editor = searchItem.searchField.currentEditor() as? NSTextView else {
            return XCTFail("the field editor is not a text view")
        }
        editor.insertText("wget", replacementRange: NSRange(location: NSNotFound, length: 0))
        settle(rig.window, turns: 5)
        XCTAssertEqual(rig.query.text, "wget", "precondition: the typed query did not reach the page")
        rig.window.makeFirstResponder(nil)
        XCTAssertTrue(waitForEditor(searchItem, present: false), "editing did not end")
        settle(rig.window, turns: 40)
        XCTAssertEqual(searchItem.searchField.stringValue, "wget", "the query left the field")
        XCTAssertFalse(searchItem.searchField.isHidden, """
            a query typed and left is hidden behind the magnifier (\(describe(rig)))
            """)
        XCTAssertGreaterThan(searchItem.searchField.frame.width, 100, """
            a query typed and left sits in a field too narrow to read (\(describe(rig)))
            """)
        settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
        XCTAssertEqual(segmentCount(rig.window), 3, """
            at 1060 pt with a query left open the tabs never came back (\(describe(rig)))
            """)

        // The window moved with the query still held: AppKit lays the bar out
        // again, and a field still capped would fold now, query and all.
        let frame = rig.window.frame
        rig.window.setFrame(frame.insetBy(dx: 40, dy: 0), display: true)
        settle(rig.window, turns: 20)
        rig.window.setFrame(frame, display: true)
        settle(rig.window, turns: 40)
        XCTAssertFalse(searchItem.searchField.isHidden, """
            a query typed and left folded behind the magnifier once the window moved (\(describe(rig)))
            """)
        XCTAssertGreaterThan(searchItem.searchField.frame.width, 100, """
            a query typed and left shrank once the window moved (\(describe(rig)))
            """)
    }

    /// **A query typed and left, then cleared with the field's own clear
    /// button, pressed the way VoiceOver and Full Keyboard Access press it**
    /// — `performClick(_:)` on AppKit's own `_NSSearchFieldClearButton`,
    /// which is what an accessibility press or Space on the focused button
    /// does: the button's action, with no mouse and no change of focus. The
    /// field is then empty and nobody is editing it, which is exactly the
    /// state the setting promises to rest as the magnifier
    /// (`AppSettings.alwaysCollapseSearch`'s own header).
    ///
    /// **Not the mouse.** A synthetic press through `NSWindow.sendEvent(_:)`
    /// at the button's centre, with its release queued, made the field's
    /// editor first responder and left the query in place (read 2026-09-27):
    /// the rig cannot say what a real click on the button does to focus, and
    /// if a real click does focus the field, the rest arrives when that edit
    /// ends. This case is the press that needs no edit at all.
    func testAQueryClearedByPressingTheFieldsClearButtonRestsAgain() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let field = searchItem.searchField
        XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press")
        XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived")
        (field.currentEditor() as? NSTextView)?.insertText("wget", replacementRange: NSRange(location: NSNotFound, length: 0))
        rig.window.makeFirstResponder(nil)
        XCTAssertTrue(waitForEditor(searchItem, present: false), "editing did not end")
        settle(rig.window, turns: 40)
        XCTAssertFalse(field.isHidden, "precondition: the query left is not on show (\(describe(rig)))")
        XCTAssertEqual(field.stringValue, "wget", "precondition: the query is not in the field")

        // AppKit's own clear button, which on macOS 27.2 is a real button
        // inside the field's hosting view — found by its class, the way this
        // suite finds every AppKit view with no public header.
        guard let clear = field.everyView(named: "_NSSearchFieldClearButton").first as? NSButton else {
            return XCTFail("precondition: no clear button inside a field holding a query")
        }
        clear.performClick(nil)
        settle(rig.window, turns: 10)
        XCTAssertEqual(field.stringValue, "", "precondition: the clear button left «\(field.stringValue)» in the field")
        XCTAssertNil(field.currentEditor(), "precondition: pressing the clear button began an edit")
        XCTAssertEqual(rig.query.text, "", "precondition: the cleared field did not reach the page")
        settleUntil(rig.window, turns: 100) { field.isHidden }
        XCTAssertTrue(field.isHidden, """
            cleared by its own button with nobody editing, the empty idle search does not rest as \
            the magnifier while Always Collapse Search is on (\(describe(rig)))
            """)
    }

    /// **The page itself fills the field, and later empties it** (a search
    /// carried over, a Clear button): filled, it shows; emptied, it rests as
    /// the magnifier again — neither waits for somebody to click in it.
    func testAQueryThePageWritesShowsAndItsClearingRestsAgain() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        XCTAssertTrue(searchItem.searchField.isHidden, "precondition: not resting as the magnifier")
        for round in 0..<2 {
            rig.query.text = "wget"
            declare("test.collapse.first", on: rig)
            settleUntil(rig.window) { !searchItem.searchField.isHidden }
            XCTAssertEqual(searchItem.searchField.stringValue, "wget", "round \(round): the page's query is not in the field")
            XCTAssertFalse(searchItem.searchField.isHidden, """
                round \(round): a query the page wrote is hidden behind the magnifier (\(describe(rig)))
                """)
            rig.query.text = ""
            declare("test.collapse.first", on: rig)
            settleUntil(rig.window) { searchItem.searchField.isHidden }
            XCTAssertTrue(searchItem.searchField.isHidden, """
                round \(round): emptied by the page, the field does not rest as the magnifier (\(describe(rig)))
                """)
            settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
            XCTAssertEqual(segmentCount(rig.window), 3, "round \(round): the tabs are not full (\(describe(rig)))")
        }
    }

    // MARK: - Turning it off and on (the M2 trap)

    /// **Off at full width, then on and off again**: each time the field
    /// takes the state the setting names, and the tabs stay full — M2 reads
    /// a field growing at an unchanged room as the magnifier opening it,
    /// and a release it mistook for one would fold the tabs for good. The
    /// window is nudged narrower and back after each change, because a
    /// fold the prediction has stopped answering for only shows once the
    /// room moves.
    func testTurningItOffAndOnAtFullWidthLeavesTheTabsFull() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        XCTAssertTrue(searchItem.searchField.isHidden, "precondition: not resting as the magnifier")
        for (step, on) in [false, true, false, true, false].enumerated() {
            AppSettings.alwaysCollapseSearch = on
            settleUntil(rig.window) { searchItem.searchField.isHidden == on }
            settle(rig.window, turns: 20)
            XCTAssertEqual(searchItem.searchField.isHidden, on, """
                step \(step), turned \(on ? "on" : "off"): the field does not follow (\(describe(rig)))
                """)
            XCTAssertEqual(segmentCount(rig.window), 3, """
                step \(step), turned \(on ? "on" : "off") at 1060 pt: the tabs folded (\(describe(rig)))
                """)
            let frame = rig.window.frame
            rig.window.setFrame(frame.insetBy(dx: 15, dy: 0), display: true)
            settle(rig.window, turns: 20)
            rig.window.setFrame(frame, display: true)
            settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
            XCTAssertEqual(segmentCount(rig.window), 3, """
                step \(step), turned \(on ? "on" : "off"), after the window moved 30 pt and back: \
                the tabs stayed folded (\(describe(rig)))
                """)
        }
    }

    /// **Moved while somebody is typing in the field**: turned on mid-edit
    /// the field stays open until the edit ends, then rests; turned off
    /// mid-edit the field ends at AppKit's own rest and the tabs come back.
    func testTurningItOverMidEditWaitsForTheEditToEnd() {
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let full = searchItem.preferredWidthForSearchField

        searchItem.beginSearchInteraction()
        XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived")
        settle(rig.window, turns: 20)
        AppSettings.alwaysCollapseSearch = true
        settle(rig.window, turns: 20)
        XCTAssertNotNil(searchItem.searchField.currentEditor(), "turning it on ended the edit")
        XCTAssertGreaterThanOrEqual(searchItem.searchField.frame.width, full - 1, """
            turned on mid-edit, the field folded under the person typing (\(describe(rig)))
            """)
        searchItem.endSearchInteraction()
        settleUntil(rig.window, turns: 200) { searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
        XCTAssertTrue(searchItem.searchField.isHidden, """
            turned on mid-edit and closed empty, the field does not rest as the magnifier (\(describe(rig)))
            """)

        XCTAssertTrue(magnifierPress(rig, searchItem), "M1 did not take the press")
        XCTAssertTrue(waitForEditor(searchItem), "no field editor arrived")
        settle(rig.window, turns: 20)
        AppSettings.alwaysCollapseSearch = false
        settle(rig.window, turns: 10)
        searchItem.endSearchInteraction()
        settleUntil(rig.window, turns: 200) { !searchItem.searchField.isHidden && segmentCount(rig.window) == 3 }
        XCTAssertFalse(searchItem.searchField.isHidden, """
            turned off mid-edit and closed empty at 1060 pt, the field does not rest open (\(describe(rig)))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, """
            turned off mid-edit and closed empty at 1060 pt, the tabs stayed folded (\(describe(rig)))
            """)
    }

    // MARK: - Something else moves while the search rests or is open

    /// **The language changes under a resting search**: the field's prompt
    /// and name are rewritten (`patchSearch`) and the tabs are re-measured,
    /// and none of it may reopen the field or leave the tabs folded.
    func testALanguageChangeKeepsTheSearchResting() {
        AppSettings.alwaysCollapseSearch = true
        AppLanguage.only(.en) {
            let rig = mount(pane: Self.snug[.ru]!)
            defer { close(rig) }
            XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, "precondition: not resting (\(describe(rig)))")
            for language: AppLanguage in [.ru, .de, .en] {
                AppLanguage.override = language
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                // What a page redeclares after a language change: its prompt
                // in the new language — `HelmA11y.searchField`, a word the
                // host's own table translates, so the field's placeholder is
                // really rewritten under the resting cap.
                rig.channel.declare(content(rig.query, prompt: HelmA11y.searchField), token: "test.collapse.first",
                                    generation: rig.channel.nextGeneration())
                settle(rig.window, turns: 3)
                XCTAssertEqual(searchItem(rig.window)?.searchField.placeholderString, HelmA11y.searchField,
                               "precondition: the \(language) prompt did not reach the field")
                // The item on the bar now, whichever it is — a change that
                // rebuilt the bar must be read on the bar it built.
                settleUntil(rig.window, turns: 200) {
                    searchItem(rig.window)?.searchField.isHidden == true && segmentCount(rig.window) == 3
                }
                XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, """
                    after a change to \(language), the search no longer rests as the magnifier (\(describe(rig)))
                    """)
                XCTAssertEqual(segmentCount(rig.window), 3, """
                    after a change to \(language), the tabs are not full (\(describe(rig)))
                    """)
            }
        }
    }

    /// **Without Icon chosen while the search is open** — the bar's menu
    /// opens on the name while somebody is typing, and the choice rebuilds
    /// the whole bar under the open field. The new bar's search is empty and
    /// idle, so it is born resting, and its tabs are full.
    func testThePageHeaderChangedMidSearchLeavesTheNewBarResting() {
        // Turned on after the first bar is built, so the only bars born with
        // the setting already on are the ones the header change builds.
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        AppSettings.alwaysCollapseSearch = true
        guard let first = searchItem(rig.window) else { return XCTFail("no search item") }
        settleUntil(rig.window) { first.searchField.isHidden }
        XCTAssertTrue(magnifierPress(rig, first), "M1 did not take the press")
        XCTAssertTrue(waitForEditor(first), "no field editor arrived")
        settle(rig.window, turns: 20)
        for (step, style) in [PageBarStyle.windowTitle, .moduleName].enumerated() {
            AppSettings.pageBarStyle = style
            settleUntil(rig.window, turns: 200) {
                searchItem(rig.window)?.searchField.isHidden == true && segmentCount(rig.window) == 3
            }
            XCTAssertFalse(searchItem(rig.window) === first && step == 0,
                           "precondition: the page header change did not rebuild the bar")
            XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, """
                step \(step), \(style) chosen mid-search: the new bar's empty search does not rest as the \
                magnifier (\(describe(rig)))
                """)
            XCTAssertEqual(segmentCount(rig.window), 3, """
                step \(step), \(style) chosen mid-search: the new bar's tabs are not full (\(describe(rig)))
                """)
            if step == 0, let rebuilt = searchItem(rig.window) {
                XCTAssertTrue(magnifierPress(rig, rebuilt), "the rebuilt bar's magnifier is not M1's")
                XCTAssertTrue(waitForEditor(rebuilt), "the rebuilt bar's search does not open")
                settle(rig.window, turns: 20)
            }
        }
    }

    // MARK: - Bars that are not on screen (risk 5)

    /// **A cached bar that missed the change, and a bar not built yet**:
    /// turned on while another page is showing, the first page's bar comes
    /// back resting; a page first visited after the change is born resting;
    /// and turned off elsewhere, the first page comes back open.
    func testBarsOffScreenFollowTheSetting() {
        let rig = mount(pane: Self.wide[.en]!, token: "test.collapse.first")
        defer { close(rig) }
        XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, false, "precondition: the first page rests closed")

        select("test.collapse.second", on: rig)
        settle(rig.window, turns: 30)
        AppSettings.alwaysCollapseSearch = true
        settle(rig.window, turns: 20)

        select("test.collapse.first", on: rig)
        settleUntil(rig.window) { searchItem(rig.window)?.searchField.isHidden == true }
        XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, """
            turned on while another page showed, the first page's cached bar came back with its \
            field open (\(describe(rig)))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, "the first page's tabs are not full (\(describe(rig)))")

        select("test.collapse.third", on: rig)
        settleUntil(rig.window) { searchItem(rig.window)?.searchField.isHidden == true }
        XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, """
            a page first visited after the change was not born resting (\(describe(rig)))
            """)

        AppSettings.alwaysCollapseSearch = false
        settle(rig.window, turns: 20)
        select("test.collapse.first", on: rig)
        settleUntil(rig.window) { searchItem(rig.window)?.searchField.isHidden == false }
        XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, false, """
            turned off while another page showed, the first page came back as a magnifier (\(describe(rig)))
            """)
        settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
        XCTAssertEqual(segmentCount(rig.window), 3, "the first page's tabs are not full (\(describe(rig)))")
    }

    /// **A page left while its search was open, then come back to**: the
    /// search is empty and nobody is in it, so it rests as the magnifier and
    /// the full tabs are there beside it — the edit that was open when the
    /// page changed must not leave the bar believing a search is still
    /// opening.
    func testAPageLeftMidSearchComesBackResting() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!, token: "test.collapse.first")
        defer { close(rig) }
        guard let first = searchItem(rig.window) else { return XCTFail("no search item") }
        XCTAssertTrue(magnifierPress(rig, first), "M1 did not take the press")
        XCTAssertTrue(waitForEditor(first), "no field editor arrived")
        settle(rig.window, turns: 20)

        select("test.collapse.second", on: rig)
        settle(rig.window, turns: 40)
        select("test.collapse.first", on: rig)
        settle(rig.window, turns: 40)
        let frame = rig.window.frame
        rig.window.setFrame(frame.insetBy(dx: 15, dy: 0), display: true)
        settle(rig.window, turns: 20)
        rig.window.setFrame(frame, display: true)
        settleUntil(rig.window, turns: 200) {
            searchItem(rig.window)?.searchField.isHidden == true && segmentCount(rig.window) == 3
        }
        XCTAssertTrue(searchItem(rig.window) === first, "precondition: the first page's bar was rebuilt, not cached")
        XCTAssertEqual(searchItem(rig.window)?.searchField.currentEditor() == nil, true,
                       "precondition: the field is still being edited (\(describe(rig)))")
        XCTAssertEqual(searchItem(rig.window)?.searchField.isHidden, true, """
            back on a page left mid-search, the empty idle search does not rest as the \
            magnifier (\(describe(rig)))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, """
            back on a page left mid-search, the full tabs are not there \
            (\(describe(rig)))
            """)
    }

    // MARK: - The clear button's fold, fed what the repair was not

    /// The pane a page's own controls sit in.
    private func pageView(_ rig: Rig) -> NSView? {
        (rig.window.contentViewController as? NSSplitViewController)?.splitViewItems.last?.viewController.view
    }

    /// What a text field in the page is told while somebody types in it: the
    /// end of its editing and its action — neither of which a press on the
    /// toolbar's clear button is any business of.
    @MainActor
    private final class PageFieldWatch: NSObject, NSTextFieldDelegate {
        var endedEditing = 0
        var fired = 0
        func controlTextDidEndEditing(_ obj: Notification) { endedEditing += 1 }
        @objc func action(_ sender: Any?) { fired += 1 }
    }

    /// A query typed and left — the state the clear button is pressed in:
    /// through the magnifier where the search rests as one, by a click into
    /// the field where it is on show. True when the query is on show and
    /// nobody edits it.
    private func leaveAQuery(_ text: String, in rig: Rig, _ searchItem: NSSearchToolbarItem) -> Bool {
        let opened = searchItem.searchField.isHidden
            ? magnifierPress(rig, searchItem) : rig.window.makeFirstResponder(searchItem.searchField)
        guard opened, waitForEditor(searchItem),
              let editor = searchItem.searchField.currentEditor() as? NSTextView else { return false }
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        rig.window.makeFirstResponder(nil)
        guard waitForEditor(searchItem, present: false) else { return false }
        settle(rig.window, turns: 40)
        return searchItem.searchField.stringValue == text && !searchItem.searchField.isHidden
    }

    private func clearButton(_ field: NSSearchField) -> NSButton? {
        field.everyView(named: "_NSSearchFieldClearButton").first as? NSButton
    }

    /// **A query typed and left, then emptied by the page itself** — a
    /// page's own Clear, a search reset on a tab change. The field is empty
    /// and nobody edits it, so it rests as the magnifier: the path
    /// `testAQueryThePageWritesShowsAndItsClearingRestsAgain` walks with a
    /// field no interaction ever opened, taken here after one did. The cap
    /// alone does not fold a field an interaction opened
    /// (`foldOpenedSearch`'s own reading), so the page's write, which reaches
    /// the field through `patchSearch`, asks for the cap and then for that
    /// fold; without the second the field stood open at 240 pt.
    func testAQueryTypedAndLeftThenEmptiedByThePageRestsAgain() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let field = searchItem.searchField
        XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                      "precondition: the query typed and left is not on show (\(describe(rig)))")
        XCTAssertEqual(rig.query.text, "wget", "precondition: the typed query did not reach the page")

        rig.query.text = ""
        declare("test.collapse.first", on: rig)
        settleUntil(rig.window) { field.isHidden }
        XCTAssertEqual(field.stringValue, "", "precondition: the page's empty query did not reach the field")
        XCTAssertNil(field.currentEditor(), "precondition: emptying the field began an edit")
        XCTAssertTrue(field.isHidden, """
            a query typed and left, then emptied by the page, leaves the empty idle search open \
            while Always Collapse Search is on (\(describe(rig)))
            """)
        settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
        XCTAssertEqual(segmentCount(rig.window), 3, "emptied by the page: the tabs are not full (\(describe(rig)))")
    }

    /// **Somebody is typing in a field in the page when the search's clear
    /// button is pressed** — an accessibility press (Voice Control, Switch
    /// Control, VoiceOver with its cursor apart from the keyboard) that
    /// leaves the keyboard's focus in the page's field. Neither page that
    /// carries a toolbar search today holds a text field — Homebrew and
    /// Uninstaller hold lists — but the window has one field editor, and the
    /// fold must leave it where it is: `foldOpenedSearch` ends the search's
    /// editing through a throwaway text view of its own and never asks for
    /// first responder, so the field being typed in comes out as it was: the
    /// caret where it stood, editing never ended, the action never fired,
    /// the text and its undo intact. The same case with the setting
    /// off is the control — no fold runs there, so a failure there is the
    /// rig's.
    func testTheClearButtonsFoldLeavesTheFieldBeingTypedInAsItWas() {
        for on in [false, true] {
            AppSettings.alwaysCollapseSearch = on
            let arm = on ? "setting on" : "setting off (control)"
            let rig = mount(pane: Self.wide[.en]!)
            defer { close(rig) }
            guard let searchItem = searchItem(rig.window), let pane = pageView(rig) else {
                return XCTFail("\(arm): no search item or no pane")
            }
            let field = searchItem.searchField
            let page = NSTextField(frame: NSRect(x: 40, y: 300, width: 320, height: 24))
            page.stringValue = "hello world"
            let watch = PageFieldWatch()
            page.delegate = watch
            page.target = watch
            page.action = #selector(PageFieldWatch.action(_:))
            pane.addSubview(page)
            XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                          "\(arm): precondition — the query typed and left is not on show (\(describe(rig)))")
            XCTAssertTrue(rig.window.makeFirstResponder(page), "\(arm): precondition — the page's field took no focus")
            guard let editor = page.currentEditor() as? NSTextView else {
                return XCTFail("\(arm): precondition — the page's field has no editor")
            }
            editor.setSelectedRange(NSRange(location: 5, length: 0))
            editor.insertText(",", replacementRange: editor.selectedRange())
            let typed = editor.string
            let caret = editor.selectedRange()
            let couldUndo = editor.undoManager?.canUndo ?? false
            XCTAssertEqual(typed, "hello, world", "\(arm): precondition — the keystroke did not land")
            let ended = watch.endedEditing, fired = watch.fired
            guard let clear = clearButton(field) else { return XCTFail("\(arm): precondition — no clear button") }

            clear.performClick(nil)
            settle(rig.window, turns: 10)
            XCTAssertEqual(field.stringValue, "", "\(arm): precondition — the clear button left «\(field.stringValue)»")
            if on {
                settleUntil(rig.window, turns: 100) { field.isHidden }
                XCTAssertTrue(field.isHidden, "\(arm): precondition — the cleared search did not fold (\(describe(rig)))")
            }
            let now = page.currentEditor() as? NSTextView
            XCTAssertNotNil(now, """
                \(arm): the field being typed in lost its focus to the clear button's press \
                (first responder now \(String(describing: rig.window.firstResponder)))
                """)
            XCTAssertEqual(now?.string, typed, "\(arm): the text being typed changed")
            XCTAssertEqual(now?.selectedRange(), caret, """
                \(arm): the caret in the field being typed in moved from \(caret) to \
                \(String(describing: now?.selectedRange())) — the next key replaces whatever that covers
                """)
            XCTAssertEqual(watch.endedEditing, ended, """
                \(arm): the field being typed in was told its editing ended \
                \(watch.endedEditing - ended) time(s) by a press on the toolbar
                """)
            XCTAssertEqual(watch.fired, fired, "\(arm): the field being typed in fired its action — a submit nobody pressed")
            XCTAssertEqual(now?.undoManager?.canUndo ?? false, couldUndo, """
                \(arm): the typing's undo went with the press (could undo before: \(couldUndo))
                """)
        }
    }

    /// A list with rows, as the pages that carry a toolbar search hold one.
    @MainActor
    private final class Rows: NSObject, NSTableViewDataSource {
        func numberOfRows(in tableView: NSTableView) -> Int { 5 }
        func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? { "row \(row)" }
    }

    /// **Focus held by nothing, then by a list in the page** — the press on a
    /// settings window nobody is typing in, and on one whose package list has
    /// the keyboard, which is what the two pages that carry a toolbar search
    /// (Homebrew, Uninstaller) hold. The fold ends the field's editing by
    /// calling its own `textDidEndEditing(_:)` with a throwaway text view and
    /// never touches first responder (`SettingsToolbar.foldOpenedSearch`);
    /// nothing may be left behind: no editor on the search, and the window's
    /// first responder and the list's selection where they were.
    func testTheClearButtonsFoldTakesNothingFromAnIdleWindowOrAFocusedList() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window), let pane = pageView(rig) else {
            return XCTFail("no search item or no pane")
        }
        let field = searchItem.searchField

        XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                      "precondition: the query typed and left is not on show (\(describe(rig)))")
        let before = rig.window.firstResponder
        XCTAssertTrue(before === rig.window,
                      "precondition: something holds focus in the window: \(String(describing: before))")
        clearButton(field)?.performClick(nil)
        settleUntil(rig.window, turns: 100) { field.isHidden }
        XCTAssertTrue(field.isHidden, "focus held by nothing: the cleared search does not rest (\(describe(rig)))")
        XCTAssertNil(field.currentEditor(), "focus held by nothing: the fold left the search being edited")
        XCTAssertTrue(rig.window.firstResponder === before, """
            focus held by nothing: the fold left \(String(describing: rig.window.firstResponder)) holding it
            """)

        let rows = Rows()
        let list = NSTableView(frame: NSRect(x: 40, y: 200, width: 320, height: 120))
        list.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        list.dataSource = rows
        pane.addSubview(list)
        list.reloadData()
        list.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        XCTAssertTrue(leaveAQuery("brew", in: rig, searchItem),
                      "precondition: the second query typed and left is not on show (\(describe(rig)))")
        XCTAssertTrue(rig.window.makeFirstResponder(list), "precondition: the list took no focus")
        clearButton(field)?.performClick(nil)
        settleUntil(rig.window, turns: 100) { field.isHidden }
        XCTAssertTrue(field.isHidden, "a focused list: the cleared search does not rest (\(describe(rig)))")
        XCTAssertNil(field.currentEditor(), "a focused list: the fold left the search being edited")
        XCTAssertTrue(rig.window.firstResponder === list, """
            a focused list: the fold left \(String(describing: rig.window.firstResponder)) holding the \
            keyboard the list had
            """)
        XCTAssertEqual(list.selectedRowIndexes, IndexSet(integer: 2), "a focused list: its selection moved")
    }

    /// **Cleared three rounds over, and out of reach once cleared** — each
    /// round a query typed and left, the clear pressed, the field resting
    /// and the tabs full: the fold is not a one-shot. And once the field is
    /// empty its clear button is gone from every hand — hidden, so neither a
    /// pointer nor an accessibility client is offered it (the field's own
    /// `accessibilityChildren()` does not list the button even while it is
    /// on show, so that is no reading of reach). `searchSubmitted` runs
    /// `foldOpenedSearch` whenever the cap is on, without asking whether the
    /// field is open; what the fold does to a field already resting —
    /// nothing — is `testTheClearsFoldOnAFieldAlreadyRestingLeavesItAsItIs`'s
    /// to hold, with the hidden button's `performClick`. If AppKit ever
    /// offers the button on an empty field, that press becomes a person's,
    /// and this goes red first.
    func testEveryRoundOfClearingRestsAndTheClearedButtonIsOutOfReach() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let field = searchItem.searchField
        for round in 0..<3 {
            XCTAssertTrue(leaveAQuery("wget\(round)", in: rig, searchItem),
                          "round \(round): precondition — the query typed and left is not on show (\(describe(rig)))")
            guard let clear = clearButton(field) else { return XCTFail("round \(round): no clear button") }
            XCTAssertFalse(clear.isHiddenOrHasHiddenAncestor,
                           "round \(round): precondition — the clear button is hidden on a field holding a query")
            clear.performClick(nil)
            settleUntil(rig.window, turns: 100) { field.isHidden }
            XCTAssertTrue(field.isHidden, "round \(round): cleared, the search does not rest (\(describe(rig)))")
            XCTAssertNil(field.currentEditor(), "round \(round): cleared, the search is left being edited")
            settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
            XCTAssertEqual(segmentCount(rig.window), 3, "round \(round): cleared, the tabs are not full (\(describe(rig)))")
            XCTAssertTrue(clear.isHiddenOrHasHiddenAncestor, """
                round \(round): once cleared, the clear button is still on show — a second press would \
                run the fold on a resting field, which opens it
                """)
        }
    }

    /// **A query the page wrote, then cleared with the field's own button** —
    /// a search the page carried over (a bar rebuilt, a page come back to),
    /// emptied by an accessibility press. No interaction opened this field,
    /// so the cap alone folds it (`testAQueryThePageWritesShowsAndItsClearingRestsAgain`
    /// reads that); what the press must not do on top is start an interaction
    /// that is still opening when it is told to end, and leave the search
    /// open and being edited with nobody having asked.
    ///
    /// **After one ordinary clear first, in the same window.** Run first in
    /// a fresh process this case passed 4 of 4; run after
    /// `testAQueryClearedByPressingTheFieldsClearButtonRestsAgain` it failed
    /// every time, and after two other cases it passed (read 2026-09-27) —
    /// the history of the process decided it. A person's session has that
    /// history, so this case makes its own: a query typed, left and cleared
    /// by the button, and only then the page's query and its clear.
    func testAQueryThePageWroteClearedByTheButtonRestsWithNobodyInIt() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let field = searchItem.searchField

        XCTAssertTrue(leaveAQuery("brew", in: rig, searchItem),
                      "precondition: the query typed and left is not on show (\(describe(rig)))")
        clearButton(field)?.performClick(nil)
        settleUntil(rig.window, turns: 100) { field.isHidden && field.currentEditor() == nil }
        settle(rig.window, turns: 20)
        XCTAssertTrue(field.isHidden && field.currentEditor() == nil,
                      "precondition: the ordinary clear did not rest the search (\(describe(rig)))")

        rig.query.text = "wget"
        declare("test.collapse.first", on: rig)
        settleUntil(rig.window) { !field.isHidden }
        settle(rig.window, turns: 20)
        XCTAssertEqual(field.stringValue, "wget", "precondition: the page's query is not in the field")
        XCTAssertFalse(field.isHidden, "precondition: the page's query is hidden (\(describe(rig)))")
        XCTAssertNil(field.currentEditor(), "precondition: the page's write began an edit")
        let before = rig.window.firstResponder
        guard let clear = clearButton(field) else { return XCTFail("precondition: no clear button") }

        clear.performClick(nil)
        settle(rig.window, turns: 10)
        XCTAssertEqual(rig.query.text, "", "precondition: the cleared field did not reach the page")
        settleUntil(rig.window, turns: 100) { field.isHidden }
        settle(rig.window, turns: 20)
        XCTAssertNil(field.currentEditor(), """
            a query the page wrote, cleared by the button: the search is left being edited with \
            nobody having asked (\(describe(rig)))
            """)
        XCTAssertTrue(field.isHidden, """
            a query the page wrote, cleared by the button: the search does not rest (\(describe(rig)))
            """)
        XCTAssertTrue(rig.window.firstResponder === before, """
            a query the page wrote, cleared by the button: focus moved from \(String(describing: before)) \
            to \(rig.window.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing")
            """)
        settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
        XCTAssertEqual(segmentCount(rig.window), 3, "the tabs are not full (\(describe(rig)))")
    }

    /// **The page changes in the same turn as the clear** — the fold ends an
    /// interaction whose end-of-editing work (`controlTextDidEndEditing`'s
    /// deferred rest and the settle it schedules) lands after its bar has
    /// left the window. The page shown next must be untouched by it, and the
    /// page left must come back resting with its tabs full.
    func testAPageSwitchInTheClearsTurnLeavesBothBarsResting() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!, token: "test.collapse.first")
        defer { close(rig) }
        guard let first = searchItem(rig.window) else { return XCTFail("no search item") }
        XCTAssertTrue(leaveAQuery("wget", in: rig, first),
                      "precondition: the query typed and left is not on show (\(describe(rig)))")
        guard let clear = clearButton(first.searchField) else { return XCTFail("precondition: no clear button") }

        clear.performClick(nil)
        select("test.collapse.second", on: rig)
        settle(rig.window, turns: 40)
        guard let second = searchItem(rig.window), second !== first else {
            return XCTFail("precondition: the second page shows the first page's bar")
        }
        settleUntil(rig.window, turns: 200) { second.searchField.isHidden && segmentCount(rig.window) == 3 }
        XCTAssertTrue(second.searchField.isHidden, """
            the page switched to in the clear's turn does not rest its search (\(describe(rig)))
            """)
        XCTAssertNil(second.searchField.currentEditor(), """
            the page switched to in the clear's turn has its search being edited (\(describe(rig)))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, """
            the page switched to in the clear's turn has its tabs folded (\(describe(rig)))
            """)
        XCTAssertNil(first.searchField.currentEditor(), "the page left in the clear's turn is still being edited")

        select("test.collapse.first", on: rig)
        settle(rig.window, turns: 40)
        let frame = rig.window.frame
        rig.window.setFrame(frame.insetBy(dx: 15, dy: 0), display: true)
        settle(rig.window, turns: 20)
        rig.window.setFrame(frame, display: true)
        settleUntil(rig.window, turns: 200) {
            searchItem(rig.window)?.searchField.isHidden == true && segmentCount(rig.window) == 3
        }
        XCTAssertTrue(searchItem(rig.window) === first, "precondition: the first page's bar was rebuilt, not cached")
        XCTAssertEqual(first.searchField.stringValue, "", "the query cleared in the switch's turn came back")
        XCTAssertTrue(first.searchField.isHidden, """
            back on the page cleared in the switch's turn, the search does not rest (\(describe(rig)))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, """
            back on the page cleared in the switch's turn, the tabs are not full (\(describe(rig)))
            """)
    }

    // MARK: - The end-of-editing fold, fed what its repair was not

    /// **Turned on over a field an interaction opened and that was emptied
    /// while the setting was off** — a query typed through the magnifier and
    /// left, the setting turned off, the query cleared by the field's own
    /// button or by the page, the setting turned back on. The field is empty
    /// and nobody edits it, which is the state the setting promises to rest
    /// as the magnifier. The setting's change reaches the field through
    /// `restEverySearch`; the clear, made with the setting off, folded
    /// nothing, and the cap alone does not fold a field an interaction
    /// opened (`foldOpenedSearch`'s own reading). The third way turns the
    /// setting on while another page shows, so the change reaches this bar
    /// while it is out of the window.
    func testTurningItOnOverAFieldEmptiedWhileItWasOffRestsIt() {
        for how in ["cleared by its button", "emptied by the page", "cleared, turned on from another page"] {
            AppSettings.alwaysCollapseSearch = true
            let rig = mount(pane: Self.wide[.en]!, token: "test.collapse.first")
            defer { close(rig) }
            guard let searchItem = searchItem(rig.window) else { return XCTFail("\(how): no search item") }
            let field = searchItem.searchField
            XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                          "\(how): precondition — the query typed and left is not on show (\(describe(rig)))")
            AppSettings.alwaysCollapseSearch = false
            settle(rig.window, turns: 20)
            if how == "emptied by the page" {
                rig.query.text = ""
                declare("test.collapse.first", on: rig)
            } else {
                guard let clear = clearButton(field) else { return XCTFail("\(how): precondition — no clear button") }
                clear.performClick(nil)
            }
            settle(rig.window, turns: 40)
            XCTAssertEqual(field.stringValue, "", "\(how): precondition — «\(field.stringValue)» left in the field")
            XCTAssertNil(field.currentEditor(), "\(how): precondition — emptying the field began an edit")

            let away = how == "cleared, turned on from another page"
            if away {
                select("test.collapse.second", on: rig)
                settle(rig.window, turns: 40)
                XCTAssertFalse(self.searchItem(rig.window) === searchItem,
                               "\(how): precondition — the second page shows the first page's bar")
            }
            AppSettings.alwaysCollapseSearch = true
            if away {
                settle(rig.window, turns: 20)
                select("test.collapse.first", on: rig)
                XCTAssertTrue(self.searchItem(rig.window) === searchItem,
                              "\(how): precondition — the first page's bar was rebuilt, not cached")
            }
            settleUntil(rig.window) { field.isHidden }
            XCTAssertTrue(field.isHidden, """
                \(how) with Always Collapse Search off, then turned on: the empty idle search does not \
                rest as the magnifier (\(describe(rig)))
                """)
            settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
            XCTAssertEqual(segmentCount(rig.window), 3, "\(how), then turned on: the tabs are not full (\(describe(rig)))")
        }
    }

    /// **Turned on while somebody is typing in the search** — the change
    /// reaches the field being edited through `restEverySearch`, which
    /// folds every bar the change rests (`foldOpenedSearch`): only the cap
    /// staying off and the fold's own editor guard stand between that fold
    /// and an edit in progress — with both gone, it ended an empty edit.
    /// Nothing may end, move or fold that edit: the same field editor, the
    /// same text and caret, the same first responder, the same width,
    /// nothing written to the page. The edit's own end then decides — ended
    /// empty, the search rests as the magnifier; with a query, it stays on
    /// show.
    func testTurningItOnWhileTheSearchIsBeingEditedLeavesTheEditAlone() {
        for typed in ["", "wget"] {
            let label = typed.isEmpty ? "nothing typed yet" : "«\(typed)» being typed"
            AppSettings.alwaysCollapseSearch = false
            let rig = mount(pane: Self.wide[.en]!)
            defer { close(rig) }
            guard let searchItem = searchItem(rig.window) else { return XCTFail("\(label): no search item") }
            let field = searchItem.searchField
            XCTAssertFalse(field.isHidden, "\(label): precondition — with the setting off the field is not on show")
            guard rig.window.makeFirstResponder(field), waitForEditor(searchItem),
                  let editor = field.currentEditor() as? NSTextView else {
                return XCTFail("\(label): precondition — no editor on the search (\(describe(rig)))")
            }
            if !typed.isEmpty {
                editor.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            settle(rig.window, turns: 20)
            let caret = editor.selectedRange()
            let writes = rig.query.writes
            let responder = rig.window.firstResponder
            let width = field.frame.width

            AppSettings.alwaysCollapseSearch = true
            settle(rig.window, turns: 40)
            XCTAssertTrue(field.currentEditor() === editor, """
                \(label), turned on mid-edit: the edit was ended or handed another editor (\(describe(rig)))
                """)
            XCTAssertTrue(rig.window.firstResponder === responder, """
                \(label), turned on mid-edit: focus moved from \(String(describing: responder)) to \
                \(String(describing: rig.window.firstResponder))
                """)
            XCTAssertEqual(editor.string, typed, "\(label), turned on mid-edit: the text being typed changed")
            XCTAssertEqual(editor.selectedRange(), caret, "\(label), turned on mid-edit: the caret moved")
            XCTAssertFalse(field.isHidden, "\(label), turned on mid-edit: folded under the person typing (\(describe(rig)))")
            XCTAssertEqual(field.frame.width, width, accuracy: 0.5, """
                \(label), turned on mid-edit: the field being typed in changed width (\(describe(rig)))
                """)
            XCTAssertEqual(rig.query.writes, writes, "\(label), turned on mid-edit: the page's query was written")

            rig.window.makeFirstResponder(nil)
            XCTAssertTrue(waitForEditor(searchItem, present: false), "\(label): precondition — the edit did not end")
            if typed.isEmpty {
                settleUntil(rig.window, turns: 200) { field.isHidden && segmentCount(rig.window) == 3 }
                XCTAssertTrue(field.isHidden, """
                    \(label), turned on mid-edit, the edit ended empty: the search does not rest (\(describe(rig)))
                    """)
                XCTAssertEqual(segmentCount(rig.window), 3, """
                    \(label), turned on mid-edit, the edit ended empty: the tabs are not full (\(describe(rig)))
                    """)
            } else {
                settle(rig.window, turns: 40)
                XCTAssertFalse(field.isHidden, """
                    \(label), turned on mid-edit, the edit ended with a query: it is hidden (\(describe(rig)))
                    """)
                XCTAssertEqual(field.stringValue, typed, "\(label): the query left in the field changed")
            }
        }
    }

    /// **Turned on over a query left on show** — typed and left with the
    /// setting off, then the setting turned on: here, and from another page
    /// so the change reaches this bar out of the window. "Always" means
    /// "whenever the field is empty" (`AppSettings.alwaysCollapseSearch`'s
    /// own header): the query stays on show at the width it had, nobody
    /// edits it, focus stays where it was and nothing is written to the page.
    func testTurningItOnOverAQueryLeftOnShowKeepsItOnShow() {
        for away in [false, true] {
            let label = away ? "turned on from another page" : "turned on here"
            AppSettings.alwaysCollapseSearch = false
            let rig = mount(pane: Self.wide[.en]!, token: "test.collapse.first")
            defer { close(rig) }
            guard let searchItem = searchItem(rig.window) else { return XCTFail("\(label): no search item") }
            let field = searchItem.searchField
            XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                          "\(label): precondition — the query typed and left is not on show (\(describe(rig)))")
            settle(rig.window, turns: 20)
            let width = field.frame.width
            let responder = rig.window.firstResponder
            let writes = rig.query.writes

            if away {
                select("test.collapse.second", on: rig)
                settle(rig.window, turns: 40)
                XCTAssertFalse(self.searchItem(rig.window) === searchItem,
                               "\(label): precondition — the second page shows the first page's bar")
            }
            AppSettings.alwaysCollapseSearch = true
            settle(rig.window, turns: 20)
            if away {
                select("test.collapse.first", on: rig)
                XCTAssertTrue(self.searchItem(rig.window) === searchItem,
                              "\(label): precondition — the first page's bar was rebuilt, not cached")
            }
            settle(rig.window, turns: 60)
            XCTAssertFalse(field.isHidden, """
                \(label): the query left in the field was folded behind the magnifier (\(describe(rig)))
                """)
            XCTAssertEqual(field.stringValue, "wget", "\(label): the query left in the field changed")
            XCTAssertNil(field.currentEditor(), "\(label): turning it on began an edit (\(describe(rig)))")
            XCTAssertEqual(field.frame.width, width, accuracy: 0.5, """
                \(label): the query on show changed width (\(describe(rig)))
                """)
            if !away {
                XCTAssertTrue(rig.window.firstResponder === responder, """
                    \(label): focus moved from \(String(describing: responder)) to \
                    \(String(describing: rig.window.firstResponder))
                    """)
            }
            XCTAssertEqual(rig.query.writes, writes, "\(label): the page's query was written")
            XCTAssertEqual(rig.query.text, "wget", "\(label): the page's query changed")
        }
    }

    /// **Cleared at the narrowest panes** — where the full tabs fit beside
    /// the magnifier and not beside the field holding a query: with the
    /// query on show the tabs are folded, and the clear's fold is what hands
    /// their room back. English at 700 pt is left out because its full tabs
    /// do sit beside the open field there (read 2026-09-28), so that pane
    /// reads nothing about the room. The fold's end of editing reaches
    /// `controlTextDidEndEditing` as an empty edit ending does, so the
    /// settle it arms must bring the full tabs back with nothing evicted on
    /// the way — and the press is written to the page once: an end of
    /// editing that fired the field's action would write it again and fold
    /// again from inside its own fold.
    func testAClearAtTheNarrowestPanesGivesTheTabsTheirRoomBack() {
        AppSettings.alwaysCollapseSearch = true
        let panes: [AppLanguage: [CGFloat]] = [.en: [646], .ru: [646, 700]]
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                for pane in panes[language]! {
                    let label = "\(language) \(pane) pt"
                    let rig = mount(pane: pane)
                    defer { close(rig) }
                    guard let searchItem = searchItem(rig.window) else { return XCTFail("\(label): no search item") }
                    let field = searchItem.searchField
                    XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                                  "\(label): precondition — the query typed and left is not on show (\(describe(rig)))")
                    settle(rig.window, turns: 40)
                    XCTAssertNotEqual(segmentCount(rig.window), 3, """
                        \(label): precondition — the full tabs sit beside the open field, so nothing \
                        below reads the room the fold hands back (\(describe(rig)))
                        """)
                    guard let clear = clearButton(field) else { return XCTFail("\(label): precondition — no clear button") }
                    let writes = rig.query.writes
                    let watch = EvictionWatch(rig.window.toolbar)

                    clear.performClick(nil)
                    settleUntil(rig.window, turns: 250) { field.isHidden && segmentCount(rig.window) == 3 }
                    XCTAssertTrue(field.isHidden, "\(label): cleared, the search does not rest (\(describe(rig)))")
                    XCTAssertNil(field.currentEditor(), "\(label): cleared, the search is left being edited")
                    XCTAssertEqual(segmentCount(rig.window), 3, """
                        \(label): cleared, the tabs never got their room back (\(describe(rig)))
                        """)
                    XCTAssertTrue(watch.evicted.isEmpty, "\(label): \(watch.evicted.sorted()) evicted by the clear")
                    XCTAssertEqual(rig.query.writes - writes, 1, """
                        \(label): one press on the clear button wrote the page's query \
                        \(rig.query.writes - writes) times
                        """)
                }
            }
        }
    }

    /// **A page come back to with its query reset while it was away** —
    /// Uninstaller's search is the page's own state and starts empty each
    /// time the page is mounted. The query was typed and left, another page
    /// was shown, and the first comes back declaring an empty search: the
    /// empty write reaches the field in the same pass that puts its cached
    /// bar back in the window, and the field rests as the magnifier.
    func testAPageComeBackToWithItsQueryResetRestsTheSearch() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!, token: "test.collapse.first")
        defer { close(rig) }
        guard let first = searchItem(rig.window) else { return XCTFail("no search item") }
        XCTAssertTrue(leaveAQuery("wget", in: rig, first),
                      "precondition: the query typed and left is not on show (\(describe(rig)))")
        select("test.collapse.second", on: rig)
        settle(rig.window, turns: 40)
        XCTAssertFalse(searchItem(rig.window) === first, "precondition: the second page shows the first page's bar")

        rig.query.text = ""
        select("test.collapse.first", on: rig)
        settleUntil(rig.window, turns: 200) { first.searchField.isHidden && segmentCount(rig.window) == 3 }
        XCTAssertTrue(searchItem(rig.window) === first, "precondition: the first page's bar was rebuilt, not cached")
        XCTAssertEqual(first.searchField.stringValue, "", "precondition: the page's reset did not reach the field")
        XCTAssertNil(first.searchField.currentEditor(), "come back to with its query reset: the search is being edited")
        XCTAssertTrue(first.searchField.isHidden, """
            come back to with its query reset, the empty idle search does not rest as the magnifier \
            (\(describe(rig)))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, "come back to with its query reset: the tabs are not full (\(describe(rig)))")
    }

    /// **The clear's fold run on a field already resting** — the clear
    /// button's action a second time, on the field it has just emptied and
    /// folded (`searchSubmitted` runs the fold whenever the cap is on,
    /// without asking whether the field is open). Hidden, the button is no
    /// person's to press today (`testEveryRoundOfClearingRestsAndTheClearedButtonIsOutOfReach`),
    /// so it is pressed by `performClick`. The fold must change nothing: the
    /// field stays folded, nobody edits it, the tabs stay full and the
    /// window's first responder stays where it was — the interaction this
    /// fold replaced opened such a field and left it being edited. The hidden
    /// field's own frame is not read — nothing draws it while the magnifier
    /// stands in its place, and it read 72 pt before this press and 36 pt
    /// after it (2026-09-28).
    func testTheClearsFoldOnAFieldAlreadyRestingLeavesItAsItIs() {
        AppSettings.alwaysCollapseSearch = true
        let rig = mount(pane: Self.wide[.en]!)
        defer { close(rig) }
        guard let searchItem = searchItem(rig.window) else { return XCTFail("no search item") }
        let field = searchItem.searchField
        XCTAssertTrue(leaveAQuery("wget", in: rig, searchItem),
                      "precondition: the query typed and left is not on show (\(describe(rig)))")
        guard let clear = clearButton(field) else { return XCTFail("precondition: no clear button") }
        clear.performClick(nil)
        settleUntil(rig.window, turns: 100) { field.isHidden && field.currentEditor() == nil }
        settleUntil(rig.window, turns: 200) { segmentCount(rig.window) == 3 }
        settle(rig.window, turns: 20)
        XCTAssertTrue(field.isHidden && field.currentEditor() == nil && segmentCount(rig.window) == 3,
                      "precondition: the first clear did not rest the search (\(describe(rig)))")
        let before = rig.window.firstResponder

        clear.performClick(nil)
        settle(rig.window, turns: 60)
        XCTAssertNil(field.currentEditor(), """
            the fold run on a resting field left it being edited with nobody having asked (\(describe(rig)))
            """)
        XCTAssertTrue(field.isHidden, "the fold run on a resting field opened it (\(describe(rig)))")
        XCTAssertTrue(rig.window.firstResponder === before, """
            the fold run on a resting field moved focus from \(String(describing: before)) to \
            \(String(describing: rig.window.firstResponder))
            """)
        XCTAssertEqual(segmentCount(rig.window), 3, "the fold run on a resting field folded the tabs (\(describe(rig)))")
    }
}
