import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A clipboard twin (29, 31) is a row in the section while it is on and holds
/// a combination Helm holds — recorded here or shipped as the default — and at
/// no other time.** The rule is spelled once
/// in `ScreenshotsSettingsPage.drawnBoxes(_:against:)`; the first half of this
/// file feeds that function the states nobody tests by accident, the second half
/// mounts the page and asks the *rendered* section, because a test that reads
/// "drawn" from the function under test stays green when the section's
/// `ForEach` iterates something else. A render cannot read glyphs here (the
/// accessibility tree is empty under the suite), so each rendered claim is a
/// difference of one row between two pages that raise the same note.
@MainActor
final class TheSectionDrawsATwinOnlyWhileItConflictsTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private let shiftCmd = CarbonModifier.cmd | CarbonModifier.shift
    private var ctrlShiftCmd: Int { CarbonModifier.control | shiftCmd }

    private func drawn(_ boxes: [SystemBoxReading], _ combinations: [(keyCode: Int, modifiers: Int)]) -> [SystemBox] {
        ScreenshotsSettingsPage.drawnBoxes(boxes, against: combinations).map(\.box)
    }

    // MARK: - The rule

    func testATwinThatIsOnAndHoldsNothingRecordedIsNotDrawn() {
        let boxes = SystemShortcuts.boxes(from: .absent)
        XCTAssertEqual(boxes.filter { $0.state == .on }.count, 5, "the subject: both twins and the panel's box on")
        let shipped = ScreenshotsHotkey.allCases.map { (keyCode: $0.fallback.keyCode, modifiers: $0.fallback.modifiers) }
        XCTAssertEqual(drawn(boxes, shipped), [.saveScreen, .saveArea, .panel])
        XCTAssertEqual(drawn(boxes, []), [.saveScreen, .saveArea, .panel], "nothing recorded at all")
    }

    func testATwinThatIsOffIsNotDrawnOverItsOwnCombination() {
        let boxes = SystemShortcuts.boxes(from: .read(["29": ["enabled": false], "31": ["enabled": false]]))
        XCTAssertEqual(boxes.first { $0.box == .copyArea }?.state, .off, "the subject: the twin read as off")
        XCTAssertEqual(boxes.first { $0.box == .copyArea }?.keyCode, 21, "the subject: it still carries ⌃⇧⌘4")
        XCTAssertEqual(drawn(boxes, [(21, ctrlShiftCmd), (20, ctrlShiftCmd)]), [.saveScreen, .saveArea, .panel])
    }

    func testAnUnreadableReadingDrawsTheTwoAndNoTwin() {
        let boxes = SystemShortcuts.boxes(from: .unreadable)
        XCTAssertTrue(boxes.allSatisfy { $0.state == .unknown }, "the subject: every box unknown")
        XCTAssertEqual(drawn(boxes, [(21, ctrlShiftCmd), (20, ctrlShiftCmd), (21, shiftCmd)]),
                       [.saveScreen, .saveArea, .panel], "an unknown box is drawn as the three Helm may take and nothing else")
    }

    func testBothTwinsConflictingAreBothDrawnInTheTablesOrder() {
        let boxes = SystemShortcuts.boxes(from: .absent)
        XCTAssertEqual(drawn(boxes, [(21, ctrlShiftCmd), (20, ctrlShiftCmd)]),
                       [.saveScreen, .copyScreen, .saveArea, .copyArea, .panel])
        XCTAssertEqual(drawn(boxes, [(21, ctrlShiftCmd)]), [.saveScreen, .saveArea, .copyArea, .panel])
    }

    // MARK: - What the section actually draws

    private func height(state boxes: [SystemBoxReading], values: [String: Any]) -> CGFloat {
        var state = ScreenshotsPageRender.untouched
        state.boxes = boxes
        return ScreenshotsPageRender.height(of: ScreenshotsPageRender.mount(
            language: .en, appearance: .aqua, state: state, values: values))
    }

    private func recording(area: (Int, Int), screen: (Int, Int)? = nil) -> [String: Any] {
        var values: [String: Any] = ["areaHotkeyKeyCode": area.0, "areaHotkeyModifiers": area.1]
        if let screen { values["fullScreenHotkeyKeyCode"] = screen.0; values["fullScreenHotkeyModifiers"] = screen.1 }
        return values
    }

    /// The same note is raised on both pages — ⇧⌘4 against box 30, ⌃⇧⌘4 against
    /// its twin 31 — so the only thing that may differ is the twin's row.
    func testTheRenderedSectionGrowsByARowForAConflictingTwin() {
        let boxes = SystemShortcuts.boxes(from: .absent)
        let replaced = height(state: boxes, values: recording(area: (21, shiftCmd)))
        let twin = height(state: boxes, values: recording(area: (21, ctrlShiftCmd)))
        XCTAssertGreaterThan(twin, replaced + 16,
                             "⌃⇧⌘4 raised «Untick it below first» and the section drew no row for box 31 — \(twin) against \(replaced)")
        let both = height(state: boxes, values: recording(area: (21, ctrlShiftCmd), screen: (20, ctrlShiftCmd)))
        let bothReplaced = height(state: boxes, values: recording(area: (21, shiftCmd), screen: (20, shiftCmd)))
        XCTAssertGreaterThan(both, bothReplaced + 32,
                             "both twins conflict and the section did not draw two more rows — \(both) against \(bothReplaced)")
    }

    /// The two that are always drawn are the baseline: a reading that carries
    /// only boxes 28 and 30 cannot draw a twin. A page with both twins on and
    /// nothing recorded on them, with a twin off under its own combination, or
    /// with nothing readable, must be that page's height.
    func testTheRenderedSectionDrawsNoTwinThatDoesNotConflict() {
        let absent = SystemShortcuts.boxes(from: .absent)
        let onlyTheTwo = absent.filter { SystemBox.replaced.contains($0.box) }
        let baseline = height(state: onlyTheTwo, values: [:])
        XCTAssertEqual(height(state: absent, values: [:]), baseline, accuracy: 6,
                       "both twins on, conflicting with nothing, and the section drew them")

        let twinsOff = SystemShortcuts.boxes(from: .read(["29": ["enabled": false], "31": ["enabled": false]]))
        let recorded = recording(area: (21, ctrlShiftCmd), screen: (20, ctrlShiftCmd))
        XCTAssertEqual(height(state: twinsOff, values: recorded),
                       height(state: twinsOff.filter { SystemBox.replaced.contains($0.box) }, values: recorded),
                       accuracy: 6, "a twin that is off was drawn over the combination it no longer holds")

        let unreadable = SystemShortcuts.boxes(from: .unreadable)
        XCTAssertEqual(height(state: unreadable, values: recorded),
                       height(state: unreadable.filter { SystemBox.replaced.contains($0.box) }, values: recorded),
                       accuracy: 6, "an unreadable twin was drawn")
    }
}
