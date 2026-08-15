import XCTest
@testable import Module_Layout_Engine

/// The backspace count, against endings that are not one character wide in the
/// field.
///
/// The plan is a number of deletes sent blind into somebody else's text field.
/// The existing suite pins that the count is never *short* — one too few leaves
/// the head of the word in place. This is the other side: one too many eats the
/// character before the word, which is text the module never looked at.
///
/// The arithmetic is `word.count + tail.count`, two counts added after the
/// fact. That is the same number as `(word + tail).count` for every ending that
/// stands on its own, and a different number for one that does not.
final class SwitchPlanCountingTests: XCTestCase {

    /// A combining mark is a keystroke and is not a grapheme.
    ///
    /// U+0301 has no width of its own: typed after `приве` the field still
    /// holds five characters, with the accent sitting on the last one. The tap
    /// delivers it as `.punctuation` — it is not a letter, so it ends the word
    /// — and the ending is carried into the plan, where it is counted as one
    /// more thing to delete. Six deletes for five characters: the space before
    /// the word goes too, and with it the end of the word before that.
    ///
    /// Combining marks are ordinary keys on the Greek polytonic, Vietnamese and
    /// several Cyrillic layouts, and the stress mark U+0301 is typed by hand in
    /// Russian text all the time.
    func testACombiningEndingIsNotAnExtraCharacterInTheField() {
        let word = "приве"
        let combining: Character = "\u{0301}"
        XCTAssertEqual((word + String(combining)).count, 5,
                       "precondition: the mark composes onto the last letter")

        let plan = SwitchPlan.make(replacing: word, with: "ghbdt", trailing: combining)
        XCTAssertEqual(plan?.backspaces, 5,
                       "the field holds five characters and the plan deletes "
                       + "\(plan?.backspaces ?? 0) — the extra delete eats the character "
                       + "before the word")
    }

    /// The general rule the case above is one instance of: what is deleted is
    /// the word and its ending *as the field holds them*, which is one count
    /// and not two added together.
    func testTheCountIsTheWordAndItsEndingMeasuredTogether() {
        let cases: [(String, Character)] = [
            ("ghbdtn", " "),          // the ordinary one
            ("ghbdtn", "."),
            ("приве", "\u{0301}"),    // combining acute
            ("hello", "\u{0308}"),    // combining diaeresis
            ("a", "\u{0327}"),        // combining cedilla onto a single letter
        ]
        for (word, ending) in cases {
            let inTheField = word + String(ending)
            let plan = SwitchPlan.make(replacing: word, with: "xxxxx", trailing: ending)
            XCTAssertEqual(plan?.backspaces, inTheField.count,
                           "\(word) + U+\(String(format: "%04X", ending.unicodeScalars.first!.value))")
        }
    }

    /// An enormous word is still counted once per character, not truncated and
    /// not overflowed.
    func testAnEnormousWordIsCountedInFull() {
        let word = String(repeating: "g", count: 100_000)
        let plan = SwitchPlan.make(replacing: word, with: "п", trailing: " ")
        XCTAssertEqual(plan?.backspaces, 100_001)
    }

    /// A replacement made entirely of characters wider than one scalar is still
    /// one delete per character: the count is in graphemes, which is what one
    /// press of delete removes.
    func testEmojiAndSurrogatePairsCountAsOneEach() {
        XCTAssertEqual(SwitchPlan.make(replacing: "👍🏽🇷🇺👩‍👩‍👧", with: "x")?.backspaces, 3,
                       "a skin-toned thumb, a flag and a family are three deletes, not "
                       + "eleven scalars")
    }
}

/// The buffer's honesty about its own count, once it has stopped describing
/// the field.
final class TypingBufferOverflowRecoveryTests: XCTestCase {

    /// Deleting back under the limit does not make an over-long token honest.
    ///
    /// The buffer stopped at 64 while the field went on to 70, so after six
    /// backspaces the field holds 64 characters and the buffer holds 58. The
    /// two counts agree at no point until the next boundary, and a word
    /// reported here would delete 58 of 64. The flag is per-word and must
    /// survive every backspace in it.
    func testBackspacingAfterAnOverflowDoesNotMakeTheWordReportable() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength + 6) { _ = buffer.accept(.character("g")) }
        for _ in 0..<6 { _ = buffer.accept(.backspace) }
        XCTAssertNil(buffer.accept(.space),
                     "the buffer holds \(TypingBuffer.maxLength - 6) characters and the "
                     + "field holds \(TypingBuffer.maxLength)")
    }

    /// Even emptying it by hand does not, because the field is not empty: 70
    /// characters were typed and 64 backspaces take the field to six.
    func testDeletingEverythingTheBufferHoldsDoesNotClearTheOverflow() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength + 6) { _ = buffer.accept(.character("g")) }
        for _ in 0..<TypingBuffer.maxLength { _ = buffer.accept(.backspace) }
        XCTAssertEqual(buffer.word, "")
        for character in "abc" { _ = buffer.accept(.character(character)) }
        XCTAssertNil(buffer.accept(.space),
                     "six characters of the old token are still in front of `abc`")
    }

    /// …and the boundary clears it, so one pasted line of base64 does not kill
    /// conversions until relaunch.
    func testTheBoundaryClearsTheOverflow() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength + 6) { _ = buffer.accept(.character("g")) }
        _ = buffer.accept(.space)
        for character in "ghbdtn" { _ = buffer.accept(.character(character)) }
        XCTAssertEqual(buffer.accept(.space)?.word, "ghbdtn")
    }
}

/// The reverse plan is the same arithmetic pointed the other way, and it is the
/// blinder of the two edits: by the time it runs, nothing has looked at the
/// field since.
final class UndoRecordCountingTests: XCTestCase {

    private func record(before: String, after: String, trailing: String) -> UndoRecord {
        UndoRecord(event: ConversionEvent(before: before, after: after,
                                          app: "com.apple.Notes", trailing: trailing),
                   from: "en", to: "ru")
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
    /// reaches the tap before Carbon delivers it. A second is not: by then it
    /// was somebody navigating.
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
