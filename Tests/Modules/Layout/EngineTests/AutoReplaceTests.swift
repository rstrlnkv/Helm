import XCTest
@testable import Module_Layout_Engine

/// The two things that happen at a word boundary besides a layout conversion:
/// an abbreviation expanding, and a typing habit being corrected.
///
/// Both are edits nobody asked for at the moment they happen, which is the same
/// standing the layout conversion has — so they answer to the same rule: only
/// when the module is sure, and never in a way that has to be undone twice.
final class AutoReplaceTests: XCTestCase {

    private func table(_ pairs: [String: String]) -> AutoReplace {
        AutoReplace(entries: pairs.map { AutoReplace.Entry(from: $0.key, to: $0.value) })
    }

    // MARK: - Abbreviations

    func testAnAbbreviationExpands() {
        let auto = table(["адр": "Ленина 5, кв. 3", "eml": "me@example.com"])
        XCTAssertEqual(auto.expansion(for: "адр"), "Ленина 5, кв. 3")
        XCTAssertEqual(auto.expansion(for: "eml"), "me@example.com")
    }

    func testAWordThatIsNotAnAbbreviationIsLeftAlone() {
        let auto = table(["адр": "Ленина 5"])
        XCTAssertNil(auto.expansion(for: "адрес"))
        XCTAssertNil(auto.expansion(for: "др"))
        XCTAssertNil(auto.expansion(for: ""))
    }

    /// Case-sensitive, unlike the exceptions list. An abbreviation is a token
    /// somebody invented — `ООО` and `ооо` can reasonably be two different
    /// things, and folding them together makes the shorter one unusable.
    func testAbbreviationsAreCaseSensitive() {
        let auto = table(["ООО": "Общество с ограниченной ответственностью"])
        XCTAssertNotNil(auto.expansion(for: "ООО"))
        XCTAssertNil(auto.expansion(for: "ооо"))
    }

    /// An entry that expands to itself, or to nothing, is a rule that fires
    /// forever or deletes a word. Neither is stored.
    func testDegenerateEntriesAreRefused() {
        let auto = table(["x": "x", "y": "", "": "z"])
        XCTAssertNil(auto.expansion(for: "x"))
        XCTAssertNil(auto.expansion(for: "y"))
        XCTAssertNil(auto.expansion(for: ""))
    }

    // MARK: - Typing habits

    /// The classic: a capital held a moment too long. `ПРивет` is a slip;
    /// `ПРИВЕТ` is a decision, and correcting that would be rewriting somebody
    /// shouting on purpose.
    func testTwoLeadingCapitals() {
        XCTAssertEqual(TypingHabits.corrected("ПРивет"), "Привет")
        XCTAssertEqual(TypingHabits.corrected("HEllo"), "Hello")
        XCTAssertNil(TypingHabits.corrected("ПРИВЕТ"))
        XCTAssertNil(TypingHabits.corrected("Привет"))
        XCTAssertNil(TypingHabits.corrected("привет"))
    }

    /// Two letters is the whole word: `ПРивет` has a third to prove the intent,
    /// `ПР` does not — it is an abbreviation as often as a slip.
    func testTwoLettersIsNotEnoughToBeSure() {
        XCTAssertNil(TypingHabits.corrected("ПР"))
        XCTAssertNil(TypingHabits.corrected("OK"))
    }

    /// Anything with a digit in it is an identifier, not prose: `IPv6`, `PDf24`.
    func testWordsWithDigitsAreLeftAlone() {
        XCTAssertNil(TypingHabits.corrected("IPv6"))
        XCTAssertNil(TypingHabits.corrected("MP3file"))
    }

    /// A word Helm would also want to convert must not be corrected on the way:
    /// two edits to one word is one edit the person cannot undo in one press.
    func testTheCorrectionIsOnlyEverOneChange() {
        XCTAssertEqual(TypingHabits.corrected("ГГород"), "Ггород",
                       "the rule lowercases the second letter and nothing else")
    }
}
