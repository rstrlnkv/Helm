import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **The tabs toolbar's owner puts AppKit's segmented control where it is told, assigns the window's toolbar
/// only when asked, and leaves every press that is not on the control to the content under the strip.**
/// A real `NSWindow` with the settings window's style mask; a transparent title bar, a hidden title, a plain
/// content view holding probe subviews; never ordered and never key; no page, no layout and no look are
/// involved, so the class stands for the owner alone.
///
/// What an unshown window cannot say, and this class does not: that a real press, a drag, a double click or
/// the context menu is delivered where `hitTest` answers; that the hidden lead viewer stays hidden across
/// key changes; anything drawn.
@MainActor
final class TheTabsToolbarStandsItsControlWhereItIsToldTests: XCTestCase {

    /// A view that stands for the content under the strip; it answers its own hit test as any view does.
    private final class Probe: NSView {}

    private struct Bench {
        let window: NSWindow
        let frameView: NSView
        let content: NSView
        let left: Probe
        let right: Probe
        let tabs: ShellTabsToolbar
    }

    private static let titles = ["Installed", "Updates", "Leftovers"]

    private func fill(_ tabs: ShellTabsToolbar, titles: [String] = titles) {
        tabs.control.segmentCount = titles.count
        for (index, title) in titles.enumerated() { tabs.control.setLabel(title, forSegment: index) }
        tabs.control.selectedSegment = 0
    }

    /// The window, its content and the owner. `attached` and `worn` choose how far the owner is taken.
    private func bench(attached: Bool = true, worn: Bool = true) -> Bench {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let left = Probe(frame: NSRect(x: 100, y: 0, width: 300, height: 600))
        let right = Probe(frame: NSRect(x: 700, y: 0, width: 280, height: 600))
        for probe in [left, right] {
            probe.autoresizingMask = [.height]
            content.addSubview(probe)
        }
        window.contentView = content
        addTeardownBlock { await MainActor.run { window.close() } }
        let tabs = ShellTabsToolbar()
        fill(tabs)
        if attached { tabs.attach(to: window) }
        if worn { tabs.wear(true) }
        let frameView = content.superview ?? content
        let bench = Bench(window: window, frameView: frameView, content: content, left: left, right: right, tabs: tabs)
        settle(bench)
        return bench
    }

    private func settle(_ bench: Bench) {
        bench.frameView.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(0.05)
        bench.frameView.layoutSubtreeIfNeeded()
    }

    private func place(_ bench: Bench, _ x: CGFloat?) {
        bench.tabs.place(minX: x)
        settle(bench)
    }

    private func identifiers(_ window: NSWindow) -> [String] {
        window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? []
    }

    /// The tabs item of the window's toolbar, by identifier.
    private func tabsItem(_ window: NSWindow) -> NSToolbarItem? {
        window.toolbar?.items.first { $0.itemIdentifier.rawValue == "tabs" }
    }

    /// The strip the toolbar adds: the frame view's height less the content layout rect's.
    private func strip(_ bench: Bench) -> CGFloat {
        bench.frameView.bounds.height - bench.window.contentLayoutRect.height
    }

    // MARK: - the assignment

    /// **`wear` assigns once for each change and nothing when equal; off leaves no toolbar.** The count the
    /// owner keeps is checked against a key-value observer of `window.toolbar`, which fires on every
    /// assignment of any value, so a counter that lies in either direction is caught.
    func testWearAssignsOnceForEachChangeAndNothingWhenEqual() {
        let bench = bench(worn: false)
        var observed = 0
        let kvo = bench.window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { observed += 1 } }
        defer { kvo.invalidate() }
        XCTAssertNil(bench.window.toolbar, "the window wears a toolbar before anything was asked")
        XCTAssertEqual(bench.tabs.assignments, 0)

        func step(_ name: String, _ on: Bool, assigned: Int, wearing: Bool) {
            bench.tabs.wear(on)
            settle(bench)
            XCTAssertEqual(bench.tabs.assignments, assigned, "\(name): the owner's count")
            XCTAssertEqual(observed, assigned, "\(name): the window was assigned a toolbar \(observed) times, not \(assigned)")
            XCTAssertEqual(bench.window.toolbar != nil, wearing, "\(name): the window's toolbar")
        }
        step("off when never worn", false, assigned: 0, wearing: false)
        step("on", true, assigned: 1, wearing: true)
        step("on again", true, assigned: 1, wearing: true)
        step("off", false, assigned: 2, wearing: false)
        step("off again", false, assigned: 2, wearing: false)
        step("on a second time", true, assigned: 3, wearing: true)
        let first = bench.window.toolbar
        XCTAssertNotNil(first, "the toolbar worn the second time is nil")
        bench.tabs.wear(false)
        bench.tabs.wear(true)
        XCTAssertTrue(bench.window.toolbar === first, "off then on built another toolbar object")
    }

    /// **A `wear` asked before the window exists is remembered and applied by `attach`.**
    func testAWearAskedBeforeTheWindowExistsIsAppliedWhenItIsAttached() {
        let bench = bench(attached: false, worn: false)
        bench.tabs.wear(true)
        XCTAssertNil(bench.window.toolbar, "the toolbar reached a window the owner was never attached to")
        XCTAssertEqual(bench.tabs.assignments, 0, "an assignment was counted with no window")
        bench.tabs.attach(to: bench.window)
        settle(bench)
        XCTAssertNotNil(bench.window.toolbar, "attach did not apply the wear asked before it")
        XCTAssertEqual(bench.tabs.assignments, 1)
    }

    /// **With the toolbar off the window has none; with it on the items are exactly `lead` and `tabs`.**
    /// No flexible space and nothing else: a space's viewer would swallow every press right of the tabs.
    func testTheItemsAreExactlyLeadAndTabsAndOffLeavesNoToolbar() {
        let bench = bench()
        XCTAssertEqual(identifiers(bench.window), ["lead", "tabs"])
        bench.tabs.wear(false)
        settle(bench)
        XCTAssertNil(bench.window.toolbar, "wear(false) left a toolbar on the window")
        XCTAssertEqual(identifiers(bench.window), [], "the items of a window with no toolbar")
    }

    // MARK: - where the control stands

    /// **After `place(minX:)` and a layout the control's left edge in the window is the asked x rounded down,
    /// to within one point.** The toolbar snaps its items to whole points while the asked x carries quarter
    /// points: the owner rounds down, so the edge differs from the asked x by under a point, a rounding and
    /// not a lag. One point is that rounding's room and no more. The
    /// positions are far apart, so a control that never moved cannot pass; the fractions include each
    /// quarter.
    func testPlaceStandsTheControlAtTheAskedXRoundedDownWithinOnePoint() {
        let bench = bench()
        var seen: [CGFloat] = []
        for x in [CGFloat(200), 300.25, 450.5, 600.75, 560, 233.75, 410] {
            place(bench, x)
            let frame = bench.tabs.controlFrameInWindow
            XCTAssertFalse(frame.isNull || frame.isEmpty, "x \(x): the control is in no window or has no size: \(frame)")
            XCTAssertEqual(frame.minX, x.rounded(.down), accuracy: 1,
                           "x \(x): the control's left edge is \(frame.minX)")
            seen.append(frame.minX)
        }
        XCTAssertGreaterThan((seen.max() ?? 0) - (seen.min() ?? 0), 300,
                             "the control hardly moved across seven positions \(seen): the row compared one place with itself")
    }

    /// **The constant the owner writes is never below 1, whatever x is asked.** Zero lays nothing out (the
    /// toolbar kept the tabs stale), so an x left of the floor, left of the window and not a number all give
    /// a finite constant of at least 1, and the toolbar still has the control in the window.
    func testTheLeadConstantIsNeverBelowOneWhateverXIsAsked() {
        let bench = bench()
        var constants: [CGFloat] = []
        for x in [CGFloat(10), 0, 92, 96, -50, -.infinity, .nan, 97, 98.5, 300] {
            place(bench, x)
            let constant = bench.tabs.leadConstant
            constants.append(constant)
            XCTAssertTrue(constant.isFinite, "x \(x): the lead constant is \(constant)")
            XCTAssertGreaterThanOrEqual(constant, 1, "x \(x): the lead constant is \(constant)")
        }
        place(bench, 300)
        XCTAssertGreaterThan(bench.tabs.leadConstant, 150, "the constant for x 300 is \(bench.tabs.leadConstant): it does not follow x")
        XCTAssertFalse(bench.tabs.controlFrameInWindow.isNull, "after the floor was asked the control left the window")
        XCTAssertEqual(Set(constants.prefix(5)).count, 1,
                       "x left of the floor gave \(constants.prefix(5)): they should all be the floor")
    }

    /// **`place(minX: nil)` hides the tabs item and the strip stays; a number shows it again.**
    func testPlaceNilHidesTheTabsItemAndKeepsTheStrip() {
        let bench = bench()
        place(bench, 400)
        let before = strip(bench)
        XCTAssertGreaterThan(before, 40, "the strip is \(before) pt: the toolbar's bar is not there to keep")
        XCTAssertEqual(tabsItem(bench.window)?.isHidden, false)

        place(bench, nil)
        XCTAssertEqual(tabsItem(bench.window)?.isHidden, true, "the tabs item is shown after place(minX: nil)")
        XCTAssertTrue(bench.tabs.controlFrameInWindow.isNull, "the control is in the window after place(minX: nil)")
        XCTAssertEqual(strip(bench), before, accuracy: 0.5, "the strip changed with the tabs hidden")
        XCTAssertGreaterThanOrEqual(bench.tabs.leadConstant, 1, "the lead constant after place(minX: nil)")
        XCTAssertNotNil(bench.window.toolbar, "place(minX: nil) took the toolbar off")

        place(bench, 400)
        XCTAssertEqual(tabsItem(bench.window)?.isHidden, false, "a number did not show the item again")
        XCTAssertEqual(bench.tabs.controlFrameInWindow.minX, 400, accuracy: 1)
    }

    /// **The tabs item is among the toolbar's visible items.** At the window's own width and at a narrow one
    /// where the control still fits, the item has not gone to the overflow.
    func testTheTabsItemIsAmongTheVisibleItems() {
        let bench = bench()
        for (width, x) in [(CGFloat(1000), CGFloat(400)), (700, 300)] {
            bench.window.setContentSize(NSSize(width: width, height: 560))
            place(bench, x)
            guard let visible = bench.window.toolbar?.visibleItems else {
                XCTFail("width \(width): the toolbar reports no visible items")
                continue
            }
            XCTAssertTrue(visible.contains { $0.itemIdentifier.rawValue == "tabs" },
                          "width \(width): the visible items are \(visible.map { $0.itemIdentifier.rawValue })")
        }
    }

    /// **While nothing is worn the fitting width is 0; worn and in the window it is the control's.**
    func testFittingWidthIsZeroWhileNotWorn() {
        let loose = ShellTabsToolbar()
        fill(loose)
        XCTAssertEqual(loose.fittingWidth, 0, "an owner with no window")
        loose.wear(true)
        XCTAssertEqual(loose.fittingWidth, 0, "worn with no window to wear it in")

        let bench = bench(worn: false)
        XCTAssertEqual(bench.tabs.fittingWidth, 0, "attached and not worn")
        bench.tabs.wear(true)
        place(bench, 400)
        XCTAssertGreaterThan(bench.tabs.fittingWidth, 50, "worn and in the window: the fitting width is \(bench.tabs.fittingWidth)")
        bench.tabs.wear(false)
        settle(bench)
        XCTAssertEqual(bench.tabs.fittingWidth, 0, "worn off again")
    }

    // MARK: - the lead

    /// **The lead is released after a `place`, after a window resize, and after off then on.** The reading is
    /// false while nothing is worn, so a reading stuck on true fails there.
    func testTheLeadIsReleasedAfterAPlaceAResizeAndAnOffThenOn() {
        let bench = bench(worn: false)
        XCTAssertFalse(bench.tabs.leadIsReleased, "released with nothing worn")
        bench.tabs.wear(true)
        place(bench, 400)
        XCTAssertTrue(bench.tabs.leadIsReleased, "not released after a place")

        for size in [NSSize(width: 900, height: 560), NSSize(width: 1100, height: 640)] {
            bench.window.setContentSize(size)
            settle(bench)
            XCTAssertTrue(bench.tabs.leadIsReleased, "not released after a resize to \(size), before the next place")
            place(bench, 400)
            XCTAssertTrue(bench.tabs.leadIsReleased, "not released after a place at \(size)")
        }

        bench.tabs.wear(false)
        settle(bench)
        XCTAssertFalse(bench.tabs.leadIsReleased, "released with the toolbar off")
        bench.tabs.wear(true)
        settle(bench)
        XCTAssertTrue(bench.tabs.leadIsReleased, "not released after off then on, before the next place")
        place(bench, 400)
        XCTAssertTrue(bench.tabs.leadIsReleased, "not released after off then on and a place")
    }

    // MARK: - presses

    /// **A press under the strip answers the content where it is not on the control, and the control where it
    /// is.** The frame view's `hitTest` is asked, 20 pt from the window's top, inside the strip. This is the
    /// row that fails if the lead's viewer, or any item viewer of the toolbar, ever swallows a press: it is
    /// `hitTest` and not delivery, so that a real press, a drag or a double click reaches the same view is
    /// not stated here. The probes are sized from the control's frame after the place, one left of it and one
    /// right of it.
    func testAPointUnderTheStripLeftAndRightOfTheTabsAnswersTheContentAndOnTheTabsTheControl() {
        let bench = bench()
        for x in [CGFloat(420), 330.5] {
            place(bench, x)
            let control = bench.tabs.controlFrameInWindow
            XCTAssertFalse(control.isNull || control.isEmpty, "x \(x): the control is not in the window: nothing was pressed")
            XCTAssertLessThan(control.maxX + 60, 980, "x \(x): the control leaves no room for the right probe")
            bench.left.frame = NSRect(x: 100, y: 0, width: control.minX - 100, height: bench.content.bounds.height)
            bench.right.frame = NSRect(x: control.maxX, y: 0, width: 990 - control.maxX, height: bench.content.bounds.height)
            settle(bench)
            let y = bench.frameView.bounds.height - 20
            XCTAssertGreaterThan(strip(bench), 20, "the strip is not over the point 20 pt from the top")

            var pressed = 0
            func press(_ name: String, _ px: CGFloat, _ check: (NSView) -> Bool, _ expected: String) {
                guard let hit = bench.frameView.hitTest(NSPoint(x: px, y: y)) else {
                    XCTFail("x \(x), \(name) at \(px): the frame view answered nil")
                    return
                }
                pressed += 1
                XCTAssertTrue(check(hit), "x \(x), \(name) at \(px) answered \(type(of: hit)), not \(expected)")
            }
            press("far left of the tabs", 130, { $0 === bench.left }, "the left probe")
            press("just left of the tabs", control.minX - 8, { $0 === bench.left }, "the left probe")
            press("just right of the tabs", control.maxX + 8, { $0 === bench.right }, "the right probe")
            press("far right of the tabs", 960, { $0 === bench.right }, "the right probe")
            press("on the tabs", control.midX, { $0 === bench.tabs.control || $0.isDescendant(of: bench.tabs.control) }, "the control")
            XCTAssertEqual(pressed, 5, "x \(x): \(pressed) of 5 points were pressed")
        }
    }

    /// **The same points answer the same after a resize, after place(nil) and a number, and after off then on.**
    func testThePointsAnswerTheSameAfterAResizeAndAfterOffThenOn() {
        let bench = bench()
        func probe(_ when: String) {
            place(bench, 420)
            let control = bench.tabs.controlFrameInWindow
            XCTAssertFalse(control.isNull || control.isEmpty, "\(when): the control is not in the window")
            bench.left.frame = NSRect(x: 100, y: 0, width: control.minX - 100, height: bench.content.bounds.height)
            bench.right.frame = NSRect(x: control.maxX, y: 0, width: 990 - control.maxX, height: bench.content.bounds.height)
            settle(bench)
            let y = bench.frameView.bounds.height - 20
            XCTAssertTrue(bench.frameView.hitTest(NSPoint(x: control.minX - 8, y: y)) === bench.left,
                          "\(when): left of the tabs answers another view than the content's probe")
            XCTAssertTrue(bench.frameView.hitTest(NSPoint(x: control.maxX + 8, y: y)) === bench.right,
                          "\(when): right of the tabs answers another view than the content's probe")
        }
        probe("at the start")
        bench.window.setContentSize(NSSize(width: 1040, height: 560))
        probe("after a resize")
        bench.tabs.place(minX: nil)
        probe("after place(nil) and a number")
        bench.tabs.wear(false)
        bench.tabs.wear(true)
        settle(bench)
        probe("after off then on")
    }

    // MARK: - the action

    /// **The control's action calls `onPick` once with the index; a selection written from code, a label, a
    /// place or a wear call nothing.**
    func testTheControlsActionCallsOnPickOnceAndCodeCallsNothing() {
        let bench = bench()
        var picks: [Int] = []
        bench.tabs.onPick = { picks.append($0) }

        bench.tabs.control.selectedSegment = 1
        bench.tabs.control.selectedSegment = 2
        bench.tabs.control.setLabel("Renamed", forSegment: 0)
        bench.tabs.control.segmentCount = 3
        place(bench, 400)
        place(bench, nil)
        place(bench, 400)
        bench.tabs.wear(false)
        bench.tabs.wear(true)
        settle(bench)
        XCTAssertEqual(picks, [], "code called onPick: \(picks)")

        guard let action = bench.tabs.control.action else {
            XCTFail("the control has no action: nothing was pressed")
            return
        }
        bench.tabs.control.selectedSegment = 2
        XCTAssertTrue(bench.tabs.control.sendAction(action, to: bench.tabs.control.target),
                      "the action was not delivered to a target")
        XCTAssertEqual(picks, [2], "one press of segment 2 called onPick with \(picks)")
        bench.tabs.control.selectedSegment = 0
        XCTAssertTrue(bench.tabs.control.sendAction(action, to: bench.tabs.control.target))
        XCTAssertEqual(picks, [2, 0], "a second press called onPick with \(picks)")
    }

    // MARK: - no private selector

    /// What the scan looks for in code, strings kept: the four spellings of a call AppKit does not publish.
    private static func privateCalls(in text: String) -> [String] {
        ["NSSelectorFromString", "perform(", "value(forKey", "\"_"].filter { text.contains($0) }
    }

    /// **The owner's file builds no selector from a name, performs none, reads no key by name and names no
    /// string that starts with an underscore.** Comments are blanked, string literals kept. Total failure:
    /// the file must exist and be non-empty, name `NSToolbar`, and the scan is first shown to find each
    /// spelling in a text that holds all four.
    func testTheTabsToolbarsFileReachesForNoPrivateSelector() throws {
        let seeded = """
            let a = NSSelectorFromString("x"); object.perform(sel); object.value(forKey: "k"); let b = "_private"
            """
        XCTAssertEqual(Self.privateCalls(in: seeded).count, 4, "the scan misses one of its four subjects")
        XCTAssertEqual(Self.privateCalls(in: SwiftSource.uncommented(seeded)).count, 4,
                       "the reader blanks a string literal the scan needs")

        let reads = try SwiftSource.uncommented(under: "Sources")
        guard let owner = reads.first(where: { $0.path == "Sources/HelmApp/ShellTabsToolbar.swift" }) else {
            XCTFail("Sources/HelmApp/ShellTabsToolbar.swift was not read: the absence below is the absence of the file")
            return
        }
        XCTAssertGreaterThan(owner.text.count, 500, "the file was read nearly empty (\(owner.text.count) characters)")
        XCTAssertTrue(owner.text.contains("NSToolbar"), "the file does not name NSToolbar: it is not the toolbar's owner")
        XCTAssertEqual(Self.privateCalls(in: owner.text), [], "the file reaches for a selector AppKit does not publish")
    }
}
