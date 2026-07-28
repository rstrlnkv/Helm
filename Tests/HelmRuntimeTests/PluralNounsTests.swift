import XCTest
@testable import HelmRuntime

/// The four counted nouns the suite never checked.
///
/// `PluralTests` sweeps `items` thoroughly and leaves `apps`, `files`, `rules`
/// and `days` untested. Each carries its own Russian triple, written out by
/// hand at the call site, and a wrong triple is invisible to anyone who does
/// not read Russian — the exact class of defect the comment on `Plural.files`
/// records ("2 файлов" reads as a bug in the dialog that must not look buggy).
///
/// The teens are the trap in every one of them: 11–14 take the "many" form
/// whatever their final digit says, so 11 must not read like 1 and 12 must not
/// read like 2.
final class PluralNounsTests: XCTestCase {

    func testRussianAppsTakeAllThreeForms() {
        XCTAssertEqual(Plural.apps(1, language: "ru"), "1 приложение")
        XCTAssertEqual(Plural.apps(2, language: "ru"), "2 приложения")
        XCTAssertEqual(Plural.apps(5, language: "ru"), "5 приложений")
        XCTAssertEqual(Plural.apps(0, language: "ru"), "0 приложений")
    }

    func testRussianFilesTakeAllThreeForms() {
        XCTAssertEqual(Plural.files(1, language: "ru"), "1 файл")
        XCTAssertEqual(Plural.files(3, language: "ru"), "3 файла")
        XCTAssertEqual(Plural.files(7, language: "ru"), "7 файлов")
    }

    func testRussianRulesTakeAllThreeForms() {
        XCTAssertEqual(Plural.rules(1, language: "ru"), "1 правило")
        XCTAssertEqual(Plural.rules(4, language: "ru"), "4 правила")
        XCTAssertEqual(Plural.rules(9, language: "ru"), "9 правил")
    }

    func testRussianDaysTakeAllThreeForms() {
        XCTAssertEqual(Plural.days(1, language: "ru"), "1 день")
        XCTAssertEqual(Plural.days(2, language: "ru"), "2 дня")
        XCTAssertEqual(Plural.days(30, language: "ru"), "30 дней")
    }

    /// 11–14 in every noun, not only in `items`.
    func testRussianTeensTakeTheManyFormInEveryNoun() {
        XCTAssertEqual(Plural.apps(11, language: "ru"), "11 приложений")
        XCTAssertEqual(Plural.files(12, language: "ru"), "12 файлов")
        XCTAssertEqual(Plural.rules(13, language: "ru"), "13 правил")
        XCTAssertEqual(Plural.days(14, language: "ru"), "14 дней")
        // …and 111–114, which is the same rule two orders of magnitude up.
        XCTAssertEqual(Plural.files(112, language: "ru"), "112 файлов")
    }

    /// A count is never dropped, and a language never falls through to an
    /// empty word. Structural: whatever the language does with the noun, the
    /// number has to be in the string.
    func testEveryLanguageCarriesTheNumberAndANoun() {
        let counters: [(String, (Int, String) -> String)] = [
            ("items", Plural.items), ("apps", Plural.apps), ("files", Plural.files),
            ("rules", Plural.rules), ("days", Plural.days),
        ]
        for (name, counter) in counters {
            for language in ["en", "ru", "es", "fr", "de", "pt", "ja", "zh"] {
                for count in [0, 1, 2, 5, 11, 21, 101] {
                    let text = counter(count, language)
                    XCTAssertTrue(text.contains("\(count)"),
                                  "\(name)/\(language)/\(count): the number is missing from \"\(text)\"")
                    XCTAssertGreaterThan(text.count, "\(count)".count,
                                         "\(name)/\(language)/\(count): no noun in \"\(text)\"")
                }
            }
        }
    }
}
