import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
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
        let total = HelmTabsMetrics.total(tabs(["a", "b"], attention: "b"), .text)
        XCTAssertEqual(toolbar.stripForTesting.widthForTesting, total)
        XCTAssertEqual(total, dotted.reduce(0, +) + 2 * HelmTabsMetrics.trackInset)
        XCTAssertLessThan(toolbar.stripForTesting.dotAlphaForTesting(1), 1)
    }

    /// The owner's screenshot of 2026-11-23: segments summing to the item's width left the control, which keeps its
    /// own inset either side of them in a toolbar, wider than its item, so the first label sat on the track's edge
    /// and the last pill ran past it. (The inset itself shows only in a live toolbar, off screen the control reads
    /// the plain sum: it is measured on a shot, recorded in `ThePageHeader.md`, not held here.)
    func testTheItemIsTheSegmentsAndTheTracksInsetEitherSideInEveryStyle() {
        XCTAssertEqual(HelmTabsMetrics.trackInset, 9)
        for style in [ToolbarSwitcherStyle.text, .icons, .iconsAndText] {
            let toolbar = SettingsToolbar()
            toolbar.attach(to: window()) { .liquidGlass }
            let declaration = HelmTabsDeclaration(tabs: tabs(["a", "b", "c"], attention: "c"), selected: "a", enabled: true,
                                                  style: style, increasedContrast: false, select: { _ in })
            toolbar.sink.declare(UUID(), declaration)
            XCTAssertEqual(toolbar.stripForTesting.widthForTesting,
                           HelmTabsMetrics.widths(declaration.tabs, style).reduce(0, +) + 18, "\(style)")
        }
    }

    /// The owner's live finding (Helm Dev, 2 of 2): Flat to Liquid Glass with the settings window open left the page
    /// tabs gone from the toolbar on every page until relaunch; Glass to Flat worked. Driven through the real row
    /// (`helmCardHeader`, its `HelmTabsRelay`) in a hosting view with the toolbar's own sink and the look read the
    /// way the pane reads it (`helmTracksBarAppearance`): the relay is dismantled under Flat and releases the row's
    /// token, and the same row mounts it again under Glass.
    func testTheTabsComeBackWhenTheLookGoesGlassFlatGlassOnTheSameOpenWindow() {
        var look = HelmBarAppearance.liquidGlass
        let toolbar = SettingsToolbar()
        // The toolbar's own sink behind a recorder: which token each call came under, and where the slot was said to be.
        var declared: [UUID] = []
        var placed: [(owner: UUID, rect: CGRect?)] = []
        let real = toolbar.sink
        let spy = HelmTabsSink(
            declare: { owner, declaration in
                if declaration != nil { declared.append(owner) }
                real.declare(owner, declaration)
            },
            place: { owner, rect in placed.append((owner, rect)); real.place(owner, rect) },
            release: { real.release($0) })
        let page = Color.clear
            .helmWindowToolbar(HelmPageToolbarContent(tabs: tabs(["a", "b"]), selectedTab: .constant("a")))
            .helmCardHeader(symbol: "gearshape", tint: .blue, title: "Page", status: nil)
            .environment(\.helmHeaderInCard, true)
            .environment(\.helmTabsSink, spy)
            .helmTracksBarAppearance { look }
        let mount = MountedRender(page, width: 900, height: 400, appearance: .aqua)
        defer { mount.drop() }
        guard let window = mount.window else { return XCTFail("no window") }
        toolbar.attach(to: window) { look }
        let strip = toolbar.stripForTesting

        mount.settle()
        XCTAssertFalse(toolbar.tabsItemIsHiddenForTesting, "precondition: under Glass the row's tabs reach the toolbar")
        XCTAssertEqual(strip.segmentCountForTesting, 2, "precondition: the page's two tabs are in the strip")

        look = .flat
        NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
        mount.settle()
        XCTAssertNil(window.toolbar, "precondition: Flat takes the toolbar off")
        XCTAssertTrue(toolbar.tabsItemIsHiddenForTesting, "precondition: the relay's release hid the tabs under Flat")

        look = .liquidGlass
        NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
        mount.settle()
        XCTAssertTrue(toolbar.isInstalledForTesting)
        XCTAssertFalse(toolbar.tabsItemIsHiddenForTesting,
                       "DEFECT: Glass after Flat leaves the tabs hidden: the row's token was retired by the Flat release and the remounted relay is refused")
        XCTAssertEqual(strip.segmentCountForTesting, 2, "the page's tabs are back in the strip")
        // The strip can be lined up with the row's placeholder only if the slot is said by the owner that declares:
        // another owner's `place` is parked as an arrival and never reaches the spacer. (The strip's own x is not read:
        // an offscreen window's toolbar does not lay out, 759 against the slot's 383.5 on the fix itself.)
        guard let owner = declared.last, let slot = placed.last(where: { $0.rect != nil }) else {
            return XCTFail("the row declared nothing or placed nothing after the return to Glass")
        }
        XCTAssertEqual(slot.owner, owner, "the placeholder is placed under the token that declares the tabs")
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
