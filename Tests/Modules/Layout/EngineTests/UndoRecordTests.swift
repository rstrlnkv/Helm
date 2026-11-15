import XCTest
@testable import Module_Layout_Engine

/// An undo applied to text that has moved on does not restore anything — it
/// corrupts a second place. Everything here is about knowing when to refuse.
final class UndoRecordTests: XCTestCase {
    private func record() -> UndoRecord {
        UndoRecord(event: ConversionEvent(before: "ghbdtn", after: "привет",
                                          app: "com.apple.Notes"),
                   from: "en")
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

/// The reverse plan is the same arithmetic pointed the other way, and it is the
/// blinder of the two edits: by the time it runs, nothing has looked at the
/// field since.
final class UndoRecordCountingTests: XCTestCase {

    private func record(before: String, after: String, trailing: String) -> UndoRecord {
        UndoRecord(event: ConversionEvent(before: before, after: after,
                                          app: "com.apple.Notes", trailing: trailing),
                   from: "en")
    }

    /// The conversion deleted the word and its ending and typed the
    /// replacement and the ending back, so the field holds `after + trailing`
    /// — measured together, as the field holds it.
    func testTheReverseCountIsTheReplacementAndItsEndingTogether() {
        let undo = record(before: "ghbdt", after: "приве", trailing: "\u{0301}")
        XCTAssertEqual(undo.reversePlan()?.backspaces, ("приве" + "\u{0301}").count,
                       "the undo deletes one more character than the conversion put there")
    }

    /// One chord is forgiven, because the undo shortcut is itself a chord and
    /// reaches the tap before Carbon delivers it. A second is not.
    func testOneChordIsForgivenAndASecondIsNot() {
        var undo = record(before: "ghbdtn", after: "привет", trailing: " ")
        undo.soften()
        XCTAssertTrue(undo.canUndo(in: "com.apple.Notes"),
                      "the shortcut must not destroy its own precondition")
        undo.soften()
        XCTAssertFalse(undo.canUndo(in: "com.apple.Notes"),
                       "two chords is navigation, not a request")
    }

    /// Softening is a lesser thing than invalidating and must never undo one.
    /// A record killed by a keystroke cannot come back because a chord arrived
    /// afterwards.
    func testSofteningCannotReviveAnInvalidatedRecord() {
        var undo = record(before: "ghbdtn", after: "привет", trailing: " ")
        undo.invalidate()
        undo.soften()
        XCTAssertFalse(undo.canUndo(in: "com.apple.Notes"))
        undo.soften()
        XCTAssertFalse(undo.canUndo(in: "com.apple.Notes"))
    }

    /// And the app check outranks both: a softened record is still only
    /// undoable where it happened.
    func testASoftenedRecordIsStillTiedToItsApp() {
        var undo = record(before: "ghbdtn", after: "привет", trailing: " ")
        undo.soften()
        XCTAssertFalse(undo.canUndo(in: "com.apple.Mail"))
    }
}
