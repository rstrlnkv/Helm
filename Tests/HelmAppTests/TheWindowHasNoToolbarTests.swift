import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings window's `.pageBar` build carries Helm's own page bar and, as built, no `NSToolbar`, and says so at every step
/// of a session; the one file that may name a toolbar type is the settings toolbar's.** The real window is built
/// and never ordered; the fields are read by `Mirror`, so a field renamed or a bar not held fails by name. The
/// title row reads the window the app builds, which wears the toolbar.
@MainActor
final class TheWindowHasNoToolbarTests: XCTestCase {

    private let noShell = """
        the window has no content view controller of the shell's type: zero assignments were counted on a \
        window nobody built
        """

    func testNoStepEverAssignsAToolbar() throws {
        guard let rig = SettingsWindowRig.buildThePageBarWindow(in: self, failure: noShell) else { return }
        let window = rig.window
        SettingsWindowRig.pump()
        XCTAssertNil(window.toolbar, "the window already wears a toolbar before the first step")

        var assigned = 0
        let kvo = window.observe(\.toolbar, options: [.new]) { _, _ in MainActor.assumeIsolated { assigned += 1 } }
        defer { kvo.invalidate() }

        var ran: [String] = []
        func step(_ name: String, _ body: () -> Void) {
            let before = assigned
            body()
            SettingsWindowRig.pump()
            ran.append(name)
            XCTAssertEqual(assigned - before, 0, "step \(name) assigned the window a toolbar")
            XCTAssertNil(window.toolbar, "step \(name) left a toolbar on the window")
        }
        step("A page change General->A") { rig.open("probe.a", search: true) }
        XCTAssertEqual(rig.model.selection, .module("probe.a"), "the first step never moved the selection")
        step("B page change A->B") { rig.open("probe.b", search: false) }
        step("C page change B->A") { rig.open("probe.a", search: true) }
        step("D tab switch on A") { rig.open("probe.a", search: true, selected: "updates") }
        step("E sidebar fold") { rig.shell.sidebarCollapsed = true }
        XCTAssertTrue(rig.shell.sidebarCollapsed, "the fold step never folded the sidebar")
        step("F page change while folded B") { rig.open("probe.b", search: false) }
        step("G sidebar unfold") { rig.shell.sidebarCollapsed = false }
        XCTAssertFalse(rig.shell.sidebarCollapsed, "the unfold step never unfolded the sidebar")
        step("H fold again") { rig.shell.sidebarCollapsed = true }
        step("I unfold again") { rig.shell.sidebarCollapsed = false }
        XCTAssertEqual(ran.count, 9, "not all nine steps ran")
    }

    /// **Only the settings toolbar's file names a type of AppKit's toolbar family, and only it writes
    /// `window.toolbar`.** Code is read with comments and string insides blanked, so a sentence about the old
    /// shell does not count and a type does. The pattern is wider than `NSToolbar` itself:
    /// `NSSearchToolbarItem` and `NSTrackingSeparatorToolbarItem` do not contain it. Every hit must lie in
    /// `Sources/HelmApp/SettingsToolbar.swift`, and that file must hold at least one, so an allowance for a
    /// file that is gone, or an empty read, fails. Every code line under `Sources` that writes `.toolbar =`
    /// must lie in that file too, and that file must hold at least one: how many it holds is not a rule, it
    /// writes the window's toolbar, takes it off, and sets its own. Before the scan the reads must hold the
    /// settings window's file and the shared toolbar actions' file, so a misplaced read cannot pass as an
    /// absence elsewhere.
    func testOnlyTheSettingsToolbarsFileNamesAnNSToolbarType() throws {
        let owner = "Sources/HelmApp/SettingsToolbar.swift"
        let reads = try SwiftSource.code(under: "Sources")
        let window = reads.first { $0.path == "Sources/HelmApp/SettingsWindow.swift" }
        let actions = reads.first { $0.path == "Sources/HelmUI/DesignSystem/HelmToolbarActions.swift" }
        guard let window, window.text.contains("final class SettingsModel"), actions != nil else {
            XCTFail("no source file was read: the absence below is the absence of the reader")
            return
        }
        let pattern = try NSRegularExpression(pattern: "NS[A-Za-z]*Toolbar[A-Za-z]*")
        var hits: [String] = []
        var inOwner = 0
        var writersInOwner = 0
        var writersOutside: [String] = []
        for read in reads {
            for (index, line) in read.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = String(line)
                let whole = NSRange(text.startIndex..., in: text)
                if let match = pattern.firstMatch(in: text, range: whole), let range = Range(match.range, in: text) {
                    if read.path == owner { inOwner += 1 } else { hits.append("\(read.path):\(index + 1): \(text[range])") }
                }
                if text.range(of: #"\.toolbar\s*=(?!=)"#, options: .regularExpression) != nil {
                    if read.path == owner { writersInOwner += 1 } else { writersOutside.append("\(read.path):\(index + 1)") }
                }
            }
        }
        XCTAssertTrue(hits.isEmpty,
                      "\(hits.count) code lines outside \(owner) name an NSToolbar type:\n" + hits.joined(separator: "\n"))
        XCTAssertGreaterThan(inOwner, 0, "\(owner) names no NSToolbar type, or was not read: the allowance is for nothing")
        XCTAssertTrue(writersOutside.isEmpty,
                      "`.toolbar =` is written on \(writersOutside.count) code lines outside \(owner): \(writersOutside)")
        XCTAssertGreaterThan(writersInOwner, 0, "\(owner) writes no `.toolbar =`, or was not read: the allowance is for nothing")
    }

    func testADeclareOnTheWindowsChannelReachesThePageBarAlone() throws {
        guard let rig = SettingsWindowRig.buildThePageBarWindow(
            in: self, failure: "SettingsWindow holds no page bar: a declare was counted on a channel nobody reads")
        else { return }
        guard let bar = rig.pageBar else {
            XCTFail("SettingsWindow holds no page bar: a declare was counted on a channel nobody reads")
            return
        }
        SettingsWindowRig.pump()
        rig.open("probe.a", search: true)
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump()

        XCTAssertEqual(rig.model.selection, .module("probe.a"), "the selection never moved: nothing was declared for")
        XCTAssertEqual(bar.presentation, .page(key: "probe.a", isLive: true, isDimmed: false),
                       "the bar did not take the page the window's channel was told about")
        XCTAssertNil(rig.window.toolbar, "the window wears a toolbar beside the bar")
        let snapshot = bar.snapshot
        XCTAssertNotNil(snapshot, "the bar drew nothing: its snapshot is empty")
        XCTAssertEqual(snapshot?.appearsActive, false,
                       "the window never told the bar it is not active: setWindowAppearsActive did not run before a show")

        let segmented = bar.view.everyView(ofType: NSSegmentedControl.self)
        XCTAssertFalse(segmented.isEmpty, "no tab switcher is mounted under the bar for a page that declared tabs")
        XCTAssertNotNil(bar.view.menu, "the bar view has no menu to hand the tabs")
        for control in segmented {
            XCTAssertTrue(control.menu === bar.view.menu, "a tab switcher does not carry the bar's one menu")
        }
    }

    func testTheWindowsTitleIsNeverVisibleInEitherPageBarStyle() throws {
        let stored = AppSettings.pageBarStyle
        addTeardownBlock { await MainActor.run { AppSettings.pageBarStyle = stored } }
        guard let rig = SettingsWindowRig.build(in: self, failure: noShell) else { return }
        for style in [PageBarStyle.moduleName, .windowTitle] {
            AppSettings.pageBarStyle = style
            XCTAssertEqual(AppSettings.pageBarStyle, style, "the style was not stored")
            SettingsWindowRig.pump(0.2)
            // The title watch is synchronous: read before the pane's own preference can overwrite the title.
            rig.model.pageTitle = HelmPageTitle(title: "Title \(style.rawValue)", subtitle: "sub")
            XCTAssertEqual(rig.window.title, "Title \(style.rawValue)", "the title watch never ran for \(style)")
            XCTAssertEqual(rig.window.titleVisibility, .hidden, "the window's title is drawn under \(style)")
            SettingsWindowRig.pump(0.2)
            XCTAssertEqual(rig.window.titleVisibility, .hidden, "the window's title is drawn under \(style) after a turn")
        }
    }

    /// **A press 20 pt from the window's top, where the titlebar's strip lies over the bar, answers what
    /// the bar draws there.** The frame view's `hitTest` is asked, the x of each zone is the middle of the
    /// bar's own frame for it. Each control answers a view inside the bar that lies over its zone; the tabs'
    /// view cannot move the window, the name and a gap answer the bar itself, which can. The actions' and the
    /// search's hit views answer true for `mouseDownCanMoveWindow`, and this row does not say whether a press
    /// there moves the window. That a real press is delivered where `hitTest` says is not stated here.
    /// The answer's class and its flag are printed for every point (`PRESSUNDERSTRIP`).
    func testAPressOnAControlUnderTheTitlebarsStripAnswersTheControl() throws {
        guard let rig = SettingsWindowRig.buildThePageBarWindow(in: self, failure: noShell) else { return }
        guard let frameView = rig.window.contentView?.superview else {
            XCTFail("the window has no frame view: nothing was pressed")
            return
        }
        guard let bar = rig.pageBar?.view else {
            XCTFail("SettingsWindow holds no page bar: nothing was pressed")
            return
        }
        rig.open("probe.a", search: true)
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump()
        rig.window.contentView?.layoutSubtreeIfNeeded()
        guard let frames = bar.frames else {
            XCTFail("the bar has no frames: nothing was pressed")
            return
        }
        let fromTop: CGFloat = 20
        let windowHeight = rig.window.frame.height
        let strip = frameView.bounds.height - rig.window.contentLayoutRect.height
        XCTAssertTrue(strip > fromTop, "the titlebar's strip is \(strip) pt tall, not over the point \(fromTop) pt from the top")
        /// The middle x of a bar-coordinate frame, in window coordinates, and the point at `fromTop`.
        func point(atBarX x: CGFloat) -> NSPoint {
            let inWindow = bar.convert(NSPoint(x: x, y: 0), to: nil)
            return NSPoint(x: inWindow.x, y: windowHeight - fromTop)
        }
        let zones: [(String, CGRect)] = [("tabs", frames.tabs), ("actions", frames.actions), ("search", frames.search)]
        var pressed = 0
        for (zone, frame) in zones {
            guard !frame.isNull, !frame.isEmpty else {
                XCTFail("the bar has no \(zone) view on this page (frame \(frame)): nothing was pressed")
                continue
            }
            let at = point(atBarX: frame.midX)
            guard let hit = frameView.hitTest(at) else {
                XCTFail("\(zone) at x \(at.x), \(fromTop) from the top: the frame view answered nil")
                continue
            }
            pressed += 1
            let name = String(describing: type(of: hit))
            print("PRESSUNDERSTRIP \(zone) x \(at.x) y \(fromTop) -> \(name) canMove \(hit.mouseDownCanMoveWindow)")
            XCTAssertTrue(hit !== bar && hit.isDescendant(of: bar),
                          "\(zone) at x \(at.x), \(fromTop) from the top answered \(name), not a view inside the bar")
            if zone == "tabs" {
                XCTAssertFalse(hit.mouseDownCanMoveWindow,
                               "\(zone) at x \(at.x), \(fromTop) from the top answered \(name), which moves the window")
            }
            if hit !== bar, hit.isDescendant(of: bar) {
                XCTAssertTrue(hit.convert(hit.bounds, to: bar).intersects(frame),
                              "\(zone) at x \(at.x) answered \(name), which does not lie over the zone's frame \(frame)")
            }
        }
        // The name, and the first gap between two zones that holds some width.
        var handles: [(String, CGFloat)] = []
        if frames.name.isNull || frames.name.isEmpty {
            XCTFail("the bar has no name frame (\(frames.name)): nothing was pressed")
        } else {
            handles.append(("name", frames.name.midX))
        }
        let ordered = ([("name", frames.name)] + zones).filter { !$0.1.isNull && !$0.1.isEmpty }.sorted { $0.1.minX < $1.1.minX }
        var gap: CGFloat?
        for (a, b) in zip(ordered, ordered.dropFirst()) where b.1.minX - a.1.maxX >= 2 {
            gap = (a.1.maxX + b.1.minX) / 2
            break
        }
        if let gap { handles.append(("gap", gap)) } else {
            XCTFail("no gap between the bar's zones on this page: nothing was pressed in a gap (frames \(ordered.map { $0.1 }))")
        }
        for (zone, x) in handles {
            let at = point(atBarX: x)
            guard let hit = frameView.hitTest(at) else {
                XCTFail("\(zone) at x \(at.x), \(fromTop) from the top: the frame view answered nil")
                continue
            }
            pressed += 1
            let name = String(describing: type(of: hit))
            print("PRESSUNDERSTRIP \(zone) x \(at.x) y \(fromTop) -> \(name) canMove \(hit.mouseDownCanMoveWindow)")
            XCTAssertTrue(hit === bar, "\(zone) at x \(at.x), \(fromTop) from the top answered \(name), not the bar itself")
            XCTAssertTrue(hit.mouseDownCanMoveWindow, "\(zone) at x \(at.x) answered \(name), which cannot move the window")
        }
        XCTAssertEqual(pressed, 5, "\(pressed) of 5 points were pressed: the row did not measure what it names")
    }
}
