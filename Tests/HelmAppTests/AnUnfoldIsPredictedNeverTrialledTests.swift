import AppKit
import QuartzCore
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The fold mechanism predicts a layout before it touches the live bar,
/// rather than trying one and watching AppKit refuse it.**
///
/// `SettingsToolbar.settle(_:)` used to unfold the tabs on the attached bar,
/// ask AppKit's own `isVisible` whether they fit, and fold straight back if
/// they did not — a trial against the live bar, and every refusal was a real
/// eviction into AppKit's own «»» scale-and-fade, brought back a frame later.
/// Ending a search interaction always re-armed a settle
/// (`controlTextDidEndEditing`), so a room the full tabs could not hold ran
/// that trial on every search exit and lost it — an unfold immediately
/// followed by a fold at an unchanged room, which is the flicker the owner
/// reported (`grep "room=646.0" ~/Library/Logs/Helm/helm.log`, the owner's own
/// machine, before the fix below).
///
/// **A first version of this file's own fix latched instead of flickering.**
/// `searchRoomBudget(_:)` charged the search field's *resting* frame as fixed
/// demand, but AppKit widens an idle, empty field into whatever room a fold
/// just freed — so folding once made every later prediction see that widened
/// frame as unavoidable, and the tabs never unfolded again, and the field
/// never shrank back to its magnifier either. That defect was invisible to a
/// bare, split-view-less window with synthetic labels chosen to force a
/// permanent fold at 646 pt: real content actually leaves slack there, so the
/// bug it hid was not "never fits," it was "any fold, even one AppKit would
/// gladly undo, sticks." What follows uses the real split-view shape
/// `SettingsSplitViewController` builds and Homebrew's own segment words, and
/// drives the open half of the cycle through M1 (`tookMagnifierPress(_:)`)
/// rather than calling `beginSearchInteraction()` directly, which skips M1's
/// own pre-fold and evicts on the open path for a reason that has nothing to
/// do with the mechanism under test.
///
/// **The resting-state check and the full-cycle check are split apart on
/// purpose, and the full-cycle check does not use the owner's own 646 pt.**
/// `NSSearchToolbarItem` does not shrink its field back down in the same
/// layout pass that a neighbouring item grows into the room that shrink
/// would free — probed directly against this fixture: immediately after
/// `endSearchInteraction()` the field is still at its wider, pre-close frame,
/// and only an independently-timed, later AppKit pass narrows it. At the
/// owner's own minimum pane that stale width is, by itself, enough to
/// overflow the room, and nothing this file found — polling `layoutIfNeeded()`
/// for up to three seconds, flushing `CATransaction`, nudging the window's
/// size — reliably waits that independent timing out in a synchronous XCTest
/// run. `testTheRestingStateMatchesAppKitsOwnJudgment` below proves the
/// prediction itself is correct at 646, 740 and 840 pt with no interaction at
/// all (which is what `SwitcherMeasurementRig` and `currentToolbarSlack(_:)`
/// are actually answerable for), and
/// `testAFullSearchCycleThroughM1EvictsNothingAndReturnsToRest` proves the
/// full press-close cycle at a pane, per language, wide enough that a stale
/// field cannot overflow it — still narrow enough that the field rests
/// genuinely collapsed beforehand, so the comparison is not the field held
/// open against itself. Both are real regression tests: put
/// `searchRoomBudget(_:)`'s old, resting-frame-only body back and the second
/// one goes red — confirmed by running that mutant. That test's own header
/// has the exact panes and the swept band they come from.
@MainActor
final class AnUnfoldIsPredictedNeverTrialledTests: XCTestCase {

    /// **Every case here reads the search AppKit rests by itself, so "Always
    /// Collapse Search" is held off** (`AppSettings.alwaysCollapseSearch`,
    /// `AlwaysCollapseSearchRestsAsTheMagnifierTests` for the other side).
    /// The test process reads the setting from its own defaults domain, which
    /// outlives every run: found holding it on (2026-09-28), this file ran
    /// two cases red — no forced eviction left to attribute, and the wait
    /// gate never consulted — and ran them green with the value removed.
    private static let collapseKey = "alwaysCollapseSearch"
    private var savedCollapse: Any?
    /// **The bar's two styles are held too**, at the defaults every pane
    /// below was read under — `moduleName` and `text`; two cases switch to
    /// `windowTitle` themselves. With `windowTitle` and `icons` left in the
    /// same domain, nine of the twelve ran red on their own preconditions
    /// (2026-09-28). Each is kept raw and put back here rather than by a
    /// `defer` through the typed setter, which wrote the getter's default over
    /// a key the domain did not hold: every run from a clean domain left
    /// `pageBarStyle` behind in it.
    private var savedPageBar: Any?
    private var savedSwitcher: Any?

    override func setUp() async throws {
        savedCollapse = AppSettings.store.object(Self.collapseKey)
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedSwitcher = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        AppSettings.alwaysCollapseSearch = false
        AppSettings.pageBarStyle = .moduleName
        AppSettings.toolbarSwitcherStyle = .text
    }

    override func tearDown() async throws {
        AppSettings.store.set(savedCollapse, for: Self.collapseKey)
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedSwitcher, for: ToolbarSwitcherStyle.storageKey)
    }

    /// `SettingsSplitViewController`'s own `sidebarDefault` — `private` there
    /// and duplicated here rather than widened for one test file to reach,
    /// the same precedent a now-deleted sibling test already set for the
    /// identical number, before its own Uninstaller cases lost the bridged
    /// field this pass removed.
    private static let sidebarWidth: CGFloat = 214

    /// Homebrew's own three segments — reduced from four 2026-09-24 when the
    /// owner moved search onto a field every tab carries — read the way
    /// `HomebrewViewModel.Segment.label` reads them: through `L(_:)` on the
    /// same English keys (`HomebrewStrings.swift`), rather than by importing
    /// `Module_Homebrew_UI`, which `HelmAppTests` has no dependency on and no
    /// business reaching around (`Package.swift`'s own module boundaries: a
    /// UI test reaches its own module's engine through its own UI target, and
    /// the host's own tests reach a module only through `ModuleRegistry`).
    private func homebrewTabs() -> [HelmToolbarTab] {
        [
            HelmToolbarTab(id: "installed", title: L("Installed"), symbol: "shippingbox"),
            HelmToolbarTab(id: "updates", title: L("Updates"), symbol: "arrow.up.circle"),
            HelmToolbarTab(id: "health", title: L("Health"), symbol: "stethoscope")
        ]
    }

    /// Homebrew's own two actions (`HomebrewSettingsPage.swift`) — one
    /// declared but not currently shown, one shown — the shape
    /// `HelmToolbarActionsCapsule`'s reserve is actually sized from, rather
    /// than the single always-visible action an earlier version of this file
    /// declared.
    private func homebrewContent() -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: homebrewTabs(), selectedTab: .constant("installed"),
            actions: [
                HelmToolbarAction(id: "upgradeAll", title: L("Upgrade all"), symbol: "arrow.down.to.line",
                                  isEnabled: false, isVisible: false) {},
                HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}
            ],
            search: HelmToolbarSearch(prompt: L("Search packages"), text: .constant("")))
    }

    private struct Rig {
        let window: NSWindow
        let toolbar: SettingsToolbar
        let keepAlive: [AnyObject]
    }

    /// **The split-view shape `SettingsSplitViewController` actually
    /// builds** — a 214 pt sidebar and a detail pane beside it — because
    /// `offeredRoom()` reads the detail item's own width; a bare window with
    /// no split view hands it `contentLayoutRect.width` instead, which also
    /// includes the traffic-light zone a real settings window's detail pane
    /// never offers the tabs. `pane` lands exactly, corrected for the
    /// divider's own hairline the same way `ZZReviewProbeTests.mountSplit`
    /// (the review's own scratch fixture) needed to.
    /// - Parameter content: what the pane declares — `nil` for Homebrew's own
    ///   shape (`homebrewContent()`), the ordinary case every caller but
    ///   `testARefusalDoesNotOutliveTheInteractionThatEarnedIt` uses. That one
    ///   test passes `mechanismFixtureContent()` instead — see its own header
    ///   for why a real, three-tab pane cannot exercise what it needs to.
    private func mountSplit(pane: CGFloat, content: HelmPageToolbarContent? = nil) -> Rig {
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

        sidebarItem.allowsFullHeightLayout = true

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
        // **Key, not merely ordered back.** `tookMagnifierPress(_:)` calls
        // `beginSearchInteraction()`/`endSearchInteraction()`, which engage
        // and release the search field's real field editor — a window that
        // is never key cannot make anything first responder in the way a
        // press really would, and `controlTextDidEndEditing` then arrives
        // late, on whatever later responder-chain change happens to flush
        // it, rather than promptly after the close — exactly the same
        // key-window need `WindowSeenReaderRaceTests` and
        // `TheWindowReaderAnswersAtDeliveryTests` already established for a
        // real responder-chain change in a test window.
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
        model.selection = .module("test.toolbarPredict")
        channel.declare(content ?? homebrewContent(), token: "test.toolbarPredict",
                        generation: channel.nextGeneration())
        window.layoutIfNeeded()
        return Rig(window: window, toolbar: toolbar, keepAlive: [model, channel])
    }

    /// **Not Homebrew's own tabs — a mechanism fixture, for one test only.**
    /// Homebrew's real three segments never reproduce a forced eviction at
    /// the owner's own minimum pane (646 pt): three tabs leave enough slack
    /// there that defeating the wait gate for up to eight attempts never once
    /// evicted anything (measured, this Mac, `scratchpad/refit/`, Russian,
    /// 646 pt — `0/8`), and every wider pane only has more slack still, so no
    /// real width can exercise this test's own scenario with Homebrew's
    /// actual shape. A fourth segment restores the same tab count the
    /// mechanism was last proven against at this exact pane (the same 646 pt
    /// the four-tab fixture used before Homebrew's search tab was folded into
    /// a field on every tab, 2026-09-24): the identical forced-eviction path
    /// measured `0/8` with three tabs and an eviction on the second attempt
    /// with four, this Mac. The fourth segment reuses `AppStr.settingsPane`'s
    /// own key, `"Settings"` — an existing, already-translated key nothing in
    /// Homebrew's own tab strip ever shows — precisely so nobody mistakes
    /// this window for a real Homebrew screen if it is ever seen on screen
    /// (it never is: `orderBack` only, like every other rig in this file).
    private func mechanismFixtureContent() -> HelmPageToolbarContent {
        var tabs = homebrewTabs()
        tabs.append(HelmToolbarTab(id: "mechanismFixtureExtra", title: L("Settings"), symbol: "gearshape"))
        // One action, not Homebrew's own two — the capsule reserves width for
        // every *declared* action regardless of visibility (`identifiers(content:
        // style:)`'s own header), so Homebrew's hidden `upgradeAll` still
        // costs room here; measured with it kept, the four tabs plus that
        // reserve rest folded to one segment already, which is not this
        // test's own scenario (`scratchpad/refit/`).
        return HelmPageToolbarContent(
            tabs: tabs, selectedTab: .constant("installed"),
            actions: [HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}],
            search: HelmToolbarSearch(prompt: L("Search packages"), text: .constant("")))
    }

    /// **The same four-tab shape as `mechanismFixtureContent()`, with no
    /// `search:` at all** — Hosts' and Leftovers' own shape, which has tabs
    /// and actions but no search field, is the one `settle(_:)` used to skip
    /// its whole unfold decision for.
    private func searchlessMechanismFixtureContent() -> HelmPageToolbarContent {
        var tabs = homebrewTabs()
        tabs.append(HelmToolbarTab(id: "mechanismFixtureExtra", title: L("Settings"), symbol: "gearshape"))
        return HelmPageToolbarContent(
            tabs: tabs, selectedTab: .constant("installed"),
            actions: [HelmToolbarAction(id: "refresh", title: L("Refresh list"), symbol: "arrow.clockwise") {}])
    }

    private func settle(_ window: NSWindow, turns: Int = 20) {
        for _ in 0..<turns {
            window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// **Pumps until `condition` is true, or gives up after `turns`.**
    /// `endSearchInteraction()`'s own `controlTextDidEndEditing` does not
    /// always land inside a fixed pump count at this pane — measured: a
    /// generous, fixed `settle(_:turns:)` after the close still read the
    /// bar mid-transition often enough to make the assertion order-dependent
    /// on what the *next* round happened to do, at 646 pt specifically. This
    /// polls the actual condition the assertion cares about rather than
    /// guessing a turn count large enough to outrun it.
    private func settleUntil(_ window: NSWindow, turns: Int = 150, _ condition: () -> Bool) {
        for _ in 0..<turns {
            if condition() { return }
            window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private func namedItems(_ toolbar: NSToolbar) -> [(String, NSToolbarItem)] {
        toolbar.items.compactMap { item in
            switch item.itemIdentifier.rawValue {
            case "helm.tabs": return ("tabs", item)
            case "helm.actions": return ("actions", item)
            case "helm.name": return ("name", item)
            default: return nil
            }
        }
    }

    /// Watches `isVisible` on every named item and counts how many times it
    /// was seen going `true` → `false` — the KVO AppKit itself fires on an
    /// eviction (`NSToolbarItem.h:169-172`), read directly here rather than
    /// through `SettingsToolbar`'s own net (M3), which only reacts to this
    /// same notification. `everFalse` is `falseCount > 0`, kept as its own
    /// reading since most call sites only ever ask "at all", not "how many" —
    /// `falseCount` is what `testTheOwnersPaneNeverEvictsThroughASearchCloseCycle`
    /// needs to tell an ordinary, single "blinks at most once" eviction
    /// (within the mechanism's own documented contract, `CLAUDE.md`'s
    /// "Required change" #2) apart from the flicker of two or more the owner
    /// actually reported.
    @MainActor
    private final class VisibilityWatch {
        private(set) var falseCount: [String: Int]
        private var tokens: [NSKeyValueObservation] = []

        var everFalse: [String: Bool] { falseCount.mapValues { $0 > 0 } }

        init(_ items: [(String, NSToolbarItem)]) {
            falseCount = Dictionary(uniqueKeysWithValues: items.map { ($0.0, 0) })
            for (name, item) in items {
                tokens.append(item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                    guard change.newValue == false else { return }
                    MainActor.assumeIsolated { self?.falseCount[name, default: 0] += 1 }
                })
            }
        }
    }

    private func segmentCount(_ toolbar: NSToolbar) -> Int? {
        guard let tabsItem = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "helm.tabs" }),
              let view = tabsItem.view
        else { return nil }
        return view.everyView(ofType: NSSegmentedControl.self).first?.segmentCount
    }

    /// **A synthetic left-mouse-down on the search item's own magnifier**,
    /// built from the field's *own* superview bounds converted to window
    /// coordinates — the exact inverse of the conversion
    /// `tookMagnifierPress(_:)` runs to test whether a click landed inside
    /// it, so this never has to guess at the field's on-screen position
    /// independently of whatever the toolbar itself just laid out.
    private func magnifierClick(_ window: NSWindow, searchItem: NSSearchToolbarItem) -> NSEvent? {
        guard let superview = searchItem.searchField.superview else { return nil }
        let midInSuperview = NSPoint(x: superview.bounds.midX, y: superview.bounds.midY)
        let locationInWindow = superview.convert(midInSuperview, to: nil)
        return NSEvent.mouseEvent(with: .leftMouseDown, location: locationInWindow, modifierFlags: [],
                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: 1, pressure: 1)
    }

    /// One press-then-close cycle through the real paths (M1 for the press,
    /// `endSearchInteraction()` for the close) — asserts that whatever the
    /// tabs and the field rested at *before the first round*, the cycle
    /// returns to exactly that, with no watched item ever reported evicted
    /// along the way. `restSegments`/`restHidden` are fixed by the caller
    /// once, before any round runs, and passed into every round unchanged —
    /// reading them fresh at the top of each round instead would validate a
    /// wrong end state against itself the moment one round left the bar
    /// somewhere it should not have, silently turning a real regression into
    /// a self-consistent (and therefore green) new "rest."
    private func assertCycleReturnsToRest(_ rig: Rig, pane: CGFloat, language: AppLanguage, round: Int,
                                          restSegments: Int?, restHidden: Bool) {
        guard let bar = rig.window.toolbar else {
            XCTFail("pane \(pane) \(language) round \(round): no toolbar attached")
            return
        }
        guard let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first else {
            XCTFail("pane \(pane) \(language) round \(round): no search item — nothing below is measured")
            return
        }
        guard let event = magnifierClick(rig.window, searchItem: searchItem) else {
            XCTFail("pane \(pane) \(language) round \(round): could not place a synthetic press on the field")
            return
        }

        let watch = VisibilityWatch(namedItems(bar))
        _ = rig.toolbar.tookMagnifierPress(event)
        // Waits for the field's own editor before pumping further — without
        // this, at this file's narrower, three-tab panes, the press's own
        // `beginSearchInteraction()` sometimes has not actually attached an
        // editor by the time a fixed pump ends, and closing then closes an
        // interaction that, from the field's own point of view, never
        // started: no `controlTextDidEndEditing` ever fires, so nothing ever
        // re-arms `settle(_:)` and the tabs stay folded for the rest of this
        // round — measured directly on this fixture, `scratchpad/refit/`:
        // without this wait, one round in a three-round cycle (position
        // varied by run) never recorded an unfold at all
        // (`gateUnfoldFieldWidths` stayed empty for that round), and with it,
        // ten consecutive three-round cycles at five widths from 646 to
        // 710 pt (English) all converged. Same wait
        // `testTheOwnersPaneNeverEvictsThroughASearchCloseCycle` already
        // takes before its own close, for the identical reason.
        _ = spinUntilEditorArrives(searchItem)
        settle(rig.window, turns: 40)
        searchItem.endSearchInteraction()
        settleUntil(rig.window) {
            segmentCount(bar) == restSegments && searchItem.searchField.isHidden == restHidden
        }

        for (name, everFalse) in watch.everFalse {
            XCTAssertFalse(everFalse, """
                pane \(pane) \(language) round \(round): the \(name) item's isVisible went false \
                during a search open/close cycle through M1 — an eviction, which is the flicker \
                the owner reported
                """)
        }
        XCTAssertEqual(segmentCount(bar), restSegments, """
            pane \(pane) \(language) round \(round): the tabs did not return to their resting form \
            (\(restSegments.map(String.init) ?? "nil") segments) after the cycle
            """)
        XCTAssertEqual(searchItem.searchField.isHidden, restHidden, """
            pane \(pane) \(language) round \(round): the search field did not return to its resting \
            collapse state (hidden=\(restHidden)) after the cycle — this is the latch \
            `searchRoomBudget(_:)` exists to rule out
            """)
    }

    // MARK: - The resting state, at the owner's own width and beside it

    /// **The prediction itself, proved against AppKit's own resting
    /// judgment — no search interaction at all.** This is what
    /// `predictedSlack(bar:tabsWidth:)`'s two fixes (`SwitcherMeasurementRig`
    /// for an accurate twin, `currentToolbarSlack(_:)` for AppKit's own
    /// unaccounted inter-item space) are actually answerable for: at the
    /// owner's own minimum pane (646 pt) full tabs fit, in both languages,
    /// and the same holds wider (740, 840 pt) — with every watched item
    /// actually visible, which is AppKit's own verdict rather than this
    /// class's guess at one. A `settle(_:)` that ran on a wrong prediction
    /// here would fold tabs AppKit is plainly holding, which is exactly the
    /// defect the twin and slack fixes exist to rule out, and it is provable
    /// without depending on `NSSearchToolbarItem`'s own interactive
    /// open/close choreography at all. Whether the field itself rests
    /// collapsed or opportunistically expanded is not asserted here — it
    /// does either depending on how much slack is left over once the tabs
    /// are accounted for (at 840 pt, English's shorter labels leave enough
    /// that AppKit opens the field even though nobody has touched it), and
    /// that choice is AppKit's own, not this class's decision to get right
    /// or wrong.
    /// **The off-screen measurement never reaches the screen.** The rig that
    /// sizes the switcher for the fold prediction used to call
    /// `orderBack(nil)` on its window, which is an ordering: the owner found
    /// an empty 2000 × 44 window at the bottom of the screen behind everything
    /// else (2026-09-25). A measurement has to happen first — otherwise an
    /// "off screen" reading proves nothing — and the window must still not be
    /// visible after it.
    func testTheMeasurementWindowNeverReachesTheScreen() {
        let before = SettingsToolbar.measurementsTaken
        let rig = mountSplit(pane: 646)
        settle(rig.window, turns: 30)
        XCTAssertGreaterThan(SettingsToolbar.measurementsTaken, before,
                             "precondition: no switcher measurement ran — nothing below is checking the rig")
        XCTAssertFalse(SettingsToolbar.measurementWindowIsOnScreen,
                       "the measurement rig's window is on screen — an empty window the person can see")
        rig.window.toolbar = nil
        rig.window.close()
    }

    func testTheRestingStateMatchesAppKitsOwnJudgment() {
        for pane in [CGFloat(646), 740, 840] {
            for language: AppLanguage in [.en, .ru] {
                AppLanguage.only(language) {
                    let rig = mountSplit(pane: pane)
                    settle(rig.window, turns: 30)
                    guard let bar = rig.window.toolbar,
                          let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first
                    else {
                        XCTFail("pane \(pane) \(language): no toolbar or search item")
                        return
                    }
                    XCTAssertEqual(segmentCount(bar), 3, """
                        pane \(pane) \(language): the tabs are not resting full — the fixed \
                        prediction folded a width AppKit actually holds
                        """)
                    _ = searchItem
                    for (name, item) in namedItems(bar) {
                        XCTAssertTrue(item.isVisible, "pane \(pane) \(language): \(name) is not visible at rest")
                    }
                    rig.window.toolbar = nil
                    rig.window.close()
                }
            }
        }
    }

    // MARK: - A full interactive cycle, where the field's own settling time cannot force a false overflow

    /// **A full press-then-close cycle through the real paths must never
    /// evict anything and must return the tabs and field to where they
    /// rested** — proved at a pane wide enough that the field's own
    /// real-world settling time cannot itself manufacture a false overflow:
    /// `NSSearchToolbarItem` does not shrink the field back down in the same
    /// pass that a neighbour grows into freed room (this file's own probing
    /// found the field still at its wider, pre-close frame immediately after
    /// `endSearchInteraction()`, needing a further, independently-timed
    /// AppKit pass to catch up).
    ///
    /// **The pane is chosen from a swept band, not carried over from the
    /// four-tab fixture.** Three tabs need less room than four, so the band
    /// where they rest full *and* the field rests genuinely collapsed is
    /// narrower and sits at a lower width than the four-tab fixture's own
    /// 760/860 pt: swept in 10 pt steps this Mac (`scratchpad/refit/`), it is
    /// `560`–`710` pt in English and `590`–`810` pt in Russian — past either
    /// upper bound the field opens on its own even with nothing pressed, and
    /// below `590` pt Russian folds the tabs outright. `700` pt (English) and
    /// `760` pt (Russian) sit inside both bands with margin either side.
    func testAFullSearchCycleThroughM1EvictsNothingAndReturnsToRest() {
        // Inside the collapsed-rest band this class's own header measures for
        // three tabs (560–710 pt English, 590–810 pt Russian), with margin
        // either side, rather than the four-tab fixture's 760/860 pt, which
        // three tabs leave enough slack at that the field opens on its own —
        // failing this test's own "the field is not resting collapsed"
        // precondition below.
        let panes: [AppLanguage: CGFloat] = [.en: 700, .ru: 760]
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                let pane = panes[language]!
                let rig = mountSplit(pane: pane)
                settle(rig.window, turns: 30)
                guard let bar = rig.window.toolbar,
                      let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first
                else {
                    XCTFail("pane \(pane) \(language): no toolbar or search item to read a rest state from")
                    return
                }
                let restSegments = segmentCount(bar)
                let restHidden = searchItem.searchField.isHidden
                XCTAssertEqual(restSegments, 3, """
                    precondition: the tabs are not resting full at \(pane) pt \(language) — this case \
                    is not exercising what it means to
                    """)
                XCTAssertTrue(restHidden, """
                    precondition: the field is not resting collapsed at \(pane) pt \(language) — \
                    comparing an already-open field to itself would not tell a latched field from a \
                    correctly recovered one
                    """)
                for round in 0..<3 {
                    assertCycleReturnsToRest(rig, pane: pane, language: language, round: round,
                                            restSegments: restSegments, restHidden: restHidden)
                }
                rig.window.toolbar = nil
                rig.window.close()
            }
        }
    }

    // MARK: - The owner's own pane: no unfold→fold pair, whatever it takes to wait for

    /// A single spin of `RunLoop.main`, the API the owner's own brief asked
    /// this file to try harder with — `settle(_:turns:)`/`settleUntil(_:_:)`
    /// above already pump `RunLoop.current` in the same mode from the main
    /// thread, which is the same run loop under a different name; this is
    /// named for that ask rather than for a different mechanism.
    private func spinMainRunLoop(for interval: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    /// **Polls for the field's own editor rather than guessing a pump count
    /// large enough to outrun it.** A fixed `settle(_:turns:)` after the
    /// press, then an immediate `endSearchInteraction()`, is what let a
    /// close reach `settle(_:)` before AppKit's field editor had arrived at
    /// all in an earlier version of the round below — closing an interaction
    /// that, from the field's own point of view, had not genuinely started
    /// yet. `currentEditor() != nil` is the same signal
    /// `tookMagnifierPress(_:)`'s own "missing fold-back" branch and
    /// `settle(_:)`'s own live-edit branch read (`CLAUDE.md`'s own line for
    /// this file: "a real `RunLoop.main.run(until:)` … polling the field
    /// frame until it stops changing" — this polls the one condition that
    /// actually decides whether closing means anything, rather than the
    /// frame, which can stop moving mid-open at the field's growth ceiling).
    private func spinUntilEditorArrives(_ searchItem: NSSearchToolbarItem,
                                        deadline: TimeInterval = 2) -> Bool {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if searchItem.searchField.currentEditor() != nil { return true }
            spinMainRunLoop(for: 0.01)
        }
        return searchItem.searchField.currentEditor() != nil
    }

    /// **Repeated press-then-close cycles, at the owner's own 646 pt, each
    /// one ending with no eviction and the tabs back at their full, four-
    /// segment rest.** A first version of this test called
    /// `endSearchInteraction()` right after a fixed `settle(_:turns:)` pump,
    /// with nothing checking that the field's own editor had actually
    /// arrived — `NSSearchToolbarItem` does not install one synchronously
    /// with `beginSearchInteraction()`, so that close routinely landed before
    /// there was any real interaction to close, which is what read back as
    /// "some rounds never cross `unfoldMargin` at all," not a genuine
    /// coin flip in AppKit's own timing: measured this session
    /// (`scratchpad/probes-settle/review/second/probeFix-natural.log`),
    /// polling `currentEditor() != nil` before every close instead ended all
    /// sixteen rounds run (eight per language, en and ru, at this exact
    /// pane) at three segments with zero evictions. `rounds` stays generous
    /// next to that so a run that never once attempts an unfold — the one
    /// failure mode a per-round assertion cannot see on its own — cannot
    /// pass by accident either, and `gateUnfoldFieldWidths` is asserted
    /// non-empty for the same reason `testTheWaitGateNeverUnfoldsAheadOfTheFieldsOwnCatchUp`
    /// asserts it at a wider pane.
    private static let ownersPaneRounds = 5

    func testTheOwnersPaneNeverEvictsThroughASearchCloseCycle() {
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                let rig = mountSplit(pane: 646)
                settle(rig.window, turns: 30)
                guard let bar = rig.window.toolbar else {
                    XCTFail("\(language): no toolbar")
                    return
                }
                for round in 0..<Self.ownersPaneRounds {
                    guard let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first,
                          let event = magnifierClick(rig.window, searchItem: searchItem)
                    else {
                        XCTFail("\(language) round \(round): no search item or synthetic press")
                        return
                    }
                    let watch = VisibilityWatch(namedItems(bar))
                    let took = rig.toolbar.tookMagnifierPress(event)
                    XCTAssertTrue(took, """
                        \(language) round \(round): the press was not consumed by M1 — the field was \
                        not resting genuinely collapsed going into this round, so it is not exercising \
                        the owner's own press-then-close cycle
                        """)
                    settle(rig.window, turns: 40)
                    XCTAssertTrue(spinUntilEditorArrives(searchItem), """
                        \(language) round \(round): the field's own editor never arrived — closing now \
                        would not be closing a real interaction
                        """)
                    searchItem.endSearchInteraction()
                    settleUntil(rig.window, turns: 250) { segmentCount(bar) == 3 }
                    for (name, count) in watch.falseCount {
                        XCTAssertEqual(count, 0, """
                            \(language) round \(round): the \(name) item's isVisible went false \(count) \
                            times during this single search open/close cycle through M1 — an eviction, \
                            which is the flicker the owner reported
                            """)
                    }
                    XCTAssertEqual(segmentCount(bar), 3, """
                        \(language) round \(round): the tabs did not end this cycle at their full, \
                        three-segment rest — this room the owner's own Homebrew content leaves slack for
                        """)
                }
                XCTAssertFalse(rig.toolbar.gateUnfoldFieldWidths.isEmpty, """
                    \(language) at 646 pt: no unfold was ever attempted across \(Self.ownersPaneRounds) \
                    rounds — this run cannot tell a working wait gate from one that never opens
                    """)
                rig.window.toolbar = nil
                rig.window.close()
            }
        }
    }

    // MARK: - The wait gate: never unfold at a field wider than it was

    /// **`settle(_:)`'s first gate never lets an unfold through at a field
    /// wider than it was while search was open.** At these panes there is
    /// slack to spare — the pane is inside the collapsed-rest band this
    /// class's own header measures for three tabs, not the four-tab
    /// fixture's own 760/860 pt — so the field never has to narrow *all the
    /// way* for the unfold to be safe; measured this Mac, this pane: the
    /// width while open was `240.0` pt both languages, and the width recorded
    /// at unfold `212.5` pt (English) and `219.5` pt (Russian) — narrower
    /// both times, not equal, which is the *never wider* invariant the gate
    /// actually promises, checked below rather than assumed.
    /// `gateWaitedCount` is the proof the gate was actually consulted along
    /// the way rather than never triggered because there was nothing to wait
    /// for. Mutation: delete the
    /// `if let deadline = bar.searchClosingDeadline, Date() < deadline`
    /// branch in `settle(_:)` (restore from a copy afterward) and this goes
    /// red — `gateWaitedCount` stays `0` because there is no wait left to
    /// count, confirmed by running the mutant.
    func testTheWaitGateNeverUnfoldsAheadOfTheFieldsOwnCatchUp() {
        // Inside the collapsed-rest band this class's own header measures for
        // three tabs (560–710 pt English, 590–810 pt Russian) — the same
        // panes `testAFullSearchCycleThroughM1EvictsNothingAndReturnsToRest`
        // uses, rather than the four-tab fixture's 760/860 pt: at 760/860 pt
        // three tabs leave enough slack that the field rests already open
        // (measured, `scratchpad/refit/`), so a press never takes M1's
        // fold-and-open branch at all (`tookMagnifierPress(_:)` requires
        // `field.isHidden`) and the wait gate is never reached.
        let panes: [AppLanguage: CGFloat] = [.en: 700, .ru: 760]
        for language: AppLanguage in [.en, .ru] {
            AppLanguage.only(language) {
                let pane = panes[language]!
                let rig = mountSplit(pane: pane)
                settle(rig.window, turns: 30)
                guard let bar = rig.window.toolbar,
                      let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first
                else {
                    XCTFail("\(language): no toolbar or search item")
                    return
                }
                let watch = VisibilityWatch(namedItems(bar))
                guard let event = magnifierClick(rig.window, searchItem: searchItem) else {
                    XCTFail("\(language): could not place a synthetic press on the field")
                    return
                }
                _ = rig.toolbar.tookMagnifierPress(event)
                // See `assertCycleReturnsToRest`'s own header for why this
                // wait is needed at this file's narrower, three-tab panes.
                _ = spinUntilEditorArrives(searchItem)
                settle(rig.window, turns: 40)
                let widthWhileOpen = searchItem.searchField.frame.width
                searchItem.endSearchInteraction()
                settleUntil(rig.window) { segmentCount(bar) == 3 }
                XCTAssertEqual(segmentCount(bar), 3, "\(language) at \(pane) pt: never unfolded again")
                for (name, everFalse) in watch.everFalse {
                    XCTAssertFalse(everFalse, "\(language) at \(pane) pt: the \(name) item was evicted")
                }
                XCTAssertGreaterThan(rig.toolbar.gateWaitedCount, 0, """
                    \(language) at \(pane) pt: the wait gate was never consulted — this pane is meant \
                    to exercise it, not merely to have nothing to wait for
                    """)
                // A loop over zero recorded widths would pass this vacuously
                // — asserted non-empty first, so the `for` below is checking
                // something rather than nothing.
                XCTAssertFalse(rig.toolbar.gateUnfoldFieldWidths.isEmpty, """
                    \(language) at \(pane) pt: no unfold width was ever recorded — the loop below would \
                    pass with nothing to check
                    """)
                // `<=`, not `<`: the invariant the gate actually promises is
                // *never wider*, not *always narrower* — this pane's own
                // recorded widths do come out narrower (measured this Mac:
                // 212.5 pt English, 219.5 pt Russian, against 240.0 pt while
                // open, this class's own header above), but a pane with
                // slack enough that the field need not narrow at all would
                // read the two as equal, which must not fail this loop.
                for width in rig.toolbar.gateUnfoldFieldWidths {
                    XCTAssertLessThanOrEqual(width, widthWhileOpen, """
                        \(language) at \(pane) pt: unfolded at a field width (\(width)) wider than the \
                        width while search was open (\(widthWhileOpen))
                        """)
                }
                rig.window.toolbar = nil
                rig.window.close()
            }
        }
    }

    // MARK: - The refusal cache: a net fold after our own unfold is recorded

    /// **`checkOverflow()`'s second gate — recorded even when the wait gate
    /// judges correctly**, so a wrong prediction elsewhere still blinks at
    /// most once. Forced here through a real, if artificial, path: unfold
    /// once at 700 pt (English — the pane picked below is inside the band
    /// where three tabs rest full with the field genuinely collapsed,
    /// `560`–`710` pt, measured this Mac, `scratchpad/refit/`), then shrink
    /// the window enough that AppKit itself evicts the tabs — a real
    /// `isVisible` KVO firing through the real net, not a stand-in — and
    /// check the recording fired.
    /// `gateRefusalsRecorded` is the proof, since the very next `settle(_:)`
    /// after restoring the window reads a *different* context (the room
    /// moved back) and correctly unfolds rather than latching — which is
    /// `UnfoldRefusalKey`'s own self-clearing by design, not a gap in the
    /// test.
    ///
    /// **This test alone does not prove a repeat of the *identical* context
    /// is actually refused — only that a recording happens and later clears
    /// — and deleting the recording line here does not turn it red**
    /// (confirmed by running that exact mutant: every assertion in this file
    /// still passed, since nothing below reads what got recorded, only that
    /// the count moved and that restoring room unfolds again). What proves
    /// the recorded value is the *right* one —
    /// `settle(_:)`'s own pre-unfold reading, not a fresh post-fold one — is
    /// `testCheckOverflowPromotesTheUnfoldsOwnFieldWidthNotAFreshOne` below,
    /// which does turn red on that deletion. Kept as its own test regardless,
    /// since it is the only one exercising the self-clearing half (a room
    /// that moves back) at all.
    func testANetFoldAfterOurUnfoldIsRecordedAndSelfClears() {
        AppLanguage.only(.en) {
            let rig = mountSplit(pane: 700)
            settle(rig.window, turns: 30)
            guard let bar = rig.window.toolbar,
                  let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first
            else {
                XCTFail("no toolbar or search item")
                return
            }
            guard let event = magnifierClick(rig.window, searchItem: searchItem) else {
                XCTFail("could not place a synthetic press on the field")
                return
            }
            _ = rig.toolbar.tookMagnifierPress(event)
            // See `assertCycleReturnsToRest`'s own header for why this wait
            // is needed at this file's narrower, three-tab panes.
            _ = spinUntilEditorArrives(searchItem)
            settle(rig.window, turns: 40)
            searchItem.endSearchInteraction()
            settleUntil(rig.window) { segmentCount(bar) == 3 }
            XCTAssertEqual(segmentCount(bar), 3, "precondition: did not unfold once, cleanly, first")

            let originalSize = rig.window.frame.size
            rig.window.setContentSize(NSSize(width: originalSize.width - 320, height: originalSize.height))
            settleUntil(rig.window, turns: 20) { segmentCount(bar) == 1 }
            XCTAssertEqual(segmentCount(bar), 1, "precondition: the shrink did not evict the tabs")
            XCTAssertGreaterThan(rig.toolbar.gateRefusalsRecorded, 0, """
                a net fold landing within \(SettingsToolbar.overflowAttributionWindow) s of our own \
                unfold was not attributed to it
                """)

            rig.window.setContentSize(originalSize)
            settleUntil(rig.window) { segmentCount(bar) == 3 }
            XCTAssertEqual(segmentCount(bar), 3, """
                restoring the room never unfolded again — a refusal that never clears is the latch \
                this mechanism must not reintroduce
                """)
            rig.window.toolbar = nil
            rig.window.close()
        }
    }

    /// **The value `checkOverflow()` records is `settle(_:)`'s own pre-unfold
    /// reading, never a fresh one taken at attribution time.** Same forced
    /// path as `testANetFoldAfterOurUnfoldIsRecordedAndSelfClears` above (an
    /// unfold at 700 pt, then a shrink AppKit itself evicts through), but
    /// checking *what* `checkOverflow()` recorded rather than only that it
    /// recorded something: `gateUnfoldFieldWidths.last` is the field's own
    /// width at the moment `settle(_:)` decided to unfold, taken from inside
    /// `settle(_:)` itself, before anything about the room changed;
    /// `lastRefusedUnfoldFieldWidth` is what `checkOverflow()` actually
    /// stored once it attributed the later fold to that unfold. The two must
    /// be the same number — `checkOverflow()` runs one KVO hop and one
    /// `DispatchQueue.main.async` hop after the eviction it is reacting to,
    /// by which point a fresh read of the field's own frame no longer agrees
    /// with what `settle(_:)` saw — a mismatch here is exactly what let a
    /// room this field width had already evicted the tabs from get retried
    /// and evicted again on every later search close, since the stored key
    /// could never match what a later `settle(_:)` call would compute.
    /// Mutation: revert `checkOverflow()`'s `bar.refusedUnfold =
    /// unfoldContext(bar, fieldWidth: bar.pendingUnfoldFieldWidth)` to
    /// `unfoldContext(bar)` (restore from a copy afterward) and this goes
    /// red — confirmed by running that mutant against this exact pane.
    func testCheckOverflowPromotesTheUnfoldsOwnFieldWidthNotAFreshOne() {
        AppLanguage.only(.en) {
            let rig = mountSplit(pane: 700)
            settle(rig.window, turns: 30)
            guard let bar = rig.window.toolbar,
                  let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first
            else {
                XCTFail("no toolbar or search item")
                return
            }
            guard let event = magnifierClick(rig.window, searchItem: searchItem) else {
                XCTFail("could not place a synthetic press on the field")
                return
            }
            _ = rig.toolbar.tookMagnifierPress(event)
            // See `assertCycleReturnsToRest`'s own header for why this wait
            // is needed at this file's narrower, three-tab panes.
            _ = spinUntilEditorArrives(searchItem)
            settle(rig.window, turns: 40)
            searchItem.endSearchInteraction()
            settleUntil(rig.window) { segmentCount(bar) == 3 }
            XCTAssertEqual(segmentCount(bar), 3, "precondition: did not unfold once, cleanly, first")
            guard let unfoldWidth = rig.toolbar.gateUnfoldFieldWidths.last else {
                XCTFail("precondition: no unfold width was recorded")
                return
            }

            let originalSize = rig.window.frame.size
            rig.window.setContentSize(NSSize(width: originalSize.width - 320, height: originalSize.height))
            settleUntil(rig.window, turns: 20) { segmentCount(bar) == 1 }
            XCTAssertEqual(segmentCount(bar), 1, "precondition: the shrink did not evict the tabs")
            XCTAssertGreaterThan(rig.toolbar.gateRefusalsRecorded, 0, """
                a net fold landing within \(SettingsToolbar.overflowAttributionWindow) s of our own \
                unfold was not attributed to it
                """)
            XCTAssertEqual(rig.toolbar.lastRefusedUnfoldFieldWidth, unfoldWidth, """
                checkOverflow() recorded \(rig.toolbar.lastRefusedUnfoldFieldWidth.map(String.init) ?? "nil") \
                as the refused field width, not the \(unfoldWidth) settle(_:) itself unfolded at — a fresh \
                read at attribution time, not settle(_:)'s own pre-unfold one
                """)

            rig.window.setContentSize(originalSize)
            settleUntil(rig.window) { segmentCount(bar) == 3 }
            rig.window.toolbar = nil
            rig.window.close()
        }
    }

    // MARK: - A refusal is scoped to the interaction that earned it

    /// **A refusal recorded during one search interaction must not outlive
    /// it.** Forces the exact misjudged-gate scenario `UnfoldRefusalKey`
    /// exists for: `searchCollapseWait` set to zero for one cycle defeats
    /// the wait gate on purpose, so `settle(_:)` unfolds against a field
    /// still mid-shrink and AppKit evicts it for real — a genuine
    /// `isVisible` KVO through the real net (`checkOverflow()`), not a
    /// stand-in. That eviction is exactly what a first version of this gate
    /// got right — round 0 below ends folded and refused, at this room, at
    /// this field width, in Russian — and exactly where a first version of
    /// the *fix* went wrong: once the recorded key finally matched a later
    /// read, nothing ever cleared it again, so the *next*, ordinary
    /// interaction at the identical room, field width, language and style
    /// was refused too, forever, which is not "at most one blink" — it is
    /// the tabs stuck as a capsule with an idle, empty field beside them for
    /// the rest of the session. Round 1 is that next interaction, run after
    /// restoring the production wait.
    ///
    /// **This test alone, of the ones in this file, mounts
    /// `mechanismFixtureContent()` rather than Homebrew's own tabs** — see
    /// that method's own header for the numbers: three real tabs at the
    /// owner's own minimum pane (646 pt) never once evicted across eight
    /// forced attempts, so there is no real pane left to reproduce this
    /// scenario's own eviction with Homebrew's actual shape.
    ///
    /// Mutation, both directions confirmed by running the mutant against a
    /// copy of the fixed tree, restored from that copy afterward, never with
    /// `git checkout`: comment out the two clearing lines in
    /// `searchFieldFrameChanged`'s `preferredWidthForSearchField` branch and
    /// round 1's own `segmentCount(bar) == 4` assertion goes red, the tabs
    /// still folded at one segment; comment out the `if bar.refusedUnfold ==
    /// context` branch in `settle(_:)` instead (the read half of the same
    /// gate) and round 0's own `forcedEviction`/`gateRefusalsRecorded`
    /// assertions go red instead — freed of any refusal to check, the fold
    /// self-heals inside the same two-second window every attempt spins for,
    /// so `segmentCount(bar)` never reads back `1`, which is the same
    /// outcome this file's own `probeC-noread.log` recorded for the
    /// identical mutation.
    ///
    /// **Forcing the eviction is a real-clock race against AppKit's own
    /// collapse (measured ~200–215 ms, `searchCollapseWait`'s own header),
    /// and getting the *surrounding* timing wrong reads as the race itself
    /// being unwinnable when it is not.** An early version of the loop below
    /// pumped a fixed 40 turns before polling for the field's editor and
    /// exited its post-close wait the instant `segmentCount(bar)` first read
    /// back `3`; measured directly, that version forced the eviction
    /// reliably alone but failed on every one of many repeated attempts once
    /// it ran third in this file, after
    /// `testAFullSearchCycleThroughM1EvictsNothingAndReturnsToRest` and
    /// `testANetFoldAfterOurUnfoldIsRecordedAndSelfClears` — including
    /// runs where it was moved to run *first*, and runs with far more than
    /// two warm-up rounds, ruling out process warm-up as the cause. What the
    /// early-exit wait left behind was the field's own trailing frame-change
    /// notifications (M2), still in flight into the very next attempt's own
    /// press, so `spinFixed(_:)` below always pumps a fixed two full
    /// seconds, never exiting early, both after the press (waiting only for
    /// the editor, not a large fixed pump first) and after the close —
    /// confirmed by running the exact same scenario with only that change,
    /// three consecutive `bash Scripts/test.sh` passes of this file's own
    /// filter, third position included. A clean, un-evicted forced attempt
    /// simply returns to the same four-segment rest and is retried from
    /// there.
    /// A fixed span of real run-loop time, pumped unconditionally rather than
    /// exited early the moment some condition first reads true — measured
    /// against this exact test, this Mac: an early exit on `segmentCount(bar)
    /// == 4` left the field's own trailing frame-change notifications (M2)
    /// still in flight into the *next* attempt's own press, which read as
    /// `tookMagnifierPress` failing or the editor never arriving on a later
    /// attempt for no reason the attempt itself could see; two full seconds,
    /// every time, is long enough that whatever this round set in motion has
    /// finished before the next one presses anything.
    private func spinFixed(_ interval: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testARefusalDoesNotOutliveTheInteractionThatEarnedIt() {
        let savedWait = SettingsToolbar.searchCollapseWait
        defer { SettingsToolbar.searchCollapseWait = savedWait }

        // Pay whatever this process's own first-use cost is on two
        // throwaway rigs, fully discarded before the rig under test ever
        // mounts — see this method's own header for why the rig under test
        // cannot pay this cost for itself.
        for _ in 0..<2 {
            AppLanguage.only(.en) {
                let warmRig = mountSplit(pane: 760)
                settle(warmRig.window, turns: 30)
                guard let warmBar = warmRig.window.toolbar,
                      let warmSearch = warmBar.items.compactMap({ $0 as? NSSearchToolbarItem }).first,
                      let warmEvent = magnifierClick(warmRig.window, searchItem: warmSearch)
                else { return }
                _ = warmRig.toolbar.tookMagnifierPress(warmEvent)
                let editorDeadline = Date().addingTimeInterval(2)
                while Date() < editorDeadline, warmSearch.searchField.currentEditor() == nil {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                warmSearch.endSearchInteraction()
                spinFixed()
                warmRig.window.toolbar = nil
                warmRig.window.close()
            }
        }

        AppLanguage.only(.ru) {
            let rig = mountSplit(pane: 646, content: mechanismFixtureContent())
            settle(rig.window, turns: 30)
            guard let bar = rig.window.toolbar,
                  let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first
            else {
                XCTFail("no toolbar or search item")
                return
            }
            XCTAssertEqual(segmentCount(bar), 4, "precondition: not resting full at 646 pt, ru")

            // Round 0: defeat the wait gate on purpose, repeating a bounded
            // number of times until AppKit actually evicts — see this
            // method's own header for why one attempt is not enough to
            // promise that.
            SettingsToolbar.searchCollapseWait = 0
            var forcedEviction = false
            for _ in 0..<8 {
                guard let event = magnifierClick(rig.window, searchItem: searchItem) else { continue }
                _ = rig.toolbar.tookMagnifierPress(event)
                let editorDeadline = Date().addingTimeInterval(2)
                while Date() < editorDeadline, searchItem.searchField.currentEditor() == nil {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                searchItem.endSearchInteraction()
                spinFixed()
                if segmentCount(bar) == 1, rig.toolbar.gateRefusedCount > 0 {
                    forcedEviction = true
                    break
                }
            }
            XCTAssertTrue(forcedEviction, """
                forcing the wait gate to zero across 8 attempts never produced an eviction to \
                attribute — this round is not exercising what it means to
                """)
            XCTAssertGreaterThan(rig.toolbar.gateRefusalsRecorded, 0, """
                forcing the wait gate to zero never produced an eviction to attribute — this round is \
                not exercising what it means to
                """)
            XCTAssertEqual(segmentCount(bar), 1, """
                precondition: the forced eviction did not leave the tabs folded and refused — nothing \
                below is testing a stale refusal
                """)

            // Round 1: restore the production wait and run one ordinary
            // cycle — a genuinely *new* interaction, at the identical room,
            // field width, language and style the round above was refused
            // at.
            SettingsToolbar.searchCollapseWait = savedWait
            guard let secondEvent = magnifierClick(rig.window, searchItem: searchItem) else {
                XCTFail("could not place a second synthetic press on the field")
                return
            }
            if !rig.toolbar.tookMagnifierPress(secondEvent) {
                // The field is still visibly expanded from round 0 — folded
                // tabs leave it resting wide (`searchRoomBudget(_:)`'s own
                // header) — so M1's own fold-and-open branch, which requires
                // `field.isHidden`, has nothing to do here, exactly as a
                // real click on an already-visible field would not need M1
                // to open anything either.
                searchItem.beginSearchInteraction()
            }
            let editorDeadline = Date().addingTimeInterval(2)
            while Date() < editorDeadline, searchItem.searchField.currentEditor() == nil {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            searchItem.endSearchInteraction()
            spinFixed()
            XCTAssertEqual(segmentCount(bar), 4, """
                the next interaction at the same room, field width, language and style was still \
                refused — a refusal that outlives the interaction that earned it is the latch this \
                mechanism must not reintroduce
                """)
            rig.window.toolbar = nil
            rig.window.close()
        }
    }

    /// **A page with tabs and no search field must be able to unfold again,
    /// not only fold.** `settle(_:)` used to return before its own unfold
    /// decision whenever `bar.searchItem` was `nil` — the shape Hosts and
    /// Leftovers both declare, tabs and actions with no search — so once
    /// `checkOverflow()`'s fold-only KVO net evicted such a page's tabs
    /// once, nothing else in this file ever offered them the room back, and
    /// they stayed compact for the rest of the session however wide the
    /// window then grew. Mutation: put the old
    /// `guard let searchItem = bar.searchItem else { … return }` back at the
    /// top of `settle(_:)`, and this test goes red — confirmed by running
    /// that mutant.
    func testASearchlessPagesTabsUnfoldOnceThereIsRoomAgain() {
        let rig = mountSplit(pane: 420, content: searchlessMechanismFixtureContent())
        defer { rig.window.orderOut(nil); rig.window.toolbar = nil }
        guard let bar = rig.window.toolbar else {
            return XCTFail("no toolbar attached")
        }
        XCTAssertNil(bar.items.first { $0.itemIdentifier.rawValue == "helm.search" }, """
            precondition: this page must declare no search item at all, or this is not the \
            shape the fix is about
            """)

        settleUntil(rig.window) { segmentCount(bar) == 1 }
        XCTAssertEqual(segmentCount(bar), 1, """
            precondition: the four tabs did not fold at 420 pt with no search field on the bar — \
            widen the room below would prove nothing about an unfold
            """)

        rig.window.setContentSize(NSSize(width: 1200 + Self.sidebarWidth, height: 700))
        settleUntil(rig.window) { segmentCount(bar) == 4 }
        XCTAssertEqual(segmentCount(bar), 4, """
            the tabs never unfolded again once there was plenty of room — a searchless page's \
            tabs only ever fold, through checkOverflow()'s own KVO net, when settle(_:)'s unfold \
            decision is skipped for having no search item to gate on
            """)
    }

    /// **A search-less page's own fold prediction must be anchored on
    /// `currentToolbarSlack(_:)` too, not fall back to the `offeredRoom()`
    /// arithmetic just because there is no search item to read.**
    /// `predictedSlack(bar:tabsWidth:)` used to take the anchored branch only
    /// when `bar.searchItem` was non-nil, so a page with tabs and actions but
    /// no search field (Hosts, Leftovers) always fell back to the older
    /// arithmetic below, which has no notion of AppKit's own inter-item
    /// spacing and overcounts the real room by about 8 pt — that spacing
    /// itself, which no item's frame ever reports — enough to clear
    /// `unfoldMargin` where AppKit still evicts. `settle(_:)` then predicts
    /// room that is not there, unfolds, and AppKit evicts the tabs right
    /// back — one unfold→evict→refold blink, the exact flicker this
    /// mechanism exists to prevent, on the one shape that never has a search
    /// field to anchor against.
    ///
    /// **A single jump straight to a wide pane, as the test above does, never
    /// reproduces this** — AppKit is never asked to lay anything out at the
    /// widths in between, and the blink lives in a band of intermediate
    /// widths where the fallback arithmetic claims room that AppKit disputes.
    /// This sweeps the pane upward in small, fixed steps instead, settling
    /// after each one, and counts `gateRefusalsRecorded` — incremented only
    /// by `checkOverflow()` attributing a fold to our own recent unfold — to
    /// tell a clean unfold apart from a blink.
    ///
    /// **The subject before the absence.** `gateRefusalsRecorded` staying put
    /// is silent about a prediction so pessimistic that the tabs never
    /// unfold at all — that passes the refusal count for the same reason a
    /// reader that never opens a door cannot be locked out of it. The first
    /// assertion below is that the tabs actually reached their full width by
    /// 700 pt; only once that is true does the refusal count mean "unfolded
    /// cleanly" rather than "never tried".
    ///
    /// Mutation, confirmed by running it against a copy of the fixed tree and
    /// restoring from that copy afterward, never with `git checkout`: put the
    /// `let searchItem = bar.searchItem` requirement back onto the anchored
    /// branch in `predictedSlack(bar:tabsWidth:)`, and this test goes red in
    /// both languages swept below — this Mac, that mutant blinks (folds one
    /// step before unfolding to stay) at 588 pt in Russian and 528 pt in
    /// German, `gateRefusalsRecorded` moving 0→1 at each; with the anchored
    /// branch restored, the identical sweep unfolds cleanly in both — 594 pt
    /// Russian, 534 pt German — with `gateRefusalsRecorded` unmoved throughout.
    /// A second mutant, appending `- (bar.searchItem == nil ? 150 : 0)` to
    /// the anchored branch's own return line so it stays far too pessimistic
    /// without ever reading as the old bug — confirmed the same way: on this
    /// Mac Russian's tabs stay folded through the whole sweep
    /// (`segmentCount(bar) == 1` at 700 pt) while `gateRefusalsRecorded`
    /// never moves either, which the segment-count assertion below catches
    /// and the refusal count alone would not; German's slack recovers enough
    /// by 700 pt to unfold anyway under the same mutant, so it passes both
    /// assertions there and proves nothing about this particular mutant on
    /// its own — the two languages are not interchangeable witnesses for
    /// every defect this test can catch.
    func testASearchlessPagesFoldPredictionIsAnchoredAcrossAWholeSweep() {
        for language: AppLanguage in [.ru, .de] {
            AppLanguage.only(language) {
                let rig = mountSplit(pane: 420, content: searchlessMechanismFixtureContent())
                defer { rig.window.orderOut(nil); rig.window.toolbar = nil }
                guard let bar = rig.window.toolbar else {
                    XCTFail("\(language): no toolbar attached")
                    return
                }
                XCTAssertNil(bar.items.first { $0.itemIdentifier.rawValue == "helm.search" }, """
                    \(language) precondition: this page must declare no search item at all, or \
                    this is not the shape the fix is about
                    """)

                settleUntil(rig.window) { segmentCount(bar) == 1 }
                XCTAssertEqual(segmentCount(bar), 1, """
                    \(language) precondition: the four tabs did not fold at 420 pt with no search \
                    field on the bar — sweeping upward from here would prove nothing about a blink
                    """)

                let before = rig.toolbar.gateRefusalsRecorded
                var pane: CGFloat = 420
                while pane < 700 {
                    pane += 6
                    rig.window.setContentSize(NSSize(width: pane + Self.sidebarWidth, height: 700))
                    settle(rig.window, turns: 20)
                }
                XCTAssertEqual(segmentCount(bar), 4, """
                    \(language): the tabs were still folded at 700 pt after the sweep — a \
                    prediction too pessimistic to ever unfold is invisible to the refusal count \
                    below, which only proves a blink did not happen, never that room was offered \
                    back at all
                    """)
                XCTAssertEqual(rig.toolbar.gateRefusalsRecorded, before, """
                    \(language): sweeping the pane from 420 to 700 pt attributed \
                    \(rig.toolbar.gateRefusalsRecorded - before) fold(s) to our own unfold — a \
                    search-less page's tabs blinked open then shut, the flicker this mechanism \
                    exists to prevent, which only the anchored `currentToolbarSlack` reading (not \
                    the `offeredRoom()` fallback) rules out for a bar with no search item
                    """)
            }
        }
    }

    // MARK: - `.windowTitle` has no name item, and used to anchor on nothing

    /// **`.windowTitle` draws the page's name as the window's own inline
    /// title (`SettingsWindow.applyTitle(_:)`) rather than as a toolbar
    /// item, so `bar.nameItem` is `nil` for the whole life of a bar built
    /// under it** (`identifiers(content:style:)`'s own `if style ==
    /// .moduleName { list.append(nameID) }`). Before this test's own fix,
    /// `currentToolbarSlack(_:)` read that absence as "no anchor" and
    /// `predictedSlack(bar:tabsWidth:)` fell through to the `offeredRoom()`
    /// arithmetic for every bar under this style — an arithmetic with no
    /// notion of the title AppKit was actually drawing in that same leading
    /// zone. Against Homebrew's real shape (three tabs, one hidden action,
    /// one shown, a search field) in Russian, swept in half-point steps
    /// across AppKit's own fold point for this exact fixture, that fallback
    /// predicted room that was not there and unfolded straight into an
    /// eviction at every single step — this test, run before
    /// `currentToolbarSlack(_:)` learned to read the window's own title
    /// (`windowTitleMaxX(_:)`), read 11 evictions and 11 refusals recorded
    /// across the 24-step sweep below (`gateRefusalsRecorded` moving from 1
    /// to 12), confirmed by running it against the tree as found.
    ///
    /// **The sweep does assert the tabs end full again, but not at
    /// `evictionPane` itself** — a first version of this fix anchored
    /// `.windowTitle` on `NSToolbarTitleView`'s own current, already-grown
    /// frame, which is not the title's width (`windowTitleMaxX(_:)`'s own
    /// header, "The container's own `bounds.width` is not this title's
    /// width"). `PageBar.titleGrowth` and `SettingsToolbar
    /// .unfoldWorstCaseMargin` are what discount that growth back out of the
    /// prediction, and doing so is deliberately more cautious than the plain
    /// `unfoldMargin` right at this exact threshold — a room this close to
    /// where AppKit itself just folded is exactly where the container's own
    /// not-yet-reversed growth is largest relative to how much real slack is
    /// actually behind it. Measured directly on this fixture, this Mac,
    /// Russian (`swift test --filter
    /// testTheWindowTitleStyleNeverBlinksAcrossASweepAtAppKitsOwnEvictionWidth`):
    /// the tabs come back at 8 pt above `evictionPane`, inside the
    /// `unfoldMargin` cap this test allows itself, with zero evictions
    /// recorded anywhere from `evictionPane − 6` up through the recovery.
    ///
    /// **The eviction pane is found by probing this exact fixture, not
    /// carried in as a literal** — AppKit's own fold point for this shape
    /// depends on this fixture's sidebar width, minimum thickness and this
    /// Mac's own font metrics, and a copied number silently stops meaning
    /// anything the day any of those move. The search walks downward from a
    /// pane comfortably full until the tabs first go compact — one pt wider
    /// than that is `evictionPane`, confirmed resting full (AppKit's own
    /// judgment, no sweep yet) before the half-point sweep below ever moves
    /// the window.
    /// **The owner's own reported gesture (search press, then close), under
    /// `.windowTitle`, at panes wide enough that nothing here is close to
    /// AppKit's own fold threshold.** Before `currentToolbarSlack(_:)` learned
    /// to discount a `.windowTitle` title container's own unreturned growth
    /// (`SettingsToolbar.unfoldWorstCaseMargin`'s own header), this exact
    /// cycle left the tabs compact for good at both these panes, in Russian —
    /// M1 folds on every press regardless of room, and the prediction that
    /// should have unfolded them back on close instead read a phantom eviction
    /// risk from the container's own inflated frame. Confirmed by running this
    /// against that tree: `everFalse` true for `tabs` at both 646 and 700 pt,
    /// and `segmentCount(bar)` never returning to 3.
    func testAMagnifierPressAndCloseUnfoldsCleanlyUnderWindowTitle() {
        AppSettings.pageBarStyle = .windowTitle
        AppLanguage.only(.ru) {
            for pane: CGFloat in [646, 700] {
                let rig = mountSplit(pane: pane)
                rig.window.title = "Homebrew"
                rig.window.subtitle = "3"
                rig.window.titleVisibility = .visible
                settle(rig.window, turns: 30)
                guard let bar = rig.window.toolbar,
                      let searchItem = bar.items.compactMap({ $0 as? NSSearchToolbarItem }).first,
                      let event = magnifierClick(rig.window, searchItem: searchItem)
                else {
                    XCTFail("ru pane \(pane): no toolbar or search item to press")
                    continue
                }
                let watch = VisibilityWatch(namedItems(bar))
                _ = rig.toolbar.tookMagnifierPress(event)
                _ = spinUntilEditorArrives(searchItem)
                settle(rig.window, turns: 40)
                searchItem.endSearchInteraction()
                settleUntil(rig.window, turns: 200) { segmentCount(bar) == 3 }
                XCTAssertEqual(segmentCount(bar), 3, """
                    ru pane \(pane): the tabs did not return to 3 segments after one magnifier \
                    press and close — this is the latch `unfoldWorstCaseMargin` exists to rule out
                    """)
                for (name, everFalse) in watch.everFalse {
                    XCTAssertFalse(everFalse, """
                        ru pane \(pane): the \(name) item went invisible during the press/close \
                        cycle — an eviction, not merely a latch
                        """)
                }
                rig.window.toolbar = nil
                rig.window.close()
            }
        }
    }

    func testTheWindowTitleStyleNeverBlinksAcrossASweepAtAppKitsOwnEvictionWidth() {
        AppSettings.pageBarStyle = .windowTitle

        AppLanguage.only(.ru) {
            let rig = mountSplit(pane: 700)
            // `mountSplit` always hides the title (a raw window, not
            // `SettingsWindow`) — set here the same way
            // `SettingsWindow.applyTitle(_:)` sets it for `.windowTitle`,
            // after the toolbar already exists, since a real page's title
            // arrives no earlier than that either.
            rig.window.title = "Homebrew"
            rig.window.subtitle = "3"
            rig.window.titleVisibility = .visible
            settle(rig.window, turns: 30)
            guard let bar = rig.window.toolbar else {
                XCTFail("ru: no toolbar")
                return
            }
            XCTAssertEqual(segmentCount(bar), 3, """
                ru precondition: not resting full at 700 pt under .windowTitle — sweeping downward \
                from here would prove nothing about a real edge
                """)

            var probe: CGFloat = 616
            rig.window.setContentSize(NSSize(width: probe + Self.sidebarWidth, height: 700))
            settle(rig.window, turns: 20)
            while probe > 560, segmentCount(bar) == 3 {
                probe -= 1
                rig.window.setContentSize(NSSize(width: probe + Self.sidebarWidth, height: 700))
                settle(rig.window, turns: 20)
            }
            XCTAssertNotEqual(segmentCount(bar), 3, """
                ru: never found AppKit's own fold point searching down to 560 pt — nothing below \
                sweeps a real edge
                """)
            // **The tabs did rest full one pt above the fold point** — read
            // from the search above, before the sweep below ever ran: the
            // last iteration that read `segmentCount(bar) == 3` was exactly
            // `probe + 1`. `evictionPane` is not re-measured against a live,
            // already-folded bar (which would read the unfold side of the
            // hysteresis this class's own `unfoldMargin` intentionally
            // carries, not the fold point itself).
            let evictionPane = probe + 1

            let watch = VisibilityWatch(namedItems(bar))
            let before = rig.toolbar.gateRefusalsRecorded
            var steps: [CGFloat] = []
            var pane = evictionPane
            while pane > evictionPane - 6 { pane -= 0.5; steps.append(pane) }
            while pane < evictionPane { pane += 0.5; steps.append(pane) }
            for step in steps {
                rig.window.setContentSize(NSSize(width: step + Self.sidebarWidth, height: 700))
                settle(rig.window, turns: 20)
            }
            // **Keep offering room past `evictionPane` until the tabs
            // actually take it, capped well inside the verifier's own
            // tolerance ("within about `unfoldMargin` of the inert oracle's
            // T")** — `unfoldWorstCaseMargin`'s own worst-case gate is
            // deliberately more cautious than the plain, single-gap
            // `unfoldMargin` right at this exact threshold (its own header
            // has why crediting a `.windowTitle` container's unreturned
            // growth in full is what evicted `actions` here before this
            // gate existed), so recovery lands a few points above
            // `evictionPane` rather than at `evictionPane` itself. Measured
            // on this fixture, this Mac, Russian (`swift test --filter
            // testTheWindowTitleStyleNeverBlinksAcrossASweepAtAppKitsOwnEvictionWidth`):
            // 8 pt above `evictionPane`, comfortably inside the 16 pt cap
            // below and with zero evictions recorded anywhere in the search.
            var recoveryPane = evictionPane
            while recoveryPane < evictionPane + SettingsToolbar.unfoldMargin, segmentCount(bar) != 3 {
                recoveryPane += 1
                rig.window.setContentSize(NSSize(width: recoveryPane + Self.sidebarWidth, height: 700))
                settle(rig.window, turns: 20)
            }

            // **The subject before the absence** (`CLAUDE.md`'s own rule,
            // and `testASearchlessPagesFoldPredictionIsAnchoredAcrossAWholeSweep`'s
            // own precedent for the identical shape of check) — an anchor
            // that never unfolds at all (or only far above this band) would
            // pass every assertion below by never trying, which is not the
            // invariant this test exists to prove.
            XCTAssertEqual(segmentCount(bar), 3, """
                ru: the tabs were still folded at \(recoveryPane) pt, \(SettingsToolbar.unfoldMargin) pt above \
                \(evictionPane) — an anchor too pessimistic to unfold this close to AppKit's own \
                threshold is invisible to the refusal count below, which only proves a blink did \
                not happen, never that room was offered back at all
                """)

            for (name, everFalse) in watch.everFalse {
                XCTAssertFalse(everFalse, """
                    ru: the \(name) item went invisible somewhere between \(evictionPane) pt and \
                    \(recoveryPane) pt — an eviction, the flicker `.windowTitle` used to have no \
                    anchor to rule out
                    """)
            }
            XCTAssertEqual(rig.toolbar.gateRefusalsRecorded, before, """
                ru: sweeping from \(evictionPane) pt to \(recoveryPane) pt attributed \
                \(rig.toolbar.gateRefusalsRecorded - before) fold(s) to our own unfold — an unfold \
                predicted from an unanchored `.windowTitle` reading with no drawn title accounted for
                """)
            rig.window.toolbar = nil
            rig.window.close()
        }
    }
}
