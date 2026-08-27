import XCTest
@testable import Module_Layout_Engine

/// A selection is a sentence, and a sentence has spaces in it.
///
/// The whole selection path was dead for exactly that reason, and nothing said
/// so: the key tables `UCTranslation` builds hold letters only, and the
/// translation refused the entire string at the first character that was not in
/// them. Measured against the real ports on a Mac with US and Russian
/// installed: `ghbdtn` → `привет`, and `ghbdtn rfr` → nil. So «select a
/// sentence and put it right» could not work once, ever — while the last-word
/// path, whose input is one word of letters, was healthy and hid it.
///
/// The three log lines the owner's Mac had for this read
/// `selection left alone: no conversion for 24 characters`.
final class ASelectionIsMoreThanOneWordTests: XCTestCase {

    /// Toy tables, in the shape `UCTranslation.buildTable` produces: key code →
    /// the letter it types. Only letters, because that is what the real one
    /// holds — the defect under test is what happens to everything else.
    private let latin: [UInt16: Character] = [0: "g", 1: "h", 2: "b", 3: "d", 4: "t", 5: "n", 6: "r", 7: "f", 8: "k"]
    private let cyrillic: [UInt16: Character] = [0: "п", 1: "р", 2: "и", 3: "в", 4: "е", 5: "т", 6: "к", 7: "а", 8: "л"]

    func testOneWordStillConverts() {
        XCTAssertEqual(KeyRemap.map("ghbdtn", from: latin, to: cyrillic), "привет")
    }

    /// The defect itself.
    func testASpaceDoesNotKillTheWholeSentence() {
        XCTAssertEqual(KeyRemap.map("ghbdtn rfr", from: latin, to: cyrillic), "привет как")
    }

    /// Punctuation is left where the person put it. Read strictly, the comma
    /// key on US types «б» in Russian — but somebody writing Russian on a
    /// latin layout pressed that key *for a comma* and saw a comma. Converting
    /// it would be reading the keyboard right and the person wrong.
    func testPunctuationAndDigitsPassThroughUnchanged() {
        XCTAssertEqual(KeyRemap.map("ghbdtn, rfr!", from: latin, to: cyrillic), "привет, как!")
        XCTAssertEqual(KeyRemap.map("ghbdtn2", from: latin, to: cyrillic), "привет2")
    }

    func testANewlineSurvives() {
        XCTAssertEqual(KeyRemap.map("ghbdtn\nrfr", from: latin, to: cyrillic), "привет\nкак")
    }

    func testCaseIsKept() {
        XCTAssertEqual(KeyRemap.map("Ghbdtn", from: latin, to: cyrillic), "Привет")
        XCTAssertEqual(KeyRemap.map("GHBDTN", from: latin, to: cyrillic), "ПРИВЕТ")
    }

    /// Nothing to convert is not a conversion. Latin text read through the
    /// Russian table has no letter in common with it, and returning the string
    /// unchanged would report a conversion that did not happen — which
    /// `SelectionTransform` would then hand to the app as an edit.
    func testTextWithNoTranslatableLetterIsRefused() {
        XCTAssertNil(KeyRemap.map("ghbdtn", from: cyrillic, to: latin))
        XCTAssertNil(KeyRemap.map("12:34 — ...", from: latin, to: cyrillic))
    }

    /// A letter this layout does not carry stays as it is, rather than taking
    /// the whole string down with it. A selection can hold a name, an emoji or
    /// a word in a third language.
    func testAnUnknownLetterDoesNotRefuseTheRest() {
        XCTAssertEqual(KeyRemap.map("ghbdtn ñ", from: latin, to: cyrillic), "привет ñ")
    }
}
