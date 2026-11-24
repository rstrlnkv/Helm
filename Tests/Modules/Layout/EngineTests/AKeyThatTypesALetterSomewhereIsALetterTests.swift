import XCTest
@testable import Module_Layout_Engine

/// The other half of «a key is only punctuation in the layout you are holding».
///
/// The translation reads `,` as `б` and `[` as `х` (`KeyRemap`). The tap must
/// not ask what the key types in the layout being held — latin, where they are
/// marks that confirm a word, cutting `cgfcb,j` at the comma — but whether it
/// types a letter in any installed layout. That is a fact about the keyboard rather than about
/// Russian, so a Greek, Armenian or Hebrew layout gets the same answer for the
/// same reason.
final class AKeyThatTypesALetterSomewhereIsALetterTests: XCTestCase {

    /// Toy tables in the shape `UCTranslation` builds: keycode → what it types.
    private let latin: [UInt16: Character] = [1: "e", 28: ",", 29: ".", 19: ";", 8: "["]
    private let cyrillic: [UInt16: Character] = [1: "у", 28: "б", 29: "ю", 19: "ж", 8: "х"]

    func testALetterIsALetter() {
        XCTAssertTrue(LetterKeys(tables: [latin, cyrillic]).contains(1))
    }

    /// The four keys that are letters in Russian.
    func testAKeyThatIsAMarkHereAndALetterElsewhereIsALetter() {
        let keys = LetterKeys(tables: [latin, cyrillic])
        for code in [UInt16(28), 29, 19, 8] {
            XCTAssertTrue(keys.contains(code), "key \(code) types a letter in another layout")
        }
    }

    /// With only latin layouts installed, nothing changes. A Mac with US and
    /// British keyboards must keep confirming a word at a comma, or this fix
    /// would take punctuation-triggered conversion away from everybody who does
    /// not need it.
    func testWithNoLayoutMakingItALetterItStaysAMark() {
        let british: [UInt16: Character] = [1: "e", 28: ",", 29: ".", 19: ";", 8: "["]
        let keys = LetterKeys(tables: [latin, british])
        XCTAssertFalse(keys.contains(28))
        XCTAssertFalse(keys.contains(29))
        XCTAssertTrue(keys.contains(1))
    }

    /// A key nobody's layout carries at all.
    func testAnUnknownKeyIsNotALetter() {
        XCTAssertFalse(LetterKeys(tables: [latin, cyrillic]).contains(99))
    }

    /// Space is never a letter, whatever a layout does with that keycode: it
    /// is the word boundary this whole path is built on, and a boundary that
    /// could become part of a word would swallow the sentence.
    func testSpaceIsNeverALetter() {
        let odd: [UInt16: Character] = [49: "ы"]
        XCTAssertFalse(LetterKeys(tables: [latin, odd]).contains(49))
    }

    /// Nothing installed is not «everything is a letter»: with no tables no key
    /// is.
    func testNoTablesMeansNoLetters() {
        XCTAssertFalse(LetterKeys(tables: []).contains(28))
        XCTAssertFalse(LetterKeys(tables: []).contains(1))
    }
}
