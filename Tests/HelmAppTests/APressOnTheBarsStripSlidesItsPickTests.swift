import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A press on a tab of the bar's real strip slides the pick, and the update the page's answer brings does
/// not end the slide it began.**
///
/// `TheSwitchersPickSlidesToAPressedSegmentTests` feeds a bare switcher. Here the strip is `ShellBarTabs` with a
/// page's binding behind it: the control's own action is sent (the call a click ends in), `ShellBarTabs.pick`
/// writes the page, the page republishes its bar (`show` with the new selection, as the channel does), the hosts
/// are re-rooted and laid out. What is read is what the cell was ASKED (`onSlide`) and what it holds
/// (`sliding`) on the control the strip holds AFTER all of that, and whether that control and cell are the
/// ones the seam was set on. No window is ordered in, nothing waits, sleeps or spins a run loop.
///
/// **Not seen on a screen:** the slide itself, and a press landing on the strip through a window.
@MainActor
final class APressOnTheBarsStripSlidesItsPickTests: XCTestCase {

    typealias Slide = HelmFlatSegmentedCell.Slide

    /// The page's side: what its binding holds and what it was asked to write.
    private final class Page {
        var value: String
        var writes: [String] = []
        /// A page that takes no write: its binding reads back what it held.
        var takesWrites = true
        init(_ value: String) { self.value = value }
    }

    private struct Shape {
        var attention = [false, false, false]
        var notes: [String?] = [nil, nil, nil]
        var titles = ["Installed", "Updates", "Search"]
        var isLive = true
    }

    private let ids = ["installed", "updates", "search"]

    private func publish(_ zone: ShellBarTabs, _ page: Page, _ shape: Shape) {
        let tabs = ids.indices.map { index in
            HelmToolbarTab(id: ids[index], title: shape.titles[index], symbol: "circle",
                           needsAttention: shape.attention[index], attentionNote: shape.notes[index])
        }
        let binding = Binding<String>(get: { page.value },
                                      set: { page.writes.append($0); if page.takesWrites { page.value = $0 } })
        zone.show(ShellBarZoneState(content: HelmPageToolbarContent(tabs: tabs, selectedTab: binding),
                                    isLive: shape.isLive, isDimmed: false, appearsActive: true,
                                    appearance: .flat, animated: false))
        zone.apply(ShellPageBarView.Verdicts(tabsFolded: false))
    }

    private func strip(_ zone: ShellBarTabs) throws -> (control: NSSegmentedControl, cell: HelmFlatSegmentedCell) {
        let plate = try XCTUnwrap(zone.view as? ShellBarPlate, "the zone placed no plate")
        plate.content?.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(plate.content?.everyView(ofType: NSSegmentedControl.self).first,
                                    "no segmented control under the plate")
        XCTAssertEqual(control.segmentCount, 3, "the strip is folded, so a press opens a menu")
        let cell = try XCTUnwrap(control.cell as? HelmFlatSegmentedCell, "the strip does not wear the flat cell")
        return (control, cell)
    }

    private struct Mounted {
        let zone: ShellBarTabs
        let page: Page
        let control: NSSegmentedControl
        let cell: HelmFlatSegmentedCell
        let heard: Heard
    }

    private final class Heard { var slides: [Slide] = [] }

    private func mount(_ shape: Shape = Shape(), selected: String = "installed") throws -> Mounted {
        let zone = ShellBarTabs(titlebarIsTransparent: true, labelStyle: { .text })
        let page = Page(selected)
        publish(zone, page, shape)
        let (control, cell) = try strip(zone)
        XCTAssertEqual(control.selectedSegment, ids.firstIndex(of: selected), "precondition — the first draw")
        let heard = Heard()
        cell.reducesMotion = { false }
        cell.onSlide = { heard.slides.append($0) }
        return Mounted(zone: zone, page: page, control: control, cell: cell, heard: heard)
    }

    private func press(_ m: Mounted, _ index: Int) {
        m.control.selectedSegment = index
        XCTAssertTrue(m.control.sendAction(m.control.action, to: m.control.target),
                      "the control's own action went nowhere")
    }

    // MARK: - 1. A press, then the page's answer

    func testAPressOnATabOfTheRealStripSlidesAndTheRepublicationKeepsTheSlide() throws {
        let m = try mount()
        press(m, 2)
        // The write reached the page.
        XCTAssertEqual(m.page.writes, ["search"], "the press did not reach the page's binding once")
        XCTAssertEqual(m.page.value, "search", "the page's selection is not the pressed tab")
        let want = Slide(from: 0, to: 2, duration: HelmMotion.interfaceDuration)
        XCTAssertEqual(m.heard.slides, [want], "the cell was not asked for exactly the one slide")
        XCTAssertNotNil(m.cell.sliding, "precondition — the slide did not begin on the cell the seam is set on")
        let redrawsBefore = m.zone.redrawCount

        // The page republishes with the new selection; the hosts are re-rooted and laid out.
        publish(m.zone, m.page, Shape())
        XCTAssertGreaterThan(m.zone.redrawCount, redrawsBefore, "precondition — the republication re-rooted nothing")

        let after = try strip(m.zone)
        XCTAssertTrue(after.control === m.control, "the republication replaced the control")
        XCTAssertTrue(after.cell === m.cell, "the republication replaced the cell")
        XCTAssertEqual(after.control.selectedSegment, 2, "the strip does not show the pressed tab")
        XCTAssertEqual(m.heard.slides, [want], "the cell was asked for another slide")
        XCTAssertNotNil(after.cell.sliding, "the slide was ended by the update the page's answer brought")
        XCTAssertEqual(after.cell.sliding, want)
    }

    // MARK: - 2. A press that also changes what the strip shows

    /// **A refill ends a slide, and this row holds that as the rule.** A refill may change the segments' widths
    /// and the slide's target with them, so `fill` ends the slide first; the page's answer to a press that also
    /// moves a dot or renames a tab therefore leaves the strip at rest on the pressed tab. **No real page was
    /// found that does this.** Read: the only page in `Sources` that sets `needsAttention` is
    /// `ScreenshotsSettingsPage.toolbarContent`, whose dot is `holdsSystemKeys(model.state.boxes)`, a reading of
    /// the engine's answer and not of the selected tab; no module page derives a title, a symbol or a note from
    /// its selected tab. So the row makes the case by hand: the page's answer arrives in the same republication
    /// as a dot, and the same with a renamed tab.
    func testARepublicationThatAlsoMovesADotOrANameEndsTheSlideAtRest() throws {
        var dot = Shape(); dot.attention = [false, false, true]; dot.notes = [nil, nil, "still on"]
        var name = Shape(); name.titles = ["Installed", "Updates", "Find"]
        for (what, shape) in [("a dot", dot), ("a name", name)] {
            let m = try mount()
            let subviews = m.control.subviews.count
            press(m, 2)
            XCTAssertEqual(m.heard.slides.count, 1, "\(what): precondition — the cell was not asked for one slide")
            XCTAssertEqual(m.page.value, "search", "\(what): the press did not reach the page")
            publish(m.zone, m.page, shape)
            let after = try strip(m.zone)
            XCTAssertEqual(after.control.label(forSegment: 2), shape.titles[2], "\(what): the change did not reach the strip")
            XCTAssertNil(after.cell.sliding, "\(what): the slide outlived the refill")
            XCTAssertEqual(after.control.subviews.count, subviews, "\(what): the slide's temporary view outlived the refill")
            XCTAssertEqual(after.control.selectedSegment, 2, "\(what): the strip does not show the pressed tab")
        }
    }

    // MARK: - 3. A press the page refuses

    func testAPressThePageRefusesPutsTheControlBackAndEndsTheSlide() throws {
        for (what, change) in [("a page not live", { (_: Page, shape: inout Shape) in shape.isLive = false }),
                               ("a binding that reads back the old tab", { (page: Page, _: inout Shape) in page.takesWrites = false })] {
            var shape = Shape()
            let probe = Page("installed")
            change(probe, &shape)
            let m = try mount(shape)
            m.page.takesWrites = probe.takesWrites
            press(m, 2)
            XCTAssertEqual(m.page.value, "installed", "\(what): the page took the press")
            XCTAssertEqual(m.heard.slides.count, 1, "\(what): precondition — no slide began for the press")
            let after = try strip(m.zone)
            XCTAssertEqual(after.control.selectedSegment, 0, "\(what): the control is not back on the old tab")
            XCTAssertNil(after.cell.sliding, "\(what): the refused press left a slide running")
            XCTAssertEqual(m.page.writes.count, shape.isLive ? 1 : 0, "\(what): the page's handler ran unexpectedly")
        }
    }
}
