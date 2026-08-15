import XCTest
@testable import Module_Layout_Engine

/// An undo applied to text that has moved on does not restore anything — it
/// corrupts a second place. Everything here is about knowing when to refuse.
final class UndoRecordTests: XCTestCase {
    private func record() -> UndoRecord {
        UndoRecord(event: ConversionEvent(before: "ghbdtn", after: "привет",
                                          app: "com.apple.Notes"),
                   from: "en", to: "ru")
    }

    func testAFreshRecordCanBeUndoneInTheSameApp() {
        XCTAssertTrue(record().canUndo(in: "com.apple.Notes"))
    }

    /// The caret is somewhere else entirely now.
    func testAnotherAppCannotBeUndoneInto() {
        XCTAssertFalse(record().canUndo(in: "com.apple.Mail"))
    }

    func testAnythingThatMovesTheCaretInvalidatesIt() {
        var undo = record()
        undo.invalidate()
        XCTAssertFalse(undo.canUndo(in: "com.apple.Notes"))
    }

    func testTheReversePlanRestoresTheOriginal() {
        let plan = record().reversePlan()
        XCTAssertEqual(plan?.backspaces, 6)      // "привет"
        XCTAssertEqual(plan?.insert, "ghbdtn")
    }
}
