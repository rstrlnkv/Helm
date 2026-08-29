import XCTest
@testable import Module_Layout_Engine

/// A key is only «punctuation» in the layout you happen to be holding.
///
/// `,` types `б` in Russian, `;` types `ж`, `[` types `х`, `'` types `э`.
/// The key table kept letters only, so seven Cyrillic letters had no key at
/// all — and the same is true of most non-latin layouts, which is why this is
/// not a Russian fix. Measured over 24 ordinary Russian words typed on the US
/// layout: 6 corrupted mid-word, 18 refused, 0 converted correctly.
///
/// Admitting those keys fixes the words and breaks the sentences: with the
/// whole table, `Ghbdtn, rfr ltkf?` came back `Приветб как дела?` — measured.
/// Both readings are right, and which one applies is decided by the neighbour
/// on the right, not by the key:
///
/// - a letter follows → the person pressed it for a letter (`cgfcb,j`)
/// - a space, another mark, or nothing follows → they pressed it for the mark
///   (`Ghbdtn,` / `ltkf?`)
///
/// A mark at the very start with letters after it — `[jhjij` for «хорошо» —
/// reads as a letter by the same rule, which is what makes the rule worth
/// having rather than «inside a word».
final class AKeyIsOnlyPunctuationInOneLayoutTests: XCTestCase {

    /// Toy tables in the shape `buildTable` now produces: every key, not only
    /// the letter-typing ones.
    private let latin: [UInt16: Character] = [
        1: "e", 2: "t", 3: "y", 4: "u", 5: "i", 6: "o", 7: "p", 8: "[",
        10: "a", 11: "s", 12: "d", 13: "f", 14: "g", 15: "h", 16: "j", 17: "k", 18: "l", 19: ";", 20: "'",
        21: "z", 22: "x", 23: "c", 24: "v", 25: "b", 26: "n", 27: "m", 28: ",", 29: ".",
        30: "r", 31: "q", 32: "w",
    ]
    private let cyrillic: [UInt16: Character] = [
        1: "у", 2: "е", 3: "н", 4: "г", 5: "ш", 6: "щ", 7: "з", 8: "х",
        10: "ф", 11: "ы", 12: "в", 13: "а", 14: "п", 15: "р", 16: "о", 17: "л", 18: "д", 19: "ж", 20: "э",
        21: "я", 22: "ч", 23: "с", 24: "м", 25: "и", 26: "т", 27: "ь", 28: "б", 29: "ю",
        30: "к", 31: "й", 32: "ц",
    ]

    /// The six measured words that the letters-only table could not produce.
    func testAMarkFollowedByALetterIsALetter() {
        XCTAssertEqual(KeyRemap.map("cgfcb,j", from: latin, to: cyrillic), "спасибо")
        XCTAssertEqual(KeyRemap.map("nt,z", from: latin, to: cyrillic), "тебя")
        XCTAssertEqual(KeyRemap.map(";le", from: latin, to: cyrillic), "жду")
    }

    /// A mark that opens the word, with letters after it.
    func testAMarkThatOpensAWordIsALetterToo() {
        XCTAssertEqual(KeyRemap.map("[jhjij", from: latin, to: cyrillic), "хорошо")
        XCTAssertEqual(KeyRemap.map("'rhfy", from: latin, to: cyrillic), "экран")
    }

    /// And the half that broke when the table was opened up.
    func testAMarkBeforeASpaceOrAtTheEndStaysAMark() {
        XCTAssertEqual(KeyRemap.map("Ghbdtn, rfr ltkf?", from: latin, to: cyrillic),
                       "Привет, как дела?")
        XCTAssertEqual(KeyRemap.map("ghbdtn.", from: latin, to: cyrillic), "привет.")
        XCTAssertEqual(KeyRemap.map("ghbdtn,", from: latin, to: cyrillic), "привет,")
    }

    /// Two marks in a row are both marks — neither is followed by a letter.
    func testMarksInARowStayMarks() {
        XCTAssertEqual(KeyRemap.map("ghbdtn...", from: latin, to: cyrillic), "привет...")
    }
}
