import XCTest
@testable import Module_Layout_Engine

/// The two transforms that work on a selection rather than on the last word.
///
/// Both are pure string work and both are reversible-ish, which is the whole
/// reason they are safe to put on a shortcut: the person can see the result and
/// press again.
final class TextTransformTests: XCTestCase {

    // MARK: - Transliteration

    func testCyrillicBecomesLatin() {
        XCTAssertEqual(Transliteration.convert("привет"), "privet")
        XCTAssertEqual(Transliteration.convert("Москва"), "Moskva")
    }

    /// The letters that are more than one Latin character each. These are where
    /// a naive table produces `shh` for `щ` or drops the soft sign silently.
    func testTheMultiLetterOnes() {
        XCTAssertEqual(Transliteration.convert("щука"), "shchuka")
        XCTAssertEqual(Transliteration.convert("ёжик"), "yozhik")
        XCTAssertEqual(Transliteration.convert("объезд"), "obieezd")
        XCTAssertEqual(Transliteration.convert("июль"), "iyul")
    }

    /// Case is carried, including the case where one Cyrillic capital becomes
    /// several Latin letters: `Щ` is `Shch`, not `SHCH` and not `shch`.
    func testCaseIsCarried() {
        XCTAssertEqual(Transliteration.convert("Щука"), "Shchuka")
        XCTAssertEqual(Transliteration.convert("ЩУКА"), "SHCHUKA")
        XCTAssertEqual(Transliteration.convert("Юлия"), "Yuliya")
    }

    /// Anything that is not a Russian letter is left exactly as it is: this
    /// runs on a selection, and a selection contains punctuation, digits and
    /// whole English words.
    func testEverythingElseIsUntouched() {
        XCTAssertEqual(Transliteration.convert("файл 2026-07.pdf"), "fail 2026-07.pdf")
        XCTAssertEqual(Transliteration.convert("hello мир!"), "hello mir!")
        XCTAssertEqual(Transliteration.convert(""), "")
    }

    /// Back the other way, so the shortcut is one shortcut rather than two.
    /// The direction is decided by what is in the text, because a person
    /// pressing a key on a selection has already decided which way it goes.
    func testLatinBecomesCyrillic() {
        XCTAssertEqual(Transliteration.convert("privet"), "привет")
        XCTAssertEqual(Transliteration.convert("shchuka"), "щука")
        XCTAssertEqual(Transliteration.convert("Moskva"), "Москва")
    }

    /// The greedy part: `shch` has to beat `sh`, which has to beat `s`.
    /// Otherwise `щ` comes back as `сх` and the round trip is lost.
    func testTheLongestDigraphWins() {
        XCTAssertEqual(Transliteration.convert("shok"), "шок")
        XCTAssertEqual(Transliteration.convert("schet"), "счет")
        XCTAssertEqual(Transliteration.convert("zhuk"), "жук")
    }

    /// Mixed text goes to Latin: one Cyrillic letter means the person is
    /// transliterating *out*, which is what the direction rule is for.
    func testMixedTextGoesToLatin() {
        XCTAssertEqual(Transliteration.convert("файл file"), "fail file")
    }

    // MARK: - Case

    /// One shortcut, pressed repeatedly, walks a fixed cycle. Guessing "the
    /// opposite of what this is" cannot work on `Hello World`, which is neither
    /// upper nor lower.
    func testTheCaseCycle() {
        XCTAssertEqual(CaseCycle.next("hello world"), "HELLO WORLD")
        XCTAssertEqual(CaseCycle.next("HELLO WORLD"), "Hello World")
        XCTAssertEqual(CaseCycle.next("Hello World"), "hello world")
    }

    /// Anything that is none of the three starts the cycle rather than being
    /// left alone: `heLLo` is a state the cycle does not have.
    func testAnUnrecognisedShapeStartsTheCycle() {
        XCTAssertEqual(CaseCycle.next("heLLo"), "HELLO")
    }

    func testCaseWorksInRussian() {
        XCTAssertEqual(CaseCycle.next("привет мир"), "ПРИВЕТ МИР")
        XCTAssertEqual(CaseCycle.next("ПРИВЕТ МИР"), "Привет Мир")
    }

    /// Text with no letters at all has no case to change, and returning it
    /// unchanged is what stops the shortcut replacing a selection with itself
    /// — a replacement is an edit, and an edit that changes nothing still
    /// clears the undo stack of whatever app it happened in.
    func testTextWithoutLettersIsRefused() {
        XCTAssertNil(CaseCycle.apply("2026 — 07"))
        XCTAssertNil(CaseCycle.apply(""))
        XCTAssertNotNil(CaseCycle.apply("a"))
    }
}
