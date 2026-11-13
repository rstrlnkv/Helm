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
