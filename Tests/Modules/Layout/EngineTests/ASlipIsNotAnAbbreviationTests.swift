import XCTest
@testable import Module_Layout_Engine

/// The one typing habit Helm corrects on its own, `TypingHabits.corrected`.
///
/// Three letters, upper-upper-lower, is a slipped Shift and it is `CDs`, `IDs`,
/// `PCs`, `TVs`, `OKs` — a two-letter abbreviation with a lowercase suffix, the
/// commonest shape the rule cannot tell from a mistake.
///
/// The fourth letter is what separates them: a slip carries a word behind it,
/// an abbreviation-plus-suffix does not.
final class ASlipIsNotAnAbbreviationTests: XCTestCase {

    func testASlippedShiftIsCorrected() {
        XCTAssertEqual(TypingHabits.corrected("ПРивет"), "Привет")
        XCTAssertEqual(TypingHabits.corrected("HEllo"), "Hello")
        XCTAssertEqual(TypingHabits.corrected("WOrld"), "World")
    }

    /// A two-letter abbreviation with a lowercase suffix.
    func testATwoLetterAbbreviationWithASuffixIsLeftAlone() {
        for word in ["CDs", "IDs", "PCs", "TVs", "OKs"] {
            XCTAssertNil(TypingHabits.corrected(word),
                         "\(word) is an abbreviation, not a Shift held too long")
        }
    }

    /// Shouting is a decision. Correcting somebody who meant it is worse than
    /// leaving a typo.
    func testAllCapitalsIsLeftAlone() {
        XCTAssertNil(TypingHabits.corrected("ПРИВЕТ"))
        XCTAssertNil(TypingHabits.corrected("HELLO"))
    }

    /// An identifier's shape is its meaning.
    func testAWordWithADigitIsLeftAlone() {
        XCTAssertNil(TypingHabits.corrected("IPv6"))
        XCTAssertNil(TypingHabits.corrected("MP3file"))
    }

    func testTooShortToTell() {
        XCTAssertNil(TypingHabits.corrected(""))
        XCTAssertNil(TypingHabits.corrected("A"))
        XCTAssertNil(TypingHabits.corrected("AB"))
        XCTAssertNil(TypingHabits.corrected("ПР"))
    }

    /// One letter changes, and only one: a correction that also converted the
    /// layout would be two edits to one word, which the undo shortcut cannot
    /// take back in a single press.
    func testExactlyOneLetterMoves() {
        let before = "ПРивет"
        let after = try? XCTUnwrap(TypingHabits.corrected(before))
        let differing = zip(Array(before), Array(after ?? "")).filter { $0 != $1 }
        XCTAssertEqual(differing.count, 1)
    }

    /// What shape alone gets wrong: a longer abbreviation with a lowercase tail
    /// (`OSes`, `ТВшник`, `IPhone`) reads as a slip to this rule, which is why
    /// the engine also asks the dictionary (`ASlipHasAWordBehindItTests`).
    func testTheBoundaryThisRuleCannotDraw() {
        XCTAssertEqual(TypingHabits.corrected("OSes"), "Oses")
        XCTAssertEqual(TypingHabits.corrected("ТВшник"), "Твшник")
    }
}
