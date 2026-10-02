import HelmRuntime
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The conflict note says «Untick it below first», so the box it means has to
/// be below.** The note is raised by `SystemShortcuts.holding` over *every* box
/// the engine reads — the two clipboard twins, 29 (⌃⇧⌘3) and 31 (⌃⇧⌘4),
/// included. The section under it draws the two `SystemBox.replaced` and a twin
/// only while it conflicts (`drawnBoxes`), in warning ink. Without that, a
/// person who records ⌃⇧⌘3 (the twin was off when they recorded, or they ticked
/// it again afterwards) was told to untick a box the page did not show, under
/// two rows that read calm.
///
/// This file checks the function: it reads `drawnBoxes`, the list the section is
/// built from. That the rendered section draws that list is
/// `TheSectionDrawsATwinOnlyWhileItConflictsTests`.
@MainActor
final class AConflictNoteNamesABoxThePageDrawsTests: XCTestCase {

    private func store(_ values: [String: Any]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    /// Every combination a note can be raised for — the one each box holds on an
    /// untouched Mac, recorded into the row — must light a box the section draws.
    func testEveryCombinationThatRaisesTheNoteLightsABoxBelowIt() throws {
        let boxes = SystemShortcuts.boxes(from: .absent)
        XCTAssertEqual(boxes.count, SystemBox.allCases.count, "the subject: every box read, all on")
        var raised = 0
        for held in boxes {
            let keyCode = try XCTUnwrap(held.keyCode), modifiers = try XCTUnwrap(held.modifiers)
            let recorded = store(["areaHotkeyKeyCode": keyCode, "areaHotkeyModifiers": modifiers])
            let combination = try XCTUnwrap(ScreenshotsSettingsPage.combination(of: .area, in: recorded))
            // What `conflictNote(_:)` asks.
            let noted = !SystemShortcuts.holding(keyCode: combination.keyCode, modifiers: combination.modifiers,
                                                 in: boxes).isEmpty
            guard noted else { continue }
            raised += 1
            // What the section below draws, and which of it is in warning ink.
            let drawn = ScreenshotsSettingsPage.drawnBoxes(boxes, against: [combination])
            let lit = drawn.filter { ScreenshotsSettingsPage.conflicts($0, with: [combination]) }.map(\.box)
            XCTAssertFalse(lit.isEmpty,
                           "recording \(held.box)'s combination raises «Untick it below first», and nothing below is that box")
        }
        XCTAssertEqual(raised, SystemBox.allCases.count, "the subject: each box's own combination raised the note")
    }
}
