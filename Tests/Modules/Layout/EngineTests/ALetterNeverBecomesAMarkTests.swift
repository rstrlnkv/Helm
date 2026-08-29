import XCTest
@testable import Module_Layout_Engine

/// A letter may become a letter. It may not become a mark.
///
/// Opening the key table up so `,` could be read as `б` (`96afdc45`) gave every
/// letter its key in the other direction too — and some of those keys type
/// punctuation. Measured on this Mac: `дфых` translates to `las[`, `срфех` to
/// `chat[`, and `NSSpellChecker` accepts both as English words, because a
/// trailing mark does not trouble it. So the verdict, which asks only «is the
/// translation a word», would rewrite somebody's word into one with a bracket
/// on the end.
///
/// The rule is asymmetric on purpose. A mark becoming a letter is the whole
/// repair — `cgfcb,j` → `спасибо`, where the comma key was pressed for `б`. A
/// letter becoming a mark is the opposite: somebody typing letters meant
/// letters, and no dictionary's opinion outranks that.
final class ALetterNeverBecomesAMarkTests: XCTestCase {

    private func decide(_ word: String, _ translated: String) -> LayoutVerdict.Decision {
        LayoutVerdict.decide(word: word, translated: translated,
                             validAsTyped: false, validTranslated: true, exceptions: [])
    }

    /// The two measured cases.
    func testALetterTurningIntoAMarkIsRefused() {
        XCTAssertEqual(decide("дфых", "las["), .leave)
        XCTAssertEqual(decide("срфех", "chat["), .leave)
    }

    /// The repair this must not undo: a mark becoming a letter is allowed, and
    /// is the reason most Russian words convert at all.
    func testAMarkTurningIntoALetterIsAllowed() {
        XCTAssertEqual(decide("cgfcb,j", "спасибо"), .convert("спасибо"))
        XCTAssertEqual(decide("nt,z", "тебя"), .convert("тебя"))
    }

    func testLetterForLetterIsUntouched() {
        XCTAssertEqual(decide("ghbdtn", "привет"), .convert("привет"))
    }

    /// Punctuation that stays punctuation is not a change of kind.
    func testAMarkThatStaysAMarkIsFine() {
        XCTAssertEqual(decide("ghbdtn.", "привет."), .convert("привет."))
    }

    /// **The gesture obeys it too.** `decideForced` skips the dictionary because
    /// the person asked for this word by name — but they asked for a word, and
    /// a bracket where a letter was is not what they asked for.
    func testTheGestureRefusesItAsWell() {
        XCTAssertEqual(LayoutVerdict.decideForced(word: "дфых", translated: "las[",
                                                  exceptions: []), .leave)
        XCTAssertEqual(LayoutVerdict.decideForced(word: "cgfcb,j", translated: "спасибо",
                                                  exceptions: []), .convert("спасибо"))
    }
}
