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
    /// says (an unshown window never reads them again) and the name's view is held off its item's edge by the
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

    /// Where an unshown window's toolbar starts its items: the seed (`SettingsToolbar.itemsStartSeed`), which a
    /// window nobody ordered never reads again. Spelled as a number here, not read from the declaration, so a
    /// seed that moved turns the rows below red by their own precondition.
    private static let itemsStart: CGFloat = 92.5

    /// The distance the name keeps from the pane's leading edge.
    private static let nameGap: CGFloat = 16

    /// The inset the name's view is held off the item's leading edge by when the pane starts at `leading`.
    private static func inset(forPaneLeading leading: CGFloat) -> CGFloat {
        max(0, leading + nameGap - itemsStart)
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
    /// frame view is laid out first, then the host's frame is read. Not seen red: no run read the frame without that layout.
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
    /// it, or where the toolbar's items start when that is further right, within a point.** The reading is
    /// the hosting view's left edge in window x, a frame: the frame view is laid out first (`nameStart`), and no
    /// run read the frame without that layout. The band between 76.5 and 112.5 is where the
    /// inset is above zero and below 36 pt; the row requires three readings there. Before the readings every
    /// width must have given one.
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
                    let want = max(edge + Self.nameGap, owner.itemsStart)
                    guard let got = nameStart(rig) else {
                        off.append("pane \(edge): the name has no frame")
                        return
                    }
                    reads += 1
                    if edge > 76.5, edge < 112.5 { inBand += 1 }
                    if abs(got - want) > 1 { off.append("pane \(edge): name at \(got), want \(want)") }
                }
            }
            XCTAssertEqual(reads, 24, "\(label): the name was read \(reads) times of 24: \(off)")
            XCTAssertGreaterThanOrEqual(inBand, 3, "\(label): the band between 76.5 and 112.5 was read \(inBand) times")
            XCTAssertTrue(off.isEmpty, "\(label): the name is off the pane's edge at \(off.count) of \(reads) widths: \(off)")
        }
    }

    /// **At every width of the fold the name's inset is the pane's edge plus sixteen less where the items
    /// start, and never below zero.** The same walk as above, read as the constant the name item holds and not
    /// as a frame, so what AppKit makes of an item narrower than its viewer does not enter. The seed this
    /// stands on is asserted before the readings.
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
                    let want = Self.inset(forPaneLeading: edge)
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
    /// container that holds no inset reads as a failure and not as an agreement.
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
            XCTAssertEqual(beyond, Self.inset(forPaneLeading: width), accuracy: 0.5,
                           "at \(width) the name item is \(beyond) wider than its hosting view, not the inset \(Self.inset(forPaneLeading: width))")
        }
        XCTAssertEqual(reads, 3, "the name item was read \(reads) times of 3")
    }

    /// **The tabs fold against the name's own width and not against the inset the item holds it off the edge by.**
    /// A page declares tabs and nothing else, so the toolbar has no actions item to anchor on and the prediction
    /// falls back to the room the pane offers less the name's, the tabs' and the search's widths. At a pane 40
    /// wider than the name and the full tabs need the tabs stay full (an inset charged to the name, 123.5 at
    /// 200, would fold them); at a pane 40 narrower they fold (so the first reading is the fold's own decision and
    /// not a bar that never folds). Folded is one segment shown, full is one per tab. The window's least width
    /// holds the pane at no less than the card gets there, which the row reads and prints.
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
        let roomy = pane(of: need + 40)
        XCTAssertEqual(roomy, need + 40, accuracy: 1, "the pane stands at \(roomy), not \(need + 40): the window's least width does not let the row reach it (name \(host.frame.width) + tabs \(control.frame.width))")
        XCTAssertEqual(tabsControl(rig)?.segmentCount, tabs.count,
                       "with 40 to spare beyond the name and the tabs the tabs are folded to \(tabsControl(rig)?.segmentCount ?? -1) segments: the inset was charged to the name")
        let short = pane(of: need - 40)
        XCTAssertEqual(short, need - 40, accuracy: 1, "the pane stands at \(short), not \(need - 40): the window's least width does not let the row reach it")
        XCTAssertEqual(tabsControl(rig)?.segmentCount, 1,
                       "with 40 too little the tabs are \(tabsControl(rig)?.segmentCount ?? -1) segments, not folded: the row never saw the fold decide")
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
