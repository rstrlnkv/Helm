import XCTest
@testable import Module_Layout_Engine

/// Two- and three-letter words, which the module used to refuse outright.
///
/// The old rule declined anything under three characters, and its reasoning
/// was sound: a spell checker's yes/no is nearly worthless that short, because
/// both forms are usually "words" to it. `yt` is not English, but a checker
/// that has met `yt` as an abbreviation will say it is — and the cost of
/// being wrong here is a rewritten word in somebody's sentence.
///
/// So short words are not decided by "is this a word" at all. They are decided
/// by a curated list of the short words people actually type, and only convert
/// when the translated form is on it and the typed form is not. Confidence,
/// not permission.
final class ShortWordTests: XCTestCase {

    private func decide(_ typed: String, _ translated: String,
                        validAsTyped: Bool = false, validTranslated: Bool = true)
    -> LayoutVerdict.Decision {
        LayoutVerdict.decide(word: typed, translated: translated,
                             validAsTyped: validAsTyped, validTranslated: validTranslated,
                             exceptions: [])
    }

    // MARK: - The words this was asked for

    /// Typing Russian on a US layout: the keys for «не» give `yt`.
    func testATwoLetterRussianWordIsConverted() {
        XCTAssertEqual(decide("yt", "не"), .convert("не"))
        XCTAssertEqual(decide("yf", "на"), .convert("на"))
        XCTAssertEqual(decide("gj", "по"), .convert("по"))
    }

    /// And the other direction: the keys for `no` on a Russian layout give «тщ».
    func testATwoLetterEnglishWordIsConverted() {
        XCTAssertEqual(decide("тщ", "no"), .convert("no"))
        XCTAssertEqual(decide("шы", "is"), .convert("is"))
    }

    func testThreeLetterWordsWork() {
        XCTAssertEqual(decide("dct", "все"), .convert("все"))
        XCTAssertEqual(decide("rfr", "как"), .convert("как"))
        XCTAssertEqual(decide("xnj", "что"), .convert("что"))
        XCTAssertEqual(decide("faq", "фзй"), .leave)   // an acronym, not a word
    }

    // MARK: - What must still not happen

    /// The rule that outranks everything: what was typed is already a word.
    func testAShortWordThatIsAlreadyAWordIsNeverTouched() {
        XCTAssertEqual(decide("no", "тщ", validAsTyped: true), .leave)
        XCTAssertEqual(decide("не", "yt", validAsTyped: true), .leave)
    }

    /// The translated form has to be a word people type, not merely something
    /// a dictionary tolerates. This is the whole reason the list exists.
    func testAnUnlikelyTranslationIsNotConverted() {
        // "аы" is not a Russian word anyone types, whatever a checker says.
        XCTAssertEqual(decide("fs", "аы", validTranslated: true), .leave)
        XCTAssertEqual(decide("хз", "[p", validTranslated: true), .leave)
    }

    /// A single character carries no evidence at all.
    func testOneCharacterIsNeverConverted() {
        XCTAssertEqual(decide("y", "н"), .leave)
        XCTAssertEqual(decide("a", "ф"), .leave)
    }

    /// The short list must not override the guards that protect real text.
    func testTheOtherGuardsStillApply() {
        XCTAssertEqual(decide("yt2", "не2"), .leave)          // has a digit
        XCTAssertEqual(decide("yt/", "не/"), .leave)          // looks like a path
        XCTAssertEqual(decide("YT", "НЕ"), .leave)            // an acronym
    }

    func testAnExceptionStillWins() {
        let decision = LayoutVerdict.decide(word: "yt", translated: "не",
                                            validAsTyped: false, validTranslated: true,
                                            exceptions: ["не"])
        XCTAssertEqual(decision, .leave)
    }

    // MARK: - The list itself

    func testTheListHoldsBothLanguagesAndOnlyShortWords() {
        XCTAssertTrue(ShortWords.isCommon("не"))
        XCTAssertTrue(ShortWords.isCommon("no"))
        XCTAssertTrue(ShortWords.isCommon("ЧТО"))     // case does not matter
        XCTAssertFalse(ShortWords.isCommon("аы"))
        XCTAssertFalse(ShortWords.isCommon(""))
    }

    /// Every entry is short: a long word here would silently bypass the spell
    /// checker, which is the one thing this list must never do.
    func testEveryEntryIsShort() {
        for word in ShortWords.all {
            XCTAssertLessThanOrEqual(word.count, 3, "\(word) is not a short word")
            XCTAssertGreaterThanOrEqual(word.count, 2, "\(word) is too short to judge")
            XCTAssertEqual(word, word.lowercased(), "\(word) is not lowercased")
        }
    }

    /// A word cannot be common in both languages at once here, or the
    /// asymmetry the decision rests on disappears.
    func testNoWordIsCommonOnBothSides() {
        let overlap = ShortWords.russian.intersection(ShortWords.english)
        XCTAssertTrue(overlap.isEmpty, "ambiguous in both languages: \(overlap)")
    }
}
