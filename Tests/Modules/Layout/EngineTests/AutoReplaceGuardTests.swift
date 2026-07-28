import XCTest
@testable import Module_Layout_Engine

/// The two entries `AutoReplace` promises never to store.
///
/// Its initialiser states the rule and the reason: "An entry that expands to
/// itself fires forever; one that expands to nothing deletes a word somebody
/// typed. Neither is stored, so the engine never has to know they were
/// possible." The engine takes that promise literally — `replaceWord` hands
/// whatever comes back to `SwitchPlan.make`, whose only test of a replacement
/// is `!replacement.isEmpty`.
final class AutoReplaceGuardTests: XCTestCase {

    /// The trap: an expansion made of whitespace.
    ///
    /// `!entry.to.isEmpty` is a test of the string's length, not of whether it
    /// has anything in it. `from` is trimmed before it is compared and stored;
    /// `to` is not, at either end — the settings page guards the Add button with
    /// `newLong.isEmpty` on the raw text, so a space typed into the expansion
    /// field is accepted, saved and loaded back.
    ///
    /// What the engine then does with it is precisely the outcome the guard
    /// names: the word is deleted and nothing legible is typed in its place.
    /// Somebody types `brb`, presses space, and watches their word disappear.
    func testAnExpansionOfNothingButWhitespaceIsNotStored() {
        for blank in [" ", "   ", "\t", "\n", " \t "] {
            let table = AutoReplace(entries: [AutoReplace.Entry(from: "brb", to: blank)])
            XCTAssertNil(table.expansion(for: "brb"),
                         "an expansion of \(blank.debugDescription) deletes the word and "
                         + "types whitespace over it")
        }
    }

    /// The other half of the same asymmetry. `to` is compared against the
    /// *trimmed* `from`, so padding one side is enough to slip an entry that
    /// expands to itself past the check — and an expansion that only adds
    /// whitespace still costs the word: `brb` and a space become `brb` and two.
    func testAnExpansionThatIsTheWordWithPaddingIsNotStored() {
        for padded in ["brb ", " brb", " brb "] {
            let table = AutoReplace(entries: [AutoReplace.Entry(from: "brb", to: padded)])
            XCTAssertNil(table.expansion(for: "brb"),
                         "\(padded.debugDescription) is the word it replaces")
        }
    }

    /// The control: an ordinary entry, and one whose expansion legitimately
    /// carries inner spaces, are both kept. The rule is about entries with
    /// nothing in them, not about entries with spaces in them.
    func testOrdinaryEntriesAreUntouched() {
        let table = AutoReplace(entries: [
            AutoReplace.Entry(from: "brb", to: "be right back"),
            AutoReplace.Entry(from: "адр", to: "ул. Ленина, 1"),
        ])
        XCTAssertEqual(table.expansion(for: "brb"), "be right back")
        XCTAssertEqual(table.expansion(for: "адр"), "ул. Ленина, 1")
    }
}
