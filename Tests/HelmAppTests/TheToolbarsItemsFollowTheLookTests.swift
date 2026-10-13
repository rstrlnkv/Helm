import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings window the app builds wears one toolbar under both looks, and the look
/// (`AppSettings.barAppearance`) decides what the tabs and the actions in it are made of: under Flat the tabs
/// are Helm's cell on a flat plate with no platter of AppKit's behind them and a press slides the pick, and
/// the capsule is handed the look; under Liquid Glass nothing of that is so and the tabs stay AppKit's cell.
/// A change of look puts a fresh bar on the window exactly once, and a bar built under the other look never
/// comes back, cached or not.**
///
/// The real window is built as the app builds it (`SettingsWindowRig.buildAsTheAppDoes`) and never ordered;
/// the look is pinned through the store by `PinnedBarSettings`, which puts the key back. Every row prints
/// what it could not read («no toolbar on the window», «no tabs item», «no segmented control», «no readable
/// root») and stops there, so a window that wears nothing is a red row and never a crash on a nil nor a green
/// on an empty read.
///
/// **How the capsule's look is read.** The actions item's view is an `NSHostingView`; its root is read through
/// `Mirror` (the stored `_rootView`, and every value type under it: the environment writers' values, the
/// capsule's fields). `leaves(of:)` meets the capsule itself or the row says it did not, so a root that is
/// read as empty is a failure and not an absence of the look. A look handed any other way than a value in the
/// root is not read here.
///
/// **How the toolbar's private state is read.** The cache of page bars, the plate of a bar that is not on the
/// window and the width `settle` measured for the tabs are fields of private types; the rows read them by
/// `Mirror` and by label (`pageBars`, `tabsPlate`, `tabsWidth`, `toolbar`, `actionsModel`,
/// `windowAppearsActive`), and a row that reads none of them fails saying what it could not read.
///
/// **How the fold is driven.** `setTabsFolded` is private, so the fold row narrows the window itself
/// (`setContentSize` under a lowered `contentMinSize`, then a pump) until the toolbar's own settle folds the
/// tabs, and widens it again for the unfold. The reseat is held through what it must leave: the same plate
/// on the item, one control in it wearing Helm's cell, the plate as wide as the strip it holds.
///
/// **How the capsule's host is told apart.** A rebuilt host is a new `NSHostingView`, so the row keeps the
/// view it read before and compares by identity after each flip of the window's activity
/// (`setWindowAppearsActive`); what a flat capsule dims by is the activity its model reads
/// (`HelmToolbarActionsModel.appearsActive`, through `PageBar.actionsModel`). The first attach of a capsule
/// built while the window reads inactive is read by the toolbar assignment that attaches the bar: the host
/// standing at that moment against the host standing after the turn the correction needs.
///
/// **Not asserted, because an unshown window cannot hold it:** anything drawn (the plate's fill, whether
/// AppKit's glass is behind the tabs on a screen, the pick passing over the words), the slide itself (only
/// that the cell was asked, once, for `HelmMotion.interfaceDuration`), `isBordered`'s read-back in a key
/// window (the probe row reads it in an unshown one), that a flat capsule's dim follows the window on a
/// screen without a new host (the rows read the model's activity and that the host is the same view), and the
/// three window buttons across a flip. The unshown window's own activity is not trusted: the first-attach rows
/// tell the toolbar `setWindowAppearsActive(false)` and read its `windowAppearsActive` back before they select
/// the page.
@MainActor
final class TheToolbarsItemsFollowTheLookTests: XCTestCase {

    private typealias Slide = HelmFlatSegmentedCell.Slide
    private typealias Ink = HelmToolbarActionsCapsule.InactiveInk

    // MARK: - Plumbing

    /// The window as the app builds it under `look`, with two pages declared and the first selected.
    private func open(_ look: HelmBarAppearance, file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        PinnedBarSettings.pin(in: self)
        AppSettings.barAppearance = look
        guard let rig = SettingsWindowRig.buildAsTheAppDoes(in: self, failure: SettingsWindowRig.noShell, file: file, line: line) else { return nil }
        rig.declare("probe.a", search: true)
        rig.declare("probe.b", search: false)
        rig.model.selection = .module("probe.a")
        rig.settle()
        return rig
    }

    /// The setting written, and the turns the notification and the settle after it need.
    private func flip(_ rig: SettingsWindowRig, to look: HelmBarAppearance) {
        AppSettings.barAppearance = look
        SettingsWindowRig.pump()
        rig.settle()
    }

    private struct Tabs {
        let item: NSToolbarItem
        let host: NSView
        let control: NSSegmentedControl
    }

    /// The tabs item of the toolbar the window wears and the one segmented control in its view.
    private func tabs(of rig: SettingsWindowRig, file: StaticString = #filePath, line: UInt = #line) -> Tabs? {
        guard let toolbar = rig.worn("no tabs item was read, so no cell", file: file, line: line) else { return nil }
        guard let tabs = SettingsWindowRig.item("helm.tabs", in: toolbar), let host = tabs.view else {
            XCTFail("no tabs item with a view: the toolbar's items are \(toolbar.items.map(\.itemIdentifier.rawValue))",
                    file: file, line: line)
            return nil
        }
        host.layoutSubtreeIfNeeded()
        let controls = host.everyView(ofType: NSSegmentedControl.self)
        guard controls.count == 1, let control = controls.first else {
            XCTFail("no segmented control: the tabs item holds \(controls.count) of them, not one", file: file, line: line)
            return nil
        }
        return Tabs(item: tabs, host: host, control: control)
    }

    /// Every value this value is made of, itself first: the walk goes down through value types (structs,
    /// optionals, enums, tuples) and stops at a reference type, whose fields are somebody's state and not a
    /// view's description.
    private func leaves(of value: Any, depth: Int = 0) -> [Any] {
        guard depth < 12 else { return [] }
        var out: [Any] = [value]
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle != .class else { return out }
        for child in mirror.children { out += leaves(of: child.value, depth: depth + 1) }
        return out
    }

    private struct CapsuleRoot {
        let view: NSView
        let appearances: [HelmBarAppearance]
        let cells: [HelmSwitcherCell]
        let inks: [Ink]
    }

    /// What the actions item's hosting root is made of. nil, with the reason printed, when it cannot be read.
    private func capsule(of rig: SettingsWindowRig, file: StaticString = #filePath, line: UInt = #line) -> CapsuleRoot? {
        guard let toolbar = rig.worn("no capsule was read, so no look", file: file, line: line) else { return nil }
        guard let actions = SettingsWindowRig.item("helm.actions", in: toolbar), let host = actions.view else {
            XCTFail("no actions item with a view: the toolbar's items are \(toolbar.items.map(\.itemIdentifier.rawValue))",
                    file: file, line: line)
            return nil
        }
        guard let root = Mirror(reflecting: host).children.first(where: { $0.label == "_rootView" })?.value else {
            XCTFail("no readable root: the actions item's view is a \(type(of: host)) with no stored root", file: file, line: line)
            return nil
        }
        let all = leaves(of: root)
        guard all.contains(where: { type(of: $0) == HelmToolbarActionsCapsule.self }) else {
            XCTFail("no readable root: the walk of \(type(of: root)) met no HelmToolbarActionsCapsule", file: file, line: line)
            return nil
        }
        return CapsuleRoot(view: host,
                           appearances: all.compactMap { $0 as? HelmBarAppearance },
                           cells: all.compactMap { $0 as? HelmSwitcherCell },
                           inks: all.compactMap { $0 as? Ink })
    }

    private func cellName(_ control: NSSegmentedControl) -> String { control.cell.map { "\(type(of: $0))" } ?? "no cell" }

    /// Whether the control's cell is exactly of this class, not a subclass of it.
    private func cellIs(_ cls: AnyClass, _ control: NSSegmentedControl) -> Bool {
        control.cell.map { type(of: $0) == cls } ?? false
    }

    // MARK: - 1. Under Flat the tabs are Helm's cell on a flat plate

    /// **Under Flat the one segmented control in the tabs item wears `HelmFlatSegmentedCell`, and it stands
    /// inside a `ShellBarPlate` that wears the flat look.** The plate is the item's view or sits under it; the
    /// row asks that it exists once, that its look is Flat and that the control is inside it.
    func testUnderFlatTheTabsWearHelmsCellOnAFlatPlate() throws {
        guard let rig = open(.flat), let tabs = tabs(of: rig) else { return }
        XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, tabs.control),
                      "under Flat the tabs wear \(cellName(tabs.control)), not Helm's HelmFlatSegmentedCell")
        let plates = tabs.host.everyView(ofType: ShellBarPlate.self)
        XCTAssertEqual(plates.count, 1,
                       "under Flat the tabs item's view holds \(plates.count) ShellBarPlates, not one: the tabs stand on no plate (the view is a \(type(of: tabs.host)))")
        guard let plate = plates.first else { return }
        XCTAssertEqual(plate.barAppearance, .flat, "the tabs' plate wears \(plate.barAppearance), not the flat look")
        XCTAssertTrue(tabs.control.isDescendant(of: plate), "the tabs' control does not stand inside the plate")
    }

    /// **Under Flat the tabs item asks for no platter of AppKit's: `isBordered` reads back `false`.** The
    /// read-back is what the probe row measured on the shapes the tabs item may take; where a shape does not
    /// keep it this row is not the one to hold the sentence.
    func testUnderFlatTheTabsItemCarriesNoPlatterOfAppKits() throws {
        guard let rig = open(.flat), let tabs = tabs(of: rig) else { return }
        XCTAssertFalse(tabs.item.isBordered,
                       "under Flat the tabs item still reads isBordered = true: AppKit's platter is behind the tabs (the view is a \(type(of: tabs.host)))")
    }

    // MARK: - 2. A change of look puts a fresh bar on the window once

    /// **A change of look assigns the window exactly one toolbar, a fresh one that wears the new look; the
    /// same look written again assigns none and keeps the object; the change back assigns one more, and that
    /// bar is neither the first nor the second.** The count is KVO on `toolbar` over the turn after each
    /// write, the settle included; every toolbar is kept in a variable, so an identity cannot be a reused
    /// address.
    func testAChangeOfLookPutsAFreshBarOnTheWindowOnceAndTheOtherLooksBarNeverComesBack() throws {
        guard let rig = open(.liquidGlass), rig.worn("no change of look could be counted") != nil else { return }
        let window = rig.window
        let glass = window.toolbar
        guard let glassTabs = tabs(of: rig) else { return }
        XCTAssertTrue(cellIs(NSSegmentedCell.self, glassTabs.control),
                      "precondition — under Liquid Glass the tabs wear \(cellName(glassTabs.control)), not AppKit's cell")

        var assigned = 0
        let kvo = window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { assigned += 1 } }
        defer { kvo.invalidate() }

        flip(rig, to: .flat)
        XCTAssertEqual(assigned, 1, "the change to Flat assigned the window \(assigned) toolbars, not one")
        let flat = window.toolbar
        XCTAssertNotNil(flat, "the change to Flat left no toolbar on the window")
        XCTAssertFalse(flat === glass, "the change to Flat left Liquid Glass's toolbar on the window: no fresh bar was put there")
        if let flatTabs = tabs(of: rig) {
            XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, flatTabs.control),
                          "after the change to Flat the tabs wear \(cellName(flatTabs.control)), not Helm's cell")
        }

        let before = assigned
        flip(rig, to: .flat)
        XCTAssertEqual(assigned - before, 0, "writing the look the window already wears assigned it \(assigned - before) toolbars")
        XCTAssertTrue(window.toolbar === flat, "writing the look the window already wears replaced its toolbar")

        let beforeBack = assigned
        flip(rig, to: .liquidGlass)
        XCTAssertEqual(assigned - beforeBack, 1, "the change back to Liquid Glass assigned the window \(assigned - beforeBack) toolbars, not one")
        let back = window.toolbar
        XCTAssertNotNil(back, "the change back left no toolbar on the window")
        XCTAssertFalse(back === flat, "the change back left Flat's toolbar on the window")
        XCTAssertFalse(back === glass, "the change back put Liquid Glass's first toolbar on the window again: the other look's bar came back")
        if let backTabs = tabs(of: rig) {
            XCTAssertTrue(cellIs(NSSegmentedCell.self, backTabs.control),
                          "after the change back the tabs wear \(cellName(backTabs.control)), not AppKit's cell")
        }
    }

    /// **A page whose bar was built under the other look is not given that bar back on a return.** Page A and
    /// page B each have a bar built under Liquid Glass; the look changes to Flat while B is on screen; the
    /// return to A puts a bar on the window that is not A's first, and its tabs are Helm's; the look changes
    /// back while A is on screen and the return to B puts a bar that is neither B's first nor B's flat one.
    /// One assignment for each page switch.
    func testAPageBuiltUnderTheOtherLookIsNotGivenItsOldBarOnAReturn() throws {
        guard let rig = open(.liquidGlass), rig.worn("no page's bar could be held") != nil else { return }
        let window = rig.window
        let aGlass = window.toolbar
        rig.model.selection = .module("probe.b")
        rig.settle()
        let bGlass = window.toolbar
        XCTAssertFalse(bGlass === aGlass, "precondition — page B was given page A's bar")

        flip(rig, to: .flat)
        let bFlat = window.toolbar
        XCTAssertFalse(bFlat === bGlass, "precondition — the change to Flat left page B's Liquid Glass bar on the window")

        var assigned = 0
        let kvo = window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { assigned += 1 } }
        defer { kvo.invalidate() }
        rig.model.selection = .module("probe.a")
        rig.settle()
        XCTAssertEqual(assigned, 1, "the return to page A assigned the window \(assigned) toolbars, not one")
        let aFlat = window.toolbar
        XCTAssertFalse(aFlat === aGlass, "the return to page A put the bar it had under Liquid Glass back on the window")
        if let flatTabs = tabs(of: rig) {
            XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, flatTabs.control),
                          "after the return the tabs of page A wear \(cellName(flatTabs.control)), not Helm's cell")
        }

        flip(rig, to: .liquidGlass)
        let before = assigned
        rig.model.selection = .module("probe.b")
        rig.settle()
        XCTAssertEqual(assigned - before, 1, "the return to page B assigned the window \(assigned - before) toolbars, not one")
        XCTAssertFalse(window.toolbar === bFlat, "the return to page B put the bar it had under Flat back on the window")
        XCTAssertFalse(window.toolbar === bGlass, "the return to page B put its first Liquid Glass bar back on the window")
        if let glassTabs = tabs(of: rig) {
            XCTAssertTrue(cellIs(NSSegmentedCell.self, glassTabs.control),
                          "after the return the tabs of page B wear \(cellName(glassTabs.control)), not AppKit's cell")
        }
    }

    // MARK: - 3. The capsule is handed the look

    /// **Under Flat the actions capsule's root carries the flat look and the flat inactive ink.**
    func testTheCapsuleIsHandedTheLook() throws {
        guard let rig = open(.flat), let root = capsule(of: rig) else { return }
        XCTAssertTrue(root.appearances.contains(.flat),
                      "under Flat the capsule's root hands it the looks \(root.appearances): the capsule reads the environment's default, Liquid Glass")
        XCTAssertFalse(root.appearances.contains(.liquidGlass), "under Flat the capsule's root hands it Liquid Glass")
        XCTAssertFalse(root.inks.isEmpty, "under Flat the capsule's root carries no flat inactive ink")
    }

    /// **After a change of look the capsule is handed the new look and the ink; under Flat the window's
    /// activity flipping rebuilds no host and the capsule's model reads the activity both ways; under
    /// Liquid Glass it rebuilds the host, and the rebuilt host is handed Liquid Glass and AppKit's cell.**
    /// Liquid Glass to Flat: the fresh bar's host is handed Flat and the flat inactive ink. Then
    /// `setWindowAppearsActive` false, true, false, true: after each step the host is the same view, still
    /// handed Flat and the ink, and the model of the bar on the window (`PageBar.actionsModel`) reads the
    /// activity just told. Back to Liquid Glass: the capsule is handed no Flat; the same four steps each put
    /// a new view on the item, which is handed Liquid Glass, no Flat and AppKit's cell.
    func testAChangeOfLookHandsTheCapsuleItsLookAndOnlyGlassRebuildsItsHostWhenTheWindowsActivityFlips() throws {
        guard let rig = open(.liquidGlass), let glass = capsule(of: rig) else { return }
        XCTAssertFalse(glass.appearances.contains(.flat), "precondition — under Liquid Glass the capsule is handed \(glass.appearances)")

        flip(rig, to: .flat)
        guard let flat = capsule(of: rig) else { return }
        XCTAssertTrue(flat.appearances.contains(.flat), "after the change to Flat the capsule is handed \(flat.appearances), not Flat")
        XCTAssertFalse(flat.inks.isEmpty, "after the change to Flat the fresh bar's host carries no flat inactive ink")
        XCTAssertFalse(flat.view === glass.view, "precondition — the change to Flat left Liquid Glass's host on the item")

        guard let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no activity was told")
            return
        }
        guard let bar = wornBar(of: rig), let model = unwrapped(field("actionsModel", of: bar)) as? HelmToolbarActionsModel else {
            XCTFail("the bar on the window holds no actions model (PageBar.actionsModel is nil, or the field is gone): no activity could be read")
            return
        }
        for active in [false, true, false, true] {
            owner.setWindowAppearsActive(active)
            SettingsWindowRig.pump(0.2)
            XCTAssertEqual(model.appearsActive, active,
                           "under Flat the capsule's model reads appearsActive = \(model.appearsActive) after the window was told \(active)")
            guard let now = capsule(of: rig) else { return }
            XCTAssertTrue(now.view === flat.view,
                          "under Flat the window's activity flipping to \(active) rebuilt the capsule's host: a flat capsule dims by its model and needs no new host")
            XCTAssertTrue(now.appearances.contains(.flat), "under Flat after the activity \(active) the capsule is handed \(now.appearances), not Flat")
            XCTAssertFalse(now.inks.isEmpty, "under Flat after the activity \(active) the capsule carries no flat inactive ink")
        }

        flip(rig, to: .liquidGlass)
        guard let back = capsule(of: rig) else { return }
        XCTAssertFalse(back.appearances.contains(.flat), "after the change back the capsule is handed \(back.appearances): Flat stayed")
        XCTAssertTrue(back.appearances.contains(.liquidGlass), "after the change back the capsule is handed \(back.appearances), not Liquid Glass")
        var standing = back.view
        for active in [false, true, false, true] {
            owner.setWindowAppearsActive(active)
            SettingsWindowRig.pump(0.2)
            guard let now = capsule(of: rig) else { return }
            XCTAssertFalse(now.view === standing,
                           "under Liquid Glass the window's activity flipping to \(active) rebuilt no host: the glass cannot follow the window")
            XCTAssertTrue(now.appearances.contains(.liquidGlass), "the host rebuilt for the activity \(active) is handed \(now.appearances), not Liquid Glass")
            XCTAssertFalse(now.appearances.contains(.flat), "the host rebuilt for the activity \(active) is handed \(now.appearances): Flat stayed")
            XCTAssertTrue(now.cells.contains(.systems), "the host rebuilt for the activity \(active) asks for \(now.cells), not AppKit's cell")
            standing = now.view
        }
    }

    // MARK: - 3b. A capsule first attached while the window reads inactive

    /// The window under `look`, told it is inactive, then a page it has not shown selected: the capsule's host
    /// standing at the instant the page's bar is assigned to the window, and the one standing after the turn
    /// a correction would need. nil, with the reason printed, when either could not be read.
    private func capsuleHosts(attachedWhileInactiveUnder look: HelmBarAppearance,
                              file: StaticString = #filePath, line: UInt = #line) -> (atAttach: NSView, after: NSView)? {
        guard let rig = open(look), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
            XCTFail("no settings toolbar on the window: no first attach was read", file: file, line: line)
            return nil
        }
        owner.setWindowAppearsActive(false)
        rig.settle()
        guard let reading = field("windowAppearsActive", of: owner) as? Bool else {
            XCTFail("the toolbar's windowAppearsActive could not be read (the field is gone)", file: file, line: line)
            return nil
        }
        XCTAssertFalse(reading, "precondition — the window reads active after it was told it is not", file: file, line: line)
        rig.declare("probe.c", search: false)
        var assigned = 0
        var atAttach: NSView?
        let kvo = rig.window.observe(\.toolbar, options: [.new]) { window, _ in
            MainActor.assumeIsolated {
                assigned += 1
                atAttach = window.toolbar.flatMap { SettingsWindowRig.item("helm.actions", in: $0) }?.view
            }
        }
        defer { kvo.invalidate() }
        rig.model.selection = .module("probe.c")
        rig.settle()
        XCTAssertEqual(assigned, 1, "selecting the page assigned the window \(assigned) toolbars, not one", file: file, line: line)
        guard let atAttach else {
            XCTFail("no actions view stood on the toolbar at the instant it was assigned: nothing to compare", file: file, line: line)
            return nil
        }
        guard let after = capsule(of: rig, file: file, line: line) else { return nil }
        return (atAttach, after.view)
    }

    /// **A flat capsule attached while the window reads inactive is not rebuilt: the host standing when its
    /// bar is assigned is the host standing a turn later.** A flat capsule draws no glass, so there is no glass
    /// to correct; the first-attach correction is armed under Liquid Glass only.
    func testAFlatCapsuleFirstAttachedInAnInactiveWindowIsNotRebuilt() throws {
        guard let hosts = capsuleHosts(attachedWhileInactiveUnder: .flat) else { return }
        XCTAssertTrue(hosts.after === hosts.atAttach,
                      "under Flat the capsule's host was rebuilt after its bar was attached to an inactive window: the first-attach correction ran for a capsule with no glass")
    }

    /// **A glass capsule attached while the window reads inactive is rebuilt after its bar is assigned: the
    /// host standing after the settle is not the host standing at the assignment.** The row reads those two
    /// hosts only, not how many rebuilds ran between them. The contrast of the row above: the same steps, the
    /// other look, and the host changes, so the instrument that reads «not rebuilt» there can read «rebuilt».
    func testAGlassCapsuleFirstAttachedInAnInactiveWindowIsRebuilt() throws {
        guard let hosts = capsuleHosts(attachedWhileInactiveUnder: .liquidGlass) else { return }
        XCTAssertFalse(hosts.after === hosts.atAttach,
                       "under Liquid Glass the capsule's host was not rebuilt after its bar was attached to an inactive window: the first-attach correction did not run")
    }

    // MARK: - 4. A press under Flat slides the pick

    /// **A press on the second tab under Flat asks Helm's cell for one slide, from the first segment to the
    /// second, over `HelmMotion.interfaceDuration`.** The press is the control's own action sent (the call a
    /// click ends in), as `APressOnTheBarsStripSlidesItsPickTests` sends it; Reduce Motion is answered `false`
    /// by the cell's seam. What the page then writes is not read here.
    func testAPressUnderFlatSlidesThePick() throws {
        guard let rig = open(.flat), let tabs = tabs(of: rig) else { return }
        XCTAssertEqual(tabs.control.segmentCount, 2, "precondition — the strip is folded or empty, so a press opens a menu")
        XCTAssertEqual(tabs.control.selectedSegment, 0, "precondition — the first draw selects segment \(tabs.control.selectedSegment)")
        guard let cell = tabs.control.cell as? HelmFlatSegmentedCell else {
            XCTFail("no slide could be heard: under Flat the tabs wear \(cellName(tabs.control)), not Helm's HelmFlatSegmentedCell")
            return
        }
        var heard: [Slide] = []
        cell.reducesMotion = { false }
        cell.onSlide = { heard.append($0) }
        tabs.control.selectedSegment = 1
        XCTAssertTrue(tabs.control.sendAction(tabs.control.action, to: tabs.control.target), "the control's own action went nowhere")
        XCTAssertEqual(heard, [Slide(from: 0, to: 1, duration: HelmMotion.interfaceDuration)],
                       "the press asked the cell for \(heard), not for one slide over the interface duration")
    }

    // MARK: - 5. The control: under Liquid Glass the tabs and the capsule stay AppKit's

    /// **Under Liquid Glass the window's tabs and capsule are AppKit's: AppKit's own cell on no plate of
    /// Helm's, the capsule's root asking for AppKit's cell and handed no Flat.** The tabs' cell is read by its
    /// exact class and the capsule's cell from the same root the look is read from, so the reader that finds
    /// no Flat here is shown to reach the capsule's environment at all.
    func testUnderLiquidGlassTheTabsAndTheCapsuleStayAppKits() throws {
        guard let rig = open(.liquidGlass), let toolbar = rig.worn("nothing of the window was read") else { return }
        XCTAssertTrue(toolbar.delegate is SettingsToolbar, "the toolbar's delegate is \(String(describing: toolbar.delegate)), not the settings toolbar")
        let ids = toolbar.items.map(\.itemIdentifier.rawValue)
        for want in ["helm.name", "helm.tabs", "helm.actions", "helm.search"] {
            XCTAssertTrue(ids.contains(want), "the toolbar lacks \(want): it holds \(ids)")
        }
        if let tabs = tabs(of: rig) {
            XCTAssertTrue(cellIs(NSSegmentedCell.self, tabs.control),
                          "under Liquid Glass the tabs wear \(cellName(tabs.control)), not AppKit's NSSegmentedCell")
            XCTAssertTrue(tabs.host.everyView(ofType: ShellBarPlate.self).isEmpty,
                          "under Liquid Glass the tabs item holds a ShellBarPlate of Helm's")
        }
        if let root = capsule(of: rig) {
            XCTAssertTrue(root.cells.contains(.systems), "under Liquid Glass the capsule's root asks for \(root.cells), not AppKit's cell")
            XCTAssertFalse(root.appearances.contains(.flat), "under Liquid Glass the capsule is handed \(root.appearances)")
        }
    }

    /// **Under Liquid Glass the tabs item is still bordered: AppKit's platter is behind AppKit's cell.** A row
    /// of its own, because the read-back of `isBordered` in a window nobody ordered is a reading of AppKit's
    /// and not of Helm's.
    func testUnderLiquidGlassTheTabsItemIsStillBordered() throws {
        guard let rig = open(.liquidGlass), let tabs = tabs(of: rig) else { return }
        XCTAssertTrue(tabs.item.isBordered, "under Liquid Glass the tabs item reads isBordered = false: AppKit's platter is gone")
    }

    // MARK: - Readings of the settings toolbar's private state (Mirror)

    /// A stored field of a value by its label, nil when there is none. The toolbar's cache of page bars and
    /// the page bar's fields are private; `Mirror` reads them as the rig reads the window's.
    private func field(_ label: String, of value: Any) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == label }?.value
    }

    /// An optional's content, the value itself when it is not one; nil for nil.
    private func unwrapped(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional ? mirror.children.first?.value : value
    }

    /// Every page bar the toolbar keeps, with the page key it is kept under.
    private func pageBars(of owner: SettingsToolbar) -> [(key: String, bar: Any)] {
        guard let cache = field("pageBars", of: owner) else { return [] }
        return Mirror(reflecting: cache).children.compactMap { child in
            let pair = Array(Mirror(reflecting: child.value).children)
            guard pair.count == 2, let key = pair[0].value as? String else { return nil }
            return (key, pair[1].value)
        }
    }

    /// The page bar (the toolbar's private `PageBar`) whose `toolbar` is the one the window wears now.
    private func wornBar(of rig: SettingsWindowRig) -> Any? {
        guard let owner = rig.window.toolbar?.delegate as? SettingsToolbar else { return nil }
        return pageBars(of: owner).first { entry in
            (field("toolbar", of: entry.bar) as? NSToolbar) === rig.window.toolbar
        }?.bar
    }

    /// The width `settle` measured for the tabs of the bar the window wears now, in the toolbar's own
    /// measuring view (`PageBar.tabsWidth`), waiting for the settle that measures it. nil when it never did.
    private func measuredTabsWidth(of rig: SettingsWindowRig) -> CGFloat? {
        for _ in 0..<10 {
            if let worn = wornBar(of: rig), let pair = unwrapped(field("tabsWidth", of: worn)),
               let full = field("full", of: pair) as? CGFloat {
                return full
            }
            SettingsWindowRig.pump(0.2)
        }
        return nil
    }

    private func layOutTheToolbar(_ rig: SettingsWindowRig) {
        rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
        rig.window.contentView?.layoutSubtreeIfNeeded()
    }

    // MARK: - 6. The plate is as large as the strip it holds

    /// **Under Flat the tabs item's view is a `ShellBarPlate` that has no size of its own (four constraints
    /// pin the hosting view to its edges); in the toolbar it measures what the strip measures, not zero.**
    /// Read in the window the app builds, never ordered, after a layout of its toolbar: the plate's size
    /// is not empty, is the hosting view's size, is what the hosting view's own intrinsic size asks, holds
    /// the control whole, and its width is what the toolbar's own measuring view
    /// (`PageBar.tabsWidth`, the width `settle` decides the fold by) answered for the same tabs.
    ///
    /// **Why these comparisons are fair, and the one that is not made.** The hosting view and the measuring
    /// view are the same `HelmToolbarSwitcher` over the same segments, style and look, so under Flat both
    /// are Helm's cell and the plate (which adds no padding by construction) must change none of the two
    /// numbers: a gap between the plate and either is the plate's. The same page's tabs under Liquid Glass
    /// are NOT a fair comparison for the size: they are AppKit's cell, which is a different width and
    /// height by design.
    func testUnderFlatThePlateIsAsLargeAsTheStripItHolds() throws {
        guard let rig = open(.flat), let tabs = tabs(of: rig) else { return }
        guard let plate = tabs.item.view as? ShellBarPlate else {
            XCTFail("under Flat the tabs item's view is a \(type(of: tabs.host)), not the plate: no plate was measured")
            return
        }
        guard let strip = plate.content else {
            XCTFail("the tabs' plate holds no content: no strip was measured")
            return
        }
        XCTAssertEqual(tabs.control.segmentCount, 2, "precondition — the strip is folded or empty (\(tabs.control.segmentCount) segments), so the measuring view's full width is not its width")
        layOutTheToolbar(rig)
        plate.layoutSubtreeIfNeeded()
        let size = plate.frame.size
        XCTAssertGreaterThan(size.width, 0, "the plate measures \(size) in the toolbar: it takes no width from the strip")
        XCTAssertGreaterThan(size.height, 0, "the plate measures \(size) in the toolbar: it takes no height from the strip")
        XCTAssertEqual(size.width, strip.frame.width, accuracy: 0.5,
                       "the plate is \(size.width) pt wide and the strip it holds \(strip.frame.width)")
        XCTAssertEqual(size.height, strip.frame.height, accuracy: 0.5,
                       "the plate is \(size.height) pt high and the strip it holds \(strip.frame.height)")
        let asked = strip.intrinsicContentSize
        XCTAssertEqual(size.width, asked.width, accuracy: 1, "the plate is \(size.width) pt wide, the strip asks for \(asked.width)")
        XCTAssertEqual(size.height, asked.height, accuracy: 1, "the plate is \(size.height) pt high, the strip asks for \(asked.height)")
        let box = tabs.control.convert(tabs.control.bounds, to: plate)
        XCTAssertTrue(plate.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box),
                      "the control stands at \(box) outside the plate's \(plate.bounds): the plate clips or misses it")
        XCTAssertGreaterThan(tabs.control.frame.width, 0, "the control measures \(tabs.control.frame.size) inside the plate")
        guard let measured = measuredTabsWidth(of: rig) else {
            XCTFail("the toolbar's measuring view was never read (PageBar.tabsWidth is nil, or the field is gone): no width to compare the plate with")
            return
        }
        XCTAssertEqual(size.width, measured, accuracy: 1,
                       "the plate is \(size.width) pt wide in the toolbar and the toolbar's measuring view says the same tabs are \(measured)")
    }

    // MARK: - 7. The plate follows the window's activity

    /// **The plate of the attached bar and the plate of a bar cached for another page both read the
    /// window's activity after `setWindowAppearsActive`, in both directions.** The sequence false, true,
    /// false, true: whatever the window opened with, it contains changes both ways, and every plate is
    /// read after every step.
    func testThePlatesOfEveryBarFollowTheWindowsActivity() throws {
        guard let rig = open(.flat), let tabs = tabs(of: rig) else { return }
        rig.model.selection = .module("probe.b")
        rig.settle()
        rig.model.selection = .module("probe.a")
        rig.settle()
        guard let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no activity was told")
            return
        }
        guard let attached = tabs.item.view as? ShellBarPlate else {
            XCTFail("under Flat the attached tabs item's view is a \(type(of: tabs.host)), not a plate")
            return
        }
        let bars = pageBars(of: owner)
        let plates: [(key: String, plate: ShellBarPlate)] = bars.compactMap { entry in
            (unwrapped(field("tabsPlate", of: entry.bar)) as? ShellBarPlate).map { (entry.key, $0) }
        }
        XCTAssertGreaterThanOrEqual(plates.count, 2,
                                    "the toolbar keeps \(bars.map(\.key)) and \(plates.count) plates among them: no cached bar of another page was read")
        XCTAssertTrue(plates.contains { $0.plate === attached },
                      "the attached tabs item's plate is not among the plates the toolbar keeps (\(plates.map(\.key)))")
        XCTAssertTrue(plates.contains { $0.plate !== attached },
                      "no plate but the attached one was read: the cached bar's plate could not be told")
        for active in [false, true, false, true] {
            owner.setWindowAppearsActive(active)
            for (key, plate) in plates {
                XCTAssertEqual(plate.isActive, active,
                               "after setWindowAppearsActive(\(active)) the plate of page \(key) reads isActive = \(plate.isActive)\(plate === attached ? " (the attached bar's)" : " (a cached bar's)")")
            }
        }
    }

    // MARK: - 8. The fold keeps the one plate

    /// **A fold of the tabs under Flat keeps the item's view, the one plate, with one control in it that
    /// wears Helm's cell, the plate as wide as the strip it holds and narrower than the whole strip was; the
    /// unfold gives the same plate two segments back.**
    /// The fold is driven by the window itself: its content is narrowed (`contentMinSize` lowered first, so
    /// the narrowing is not clamped) and the toolbar's own settle decides; no seam of `Sources` is used.
    func testTheFoldKeepsTheOnePlateTheControlAndTheCell() throws {
        guard let rig = open(.flat), let before = tabs(of: rig) else { return }
        guard let plate = before.item.view as? ShellBarPlate else {
            XCTFail("under Flat the tabs item's view is a \(type(of: before.host)), not the plate: no fold was tried")
            return
        }
        XCTAssertEqual(before.control.segmentCount, 2, "precondition — the strip is not whole before the narrowing")
        let wide = plate.frame.width
        let startWidth = rig.window.contentLayoutRect.width
        rig.window.contentMinSize = NSSize(width: 100, height: 100)
        var read: [String] = []
        var folded: Tabs?
        for width in [700, 560, 440, 360, 300, 240, 200, 160] as [CGFloat] {
            rig.window.setContentSize(NSSize(width: width, height: rig.window.contentLayoutRect.height))
            SettingsWindowRig.pump(0.5)
            rig.settle()
            layOutTheToolbar(rig)
            guard let now = tabs(of: rig) else { return }
            read.append("\(width) -> window \(rig.window.contentLayoutRect.width), segments \(now.control.segmentCount), item \(now.item.view?.frame ?? .zero)")
            if now.control.segmentCount == 1 { folded = now; break }
        }
        guard let folded else {
            XCTFail("the tabs did not fold in the window the app builds, narrowed from \(startWidth) pt (the plate was \(wide) pt wide): \(read)")
            return
        }
        XCTAssertTrue(folded.item.view === plate, "the fold put \(String(describing: folded.item.view)) on the tabs item, not the plate it held")
        XCTAssertEqual(folded.host.everyView(ofType: NSSegmentedControl.self).count, 1, "the folded plate holds not one control")
        XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, folded.control),
                      "after the fold the tabs wear \(cellName(folded.control)), not Helm's HelmFlatSegmentedCell")
        if let strip = plate.content {
            XCTAssertEqual(plate.frame.width, strip.frame.width, accuracy: 0.5,
                           "after the fold the plate is \(plate.frame.width) pt wide and the strip it holds \(strip.frame.width)")
        }
        XCTAssertLessThan(plate.frame.width, wide - 1, "after the fold the plate is \(plate.frame.width) pt wide, the whole strip was \(wide)")
        XCTAssertGreaterThan(folded.control.frame.width, 0, "the folded control measures \(folded.control.frame.size)")

        rig.window.setContentSize(NSSize(width: max(startWidth, 1100), height: rig.window.contentLayoutRect.height))
        for _ in 0..<6 {
            SettingsWindowRig.pump(0.5)
            rig.settle()
            layOutTheToolbar(rig)
            if tabs(of: rig)?.control.segmentCount == 2 { break }
        }
        guard let after = tabs(of: rig) else { return }
        XCTAssertEqual(after.control.segmentCount, 2,
                       "after the window was widened the tabs hold \(after.control.segmentCount) segments, not the whole strip: \(read)")
        XCTAssertTrue(after.item.view === plate, "the unfold put \(String(describing: after.item.view)) on the tabs item, not the plate it held")
        XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, after.control),
                      "after the unfold the tabs wear \(cellName(after.control)), not Helm's HelmFlatSegmentedCell")
        XCTAssertEqual(plate.frame.width, wide, accuracy: 1, "after the unfold the plate is \(plate.frame.width) pt wide, it was \(wide)")
    }

    // MARK: - 9. The measuring view wears the look's cell and no width crosses looks

    /// **The width the toolbar measures for the tabs is the width of the cell the look puts on them: under
    /// Flat Helm's cell's, under Liquid Glass AppKit's, and a flip there and back brings the first number
    /// back.** The measuring view is private, so the row reads its answer (`PageBar.tabsWidth.full`) beside
    /// the width the tabs item draws. It can tell the two cells apart only if they measure differently, and
    /// says so if they do not.
    func testTheMeasuredTabsWidthIsOfTheCellTheLookPutsOnTheTabs() throws {
        guard let rig = open(.flat), let flat = tabs(of: rig) else { return }
        layOutTheToolbar(rig)
        let drawnFlat = flat.item.view?.frame.width ?? 0
        guard let measuredFlat = measuredTabsWidth(of: rig) else {
            XCTFail("under Flat the toolbar's measuring view was never read (PageBar.tabsWidth is nil): nothing to compare")
            return
        }
        XCTAssertEqual(measuredFlat, drawnFlat, accuracy: 1,
                       "under Flat the measuring view says the tabs are \(measuredFlat) pt and the item draws \(drawnFlat)")

        flip(rig, to: .liquidGlass)
        guard let glass = tabs(of: rig) else { return }
        layOutTheToolbar(rig)
        let drawnGlass = glass.item.view?.frame.width ?? 0
        guard let measuredGlass = measuredTabsWidth(of: rig) else {
            XCTFail("under Liquid Glass the toolbar's measuring view was never read (PageBar.tabsWidth is nil): nothing to compare")
            return
        }
        XCTAssertEqual(measuredGlass, drawnGlass, accuracy: 1,
                       "under Liquid Glass the measuring view says the tabs are \(measuredGlass) pt and the item draws \(drawnGlass)")
        XCTAssertGreaterThan(abs(measuredFlat - measuredGlass), 1,
                             "the two cells measure the same \(measuredFlat) pt: this row cannot tell which cell the measuring view wore")

        flip(rig, to: .flat)
        guard tabs(of: rig) != nil, let again = measuredTabsWidth(of: rig) else {
            XCTFail("after the way back to Flat the measuring view was never read")
            return
        }
        XCTAssertEqual(again, measuredFlat, accuracy: 0.5,
                       "after Flat, Liquid Glass and Flat the measured width is \(again) pt, not the first Flat's \(measuredFlat): a width crossed looks")
    }

    // MARK: - 10. The capsule's segmented entry wears the look's cell

    /// A page whose actions hold Hosts' shape, a `.segmented` entry, and a button.
    private func openWithASegmentedEntry(_ look: HelmBarAppearance) -> SettingsWindowRig? {
        PinnedBarSettings.pin(in: self)
        AppSettings.barAppearance = look
        guard let rig = SettingsWindowRig.buildAsTheAppDoes(in: self, failure: SettingsWindowRig.noShell) else { return nil }
        let content = HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "one", title: "One", symbol: "shippingbox"),
                   HelmToolbarTab(id: "two", title: "Two", symbol: "arrow.up.circle")],
            selectedTab: .constant("one"),
            actions: [HelmToolbarAction(id: "viewMode", title: "View", options: [
                          HelmToolbarTab(id: "table", title: "Table", symbol: "tablecells"),
                          HelmToolbarTab(id: "plain", title: "Plain text", symbol: "doc.plaintext")],
                                        selection: .constant("table")),
                      HelmToolbarAction(id: "refresh", title: "Refresh list", symbol: "arrow.clockwise") {}])
        rig.channel.declare(content, token: "probe.c", generation: rig.channel.nextGeneration())
        rig.model.selection = .module("probe.c")
        rig.settle()
        return rig
    }

    private func entryControls(of rig: SettingsWindowRig, _ look: String) -> [NSSegmentedControl] {
        guard let toolbar = rig.worn("no capsule control was read under \(look)"),
              let actions = SettingsWindowRig.item("helm.actions", in: toolbar), let host = actions.view else {
            XCTFail("under \(look) there is no actions item with a view: no capsule control was read")
            return []
        }
        host.layoutSubtreeIfNeeded()
        let controls = host.everyView(ofType: NSSegmentedControl.self)
        if controls.isEmpty {
            XCTFail("under \(look) the capsule mounted no segmented control (the item's view is a \(type(of: host)) holding \(host.subviews.count) subviews): the entry was not read")
        }
        return controls
    }

    /// **The capsule's `.segmented` entry wears Helm's cell under Flat and AppKit's own under Liquid Glass,
    /// on the same window flipped from one look to the other.** Every segmented control the actions item
    /// holds is read by its cell's exact class.
    func testTheCapsulesSegmentedEntryWearsTheCellOfTheLook() throws {
        guard let rig = openWithASegmentedEntry(.flat) else { return }
        let flat = entryControls(of: rig, "Flat")
        for control in flat {
            XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, control), "under Flat the capsule's segmented entry wears \(cellName(control)), not Helm's HelmFlatSegmentedCell")
        }
        flip(rig, to: .liquidGlass)
        let glass = entryControls(of: rig, "Liquid Glass")
        for control in glass {
            XCTAssertTrue(cellIs(NSSegmentedCell.self, control), "under Liquid Glass the capsule's segmented entry wears \(cellName(control)), not AppKit's NSSegmentedCell")
        }
        flip(rig, to: .flat)
        for control in entryControls(of: rig, "Flat again") {
            XCTAssertTrue(cellIs(HelmFlatSegmentedCell.self, control), "after the way back to Flat the capsule's segmented entry wears \(cellName(control)), not Helm's HelmFlatSegmentedCell")
        }
    }

    // MARK: - What `isBordered = false` reads back on each shape of item

    /// The item shapes the toolbar builds around a hosting view, less the name item's container (a bare `NSView` holding one, told `false`, not probed), and one the tree does not build:
    /// `hosting` is a hosting view told
    /// `isBordered = false`, as the status and actions items are; `plate` is a `ShellBarPlate` holding a
    /// hosting view, as the tabs item is under Flat; `default` is a hosting view never told, as the tabs item
    /// is under Liquid Glass; `segmented` is a bare control told `false`, which no item of the toolbar is, the
    /// contrast that shows the instrument can say `true`.
    @MainActor
    private final class ProbeItems: NSObject, NSToolbarDelegate {
        static let ids = ["hosting", "plate", "segmented", "default"]

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.ids.map { .init($0) } }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.ids.map { .init($0) } }

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            let id = identifier.rawValue
            let item = NSToolbarItem(itemIdentifier: identifier)
            func hosting() -> NSHostingView<Text> {
                let view = NSHostingView(rootView: Text("x"))
                view.sizingOptions = [.intrinsicContentSize]
                return view
            }
            switch id {
            case "hosting", "default":
                item.view = hosting()
            case "plate":
                let plate = ShellBarPlate(appearance: .flat, isActive: true, titlebarIsTransparent: true)
                plate.content = hosting()
                plate.frame = NSRect(x: 0, y: 0, width: 80, height: 30)
                item.view = plate
            default:
                item.view = NSSegmentedControl(labels: ["a", "b"], trackingMode: .selectOne, target: nil, action: nil)
            }
            if id != "default" { item.isBordered = false }
            return item
        }
    }

    /// **`isBordered = false`, set in the delegate call as the app sets it, reads back `false` once the
    /// toolbar is on a window nobody ordered, on an item whose view is an `NSHostingView` or a
    /// `ShellBarPlate` holding one: the shapes of the status, actions and Flat tabs items.** The
    /// name item's container, a bare `NSView` holding a hosting view and told `false`, is a third shape the toolbar builds around a hosting view and is not probed. So
    /// `testUnderFlatTheTabsItemCarriesNoPlatterOfAppKits` reads a value that sticks. The two controls show
    /// the instrument can say `true`: an `NSSegmentedControl` as the item's own view reads `true` after
    /// `= false` (the shape that does NOT keep it), and an item never told reads `true` on a window.
    func testIsBorderedFalseStaysFalseAroundAHostingView() throws {
        let probe = ProbeItems()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "probe.isBordered")
        toolbar.delegate = probe
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(0.3)
        window.contentView?.layoutSubtreeIfNeeded()
        var onWindow: [String: Bool] = [:]
        for id in ProbeItems.ids {
            guard let item = toolbar.items.first(where: { $0.itemIdentifier.rawValue == id }) else {
                XCTFail("no probe item \(id) on the toolbar: it holds \(toolbar.items.map(\.itemIdentifier.rawValue))")
                continue
            }
            onWindow[id] = item.isBordered
        }
        XCTAssertEqual(onWindow.count, ProbeItems.ids.count, "the probe read \(onWindow.count) of \(ProbeItems.ids.count) shapes: \(onWindow)")
        for id in ["hosting", "plate"] {
            XCTAssertEqual(onWindow[id], false, "isBordered = false reads back \(String(describing: onWindow[id])) on the \(id) shape: it is not a shape that keeps it")
        }
        XCTAssertEqual(onWindow["segmented"], true, "the instrument cannot say true: a bare segmented control as the item's view read \(String(describing: onWindow["segmented"]))")
        XCTAssertEqual(onWindow["default"], true, "the instrument cannot say true: an item never told read \(String(describing: onWindow["default"])) on a window")
        window.toolbar = nil
    }
}
