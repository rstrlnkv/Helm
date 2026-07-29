import XCTest
import HelmRuntime
@testable import Module_Autopilot_Engine

/// «старше» and «новее» govern the genitive. `Plural.days` answers in the
/// nominative — right where the phrase stands alone ("30 дней" as a count),
/// wrong in the two places a rule is actually read: the condition row and the
/// rule summary both put the unit directly after one of those two words, and
/// they read «старше 1 день» and «старше 2 дня».
///
/// Parameterised by language rather than reading `AppLanguage.current`, so the
/// assertion is about the grammar and not about the machine the suite runs on.
final class DayUnitTests: XCTestCase {

    /// Genitive singular after one, genitive plural after everything else —
    /// including 2–4, where the nominative would say «дня». The 11–14 exception
    /// is the one that catches a rule of thumb written from the last digit.
    func test_russian_after_a_comparison_is_genitive() {
        let expected: [Int: String] = [
            1: "дня", 2: "дней", 3: "дней", 4: "дней", 5: "дней",
            11: "дней", 12: "дней", 14: "дней",
            21: "дня", 22: "дней", 30: "дней", 101: "дня", 111: "дней",
        ]
        for (n, word) in expected {
            XCTAssertEqual(DayUnit.afterComparison(n, language: "ru"), "\(n) \(word)",
                           "старше \(n) …")
        }
    }

    /// Nothing else of the eight inflects after its comparison, so every other
    /// language must be exactly what it already said — this must not become a
    /// second, drifting copy of `Plural.days`.
    func test_every_other_language_is_unchanged() {
        for language in ["en", "es", "fr", "de", "ja", "zh", "pt"] {
            for n in [0, 1, 2, 5, 11, 21, 100] {
                XCTAssertEqual(DayUnit.afterComparison(n, language: language),
                               Plural.days(n, language: language), "\(language) \(n)")
            }
        }
    }

    /// The bare word for the editor row, which draws the number in a field of
    /// its own — the same agreement, with the numeral taken back off.
    func test_the_bare_word_carries_the_same_agreement() {
        XCTAssertEqual(DayUnit.wordAfterComparison(1, language: "ru"), "дня")
        XCTAssertEqual(DayUnit.wordAfterComparison(2, language: "ru"), "дней")
        XCTAssertEqual(DayUnit.wordAfterComparison(30, language: "ru"), "дней")
        XCTAssertEqual(DayUnit.wordAfterComparison(1, language: "en"), "day")
        XCTAssertEqual(DayUnit.wordAfterComparison(30, language: "en"), "days")
        XCTAssertEqual(DayUnit.wordAfterComparison(2, language: "de"), "Tage")
    }

    /// A rule's day count comes out of a plist any process can write, and
    /// `Int(Double.infinity)` is a trap rather than an error — the crash
    /// `RuleSummary.number` already documents, one function over. Nothing here
    /// may be reachable with a number that cannot be counted.
    func test_a_count_no_rule_could_mean_does_not_trap() {
        for value in [Double.infinity, -.infinity, .nan, 1e30, -1e30] {
            XCTAssertFalse(DayUnit.afterComparison(value, language: "ru").isEmpty, "\(value)")
            XCTAssertFalse(DayUnit.wordAfterComparison(value, language: "ru").isEmpty, "\(value)")
        }
    }
}
