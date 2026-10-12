import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings window the app builds, with no bar named to its initialiser, wears the app-owned toolbar
/// and mounts no page bar: a page switch assigns it exactly one toolbar and a return reuses the object, the
/// name starts sixteen points past the pane, the pane starts where AppKit's strip ends and Helm adds nothing
/// to it, the tabs wear AppKit's own cell under Liquid Glass, and only the toolbar's file asks for that cell.** The real window
/// is built and never ordered, and nothing in it is key. Every row that builds the window prints «no toolbar
/// on the window» when the window wears none, so a window that does not is a red row and not a crash on a
/// nil; `testNothingButTheToolbarsFileAsksForTheSystemsCell` builds no window and reads the sources.
///
/// What an unshown window cannot hold is not asserted here: a toolbar's layout in a key window, the glass
/// and the flat look drawn, a press, and every motion.
@MainActor
final class TheWindowWearsTheToolbarTests: XCTestCase {

    private func build(file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        SettingsWindowRig.buildAsTheAppDoes(in: self, failure: SettingsWindowRig.noShell, file: file, line: line)
    }

    // MARK: - The window wears the toolbar

    /// **As built, the window has a toolbar whose delegate is the app's own, and the card's clip holds no page
    /// bar.** Both halves are asserted apart, so a window that wears a toolbar beside a bar, and one that wears
    /// neither, each fail by their own sentence.
    func testTheWindowTheAppBuildsWearsAToolbarAndMountsNoPageBar() throws {
        guard let rig = build() else { return }
        rig.settle()
        let bars = rig.shell.shell.clip.subviews.compactMap { $0 as? ShellPageBarView }
        XCTAssertTrue(bars.isEmpty, "the card's clip holds \(bars.count) page bars beside the window's toolbar")
        guard let toolbar = rig.worn("the window holds \(bars.count) page bars in its clip and nothing in its title bar")
        else { return }
        XCTAssertTrue(toolbar.delegate is SettingsToolbar,
                      "the window's toolbar is not the settings toolbar's: its delegate is \(String(describing: toolbar.delegate))")
        XCTAssertFalse(toolbar.items.isEmpty, "the window's toolbar holds no item: it shows nothing")
    }

    // MARK: - One assignment for a page switch

    /// **A page switch assigns the window exactly one toolbar and a return to a page puts back the object that
    /// page had; a resize and a declare on the page on screen assign none.** Both pages declare before either
    /// is selected, so a switch is one assignment and not the name-only bar followed by the page's own. The
    /// count is KVO on `toolbar` over the whole turn after each step, the settle that follows it included. A
    /// fold of the sidebar is not a step here: it moves the pane's leading edge and with it whether the bar
    /// carries a spacer.
    func testAPageSwitchAssignsOneToolbarAndAReturnReusesTheObject() throws {
        guard let rig = build() else { return }
        let window = rig.window
        rig.declare("probe.a", search: true)
        rig.declare("probe.b", search: false)
        rig.settle()
        SettingsWindowRig.pump()
        guard let general = rig.worn("no assignment was counted on a window that wore nothing") else { return }

        var assigned = 0
        let kvo = window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { assigned += 1 } }
        defer { kvo.invalidate() }

        var ran = 0
        func step(_ name: String, expecting count: Int, _ body: () -> Void) {
            let before = assigned
            body()
            SettingsWindowRig.pump()
            ran += 1
            XCTAssertEqual(assigned - before, count, "step \(name) assigned the window \(assigned - before) toolbars, not \(count)")
        }

        step("A switch General->A", expecting: 1) { rig.model.selection = .module("probe.a") }
        XCTAssertEqual(rig.model.selection, .module("probe.a"), "the first step never moved the selection")
        let pageA = window.toolbar
        XCTAssertNotNil(pageA, "step A left no toolbar on the window")
        XCTAssertFalse(pageA === general, "step A left General's toolbar on the window: the page got no bar of its own")

        step("B switch A->B", expecting: 1) { rig.model.selection = .module("probe.b") }
        let pageB = window.toolbar
        XCTAssertFalse(pageB === pageA, "step B left page A's toolbar on the window")
        XCTAssertNotNil(pageB, "step B left no toolbar on the window")

        step("C return B->A", expecting: 1) { rig.model.selection = .module("probe.a") }
        XCTAssertTrue(window.toolbar === pageA,
                      "step C put another toolbar on the window than page A's own: \(String(describing: window.toolbar)) is not \(String(describing: pageA))")

        step("D declare on the page on screen", expecting: 0) { rig.declare("probe.a", search: true, selected: "updates") }
        XCTAssertTrue(window.toolbar === pageA, "step D replaced the toolbar of the page on screen")

        step("E resize", expecting: 0) {
            window.setContentSize(NSSize(width: 880, height: 620))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(window.toolbar === pageA, "step E replaced the toolbar of the page on screen")
        XCTAssertEqual(ran, 5, "not all five steps ran")
    }

    /// **A page switch that gives the window a toolbar is counted by the shell as the same number of calls of
    /// `barWasAttached()`.** The shell is laid out until it asks for none, the window's `toolbar` is observed
    /// by KVO, and one page switch (both pages declared first, so the switch is one assignment and not the
    /// name-only bar followed by the page's own) is made. Then the assignments are counted, at least one is
    /// required, and `barAttachments` must have grown by exactly that many. That count is what holds the call:
    /// with the window's `barAttached` closure emptied the count stays where it was. A second assertion reads
    /// that a layout of the shell is pending after the switch, which holds that and no more: other causes in
    /// the turn set `needsLayout` too, and with the closure emptied it is still true. Nothing here is a shown
    /// window and nothing reads where the buttons stand.
    func testAWindowTakingABarAsksTheShellForALayout() throws {
        guard let rig = build() else { return }
        rig.declare("probe.a", search: true)
        rig.declare("probe.b", search: false)
        rig.settle()
        let shell = rig.shell.shell
        for _ in 0..<3 where shell.needsLayout { rig.settle() }
        guard rig.worn("no bar was taken, so no call could be counted") != nil else { return }
        XCTAssertFalse(shell.needsLayout, "the shell was still waiting for a layout before the switch: the row would read an old request")

        var assigned = 0
        let kvo = rig.window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { assigned += 1 } }
        defer { kvo.invalidate() }
        let told = shell.barAttachments

        rig.model.selection = .module("probe.a")
        XCTAssertEqual(rig.model.selection, .module("probe.a"), "the switch never moved the selection: no bar was asked for")
        guard rig.worn("the switch left no toolbar on the window") != nil else { return }
        XCTAssertGreaterThan(assigned, 0, "the switch assigned the window no toolbar: nothing was taken, so there was no call to count")
        XCTAssertEqual(shell.barAttachments - told, assigned,
                       "the window took \(assigned) toolbars in the switch and told the shell \(shell.barAttachments - told) times, not as many")
        XCTAssertTrue(shell.needsLayout, "after the switch the shell has no layout pending")
    }

    // MARK: - Where the name starts

    /// **At a sidebar of 200 the name starts sixteen past the pane.** The toolbar's items start where the seed
    /// says (an unshown window never reads them again) and the leading spacer item is as wide as the pane's
    /// edge plus sixteen less that start, so the name's left edge is the sum, 216 in window x, read here from
    /// the item and not from a frame, which a window nobody ordered does not give.
    func testAtTwoHundredTheNameStartsSixteenPastThePane() throws {
        guard let rig = build() else { return }
        rig.settle()
        guard let toolbar = rig.worn("no spacer item was read, so no name start") else { return }
        let card = rig.shell.shell.card.frame
        XCTAssertEqual(card.minX, 200, accuracy: 0.5, "the card's edge is \(card.minX), not the sidebar's 200: the row stands at another width")
        guard let owner = toolbar.delegate as? SettingsToolbar else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no item start was read")
            return
        }
        guard let spacer = SettingsWindowRig.item("helm.leadingSpacer", in: toolbar),
              let width = spacer.view?.constraints.first(where: { $0.firstAttribute == .width && $0.secondItem == nil })?.constant
        else {
            XCTFail("the toolbar's items \(toolbar.items.map(\.itemIdentifier.rawValue)) hold no leading spacer with a width: the name lands where the items start")
            return
        }
        let nameStart = owner.itemsStart + width
        XCTAssertEqual(nameStart, 216, accuracy: 1, "the name starts at window x \(nameStart), not 216")
        XCTAssertEqual(nameStart, card.minX + 16, accuracy: 1,
                       "the name starts at \(nameStart), not sixteen past the pane's edge at \(card.minX)")
    }

    // MARK: - Where the pane starts

    /// **The pane starts where AppKit's strip ends and Helm adds nothing to it.** The pane's own safe area is
    /// the strip's height less the card's gap at the window's top, and the shell adds no inset of its own,
    /// at two window sizes.
    func testThePaneStartsWhereTheStripEndsAndHelmAddsNothing() throws {
        guard let rig = build() else { return }
        rig.settle()
        guard rig.worn("no strip was read, so no pane start") != nil else { return }
        guard let frameView = rig.window.contentView?.superview else {
            XCTFail("the window has no frame view: no strip was read")
            return
        }
        let panes = rig.shell.shell.clip.subviews.filter { !($0 is ShellPageBarView) }
        XCTAssertEqual(panes.count, 1, "the card's clip holds \(panes.count) panes")
        guard let pane = panes.first else { return }
        for size in [NSSize(width: 1060, height: 760), NSSize(width: 880, height: 620)] {
            rig.window.setContentSize(size)
            rig.settle()
            let strip = frameView.bounds.height - rig.window.contentLayoutRect.height
            XCTAssertGreaterThan(strip, 40, "the strip is \(strip) pt at \(size): the window's toolbar made it no taller than a bare title bar")
            XCTAssertEqual(pane.additionalSafeAreaInsets.top, 0, accuracy: 0.01,
                           "Helm adds \(pane.additionalSafeAreaInsets.top) pt to the pane's top safe area at \(size)")
            XCTAssertEqual(pane.safeAreaInsets.top, strip - ShellGeometry.inset, accuracy: 0.5,
                           "the pane's top safe area is \(pane.safeAreaInsets.top) at \(size), not the strip \(strip) less the card's gap")
            if size.width == 1060 {
                XCTAssertEqual(pane.safeAreaInsets.top, 48, accuracy: 1,
                               "the pane's top safe area is \(pane.safeAreaInsets.top), not the 48 the strip of 52 leaves")
            }
        }
    }

    // MARK: - The items a declare reaches

    /// **What a page declared on the window's channel is in the items of the toolbar the window wears once that
    /// page is selected: tabs, actions and, when the page has one, search; a page without search carries none.**
    func testADeclareOnTheWindowsChannelReachesTheAttachedToolbarsItems() throws {
        guard let rig = build() else { return }
        rig.declare("probe.a", search: true)
        rig.declare("probe.b", search: false)
        rig.model.selection = .module("probe.a")
        rig.settle()
        guard let withSearch = rig.worn("no item was read for a page that declared tabs, an action and a search") else { return }
        let ids = withSearch.items.map(\.itemIdentifier.rawValue)
        for want in ["helm.name", "helm.tabs", "helm.actions", "helm.search"] {
            XCTAssertTrue(ids.contains(want), "the toolbar of a page that declared tabs, an action and a search lacks \(want): it holds \(ids)")
        }
        rig.model.selection = .module("probe.b")
        rig.settle()
        let without = rig.window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        XCTAssertTrue(without.contains("helm.tabs"), "the toolbar of a page that declared tabs lacks helm.tabs: it holds \(without)")
        XCTAssertFalse(without.contains("helm.search"), "the toolbar of a page that declared no search holds one: \(without)")
    }

    // MARK: - The tabs' cell

    /// **Under Liquid Glass the tabs in the toolbar are AppKit's own segmented cell, not Helm's flat one.** The
    /// look is pinned to Liquid Glass (with nothing stored the look reads Flat, `HelmBarAppearance.init(stored:)`,
    /// and under Flat the tabs wear Helm's cell: `TheToolbarsItemsFollowTheLookTests`). The single segmented control mounted in the
    /// tabs item is read for the exact class of its cell.
    func testTheTabsWearAppKitsCellInTheToolbar() throws {
        PinnedBarSettings.pin(in: self)
        AppSettings.barAppearance = .liquidGlass
        guard let rig = build() else { return }
        rig.declare("probe.a", search: true)
        rig.model.selection = .module("probe.a")
        rig.settle()
        guard let toolbar = rig.worn("no tabs item was read, so no cell") else { return }
        guard let tabs = SettingsWindowRig.item("helm.tabs", in: toolbar), let host = tabs.view else {
            XCTFail("the toolbar's items \(toolbar.items.map(\.itemIdentifier.rawValue)) hold no tabs item with a view: no cell was read")
            return
        }
        host.layoutSubtreeIfNeeded()
        let controls = host.everyView(ofType: NSSegmentedControl.self)
        XCTAssertEqual(controls.count, 1, "the tabs item holds \(controls.count) segmented controls, not one: no cell was read")
        guard let cell = controls.first?.cell else { return }
        XCTAssertTrue(type(of: cell) == NSSegmentedCell.self,
                      "the tabs in the toolbar wear \(type(of: cell)), not AppKit's NSSegmentedCell")
    }

    /// **Only the toolbar's file asks for the system's cell.** Code is read with comments and string insides
    /// blanked. Outside `Sources/HelmApp/SettingsToolbar.swift`, no code line writes the environment value
    /// that chooses the cell (`\.helmSwitcherCell,`) and none names it beside `systems`; the toolbar's file
    /// names it at least once. Before the scan the reads must hold the settings window's file, the owner and
    /// the switcher's file, so an empty read cannot pass as an absence.
    func testNothingButTheToolbarsFileAsksForTheSystemsCell() throws {
        let owner = "Sources/HelmApp/SettingsToolbar.swift"
        let reads = try SwiftSource.code(under: "Sources")
        let window = reads.first { $0.path == "Sources/HelmApp/SettingsWindow.swift" }
        guard let window, window.text.contains("final class SettingsModel"),
              reads.contains(where: { $0.path == owner }),
              reads.contains(where: { $0.path == "Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift" }) else {
            XCTFail("no source file was read: the absence below is the absence of the reader")
            return
        }
        var inOwner = 0
        var outside: [String] = []
        for read in reads {
            for (index, line) in read.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                guard text.contains("helmSwitcherCell") else { continue }
                if read.path == owner {
                    inOwner += 1
                } else if text.range(of: #"\.helmSwitcherCell\s*,"#, options: .regularExpression) != nil
                            || text.contains("systems") {
                    outside.append("\(read.path):\(index + 1)")
                }
            }
        }
        XCTAssertTrue(outside.isEmpty, "\(outside.count) code lines outside \(owner) ask for the system's cell: \(outside)")
        XCTAssertGreaterThan(inOwner, 0,
                             "no toolbar on the window asks for the system's cell: \(owner) never names helmSwitcherCell, or was not read")
    }
}
