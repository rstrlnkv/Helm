import XCTest
@testable import Module_Layout_Engine

/// A selection is a sentence, and a sentence has spaces in it.
///
/// The key tables `UCTranslation` builds hold letters only, so a translation
/// that refused the string at the first character not in them would turn
/// `ghbdtn rfr` into nil and the selection path would never work, while the
/// last-word path, one word of letters, hid it.
final class ASelectionIsMoreThanOneWordTests: XCTestCase {

    /// Toy tables, in the shape `UCTranslation.buildTable` produces: key code →
    /// the letter it types. Only letters, because that is what the real one
    /// holds; what is under test is what happens to everything else.
    private let latin: [UInt16: Character] = [0: "g", 1: "h", 2: "b", 3: "d", 4: "t", 5: "n", 6: "r", 7: "f", 8: "k"]
    private let cyrillic: [UInt16: Character] = [0: "п", 1: "р", 2: "и", 3: "в", 4: "е", 5: "т", 6: "к", 7: "а", 8: "л"]

    func testOneWordStillConverts() {
        XCTAssertEqual(KeyRemap.map("ghbdtn", from: latin, to: cyrillic), "привет")
    }

    /// A sentence converts.
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
    /// `convertSelection` would then hand to the app as an edit.
    func testTextWithNoTranslatableLetterIsRefused() {
        XCTAssertNil(KeyRemap.map("ghbdtn", from: cyrillic, to: latin))
        XCTAssertNil(KeyRemap.map("12:34 — ...", from: latin, to: cyrillic))
    }

    /// A letter it cannot map refuses the whole string, and that is the line
    /// between this and punctuation. Passed through, `дфых` would come back
    /// `lasх`, a Cyrillic х on the end (`[` is not a letter in the latin table),
    /// which `NSSpellChecker` accepts as English. A space or a comma carries no
    /// reading in another layout and is kept; a letter it cannot read means it
    /// cannot read the word.
    func testAnUntranslatableLetterRefusesTheWholeString() {
        XCTAssertNil(KeyRemap.map("ghbdtn ñ", from: latin, to: cyrillic),
                     "a letter with no key in this layout was passed through")
        // The measured case, in miniature: `х` has no latin key.
        let ruWithGap: [UInt16: Character] = [0: "д", 1: "ф", 2: "ы", 9: "х"]
        XCTAssertNil(KeyRemap.map("дфых", from: ruWithGap, to: latin),
                     "a mixed-script word was handed to the spell checker")
    }

    /// And the control: everything that is not a letter still passes, or the
    /// selection path is dead.
    func testNonLettersStillPass() {
        XCTAssertEqual(KeyRemap.map("ghbdtn rfr!", from: latin, to: cyrillic), "привет как!")
    }
}
