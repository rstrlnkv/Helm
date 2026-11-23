import AppKit
import HelmUI
import XCTest
@testable import HelmApp

/// **Under Liquid Glass the settings window's page tabs are a system toolbar item (`SettingsToolbar`); under Flat
/// there is no toolbar; the window's three buttons stand at one place under both.** Driven on an offscreen window
/// and the sink the pane gets, with no screen.
@MainActor
final class ThePageTabsAreTheToolbarsUnderGlassTests: XCTestCase {

    private func tabs(_ ids: [String], attention: String? = nil) -> [HelmToolbarTab] {
        ids.map { HelmToolbarTab(id: $0, title: "Tab " + $0, symbol: "circle", needsAttention: $0 == attention,
                                 attentionNote: $0 == attention ? "Look" : nil) }
    }

    private func declaration(_ ids: [String], selected: String = "a", attention: String? = nil,
                             picked: @escaping (String) -> Void = { _ in }) -> HelmTabsDeclaration {
        HelmTabsDeclaration(tabs: tabs(ids, attention: attention), selected: selected, enabled: true,
                            style: .text, increasedContrast: false, select: picked)
    }

    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
                 styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
    }

    func testTheWidthsAreEachWordsOwnAndSumToTheStrip() {
        let widths = HelmTabsMetrics.widths(tabs(["a", "b"]), .text)
        XCTAssertEqual(widths.count, 2)
        XCTAssertTrue(widths.allSatisfy { $0 > 24 })
        XCTAssertEqual(HelmTabsMetrics.widths(tabs(["a", "b", "c"]), .icons), [38, 38, 38])
    }

    func testTheStripFollowsEachDeclarationInCountLabelsDotsAndHiding() {
        let toolbar = SettingsToolbar()
        toolbar.attach(to: window()) { .liquidGlass }
        let owner = UUID()
        let strip = toolbar.stripForTesting

        toolbar.sink.declare(owner, declaration(["a", "b", "c"], attention: "b"))
        XCTAssertEqual(strip.segmentCountForTesting, 3)
        XCTAssertEqual((0..<3).map { strip.labelForTesting($0) }, ["Tab a", "Tab b", "Tab c"])
        XCTAssertEqual((0..<3).map { strip.hasDotForTesting($0) }, [false, true, false])
        XCTAssertEqual(strip.selectedSegmentForTesting, 0)

        toolbar.sink.declare(owner, declaration(["a", "b"], selected: "b"))
        XCTAssertEqual(strip.segmentCountForTesting, 2)
        XCTAssertEqual((0..<2).map { strip.hasDotForTesting($0) }, [false, false])
        XCTAssertEqual(strip.selectedSegmentForTesting, 1)

        toolbar.sink.declare(owner, nil)
        XCTAssertTrue(toolbar.tabsItemIsHiddenForTesting)
    }

    func testTheToolbarIsWornUnderGlassAndOffUnderFlat() {
        let window = window()
        var look = HelmBarAppearance.flat
        let toolbar = SettingsToolbar()
        toolbar.attach(to: window) { look }
        XCTAssertNil(window.toolbar)
        look = .liquidGlass
        NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
        XCTAssertNotNil(window.toolbar)
        XCTAssertTrue(toolbar.isInstalledForTesting)
        look = .flat
        NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
        XCTAssertNil(window.toolbar)
    }

    func testALateCallOfAnOldRowTouchesNothingOfTheNewOne() {
        let toolbar = SettingsToolbar()
        toolbar.attach(to: window()) { .liquidGlass }
        let old = UUID(), new = UUID()
        var pressed: [String] = []
        toolbar.sink.declare(old, declaration(["a"]))
        toolbar.sink.declare(new, declaration(["a", "b"]) { pressed.append($0) })
        toolbar.sink.place(new, CGRect(x: 300, y: 12, width: 200, height: 36))
        // The old row, rebuilt by a change of language, speaks late: each kind of call.
        toolbar.sink.place(old, nil)
        toolbar.sink.declare(old, declaration(["z"]) { _ in XCTFail("the old row's press") })
        toolbar.sink.release(old)
        let strip = toolbar.stripForTesting
        XCTAssertEqual(strip.segmentCountForTesting, 2)
        XCTAssertFalse(toolbar.tabsItemIsHiddenForTesting)
        strip.onPick(1)
        XCTAssertEqual(pressed, ["b"])
        toolbar.sink.release(new)
        XCTAssertTrue(toolbar.tabsItemIsHiddenForTesting)
    }

    func testASegmentWithADotIsWiderByTheDotAndItsGapAndTheDotsDimWithTheControl() {
        let plain = HelmTabsMetrics.widths(tabs(["a", "b"]), .text)
        let dotted = HelmTabsMetrics.widths(tabs(["a", "b"], attention: "b"), .text)
        XCTAssertEqual(dotted[0], plain[0])
        XCTAssertEqual(dotted[1] - plain[1], HelmTabsMetrics.dot + HelmTabsMetrics.dotGap)
        let toolbar = SettingsToolbar()
        toolbar.attach(to: window()) { .liquidGlass }
        let off = HelmTabsDeclaration(tabs: tabs(["a", "b"], attention: "b"), selected: "a", enabled: false,
                                      style: .text, increasedContrast: false, select: { _ in })
        toolbar.sink.declare(UUID(), off)
        XCTAssertEqual(toolbar.stripForTesting.widthForTesting, dotted.reduce(0, +))
        XCTAssertLessThan(toolbar.stripForTesting.dotAlphaForTesting(1), 1)
    }

    func testTheSpacerPutsTheStripsEdgeAtTheWantedOneWhateverItHadBefore() {
        XCTAssertEqual(SettingsToolbar.spacerWidth(chrome: 96, wantedMinX: 300), 204)
        XCTAssertEqual(SettingsToolbar.spacerWidth(chrome: 96, wantedMinX: 50), 0)
        XCTAssertEqual(SettingsToolbar.spacerWidth(chrome: .nan, wantedMinX: 50), 0)
    }

    func testTheWindowsButtonsStandAtOnePlaceWhateverTheToolbar() {
        let flat = CGRect(x: 13, y: 6, width: 52, height: 16)
        let shift = ShellGeometry.toolbarShift
        let worn = flat.offsetBy(dx: shift.width, dy: shift.height)
        for rail in [false, true] {
            let a = ShellWindowButtons.placed(home: flat, rail: rail)
            let b = ShellWindowButtons.placed(home: worn, rail: rail, toolbar: true)
            XCTAssertEqual(flat.offsetBy(dx: a!.offset.width, dy: a!.offset.height),
                           worn.offsetBy(dx: b!.offset.width, dy: b!.offset.height), "rail \(rail)")
            XCTAssertEqual(a?.capsule, b?.capsule)
        }
    }
}
