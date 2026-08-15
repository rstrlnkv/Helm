import XCTest
@testable import HelmRuntime

/// A five-digit count is read by counting its digits unless the language groups
/// them — which is the one thing a magnitude is not for (`HelmBytes.grouped`
/// says the same about scan totals). `Plural` interpolated the raw `Int` into
/// all eight languages, so the Disk basket's confirmation said "Переместить в
/// Корзину 12345 файлов" over exactly the batch big enough to deserve reading.
///
/// Structural on purpose: the assertion is "a separator stands between the
/// digit groups", never "the string equals what `HelmBytes.grouped` answers" —
/// a test whose two sides read one shared constant cannot fail
/// (ARCHITECTURE.md § A check that cannot fail is not a check).
final class PluralGroupingTests: XCTestCase {

    /// The eight the switch in `Plural` spells, including the `default` arm.
    private let languages = ["en", "ru", "es", "fr", "de", "pt", "ja", "zh"]

    /// Every counted noun, by name, so a mutation that ungroups one form fails
    /// on that form rather than hiding behind the others.
    private let forms: [(name: String, spell: (Int, String) -> String)] = [
        ("items", Plural.items),
        ("apps", Plural.apps),
        ("files", Plural.files),
        ("rules", Plural.rules),
        ("days", Plural.days),
    ]

    func testAFiveDigitCountArrivesGrouped() {
        for language in languages {
            for form in forms {
                let sentence = form.spell(12345, language)
                XCTAssertNil(sentence.range(of: "12345"),
                             "Plural.\(form.name)(12345, \(language)) says «\(sentence)» — "
                             + "five ungrouped digits, read by counting them")
                XCTAssertNotNil(sentence.range(of: "12[^0-9]345", options: .regularExpression),
                                "Plural.\(form.name)(12345, \(language)) says «\(sentence)» — "
                                + "the digit groups are not both there with a separator between")
            }
        }
    }

    /// The common case must stay exactly as the value tests beside this file
    /// pin it: grouping starts at four digits, so a basket of 21 reads as it
    /// always did.
    func testASmallCountIsUntouched() {
        for language in languages {
            for form in forms {
                let sentence = form.spell(21, language)
                XCTAssertNotNil(sentence.range(of: "21"),
                                "Plural.\(form.name)(21, \(language)) says «\(sentence)»")
            }
        }
    }
}
