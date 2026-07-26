import XCTest
@testable import Module_Layout_Engine

/// The record on inputs that carry nothing. It decides whether a blind edit
/// fires, so "nothing" has to mean "do not fire" everywhere it can appear.
final class UndoRecordEdgeTests: XCTestCase {
    private func record(before: String = "ghbdtn", after: String = "привет",
                        app: String = "com.apple.Notes", trailing: String = "") -> UndoRecord {
        UndoRecord(event: ConversionEvent(before: before, after: after,
                                          app: app, trailing: trailing))
    }

    /// Nothing to put back, or nothing to take away, is not a plan to send zero
    /// keystrokes — it is no plan. A plan with no backspaces would type the
    /// original in on top of the replacement.
    func testAnEmptySideOfTheConversionHasNoPlan() {
        XCTAssertNil(record(before: "").reversePlan())
        XCTAssertNil(record(after: "").reversePlan())
        XCTAssertNil(record(before: "", after: "").reversePlan())
    }

    /// The character that ended the word was deleted and retyped with the
    /// replacement, so undoing has to do the same. Empty means the hotkey
    /// converted mid-word and nothing extra is in the field.
    func testTheEndingIsPutBackWithTheOriginal() {
        XCTAssertEqual(record(trailing: "").reversePlan()?.backspaces, 6)
        XCTAssertEqual(record(trailing: "").reversePlan()?.insert, "ghbdtn")
        for ending in [" ", ".", "\n", "»"] {
            let plan = record(trailing: ending).reversePlan()
            XCTAssertEqual(plan?.backspaces, 7, ending)
            XCTAssertEqual(plan?.insert, "ghbdtn" + ending, ending)
        }
    }

    /// Nowhere to type is not somewhere safe to type — the rule `AppScope`
    /// already states for the forward direction. An undo is a blind edit at
    /// whatever has the keyboard, and "no frontmost app" is not a match for
    /// anything.
    func testAnUnknownAppIsNotAMatch() {
        XCTAssertFalse(record(app: "").canUndo(in: ""))
    }

    /// Bundle ids are compared whole. A prefix of the app's id is another app.
    func testAnAppIsMatchedWholeAndExactly() {
        XCTAssertFalse(record(app: "com.apple.Notes").canUndo(in: "com.apple.Note"))
        XCTAssertFalse(record(app: "com.apple.Notes").canUndo(in: "com.apple.Notes.helper"))
        XCTAssertTrue(record(app: "com.apple.Notes").canUndo(in: "com.apple.Notes"))
    }
}
