import XCTest
@testable import Module_Layout_Engine

/// The personal vocabulary reaching the verdict.
///
/// **It refuses and never permits.** `learned` can turn a conversion into
/// `.leave` and there is no value it can take that turns a `.leave` into a
/// conversion — a vocabulary that could would let one repeated typo become a
/// standing rule inside somebody else's app.
///
/// It sits beside the never-list rather than replacing it: that list is typed
/// by hand and says «never this word», while this one is what the module
/// noticed about the words it got wrong. Both refuse; neither permits.
final class AWordPutBackTwiceIsLeftAloneTests: XCTestCase {

    private func decide(_ word: String, _ translated: String, learned: Bool) -> LayoutVerdict.Decision {
        LayoutVerdict.decide(word: word, translated: translated,
                             validAsTyped: false, validTranslated: true,
                             exceptions: [], learned: learned)
    }

    func testAWordTheModuleHasNotLearnedIsConvertedAsBefore() {
        XCTAssertEqual(decide("cnjk", "стол", learned: false), .convert("стол"))
    }

    /// The defect this closes: somebody whose login is `cnjk` had it rewritten
    /// to `стол` every time, put it back every time, and the module learned
    /// nothing.
    func testAWordPutBackTwiceIsLeftAlone() {
        XCTAssertEqual(decide("cnjk", "стол", learned: true), .leave)
    }

    /// **The direction that must not exist.** Every guard that refuses keeps
    /// refusing whatever the personal vocabulary says — it has no vote in
    /// favour of a conversion, only against.
    func testItCannotPermitWhatTheDictionaryRefused() {
        // Already a word as typed.
        XCTAssertEqual(LayoutVerdict.decide(word: "hello", translated: "руддщ",
                                            validAsTyped: true, validTranslated: true,
                                            exceptions: [], learned: false), .leave)
        // The translation is not a word.
        XCTAssertEqual(LayoutVerdict.decide(word: "xyzzy", translated: "цнййн",
                                            validAsTyped: false, validTranslated: false,
                                            exceptions: [], learned: false), .leave)
        // A digit in the word.
        XCTAssertEqual(LayoutVerdict.decide(word: "cnjk2", translated: "стол2",
                                            validAsTyped: false, validTranslated: true,
                                            exceptions: [], learned: false), .leave)
    }

    /// And the gesture obeys it too. The person asked for this word by name —
    /// but they also, twice, said this exact word is to be left alone, and the
    /// later instruction is the standing one. The never-list already works this
    /// way.
    func testTheGestureObeysItAsWell() {
        XCTAssertEqual(LayoutVerdict.decideForced(word: "cnjk", translated: "стол",
                                                  exceptions: [], learned: true), .leave)
        XCTAssertEqual(LayoutVerdict.decideForced(word: "cnjk", translated: "стол",
                                                  exceptions: [], learned: false),
                       .convert("стол"))
    }
}
