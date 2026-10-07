import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The settings window carries Helm's own page bar and no `NSToolbar`, and says so at every step of a
/// session.** The real window is built and never ordered; the fields are read by `Mirror`, so a field renamed
/// or a bar not held fails by name.
@MainActor
final class TheWindowHasNoToolbarTests: XCTestCase {

    private let noShell = """
        the window has no content view controller of the shell's type: zero assignments were counted on a \
        window nobody built
        """

    func testNoStepEverAssignsAToolbar() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: noShell) else { return }
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

    func testADeclareOnTheWindowsChannelReachesThePageBarAlone() throws {
        guard let rig = SettingsWindowRig.build(
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
        XCTAssertFalse(Mirror(reflecting: rig.owner).children.contains { $0.value is SettingsToolbar },
                       "the window still holds a SettingsToolbar")
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
}
