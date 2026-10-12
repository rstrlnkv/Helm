import AppKit
import HelmRuntime
import HelmTestSupport
import SwiftUI
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
/// **The fold of the sidebar travels with the toolbar: across it the window is given no toolbar, the name's
/// view is held off the item's leading edge by one inset that follows the pane's edge, and the layout that
/// moves the card tells the toolbar in that turn.** Those rows write the sidebar's width value after value over
/// the window built as the app builds it, read the inset as a constant and the name's hosting view as a frame
/// (an unshown window gives a frame once the frame view is laid out), and say for each which of the two it
/// rests on.
///
/// **The tabs stand on the card's middle, not the window's.** The rows under "Where the tabs stand" read frames in
/// window x after the frame view is laid out, and the lead item `helm.tabsLead` that stands them off the name as the
/// one width constraint its view holds; a window with no such item fails the rows that read the lead's constant by
/// naming the list the toolbar has, and the row at 200 and in the rail by its offsets; the centred-set row and the
/// narrowing row are green without it. They run under both looks (the tabs are 168 pt wide under Flat and 148 under
/// Liquid Glass in the rig's two-tab page), at a sidebar of 200 and in the rail, in a window never ordered: there the
/// toolbar's items start where AppKit lays them out for an unshown window, which is x 92.0 to 92.5 at a sidebar of
/// 200 and x 22.0 to 22.5 in the rail. The one start the name's inset and the tabs' lead are worked out from
/// (`SettingsToolbar.itemsStart`, `startOfItems(rail:)`) is, in a window never ordered, the seed of the placement the
/// pane was told (92.5 expanded, 22.5 in the rail), because `learnStartOfItems` reads the name item only while the window is
/// visible; so the name stands sixteen inside the card in the rail too (72 at 56, an inset of 49.5). The rows that
/// read a start off the item put the window under `whileShown`, which answers `isVisible` true for the span of a call.
///
/// **The idle search field is offered room before the tabs fold.** The rows under "Where the search field stands
/// beside the tabs", "What the fold on the search field's growth lets through" and "Where the tabs fold and unfold
/// on the room the field is offered", and three of the five under "Where the lead, the floor and the start of the
/// rail are read", declare a page of three tabs, an action and a search; the other two of that section declare the
/// rig's two-tab page under both looks, and the rows under "What the search field is offered, as numbers" build no
/// window. Those that stand on the shaped page's band or zero window, and the row with a field holding text, run
/// under Flat alone.
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
    /// fold of the sidebar is not a step here: it is held apart (`testAcrossAFoldNoToolbarIsAssigned`).
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
    /// says (a window never shown learns no start off the item) and the name's view is held off its item's edge by the
    /// pane's edge plus sixteen less that start, so the name's left edge is the sum, 216 in window x, read here
    /// from the item's constraint; the frame the same view takes at every width of the fold is read by
    /// `testTheNameFollowsThePaneOneForOneAtEveryWidth`.
    func testAtTwoHundredTheNameStartsSixteenPastThePane() throws {
        guard let rig = build() else { return }
        rig.settle()
        guard let toolbar = rig.worn("no name item was read, so no name start") else { return }
        let card = rig.shell.shell.card.frame
        XCTAssertEqual(card.minX, 200, accuracy: 0.5, "the card's edge is \(card.minX), not the sidebar's 200: the row stands at another width")
        guard let owner = toolbar.delegate as? SettingsToolbar else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no item start was read")
            return
        }
        guard let inset = readInset(rig, "at 200") else { return }
        let nameStart = owner.itemsStart + inset
        XCTAssertEqual(nameStart, 216, accuracy: 1, "the name starts at window x \(nameStart), not 216")
        XCTAssertEqual(nameStart, card.minX + 16, accuracy: 1,
                       "the name starts at \(nameStart), not sixteen past the pane's edge at \(card.minX)")
    }

    // MARK: - The fold and the name's inset

    /// Where an unshown window's toolbar starts its items at the full sidebar: the seed (`SettingsToolbar.itemsStartSeed`), which a
    /// window nobody ordered holds for the full sidebar's placement. Spelled as a number here, not read from the declaration, so a
    /// seed that moved turns the rows below red by their own precondition.
    private static let itemsStart: CGFloat = 92.5

    /// Where the same toolbar starts its items in the rail's placement of the window's buttons (`SettingsToolbar.railItemsStartSeed`),
    /// spelled as a number for the same reason.
    private static let railItemsStart: CGFloat = 22.5

    /// The sidebar width at and under which the window's buttons stand in the rail's placement, spelled here and not read from `ShellGeometry`.
    private static let railWidth: CGFloat = 56

    /// The distance the name keeps from the pane's leading edge.
    private static let nameGap: CGFloat = 16

    /// The inset the name's view is held off the item's leading edge by when the pane starts at `leading`: the pane's edge
    /// plus sixteen less the start of the placement the window's buttons stand in (`rail`: 22.5, else 92.5), never below 0.
    private static func inset(forPaneLeading leading: CGFloat, rail: Bool = false) -> CGFloat {
        max(0, leading + nameGap - (rail ? railItemsStart : itemsStart))
    }

    /// Sidebar widths from the full one to the rail in twelve steps, and back.
    private static let widthsDown: [CGFloat] = Array(stride(from: CGFloat(188), through: 56, by: -12))
    private static let widthsUp: [CGFloat] = Array(stride(from: CGFloat(68), through: 200, by: 12))

    private func settingsToolbar(of toolbar: NSToolbar) -> SettingsToolbar? { toolbar.delegate as? SettingsToolbar }

    /// The hosting view of the name zone in the toolbar's name item, wherever the item keeps it: the item's
    /// own view or a view inside it.
    private func nameHost(in toolbar: NSToolbar) -> NSHostingView<NameZoneView>? {
        SettingsWindowRig.item("helm.name", in: toolbar)?.view?.everyView(ofType: NSHostingView<NameZoneView>.self).first
    }

    /// The insets the name item holds its hosting view off its own leading edge by: the constants of the
    /// constraints in the item's view that tie the hosting view's leading edge to the item view's, read as a
    /// distance from the item view's edge whichever side is written first. Empty where the item's view is the
    /// hosting view itself or holds no such constraint.
    private func insets(in toolbar: NSToolbar) -> [CGFloat] {
        guard let view = SettingsWindowRig.item("helm.name", in: toolbar)?.view,
              let host = nameHost(in: toolbar), host !== view else { return [] }
        return view.constraints.compactMap { constraint in
            guard constraint.firstAttribute == .leading, constraint.secondAttribute == .leading else { return nil }
            if constraint.firstItem === host, constraint.secondItem === view { return constraint.constant }
            if constraint.firstItem === view, constraint.secondItem === host { return -constraint.constant }
            return nil
        }
    }

    /// The one inset the window's name item holds, or nil after a failure that says what the item is made of.
    private func readInset(_ rig: SettingsWindowRig, _ when: String,
                           file: StaticString = #filePath, line: UInt = #line) -> CGFloat? {
        guard let toolbar = rig.worn("no inset was read \(when)", file: file, line: line) else { return nil }
        let found = insets(in: toolbar)
        guard found.count == 1 else {
            let view = SettingsWindowRig.item("helm.name", in: toolbar)?.view
            XCTFail("\(when): the name item holds \(found.count) leading insets for the name's hosting view, not one: its view is "
                    + "\(view.map { "\(type(of: $0))" } ?? "missing") and the toolbar lists \(toolbar.items.map(\.itemIdentifier.rawValue))",
                    file: file, line: line)
            return nil
        }
        return found[0]
    }

    /// The window x the name's hosting view starts at, nil where it is not in the window or has no width. The
    /// frame view is laid out first, then the host's frame is read. No run has read the frame without that layout.
    private func nameStart(_ rig: SettingsWindowRig) -> CGFloat? {
        rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
        guard let toolbar = rig.window.toolbar, let host = nameHost(in: toolbar),
              host.window != nil, host.frame.width > 0 else { return nil }
        return host.convert(host.bounds, to: nil).minX
    }

    /// Writes the sidebar's width value after value, the way the fold's link does: each write is followed
    /// by the layout it asks for, by the turns the main queue and the toolbar's settle take, and by a layout of
    /// the frame view, and then `visit` reads. The fold itself (`fold(to:animated:)`) is not driven here: this rig
    /// leaves the shell the display link it was built with, which no row ticks;
    /// `TheFoldIsDrivenByTheLinksOwnClockTests` drives a fold through a link ticked by hand.
    private func walk(_ rig: SettingsWindowRig, _ widths: [CGFloat], visit: (CGFloat) -> Void) {
        let shell = rig.shell.shell
        for width in widths {
            shell.sidebarWidth = width
            shell.layoutSubtreeIfNeeded()
            rig.settle()
            rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
            visit(width)
        }
    }

    /// How many toolbars the window was given, and how many times the shell was told it took one, while `body` ran.
    private func counts(_ rig: SettingsWindowRig, during body: () -> Void) -> (assigned: Int, attached: Int) {
        var assigned = 0
        let kvo = rig.window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { assigned += 1 } }
        let told = rig.shell.shell.barAttachments
        body()
        kvo.invalidate()
        return (assigned, rig.shell.shell.barAttachments - told)
    }

    /// The two pages every fold row runs over: General, whose bar is the name alone and its status, and a page
    /// that declares tabs, an action and a search.
    private func pages(_ rig: SettingsWindowRig) -> [(label: String, show: () -> Void)] {
        rig.declare("probe.a", search: true)
        return [("General", { rig.model.selection = .general }),
                ("a page with tabs, an action and a search", { rig.model.selection = .module("probe.a") })]
    }

    /// **Across a fold of the sidebar, from 200 to the rail and back, the window is given no toolbar and the
    /// shell is told of none, and the page's toolbar and its name item are the objects they were.** The
    /// fold is the sidebar's width written value after value (twelve steps each way), a layout after each,
    /// over two pages. The count is KVO on `window.toolbar` and the shell's `barAttachments`, never
    /// `needsLayout`, which an unshown window sets for a reason nobody found. Before the steps the card
    /// stands at 200, at each step it stands at the width written, and the last step stands at the rail, so a
    /// fold that never crossed the point where the name's inset reaches 0 reads as no fold. After the
    /// steps a page switch is counted by the same two counters, so a counter that heard nothing is not
    /// mistaken for a fold that assigned nothing.
    func testAcrossAFoldNoToolbarIsAssigned() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        let shell = rig.shell.shell
        for (label, show) in pages(rig) {
            show()
            rig.settle()
            SettingsWindowRig.pump()
            guard let before = rig.worn("no fold was run on \(label)") else { return }
            let nameItem = SettingsWindowRig.item("helm.name", in: before)
            XCTAssertNotNil(nameItem, "\(label): the toolbar lists no name item: \(before.items.map(\.itemIdentifier.rawValue))")
            XCTAssertEqual(shell.card.frame.minX, 200, accuracy: 0.5, "\(label): the fold does not start at 200: the card's edge is \(shell.card.frame.minX)")

            var stood: [CGFloat] = []
            var firstNameItemMoved = false
            for (direction, widths) in [("200 -> 56", Self.widthsDown), ("56 -> 200", Self.widthsUp)] {
                stood.removeAll()
                let heard = counts(rig) {
                    walk(rig, widths) { width in
                        stood.append(shell.card.frame.minX)
                        if SettingsWindowRig.item("helm.name", in: rig.window.toolbar ?? before) !== nameItem { firstNameItemMoved = true }
                    }
                }
                XCTAssertEqual(stood, widths, "\(label), \(direction): the card did not stand at each width written: \(stood)")
                XCTAssertEqual(heard.assigned, 0,
                               "\(label), \(direction): the fold gave the window \(heard.assigned) toolbars, not none (pane edge from \(widths.first ?? 0) to \(widths.last ?? 0))")
                XCTAssertEqual(heard.attached, 0,
                               "\(label), \(direction): the fold told the shell \(heard.attached) times that the window took a bar, not never")
            }
            XCTAssertTrue(rig.window.toolbar === before, "\(label): the toolbar on the window after the fold is another object than before it")
            XCTAssertFalse(firstNameItemMoved, "\(label): the name item was another object at some step of the fold")
        }
        let control = counts(rig) { rig.model.selection = rig.model.selection == .general ? .module("probe.a") : .general }
        XCTAssertGreaterThan(control.assigned, 0, "a page switch after the fold assigned no toolbar: the counters heard nothing, so the zeros above prove nothing")
        XCTAssertEqual(control.attached, control.assigned, "the page switch assigned \(control.assigned) toolbars and told the shell \(control.attached) times")
    }

    /// **At every width of the fold the name's hosting view starts where the pane's edge plus sixteen puts
    /// it while that is right of where the toolbar's items start, and at the start of the name's item
    /// where it is not, within a point.** The reading is the hosting view's left edge in window x, a frame: the
    /// frame view is laid out first (`nameStart`), and no run read the frame without that layout. The band between
    /// 76.5 and 112.5 is where the inset is above zero and below 36 pt; the row requires three readings there.
    /// Before the readings every width must have given one.
    ///
    /// Where the items start is read twice. The toolbar's own start (`itemsStart`) is the seed of the placement the
    /// pane was told in a window that is never visible (92.5 expanded, 22.5 in the rail, spelled in this file), and the row
    /// requires the inset to be above zero exactly where the pane's edge plus sixteen is right of the start of the placement
    /// the width stands in (the rail at 56 and under, told by the shell). The name's item, though, starts where AppKit lays it out, which the row reads from the
    /// view: 92.0 to 92.5 in the expanded placement of the window's buttons and 22.0 to 22.5 in the rail placement, where the lead
    /// changes at every step and the toolbar is laid out again. In the rail the pane's edge plus sixteen (72) is right of the
    /// 22.5 the toolbar starts its items at there, so the inset is 49.5 and the name stands at 72, sixteen inside the card as at
    /// every other width (a toolbar that worked the rail's inset out from the full sidebar's 92.5 would write 0 and the name would stand at the item's 22.5).
    /// Where the inset is 0 the name is wanted at the item's start; where it is above zero, at the pane's edge plus sixteen.
    func testTheNameFollowsThePaneOneForOneAtEveryWidth() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        let shell = rig.shell.shell
        for (label, show) in pages(rig) {
            show()
            rig.settle()
            SettingsWindowRig.pump()
            guard let toolbar = rig.worn("no name was read on \(label)") else { return }
            guard let owner = settingsToolbar(of: toolbar) else {
                XCTFail("\(label): the toolbar's delegate is not the settings toolbar's: no items start was read")
                return
            }
            XCTAssertEqual(owner.itemsStart, Self.itemsStart, accuracy: 0.0001, "\(label): the toolbar's items start at \(owner.itemsStart), not at the seed this row stands on")

            var reads = 0
            var inBand = 0
            var off: [String] = []
            for widths in [Self.widthsDown, Self.widthsUp] {
                walk(rig, widths) { width in
                    let edge = shell.card.frame.minX
                    guard let got = nameStart(rig),
                          let container = SettingsWindowRig.item("helm.name", in: toolbar)?.view, container.window != nil,
                          let held = insets(in: toolbar).first else {
                        off.append("pane \(edge): the name has no frame, item or inset")
                        return
                    }
                    let itemStart = container.convert(container.bounds, to: nil).minX
                    reads += 1
                    if edge > 76.5, edge < 112.5 { inBand += 1 }
                    let start = edge <= Self.railWidth ? Self.railItemsStart : Self.itemsStart
                    let asked = edge + Self.nameGap > start + 0.0001
                    if asked != (held > 0.0001) {
                        off.append("pane \(edge): the inset is \(f3(held)) where the pane's edge plus sixteen is \(f3(edge + Self.nameGap)) and the items start at \(f3(start)) (the toolbar holds \(f3(owner.itemsStart)))")
                    }
                    let want = held > 0.0001 ? edge + Self.nameGap : itemStart
                    if abs(got - want) > 1 { off.append("pane \(edge): name at \(got), want \(want) (the name's item starts at \(itemStart), inset \(held))") }
                }
            }
            XCTAssertEqual(reads, 24, "\(label): the name was read \(reads) times of 24: \(off)")
            XCTAssertGreaterThanOrEqual(inBand, 3, "\(label): the band between 76.5 and 112.5 was read \(inBand) times")
            XCTAssertTrue(off.isEmpty, "\(label): the name is off the pane's edge at \(off.count) of \(reads) widths: \(off)")
        }
    }

    /// **At every width of the fold the name's inset is the pane's edge plus sixteen less where the items
    /// start under the placement the width stands in, and never below zero.** The same walk as above, read as the constant the name item holds and not
    /// as a frame, so what AppKit makes of an item narrower than its viewer does not enter. The start is the seed of the placement
    /// (92.5 expanded, 22.5 in the rail at 56 and under: a window never shown learns none off the item), spelled in this file; the
    /// seed at rest is asserted before the readings, and at each width the pane the toolbar was told stands in the rail exactly where
    /// the width does, so a row whose rail start is wrong fails by that precondition and not by a number. At 56 the inset is
    /// 56 + 16 - 22.5 = 49.5, not 0: the name stands sixteen inside the card in the rail as it does at every other width.
    func testTheNamesInsetFollowsThePaneOneForOneAtEveryWidth() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        let shell = rig.shell.shell
        for (label, show) in pages(rig) {
            show()
            rig.settle()
            SettingsWindowRig.pump()
            guard let toolbar = rig.worn("no inset was read on \(label)") else { return }
            XCTAssertEqual(settingsToolbar(of: toolbar)?.itemsStart ?? -1, Self.itemsStart, accuracy: 0.0001,
                           "\(label): the toolbar's items do not start at the seed this row stands on")
            guard readInset(rig, "\(label) at rest") != nil else { return }
            var reads = 0
            var off: [String] = []
            for widths in [Self.widthsDown, Self.widthsUp] {
                walk(rig, widths) { _ in
                    let edge = shell.card.frame.minX
                    let rail = edge <= Self.railWidth
                    if let owner = settingsToolbar(of: toolbar), let told = toldPane(owner, "\(label) at pane \(edge)") {
                        XCTAssertEqual(told.rail, rail, "\(label) at pane \(edge): the toolbar was told the \(told.rail ? "rail's" : "full sidebar's") placement where the width calls for the \(rail ? "rail's" : "full sidebar's")")
                    }
                    let want = Self.inset(forPaneLeading: edge, rail: rail)
                    guard let got = readInset(rig, "\(label) at pane \(edge)") else { return }
                    reads += 1
                    if abs(got - want) > 0.01 { off.append("pane \(edge): inset \(got), want \(want)") }
                }
            }
            XCTAssertEqual(reads, 24, "\(label): the inset was read \(reads) times of 24")
            XCTAssertTrue(off.isEmpty, "\(label): the inset is off at \(off.count) of \(reads) widths: \(off)")
        }
    }

    /// **The layout that moves the card tells the toolbar in that same turn: with no turn of the main queue
    /// in between, the room the toolbar offers is the card's new width and the name's inset is the new one.**
    /// The sidebar is narrowed from 200 to 120 and the shell laid out, and nothing runs after that. Before it,
    /// the toolbar offers the card's width at rest, so the reading is live; after it, the card stands at 120
    /// and the room is read first, since the room exists on the toolbar whatever the name is made of.
    func testTheToolbarIsToldInTheLayoutsOwnTurn() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        rig.settle()
        SettingsWindowRig.pump()
        guard let toolbar = rig.worn("nothing was told to a window that wore no toolbar"),
              let owner = settingsToolbar(of: toolbar) else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no room was read")
            return
        }
        let shell = rig.shell.shell
        XCTAssertEqual(shell.card.frame.minX, 200, accuracy: 0.5, "the row does not start at 200: the card's edge is \(shell.card.frame.minX)")
        XCTAssertEqual(owner.offeredRoom(), shell.card.frame.width, accuracy: 0.5,
                       "at rest the toolbar offers \(owner.offeredRoom()), not the card's \(shell.card.frame.width): the reading is not live")

        shell.sidebarWidth = 120
        shell.layoutSubtreeIfNeeded()
        XCTAssertEqual(shell.card.frame.minX, 120, accuracy: 0.5, "the layout never moved the card: its edge is \(shell.card.frame.minX)")
        XCTAssertEqual(owner.offeredRoom(), shell.card.frame.width, accuracy: 0.5,
                       "after the layout, with no turn of the main queue, the toolbar offers \(owner.offeredRoom()), not the card's new \(shell.card.frame.width): the layout's report was left for a later turn")
        if let inset = readInset(rig, "after the layout, with no turn of the main queue") {
            XCTAssertEqual(inset, Self.inset(forPaneLeading: 120), accuracy: 0.01,
                           "after the layout, with no turn of the main queue, the name's inset is \(inset), not \(Self.inset(forPaneLeading: 120))")
        }
    }

    // MARK: - The name without its icon

    /// **Under "Without Icon" the toolbar lists the name, its hosting view draws no icon, and the window's own
    /// title is hidden.** The style is stored before the window is built. The three halves are asserted
    /// apart: the title's visibility is read first, then the item, then the view's `showsIcon`.
    func testWithoutIconTheNameIsDrawnWithoutItsIconAndTheTitleStaysHidden() throws {
        PinnedBarSettings.pin(in: self)
        AppSettings.pageBarStyle = .windowTitle
        guard let rig = build() else { return }
        rig.settle()
        XCTAssertEqual(rig.window.titleVisibility, .hidden,
                       "under Without Icon the window's title is \(rig.window.titleVisibility == .visible ? "visible" : "not hidden"): AppKit draws it over the sidebar")
        guard let toolbar = rig.worn("no name item was read under Without Icon") else { return }
        guard SettingsWindowRig.item("helm.name", in: toolbar) != nil else {
            XCTFail("under Without Icon the toolbar lists no name item: it holds \(toolbar.items.map(\.itemIdentifier.rawValue))")
            return
        }
        guard let host = nameHost(in: toolbar) else {
            XCTFail("under Without Icon the name item holds no hosting view of the name zone")
            return
        }
        XCTAssertFalse(host.rootView.showsIcon, "under Without Icon the name is drawn with its icon")
    }

    /// **A name patched in place under "Without Icon" stays without its icon.** The window's activity reaching
    /// the toolbar rewrites the hosting view's root view instead of building another; the root view's
    /// `appearsActive` is read before and after, so a change that patched nothing is a failure and not an
    /// agreement.
    func testWithoutIconAPatchedNameStaysWithoutItsIcon() throws {
        PinnedBarSettings.pin(in: self)
        AppSettings.pageBarStyle = .windowTitle
        guard let rig = build() else { return }
        rig.settle()
        guard let toolbar = rig.worn("no name was read under Without Icon"), let host = nameHost(in: toolbar),
              let owner = settingsToolbar(of: toolbar) else {
            XCTFail("under Without Icon the name item holds no hosting view of the name zone")
            return
        }
        let was = host.rootView.appearsActive
        owner.setWindowAppearsActive(!was)
        guard let patched = nameHost(in: toolbar) else {
            XCTFail("the change of the window's activity left the name item with no hosting view")
            return
        }
        XCTAssertTrue(patched === host, "the change of the window's activity built another hosting view: the name was not patched in place")
        XCTAssertEqual(patched.rootView.appearsActive, !was, "the change of the window's activity left the name's root view as it was: nothing was patched")
        XCTAssertFalse(patched.rootView.showsIcon, "the name patched under Without Icon is drawn with its icon")
    }

    /// **Under the module's name the icon stays and the title is hidden.** The control half of
    /// `testWithoutIconTheNameIsDrawnWithoutItsIconAndTheTitleStaysHidden`: the same reads, under the other style.
    func testWithTheModuleNameThePlateStaysAndTheTitleStaysHidden() throws {
        PinnedBarSettings.pin(in: self)
        AppSettings.pageBarStyle = .moduleName
        guard let rig = build() else { return }
        rig.settle()
        XCTAssertEqual(rig.window.titleVisibility, .hidden, "under the module's name the window's title is not hidden")
        guard let toolbar = rig.worn("no name item was read under the module's name") else { return }
        guard let host = nameHost(in: toolbar) else {
            XCTFail("under the module's name the toolbar lists no name zone: it holds \(toolbar.items.map(\.itemIdentifier.rawValue))")
            return
        }
        XCTAssertTrue(host.rootView.showsIcon, "under the module's name the name is drawn without its icon")
    }

    // MARK: - What a pane that is no position reads

    /// **A pane edge that is not a number, infinite or below zero is a pane at 0, and the name's inset reads
    /// 0: never a wide one.** For each such value the pane is first told 200, so the inset reads 123.5 and
    /// the report that follows has something to take away; then the hostile edge is told and must be stored
    /// (it differs from 200), and the inset reads 0 and the name starts at the toolbar's items start, within
    /// a point.
    func testANotANumberPaneReadsZeroInset() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        rig.settle()
        SettingsWindowRig.pump()
        guard let toolbar = rig.worn("no pane was told to a window that wore no toolbar"),
              let owner = settingsToolbar(of: toolbar) else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no pane was told")
            return
        }
        let width = rig.shell.shell.card.frame.width
        let hostile: [(String, CGFloat)] = [("not a number", .nan), ("plus infinity", .infinity), ("minus infinity", -.infinity),
                                           ("minus one", -1), ("far below zero", -1e9)]
        for (label, value) in hostile {
            owner.paneMoved(leading: 200, width: width)
            if let inset = readInset(rig, "with the pane told 200 before \(label)") {
                XCTAssertEqual(inset, 123.5, accuracy: 0.01, "with the pane told 200 the inset is \(inset), not 123.5")
            }
            XCTAssertTrue(owner.paneMoved(leading: value, width: width), "a pane edge that is \(label) was refused: the bar keeps the pane it had")
            if let inset = readInset(rig, "a pane edge that is \(label)") {
                XCTAssertEqual(inset, 0, accuracy: 0.01, "a pane edge that is \(label) reads an inset of \(inset), not 0")
            }
            if let start = nameStart(rig) {
                XCTAssertEqual(start, Self.itemsStart, accuracy: 1, "a pane edge that is \(label) starts the name at \(start), not at the items' start \(Self.itemsStart)")
            } else {
                XCTFail("a pane edge that is \(label): the name has no frame")
            }
        }
    }

    /// **A pane edge past the window's own width is held at it: the inset is never wider than the window
    /// less where the items start, plus sixteen.** The wide side of the row above; finite and huge.
    func testAPaneEdgePastTheWindowIsHeldAtTheWindowsWidth() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        rig.settle()
        SettingsWindowRig.pump()
        guard let toolbar = rig.worn("no pane was told to a window that wore no toolbar"),
              let owner = settingsToolbar(of: toolbar) else {
            XCTFail("the toolbar's delegate is not the settings toolbar's: no pane was told")
            return
        }
        let ceiling = rig.window.frame.width
        XCTAssertGreaterThan(ceiling, 0, "the window has no width")
        for value: CGFloat in [1e9, .greatestFiniteMagnitude] {
            owner.paneMoved(leading: 100, width: 800)
            XCTAssertTrue(owner.paneMoved(leading: value, width: 800), "a pane edge of \(value) was refused")
            if let inset = readInset(rig, "a pane edge of \(value)") {
                XCTAssertEqual(inset, ceiling + Self.nameGap - Self.itemsStart, accuracy: 0.01,
                               "a pane edge of \(value) reads an inset of \(inset), not the window's \(ceiling) + 16 less \(Self.itemsStart)")
            }
        }
    }

    // MARK: - A bar the window did not have

    /// **A change of look puts another bar on the window, and that bar carries the inset of now.** The
    /// pane stands at 140 when the look changes from Flat to Liquid Glass; the bar on the window afterwards is
    /// another object than the one before (so the row reads a new bar), its name's inset is the one for 140,
    /// and the name starts there within a point.
    func testAChangeOfLookPutsABarWithTheInsetOfNowOnTheWindow() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        walk(rig, [140]) { _ in }
        guard let before = rig.worn("the look was changed on a window that wore no toolbar") else { return }
        XCTAssertEqual(rig.shell.shell.card.frame.minX, 140, accuracy: 0.5, "the pane does not stand at 140")
        AppSettings.barAppearance = .liquidGlass
        rig.settle()
        SettingsWindowRig.pump()
        guard let after = rig.worn("the look changed and the window lost its toolbar") else { return }
        XCTAssertFalse(after === before, "a change of look left the window the bar of the other look: the row reads no new bar")
        if let inset = readInset(rig, "on the bar of the new look") {
            XCTAssertEqual(inset, Self.inset(forPaneLeading: 140), accuracy: 0.01,
                           "the bar of the new look carries an inset of \(inset), not \(Self.inset(forPaneLeading: 140))")
        }
        if let start = nameStart(rig) {
            XCTAssertEqual(start, 140 + Self.nameGap, accuracy: 1, "on the bar of the new look the name starts at \(start), not at \(140 + Self.nameGap)")
        } else {
            XCTFail("on the bar of the new look the name has no frame")
        }
    }

    /// **A page's bar kept off the window comes back with the inset of now, not of the time it was left.**
    /// General's bar is on the window at 200 and then left for a page with tabs; the pane moves to 140 while
    /// that page is shown; General is selected again. The bar that returns is the object General had (so the
    /// row reads a cached bar), and its inset is the one for 140, not the 123.5 it was built with.
    func testACachedBarComesBackWithTheInsetOfNowNotOfWhenItWasLeft() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        rig.declare("probe.a", search: true)
        rig.settle()
        SettingsWindowRig.pump()
        guard let general = rig.worn("no page was left on a window that wore no toolbar") else { return }
        if let inset = readInset(rig, "on General at 200") {
            XCTAssertEqual(inset, 123.5, accuracy: 0.01, "General's bar at 200 carries an inset of \(inset), not 123.5")
        }
        rig.model.selection = .module("probe.a")
        rig.settle()
        XCTAssertFalse(rig.window.toolbar === general, "the page with tabs shows General's bar: nothing was left")
        walk(rig, [140]) { _ in }
        XCTAssertEqual(rig.shell.shell.card.frame.minX, 140, accuracy: 0.5, "the pane does not stand at 140")
        rig.model.selection = .general
        rig.settle()
        XCTAssertTrue(rig.window.toolbar === general, "General came back with another bar than the one it was left with: the row reads no cached bar")
        if let inset = readInset(rig, "on General back at 140") {
            XCTAssertEqual(inset, Self.inset(forPaneLeading: 140), accuracy: 0.01,
                           "General's cached bar came back with an inset of \(inset), not \(Self.inset(forPaneLeading: 140)): nobody told it the pane moved while it was off the window")
        }
    }

    /// **The first bar of a freshly built window carries the inset of the first layout, with no settle and no
    /// turn of the main queue.** The window is built and read at once; the card stands at 200.
    func testTheFirstBarOfAFreshWindowCarriesTheInsetOfTheFirstLayout() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        XCTAssertEqual(rig.shell.shell.card.frame.minX, 200, accuracy: 0.5, "the fresh window's card does not stand at 200")
        if let inset = readInset(rig, "on the first bar of a fresh window") {
            XCTAssertEqual(inset, Self.inset(forPaneLeading: 200), accuracy: 0.01,
                           "the first bar of a fresh window carries an inset of \(inset), not \(Self.inset(forPaneLeading: 200))")
        }
    }

    // MARK: - A fold in flight

    /// **A toolbar given to the window while the sidebar's fold travels does not end the fold.** The fold is
    /// asked for with Reduce Motion off and the shell's claim on it (`foldTarget`) is read; in the same turn
    /// of the main queue, so that nothing animated has run, the window is given the toolbar of another page and
    /// the claim is read again. A claim that is gone fails the row; `ShellContentView.viewDidMoveToWindow` finishes
    /// a fold in flight, and that this is what would end it here is read from that method and not shown. Not seen
    /// red: no run made the assignment of a toolbar end a fold. What the link then does in a window nobody ordered is not read.
    func testAToolbarAssignedWhileTheFoldTravelsDoesNotEndIt() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        rig.declare("probe.a", search: true)
        rig.settle()
        SettingsWindowRig.pump()
        guard rig.worn("no fold was asked of a window that wore no toolbar") != nil else { return }
        let shell = rig.shell.shell
        shell.reducesMotion = { false }
        XCTAssertTrue(shell.fold(to: 56, animated: true), "the fold was cut, not asked for: nothing travels")
        XCTAssertEqual(shell.foldTarget, 56, "the fold's claim is \(String(describing: shell.foldTarget)), not 56")
        let heard = counts(rig) { rig.model.selection = .module("probe.a") }
        XCTAssertGreaterThan(heard.assigned, 0, "the page switch gave the window no toolbar: the row never assigned one")
        XCTAssertEqual(shell.foldTarget, 56, "a toolbar given to the window ended the fold in flight: its claim is \(String(describing: shell.foldTarget))")
        SettingsWindowRig.pump(0.6)
    }

    // MARK: - What the tabs' prediction reads of the name

    /// The tabs' control in the window's toolbar, nil where the toolbar lists none.
    private func tabsControl(_ rig: SettingsWindowRig) -> NSSegmentedControl? {
        guard let toolbar = rig.window.toolbar else { return nil }
        return SettingsWindowRig.item("helm.tabs", in: toolbar)?.view?.everyView(ofType: NSSegmentedControl.self).first
    }

    /// **The name item ends where its hosting view ends, and the width the item has beyond the view is the
    /// inset.** The tabs' prediction measures the gap from the name item's trailing edge to the tabs; the item is
    /// a container wider than its hosting view by the inset, so the gap is the view's only while the container's
    /// trailing edge is the view's. Read at the full sidebar, at 140 and at the rail, in window x after the frame
    /// view is laid out; at 200 the container is wider than the view by 123.5, which is read first so that a
    /// container that holds no inset reads as a failure and not as an agreement. At the rail (56) it is wider by
    /// 49.5, the pane's edge plus sixteen less the rail's start of 22.5, and not by 0.
    func testTheNameItemEndsWhereItsHostingViewEnds() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        rig.settle()
        SettingsWindowRig.pump()
        var reads = 0
        walk(rig, [200, 140, 56]) { width in
            guard let toolbar = rig.worn("no name item was read at \(width)"),
                  let container = SettingsWindowRig.item("helm.name", in: toolbar)?.view,
                  let host = nameHost(in: toolbar), host !== container,
                  host.window != nil, host.bounds.width > 0 else {
                XCTFail("at \(width) the name item has no container with a hosting view in a window")
                return
            }
            reads += 1
            let containerEnd = container.convert(NSPoint(x: container.bounds.width, y: 0), to: nil).x
            let hostEnd = host.convert(NSPoint(x: host.bounds.width, y: 0), to: nil).x
            XCTAssertEqual(containerEnd, hostEnd, accuracy: 0.5,
                           "at \(width) the name item ends at window x \(containerEnd) and its hosting view at \(hostEnd): the gap to the tabs is read from the wrong edge")
            let beyond = container.bounds.width - host.bounds.width
            let rail = width <= Self.railWidth
            XCTAssertEqual(beyond, Self.inset(forPaneLeading: width, rail: rail), accuracy: 0.5,
                           "at \(width) the name item is \(beyond) wider than its hosting view, not the inset \(Self.inset(forPaneLeading: width, rail: rail))")
        }
        XCTAssertEqual(reads, 3, "the name item was read \(reads) times of 3")
    }

    /// **The tabs fold against the name's own width and not against the inset the item holds it off the edge by.**
    /// A page declares tabs and nothing else, so the toolbar has no actions item to anchor on and the prediction
    /// falls back to the room the pane offers less the name's, the lead's and the tabs' widths. At a pane 90
    /// wider than the name and the full tabs need the tabs stay full (an inset charged to the name, 123.5 at
    /// 200, would fold them); at a pane 40 narrower they fold (so the first reading is the fold's own decision and
    /// not a bar that never folds). Folded is one segment shown, full is one per tab. The window's least width
    /// holds the pane at no less than the card gets there, which the row reads and prints.
    ///
    /// The 90 is the lead's floor and the name's gap to the pane: the lead item's viewer acts as 36 pt at least
    /// where the flexible space it replaced cost about 8, so the tabs stand 36 pt (Flat) and 40.0 to 40.5 pt (Liquid Glass)
    /// right of the name's end when the lead's constant is 1, and the name starts 16 right of the pane's edge. Measured on fresh windows narrowed from the default to the name and the tabs plus a spare, before the fallback
    /// charged the lead its floor and not since: with a spare of 20 and 40 the tabs fold under both looks, with 60, 80, 90,
    /// 100, 120, 150 they stay whole; 90 is over the least spare read whole, 60, and 33.5 under the 123.5 an inset charged to
    /// the name would take. Not measured: what a spare between 40 and 60 reads.
    func testTheTabsFoldAgainstTheNamesOwnWidthAndNotItsInset() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = build() else { return }
        let titles = ["Everything installed", "Everything outdated", "Everything pinned", "Everything cached"]
        let tabs = titles.enumerated().map { HelmToolbarTab(id: "t\($0.offset)", title: $0.element, symbol: "shippingbox") }
        rig.channel.declare(HelmPageToolbarContent(tabs: tabs, selectedTab: .constant("t0")),
                            token: "probe.t", generation: rig.channel.nextGeneration())
        rig.model.selection = .module("probe.t")
        rig.settle()
        SettingsWindowRig.pump()
        guard let control = tabsControl(rig), let toolbar = rig.worn("no tabs were read"), let host = nameHost(in: toolbar) else {
            XCTFail("the page's toolbar lists no tabs control or no name zone: \(rig.window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [])")
            return
        }
        XCTAssertNil(SettingsWindowRig.item("helm.actions", in: toolbar), "the fixture is wrong: the page has an actions item to anchor the prediction on")
        let shell = rig.shell.shell
        rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
        XCTAssertEqual(control.segmentCount, tabs.count, "at the default size the tabs are \(control.segmentCount) segments, not \(tabs.count): the row starts from a fold (control \(control.frame.width) wide, name \(host.frame.width), pane \(shell.card.frame.width))")
        let need = host.frame.width + control.frame.width
        XCTAssertGreaterThan(control.frame.width, 0, "the tabs' control has no width in the window")

        func pane(of width: CGFloat) -> CGFloat {
            let chrome = (rig.window.contentView?.frame.width ?? 0) - shell.card.frame.width
            rig.window.setContentSize(NSSize(width: width + chrome, height: rig.window.contentView?.frame.height ?? 760))
            rig.settle()
            SettingsWindowRig.pump()
            return shell.card.frame.width
        }
        let roomy = pane(of: need + 90)
        XCTAssertEqual(roomy, need + 90, accuracy: 1, "the pane stands at \(roomy), not \(need + 90): the window's least width does not let the row reach it (name \(host.frame.width) + tabs \(control.frame.width))")
        XCTAssertEqual(tabsControl(rig)?.segmentCount, tabs.count,
                       "with 90 to spare beyond the name and the tabs the tabs are folded to \(tabsControl(rig)?.segmentCount ?? -1) segments: the inset was charged to the name")
        let short = pane(of: need - 40)
        XCTAssertEqual(short, need - 40, accuracy: 1, "the pane stands at \(short), not \(need - 40): the window's least width does not let the row reach it")
        XCTAssertEqual(tabsControl(rig)?.segmentCount, 1,
                       "with 40 too little the tabs are \(tabsControl(rig)?.segmentCount ?? -1) segments, not folded: the row never saw the fold decide")
    }

    // MARK: - Where the tabs stand

    private static let looks: [HelmBarAppearance] = [.flat, .liquidGlass]

    /// How far the lead's constant may stand from the width the views call for: 1.5 points, chosen half a point above the two half
    /// points AppKit places the name's item and the lead by (22.0 or 22.5 in the rail, 92.0 or 92.5 expanded); the constant is
    /// worked out from the start learnt at the last settle, or the seed 22.5 or 92.5 before one, and from the gap it reads off the
    /// frames; 1.0 was the most read.
    private static let halfPoints: CGFloat = 1.5

    private func f(_ value: CGFloat) -> String { String(format: "%.1f", Double(value)) }

    /// Three decimals, for a number that is compared against a point.
    private func f3(_ value: CGFloat) -> String { String(format: "%.3f", Double(value)) }

    /// Where the parts of a page with tabs stand, in window x, after the frame view is laid out. The tabs' middle
    /// and the card's middle are the two numbers the rows compare; the rest is printed with them.
    private struct Stand {
        let cardMinX: CGFloat
        let cardWidth: CGFloat
        let nameMinX: CGFloat
        let nameMaxX: CGFloat
        let containerMinX: CGFloat
        let inset: CGFloat?
        let tabsMinX: CGFloat
        let tabsMaxX: CGFloat
        let controlMid: CGFloat?
        let segments: Int
        let actionsMinX: CGFloat?
        let leadMinX: CGFloat?
        let leadMaxX: CGFloat?
        let itemsStart: CGFloat?

        var cardMid: CGFloat { cardMinX + cardWidth / 2 }
        var tabsWidth: CGFloat { tabsMaxX - tabsMinX }
        var tabsMid: CGFloat { (tabsMinX + tabsMaxX) / 2 }
        /// How far right of the card's middle the middle of the tabs' view stands.
        var off: CGFloat { tabsMid - cardMid }
        /// Where the tabs' left edge would stand were their middle the card's.
        var centredMinX: CGFloat { cardMid - tabsWidth / 2 }

        var line: String {
            func f(_ value: CGFloat?) -> String { value.map { String(format: "%.1f", Double($0)) } ?? "none" }
            return "card \(f(cardMinX)) wide \(f(cardWidth)) middle \(f(cardMid)); name host \(f(nameMinX))...\(f(nameMaxX)) in an item from "
                + "\(f(containerMinX)) with inset \(f(inset)); tabs \(f(tabsMinX))...\(f(tabsMaxX)) wide \(f(tabsWidth)) middle \(f(tabsMid)) "
                + "(\(f(off)) from the card's, control middle \(f(controlMid))), \(segments) segments; actions from \(f(actionsMinX)); "
                + "lead item \(f(leadMinX))...\(f(leadMaxX)); the bar's items start \(f(itemsStart))"
        }
    }

    /// The parts of the page on the window, or nil after a failure that names the toolbar's items.
    private func stand(_ rig: SettingsWindowRig, _ when: String,
                       file: StaticString = #filePath, line: UInt = #line) -> Stand? {
        rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
        guard let toolbar = rig.worn("no tabs were read \(when)", file: file, line: line) else { return nil }
        guard let tabsView = SettingsWindowRig.item("helm.tabs", in: toolbar)?.view,
              let container = SettingsWindowRig.item("helm.name", in: toolbar)?.view,
              let host = nameHost(in: toolbar), host.window != nil, host.frame.width > 0, tabsView.window != nil
        else {
            XCTFail("\(when): the name or the tabs have no view in the window; the toolbar lists \(toolbar.items.map(\.itemIdentifier.rawValue))",
                    file: file, line: line)
            return nil
        }
        func box(_ view: NSView?) -> CGRect? {
            guard let view, view.window != nil else { return nil }
            return view.convert(view.bounds, to: nil)
        }
        let shell = rig.shell.shell
        let card = shell.card.convert(shell.card.bounds, to: nil)
        let hostBox = host.convert(host.bounds, to: nil)
        let tabsBox = tabsView.convert(tabsView.bounds, to: nil)
        let found = insets(in: toolbar)
        return Stand(cardMinX: card.minX, cardWidth: card.width, nameMinX: hostBox.minX, nameMaxX: hostBox.maxX,
                     containerMinX: container.convert(container.bounds, to: nil).minX,
                     inset: found.count == 1 ? found[0] : nil, tabsMinX: tabsBox.minX, tabsMaxX: tabsBox.maxX,
                     controlMid: box(tabsControl(rig)).map { $0.midX }, segments: tabsControl(rig)?.segmentCount ?? -1,
                     actionsMinX: box(SettingsWindowRig.item("helm.actions", in: toolbar)?.view)?.minX,
                     leadMinX: box(SettingsWindowRig.item("helm.tabsLead", in: toolbar)?.view)?.minX,
                     leadMaxX: box(SettingsWindowRig.item("helm.tabsLead", in: toolbar)?.view)?.maxX,
                     itemsStart: settingsToolbar(of: toolbar)?.itemsStart)
    }

    /// The constants of the width constraints the tabs' lead item's view holds on itself, read from the views as
    /// `insets(in:)` reads the name's inset; nil where the toolbar lists no such item or the item has no view.
    private func leadConstants(in toolbar: NSToolbar) -> [CGFloat]? {
        guard let view = SettingsWindowRig.item("helm.tabsLead", in: toolbar)?.view else { return nil }
        return view.constraints.compactMap { constraint in
            constraint.firstItem === view && constraint.firstAttribute == .width && constraint.secondItem == nil
                ? constraint.constant : nil
        }
    }

    /// The one constant the window's tabs lead item holds, or nil after a failure that names what the toolbar lists.
    private func leadConstant(_ rig: SettingsWindowRig, _ when: String,
                              file: StaticString = #filePath, line: UInt = #line) -> CGFloat? {
        guard let toolbar = rig.worn("no lead was read \(when)", file: file, line: line) else { return nil }
        guard let found = leadConstants(in: toolbar) else {
            XCTFail("\(when): the toolbar lists no helm.tabsLead with a view: it holds \(toolbar.items.map(\.itemIdentifier.rawValue))",
                    file: file, line: line)
            return nil
        }
        guard found.count == 1 else {
            XCTFail("\(when): the lead item's view holds \(found.count) width constraints on itself, not one: \(found)", file: file, line: line)
            return nil
        }
        return found[0]
    }

    /// A page with tabs, an action and a search on the window, the look set first.
    private func pageWithTabs(_ look: HelmBarAppearance, file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        AppSettings.barAppearance = look
        guard let rig = build(file: file, line: line) else { return nil }
        rig.declare("probe.a", search: true)
        rig.model.selection = .module("probe.a")
        rig.settle()
        SettingsWindowRig.pump()
        return rig
    }

    /// The window's content set to `width`, then the shell's sidebar to `sidebar`, each settled.
    private func place(_ rig: SettingsWindowRig, window width: CGFloat, sidebar: CGFloat) {
        rig.window.setContentSize(NSSize(width: width, height: 760))
        rig.settle()
        walk(rig, [sidebar]) { _ in }
    }

    /// **At a sidebar of 200 and in the rail, in a window 1060 and 860 wide, under both looks, the middle of the
    /// tabs' view is the card's middle, within a point.** The page has two tabs, an action and a search. The
    /// tabs are read in window x after the frame view is laid out, the card's middle from its own frame. A
    /// configuration where the tabs are folded, or where the centred place is less than 48 pt right of where the
    /// name ends (so that no centre is reachable), is listed and not compared. Every failure prints the eight
    /// configurations whole.
    ///
    /// Seen on a window with the flexible spaces on either side of the tabs: red in all eight, the tabs' middle
    /// 530 at 1060 under both looks and, at 860, 440 (Flat at a sidebar of 200) and 430 (Flat in the rail, Liquid Glass at both) where the card's middle is 628 and
    /// 528 at a sidebar of 200 and 556 and 456 in the rail, so 98, 26, 88 (Flat; the name holds the tabs 8 pt off its
    /// end) and 98, and 26 and 26, off; none folded, none too near the name to compare.
    func testTheTabsMiddleIsTheCardsMiddleAtTwoHundredAndInTheRail() throws {
        PinnedBarSettings.pin(in: self)
        var table: [String] = []
        var off: [String] = []
        var skipped: [String] = []
        var reads = 0
        for look in Self.looks {
            guard let rig = pageWithTabs(look) else { return }
            for width: CGFloat in [1060, 860] {
                for sidebar: CGFloat in [200, 56] {
                    place(rig, window: width, sidebar: sidebar)
                    let label = "\(look.rawValue) \(Int(width))/\(sidebar == 200 ? "200" : "rail")"
                    XCTAssertEqual(rig.window.contentView?.frame.width ?? 0, width, accuracy: 0.5,
                                   "\(label): the window is not \(width) wide: the row stands at another width")
                    guard let s = stand(rig, label) else { continue }
                    reads += 1
                    table.append("\(label): \(s.line)")
                    if s.segments != 2 {
                        skipped.append("\(label): folded to \(s.segments) segments")
                    } else if s.centredMinX - s.nameMaxX < 48 {
                        skipped.append("\(label): the centred place \(f(s.centredMinX)) is \(f(s.centredMinX - s.nameMaxX)) from the name's end")
                    } else if abs(s.off) > 1 {
                        off.append("\(label): the tabs' middle is \(f(s.tabsMid)), the card's \(f(s.cardMid)) (\(f(s.off)) off)")
                    }
                }
            }
        }
        XCTAssertEqual(reads, 8, "the tabs were read \(reads) times of 8")
        XCTAssertTrue(off.isEmpty, "the tabs' middle is off the card's middle in \(off.count) of \(8 - skipped.count) configurations compared: \(off); not compared: \(skipped); all: \(table)")
    }

    /// **The tabs stay in the toolbar's centred set, under both looks: on a page with tabs the set is the tabs
    /// alone, and on a page with an action and no tabs it is empty.** The control for the tabs' lift and slide,
    /// which AppKit ties to the set's membership: a lead item that pushes the tabs off the window's middle must not
    /// take them out of it, and must not put a page that has none into one. General declares tabs of its own (its
    /// bar lists the lead and the tabs), so its set is the tabs' too and the page with no tabs is declared here,
    /// an action alone. Green on a window with flexible spaces and with the lead item, both looks.
    func testTheTabsStayInAppKitsCentredSet() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let rig = pageWithTabs(look), let toolbar = rig.worn("no centred set was read under \(look.rawValue)") else { return }
            XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier.rawValue == "helm.tabs" },
                          "\(look.rawValue): the toolbar lists no tabs: \(toolbar.items.map(\.itemIdentifier.rawValue))")
            XCTAssertEqual(Set(toolbar.centeredItemIdentifiers.map(\.rawValue)), ["helm.tabs"],
                           "\(look.rawValue): the centred set is \(toolbar.centeredItemIdentifiers.map(\.rawValue)), not the tabs alone")

            rig.channel.declare(HelmPageToolbarContent(actions: [HelmToolbarAction(id: "refresh", title: "Refresh list", symbol: "arrow.clockwise") {}]),
                                token: "probe.n", generation: rig.channel.nextGeneration())
            rig.model.selection = .module("probe.n")
            rig.settle()
            SettingsWindowRig.pump()
            guard let bare = rig.worn("no centred set was read for a page with no tabs under \(look.rawValue)") else { return }
            XCTAssertTrue(SettingsWindowRig.item("helm.actions", in: bare) != nil && !bare.items.contains { $0.itemIdentifier.rawValue == "helm.tabs" },
                          "\(look.rawValue): the page with an action and no tabs lists \(bare.items.map(\.itemIdentifier.rawValue)): the fixture is wrong")
            XCTAssertTrue(bare.centeredItemIdentifiers.isEmpty,
                          "\(look.rawValue): the centred set of a page with no tabs is \(bare.centeredItemIdentifiers.map(\.rawValue)), not empty")
        }
    }

    /// The pane's width set by the window's own, the window's least width lowered first; returns the width the card
    /// then has.
    private func setPane(_ rig: SettingsWindowRig, to width: CGFloat) -> CGFloat {
        let shell = rig.shell.shell
        rig.window.contentMinSize = NSSize(width: 100, height: 100)
        let chrome = (rig.window.contentView?.frame.width ?? 0) - shell.card.frame.width
        rig.window.setContentSize(NSSize(width: width + chrome, height: rig.window.contentView?.frame.height ?? 760))
        rig.settle()
        SettingsWindowRig.pump()
        return shell.card.frame.width
    }

    /// **Where the name's end leaves less than the 36 pt the lead item was read to take (in a window never shown) before the centred place, the tabs stand against the name and are not centred, and the lead's constant is never below 1; where
    /// the room is wide they are centred, and the constant is the room.** A page with four long tabs and nothing
    /// else, at the full sidebar, under both looks: the pane is set to the name and the tabs plus 80, 120,
    /// 150, 230, 330 and 450, from the full tabs' place, narrowest first. Each step is read from frames: the room is where the centred
    /// place stands less where the name ends. At most 0 of it the tabs must stand within 60 pt of the name's end
    /// with the constant 1; between 0 and 60 they must not stand left of the centred place, and where the room is
    /// under 36 they stand within 60 pt of the name; at 60 and over they are centred within a point. Each look must
    /// reach a step in the first and one in the last class, so a sweep that never reached either fails. When the
    /// toolbar lists no `helm.tabsLead` the row says so, with the list and every step read.
    ///
    /// Why the first step is 80. The page has no actions item, so the prediction of the tabs' fold is the fallback,
    /// which folds on a narrowing and never unfolds; a step that folds the tabs ends the sweep for every step after it.
    /// The first step must therefore keep them whole: the tabs start 36.0 (Flat) and 40.0 to 40.5 (Liquid Glass) right
    /// of the name's end when the constant is 1 (read: the lead's view is 1 pt wide and 17.5 right of the name's end; that it
    /// stands centred in a viewer 36 wide is assumed, no viewer's frame was read), the name starts 16 right of the pane's edge, and fresh windows narrowed from the default to the name and the tabs plus 20 and 40 fold the tabs under both looks
    /// and plus 60 to 450 keep them whole (measured before the fallback charged the lead its floor, not since). Measured at
    /// the steps below, with that earlier fallback and not read again since (the row prints its table only on failure): the centred place is left of the name's end by 42.5 (Flat) and 42.25
    /// (Liquid Glass) at 80 and by 7.5 and 7.25 at 150, and right of it by 32.5 and 32.75 at 230, where the constant is
    /// 16.5 and 16.75, below the floor, and the tabs stand 3.5 and 7.75 right of the card's middle; at 330 and 450 they are
    /// 0.5 and 0.75 off it.
    ///
    /// Seen on a window with flexible spaces: the name ends at 348 and the four tabs are 600 pt (Flat) and 550.5 (Liquid Glass) wide; the sweep then started at 40 and 90 where it now starts at 80 and 120, and its three steps with the name reaching the centred place (40, 90, 150) read the tabs 8 to 8.5 pt from the name's end, 70, 45 and 15 pt right of the card's middle, and the three steps with room read them at 656
    /// and 693.5 (Flat), 631.8 and 668.8 (Liquid Glass): 25 left of the centred place, then 75 and 98 off the
    /// card's middle. The toolbar listed no lead item: the row failed on that and on the six steps read wrong.
    func testWhereTheNameReachesTheCentredPlaceTheTabsStandAgainstIt() throws {
        PinnedBarSettings.pin(in: self)
        let titles = ["Everything installed", "Everything outdated", "Everything pinned", "Everything cached"]
        let tabs = titles.enumerated().map { HelmToolbarTab(id: "t\($0.offset)", title: $0.element, symbol: "shippingbox") }
        var table: [String] = []
        var wrong: [String] = []
        var unlisted: [String] = []
        for look in Self.looks {
            AppSettings.barAppearance = look
            guard let rig = build() else { return }
            rig.channel.declare(HelmPageToolbarContent(tabs: tabs, selectedTab: .constant("t0")),
                                token: "probe.t", generation: rig.channel.nextGeneration())
            rig.model.selection = .module("probe.t")
            rig.settle()
            SettingsWindowRig.pump()
            guard let first = stand(rig, "\(look.rawValue), at the start") else { return }
            XCTAssertEqual(first.segments, tabs.count, "\(look.rawValue): the row starts from folded tabs: \(first.line)")
            let need = (first.nameMaxX - first.nameMinX) + first.tabsWidth
            var inside = 0
            var wide = 0
            for extra: CGFloat in [80, 120, 150, 230, 330, 450] {
                let label = "\(look.rawValue), pane = name + tabs + \(Int(extra))"
                let reached = setPane(rig, to: need + extra)
                if abs(reached - (need + extra)) > 1 {
                    wrong.append("\(label): the pane stands at \(f(reached)), not \(f(need + extra))")
                    continue
                }
                guard let s = stand(rig, label) else { continue }
                let room = s.centredMinX - s.nameMaxX
                let constant = rig.window.toolbar.flatMap { leadConstants(in: $0) }?.first
                table.append("\(label), room \(f(room)), constant \(constant.map { f($0) } ?? "none"): \(s.line)")
                if s.segments != tabs.count {
                    wrong.append("\(label): the tabs are folded to \(s.segments) segments")
                    continue
                }
                if let constant, !(constant.isFinite && constant >= 1) {
                    wrong.append("\(label): the constant is \(constant), below 1 or not a number")
                }
                if room <= 0 {
                    inside += 1
                    if abs(s.off) <= 1 { wrong.append("\(label): the name reaches the centred place and the tabs are centred") }
                    if s.tabsMinX - s.nameMaxX > 60 { wrong.append("\(label): the tabs stand \(f(s.tabsMinX - s.nameMaxX)) from the name's end, not against it") }
                    if let constant, abs(constant - 1) > 0.01 { wrong.append("\(label): the constant is \(f(constant)), not 1") }
                } else if room >= 60 {
                    wide += 1
                    if abs(s.off) > 1 { wrong.append("\(label): the room is \(f(room)) and the tabs are \(f(s.off)) off the card's middle") }
                } else {
                    if s.tabsMinX < s.centredMinX - 1 { wrong.append("\(label): the tabs stand \(f(s.centredMinX - s.tabsMinX)) left of the centred place") }
                    if room < 36, s.tabsMinX - s.nameMaxX > 60 { wrong.append("\(label): the tabs stand \(f(s.tabsMinX - s.nameMaxX)) from the name's end with a room of \(f(room))") }
                }
            }
            if rig.window.toolbar.flatMap({ leadConstants(in: $0) }) == nil {
                unlisted.append("\(look.rawValue): the toolbar lists \(rig.window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [])")
            }
            XCTAssertGreaterThanOrEqual(inside, 1, "\(look.rawValue): no step had the name reach the centred place: \(table)")
            XCTAssertGreaterThanOrEqual(wide, 1, "\(look.rawValue): no step had room for the centred place: \(table)")
        }
        XCTAssertTrue(unlisted.isEmpty, "the toolbar lists no helm.tabsLead with a view, so no lead was read: \(unlisted); steps read: \(table)")
        XCTAssertTrue(wrong.isEmpty, "the tabs stand wrong at \(wrong.count) steps: \(wrong); all: \(table)")
    }

    /// What the lead's constant is worked out from, read off the views at the moment of the call: where the name's
    /// item starts in window x, the name's hosting view's width, the tabs' width and the inset the name item holds.
    /// Called after the frame view is laid out, the item stands where the placement puts it; called before, it
    /// stands where the layout before put it, which is not what the constant was written for. nil where the name or
    /// the tabs are not in a window.
    private struct LeadInputs {
        let containerMinX: CGFloat
        let hostWidth: CGFloat
        let tabsWidth: CGFloat
        let inset: CGFloat
        var nameMaxX: CGFloat { containerMinX + inset + hostWidth }
    }

    private func leadInputs(_ rig: SettingsWindowRig) -> LeadInputs? {
        guard let toolbar = rig.window.toolbar,
              let container = SettingsWindowRig.item("helm.name", in: toolbar)?.view,
              let host = nameHost(in: toolbar), let tabs = SettingsWindowRig.item("helm.tabs", in: toolbar)?.view,
              container.window != nil, tabs.window != nil, host.frame.width > 0, tabs.frame.width > 0,
              let inset = insets(in: toolbar).first else { return nil }
        return LeadInputs(containerMinX: container.convert(container.bounds, to: nil).minX,
                          hostWidth: host.frame.width, tabsWidth: tabs.frame.width, inset: inset)
    }

    /// **Across a fold of the sidebar, in both directions and under both looks, after each tick of the link and
    /// the layout it asks for, with no turn of the main queue between, the middle of the tabs' view is the card's
    /// middle, within a point; the lead's constant is that tick's own, and the window is given no toolbar.** The fold
    /// is `ShellContentView.fold(to:animated:)` with a `HandTickedFoldLink`: the first tick writes nothing, then ten ticks: nine a tenth of the length apart (0.1 to 0.9) and a last at 1.1, past the end.
    ///
    /// "That tick's own" is a constant that is already there when the shell's layout of the tick ends, before the
    /// frame view is laid out and with no turn of the main queue: it is read then, and compared, within `halfPoints`,
    /// with `SettingsToolbar.tabsLead(paneLeading:paneWidth:tabsWidth:gap:nameMaxX:)` over the card of this tick and
    /// the name and the tabs as they stand once the frame view has been laid out (`leadInputs(_:)`), where the
    /// placement the shell told has put the name's item. The name's item is not the reference before that layout:
    /// it moves by 70 points, between 92.0 to 92.5 and 22.0 to 22.5, when the window's three buttons enter the rail's placement at the first tick
    /// of a fold into the rail and leave it at the landing of one out of it, and until the frame view is laid out
    /// it stands where the layout before put it, which is the stale reading a constant written from it would
    /// carry, so a reference taken there would call the stale constant right and the right one wrong. The constant
    /// is not compared with the constant at rest either: it moves with the item's start. The gap is the one the
    /// frames show at rest (the tabs' left edge less the lead's right edge).
    ///
    /// A constant one tick late fails this twice over. At a tick where the sidebar moved 8 pt or more the constant
    /// must stand nearer this tick's reference than the previous tick's, which a constant worked out from the card and
    /// the placement before does not: it stands at the previous reference, give or take the half points. And it
    /// must stand within `halfPoints` of this tick's reference, which a constant that is a tick late fails by the
    /// 70 points the name's item moves where the buttons change placement, and by half of what the sidebar moved
    /// elsewhere less what the name's own move takes back. That second reach is as short as 1.1 points at the tick
    /// where the name stops following the pane's edge, which is why the nearer-than-before rule is there beside it. The
    /// row requires four ticks in each direction where the sidebar moved 8 pt or more, so the rule is applied at
    /// four ticks at least, and four widths strictly between the ends in each direction, so a fold that was cut
    /// reads as a failure.
    ///
    /// Seen with the lead worked out from the start of items of the placement the shell told: the tabs' middle within
    /// 0.62 of the card's at all forty ticks under both looks; -0.438 at the first tick of the fold into the rail,
    /// 0.042 at the fourth, 0.000 at the landing of the fold out of it; the constant 1.0 or less from the
    /// reference at every tick; at the sixteen ticks where the sidebar moved 8 pt or more, the previous tick's
    /// constant fails the rule at all sixteen. With the lead worked out from the name's item as it stood before the
    /// frame view's layout, the tabs' middle was 69.438 and 67.438 (Flat, Liquid Glass) left of the card's at the
    /// first tick into the rail, and 70.000 right of it at the landing out of it.
    ///
    /// Seen on a window with flexible spaces: the fold travelled (nine widths between the ends in each direction, none
    /// cut), no toolbar was assigned, and the tabs stayed at 530 while the card's middle went from 628 to 556 and back,
    /// so the offset ran from 98 to 26 and back, tick by tick; the toolbar listed no lead item.
    func testAcrossAFoldTheTabsMiddleFollowsTheCardsMiddle() throws {
        PinnedBarSettings.pin(in: self)
        var off: [String] = []
        var late: [String] = []
        var unlisted: [String] = []
        var cut: [String] = []
        var assigned = 0
        var attached = 0
        var ticks = 0
        for look in Self.looks {
            guard let rig = pageWithTabs(look) else { return }
            let shell = rig.shell.shell
            let link = HandTickedFoldLink()
            shell.foldLink = link
            shell.reducesMotion = { false }
            guard let rest = stand(rig, "\(look.rawValue) at rest"), let toolbar = rig.worn("no fold was run under \(look.rawValue)") else { return }
            XCTAssertEqual(rest.cardMinX, 200, accuracy: 0.5, "\(look.rawValue): the fold does not start at 200")
            if abs(rest.off) > 1 { off.append("\(look.rawValue) at rest: \(f3(rest.off)) off: \(rest.line)") }
            let restLead = leadConstants(in: toolbar)?.first
            var constantOfTheTick: CGFloat? {
                rig.window.toolbar.flatMap { leadConstants(in: $0) }?.first
            }
            if restLead == nil { unlisted.append("\(look.rawValue): the toolbar lists \(toolbar.items.map(\.itemIdentifier.rawValue))") }
            let gap = rest.leadMaxX.map { rest.tabsMinX - $0 } ?? 0
            XCTAssertTrue(gap >= 0 && gap < 8, "\(look.rawValue): the gap between the lead and the tabs at rest is \(f3(gap)): the row stands on a bar that is not the lead and the tabs")
            var previousOwn: CGFloat? = leadInputs(rig).map {
                SettingsToolbar.tabsLead(paneLeading: rest.cardMinX, paneWidth: rest.cardWidth, tabsWidth: $0.tabsWidth, gap: gap, nameMaxX: $0.nameMaxX)
            }

            let heard = counts(rig) {
                for target: CGFloat in [56, 200] {
                    let from = shell.sidebarWidth
                    let direction = "\(look.rawValue) \(Int(from)) -> \(Int(target))"
                    XCTAssertTrue(shell.fold(to: target, animated: true), "\(direction): the fold was cut, not asked for")
                    XCTAssertTrue(link.fire(at: 100), "\(direction): the link was never started")
                    var between = 0
                    var moved = 0
                    var previous = shell.sidebarWidth
                    for fraction in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.1] {
                        link.fire(at: 100 + fraction * HelmMotion.sidebarFoldDuration)
                        shell.layoutSubtreeIfNeeded()
                        ticks += 1
                        let lead = constantOfTheTick
                        rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
                        let inputs = leadInputs(rig)
                        let card = shell.card.convert(shell.card.bounds, to: nil)
                        let width = shell.sidebarWidth
                        if abs(width - target) > 0.01 { between += 1 }
                        let widthBefore = previous
                        if abs(width - previous) >= 8 { moved += 1 }
                        previous = width
                        if let lead, let inputs {
                            let own = SettingsToolbar.tabsLead(paneLeading: card.minX, paneWidth: card.width,
                                                               tabsWidth: inputs.tabsWidth, gap: gap, nameMaxX: inputs.nameMaxX)
                            let detail = "(name's item from \(f3(inputs.containerMinX)), inset \(f3(inputs.inset)), name \(f3(inputs.hostWidth)) wide, tabs \(f3(inputs.tabsWidth)) wide)"
                            if abs(lead - own) > Self.halfPoints {
                                late.append("\(direction) at \(fraction), card at \(f3(width)): the constant is \(f3(lead)), this tick's own is \(f3(own)) \(detail)")
                            }
                            if let ownBefore = previousOwn, abs(width - widthBefore) >= 8, abs(lead - own) >= abs(lead - ownBefore) {
                                late.append("\(direction) at \(fraction), card at \(f3(width)): the constant \(f3(lead)) is no nearer this tick's own \(f3(own)) "
                                            + "than the previous tick's \(f3(ownBefore)) \(detail)")
                            }
                            previousOwn = own
                        } else {
                            late.append("\(direction) at \(fraction): the constant or the views it is made from could not be read (lead \(lead.map { f3($0) } ?? "none"))")
                        }
                        guard let s = stand(rig, "\(direction) at \(fraction)") else { continue }
                        if abs(s.off) > 1 {
                            off.append("\(direction) at \(fraction), card at \(f3(width)): the tabs' middle is \(f3(s.off)) off the card's "
                                       + "(tabs \(f3(s.tabsMinX))...\(f3(s.tabsMaxX)) middle \(f3(s.tabsMid)), card middle \(f3(s.cardMid)), name's item from \(f3(s.containerMinX)), lead \(f3(s.leadMinX ?? -1))...\(f3(s.leadMaxX ?? -1)), the lead's constant \(lead.map { f3($0) } ?? "none"), the tabs' left edge wanted at \(f3(s.cardMid - s.tabsWidth / 2)))")
                        }
                    }
                    if between < 4 { cut.append("\(direction): \(between) widths strictly between the ends") }
                    if moved < 4 { cut.append("\(direction): the sidebar moved 8 pt or more at \(moved) ticks, not 4: a late constant has nowhere to show") }
                    XCTAssertEqual(shell.sidebarWidth, target, accuracy: 0.01, "\(direction): the fold did not end at \(target)")
                }
            }
            assigned += heard.assigned
            attached += heard.attached
        }
        XCTAssertTrue(unlisted.isEmpty, "the toolbar lists no helm.tabsLead with a view, so no tick's constant was read: \(unlisted)")
        XCTAssertEqual(ticks, 40, "\(ticks) ticks of 40 were read")
        XCTAssertTrue(cut.isEmpty, "the fold did not travel: \(cut)")
        XCTAssertTrue(off.isEmpty, "the tabs' middle left the card's middle at \(off.count) of 42 readings (40 ticks and two rests): \(off)")
        XCTAssertTrue(late.isEmpty, "the lead's constant is not that tick's own: \(late.count) failed rules over 40 ticks: \(late)")
        XCTAssertEqual(assigned, 0, "the fold gave the window \(assigned) toolbars, not none")
        XCTAssertEqual(attached, 0, "the fold told the shell \(attached) times that the window took a bar, not never")
    }

    /// The tabs centred on the card and the lead's constant the frame it makes: failures name `when`.
    private func assertCentredWithItsLead(_ rig: SettingsWindowRig, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let s = stand(rig, when, file: file, line: line) else { return }
        XCTAssertEqual(s.segments, 2, "\(when): the tabs are folded: \(s.line)", file: file, line: line)
        XCTAssertEqual(s.off, 0, accuracy: 1, "\(when): the tabs' middle is \(f(s.off)) off the card's: \(s.line)", file: file, line: line)
        guard let constant = leadConstant(rig, when, file: file, line: line) else { return }
        if let lo = s.leadMinX, let hi = s.leadMaxX, constant >= 36 {
            XCTAssertEqual(hi - lo, constant, accuracy: 1, "\(when): the lead item is \(f(hi - lo)) wide and its constant is \(f(constant))", file: file, line: line)
        }
    }

    /// **A change of look puts another bar on the window, in either direction, and that bar's lead item holds the
    /// constant of now: the tabs stand on the card's middle at a pane of 140.** The twin of
    /// `testAChangeOfLookPutsABarWithTheInsetOfNowOnTheWindow` for the tabs. The bar before and after are different
    /// objects, so the row reads a new bar, and each is read at the pane where the card stands. Seen on a window
    /// with flexible spaces: both looks, in both directions, the tabs 68 off the card's middle (530 against 598) and no
    /// lead item.
    func testAChangeOfLookPutsABarWithTheTabsLeadOfNowOnTheWindow() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = pageWithTabs(.flat) else { return }
        walk(rig, [140]) { _ in }
        XCTAssertEqual(rig.shell.shell.card.frame.minX, 140, accuracy: 0.5, "the pane does not stand at 140")
        assertCentredWithItsLead(rig, "flat, before the change, pane at 140")
        for look in [HelmBarAppearance.liquidGlass, .flat] {
            guard let before = rig.worn("the look was changed on a window that wore no toolbar") else { return }
            AppSettings.barAppearance = look
            rig.settle()
            SettingsWindowRig.pump()
            guard let after = rig.worn("the look changed and the window lost its toolbar") else { return }
            XCTAssertFalse(after === before, "a change of look to \(look.rawValue) left the window the bar of the other look: the row reads no new bar")
            assertCentredWithItsLead(rig, "\(look.rawValue), on the new bar, pane at 140")
        }
    }

    /// **A page's bar kept off the window comes back with the lead of now, not of the time it was left.** The page with
    /// tabs is on the window at 200 and then left for General; the pane moves to 140 there; the page is selected
    /// again. The bar that returns is the object the page had, and its tabs stand on the card's middle. The twin of
    /// `testACachedBarComesBackWithTheInsetOfNowNotOfWhenItWasLeft` for the tabs. Seen on a window with flexible
    /// spaces: the tabs 98 off the card's middle before the page was left and 68 off after the return, and no lead item.
    func testACachedBarComesBackWithTheTabsLeadOfNowNotOfWhenItWasLeft() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = pageWithTabs(.flat), let page = rig.worn("no page was left on a window that wore no toolbar") else { return }
        assertCentredWithItsLead(rig, "the page at 200 before it is left")
        rig.model.selection = .general
        rig.settle()
        XCTAssertFalse(rig.window.toolbar === page, "General shows the page's bar: nothing was left")
        walk(rig, [140]) { _ in }
        XCTAssertEqual(rig.shell.shell.card.frame.minX, 140, accuracy: 0.5, "the pane does not stand at 140")
        rig.model.selection = .module("probe.a")
        rig.settle()
        XCTAssertTrue(rig.window.toolbar === page, "the page came back with another bar than the one it was left with: the row reads no cached bar")
        assertCentredWithItsLead(rig, "the cached bar, back at 140")
    }

    /// **Narrowing the window itself, step by step, under both looks and at a sidebar of 200 and in the rail, no item
    /// of the toolbar is evicted while the tabs are whole: the tabs fold first.** The page has two tabs, an action
    /// and a search. The window's least width is lowered and the content is set to ten widths from 1060 to 380, each
    /// followed by the toolbar's settle and a layout of the frame view; forty settled steps in all. At each step an
    /// item whose `isVisible` is false while the tabs show two segments fails. The row requires that the items were
    /// visible at the first step (so an instrument that answers false for all is dead, not green) and that each of the
    /// four configurations saw the tabs whole at one step and folded at another. Green on a window with flexible
    /// spaces: forty steps, no item evicted with the tabs whole, every item visible at the widest step. No run made `isVisible` answer false here, so the instrument is seen alive in one direction only.
    func testNarrowingTheWindowFoldsTheTabsBeforeAnyItemIsEvicted() throws {
        PinnedBarSettings.pin(in: self)
        let widths: [CGFloat] = [1060, 960, 880, 800, 730, 660, 590, 520, 450, 380]
        var steps = 0
        var evicted: [String] = []
        var notSeen: [String] = []
        for look in Self.looks {
            for sidebar: CGFloat in [200, 56] {
                let label = "\(look.rawValue), sidebar \(sidebar == 200 ? "200" : "rail")"
                guard let rig = pageWithTabs(look) else { return }
                rig.window.contentMinSize = NSSize(width: 100, height: 100)
                walk(rig, [sidebar]) { _ in }
                var whole = 0
                var folded = 0
                for (index, width) in widths.enumerated() {
                    rig.window.setContentSize(NSSize(width: width, height: 760))
                    rig.settle()
                    rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
                    steps += 1
                    guard let toolbar = rig.worn("no item was read at \(label), \(width)") else { continue }
                    let segments = tabsControl(rig)?.segmentCount ?? -1
                    let gone = toolbar.items.filter { !$0.isVisible }.map(\.itemIdentifier.rawValue)
                    if index == 0 {
                        XCTAssertTrue(gone.isEmpty, "\(label), \(width): \(gone) of \(toolbar.items.map(\.itemIdentifier.rawValue)) are not visible at the widest step: the instrument answers false for items on the window")
                    }
                    if segments == 2 {
                        whole += 1
                        if !gone.isEmpty { evicted.append("\(label), window \(width): \(gone) evicted with the tabs whole") }
                    } else {
                        folded += 1
                    }
                }
                if whole == 0 || folded == 0 { notSeen.append("\(label): the tabs were whole at \(whole) steps and folded at \(folded)") }
            }
        }
        XCTAssertEqual(steps, 40, "\(steps) steps of 40 were taken")
        XCTAssertTrue(evicted.isEmpty, "an item was evicted while the tabs were whole: \(evicted)")
        XCTAssertTrue(notSeen.isEmpty, "a configuration never showed both the whole tabs and the folded: \(notSeen)")
    }

    /// **The lead is the card's middle less half the tabs, less the gap, less where the name ends, held to
    /// `1...1_000_000`; a parameter that is not a number or infinite, and a result that is, read 1.** Literal
    /// numbers for three ordinary cases: the full sidebar in a window 1060 wide (card from 200, 856 wide) with the
    /// tabs 168 wide (Flat) and 148 wide (Liquid Glass) and the name ending at 348.5, and the rail (card from 56,
    /// 1000 wide) with the name ending at 155; then each of not-a-number and both infinities in each of the five
    /// parameters, a result under 1, a result over `1_000_000`, the two bounds themselves, and a pair of finite
    /// parameters whose result overflows to infinity.
    func testANotANumberCentreReadsOne() {
        func lead(_ pane: CGFloat = 200, _ width: CGFloat = 856, _ tabs: CGFloat = 168, _ gap: CGFloat = 4.5,
                  _ name: CGFloat = 348.5) -> CGFloat {
            SettingsToolbar.tabsLead(paneLeading: pane, paneWidth: width, tabsWidth: tabs, gap: gap, nameMaxX: name)
        }
        XCTAssertEqual(lead(), 191, accuracy: 0.0001, "at a sidebar of 200 under Flat the lead is \(lead()), not 191")
        XCTAssertEqual(lead(200, 856, 148), 201, accuracy: 0.0001, "at a sidebar of 200 under Liquid Glass the lead is \(lead(200, 856, 148)), not 201")
        XCTAssertEqual(lead(56, 1000, 168, 4.5, 155), 312.5, accuracy: 0.0001, "in the rail the lead is \(lead(56, 1000, 168, 4.5, 155)), not 312.5")

        let ordinary: [CGFloat] = [200, 856, 168, 4.5, 348.5]
        let names = ["paneLeading", "paneWidth", "tabsWidth", "gap", "nameMaxX"]
        for bad: CGFloat in [.nan, .infinity, -.infinity] {
            for index in ordinary.indices {
                var arguments = ordinary
                arguments[index] = bad
                let answer = lead(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4])
                XCTAssertEqual(answer, 1, accuracy: 0.0001, "a \(names[index]) of \(bad) leads by \(answer), not 1")
            }
        }
        XCTAssertEqual(lead(200, 856, 168, 4.5, 600), 1, accuracy: 0.0001, "a name that ends past the centred place leads by \(lead(200, 856, 168, 4.5, 600)), not 1")
        XCTAssertEqual(lead(0, 2, 0, 0, 0.5), 1, accuracy: 0.0001, "a result of 0.5 reads \(lead(0, 2, 0, 0, 0.5)), not 1")
        XCTAssertEqual(lead(0, 2, 0, 0, 0), 1, accuracy: 0.0001, "a result of exactly 1 reads \(lead(0, 2, 0, 0, 0)), not 1")
        XCTAssertEqual(lead(0, 4_000_000, 0, 0, 0), 1_000_000, accuracy: 0.0001, "a result of 2 000 000 reads \(lead(0, 4_000_000, 0, 0, 0)), not 1 000 000")
        XCTAssertEqual(lead(0, 2_000_000, 0, 0, 0), 1_000_000, accuracy: 0.0001, "a result of exactly 1 000 000 reads \(lead(0, 2_000_000, 0, 0, 0)), not 1 000 000")
        XCTAssertEqual(lead(0, 2_000_002, 0, 0, 0), 1_000_000, accuracy: 0.0001, "a result of 1 000 001 reads \(lead(0, 2_000_002, 0, 0, 0)), not 1 000 000")
        let overflow = lead(.greatestFiniteMagnitude, 856, 168, 4.5, -.greatestFiniteMagnitude)
        XCTAssertEqual(overflow, 1, accuracy: 0.0001, "finite parameters whose result overflows to infinity lead by \(overflow), not 1")
    }

    // MARK: - Where the search field stands beside the tabs

    /// The id, title and symbol of each of the three tabs of the page the rows below declare. The titles are
    /// shortened from the first version of these rows ("Installed packages", "Available updates", "Health check"),
    /// whose whole tabs were 400 points wide under Flat and 365 under Liquid Glass, so that the whole tabs come near a
    /// real page's; every `[search beside tabs]` line prints the width they have. In the run that read them they
    /// were 343 points wide whole under Flat and 310 under Liquid Glass.
    private static let shapedTabs: [(id: String, title: String, symbol: String)] = [
        ("installed", "Installed packages", "shippingbox"),
        ("updates", "Updates", "arrow.up.circle"),
        ("health", "Health check", "stethoscope")]

    /// A page of the shape a package manager's has: three tabs, one action and a search; with `hiddenAction` a
    /// second action that is declared and not visible.
    private static func shapedContent(hiddenAction: Bool = false) -> HelmPageToolbarContent {
        var actions = [HelmToolbarAction(id: "refresh", title: "Refresh list", symbol: "arrow.clockwise") {}]
        if hiddenAction {
            actions.insert(HelmToolbarAction(id: "upgradeAll", title: "Upgrade all", symbol: "arrow.down.to.line",
                                             isVisible: false) {}, at: 0)
        }
        return HelmPageToolbarContent(
            tabs: shapedTabs.map { HelmToolbarTab(id: $0.id, title: $0.title, symbol: $0.symbol) },
            selectedTab: .constant("installed"),
            actions: actions,
            search: HelmToolbarSearch(prompt: "Search packages", text: .constant("")))
    }

    /// The window as the app builds it under `look`, the shaped page declared on its channel and selected, the
    /// window's least width lowered so that a row may narrow it.
    private func shapedPage(_ look: HelmBarAppearance, hiddenAction: Bool = false,
                            file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        AppSettings.barAppearance = look
        guard let rig = build(file: file, line: line) else { return nil }
        rig.channel.declare(Self.shapedContent(hiddenAction: hiddenAction), token: "probe.shaped",
                            generation: rig.channel.nextGeneration())
        rig.model.selection = .module("probe.shaped")
        rig.window.contentMinSize = NSSize(width: 100, height: 100)
        rig.settle()
        SettingsWindowRig.pump()
        return rig
    }

    /// What the window shows of the shaped page at one window width and sidebar: the parts `stand` reads, the
    /// actions' and the search item's frames in window x, and the search field's width and whether it is hidden.
    private struct Shaped {
        let look: HelmBarAppearance
        let window: CGFloat
        let sidebar: CGFloat
        let stand: Stand
        let actionsMinX: CGFloat?
        let actionsMaxX: CGFloat?
        let searchMinX: CGFloat?
        let searchMaxX: CGFloat?
        let fieldWidth: CGFloat?
        let fieldHidden: Bool?

        /// The room the field has beside whole tabs on the card's middle: from the field's right edge back over the field's gap to the actions, the actions, `tabsToActions` and the tabs' half
        /// from the card's middle. A number computed from widths read at another window, not read here.
        func room(tabsWidth: CGFloat, actionsWidth: CGFloat, actionsToSearch: CGFloat, tabsToActions: CGFloat) -> CGFloat? {
            searchMaxX.map { $0 - (stand.cardMid + tabsWidth / 2 + tabsToActions + actionsWidth + actionsToSearch) }
        }

        var line: String {
            func f(_ value: CGFloat?) -> String { value.map { String(format: "%.1f", Double($0)) } ?? "none" }
            let hidden = fieldHidden.map { $0 ? "hidden" : "shown" } ?? "none"
            return "\(look.rawValue) window \(f(window)) sidebar \(f(sidebar)); card middle \(f(stand.cardMid)); tabs \(f(stand.tabsMinX))...\(f(stand.tabsMaxX)) "
                + "(\(stand.segments) segments, \(f(stand.off)) off the card's middle); actions \(f(actionsMinX))...\(f(actionsMaxX)); "
                + "search field frame \(f(searchMinX))...\(f(searchMaxX)), field \(f(fieldWidth)) wide, \(hidden); "
                + "lead item \(f(stand.leadMinX))...\(f(stand.leadMaxX)); name host \(f(stand.nameMinX))...\(f(stand.nameMaxX))"
        }
    }

    /// The shaped page placed at `width` and `sidebar`, laid out and settled, read, and printed as one line whatever
    /// the row then says of it. nil after a failure.
    private func readShaped(_ rig: SettingsWindowRig, _ look: HelmBarAppearance, window width: CGFloat, sidebar: CGFloat,
                            _ label: String, file: StaticString = #filePath, line: UInt = #line) -> Shaped? {
        place(rig, window: width, sidebar: sidebar)
        SettingsWindowRig.pump()
        rig.settle()
        XCTAssertEqual(rig.window.contentView?.frame.width ?? 0, width, accuracy: 0.5,
                       "\(label): the window is not \(width) wide: the row stands at another width", file: file, line: line)
        guard let s = stand(rig, label, file: file, line: line), let toolbar = rig.window.toolbar else { return nil }
        func box(_ view: NSView?) -> CGRect? {
            guard let view, view.window != nil else { return nil }
            return view.convert(view.bounds, to: nil)
        }
        let actions = box(SettingsWindowRig.item("helm.actions", in: toolbar)?.view)
        let searchItem = SettingsWindowRig.item("helm.search", in: toolbar) as? NSSearchToolbarItem
        let field = searchItem?.searchField
        let search = box(field)
        let shaped = Shaped(look: look, window: width, sidebar: sidebar, stand: s,
                            actionsMinX: actions?.minX, actionsMaxX: actions?.maxX,
                            searchMinX: search?.minX, searchMaxX: search?.maxX,
                            fieldWidth: field.flatMap { box($0)?.width ?? $0.frame.width }, fieldHidden: field?.isHidden)
        print("[search beside tabs] \(label): \(shaped.line)")
        return shaped
    }

    /// The window width and sidebar the first rows stand at.
    private static let shapedWindow: CGFloat = 1060
    private static let shapedSidebar: CGFloat = 200

    /// **At a window of 1060 and a sidebar of 200 the tabs are whole and on the card's middle, and the search
    /// field has given room: narrower than its usual width, not narrower than its floor.** Each claim has its
    /// own assertion, so a page whose tabs are folded fails on the tabs and on the field apart. Every failure
    /// prints the whole reading.
    private func assertTheFieldGivesRoomAtTheDefaultWidth(_ look: HelmBarAppearance, hiddenAction: Bool = false,
                                                           file: StaticString = #filePath, line: UInt = #line) {
        PinnedBarSettings.pin(in: self)
        guard let rig = shapedPage(look, hiddenAction: hiddenAction, file: file, line: line) else { return }
        let label = "\(look.rawValue) \(Int(Self.shapedWindow))/\(Int(Self.shapedSidebar))\(hiddenAction ? " with a hidden second action" : "")"
        guard let r = readShaped(rig, look, window: Self.shapedWindow, sidebar: Self.shapedSidebar, label, file: file, line: line) else { return }
        XCTAssertEqual(r.stand.segments, 3, "\(label): the tabs are \(r.stand.segments) segments, not the 3 of whole tabs. \(r.line)", file: file, line: line)
        XCTAssertEqual(r.stand.off, 0, accuracy: 1, "\(label): the tabs' middle is \(f(r.stand.off)) from the card's. \(r.line)", file: file, line: line)
        XCTAssertEqual(r.fieldHidden, false, "\(label): the search field is not shown. \(r.line)", file: file, line: line)
        guard let width = r.fieldWidth else {
            XCTFail("\(label): the search item has no field in the window. \(r.line)", file: file, line: line)
            return
        }
        XCTAssertLessThan(width, ShellBarLayout.searchWidth,
                          "\(label): the field is \(f(width)) wide, not narrower than its usual \(f(ShellBarLayout.searchWidth)): it gave no room. \(r.line)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(width, ShellBarLayout.searchFloor - 0.5,
                                    "\(label): the field is \(f(width)) wide, narrower than its floor \(f(ShellBarLayout.searchFloor)). \(r.line)", file: file, line: line)
    }

    /// **Under Liquid Glass, at 1060 and a sidebar of 200, a page with three tabs, an action and a search shows
    /// whole tabs on the card's middle and a field that gave room.** With the first titles of these rows (whole tabs
    /// 365 wide) this row was green: the tabs 3 segments, 0.5 off the card's middle, the field 193 wide and shown. With
    /// the shortened titles it read the tabs 3 segments on the card's middle and the field 221 wide and shown.
    func testUnderLiquidGlassTheFieldGivesRoomBeforeTheTabsFold() throws {
        assertTheFieldGivesRoomAtTheDefaultWidth(.liquidGlass)
    }

    /// **Under Flat, the same.** With the first titles of these rows (whole tabs 400 wide) this row was green: the
    /// tabs 3 segments on the card's middle, the field 176 wide and shown. With the shortened titles it read the
    /// tabs 3 segments, 0.5 off the card's middle, and the field 204 wide and shown.
    func testUnderFlatTheFieldGivesRoomBeforeTheTabsFold() throws {
        assertTheFieldGivesRoomAtTheDefaultWidth(.flat)
    }

    /// **The same page with a second action declared and not visible, which the capsule reserves the width of
    /// (72 wide against 36 without it), under Liquid Glass: at the default width the tabs are whole on the card's
    /// middle and the field is shown, narrower than its usual width and not under its floor.** The titles are
    /// shaped so that the whole tabs are near a real page's, which leaves the field about 185 points at 1060/200.
    /// With the first titles (whole tabs 365 wide, about 157 points for the field) this row was red by two
    /// assertions, the field 36 wide and hidden. With the shortened titles it read green: the tabs 3 segments on
    /// the card's middle, the capsule 791...863 and the field 185 wide and shown.
    func testUnderLiquidGlassAHiddenSecondActionDoesNotCollapseTheField() throws {
        assertTheFieldGivesRoomAtTheDefaultWidth(.liquidGlass, hiddenAction: true)
    }

    /// **The same under Flat**, where the shaped titles leave the field about 168 points at 1060/200. With the
    /// first titles (whole tabs 400 wide, 140 points worked out for the field) this row was red by the same two
    /// assertions. With the shortened titles it was red by one, the tabs: the field stood 168 wide and shown, the capsule at 808...880, and
    /// the tabs' control had 1 segment while the tabs' item stood 457...800, 343 wide, 0.5 off the card's middle. Since a
    /// regrowth of the field within its offer no longer folds the tabs (`growthIsWithinTheOffer`) it reads green: the tabs 3
    /// segments at 457...800, 0.5 off the card's middle, the capsule at 808...880 and the field 168 wide and shown. Seen red
    /// again with the cap's constant not written, and with `predictedSlack` not answering from the offer (the tabs 1 segment,
    /// not 3).
    func testUnderFlatAHiddenSecondActionDoesNotCollapseTheField() throws {
        assertTheFieldGivesRoomAtTheDefaultWidth(.flat, hiddenAction: true)
    }

    /// The width of a window that leaves the field `room` beside whole, card-centred tabs, worked out from the
    /// reference reading `reference` taken at `referenceWindow`: the room is the bar's right edge less the card's
    /// middle, half the tabs, `tabsToActions`, the actions and their gap to the field, and with the window
    /// `d` wider the right edge is `d` further right and the card's middle `d / 2`, so the room moves by `d / 2`.
    private static func windowWidth(forRoom room: CGFloat, reference r: Shaped, referenceRoom: CGFloat) -> CGFloat {
        (r.window + 2 * (room - referenceRoom)).rounded()
    }

    /// What the shaped page reads at a window of 1400 (everything fits) under one look, and the room the field has
    /// there beside whole tabs on the card's middle, from which the width of a window that leaves any other room is
    /// worked out. `tabsToActions` is 8 and is assumed, not read.
    private struct RoomReference {
        let wide: Shaped
        let tabsWidth: CGFloat
        let actionsWidth: CGFloat
        let actionsToSearch: CGFloat
        let wideRoom: CGFloat
        static let tabsToActions: CGFloat = 8

        /// The room the field has beside whole tabs on the card's middle in the reading `r`, worked out from the
        /// frames read there and the widths read at the reference window.
        func room(of r: Shaped) -> CGFloat? {
            r.room(tabsWidth: tabsWidth, actionsWidth: actionsWidth, actionsToSearch: actionsToSearch, tabsToActions: Self.tabsToActions)
        }
    }

    /// The shaped page under `look` read at a window of 1400 and a sidebar of 200 on a window of its own; nil after
    /// a failure.
    private func roomReference(_ look: HelmBarAppearance) -> RoomReference? {
        guard let wideRig = shapedPage(look) else { return nil }
        guard let wide = readShaped(wideRig, look, window: 1400, sidebar: Self.shapedSidebar, "\(look.rawValue) 1400/200 reference"),
              let actionsMin = wide.actionsMinX, let actionsMax = wide.actionsMaxX, let searchMin = wide.searchMinX
        else { XCTFail("\(look.rawValue): the reference reading has no actions or search frame"); return nil }
        XCTAssertEqual(wide.stand.segments, 3, "\(look.rawValue): the tabs are \(wide.stand.segments) segments at the reference window 1400, not 3. \(wide.line)")
        let probe = RoomReference(wide: wide, tabsWidth: wide.stand.tabsWidth, actionsWidth: actionsMax - actionsMin,
                                  actionsToSearch: searchMin - actionsMax, wideRoom: 0)
        guard let wideRoom = probe.room(of: wide) else { XCTFail("\(look.rawValue): no room was worked out at the reference window"); return nil }
        return RoomReference(wide: wide, tabsWidth: probe.tabsWidth, actionsWidth: probe.actionsWidth,
                             actionsToSearch: probe.actionsToSearch, wideRoom: wideRoom)
    }

    /// How far the room worked out from the frames read at a window may stand from the room the window was
    /// chosen for, before the row says its width is wrong and judges nothing.
    private static let roomTolerance: CGFloat = 10

    /// How far a shown field's width may stand from the room worked out for it: 2 points, chosen; in the runs that read it the
    /// shown field was exactly the room wide (210 at OPEN; 160, 170, 180, 190 and 200 in the sweep).
    private static let offeredTolerance: CGFloat = 2

    /// The shaped page read, on a window of its own, at the window that leaves the field `target` points beside
    /// whole tabs on the card's middle; printed before the reading. nil after a failure, among them a room worked
    /// out from the frames read there more than `roomTolerance` from `target`.
    private func readAtRoom(_ target: CGFloat, _ look: HelmBarAppearance, _ ref: RoomReference, _ name: String)
        -> (read: Shaped, room: CGFloat, label: String)? {
        let width = Self.windowWidth(forRoom: target, reference: ref.wide, referenceRoom: ref.wideRoom)
        let label = "\(look.rawValue), \(name), window \(Int(width))/200"
        print("[search beside tabs] \(label): whole tabs \(f(ref.tabsWidth)) wide, actions \(f(ref.actionsWidth)) wide, actions to search \(f(ref.actionsToSearch)), tabs to actions \(f(RoomReference.tabsToActions)) assumed, reference room \(f(ref.wideRoom)), room asked \(f(target))")
        guard let rig = shapedPage(look),
              let r = readShaped(rig, look, window: width, sidebar: Self.shapedSidebar, label) else { return nil }
        guard let room = ref.room(of: r) else { XCTFail("\(label): no room was worked out. \(r.line)"); return nil }
        let missed = abs(room - target) > Self.roomTolerance
        XCTAssertFalse(missed, "\(label): the room worked out from the frames read at this window is \(f(room)), not within \(f(Self.roomTolerance)) of the \(f(target)) asked: the row's width is wrong, nothing is judged. \(r.line)")
        return missed ? nil : (r, room, label)
    }

    /// **Where the room worked out for the field is 30 under its floor the tabs are folded, and at 150 and 210 they are whole
    /// (the fold's boundary is held by `testTheTabsFoldOnePointUnderNoSlackAndStayWholeAtNone`); between the floor and where
    /// AppKit itself collapses the field, the tabs are whole and the field is what AppKit draws.** Under
    /// each look, on a fresh window each, the shaped page is read at a window of 1400 (everything fits) for the
    /// whole tabs' width, the actions' width and the gap between the actions and the search; the room the field is
    /// left beside whole tabs on the card's middle is then worked out for three windows, each read on a window of
    /// its own (`tabsToActions` 8 is assumed, and each window's room is worked out again from the frames read there,
    /// which must stand within `roomTolerance` of the room asked).
    /// - BELOW (the room worked out by hand 30 points under the floor; the slack the rule reads there is -69 under Flat, see
    ///   below): the tabs must be 1 segment.
    /// - BAND (150, over the floor and, in an unshown window, under the room at which AppKit collapses the field):
    ///   the tabs must be 3 segments on the card's middle. The field's state is printed and not asserted; only that
    ///   it is no wider than the room, which AppKit's choice cannot make false.
    /// - OPEN (210, under the usual width): the tabs 3 segments on the card's middle, the field shown, not under its
    ///   floor, under its usual width and within `offeredTolerance` of the room worked out. That room is the row's own arithmetic from
    ///   the field's frame; the offer written to the cap was read 4 points over it at window 951 under Flat, where 150 is
    ///   worked out (154.000 written to the cap), so this row does not hold the offer and the field's width to one number.
    /// Every failure says which point it is and prints the reading.
    ///
    /// **BELOW is not 30 points under the floor as the rule reads it.** The "room 90" is worked out by hand from the frames and
    /// counts the tabs on the card's middle; in a window never shown under Flat the name holds the whole tabs right of
    /// the card's middle at window 831, so the room the rule charges is less. Read (a run of a temporary row, since deleted; Flat): the
    /// slack `settle` judged by at window 831 was -69.00, that is 69 points under nothing, not -30. The row therefore does not hold the fold's boundary: it folds at -69 under a rule that waits for
    /// -40 as well (a mutant `slack < -40` stayed green on it), and `testTheTabsFoldOnePointUnderNoSlackAndStayWholeAtNone`
    /// is the row that holds the boundary. Under Liquid Glass the slack at this row's window was not read.
    ///
    /// BELOW was red before the fold decided on the offered room: with the first titles of these rows (whole tabs
    /// 400 wide under Flat and 365 under Liquid Glass) at windows 888 and 853, 90 points of room worked out, the
    /// tabs stayed 3 segments, 43 and 47 points off the card's middle, and the field was collapsed to its
    /// 36-wide magnifier.
    ///
    /// With the shortened titles (whole tabs 343 wide under Flat and 310 under Liquid Glass) the row was green. BELOW,
    /// at windows 831 and 798, the tabs were 1 segment and the field, given their room back, shown 180 and 169
    /// wide. BAND, at 951 and 918: the tabs 3 segments on the card's middle and the field collapsed to its 36-wide
    /// magnifier under both looks, with 150 points of room worked out. OPEN, at 1071 and 1038: the tabs 3 segments
    /// on the card's middle and the field shown, 210 wide, the room worked out.
    func testTheTabsFoldOnlyWhereTheFieldWouldFallBelowItsFloor() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let ref = roomReference(look) else { return }
            if let got = readAtRoom(ShellBarLayout.searchFloor - 30, look, ref, "BELOW the floor") {
                XCTAssertEqual(got.read.stand.segments, 1,
                               "\(got.label): the room beside whole tabs is \(f(got.room)), under the floor \(f(ShellBarLayout.searchFloor)), and the tabs are \(got.read.stand.segments) segments, not folded to 1. \(got.read.line)")
            }
            if let got = readAtRoom(150, look, ref, "BAND over the floor") {
                let r = got.read
                XCTAssertEqual(r.stand.segments, 3,
                               "\(got.label): the room beside whole tabs is \(f(got.room)), over the floor \(f(ShellBarLayout.searchFloor)), and the tabs are \(r.stand.segments) segments, not whole (3). \(r.line)")
                XCTAssertEqual(r.stand.off, 0, accuracy: 1, "\(got.label): the tabs' middle is \(f(r.stand.off)) from the card's. \(r.line)")
                let state = r.fieldHidden.map { $0 ? "collapsed to its magnifier" : "shown" } ?? "absent"
                print("[search beside tabs] \(got.label): the band reading, room \(f(got.room)), field \(state), \(f(r.fieldWidth ?? -1)) wide")
                if let width = r.fieldWidth {
                    XCTAssertLessThanOrEqual(width, got.room + 0.5, "\(got.label): the field is \(f(width)) wide, wider than the \(f(got.room)) of room worked out for it. \(r.line)")
                } else {
                    XCTFail("\(got.label): the search item has no field in the window. \(r.line)")
                }
            }
            if let got = readAtRoom(210, look, ref, "OPEN") {
                let r = got.read
                XCTAssertEqual(r.stand.segments, 3,
                               "\(got.label): the room beside whole tabs is \(f(got.room)), and the tabs are \(r.stand.segments) segments, not whole (3). \(r.line)")
                XCTAssertEqual(r.stand.off, 0, accuracy: 1, "\(got.label): the tabs' middle is \(f(r.stand.off)) from the card's. \(r.line)")
                XCTAssertEqual(r.fieldHidden, false, "\(got.label): the field is collapsed to its magnifier with \(f(got.room)) points of room worked out for it. \(r.line)")
                if let width = r.fieldWidth {
                    XCTAssertGreaterThanOrEqual(width, ShellBarLayout.searchFloor - 0.5, "\(got.label): the field is \(f(width)) wide, under its floor \(f(ShellBarLayout.searchFloor)). \(r.line)")
                    XCTAssertLessThan(width, ShellBarLayout.searchWidth, "\(got.label): the field is \(f(width)) wide, not under its usual \(f(ShellBarLayout.searchWidth)). \(r.line)")
                    XCTAssertEqual(width, got.room, accuracy: Self.offeredTolerance, "\(got.label): the field is \(f(width)) wide, not the \(f(got.room)) of room worked out for it. \(r.line)")
                } else {
                    XCTFail("\(got.label): the search item has no field in the window. \(r.line)")
                }
            }
        }
    }

    /// **Between the band and the open field, ten points at a time: the tabs stay whole on the card's middle, the
    /// field is no wider than the room, and a field that is shown is the room wide.** Rooms 160, 170, 180, 190 and 200
    /// under each look, each on a window of its own; the state of the field is printed for each and the widest room
    /// read collapsed and the narrowest read shown are printed per look. Whether the field is collapsed at any of them
    /// is AppKit's choice in a window never shown and is not asserted; this row is how that choice is read. In the
    /// run that wrote this: the field was shown at all five under both looks, as wide as the room (160, 170, 180,
    /// 190, 200), the tabs 3 segments on the card's middle; the room 150 of the row above was read collapsed.
    func testTheFieldIsReadAtEachTenPointsOfRoomBetweenTheBandAndTheOpenField() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let ref = roomReference(look) else { return }
            var collapsed: [CGFloat] = []
            var shown: [CGFloat] = []
            for target: CGFloat in [160, 170, 180, 190, 200] {
                guard let got = readAtRoom(target, look, ref, "SWEEP") else { continue }
                let r = got.read
                XCTAssertEqual(r.stand.segments, 3, "\(got.label): the room beside whole tabs is \(f(got.room)), and the tabs are \(r.stand.segments) segments, not whole (3). \(r.line)")
                XCTAssertEqual(r.stand.off, 0, accuracy: 1, "\(got.label): the tabs' middle is \(f(r.stand.off)) from the card's. \(r.line)")
                guard let width = r.fieldWidth, let hidden = r.fieldHidden else {
                    XCTFail("\(got.label): the search item has no field in the window. \(r.line)")
                    continue
                }
                XCTAssertLessThanOrEqual(width, got.room + 0.5, "\(got.label): the field is \(f(width)) wide, wider than the \(f(got.room)) of room worked out for it. \(r.line)")
                if hidden {
                    collapsed.append(got.room)
                } else {
                    shown.append(got.room)
                    XCTAssertEqual(width, got.room, accuracy: Self.offeredTolerance, "\(got.label): the field is \(f(width)) wide, not the \(f(got.room)) of room worked out for it. \(r.line)")
                }
            }
            func list(_ rooms: [CGFloat]) -> String { rooms.map { f($0) }.joined(separator: ", ") }
            print("[search beside tabs] \(look.rawValue) sweep: widest room read collapsed \(collapsed.max().map { f($0) } ?? "none"), narrowest room read shown \(shown.min().map { f($0) } ?? "none"), rooms read collapsed [\(list(collapsed))], shown [\(list(shown))]")
        }
    }

    /// **In a window wide enough for everything, under each look, the tabs are whole on the card's middle and the
    /// field is the usual width: `searchWidth`, within a point.** The window is 1400 wide and the sidebar 200. The row first asserted the usual width within a point and was red while the field was not capped (it was 325 wide); it
    /// then asked only that the field be no narrower, and asks the width within a point again since the cap: 283 wide under both
    /// looks, the tabs 3 segments, under Flat 0.5 off the card's middle.
    func testInAWindowWideEnoughForEverythingTheFieldIsNotNarrowed() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let rig = shapedPage(look) else { return }
            let label = "\(look.rawValue) 1400/200"
            guard let r = readShaped(rig, look, window: 1400, sidebar: Self.shapedSidebar, label) else { return }
            XCTAssertEqual(r.stand.segments, 3, "\(label): the tabs are \(r.stand.segments) segments, not 3. \(r.line)")
            XCTAssertEqual(r.stand.off, 0, accuracy: 1, "\(label): the tabs' middle is \(f(r.stand.off)) from the card's. \(r.line)")
            XCTAssertEqual(r.fieldHidden, false, "\(label): the search field is not shown. \(r.line)")
            XCTAssertEqual(r.fieldWidth ?? -1, ShellBarLayout.searchWidth, accuracy: 1,
                           "\(label): the field is \(f(r.fieldWidth ?? -1)) wide, not its usual \(f(ShellBarLayout.searchWidth)). \(r.line)")
        }
    }

    // MARK: - What the fold on the search field's growth lets through

    /// **How these rows reach the clause `!growthIsWithinTheOffer(bar, width: width)`.** It is a private method of
    /// the toolbar, called only from the toolbar's observer of the search field's frame (M2,
    /// `searchFieldFrameChanged`), which runs at once, on the caller's stack, when the field's frame changes. A row
    /// therefore gives the field a width itself with `setFrameSize`: **that stands for AppKit's layout giving the
    /// field a wider frame than it had**, which a window never shown does not do on demand. Nothing is waited for: the
    /// observer's verdict is on the page bar before `setFrameSize` returns, and the rows read it there by `Mirror`
    /// (`tabsFolded`, `searchOpening`, `rest`, `lastFieldWidth`, `searchOfferCap`: private fields, read by label, and a
    /// row that cannot read one fails saying which) and from the tabs' control (`segmentCount`, 3 whole and 1
    /// folded). The offer in force is read from the cap on the field's width (`searchOfferCap`), which `settle`
    /// writes from the same `searchOffer(_:tabsWidth:)` the clause asks, to within the hundredth of a point it
    /// leaves alone.
    ///
    /// **The arrangement every row stands in (`inTheBand`).** The shaped page at the window that leaves the field 150
    /// points beside whole tabs (the BAND of `testTheTabsFoldOnlyWhereTheFieldWouldFallBelowItsFloor`), where AppKit
    /// itself collapses the field to its magnifier and the tabs stay whole: it is the state M2's other conditions
    /// ask for (the tabs whole, the field hidden so that `rest.collapsed` is true, `rest.room` the room now, the
    /// field idle) with nothing written to the bar by the row, and the offer is the floor 120 plus the slack, about
    /// 150 and not under the floor. A row that finds the arrangement otherwise fails by naming what it found, and
    /// judges nothing. Read in the run that wrote the rows: window 951/200, the tabs 3 segments, the field 36 wide and
    /// hidden, the offer 154 (slack 34), `rest.room` 747, the field's last width 36.
    private struct InTheBand {
        let rig: SettingsWindowRig
        let ref: RoomReference
        let toolbar: NSToolbar
        let bar: Any
        let field: NSSearchField
        let label: String
        /// The width the cap holds for the idle field: the offer in force.
        let offer: CGFloat
    }

    /// The page bar's fields the rows read.
    private struct BarState {
        let folded: Bool
        let opening: Bool
        let collapsed: Bool
        let restRoom: CGFloat
        let lastFieldWidth: CGFloat
        let cap: NSLayoutConstraint
    }

    /// A stored field of a value by its label; nil when it has none.
    private func stored(_ label: String, of value: Any) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == label }?.value
    }

    /// An optional's content, the value itself when it is not one; nil for nil.
    private func inside(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional ? mirror.children.first?.value : value
    }

    /// The toolbar's page bar whose own toolbar is the one the window wears; nil when there is none.
    private func wornPageBar(_ rig: SettingsWindowRig, of owner: SettingsToolbar) -> Any? {
        guard let cache = stored("pageBars", of: owner) else { return nil }
        for child in Mirror(reflecting: cache).children {
            let pair = Array(Mirror(reflecting: child.value).children)
            if pair.count == 2, (stored("toolbar", of: pair[1].value) as? NSToolbar) === rig.window.toolbar {
                return pair[1].value
            }
        }
        return nil
    }

    private func barState(_ bar: Any, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> BarState? {
        guard let folded = stored("tabsFolded", of: bar) as? Bool,
              let opening = stored("searchOpening", of: bar) as? Bool,
              let rest = inside(stored("rest", of: bar)),
              let collapsed = stored("collapsed", of: rest) as? Bool,
              let restRoom = stored("room", of: rest) as? CGFloat,
              let last = stored("lastFieldWidth", of: bar) as? CGFloat,
              let cap = inside(stored("searchOfferCap", of: bar)) as? NSLayoutConstraint
        else {
            XCTFail("\(label): the page bar's tabsFolded, searchOpening, rest (collapsed, room), lastFieldWidth or searchOfferCap could not be read by Mirror: nothing is judged",
                    file: file, line: line)
            return nil
        }
        return BarState(folded: folded, opening: opening, collapsed: collapsed, restRoom: restRoom,
                        lastFieldWidth: last, cap: cap)
    }

    /// The shaped page, under `look`, at the window that leaves the field 150 beside whole tabs, settled, and the
    /// state M2's other conditions ask for checked; nil after a failure that names what was found instead.
    /// Needs `PinnedBarSettings.pin(in:)` called by the row first.
    private func inTheBand(_ look: HelmBarAppearance, _ name: String,
                           file: StaticString = #filePath, line: UInt = #line) -> InTheBand? {
        let label = "\(look.rawValue), \(name)"
        guard let ref = roomReference(look) else { return nil }
        let width = Self.windowWidth(forRoom: 150, reference: ref.wide, referenceRoom: ref.wideRoom)
        guard let rig = shapedPage(look, file: file, line: line) else { return nil }
        place(rig, window: width, sidebar: Self.shapedSidebar)
        SettingsWindowRig.pump()
        rig.settle()
        guard let toolbar = rig.worn("\(label): no band was read", file: file, line: line),
              let owner = toolbar.delegate as? SettingsToolbar,
              let bar = wornPageBar(rig, of: owner),
              let field = (SettingsWindowRig.item("helm.search", in: toolbar) as? NSSearchToolbarItem)?.searchField,
              let state = barState(bar, label, file: file, line: line),
              let s = stand(rig, label, file: file, line: line)
        else {
            XCTFail("\(label): the window has no worn page bar, search field or stand to read: nothing is judged", file: file, line: line)
            return nil
        }
        var found: [String] = []
        if s.segments != 3 { found.append("the tabs are \(s.segments) segments, not 3") }
        if !field.isHidden { found.append("the field is shown (\(f(field.frame.width)) wide), not collapsed") }
        if state.folded { found.append("tabsFolded is true") }
        if state.opening { found.append("searchOpening is true") }
        if !state.collapsed { found.append("rest.collapsed is false") }
        if state.restRoom != owner.offeredRoom() { found.append("rest.room \(f(state.restRoom)) is not the room now \(f(owner.offeredRoom()))") }
        if !state.cap.isActive { found.append("the offer cap is not active") }
        if state.cap.constant < ShellBarLayout.searchFloor + 10 || state.cap.constant >= ShellBarLayout.searchWidth {
            found.append("the offer \(f(state.cap.constant)) is not in \(f(ShellBarLayout.searchFloor + 10))..<\(f(ShellBarLayout.searchWidth))")
        }
        if state.lastFieldWidth >= state.cap.constant { found.append("the field's last width \(f(state.lastFieldWidth)) is not under the offer \(f(state.cap.constant))") }
        guard found.isEmpty else {
            XCTFail("\(label): the arrangement is not the band: \(found.joined(separator: "; ")). Nothing is judged.", file: file, line: line)
            return nil
        }
        print("[fold on growth] \(label): window \(f(width))/200; tabs \(s.segments) segments; field \(f(field.frame.width)) wide, hidden; offer \(f3(state.cap.constant)); last field width \(f(state.lastFieldWidth)); rest.room \(f(state.restRoom))")
        return InTheBand(rig: rig, ref: ref, toolbar: toolbar, bar: bar, field: field, label: label,
                         offer: state.cap.constant)
    }

    /// Gives the field `width` as a frame, at once, and reads the toolbar's verdict as it stands on return: the
    /// bar's two flags and the tabs' segments. Printed whatever the row then says of it.
    private func growField(_ b: InTheBand, to width: CGFloat, _ what: String)
        -> (folded: Bool, opening: Bool, segments: Int)? {
        b.field.setFrameSize(NSSize(width: width, height: b.field.frame.height))
        guard let after = barState(b.bar, "\(b.label), \(what)") else { return nil }
        let segments = tabsControl(b.rig)?.segmentCount ?? -1
        print("[fold on growth] \(b.label), \(what): field given \(f3(width)) (offer \(f3(b.offer))): tabsFolded \(after.folded), searchOpening \(after.opening), \(segments) segments")
        return (after.folded, after.opening, segments)
    }

    /// One assertion per part of the verdict on a growth, each with its own sentence: the tabs' flag, the bar's
    /// opening flag (which `folds` sets together with the fold) and the tabs' segments.
    private func expectGrowth(folds: Bool, _ got: (folded: Bool, opening: Bool, segments: Int), _ why: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.folded, folds, "\(why): tabsFolded is \(got.folded), not \(folds)", file: file, line: line)
        XCTAssertEqual(got.opening, folds, "\(why): searchOpening is \(got.opening), not \(folds): the bar is \(got.opening ? "left opening" : "not marked opening")", file: file, line: line)
        XCTAssertEqual(got.segments, folds ? 1 : 3, "\(why): the tabs are \(got.segments) segments, not \(folds ? 1 : 3)", file: file, line: line)
    }

    /// **A field growing from its collapsed 36 to 40 points over the offer still folds the tabs and marks the bar
    /// opening: the fold the clause must not take away.** In the band the offer is about 150
    /// (`offer`); the field is given `offer + 40`, about 190, which is under the usual 283 and over the offer by
    /// 40, far beyond the half point the clause allows. It exercises the direction ABOVE the offer only; the
    /// widths at and just over the tolerance are the next row, the widths at and under the offer the row after.
    /// Hand-worked: 190 > 36 (it grew), tabs whole, `rest.collapsed` true, `rest.room` the room now; the
    /// clause asks `190 <= 150.5`, false, so the fold runs: tabsFolded and searchOpening true, the tabs 1 segment.
    /// Read: the field given 194 (offer 154), tabsFolded and searchOpening true, 1 segment. Seen red with `growthIsWithinTheOffer` answering by `wholeTabsFit` alone, whatever the width: the field given 194.0,
    /// 40.0 over its offer of 154.0, left tabsFolded false. Not run: `>=` for the `<=`.
    func testAGrowthOfTheFieldBeyondTheOfferStillFoldsTheTabs() throws {
        PinnedBarSettings.pin(in: self)
        guard let b = inTheBand(.flat, "growth beyond the offer"),
              let got = growField(b, to: b.offer + 40, "offer + 40") else { return }
        expectGrowth(folds: true, got, "\(b.label): the field grew to \(f(b.offer + 40)), \(f(40)) over its offer of \(f(b.offer))")
    }

    /// **The tolerance: a field 0.45 over the offer is excused, and one 0.55 over it is not.** Each on a window of its own in the band, the offer `W` read from the cap (about
    /// 150): `W + 0.45` must leave the tabs whole and the bar not opening, `W + 0.55` must fold them. The two
    /// straddle `offerTolerance` (0.5) by 0.05, five times the 0.01 by which the cap may stand off the offer the
    /// clause works out, so the row does not sit on a rounding. Hand-worked: the clause asks `W + 0.45 <= W' + 0.5`
    /// (true, `W'` within 0.01 of `W`) and `W + 0.55 <= W' + 0.5` (false). The widths exactly at the offer and exactly at
    /// W + 0.5 are not here: the cap's slack of 0.01 puts them on the edge (they need the clause as a function of plain numbers, which the toolbar does not have). It exercises both sides of the bound.
    /// Read: 154.45 left the tabs whole (3 segments, both flags false); 154.55 folded them (1 segment, both flags true).
    /// Seen red on both halves: with `+ Self.offerTolerance` dropped the 0.45 half folded (tabsFolded true, 1 segment), and
    /// with the tolerance at 0.6 the 0.55 half stayed whole (tabsFolded false, 3 segments).
    func testAFieldJustUnderTheToleranceIsExcusedAndOneJustOverItIsNot() throws {
        PinnedBarSettings.pin(in: self)
        if let near = inTheBand(.flat, "0.45 over the offer"),
           let got = growField(near, to: near.offer + 0.45, "offer + 0.45") {
            expectGrowth(folds: false, got, "\(near.label): the field grew to \(f3(near.offer + 0.45)), 0.45 over its offer of \(f3(near.offer))")
        }
        if let past = inTheBand(.flat, "0.55 over the offer"),
           let got = growField(past, to: past.offer + 0.55, "offer + 0.55") {
            expectGrowth(folds: true, got, "\(past.label): the field grew to \(f3(past.offer + 0.55)), 0.55 over its offer of \(f3(past.offer))")
        }
    }

    /// **A field regrowing where the whole tabs do not fit is not excused: `offer.wholeTabsFit` is part of the clause.** Two windows in the band. In the first the actions' item is made 60 points wider
    /// than it stands and the field given the floor, 120: **the wider actions item stands for AppKit laying the
    /// actions out wider**, and the slack of about 30 becomes about -30 (the actions are charged in full to the
    /// room), so `offer.width` is the floor 120 and `wholeTabsFit` false, while 120 is under `offer.width + 0.5`, so
    /// that the width test alone would excuse it. The tabs must fold. In the second window nothing is made wider
    /// and the field is given the same 120: the offer is about 150, the slack about 30, and the field is excused,
    /// the tabs stay whole. The pair differ in the slack only. Hand-worked: first, `120 <= 120.5` true,
    /// `wholeTabsFit` false, so not excused; second, `120 <= 150.5` and the tabs fit, excused.
    /// Read: with the actions 60 wider the field given 120 folded the tabs (slack 34 less 60 = -26); with the actions as
    /// they stand the same 120 left them whole.
    /// Seen red with `offer.wholeTabsFit &&` dropped from `growthIsWithinTheOffer`: with the actions 60 wider the tabs stayed
    /// whole (tabsFolded false, 3 segments) at a slack under 0.
    func testAFieldRegrowingWhereTheWholeTabsDoNotFitIsNotExcused() throws {
        PinnedBarSettings.pin(in: self)
        let floor = ShellBarLayout.searchFloor
        if let tight = inTheBand(.flat, "actions 60 wider"),
           let actions = SettingsWindowRig.item("helm.actions", in: tight.toolbar)?.view {
            actions.setFrameSize(NSSize(width: actions.frame.width + 60, height: actions.frame.height))
            if let got = growField(tight, to: floor, "the floor, actions 60 wider") {
                expectGrowth(folds: true, got, "\(tight.label): the field grew to its floor \(f(floor)) with the actions 60 wider, a slack under 0")
            }
        } else {
            XCTFail("the window lists no helm.actions with a view to make wider: nothing is judged")
        }
        if let roomy = inTheBand(.flat, "actions as they stand"),
           let got = growField(roomy, to: floor, "the floor, actions as they stand") {
            expectGrowth(folds: false, got, "\(roomy.label): the field grew to its floor \(f(floor)) with a slack of about \(f(roomy.offer - floor))")
        }
    }

    /// **A field regrowing to the offer itself leaves the tabs whole, the bar not opening, and the settle that follows
    /// still runs (the excusal itself).** In the band the field is given exactly the offer `W` read
    /// from the cap, about 150: **that stands for AppKit's layout giving the field the width it was offered**,
    /// as the traced defect did after an unfold. Immediately: tabsFolded false, searchOpening false, 3 segments.
    /// Then `rig.settle()`, which runs the settle the observer schedules: the same three. Then
    /// the window is narrowed to the one that leaves 90 points beside whole tabs by the hand arithmetic (a slack of about -69 as the rule reads it), which only a
    /// settle that is not held at its `searchOpening` guard can answer with a fold: the tabs must be 1
    /// segment. Hand-worked: `W <= W' + 0.5`, true, the tabs fit; the BELOW room of `testTheTabsFoldOnlyWhereTheFieldWouldFallBelowItsFloor`, 90 by that row's own arithmetic, is under
    /// the floor 120; the slack the rule read at that window was -69.00.
    /// Read: 154 given, both flags false and 3 segments at once and after the settle (where AppKit's layout collapsed the
    /// field to 36 again, as in the band); narrowed to 831 the tabs were 1 segment.
    /// Seen red on its last assertion only, with `predictedSlack` no longer answering from the offer: narrowed to 831 the tabs
    /// stayed 3 segments. The first three assertions have not been seen red: no run deleted the clause from the observer's
    /// condition.
    func testAFieldRegrowingToTheOfferLeavesTheTabsWholeAndTheSettleRunning() throws {
        PinnedBarSettings.pin(in: self)
        guard let b = inTheBand(.flat, "regrowth to the offer"),
              let got = growField(b, to: b.offer, "offer") else { return }
        expectGrowth(folds: false, got, "\(b.label): the field grew to its offer \(f3(b.offer))")
        b.rig.settle()
        if let after = barState(b.bar, "\(b.label), after the settle") {
            let segments = tabsControl(b.rig)?.segmentCount ?? -1
            print("[fold on growth] \(b.label), after the settle: tabsFolded \(after.folded), searchOpening \(after.opening), \(segments) segments, field \(f(b.field.frame.width)) wide")
            expectGrowth(folds: false, (after.folded, after.opening, segments), "\(b.label): after the settle that follows the regrowth")
        }
        let below = Self.windowWidth(forRoom: ShellBarLayout.searchFloor - 30, reference: b.ref.wide, referenceRoom: b.ref.wideRoom)
        place(b.rig, window: below, sidebar: Self.shapedSidebar)
        let segments = tabsControl(b.rig)?.segmentCount ?? -1
        let opening = barState(b.bar, "\(b.label), narrowed")?.opening
        print("[fold on growth] \(b.label), narrowed to \(f(below)): \(segments) segments, searchOpening \(String(describing: opening))")
        XCTAssertEqual(segments, 1, "\(b.label): narrowed to \(f(below)) (a room 30 under the floor by the hand arithmetic, a slack of about -69 as the rule reads it), the tabs are \(segments) segments, not folded to 1: the settle did not fold after the excused regrowth")
    }

    // MARK: - Where the tabs fold and unfold on the room the field is offered

    /// **How these rows read the slack the rule judges by.** `predictedSlack(bar:tabsWidth:)` and the bar's own `searchOffer(_:tabsWidth:)` are private, and the cap on the field's width (`searchOfferCap`) holds `floor + slack` only while the slack is
    /// over 0, so it cannot say how far under 0 a window stands. What can: `settle(_:)` leaves its last slack in
    /// `lastOpenSlack` after taking the field's share off it, `slack - (preferredWidthForSearchField - occupied) -
    /// titleOpenFloorCharge`, so the row adds the share back (`occupied` being the field's frame width as it stands
    /// once the settle is quiet, which the last pass also read) and gets the slack itself. **Cross-check, read in the
    /// run that wrote the rows: at every window where the cap is the offer for whole tabs (the tabs whole, the field
    /// collapsed) the slack by this reading and the slack by the cap (`cap - floor`) are the same number**, 16.00
    /// at window 916 and 17.00 at 917 under Flat. Under Flat in a window never shown the name holds the whole tabs
    /// right of the card's middle from about window 917 down, so there the slack falls one point for each point of
    /// window and not a half: the slack was -69.00 at window 831, -37.00 at 863, -9.00 at 891, -1.00 at 899, 0.00 at 900, 16.00 at
    /// 916 and 17.00 at 917; from there up the slope is a half (20.00 at 923, 20.50 at 924, 24.00 at 931). Only Flat is read: a first reading under Liquid Glass could not read the page bar by
    /// `Mirror` at its band (a run of a temporary row, since deleted, found these windows), and no row is written against numbers not read.
    private struct FoldReading {
        let window: CGFloat
        let folded: Bool
        let segments: Int
        let capActive: Bool
        let cap: CGFloat
        /// The slack of the last pass; nil where no pass has reached `openFitsPrediction`.
        let slack: CGFloat?
        let fieldHidden: Bool
        let fieldWidth: CGFloat

        var line: String {
            func n(_ value: CGFloat?, _ digits: Int = 2) -> String { value.map { String(format: "%.\(digits)f", Double($0)) } ?? "none" }
            return "window \(n(window, 1)): tabs \(folded ? "folded" : "whole") (\(segments) segments), slack read \(n(slack)), cap \(capActive ? n(cap, 3) : "inactive") "
                + "(slack by the cap \(capActive ? n(cap - ShellBarLayout.searchFloor) : "none")), field \(n(fieldWidth, 1)) wide, \(fieldHidden ? "hidden" : "shown")"
        }
    }

    /// The fold's reading of a settled window. nil after a failure that names what could not be read.
    private func foldReading(_ rig: SettingsWindowRig, window: CGFloat, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) -> FoldReading? {
        guard let toolbar = rig.worn("\(label): no fold was read", file: file, line: line),
              let owner = toolbar.delegate as? SettingsToolbar,
              let bar = wornPageBar(rig, of: owner),
              let item = SettingsWindowRig.item("helm.search", in: toolbar) as? NSSearchToolbarItem,
              let state = barState(bar, label, file: file, line: line)
        else {
            XCTFail("\(label): the window has no worn page bar or search item to read the fold from: nothing is judged", file: file, line: line)
            return nil
        }
        let field = item.searchField
        var slack: CGFloat?
        if let open = owner.lastOpenSlack {
            let occupied = min(field.frame.width, field.superview?.frame.width ?? field.frame.width)
            let charge = stored("titleOpenFloorCharge", of: bar) as? CGFloat ?? 0
            slack = open + (item.preferredWidthForSearchField - occupied) + charge
        }
        let reading = FoldReading(window: window, folded: state.folded, segments: tabsControl(rig)?.segmentCount ?? -1,
                                  capActive: state.cap.isActive, cap: state.cap.constant, slack: slack,
                                  fieldHidden: field.isHidden, fieldWidth: field.frame.width)
        print("[fold slack] \(label): \(reading.line)")
        return reading
    }

    /// The shaped page, under Flat, placed at `width` and a sidebar of 200, and settled; nil after a failure.
    private func settledAt(window width: CGFloat, file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        guard let rig = shapedPage(.flat, file: file, line: line) else { return nil }
        place(rig, window: width, sidebar: Self.shapedSidebar)
        SettingsWindowRig.pump()
        rig.settle()
        return rig
    }

    /// A window, on a rig of its own, whose settled slack reads inside `wanted`, found by reading: from `guess`, each
    /// window that misses is moved by the miss, rounded, and read again on a fresh rig (up to five). nil after a
    /// failure that lists the windows tried and what each read.
    private func settledAtSlack(_ wanted: Range<CGFloat>, near guess: CGFloat, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) -> (rig: SettingsWindowRig, reading: FoldReading, slack: CGFloat)? {
        var width = guess
        var tried: [String] = []
        for attempt in 1...5 {
            guard let rig = settledAt(window: width, file: file, line: line),
                  let reading = foldReading(rig, window: width, "\(label), try \(attempt)", file: file, line: line) else { return nil }
            guard let slack = reading.slack else {
                XCTFail("\(label): the window \(f(width)) has no slack to read: nothing is judged. \(reading.line)", file: file, line: line)
                return nil
            }
            if wanted.contains(slack) { return (rig, reading, slack) }
            tried.append("\(f(width)) read \(f3(slack))")
            let middle = (wanted.lowerBound + wanted.upperBound) / 2
            let step = (middle - slack).rounded(.toNearestOrAwayFromZero)
            width += step == 0 ? (middle > slack ? 1 : -1) : step
        }
        XCTFail("\(label): no window read a slack in \(f(wanted.lowerBound))..<\(f(wanted.upperBound)); tried \(tried.joined(separator: ", ")): nothing is judged", file: file, line: line)
        return nil
    }

    /// The window the rows below stand around: the first whose settled slack reads in `0..<0.5`, found from the
    /// window that leaves the field its floor by the arithmetic of `testTheTabsFoldOnlyWhereTheFieldWouldFallBelowItsFloor`
    /// (which does not count the name holding the tabs, so it misses and the search moves it).
    private func zeroWindow(_ label: String, file: StaticString = #filePath, line: UInt = #line)
        -> (rig: SettingsWindowRig, reading: FoldReading, slack: CGFloat)? {
        guard let ref = roomReference(.flat) else { return nil }
        let guess = Self.windowWidth(forRoom: ShellBarLayout.searchFloor, reference: ref.wide, referenceRoom: ref.wideRoom)
        return settledAtSlack(0..<0.5, near: guess, label, file: file, line: line)
    }

    /// **The tabs fold where the slack, as the rule reads it, is under 0, and not before: at 1 point of slack under
    /// 0 they fold and at 0 they stay whole (the fold's boundary, `foldMargin`).** Two windows, each on a rig of its
    /// own, settled once (`rig.settle()`): the first is found by reading, the first window whose slack reads in
    /// `0..<0.5`; the second is one point narrower and must read a slack in `-1.5..<0`, which the row checks before
    /// it judges. The slack changes by one point for each point of window there (the name holds the tabs). The
    /// first must leave the tabs whole (3 segments, `tabsFolded` false), the second must fold them (1 segment,
    /// `tabsFolded` true). A rule that waited for a cushion under 0 before folding (`slack < -40`) would leave the
    /// second whole: AppKit does not evict anything at a slack of -1, which is the reason a fold at that room has to
    /// come from the rule. It exercises both sides of the boundary, 1 point apart; the slack is a whole number of
    /// points in every reading, so a boundary read as a fraction is not asserted.
    /// Read (Flat): the search found the zero window at the second window it tried (891 read -9.00, 900 read 0.00); window 900 read
    /// slack 0.00, 3 segments, `tabsFolded` false, the field 36 wide and hidden, the cap 120.000; window 899 read slack -1.00,
    /// folded to 1 segment, the field 214 wide and shown.
    /// Seen red on the second window with the fold made to wait for `slack < -40` (`settle`'s `else if !bar.tabsFolded, slack <
    /// Self.foldMargin`): at a slack of -1.000 the tabs stayed whole (tabsFolded false, 3 segments). The first window has not
    /// been seen red: no run raised `foldMargin`.
    func testTheTabsFoldOnePointUnderNoSlackAndStayWholeAtNone() throws {
        PinnedBarSettings.pin(in: self)
        guard let at = zeroWindow("slack 0") else { return }
        XCTAssertFalse(at.reading.folded, "slack \(f3(at.slack)): the tabs are folded (tabsFolded true) at a slack of nothing, where they stay whole. \(at.reading.line)")
        XCTAssertEqual(at.reading.segments, 3, "slack \(f3(at.slack)): the tabs are \(at.reading.segments) segments, not the 3 of whole tabs. \(at.reading.line)")
        let under = at.reading.window - 1
        guard let rig = settledAt(window: under), let r = foldReading(rig, window: under, "slack one under") else { return }
        guard let slack = r.slack, (-1.5..<0).contains(slack) else {
            XCTFail("window \(f(under)) reads a slack of \(r.slack.map { f3($0) } ?? "none"), not in -1.5..<0: the window is not just under nothing, nothing is judged. \(r.line)")
            return
        }
        XCTAssertTrue(r.folded, "slack \(f3(slack)): the tabs are whole (tabsFolded false) at a slack under nothing, where the rule folds them. \(r.line)")
        XCTAssertEqual(r.segments, 1, "slack \(f3(slack)): the tabs are \(r.segments) segments, not folded to 1. \(r.line)")
    }

    /// **From tabs the rule folded, a widening that leaves the slack under the unfold margin (16) leaves them folded,
    /// and one that brings it to the margin unfolds them (`unfoldMargin`, the hysteresis).** Per target one rig:
    /// the window is `zero` less 10 (slack -10), settled, and the row first asserts the tabs are folded there (so
    /// the row begins from tabs the rule folded); the window is then widened by 8, 15, 16 or 17 over `zero`
    /// (`place`, then `rig.settle()`), the slack read there must stand at the zero window's own slack plus that (a guard that
    /// judges nothing otherwise), and the verdict is read after the settle and after a second `rig.settle()`:
    /// folded at +8 and +15 (slack 8 and 15), whole at +16 and +17. The unfold's own layout leaves the field collapsed for a moment (it read 36 wide and hidden at 916 and 917 after the unfold); a second settle is read to see the verdict stands.
    /// The 15 is the point under the margin, the 16 the point on it (`>=`). It exercises the unfold from below the margin, on it and over it, and
    /// the stay-folded side at a half and at one point under the margin.
    /// Read (Flat): zero at window 900; each rig's start, window 890, read slack -10.00 and folded (the field 210 wide, shown).
    /// Widened to 908 (slack 8.00) the tabs stayed folded, after the settle and after a second one; 915 (15.00) stayed folded,
    /// both times; 916 (16.00) were whole, 3 segments, the field collapsed to 36 and the cap at 136.000, both times; 917 (17.00) were
    /// whole, 3 segments, the field collapsed to 36 and the cap at 137.000, both times. A first
    /// version had a +24 target; it read slack 20.50 at window 924 and not the 24.00 asked (the name's hold ends near window
    /// 917, and the slack rises a half point for each point of window after that), so its guard failed before its two
    /// assertions. The target is 17 (window 917, read 17.00), inside the hold.
    /// Seen red: with `unfoldMargin` 0 the +8 and +15 targets unfolded (slack 8.00 at window 908, 15.00 at 915), and with 17
    /// the +16 target stayed folded (slack 16.00 at window 916, 1 segment). Not run: a margin of 15. The +17 target has not been
    /// seen red: with the margin at 17 it unfolds as it should (`>=`).
    func testFoldedTabsUnfoldAtTheMarginAndNotBefore() throws {
        PinnedBarSettings.pin(in: self)
        guard let zero = zeroWindow("zero for the unfold") else { return }
        let w0 = zero.reading.window
        for (offset, unfolds) in [(CGFloat(8), false), (15, false), (16, true), (17, true)] {
            let label = "from folded, widened \(f(offset)) over the zero window"
            let start = w0 - 10
            guard let rig = settledAt(window: start), let r0 = foldReading(rig, window: start, "\(label): start") else { continue }
            XCTAssertTrue(r0.folded, "\(label): the tabs are whole (tabsFolded false) at the start window \(f(start)), where the rule folds them: the row does not begin from folded tabs. \(r0.line)")
            guard r0.folded else { continue }
            let target = w0 + offset
            place(rig, window: target, sidebar: Self.shapedSidebar)
            SettingsWindowRig.pump()
            rig.settle()
            guard let r1 = foldReading(rig, window: target, "\(label): settled"), let s1 = r1.slack else { continue }
            guard abs(s1 - (zero.slack + offset)) <= 0.25 else {
                XCTFail("\(label): window \(f(target)) reads a slack of \(f3(s1)), not the \(f3(zero.slack + offset)) asked: nothing is judged. \(r1.line)")
                continue
            }
            rig.settle()
            guard let r2 = foldReading(rig, window: target, "\(label): settled again") else { continue }
            for (when, r) in [("after the settle", r1), ("after a second settle", r2)] {
                XCTAssertEqual(r.folded, !unfolds, "\(label) (slack \(f3(s1))), \(when): tabsFolded is \(r.folded), not \(!unfolds). \(r.line)")
                XCTAssertEqual(r.segments, unfolds ? 3 : 1, "\(label) (slack \(f3(s1))), \(when): the tabs are \(r.segments) segments, not \(unfolds ? 3 : 1). \(r.line)")
            }
        }
    }

    /// The bar's fold flag and the cap, as numbers: the cap is a reference, so its constant is copied here at the moment of the read.
    private struct CapTurn {
        let folded: Bool
        let capActive: Bool
        let cap: CGFloat
    }

    private func capTurn(_ bar: Any, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> CapTurn? {
        guard let state = barState(bar, label, file: file, line: line) else { return nil }
        return CapTurn(folded: state.folded, capActive: state.cap.isActive, cap: state.cap.constant)
    }

    /// The settle's pending pass, run by hand, until the tabs' fold flag becomes `folded`; what the cap held just before the pass that flipped it
    /// and just after, with no run-loop turn between and no layout after, and the slack and the tabs' reach that pass judged by. nil after a failure.
    private struct FlippingPass {
        let before: CapTurn
        let after: CapTurn
        let slack: CGFloat
        /// The tabs' right edge less the card's middle, from the frames read just before the pass.
        let tabsReach: CGFloat
        let passes: Int
        /// The frames read just before the pass, and the lead's constant then and right after the pass (no layout
        /// between), and the tabs' frame width right after the pass, before any layout: nil where the item has no view.
        let standBefore: Stand
        let leadBefore: CGFloat?
        let leadAfter: CGFloat?
        let tabsWidthAfter: CGFloat?
    }

    private func flipTheTabs(_ rig: SettingsWindowRig, to folded: Bool, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) -> FlippingPass? {
        guard let toolbar = rig.worn("\(label): no pass was run", file: file, line: line),
              let owner = toolbar.delegate as? SettingsToolbar, let bar = wornPageBar(rig, of: owner),
              let item = SettingsWindowRig.item("helm.search", in: toolbar) as? NSSearchToolbarItem else {
            XCTFail("\(label): the window has no worn page bar or search item: nothing is judged", file: file, line: line)
            return nil
        }
        func pending() -> DispatchWorkItem? { inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem }
        for pass in 1...20 {
            guard let work = pending() else {
                XCTFail("\(label): the toolbar holds no pending settle (settleWorkItem) at pass \(pass): nothing is judged", file: file, line: line)
                return nil
            }
            guard let st = stand(rig, "\(label), pass \(pass)", file: file, line: line),
                  let before = capTurn(bar, "\(label), before pass \(pass)", file: file, line: line) else { return nil }
            let field = item.searchField
            let occupied = min(field.frame.width, field.superview?.frame.width ?? field.frame.width)
            let charge = stored("titleOpenFloorCharge", of: bar) as? CGFloat ?? 0
            let leadBefore = leadConstants(in: toolbar)?.first
            work.perform()
            let leadAfter = leadConstants(in: toolbar)?.first
            let tabsWidthAfter = SettingsWindowRig.item("helm.tabs", in: toolbar)?.view?.frame.width
            guard let after = capTurn(bar, "\(label), after pass \(pass)", file: file, line: line) else { return nil }
            print("[fold turn] \(label), pass \(pass): tabs \(before.folded ? "folded" : "whole") -> \(after.folded ? "folded" : "whole"), cap \(before.capActive ? f3(before.cap) : "inactive") -> \(after.capActive ? f3(after.cap) : "inactive"), lastOpenSlack \(owner.lastOpenSlack.map { f3($0) } ?? "none"), pending pass replaced: \(pending() !== work)")
            if before.folded != folded, after.folded == folded {
                guard let open = owner.lastOpenSlack else {
                    XCTFail("\(label): the pass that flipped the tabs left no slack to read: nothing is judged", file: file, line: line)
                    return nil
                }
                return FlippingPass(before: before, after: after,
                                    slack: open + (item.preferredWidthForSearchField - occupied) + charge,
                                    tabsReach: st.tabsMaxX - st.cardMid, passes: pass, standBefore: st,
                                    leadBefore: leadBefore, leadAfter: leadAfter, tabsWidthAfter: tabsWidthAfter)
            }
        }
        XCTFail("\(label): twenty passes of the settle by hand did not make the tabs \(folded ? "folded" : "whole")", file: file, line: line)
        return nil
    }

    /// **In the turn that folds the tabs the cap on the field's width holds the offer for tabs of no width, and
    /// in the turn that unfolds them the offer for the whole tabs, before any further settle rewrites it
    /// (`setTabsFolded`'s own write).** The settle's timer is put out of reach (`SettingsToolbar.settleInterval`
    /// 1000, put back by a teardown block) and the settle's pending pass (`settleWorkItem`, read by `Mirror`)
    /// is run by hand with `perform()`, one pass at a time, with nothing awaited between: so the cap can be read
    /// at once after the pass that flips `tabsFolded`, before any later pass writes it from the layout. The
    /// window starts at the zero window plus 24 (tabs whole), is narrowed by `setContentSize` to one point under
    /// the zero window (slack -1), the passes run until the tabs fold; then the window is widened again to the
    /// start's width and the passes run until they unfold. **What a pass leaves in the cap when it folds:**
    /// - folding: the cap is active and holds the offer for tabs of no width, `floor + slack + (the tabs' right edge
    ///   less the card's middle)` held between the floor and the usual width, to within 3 points, chosen; it must also be over what
    ///   the same pass wrote a moment before for the whole tabs, which is the floor at a slack under 0.
    /// - unfolding: the cap holds `floor + slack` of that pass, within half a point, and not what it held a
    ///   moment before, the offer for the folded tabs' width.
    /// The slack is the one the pass judged by (`FoldReading`'s reading, taken with the field's width as it stood
    /// before the pass). It exercises both directions of `setTabsFolded` from `settle`; the fold from the field's growth (M2) takes the offer
    /// away (`searchOpening`) and is not what this reads.
    /// Read (Flat): the start window 924 (slack 20.50), narrowed to 899. Folding took two passes: pass 1 moved the cap 140.500 ->
    /// 120.000 and left the tabs whole; pass 2 folded them and moved the cap 120.000 -> 283.000 (the offer for tabs of no width is
    /// over the usual width there, so it is held at it). Widened to 924: unfolding took three passes; passes 1 and 2 left the
    /// tabs folded (cap 218.500 -> 231.000 -> 231.000), pass 3 unfolded them and moved the cap 231.000 -> 140.500, which is the
    /// floor and the pass's slack of 20.50.
    /// Seen red on both halves with the `writeSearchOffer(bar, tabsWidth: ...)` line of `setTabsFolded` deleted: the folding
    /// pass left the cap at 120.000, not 283.000, and the unfolding pass left it at 231.000, not 140.500. Not run: the two widths
    /// the other way round.
    func testTheCapFollowsTheTabsInTheTurnThatFoldsOrUnfoldsThem() throws {
        PinnedBarSettings.pin(in: self)
        guard let zero = zeroWindow("zero for the cap") else { return }
        let wide = zero.reading.window + 24
        guard let rig = settledAt(window: wide), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
            XCTFail("the window wears no SettingsToolbar to run the settle of by hand: nothing is judged")
            return
        }
        let original = SettingsToolbar.settleInterval
        SettingsToolbar.settleInterval = 1000
        addTeardownBlock { @MainActor in SettingsToolbar.settleInterval = original }
        rig.window.setContentSize(NSSize(width: zero.reading.window - 1, height: 760))
        rig.window.contentView?.layoutSubtreeIfNeeded()
        let floor = ShellBarLayout.searchFloor
        func held(_ value: CGFloat) -> CGFloat { min(max(value, floor), ShellBarLayout.searchWidth) }
        if let fold = flipTheTabs(rig, to: true, "fold") {
            let expected = held(floor + fold.slack + fold.tabsReach)
            XCTAssertTrue(fold.after.capActive, "the turn that folds the tabs leaves the cap inactive (before \(f3(fold.before.cap)), after \(f3(fold.after.cap))): it should hold the offer for tabs of no width")
            XCTAssertEqual(fold.after.cap, expected, accuracy: 3,
                           "the turn that folds the tabs (pass \(fold.passes), slack \(f3(fold.slack)), the tabs reach \(f3(fold.tabsReach)) past the card's middle) leaves the cap at \(f3(fold.after.cap)), not the offer for tabs of no width, \(f3(expected))")
            XCTAssertGreaterThan(fold.after.cap, fold.before.cap + 1,
                                 "the turn that folds the tabs leaves the cap at \(f3(fold.after.cap)), where the same pass left it for the whole tabs, \(f3(fold.before.cap)): it did not follow the fold")
            for _ in 0..<12 {
                guard let work = inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem else { break }
                work.perform()
                if (inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem) === work { break }
            }
            rig.window.setContentSize(NSSize(width: wide, height: 760))
            rig.window.contentView?.layoutSubtreeIfNeeded()
            if let unfold = flipTheTabs(rig, to: false, "unfold") {
                let expected = held(floor + unfold.slack)
                XCTAssertTrue(unfold.after.capActive, "the turn that unfolds the tabs leaves the cap inactive (before \(f3(unfold.before.cap)), after \(f3(unfold.after.cap))): it should hold the offer for the whole tabs")
                XCTAssertEqual(unfold.after.cap, expected, accuracy: 0.5,
                               "the turn that unfolds the tabs (pass \(unfold.passes), slack \(f3(unfold.slack))) leaves the cap at \(f3(unfold.after.cap)), not the offer for the whole tabs, \(f3(expected)); it held \(f3(unfold.before.cap)) for the folded tabs a moment before")
            }
        }
    }

    // MARK: - Where the lead, the floor and the start of the rail are read

    /// A page of three tabs, an action and a search holding «find»: the field holds text from the start (its
    /// `stringValue`, which needs no key window), so `searchOffer(_:tabsWidth:)` answers nil and the fold is predicted
    /// from the layout of now. Flat, the window as the app builds it, never ordered.
    private func textPage(file: StaticString = #filePath, line: UInt = #line) -> SettingsWindowRig? {
        AppSettings.barAppearance = .flat
        guard let rig = build(file: file, line: line) else { return nil }
        let doing = [HelmToolbarAction(id: "refresh", title: "Refresh list", symbol: "arrow.clockwise") {}]
        let content = HelmPageToolbarContent(
            tabs: Self.shapedTabs.map { HelmToolbarTab(id: $0.id, title: $0.title, symbol: $0.symbol) },
            selectedTab: .constant("installed"), actions: doing,
            search: HelmToolbarSearch(prompt: "Search packages", text: .constant("find")))
        rig.channel.declare(content, token: "probe.text", generation: rig.channel.nextGeneration())
        rig.model.selection = .module("probe.text")
        rig.window.contentMinSize = NSSize(width: 100, height: 100)
        rig.settle()
        SettingsWindowRig.pump()
        return rig
    }

    /// What the window shows round the tabs at one width: the frames in window x, the tabs' fold flag, the cap's
    /// state and the last slack the settle left.
    private struct Beside {
        let window: CGFloat
        let stand: Stand
        let folded: Bool?
        let capActive: Bool?
        let openSlack: CGFloat?
        let actionsMaxX: CGFloat?
        let slotMaxX: CGFloat?
        let fieldWidth: CGFloat?
        let fieldHidden: Bool?
        let fieldHasText: Bool?
        let full: CGFloat?

        /// The room the frames leave round the tabs: the lead's end to the tabs' start, and the tabs' end to the
        /// actions' start. nil where the page has no lead item or no actions.
        var around: CGFloat? {
            guard let lead = stand.leadMaxX, let actions = stand.actionsMinX else { return nil }
            return (stand.tabsMinX - lead) + (actions - stand.tabsMaxX)
        }

        var line: String {
            func n(_ value: CGFloat?) -> String { value.map { String(format: "%.2f", Double($0)) } ?? "none" }
            return "window \(n(window)): tabs \(folded.map { $0 ? "folded" : "whole" } ?? "?") (\(stand.segments) segments) \(n(stand.tabsMinX))...\(n(stand.tabsMaxX)), "
                + "name ends \(n(stand.nameMaxX)), lead \(n(stand.leadMinX))...\(n(stand.leadMaxX)), actions \(n(stand.actionsMinX))...\(n(actionsMaxX)), "
                + "bar ends \(n(slotMaxX)), field \(n(fieldWidth)) wide \(fieldHidden.map { $0 ? "hidden" : "shown" } ?? "?"), "
                + "cap \(capActive.map { $0 ? "active" : "inactive" } ?? "?"), slack read \(n(openSlack)), room round the tabs \(n(around)), whole tabs \(n(full))"
        }
    }

    private func beside(_ rig: SettingsWindowRig, window: CGFloat, _ label: String,
                        file: StaticString = #filePath, line: UInt = #line) -> Beside? {
        guard let s = stand(rig, label, file: file, line: line), let toolbar = rig.window.toolbar else { return nil }
        let owner = toolbar.delegate as? SettingsToolbar
        let bar = owner.flatMap { wornPageBar(rig, of: $0) }
        let field = (SettingsWindowRig.item("helm.search", in: toolbar) as? NSSearchToolbarItem)?.searchField
        func box(_ view: NSView?) -> CGRect? {
            guard let view, view.window != nil else { return nil }
            return view.convert(view.bounds, to: nil)
        }
        let slot = field?.superview?.superview ?? field?.superview
        let cap = bar.flatMap { inside(stored("searchOfferCap", of: $0)) as? NSLayoutConstraint }
        let full = bar.flatMap { inside(stored("tabsWidth", of: $0)) }.flatMap { stored("full", of: $0) as? CGFloat }
        return Beside(window: window, stand: s, folded: bar.flatMap { stored("tabsFolded", of: $0) as? Bool },
                      capActive: cap?.isActive, openSlack: owner?.lastOpenSlack,
                      actionsMaxX: box(SettingsWindowRig.item("helm.actions", in: toolbar)?.view)?.maxX,
                      slotMaxX: box(slot)?.maxX, fieldWidth: field?.frame.width, fieldHidden: field?.isHidden,
                      fieldHasText: field.map { !$0.stringValue.isEmpty }, full: full)
    }

    /// The toolbar's last told pane, read by `Mirror` (`pane` is private): where the card's leading edge and width were
    /// told to be, and whether the window's buttons were told to stand in the rail's placement. nil after a failure.
    private func toldPane(_ owner: SettingsToolbar, _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) -> (leading: CGFloat, width: CGFloat, rail: Bool)? {
        guard let pane = inside(stored("pane", of: owner)), let leading = stored("leading", of: pane) as? CGFloat,
              let width = stored("width", of: pane) as? CGFloat, let rail = stored("rail", of: pane) as? Bool else {
            XCTFail("\(label): the toolbar holds no pane (leading, width, rail) to read by Mirror: nothing is judged", file: file, line: line)
            return nil
        }
        return (leading, width, rail)
    }

    /// **At the start of a fold of the sidebar into the rail, before the first tick has moved the card, the toolbar
    /// is told the rail's placement in that same layout: the pane it holds stands in the rail while its leading edge
    /// and width are still the card's of 200, the name's inset has moved to the rail's start, and the lead's constant has not.** The fold is
    /// `ShellContentView.fold(to:animated:)` with a `HandTickedFoldLink`; its first tick records the start and writes
    /// nothing (`foldTarget` is 56 and `sidebarWidth` is still 200), so the card's frame is the one at rest and the only
    /// thing the layout has to tell the toolbar is that `buttonsStandInRail` became true. A `Told` that compared the
    /// card alone would tell nothing here and the toolbar would hold the pane of the full sidebar until the second
    /// tick moved the card. Three claims, each with its own message: the row stands at the start (width 200, target 56,
    /// `buttonsStandInRail`), the pane is told the rail (`pane.rail`) with the card's leading edge and width unchanged,
    /// the name's inset (the constant of the constraint, no frame) moved by 70 points, from the full sidebar's 200 + 16 - 92.5 =
    /// 123.5 to the rail's 200 + 16 - 22.5 = 193.5, and the lead's constant stands where it stood. The inset moves because the
    /// start moves between the placements and the name stays on the card's edge plus sixteen; the name's end therefore
    /// does not move at the first tick, and the lead, which is worked out from where the name ends, does not move with it. Both looks.
    /// Read: under both looks the pane at rest was `leading: 200.0, width: 856.0, rail: false` and at the start of the
    /// fold `leading: 200.0, width: 856.0, rail: true`, the width 200.0 and the target 56.0; the inset went 123.500 -> 193.500
    /// and the lead's constant stayed 195.000 under Flat and 201.000 under Liquid Glass (read: 195.000 and 201.000 at rest and at the
    /// start of the fold).
    /// Seen red under both looks with `if told.card != lastTold?.card` in `ShellContentView.layout()`: at the start of the fold
    /// the toolbar held the pane of the full sidebar (rail false), not told in the layout that moved the buttons, and the lead's
    /// constant had not moved (195.000 at the start and at rest under Flat); with that mutant the claims on the pane's rail and on
    /// the inset are the ones meant to fail; the inset's failure is read from the code, not run.
    func testTheStartOfAFoldIntoTheRailTellsTheToolbarTheRailBeforeTheCardMoves() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            let label = look.rawValue
            guard let rig = pageWithTabs(look), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
                XCTFail("\(label): the window wears no SettingsToolbar: nothing is judged")
                return
            }
            let shell = rig.shell.shell
            let link = HandTickedFoldLink()
            shell.foldLink = link
            shell.reducesMotion = { false }
            guard let rest = toldPane(owner, "\(label) at rest"), let restLead = leadConstant(rig, "\(label) at rest"),
                  let restInset = readInset(rig, "\(label) at rest") else { return }
            XCTAssertFalse(rest.rail, "\(label): the pane at rest is already in the rail: the row does not begin from the full sidebar")
            XCTAssertTrue(shell.fold(to: 56, animated: true), "\(label): the fold was cut, not asked for")
            XCTAssertTrue(link.fire(at: 100), "\(label): the link was never started")
            shell.layoutSubtreeIfNeeded()
            XCTAssertEqual(shell.sidebarWidth, 200, accuracy: 0.01, "\(label): the first tick moved the sidebar to \(shell.sidebarWidth): the card has moved and the row judges nothing")
            XCTAssertEqual(shell.foldTarget ?? -1, 56, accuracy: 0.01, "\(label): the fold's target is \(shell.foldTarget.map { "\($0)" } ?? "none"), not 56")
            XCTAssertTrue(shell.buttonsStandInRail, "\(label): the buttons do not stand in the rail's placement at the start of the fold into it")
            guard let told = toldPane(owner, "\(label) at the start of the fold") else { return }
            XCTAssertTrue(told.rail, "\(label): at the start of the fold the toolbar holds the pane of the full sidebar (rail \(told.rail)), not the rail's: it was not told in the layout that moved the buttons (leading \(f3(told.leading)), width \(f3(told.width)))")
            XCTAssertEqual(told.leading, rest.leading, accuracy: 0.01, "\(label): the pane's leading edge moved from \(f3(rest.leading)) to \(f3(told.leading)): the card has moved and the row judges nothing")
            XCTAssertEqual(told.width, rest.width, accuracy: 0.01, "\(label): the pane's width moved from \(f3(rest.width)) to \(f3(told.width)): the card has moved and the row judges nothing")
            if let inset = readInset(rig, "\(label) at the start of the fold") {
                XCTAssertEqual(inset - restInset, 70, accuracy: 0.5, "\(label): the name's inset is \(f3(inset)) at the start of the fold, \(f3(restInset)) at rest: it did not move by the 70 between the placements' starts, so the toolbar worked it out for the placement it was not in")
                XCTAssertEqual(inset, 200 + Self.nameGap - Self.railItemsStart, accuracy: 0.5, "\(label): the name's inset is \(f3(inset)) at the start of the fold, not the card's edge plus sixteen less the rail's start")
            }
            if let lead = leadConstant(rig, "\(label) at the start of the fold") {
                XCTAssertEqual(lead, restLead, accuracy: 1, "\(label): the lead's constant is \(f3(lead)) at the start of the fold, \(f3(restLead)) at rest: it moved with the placement, so the lead was worked out from a name that moved (the name stands on the card's edge plus sixteen before the fold and at its first tick)")
            }
            print("[rail start] \(label): pane at rest \(rest), at the start \(told); lead \(f3(restLead)) -> \(leadConstant(rig, "\(label) print").map { f3($0) } ?? "none")")
        }
    }

    // MARK: - Where the name stands in the turn the buttons change place

    /// Runs `body` with `window` answering `isVisible` true when `claimed`, and as it did after it: one of the gates
    /// `SettingsToolbar.learnStartOfItems(_:)` asks of the window, so that the toolbar of a window nobody ordered learns
    /// where its items start the way it does in a shown one. The getter of `NSWindow` is replaced for the span of
    /// `body` by one that answers true for `window` and asks the original of every other object; it is put back
    /// on every exit. The window's class is not changed: the app observes the window by key-value observation, whose
    /// subclass a swap of the window's class takes away (the process trapped in the layout that followed). The same
    /// gate is answered in `TheBarTellsItsShellWhenItIsAttachedTests` by `ClaimedWindow`, a subclass of `NSWindow` that
    /// a bare toolbar's test window can be and a `SettingsWindow` cannot, since it builds its own `NSWindow`; hence the two seams.
    private func whileShown(_ claimed: Bool, _ window: NSWindow, _ body: () -> Void) {
        guard claimed else { body(); return }
        let selector = #selector(getter: NSWindow.isVisible)
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
            XCTFail("NSWindow has no isVisible getter to answer for: the row cannot stand for a shown window")
            body()
            return
        }
        let original = method_getImplementation(method)
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let asked = unsafeBitCast(original, to: Getter.self)
        let answer: @convention(block) (AnyObject) -> Bool = { [unowned window] object in
            object === window ? true : asked(object, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(answer))
        defer { method_setImplementation(method, original) }
        body()
    }

    /// One reading of where the name's hosting view stands against the card's edge plus sixteen, with what the
    /// toolbar holds at that moment. `off` is the name's x less the card's edge less sixteen.
    private struct NameReading {
        let label: String
        let sidebar: CGFloat
        let card: CGFloat
        let name: CGFloat
        let rail: Bool?
        let itemsStart: CGFloat
        let learnt: String
        let container: CGFloat
        let inset: CGFloat?
        let tabs: CGFloat
        let tabsWidth: CGFloat
        var wanted: CGFloat { card + 16 }
        var off: CGFloat { name - wanted }
        var line: String {
            func f(_ value: CGFloat) -> String { String(format: "%.1f", Double(value)) }
            return "\(label): sidebar \(f(sidebar)), card at \(f(card)), the name's host at \(f(name)) where the card's edge plus 16 is \(f(wanted)) "
                + "(\(String(format: "%+.1f", Double(off))))"
        }
        var cause: String {
            func f(_ value: CGFloat) -> String { String(format: "%.1f", Double(value)) }
            return "\(label): pane told rail \(rail.map { "\($0)" } ?? "?"), itemsStart \(f(itemsStart)), learnt starts \(learnt), "
                + "the name's item from \(f(container)), the inset held \(inset.map { f($0) } ?? "none"), host \(f(name)); tabs from \(f(tabs)) \(f(tabsWidth)) wide"
        }
    }

    /// The name's place now: the frame view is laid out first (`stand`), nothing is pumped.
    private func nameReading(_ rig: SettingsWindowRig, _ owner: SettingsToolbar, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) -> NameReading? {
        guard let s = stand(rig, label, file: file, line: line) else { return nil }
        return NameReading(label: label, sidebar: rig.shell.shell.sidebarWidth, card: s.cardMinX, name: s.nameMinX,
                           rail: toldPane(owner, label, file: file, line: line)?.rail, itemsStart: owner.itemsStart,
                           learnt: "\(stored("learntItemsStarts", of: owner) ?? "?")", container: s.containerMinX, inset: s.inset,
                           tabs: s.tabsMinX, tabsWidth: s.tabsWidth)
    }

    /// The ticks after the first one, as fractions of the fold's length; the last is past the end and lands.
    private static let foldTicks: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.1]

    /// **In the layout that gives the window's buttons the rail's placement (the first tick of a fold into the rail,
    /// before the card has moved) and at every tick after it, the name's hosting view stands on the card's edge plus
    /// sixteen, within a point.** The fold is `ShellContentView.fold(to:animated:)` over a `HandTickedFoldLink`: the
    /// first tick writes nothing, the layout that follows it tells the toolbar the rail's placement while the card
    /// still stands at 200, and the frames are read in that turn, before any pump (`nameReading` lays the frame view
    /// out and nothing more). The card's edge plus sixteen is 216 there, as it was at rest. Under both looks, in a window
    /// whose toolbar learns where it starts its items (`whileShown`) and in one that does not (the start of each placement stays
    /// its seed there, 92.5 expanded and 22.5 in the rail). The reading before the fold is asserted equal to 216 as the precondition, and the
    /// landing in the rail (56, 72) is read with the others.
    func testTheNameStandsOnTheCardsEdgePlusSixteenFromTheFirstTickOfAFoldIntoTheRail() throws {
        PinnedBarSettings.pin(in: self)
        var first: [String] = []
        var later: [String] = []
        var causes: [String] = []
        var ticks = 0
        for look in Self.looks {
            for claimed in [false, true] {
                let label = "\(look.rawValue)\(claimed ? ", toolbar re-reads its start" : ", toolbar on the seed")"
                guard let rig = pageWithTabs(look), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
                    XCTFail("\(label): the window wears no SettingsToolbar: nothing is judged")
                    return
                }
                whileShown(claimed, rig.window) { rig.settle() }
                let shell = rig.shell.shell
                let link = HandTickedFoldLink()
                shell.foldLink = link
                shell.reducesMotion = { false }
                guard let rest = nameReading(rig, owner, "\(label), at rest") else { return }
                XCTAssertEqual(rest.card, 200, accuracy: 0.5, "\(label): the fold does not start at 200")
                XCTAssertEqual(rest.off, 0, accuracy: 1, "\(label), precondition: \(rest.line)")
                causes.append(rest.cause)

                XCTAssertTrue(shell.fold(to: 56, animated: true), "\(label): the fold was cut, not asked for")
                XCTAssertTrue(link.fire(at: 100), "\(label): the link was never started")
                whileShown(claimed, rig.window) { shell.layoutSubtreeIfNeeded() }
                guard let start = nameReading(rig, owner, "\(label), first tick into the rail") else { return }
                XCTAssertEqual(start.sidebar, 200, accuracy: 0.01, "\(label): the first tick moved the card: the row judges nothing")
                if abs(start.off) > 1 { first.append(start.line) }
                causes.append(start.cause)
                for fraction in Self.foldTicks {
                    link.fire(at: 100 + fraction * HelmMotion.sidebarFoldDuration)
                    whileShown(claimed, rig.window) { shell.layoutSubtreeIfNeeded() }
                    ticks += 1
                    guard let r = nameReading(rig, owner, "\(label), tick at \(fraction)") else { return }
                    if abs(r.off) > 1 { later.append(r.line) }
                    if fraction == 0.1 || fraction == 1.1 { causes.append(r.cause) }
                }
                XCTAssertEqual(shell.sidebarWidth, 56, accuracy: 0.01, "\(label): the fold did not land in the rail")
            }
        }
        print("[name into the rail] " + causes.joined(separator: "\n[name into the rail] "))
        XCTAssertEqual(ticks, 40, "\(ticks) ticks of 40 were read")
        XCTAssertTrue(first.isEmpty, "the name is not on the card's edge plus sixteen in the layout that sends the buttons into the rail: \(first)")
        XCTAssertTrue(later.isEmpty, "the name left the card's edge plus sixteen at \(later.count) of 40 ticks into the rail: \(later)")
    }

    /// **In the layout that brings the window's buttons out of the rail (the tick that lands the sidebar on 200) and
    /// at every tick before it, the name's hosting view stands on the card's edge plus sixteen, within a point.**
    /// The fold in is made first (ticked by hand, then a settle, so the toolbar has been laid out in the rail
    /// and has read or learnt where it starts its items there); the name at rest in the rail is the precondition
    /// (the card's 56 plus 16, 72). Then the fold out: first tick, nine more, and the landing, each followed by the
    /// shell's layout and read at once. After the landing a settle is run and the name is read again as the control:
    /// where it rests is 216, so a reading that is off at the landing is a turn that the rest corrects, not a
    /// place the window never reaches. Under both looks, in a window whose toolbar re-reads its start (the window answering isVisible true for
    /// the span of each layout (`whileShown`)); the variant with the toolbar on its seeds is not run by this row.
    func testTheNameStandsOnTheCardsEdgePlusSixteenAtTheLandingOfAFoldOutOfTheRail() throws {
        PinnedBarSettings.pin(in: self)
        var landing: [String] = []
        var others: [String] = []
        var causes: [String] = []
        var ticks = 0
        for look in Self.looks {
            do {
                let claimed = true
                let label = "\(look.rawValue), toolbar re-reads its start"
                guard let rig = pageWithTabs(look), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
                    XCTFail("\(label): the window wears no SettingsToolbar: nothing is judged")
                    return
                }
                whileShown(claimed, rig.window) { rig.settle() }
                let shell = rig.shell.shell
                let link = HandTickedFoldLink()
                shell.foldLink = link
                shell.reducesMotion = { false }
                XCTAssertTrue(shell.fold(to: 56, animated: true), "\(label): the fold in was cut, not asked for")
                link.fire(at: 100)
                for fraction in Self.foldTicks {
                    whileShown(claimed, rig.window) {
                        link.fire(at: 100 + fraction * HelmMotion.sidebarFoldDuration)
                        shell.layoutSubtreeIfNeeded()
                    }
                    rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
                }
                whileShown(claimed, rig.window) { rig.settle() }
                guard let rail = nameReading(rig, owner, "\(label), at rest in the rail") else { return }
                XCTAssertEqual(rail.card, 56, accuracy: 0.5, "\(label): the fold in did not land in the rail")
                XCTAssertEqual(rail.off, 0, accuracy: 1, "\(label), precondition: \(rail.line)")
                causes.append(rail.cause)

                XCTAssertTrue(shell.fold(to: 200, animated: true), "\(label): the fold out was cut, not asked for")
                XCTAssertTrue(link.fire(at: 200), "\(label): the link was never started")
                whileShown(claimed, rig.window) { shell.layoutSubtreeIfNeeded() }
                if let r = nameReading(rig, owner, "\(label), first tick out of the rail") {
                    if abs(r.off) > 1 { others.append(r.line) }
                    causes.append(r.cause)
                }
                for fraction in Self.foldTicks {
                    link.fire(at: 200 + fraction * HelmMotion.sidebarFoldDuration)
                    whileShown(claimed, rig.window) { shell.layoutSubtreeIfNeeded() }
                    ticks += 1
                    let landed = fraction > 1
                    guard let r = nameReading(rig, owner, "\(label), \(landed ? "the landing" : "tick at \(fraction)")") else { return }
                    if abs(r.off) > 1 { if landed { landing.append(r.line) } else { others.append(r.line) } }
                    if fraction == 0.9 || landed { causes.append(r.cause) }
                }
                XCTAssertEqual(shell.sidebarWidth, 200, accuracy: 0.01, "\(label): the fold did not land on 200")
                whileShown(claimed, rig.window) { rig.settle() }
                if let control = nameReading(rig, owner, "\(label), control after a settle") {
                    XCTAssertEqual(control.off, 0, accuracy: 1, "control: \(control.line)")
                    causes.append(control.cause)
                }
            }
        }
        print("[name out of the rail] " + causes.joined(separator: "\n[name out of the rail] "))
        XCTAssertEqual(ticks, 20, "\(ticks) ticks of 20 were read")
        XCTAssertTrue(landing.isEmpty, "the name is not on the card's edge plus sixteen in the layout that brings the buttons out of the rail: \(landing)")
        XCTAssertTrue(others.isEmpty, "the name left the card's edge plus sixteen at \(others.count) readings before the landing: \(others)")
    }

    // MARK: - Where the tabs stand in the turn a fresh bar is assigned

    /// The search field's width on the worn bar; nil where the bar lists no search item.
    private func searchFieldWidth(_ rig: SettingsWindowRig) -> CGFloat? {
        guard let toolbar = rig.window.toolbar,
              let item = SettingsWindowRig.item("helm.search", in: toolbar) as? NSSearchToolbarItem else { return nil }
        return item.searchField.frame.width
    }

    /// The settle's timer put out of reach for the rest of the row (`SettingsToolbar.settleInterval` 1000, put back by a
    /// teardown block), so that no pass runs unless the row runs it, and a reading made after a change is the turn's
    /// own.
    private func holdTheSettle() {
        let original = SettingsToolbar.settleInterval
        SettingsToolbar.settleInterval = 1000
        addTeardownBlock { @MainActor in SettingsToolbar.settleInterval = original }
    }

    /// One change that puts a bar on the window, read in the turn that made it and again once the settle has nothing
    /// more to move: the tabs, the lead's constant, the search field and the segments.
    private struct FirstFrame {
        let label: String
        /// The bar's item list, in list order.
        let order: [String]
        let turn: Stand
        let turnLead: CGFloat?
        /// The lead's constant read before the frame view was laid out at all.
        let leadAtOnce: CGFloat?
        let turnField: CGFloat?
        let rest: Stand
        let restLead: CGFloat?
        let restField: CGFloat?
        let passes: Int
        /// After each pass of the settle: the lead's constant and the tabs' left edge.
        let perPass: [(lead: CGFloat?, tabs: CGFloat)]
        /// How far right of its resting place the tabs' left edge stood in the turn.
        var off: CGFloat { turn.tabsMinX - rest.tabsMinX }
        var line: String {
            func f(_ value: CGFloat?) -> String { value.map { String(format: "%.1f", Double($0)) } ?? "none" }
            return "\(label): the tabs' left edge \(f(turn.tabsMinX)) in the turn (\(turn.segments) segments, \(f(turn.tabsWidth)) wide, lead \(f(turnLead)), "
                + "search field \(f(turnField))) and \(f(rest.tabsMinX)) at rest after \(passes) passes (\(rest.segments) segments, \(f(rest.tabsWidth)) wide, "
                + "lead \(f(restLead)), search field \(f(restField))), \(String(format: "%+.1f", Double(off))) off; the card's middle \(f(rest.cardMid)), "
                + "the name host \(f(turn.nameMinX))...\(f(turn.nameMaxX)) in the turn and \(f(rest.nameMinX))...\(f(rest.nameMaxX)) at rest; "
                + "items \(order); the lead's constant before any layout \(f(leadAtOnce)); after each pass (lead, tabs): "
                + perPass.map { "(\(f($0.lead)), \(f($0.tabs)))" }.joined(separator: " ")
        }
    }

    /// Runs the settle's pending pass by hand, one at a time with the frame view laid out before each, until a pass
    /// arms no further one; what each pass left (the lead's constant and the tabs' left edge, the frame view laid out),
    /// or nil after a failure (twenty passes, or no pass pending at the start).
    private func runToRest(_ rig: SettingsWindowRig, _ owner: SettingsToolbar, _ label: String,
                           file: StaticString = #filePath, line: UInt = #line) -> [(lead: CGFloat?, tabs: CGFloat)]? {
        func pending() -> DispatchWorkItem? { inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem }
        var seen: [(lead: CGFloat?, tabs: CGFloat)] = []
        for pass in 1...20 {
            guard let work = pending() else {
                XCTFail("\(label): the toolbar holds no pending settle at pass \(pass): nothing is judged", file: file, line: line)
                return nil
            }
            rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
            work.perform()
            rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
            if let toolbar = rig.window.toolbar, let tabs = SettingsWindowRig.item("helm.tabs", in: toolbar)?.view, tabs.window != nil {
                seen.append((leadConstants(in: toolbar)?.first, tabs.convert(tabs.bounds, to: nil).minX))
            }
            if pending() === work { return seen }
        }
        XCTFail("\(label): twenty passes of the settle by hand did not come to rest", file: file, line: line)
        return nil
    }

    /// `change` is made on the worn bar, the bar it puts on the window is read at once (a look's change reaches the toolbar by
    /// a notification on the main queue, so the run loop turns in one-millisecond slices until the window wears another bar,
    /// at most 200; a page switch has made it already), then the settle's passes are run by hand and the bar is read again.
    private func firstFrame(_ rig: SettingsWindowRig, _ label: String, _ change: () -> Void,
                            file: StaticString = #filePath, line: UInt = #line) -> FirstFrame? {
        guard let before = rig.worn("\(label): no bar was on the window before the change", file: file, line: line),
              let owner = before.delegate as? SettingsToolbar else { return nil }
        change()
        var slices = 0
        while rig.window.toolbar === before, slices < 200 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            slices += 1
        }
        guard let after = rig.worn("\(label): the change left the window no bar", file: file, line: line) else { return nil }
        guard after !== before else {
            XCTFail("\(label): the change left the window the bar it had after \(slices) ms: the row reads no new bar", file: file, line: line)
            return nil
        }
        let leadAtOnce = leadConstants(in: after)?.first
        guard let turn = stand(rig, "\(label), in the turn", file: file, line: line) else { return nil }
        let turnLead = leadConstants(in: after)?.first
        let turnField = searchFieldWidth(rig)
        guard let perPass = runToRest(rig, owner, label, file: file, line: line),
              let rest = stand(rig, "\(label), at rest", file: file, line: line) else { return nil }
        let frame = FirstFrame(label: label, order: after.itemIdentifiers.map(\.rawValue), turn: turn, turnLead: turnLead, leadAtOnce: leadAtOnce, turnField: turnField, rest: rest,
                               restLead: leadConstants(in: rig.window.toolbar ?? after)?.first,
                               restField: searchFieldWidth(rig), passes: perPass.count, perPass: perPass)
        print("[first frame] " + frame.line)
        return frame
    }

    /// A rig on the page `probe.a` (two tabs, an action, a search) under `look`, its settle held and run to rest.
    private func restingPage(_ look: HelmBarAppearance, file: StaticString = #filePath, line: UInt = #line)
        -> (rig: SettingsWindowRig, owner: SettingsToolbar)? {
        guard let rig = pageWithTabs(look, file: file, line: line),
              let owner = rig.worn("no toolbar on the page", file: file, line: line)?.delegate as? SettingsToolbar else { return nil }
        holdTheSettle()
        // Reaching the page left a settle pending at the default interval; re-arm it at the held one.
        rig.model.selection = .general
        rig.model.selection = .module("probe.a")
        guard runToRest(rig, owner, "\(look.rawValue), the first page", file: file, line: line) != nil else { return nil }
        return (rig, owner)
    }

    private func switchTo(_ rig: SettingsWindowRig, _ token: String, search: Bool) {
        rig.declare(token, search: search)
        rig.model.selection = .module(token)
    }

    /// What every row below judges: the tabs of the bar just assigned stand within a point of where they rest once the
    /// settle has nothing more to move, and they are whole at rest (so that the comparison is of a place and not of a
    /// fold). The message is the whole reading.
    private func assertFirstFrameIsTheRestingOne(_ frame: FirstFrame, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frame.rest.segments, 2, "\(frame.label): the tabs are not whole at rest, so nothing is compared: \(frame.line)", file: file, line: line)
        XCTAssertEqual(frame.turn.tabsMinX, frame.rest.tabsMinX, accuracy: 1, frame.line, file: file, line: line)
    }

    /// **A page with tabs and a search, visited for the first time, puts its tabs where they will rest in the turn
    /// its bar is assigned, within a point.** The window rests on `probe.a` (two tabs, an action, a search); the settle's
    /// timer is out of reach (`holdTheSettle`), `probe.b` is declared with the same shape and selected, and the tabs'
    /// left edge is read at once (the frame view laid out, nothing pumped), then after the settle's passes run by hand
    /// until one arms no more. Under both looks. **The card's middle is 628, the tabs 168 wide (Flat) and 148 (Liquid
    /// Glass), so they rest at 544 and 554.** Also read and printed with the reading: the lead item's constant in the
    /// turn and at rest, the search field's width in both, the segments, the bar's item list in list order.
    /// Seen red with `tabsWidth(_:)` answering 0 for a bar that has no tabs item: in the turn the tabs' left edge on the card's
    /// middle, 628.0, where they rest at 544.0 (Flat) and 554.0 (Liquid Glass), the lead 279.0 and 275.0.
    func testTheTabsOfAFreshBarWithASearchStandWhereTheyWillRestInTheTurnItIsAssigned() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, _) = restingPage(look),
                  let frame = firstFrame(rig, "\(look.rawValue), a first visit of a page with tabs and a search", {
                      self.switchTo(rig, "probe.b", search: true)
                  }) else { return }
            assertFirstFrameIsTheRestingOne(frame)
        }
    }

    /// **A page with tabs and no search, visited for the first time, puts its tabs where they will rest in the turn its
    /// bar is assigned, within a point.** The twin of the row above for the shape of Hosts and General: no search item
    /// to take room, so the field's width is not read. Seen red with `tabsWidth(_:)` answering 0 for a bar that has no tabs item: in
    /// the turn the tabs' left edge on the card's middle, 628.0, where they rest at 544.0 (Flat) and 554.0 (Liquid Glass), the lead
    /// 279.0 and 275.0.
    func testTheTabsOfAFreshBarWithNoSearchStandWhereTheyWillRestInTheTurnItIsAssigned() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, _) = restingPage(look),
                  let frame = firstFrame(rig, "\(look.rawValue), a first visit of a page with tabs and no search", {
                      self.switchTo(rig, "probe.c", search: false)
                  }) else { return }
            assertFirstFrameIsTheRestingOne(frame)
        }
    }

    /// **A bar the toolbar kept comes back with its tabs where they will rest, in the turn it is assigned, within a point.**
    /// The control for the two rows above: `show(_:key:)` writes the lead of now to a cached bar, whose tabs item has a width, before the
    /// window takes it. The window rests on `probe.a`, goes to a fresh `probe.b` (run to rest) and back to `probe.a`, then to
    /// `probe.b` again; both returns are read. Under both looks. Read: on the return to the first page 544.0 (Flat) and 554.0
    /// (Liquid Glass) in the turn, as at rest; on the return to the second page 543.0 and 553.0 in the turn against 544.0 and
    /// 554.0 at rest.
    func testTheTabsOfACachedBarStandWhereTheyWillRestInTheTurnItComesBack() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, _) = restingPage(look) else { return }
            switchTo(rig, "probe.b", search: true)
            guard let owner = rig.worn("no toolbar on the second page")?.delegate as? SettingsToolbar,
                  runToRest(rig, owner, "\(look.rawValue), the second page") != nil,
                  let toA = firstFrame(rig, "\(look.rawValue), a return to the first page's kept bar", {
                      rig.model.selection = .module("probe.a")
                  }),
                  let toB = firstFrame(rig, "\(look.rawValue), a return to the second page's kept bar", {
                      rig.model.selection = .module("probe.b")
                  }) else { return }
            assertFirstFrameIsTheRestingOne(toA)
            assertFirstFrameIsTheRestingOne(toB)
        }
    }

    /// **A change of look puts a bar on the window, and its tabs stand where they will rest in the turn it is assigned, within
    /// a point.** The window rests on `probe.a` under one look; `AppSettings.barAppearance` is set to the other (the toolbar
    /// hears it by a notification on the main queue, so the run loop turns in one-millisecond slices until the window wears
    /// another bar, and the tabs are read in that turn), and then set back; then the same on `probe.c`, a page with no
    /// search. The first change of a window's life to a look it has not worn is a look whose gap between the lead and the tabs
    /// is still the look's prior (`tabsGapPrior(of:)`, Flat 0 and Liquid Glass 4), the changes after it are to looks whose gap was read. Under both looks as the
    /// start. Seen red with `tabsGapPrior(of:)` answering 16 for both looks, in the two readings of a look the window has not worn
    /// (542.0 in the turn where 554.0 at rest, 528.0 where 544.0), and in all six with `tabsWidth(_:)` answering 0 for a bar that has
    /// no tabs item.
    func testAChangeOfLookPutsABarWhoseTabsStandWhereTheyWillRestInTheTurnItIsAssigned() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            let other: HelmBarAppearance = look == .flat ? .liquidGlass : .flat
            guard let (rig, owner) = restingPage(look),
                  let first = firstFrame(rig, "\(look.rawValue) to \(other.rawValue), a look the window has not worn, tabs and a search", {
                      AppSettings.barAppearance = other
                  }),
                  let back = firstFrame(rig, "\(other.rawValue) to \(look.rawValue), a look whose gap was read, tabs and a search", {
                      AppSettings.barAppearance = look
                  }) else { return }
            assertFirstFrameIsTheRestingOne(first)
            assertFirstFrameIsTheRestingOne(back)
            switchTo(rig, "probe.c", search: false)
            guard runToRest(rig, owner, "\(look.rawValue), the page with no search") != nil,
                  let noSearch = firstFrame(rig, "\(look.rawValue) to \(other.rawValue), a look whose gap was read, tabs and no search", {
                      AppSettings.barAppearance = other
                  }) else { return }
            assertFirstFrameIsTheRestingOne(noSearch)
        }
    }

    // MARK: - Where the name, the tabs and the field stand across the passes that follow a show and a landing

    /// What stood where after one pass of the settle (pass 0 is the state before any pass): what the toolbar held and what the
    /// frames read, the frame view laid out, with the window answering `isVisible` true for the pass and the layouts.
    private struct PassReading {
        let pass: Int
        let itemsStart: CGFloat
        let moves: Int
        let inset: CGFloat?
        let lead: CGFloat?
        let cap: CGFloat?
        let container: CGFloat
        let name: CGFloat
        let tabs: CGFloat
        let field: CGFloat?
        let rearmed: Bool?
        var line: String {
            func n(_ value: CGFloat?) -> String { value.map { String(format: "%.2f", Double($0)) } ?? "none" }
            return "pass \(pass): itemsStart \(n(itemsStart)), moves \(moves), inset \(n(inset)), lead \(n(lead)), cap \(n(cap)), "
                + "item from \(n(container)), name \(n(name)), tabs \(n(tabs)), field \(n(field)), re-armed \(rearmed.map { $0 ? "yes" : "no" } ?? "-")"
        }
    }

    /// The state now, read with the frame view laid out, under a window that answers visible when `shown`.
    private func passReading(_ rig: SettingsWindowRig, _ owner: SettingsToolbar, pass: Int, rearmed: Bool?, shown: Bool,
                             file: StaticString = #filePath, line: UInt = #line) -> PassReading? {
        var read: Stand?
        whileShown(shown, rig.window) { read = stand(rig, "pass \(pass)", file: file, line: line) }
        guard let s = read else { return nil }
        let cap = wornPageBar(rig, of: owner).flatMap { barState($0, "pass \(pass)", file: file, line: line)?.cap.constant }
        return PassReading(pass: pass, itemsStart: owner.itemsStart, moves: owner.itemsStartMoves, inset: s.inset,
                           lead: leadConstants(in: rig.window.toolbar ?? NSToolbar())?.first, cap: cap, container: s.containerMinX,
                           name: s.nameMinX, tabs: s.tabsMinX, field: searchFieldWidth(rig), rearmed: rearmed)
    }

    /// The settle's pending pass, run by hand with the window answering visible (unless not `shown`) for the pass and for the layouts either side,
    /// until a pass arms no further one or `limit` passes have run; the state before the first and after each. nil after a
    /// failure (no pass pending at the start).
    private func passesOfTheSettle(_ rig: SettingsWindowRig, _ owner: SettingsToolbar, _ label: String, limit: Int = 12,
                                   shown: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> [PassReading]? {
        func pending() -> DispatchWorkItem? { inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem }
        guard let first = passReading(rig, owner, pass: 0, rearmed: nil, shown: shown, file: file, line: line) else { return nil }
        var seen = [first]
        for pass in 1...limit {
            guard let work = pending() else {
                XCTFail("\(label): the toolbar holds no pending settle at pass \(pass): nothing is judged", file: file, line: line)
                return nil
            }
            var armedAgain = false
            whileShown(shown, rig.window) {
                rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
                work.perform()
                armedAgain = pending() !== work
                rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
            }
            guard let reading = passReading(rig, owner, pass: pass, rearmed: armedAgain, shown: shown, file: file, line: line) else { return nil }
            seen.append(reading)
            if !armedAgain { return seen }
        }
        return seen
    }

    /// The fold of the sidebar to `width`, ticked by hand: the first tick at `start` (it writes nothing), then
    /// `foldTicks` after it, each followed by the shell's layout under a window that answers visible and by the frame view's.
    private func foldByTicks(_ rig: SettingsWindowRig, _ link: HandTickedFoldLink, to width: CGFloat, startingAt start: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        let shell = rig.shell.shell
        XCTAssertTrue(shell.fold(to: width, animated: true), "the fold to \(width) was cut, not asked for", file: file, line: line)
        XCTAssertTrue(link.fire(at: start), "the link was never started", file: file, line: line)
        for fraction in Self.foldTicks {
            whileShown(true, rig.window) {
                link.fire(at: start + fraction * HelmMotion.sidebarFoldDuration)
                shell.layoutSubtreeIfNeeded()
            }
            rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(shell.sidebarWidth, width, accuracy: 0.01, "the fold did not land on \(width)", file: file, line: line)
    }

    /// The page of three tabs, an action and a search under `look` at 1060 and a sidebar of 200, at rest with its settle held
    /// out of reach: the window answers not shown, so the toolbar reads nothing of where its items start, and the passes by hand
    /// have run until one armed no more. The page has the shape of a package manager's, whose whole tabs (343 under Flat) and
    /// field (narrower than its usual 283) are the shape on which the name, the tabs and the field moved a point at each pass before
    /// `itemsStartTolerance`; nil after a failure.
    private func shapedPageAtRest(_ look: HelmBarAppearance, file: StaticString = #filePath, line: UInt = #line)
        -> (rig: SettingsWindowRig, owner: SettingsToolbar)? {
        guard let rig = shapedPage(look, file: file, line: line),
              let owner = rig.worn("no toolbar on the page", file: file, line: line)?.delegate as? SettingsToolbar else { return nil }
        holdTheSettle()
        rig.model.selection = .general
        rig.model.selection = .module("probe.shaped")
        guard runToRest(rig, owner, "\(look.rawValue), the page at rest", file: file, line: line) != nil else { return nil }
        return (rig, owner)
    }

    /// How many passes of the settle a show or a landing may take before the name, the tabs and the field must stand still.
    /// Four: a pass that reads where the items start and writes the inset, one that finds the same start and writes the
    /// lead and the offer from it, one that finds both still, and one to spare; before `itemsStartTolerance` the loop took five or six
    /// and was ended by `SettingsToolbar.itemsStartMoveCeiling`, not by two reads agreeing.
    private static let passesToRest = 4

    /// **After the first pass that follows `event`, no later pass moves the name's hosting view, the tabs' left edge or the search
    /// field's width, and the passes come to an end of themselves.** The reference is the reading after pass 1 (the pass
    /// that reads where the items start); each later reading is held to it within a quarter of a point. A quarter: AppKit
    /// places these items on half points (the name's item at 92.0 or 92.5, the tabs at 456.0 or 457.0), the defect is a full
    /// point, and what is wanted is standing still, so any move of a half point is a move. The field is held to itself between the
    /// passes that offered it the same cap alone. The passes end of themselves: the
    /// last pass armed no further one, within `passesToRest` passes, and `itemsStartMoves` is under the ceiling that would
    /// otherwise have stopped the reads. Every message carries the whole table.
    private func assertThePassesStandStill(_ table: [PassReading], _ owner: SettingsToolbar, _ label: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let whole = "\n" + table.map { "    " + $0.line }.joined(separator: "\n")
        XCTAssertGreaterThanOrEqual(table.count, 2, "\(label): no pass ran, nothing is judged\(whole)", file: file, line: line)
        guard table.count >= 2 else { return }
        let reference = table[1]
        let later = table.dropFirst(2)
        func spread(_ value: (PassReading) -> CGFloat?) -> CGFloat {
            let all = ([reference] + later).compactMap(value)
            return (all.max() ?? 0) - (all.min() ?? 0)
        }
        XCTAssertEqual(spread(\.name), 0, accuracy: 0.25,
                       "\(label): the name's host moved after pass 1 (it stood at \(reference.name))\(whole)", file: file, line: line)
        XCTAssertEqual(spread(\.tabs), 0, accuracy: 0.25,
                       "\(label): the tabs moved after pass 1 (they stood at \(reference.tabs))\(whole)", file: file, line: line)
        // The field is held to itself only between passes that offered it the same cap: a pass that writes a new offer moves the
        // field by the offer's difference, which is not a pass moving it under an unchanged offer (a landing in the rail raises the
        // cap from 208.5 to 280.5 under Flat and from 225 to 283 under Liquid Glass at the first pass that follows it, and the
        // field follows the cap).
        let widest = Dictionary(grouping: table.dropFirst(), by: \.cap).values.map { group -> CGFloat in
            let widths = group.compactMap(\.field)
            return (widths.max() ?? 0) - (widths.min() ?? 0)
        }.max() ?? 0
        XCTAssertEqual(widest, 0, accuracy: 0.25,
                       "\(label): the search field's width moved between passes that offered it the same cap\(whole)", file: file, line: line)
        XCTAssertEqual(table.last?.rearmed, false, "\(label): the last pass armed another: the passes did not end\(whole)", file: file, line: line)
        XCTAssertLessThanOrEqual(table.count - 1, Self.passesToRest,
                                 "\(label): \(table.count - 1) passes, more than the \(Self.passesToRest) a show or a landing is given\(whole)", file: file, line: line)
        XCTAssertLessThan(owner.itemsStartMoves, SettingsToolbar.itemsStartMoveCeiling,
                          "\(label): the reads of where the items start were stopped by the ceiling of \(SettingsToolbar.itemsStartMoveCeiling), "
                          + "not by two reads agreeing (\(owner.itemsStartMoves) moves)\(whole)", file: file, line: line)
    }

    /// **A window that is shown after it has rested: no pass of the settle moves the name, the tabs or the field after the first.** The window
    /// rests on the page (three tabs, an action, a search) as a window never ordered does, its toolbar having read nothing of where its
    /// items start; then the window answers `isVisible` true (`whileShown`), a settle is armed, and its passes are run by hand with the
    /// frame view laid out either side, each read. Under both looks. Before `itemsStartTolerance`, when only a read equal to
    /// the start held was refused (an unshown window that answers visible): under Flat the name's host 216.5, 215.5, 216.5, 215.5, 215.5 after
    /// passes 1 to 5, the tabs 457, 456, 457, 456, 457, the field 204, 205, 204, 205, 204, the toolbar's items start read 92.0, 92.5, 92.0,
    /// 92.5 and then no more, six passes, the last of them armed none; under Liquid Glass the same with the tabs 474, 473 and the field
    /// 220, 221; seen red since with the tolerance at 0 (the name's host moved 1.0 after pass 1).
    func testAfterAShowNoPassMovesTheNameTheTabsOrTheField() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, owner) = shapedPageAtRest(look) else { return }
            rig.model.selection = .general
            rig.model.selection = .module("probe.shaped")
            guard let table = passesOfTheSettle(rig, owner, "\(look.rawValue), after a show") else { return }
            print("[passes after a show] \(look.rawValue)\n" + table.map { "[passes after a show]   " + $0.line }.joined(separator: "\n"))
            assertThePassesStandStill(table, owner, "\(look.rawValue), after a show")
        }
    }

    /// **The landing of a fold of the sidebar into the rail: no pass of the settle that follows moves the name, the tabs or the field after the
    /// first.** The window rests as above; the sidebar is folded to 56 by the hand-ticked link (`foldByTicks`), the passes run by hand
    /// from the landing. Under both looks. Before `itemsStartTolerance`, when only a read equal to the start held was refused: the name's host 72.5, 71.5, 72.5
    /// after passes 1 to 3, the tabs 385, 384, 385 (Flat), the toolbar's start 22.0, 22.5, 22.0 read, then no more; seen red since with
    /// the tolerance at 0 (the name's host moved 1.0 after pass 1).
    func testAfterTheLandingOfAFoldIntoTheRailNoPassMovesTheNameTheTabsOrTheField() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, owner) = shapedPageAtRest(look) else { return }
            let link = HandTickedFoldLink()
            rig.shell.shell.foldLink = link
            rig.shell.shell.reducesMotion = { false }
            foldByTicks(rig, link, to: 56, startingAt: 100)
            guard let table = passesOfTheSettle(rig, owner, "\(look.rawValue), after the landing in the rail") else { return }
            print("[passes after the landing in] \(look.rawValue)\n" + table.map { "[passes after the landing in]   " + $0.line }.joined(separator: "\n"))
            assertThePassesStandStill(table, owner, "\(look.rawValue), after the landing in the rail")
        }
    }

    /// **The landing of a fold of the sidebar out of the rail: no pass of the settle that follows moves the name, the tabs or the field after the
    /// first.** The window rests, is folded into the rail and its passes run by hand to the end, then folded out to 200, and the passes
    /// that follow the landing are read. Under both looks. Before `itemsStartTolerance`, when only a read equal to the start held was refused: the name's host 215.5, 216.5, 215.5
    /// after passes 1 to 3, the tabs 456, 457, 456 (Flat), the toolbar's start read 92.5, 92.0, 92.5, then no more; seen red since with
    /// the tolerance at 0 (the name's host moved 1.0 after pass 1).
    func testAfterTheLandingOfAFoldOutOfTheRailNoPassMovesTheNameTheTabsOrTheField() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, owner) = shapedPageAtRest(look) else { return }
            let link = HandTickedFoldLink()
            rig.shell.shell.foldLink = link
            rig.shell.shell.reducesMotion = { false }
            foldByTicks(rig, link, to: 56, startingAt: 100)
            guard passesOfTheSettle(rig, owner, "\(look.rawValue), in the rail") != nil else { return }
            foldByTicks(rig, link, to: 200, startingAt: 200)
            guard let table = passesOfTheSettle(rig, owner, "\(look.rawValue), after the landing out of the rail") else { return }
            print("[passes after the landing out] \(look.rawValue)\n" + table.map { "[passes after the landing out]   " + $0.line }.joined(separator: "\n"))
            assertThePassesStandStill(table, owner, "\(look.rawValue), after the landing out of the rail")
        }
    }

    /// **Control: the same show, with the window answering not shown, leaves the passes standing still.** The toolbar then reads nothing of
    /// where its items start (`learnStartOfItems(_:)` asks the window's `isVisible`), so what would move the name, the tabs and the field in the
    /// rows above is that read and what it writes; the judgement is the same one. With `itemsStartTolerance` at 0 the three rows above are red (the name's host
    /// moves 1.0 after pass 1) and this one stays green.
    func testWithTheWindowNotShownThePassesOfAShowStandStill() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            guard let (rig, owner) = shapedPageAtRest(look) else { return }
            rig.model.selection = .general
            rig.model.selection = .module("probe.shaped")
            guard let table = passesOfTheSettle(rig, owner, "\(look.rawValue), a show that reads nothing", shown: false) else { return }
            assertThePassesStandStill(table, owner, "\(look.rawValue), a show that reads nothing")
        }
    }

    /// **The tabs fold and unfold in a pass of the settle, and in that same turn, with no further pass and no layout,
    /// the lead item's constant is the lead for the tabs as they now stand: it moves by half of what the tabs'
    /// width moved (`setTabsFolded`'s own `writeTabsLead`).** The settle's timer is out of reach
    /// (`SettingsToolbar.settleInterval` 1000, put back by a teardown block) and its pending pass (`settleWorkItem`,
    /// read by `Mirror`) is run by hand, as `testTheCapFollowsTheTabsInTheTurnThatFoldsOrUnfoldsThem` does, on the same
    /// windows: the start is the zero window plus 24 (tabs whole), narrowed to one point under the zero window until
    /// the tabs fold, then widened again until they unfold. The constant is read just before the flipping pass and
    /// at once after it, and the tabs' frame width at once after it too; only then is the frame view laid out and the
    /// tabs' width read again. **Claims, for each half:** the tabs' frame width read at once equals the one after the
    /// layout (so the lead can be worked out from it in that turn), and the constant after the pass equals the
    /// constant before it plus half of the tabs' width lost (`(before - now) / 2`; the name does not move and the
    /// card does not move, so the other terms of `tabsLead(paneLeading:paneWidth:tabsWidth:gap:nameMaxX:)` drop
    /// out), within a point. The relation is not the absolute lead, whose gap the frames read 4.5 on one side while
    /// the toolbar's own is 0, and a lead of 27 would stand 4.5 points inside its viewer,
    /// worked out as (36 - 27) / 2 from an assumed viewer 36 wide and not read. A guard asserts the flip moved the
    /// tabs by more than 40 points, so a flip that moved nothing judges nothing.
    /// Read (Flat): folding took two passes, the constant 27.000 -> 117.500, the tabs 343.000 -> 162.000 in the frame read
    /// at once and 162.000 after the layout; unfolding took three passes, the constant 130.000 -> 39.500, the tabs 162.000
    /// -> 343.000, the same at once and after. The relation holds in both: 27 + 90.5 and 130 - 90.5.
    /// Seen red on both halves with the `writeTabsLead(bar)` line at the end of `setTabsFolded` deleted: the constant stayed
    /// 27.000 after the folding pass, where 117.500 is the lead for the tabs as they then stood (343.000 -> 162.000), and 130.0
    /// after the unfolding pass, where 39.5 was wanted. Not run: the lead written before the layout in that function.
    func testTheLeadFollowsTheTabsInTheTurnThatFoldsOrUnfoldsThem() throws {
        PinnedBarSettings.pin(in: self)
        guard let zero = zeroWindow("zero for the lead") else { return }
        let wide = zero.reading.window + 24
        guard let rig = settledAt(window: wide), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
            XCTFail("the window wears no SettingsToolbar to run the settle of by hand: nothing is judged")
            return
        }
        let original = SettingsToolbar.settleInterval
        SettingsToolbar.settleInterval = 1000
        addTeardownBlock { @MainActor in SettingsToolbar.settleInterval = original }
        rig.window.setContentSize(NSSize(width: zero.reading.window - 1, height: 760))
        rig.window.contentView?.layoutSubtreeIfNeeded()
        func judge(_ flip: FlippingPass, _ what: String) {
            guard let before = flip.leadBefore, let after = flip.leadAfter, let atOnce = flip.tabsWidthAfter else {
                XCTFail("\(what): the lead's constant or the tabs' frame could not be read around the flipping pass: nothing is judged")
                return
            }
            rig.window.contentView?.superview?.layoutSubtreeIfNeeded()
            guard let now = stand(rig, "\(what), after the layout") else { return }
            let lost = flip.standBefore.tabsWidth - now.tabsWidth
            XCTAssertGreaterThan(abs(lost), 40, "\(what): the tabs' width moved by \(f3(-lost)) only (\(f3(flip.standBefore.tabsWidth)) -> \(f3(now.tabsWidth))): the flip moved nothing to judge")
            XCTAssertEqual(atOnce, now.tabsWidth, accuracy: 0.5,
                           "\(what): the tabs' frame read at once after the pass is \(f3(atOnce)), after the layout \(f3(now.tabsWidth)): the lead cannot be worked out from the tabs as they stand in that turn")
            XCTAssertEqual(after, before + lost / 2, accuracy: 1,
                           "\(what) (pass \(flip.passes)): the lead's constant is \(f3(after)) at once after the pass, \(f3(before)) before it; the tabs went \(f3(flip.standBefore.tabsWidth)) -> \(f3(now.tabsWidth)), so the lead for them is \(f3(before + lost / 2)): it is the lead of the tabs as they stood before the flip")
            print("[lead turn] \(what): pass \(flip.passes), constant \(f3(before)) -> \(f3(after)), tabs \(f3(flip.standBefore.tabsWidth)) -> \(f3(atOnce)) at once, \(f3(now.tabsWidth)) after the layout")
        }
        if let fold = flipTheTabs(rig, to: true, "fold") {
            judge(fold, "folding")
            for _ in 0..<12 {
                guard let work = inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem else { break }
                work.perform()
                if (inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem) === work { break }
            }
            rig.window.setContentSize(NSSize(width: wide, height: 760))
            rig.window.contentView?.layoutSubtreeIfNeeded()
            if let unfold = flipTheTabs(rig, to: false, "unfold") { judge(unfold, "unfolding") }
        }
    }

    /// **Where the name holds the tabs right of the card's middle, the slack the rule reads is the room the frames
    /// show less the search field's floor, and the floor constant is the distance the frames put the tabs from the
    /// name's end.** At the zero window (found by reading, `zeroWindow`) the whole tabs stand `held` points right of
    /// the name's host, right of where the card's middle would put them. Three claims: the tabs are held there
    /// (their left edge is more than a point right of the centred place); `held` is `tabsLeadFloor` within a point
    /// (the distance is read off the frames and not off the rule; that it is the item's own least width is assumed); and the slack the rule read
    /// (`FoldReading`) equals the bar's right end less the tabs' end, `tabsToActions`, the actions' width,
    /// `ShellBarLayout.actionsToSearch` and `ShellBarLayout.searchFloor`, within a point. The bar's right end is the
    /// search item's slot, the view the rule reads the same edge of; the tabs' end and the actions are frames. Flat.
    /// Read: the zero window 900 read slack 0.00; the tabs 385.00...728.00 right of the name's end 349.00 (held 36.00,
    /// the centred place 375.50), the actions 816.00...852.00, the bar's end 896.00, so the room less the floor is
    /// 896 - (728 + 8 + 36 + 4) - 120 = 0.00. The hold is 9.5 points deep at this window, so a floor of 16 moves the
    /// rule's slack by 9.5 here (not the 20 of the floor's whole difference, which the centred place caps).
    /// Seen red with `tabsLeadFloor` 16 on the second claim (the tabs stood 36.000 points past the name's end, the floor
    /// constant said 16.000) and on the third (the zero window was found at 883, where the rule read a slack of 0.000 and the
    /// frames show a room of -17.000 less the floor).
    func testTheFloorTheRuleChargesIsTheDistanceTheFramesHoldTheTabsAt() throws {
        PinnedBarSettings.pin(in: self)
        guard let zero = zeroWindow("zero for the floor"),
              let b = beside(zero.rig, window: zero.reading.window, "the zero window") else { return }
        print("[floor] slack by the rule \(f3(zero.slack)): \(b.line)")
        guard let slot = b.slotMaxX, let actionsMin = b.stand.actionsMinX, let actionsMax = b.actionsMaxX else {
            XCTFail("the zero window has no actions item or no search slot to read the room from: \(b.line)")
            return
        }
        let held = b.stand.tabsMinX - b.stand.nameMaxX
        XCTAssertGreaterThan(b.stand.tabsMinX, b.stand.centredMinX + 1,
                             "the tabs stand at \(f3(b.stand.tabsMinX)), not right of the centred place \(f3(b.stand.centredMinX)): the name does not hold them here and the floor is not judged. \(b.line)")
        XCTAssertEqual(held, SettingsToolbar.tabsLeadFloor, accuracy: 1,
                       "the tabs stand \(f3(held)) points past the name's end, the floor constant says \(f3(SettingsToolbar.tabsLeadFloor)). \(b.line)")
        let room = slot - (b.stand.tabsMaxX + SettingsToolbar.tabsToActions + (actionsMax - actionsMin) + ShellBarLayout.actionsToSearch)
            - ShellBarLayout.searchFloor
        XCTAssertEqual(zero.slack, room, accuracy: 1,
                       "the rule read a slack of \(f3(zero.slack)) at window \(f(zero.reading.window)), the frames show a room of \(f3(room)) less the floor (bar ends \(f3(slot)), tabs end \(f3(b.stand.tabsMaxX)), actions \(f3(actionsMax - actionsMin)) wide). \(b.line)")
    }

    /// **With the search field holding text, so that no offer stands and the fold is predicted from the layout of
    /// now, folded tabs unfold only where the room the frames leave round them, from the lead's END to the actions
    /// and less the growth of the tabs, reaches the unfold margin (16), and not where the lead's own width is counted
    /// as room.** The page has three tabs, an action and a search holding «find» (`stringValue`, which needs no key
    /// window). The row narrows the window to 960 (the tabs fold there, by AppKit's eviction: with the text the rule
    /// itself sees a room of 8 or more round whole tabs at every width, so it never folds them), puts the settle's
    /// timer out of reach and widens the window 8 points at a time from 1380, running the settle's pending passes by
    /// hand at each width and reading the frames before every pass. **The rule's input, from the frames:** `around`
    /// (the lead's end to the tabs' start plus the tabs' end to the actions' start) less the whole tabs' width
    /// plus the folded tabs' width. Claims: the branch (every read has the cap inactive and the field holding text,
    /// printed); at every width without a flip the last pass's input is under 17 (one over the margin); the tabs do
    /// unfold within the sweep; and the input before the flipping pass is within 15...25 (the margin and one step).
    /// Read (Flat, a window never shown): at window 960 the tabs folded 162 wide, the field 245 wide, the room round the
    /// tabs 8.00. The sweep from 1380 in steps of 8 read the input -43.000 at 1380 and gaining 4 points for each step (a half
    /// point for each point of window): -7.000 at 1452, 13.000 at 1492, where the tabs stayed folded, and 17.000 at 1500,
    /// where one pass unfolded them. How far counting the lead as room would put the input over the margin is not read: the row
    /// prints the lead's edges at window 960 only (349.00...497.00), at none of the sweep's widths.
    /// Seen red with `let leadingView = nameView` in `currentToolbarSlack`: the tabs unfolded at window 1380 at an input of
    /// -43.000, under the margin of 16 (the lead counted as room).
    func testFoldedTabsBesideAFieldHoldingTextUnfoldOnlyWhereTheRoomBesideTheLeadCoversTheirGrowth() throws {
        PinnedBarSettings.pin(in: self)
        guard let rig = textPage(), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
            XCTFail("the window wears no SettingsToolbar: nothing is judged")
            return
        }
        for w in [CGFloat(980), 960] {
            place(rig, window: w, sidebar: Self.shapedSidebar)
            SettingsWindowRig.pump()
            rig.settle()
        }
        guard let start = beside(rig, window: 960, "start") else { return }
        print("[text start] \(start.line)")
        XCTAssertEqual(start.folded, true, "the tabs are not folded at window 960: the row does not begin from folded tabs. \(start.line)")
        guard start.folded == true else { return }
        let original = SettingsToolbar.settleInterval
        SettingsToolbar.settleInterval = 1000
        addTeardownBlock { @MainActor in SettingsToolbar.settleInterval = original }
        func input(_ b: Beside) -> CGFloat? {
            guard let around = b.around, let full = b.full else { return nil }
            return around - (full - b.stand.tabsWidth)
        }
        func foldedNow() -> Bool? { wornPageBar(rig, of: owner).flatMap { stored("tabsFolded", of: $0) as? Bool } }
        var table: [String] = []
        var stayed: [String] = []
        var flip: (window: CGFloat, input: CGFloat)?
        var branch: [String] = []
        for w in Array(stride(from: CGFloat(1380), through: 1560, by: 8)) {
            rig.window.setContentSize(NSSize(width: w, height: 760))
            rig.window.contentView?.layoutSubtreeIfNeeded()
            var passes = 0
            var lastInput: CGFloat?
            for _ in 0..<12 {
                guard let work = inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem else { break }
                guard let b = beside(rig, window: w, "window \(f(w)), pass \(passes + 1)") else { return }
                if b.capActive != false || b.fieldHasText != true { branch.append("window \(f(w)): cap \(b.capActive.map { "\($0)" } ?? "?"), text \(b.fieldHasText.map { "\($0)" } ?? "?")") }
                work.perform()
                passes += 1
                if b.folded == true, let value = input(b) {
                    lastInput = value
                    if foldedNow() == false { flip = (w, value) }
                }
                if flip != nil || (inside(stored("settleWorkItem", of: owner)) as? DispatchWorkItem) === work { break }
            }
            table.append("\(f(w)): \(passes) passes, input \(lastInput.map { f3($0) } ?? "none")\(flip?.window == w ? " (unfolded)" : "")")
            XCTAssertGreaterThan(passes, 0, "window \(f(w)): the settle holds no pending pass: nothing was judged there")
            if let flip, flip.window == w { break }
            if let lastInput, lastInput >= 17 { stayed.append("window \(f(w)) input \(f3(lastInput))") }
        }
        print("[text sweep] \(table.joined(separator: "; "))")
        XCTAssertTrue(branch.isEmpty, "the row is not on the branch with no offer (cap inactive, field holding text): \(branch)")
        XCTAssertTrue(stayed.isEmpty, "the tabs stayed folded where the room round them, less their growth, is 17 or more: \(stayed); sweep: \(table)")
        guard let flip else {
            XCTFail("the tabs did not unfold within the sweep up to 1560: nothing is judged; sweep: \(table)")
            return
        }
        XCTAssertGreaterThanOrEqual(flip.input, 15, "the tabs unfolded at window \(f(flip.window)) where the room round them, from the lead's end and less their growth, is \(f3(flip.input)), under the margin of 16: the lead is counted as room. sweep: \(table)")
        XCTAssertLessThanOrEqual(flip.input, 25, "the tabs unfolded at window \(f(flip.window)) only at an input of \(f3(flip.input)), a step and more over the margin: they waited. sweep: \(table)")
    }

    /// **A start of the toolbar's items that is not the seed is learnt from the name item and is the one the lead is
    /// worked out from, for each placement, in a window that is shown.** The toolbar is told, by a direct `paneMoved`, the placement the window is
    /// NOT in: the full sidebar's window told the rail (the items start at 92.5 there, the rail's seed is 22.5), and the
    /// window in the rail told the full sidebar (22.5 there, the seed 92.5). The rule's input is then a start 70
    /// points from the seed of the placement told, the state of another system or a shown window, put under the
    /// toolbar without editing anything. The settle runs with the window answering `isVisible` true (`whileShown`, around `rig.settle()`
    /// only: `learnStartOfItems(_:)` reads a window that is not visible not at all, which `testAnUnshownWindowNeverMovesWhereTheItemsStart`
    /// in `TheBarTellsItsShellWhenItIsAttachedTests` holds). After the settle: the name's item stands where it stood (so the row has
    /// not moved the window), the start learnt for the placement told (`learntItemsStarts`, by `Mirror`) is the item's
    /// left edge within a point, and the tabs' middle is the card's within `halfPoints` (a lead worked out from the seed
    /// would put them 70 off). A guard asserts the seed of the placement told is over 20 from the item's start. Both looks, both lies.
    /// Read, in each of the four runs, from the `[learnt start]` line the row prints (`honest item at <a>, learnt <dictionary>, tabs <b> off`):
    /// the honest item at 92.500 (told the rail) and 22.000 (told the full sidebar), the start
    /// learnt for the placement told 92.0 and 22.5 (the told inset moved the item by half a point before the read, and the tolerance of
    /// a point keeps that start), the dictionary holding that one key, and the tabs 1.000 off the card's middle (told the rail) and 0.000 off (told the full sidebar)
    /// after the settle, under both looks.
    /// Seen red in all four runs, in a window never shown (`rig.settle()` without `whileShown`) with the gate on `isVisible` in
    /// `learnStartOfItems` (the start learnt for the placement told was none, learnt [:], and the tabs' middle 70.0, -26.0, 70.0 and -24.0
    /// off the card's): the row as it stood before the gate. The failed assertion's message prints the item's place after the settle
    /// (`the item stands at`), a reading apart from the honest one that the `[learnt start]` line prints.
    /// Seen red with the window shown and the settle returning after a learnt start with the inset written and the lead not (the tabs' middle -21.0
    /// off the card's), and with `nameMaxX(_:)` working from the other placement's start. Not run: `learnStartOfItems` returning first,
    /// `startOfItems(rail:)` answering the seed alone, the write `learntItemsStarts[pane.rail] = start` deleted.
    func testAStartOfItemsThatIsNotTheSeedIsLearntAndTheLeadIsWorkedOutFromIt() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            for told in [true, false] {
                let label = "\(look.rawValue), told \(told ? "the rail" : "the full sidebar") over a window \(told ? "with" : "in")\(told ? " the full sidebar" : " the rail")"
                guard let rig = pageWithTabs(look), let owner = rig.window.toolbar?.delegate as? SettingsToolbar else {
                    XCTFail("\(label): the window wears no SettingsToolbar: nothing is judged")
                    return
                }
                place(rig, window: 1060, sidebar: told ? 200 : 56)
                guard let honest = stand(rig, "\(label): honest") else { continue }
                XCTAssertEqual(honest.off, 0, accuracy: 1, "\(label): the tabs are \(f3(honest.off)) off the card's middle before the toolbar is told wrong: the row does not begin from a bar that stands right. \(honest.line)")
                let seed = told ? SettingsToolbar.railItemsStartSeed : SettingsToolbar.itemsStartSeed
                XCTAssertGreaterThan(abs(honest.containerMinX - seed), 20, "\(label): the items start at \(f3(honest.containerMinX)), the seed of the placement told is \(f3(seed)): the start is not put away from the seed")
                owner.paneMoved(leading: honest.cardMinX, width: honest.cardWidth, rail: told)
                whileShown(true, rig.window) { rig.settle() }
                guard let s = stand(rig, "\(label): after") else { continue }
                XCTAssertEqual(s.containerMinX, honest.containerMinX, accuracy: 0.5, "\(label): the name's item moved from \(f3(honest.containerMinX)) to \(f3(s.containerMinX)): the row moved the window")
                let learnt = stored("learntItemsStarts", of: owner) as? [Bool: CGFloat]
                XCTAssertEqual(learnt?[told] ?? -1, s.containerMinX, accuracy: 1,
                               "\(label): the start learnt for the placement told is \(learnt?[told].map { f3($0) } ?? "none") (learnt \(learnt.map { "\($0)" } ?? "unreadable")), the item stands at \(f3(s.containerMinX))")
                XCTAssertEqual(s.off, 0, accuracy: Self.halfPoints, "\(label): the tabs' middle is \(f3(s.off)) off the card's after the settle: the lead is worked out from a start that is not the item's. \(s.line)")
                print("[learnt start] \(label): honest item at \(f3(honest.containerMinX)), learnt \(learnt.map { "\($0)" } ?? "none"), tabs \(f3(s.off)) off")
            }
        }
    }

    // MARK: - What the search field is offered, as numbers

    /// `SettingsToolbar.searchOffer(...)` over plain numbers. The defaults are a page in a window 1060 wide with the sidebar at
    /// 200: the card from 200 and 856 wide, so its middle is 628; whole tabs 310 wide, as the shaped page reads under Liquid
    /// Glass in a window never shown; the actions 72 wide (a second action declared and hidden), the search field ending at
    /// 1052 and the name ending at 309, as a shown window read them, so `tabsEarliest` is taken as 345 (its end and 36), left of
    /// where the tabs start. The toolbar passes the end of the search item's slot as `barEnd`, read 4 points right of the
    /// field's edge in a window never shown, so these rows pin the arithmetic and not that window's offer.
    private static func offer(barEnd: CGFloat = 1052, paneLeading: CGFloat = 200, paneWidth: CGFloat = 856,
                              tabsWidth: CGFloat = 310, tabsEarliest: CGFloat = 345,
                              actionsWidth: CGFloat = 72) -> SettingsToolbar.SearchOffer {
        SettingsToolbar.searchOffer(barEnd: barEnd, paneLeading: paneLeading, paneWidth: paneWidth, tabsWidth: tabsWidth,
                                    tabsEarliest: tabsEarliest, actionsWidth: actionsWidth)
    }

    /// One assertion per number of an offer, each saying which case it is.
    private func expect(_ got: SettingsToolbar.SearchOffer, width: CGFloat, slack: CGFloat, fits: Bool, _ why: String,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.width, width, accuracy: 0.0001, "\(why): the offered width is \(got.width), not \(width)", file: file, line: line)
        XCTAssertEqual(got.slack, slack, accuracy: 0.0001, "\(why): the slack is \(got.slack), not \(slack)", file: file, line: line)
        XCTAssertEqual(got.wholeTabsFit, fits, "\(why): the whole tabs \(got.wholeTabsFit ? "fit" : "do not fit"), slack \(got.slack)", file: file, line: line)
    }

    /// **The offer is the room beside whole tabs on the card's middle, held from `searchFloor` (120) to
    /// `searchWidth` (283), and the slack is that room less the floor.** The room is the search item's end less the
    /// tabs' end, 8 to the actions, the actions and 4 to the field (8 alone with no actions). Worked out by hand, per
    /// case, in this comment and not by the function's formula:
    /// - Liquid Glass at 1060/200 with the 72-wide capsule: the tabs 310 wide stand 473...783 (628 less 155), so the
    ///   room is 1052 less 783 less 8 less 72 less 4 = 185, slack 65, offered 185.
    /// - Flat, the tabs 343 wide: 456.5...799.5, room 1052 less 799.5 less 84 = 168.5, slack 48.5, offered 168.5.
    /// - The same with the capsule 36 wide: 1052 less 783 less 48 = 221 (slack 101) and, Flat, 1052 less 799.5 less
    ///   48 = 204.5 (slack 84.5).
    /// - 1400/200, card from 200 and 1196 wide, middle 798, the item ending at 1392: Liquid Glass, tabs 643...953,
    ///   room 391, slack 271, offered 283 (the usual width holds it); Flat, tabs 626.5...969.5, room 374.5,
    ///   slack 254.5, offered 283.
    /// The tabs' frame of the first case is the shaped page's in a window never shown. Written after the function was built.
    /// Seen red with the floor added to the slack instead of taken off it, and with 20 more than the floor taken off.
    func testTheOfferIsTheRoomBesideWholeTabsHeldBetweenTheFloorAndTheUsualWidth() {
        expect(Self.offer(), width: 185, slack: 65, fits: true, "Liquid Glass 1060/200, capsule 72")
        expect(Self.offer(tabsWidth: 343), width: 168.5, slack: 48.5, fits: true, "Flat 1060/200, capsule 72")
        expect(Self.offer(actionsWidth: 36), width: 221, slack: 101, fits: true, "Liquid Glass 1060/200, capsule 36")
        expect(Self.offer(tabsWidth: 343, actionsWidth: 36), width: 204.5, slack: 84.5, fits: true, "Flat 1060/200, capsule 36")
        expect(Self.offer(barEnd: 1392, paneWidth: 1196, actionsWidth: 36), width: 283, slack: 271, fits: true, "Liquid Glass 1400/200")
        expect(Self.offer(barEnd: 1392, paneWidth: 1196, tabsWidth: 343, actionsWidth: 36), width: 283, slack: 254.5, fits: true, "Flat 1400/200")
    }

    /// **A slack of exactly 0 fits, and a hundredth under it does not; neither moves the width off the floor.** The
    /// case of the first row (tabs 473...783, 84 beyond them): a search item ending at 987 leaves 987 less 867 =
    /// 120, the floor, so slack 0; 986.99 leaves a slack of -0.01 and 987.01 one of 0.01. The width at the first
    /// is 120 and at the third 120.01. Written after the function was built. Seen red with the floor added to the slack instead of taken off it, and with 20
    /// more than the floor taken off.
    func testASlackOfExactlyNothingFitsAndAHundredthUnderDoesNot() {
        let exact = Self.offer(barEnd: 987)
        XCTAssertEqual(exact.slack, 0, "a room of exactly the floor leaves a slack of \(exact.slack), not 0")
        XCTAssertTrue(exact.wholeTabsFit, "a slack of exactly 0 does not fit")
        XCTAssertEqual(exact.width, 120, accuracy: 0.0001, "a room of exactly the floor offers \(exact.width), not 120")
        expect(Self.offer(barEnd: 986.99), width: 120, slack: -0.01, fits: false, "a hundredth under the floor")
        expect(Self.offer(barEnd: 987.01), width: 120.01, slack: 0.01, fits: true, "a hundredth over the floor")
    }

    /// **The width is never over `searchWidth` and never under `searchFloor`, on either side of each.** The case of
    /// the first row with the item ending at: 937 (room 70, slack -50, offered 120, the floor holds it), 987.5 (slack
    /// 0.5, offered 120.5), 1149.5 (room 282.5, offered 282.5), 1150 (room exactly 283, offered 283), 1150.5 (room
    /// 283.5, slack 163.5, offered 283, the usual width holds it), 5000 (room 4133, slack 4013, offered 283) and
    /// -5000 (room -5867, slack -5987, offered 120). Written after the function was built. Seen red with the floor added to the slack instead of taken off it, and with 20
    /// more than the floor taken off.
    func testTheOffersWidthIsNeverOverTheUsualWidthNorUnderTheFloor() {
        expect(Self.offer(barEnd: 937), width: 120, slack: -50, fits: false, "room 70 under the floor")
        expect(Self.offer(barEnd: 987.5), width: 120.5, slack: 0.5, fits: true, "room 120.5 just over the floor")
        expect(Self.offer(barEnd: 1149.5), width: 282.5, slack: 162.5, fits: true, "room 282.5 just under the usual width")
        expect(Self.offer(barEnd: 1150), width: 283, slack: 163, fits: true, "room exactly the usual width")
        expect(Self.offer(barEnd: 1150.5), width: 283, slack: 163.5, fits: true, "room 283.5 just over the usual width")
        expect(Self.offer(barEnd: 5000), width: 283, slack: 4013, fits: true, "room 4133")
        expect(Self.offer(barEnd: -5000), width: 120, slack: -5987, fits: false, "room -5867")
    }

    /// **A name that holds the tabs right of the card's middle takes the room from the field.** The case of the
    /// first row, the tabs 310 wide, middle start 473: with `tabsEarliest` 500 the tabs stand 500...810, so the room
    /// is 1052 less 810 less 84 = 158 (slack 38, offered 158) against 185 on the middle; at 473.5 they stand
    /// 473.5...783.5 and the room is 184.5 (slack 64.5); at 473 and at 345 the middle holds them, 185. With the item
    /// ending at 987 and the name holding them at 500, the room is 93 (slack -27): the whole tabs do not fit.
    /// Written after the function was built. Seen red with the floor added to the slack instead of taken off it, and with 20
    /// more than the floor taken off.
    func testTheNameHoldingTheTabsRightOfTheMiddleTakesTheRoomFromTheField() {
        expect(Self.offer(tabsEarliest: 500), width: 158, slack: 38, fits: true, "tabs held at 500")
        expect(Self.offer(tabsEarliest: 473.5), width: 184.5, slack: 64.5, fits: true, "tabs held at 473.5")
        expect(Self.offer(tabsEarliest: 473), width: 185, slack: 65, fits: true, "tabs held exactly at the middle's place")
        expect(Self.offer(tabsEarliest: 345), width: 185, slack: 65, fits: true, "a name that holds nothing")
        expect(Self.offer(barEnd: 987, tabsEarliest: 500), width: 120, slack: -27, fits: false, "tabs held at 500 in a bar that fits them on the middle")
    }

    /// **With no actions only the 8 after the tabs is charged, and an actions width that is not over 0 charges no
    /// more.** The case of the first row with no capsule: the room is 1052 less 783 less 8 = 261 (slack 141, offered
    /// 261); a width of -36 reads the same. A capsule 0.5 wide charges 8 and 0.5 and 4: room 256.5. Written after the function was built. Seen red with the floor added to the slack instead of taken off it, and with 20
    /// more than the floor taken off.
    func testNoActionsChargeOnlyTheSpacingAfterTheTabs() {
        expect(Self.offer(actionsWidth: 0), width: 261, slack: 141, fits: true, "no actions")
        expect(Self.offer(actionsWidth: -36), width: 261, slack: 141, fits: true, "an actions width of -36")
        expect(Self.offer(actionsWidth: 0.5), width: 256.5, slack: 136.5, fits: true, "an actions width of 0.5")
    }

    /// **A tabs width below 0 is read as tabs of no width: it offers what a width of 0 offers, never more.** The
    /// item ending at 800, the capsule 36 wide (48 beyond the tabs: 8, 36 and 4). Tabs 0 wide stand at 628...628,
    /// so the room is 800 less 628 less 48 = 124, slack 4, offered 124, the whole tabs fitting. Each negative width
    /// must read the same 124, slack 4, fits. Read as plain arithmetic, tabs -100 wide start at 628 less -50 = 678 and
    /// end at 578, room 800 less 578 less 48 = 174, slack 54, offered 174: roomier than tabs of no width; tabs
    /// -0.01 wide end at 627.995, room 124.005, slack 4.005; the least finite number puts the end at 628 less half
    /// of it, a room that overflows to the slack's upper bound, slack 1 000 000, offered 283. The row exercises
    /// the direction below the bound only: not-a-number and infinity keep their reading, the floor to tabs that do
    /// not fit (`testANotANumberOrInfiniteInputOffersTheFloorToWholeTabsThatDoNotFit`), and a huge positive width
    /// is held by the slack's bound (`testTheSlackIsHeldToTheBoundWhateverOverflows`).
    /// Seen red: before the bound, -100 offered 174 (slack 54), -0.01 offered 124.005 (slack 4.005) and the
    /// least finite number offered 283 (slack 1 000 000), where 0 offers 124 (slack 4); the 0 case was green.
    func testATabsWidthBelowZeroOffersWhatAWidthOfZeroOffers() {
        expect(Self.offer(barEnd: 800, tabsWidth: 0, actionsWidth: 36), width: 124, slack: 4, fits: true, "tabs 0 wide")
        expect(Self.offer(barEnd: 800, tabsWidth: -100, actionsWidth: 36), width: 124, slack: 4, fits: true, "tabs -100 wide")
        expect(Self.offer(barEnd: 800, tabsWidth: -0.01, actionsWidth: 36), width: 124, slack: 4, fits: true, "tabs -0.01 wide")
        expect(Self.offer(barEnd: 800, tabsWidth: -CGFloat.greatestFiniteMagnitude, actionsWidth: 36), width: 124, slack: 4, fits: true,
               "tabs of the least finite width")
    }

    /// **An input that is not a number, or infinite, in any of the six reads a room under the floor: the floor as
    /// the width, a slack of -1 000 000, the tabs not fitting.** Each of not-a-number, positive and negative
    /// infinity in each of `barEnd`, `paneLeading`, `paneWidth`, `tabsWidth`, `tabsEarliest` and `actionsWidth`,
    /// over the case of the first row. Written after the function was built. Seen red with the floor added to the slack instead of
    /// taken off it, and with 20 more than the floor taken off, the second by its ordinary case first (offered 165.0, not 185.0);
    /// no not-a-number or infinite case has been seen red, since no run took out the function's guard for them.
    func testANotANumberOrInfiniteInputOffersTheFloorToWholeTabsThatDoNotFit() {
        let ordinary: [CGFloat] = [1052, 200, 856, 310, 345, 72]
        let names = ["barEnd", "paneLeading", "paneWidth", "tabsWidth", "tabsEarliest", "actionsWidth"]
        expect(Self.offer(), width: 185, slack: 65, fits: true, "the ordinary case the rest are made from")
        for bad: CGFloat in [.nan, .infinity, -.infinity] {
            for index in ordinary.indices {
                var a = ordinary
                a[index] = bad
                let got = Self.offer(barEnd: a[0], paneLeading: a[1], paneWidth: a[2], tabsWidth: a[3], tabsEarliest: a[4], actionsWidth: a[5])
                expect(got, width: 120, slack: -1_000_000, fits: false, "a \(names[index]) of \(bad)")
            }
        }
    }

    /// **The slack is held to -1 000 000...1 000 000, whatever overflows.** The case of the first row: the item
    /// ending at 1 000 987 leaves a slack of exactly 1 000 000 and one ending at 1 001 987 one of 1 001 000, read
    /// 1 000 000 (offered 283 both); at -999 013 the slack is -1 000 000 and at -1 000 013 it is -1 001 000, read
    /// -1 000 000 (offered 120). Finite inputs whose sum overflows to infinity: a pane leading of the largest finite
    /// number and a pane width of the same put the tabs' start at infinity, slack minus infinity, read
    /// -1 000 000; a `tabsEarliest` and a tabs width of the largest finite number likewise; and a bar end of the
    /// largest finite number with a pane leading and a `tabsEarliest` of the least finite number, a pane width and a
    /// tabs width of 0, puts the room at plus infinity, read +1 000 000 and offered 283, the whole tabs fitting. Written after the function was built. Seen red with the floor added to the slack instead of taken off it, and with 20
    /// more than the floor taken off.
    func testTheSlackIsHeldToTheBoundWhateverOverflows() {
        expect(Self.offer(barEnd: 1_000_987), width: 283, slack: 1_000_000, fits: true, "slack exactly the upper bound")
        expect(Self.offer(barEnd: 1_001_987), width: 283, slack: 1_000_000, fits: true, "slack 1 001 000")
        expect(Self.offer(barEnd: -999_013), width: 120, slack: -1_000_000, fits: false, "slack exactly the lower bound")
        expect(Self.offer(barEnd: -1_000_013), width: 120, slack: -1_000_000, fits: false, "slack -1 001 000")
        let most = CGFloat.greatestFiniteMagnitude
        expect(Self.offer(paneLeading: most, paneWidth: most), width: 120, slack: -1_000_000, fits: false, "a start that overflows to infinity")
        expect(Self.offer(tabsWidth: most, tabsEarliest: most), width: 120, slack: -1_000_000, fits: false, "an end that overflows to infinity")
        expect(Self.offer(barEnd: most, paneLeading: -most, paneWidth: 0, tabsWidth: 0, tabsEarliest: -most),
               width: 283, slack: 1_000_000, fits: true, "a room that overflows to plus infinity")
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
