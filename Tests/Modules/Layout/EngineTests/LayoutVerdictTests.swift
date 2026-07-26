import XCTest
@testable import Module_Layout_Engine

/// The one unit that can ruin somebody's sentence. Every case here is a reason
/// to decline; the single reason to act is that the word is wrong as typed and
/// right when translated.
final class LayoutVerdictTests: XCTestCase {
    private func decide(_ word: String, translated: String,
                        validAsTyped: Bool, validTranslated: Bool,
                        exceptions: Set<String> = []) -> LayoutVerdict.Decision {
        LayoutVerdict.decide(word: word, translated: translated,
                             validAsTyped: validAsTyped, validTranslated: validTranslated,
                             exceptions: exceptions)
    }

    func testWrongAsTypedAndRightTranslatedConverts() {
        XCTAssertEqual(decide("ghbdtn", translated: "привет",
                              validAsTyped: false, validTranslated: true), .convert("привет"))
    }

    /// The rule that outranks every other: a real word is never touched, even
    /// when its translation is also a real word.
    func testAValidWordIsNeverConverted() {
        XCTAssertEqual(decide("ras", translated: "кфы",
                              validAsTyped: true, validTranslated: true), .leave)
        XCTAssertEqual(decide("ras", translated: "кфы",
                              validAsTyped: true, validTranslated: false), .leave)
    }

    func testNonsenseInBothLayoutsIsLeftAlone() {
        XCTAssertEqual(decide("qqqq", translated: "ййыы",
                              validAsTyped: false, validTranslated: false), .leave)
    }

    func testShortWordsAreLeftAlone() {
        for word in ["a", "ab", "gh"] {
            XCTAssertEqual(decide(word, translated: "хх",
                                  validAsTyped: false, validTranslated: true), .leave, word)
        }
    }

    func testWordsWithDigitsAreLeftAlone() {
        XCTAssertEqual(decide("ghb1", translated: "прив1",
                              validAsTyped: false, validTranslated: true), .leave)
    }

    /// A path, a URL or an address is not prose, and converting one breaks
    /// something that was correct.
    func testAddressesAndPathsAreLeftAlone() {
        for word in ["/usr/local", "http://x.dev", "me@example.com", "~/Documents"] {
            XCTAssertEqual(decide(word, translated: "ннн",
                                  validAsTyped: false, validTranslated: true), .leave, word)
        }
    }

    func testAcronymsAreLeftAlone() {
        XCTAssertEqual(decide("HTTP", translated: "РТТР",
                              validAsTyped: false, validTranslated: true), .leave)
    }

    func testTheUsersExceptionsWin() {
        XCTAssertEqual(decide("ghbdtn", translated: "привет",
                              validAsTyped: false, validTranslated: true,
                              exceptions: ["ghbdtn"]), .leave)
    }

    /// Case is the user's business, not the dictionary's.
    func testExceptionsIgnoreCase() {
        XCTAssertEqual(decide("Ghbdtn", translated: "Привет",
                              validAsTyped: false, validTranslated: true,
                              exceptions: ["ghbdtn"]), .leave)
    }

    /// Nothing translated, or the same string back, is no conversion to make.
    func testAnEmptyOrIdenticalTranslationIsLeftAlone() {
        XCTAssertEqual(decide("ghbdtn", translated: "",
                              validAsTyped: false, validTranslated: true), .leave)
        XCTAssertEqual(decide("ghbdtn", translated: "ghbdtn",
                              validAsTyped: false, validTranslated: true), .leave)
    }
}

extension LayoutVerdictTests {
    /// Somebody tired of seeing a word appear will add the word they see — the
    /// translated one — not the letters they actually pressed.
    func testAnExceptionMatchesEitherForm() {
        XCTAssertEqual(LayoutVerdict.decide(word: "ghbdtn", translated: "привет",
                                            validAsTyped: false, validTranslated: true,
                                            exceptions: ["привет"]), .leave)
    }
}
