import XCTest
@testable import HelmRuntime

/// The confirmation dialog counts files, and a dialog that says "2 файлов" is
/// the one place a language mistake looks like a broken app.
final class PluralFilesTests: XCTestCase {

    func testRussianTakesAllThreeForms() {
        XCTAssertEqual(Plural.files(1, language: "ru"), "1 файл")
        XCTAssertEqual(Plural.files(2, language: "ru"), "2 файла")
        XCTAssertEqual(Plural.files(4, language: "ru"), "4 файла")
        XCTAssertEqual(Plural.files(5, language: "ru"), "5 файлов")
        XCTAssertEqual(Plural.files(21, language: "ru"), "21 файл")
    }

    /// 11–14 take the many form whatever their last digit says — the case a
    /// naive `% 10` gets wrong.
    func testTheRussianTeensAreNotRegular() {
        XCTAssertEqual(Plural.files(11, language: "ru"), "11 файлов")
        XCTAssertEqual(Plural.files(12, language: "ru"), "12 файлов")
        XCTAssertEqual(Plural.files(14, language: "ru"), "14 файлов")
        XCTAssertEqual(Plural.files(112, language: "ru"), "112 файлов")
    }

    func testTheOtherLanguages() {
        XCTAssertEqual(Plural.files(1, language: "en"), "1 file")
        XCTAssertEqual(Plural.files(2, language: "en"), "2 files")
        XCTAssertEqual(Plural.files(1, language: "de"), "1 Datei")
        XCTAssertEqual(Plural.files(3, language: "de"), "3 Dateien")
        // French keeps the singular at zero, where English does not.
        XCTAssertEqual(Plural.files(0, language: "fr"), "0 fichier")
        XCTAssertEqual(Plural.files(0, language: "en"), "0 files")
    }
}

/// Counted rules, and counted days — the two the autopilot page prints.
///
/// Both shipped wrong: `"\(count) rules"` says "1 rules" for a new folder,
/// which is the common case, and the Russian day count said «1 дней»,
/// «2 дней», «22 дней» for every value.
final class PluralRulesAndDaysTests: XCTestCase {

    func testRussianRulesTakeAllThreeForms() {
        XCTAssertEqual(Plural.rules(1, language: "ru"), "1 правило")
        XCTAssertEqual(Plural.rules(2, language: "ru"), "2 правила")
        XCTAssertEqual(Plural.rules(5, language: "ru"), "5 правил")
        XCTAssertEqual(Plural.rules(11, language: "ru"), "11 правил")
        XCTAssertEqual(Plural.rules(21, language: "ru"), "21 правило")
    }

    /// The case that made this a bug rather than a nicety: a folder somebody
    /// just made has exactly one rule in it.
    func testOneRuleIsSingularEverywhere() {
        XCTAssertEqual(Plural.rules(1, language: "en"), "1 rule")
        XCTAssertEqual(Plural.rules(1, language: "de"), "1 Regel")
        XCTAssertEqual(Plural.rules(1, language: "es"), "1 regla")
        XCTAssertEqual(Plural.rules(1, language: "fr"), "1 règle")
        XCTAssertEqual(Plural.rules(1, language: "pt"), "1 regra")
        XCTAssertEqual(Plural.rules(2, language: "en"), "2 rules")
    }

    func testRussianDaysTakeAllThreeForms() {
        XCTAssertEqual(Plural.days(1, language: "ru"), "1 день")
        XCTAssertEqual(Plural.days(2, language: "ru"), "2 дня")
        XCTAssertEqual(Plural.days(7, language: "ru"), "7 дней")
        XCTAssertEqual(Plural.days(22, language: "ru"), "22 дня")
        XCTAssertEqual(Plural.days(30, language: "ru"), "30 дней")
    }

    func testOneDayIsSingularEverywhere() {
        XCTAssertEqual(Plural.days(1, language: "en"), "1 day")
        XCTAssertEqual(Plural.days(1, language: "fr"), "1 jour")
        XCTAssertEqual(Plural.days(1, language: "de"), "1 Tag")
        XCTAssertEqual(Plural.days(30, language: "de"), "30 Tage")
    }
}

/// The Russian byte, which has three forms where the table could hold one.
///
/// «2 байт» shipped because the two values the existing tests used — 1 and 512
/// — both take the same form as the plural. The middle form is the one nobody
/// exercised.
final class RussianBytesTests: XCTestCase {

    func testTheMiddleFormIsTheOneThatWasWrong() {
        XCTAssertEqual(HelmBytes.string(2, language: "ru"), "2 байта")
        XCTAssertEqual(HelmBytes.string(3, language: "ru"), "3 байта")
        XCTAssertEqual(HelmBytes.string(4, language: "ru"), "4 байта")
    }

    func testTheFormsThatWereAlreadyRight() {
        XCTAssertEqual(HelmBytes.string(1, language: "ru"), "1 байт")
        XCTAssertEqual(HelmBytes.string(5, language: "ru"), "5 байт")
        XCTAssertEqual(HelmBytes.string(512, language: "ru"), "512 байт")
        XCTAssertEqual(HelmBytes.string(21, language: "ru"), "21 байт")
    }

    /// Everything above a kilobyte is invariant, and must not have picked up
    /// the counted form on the way past.
    func testLargerUnitsAreUntouched() {
        XCTAssertTrue(HelmBytes.string(2_000, language: "ru").hasSuffix(" КБ"))
        XCTAssertTrue(HelmBytes.string(2_000_000, language: "ru").hasSuffix(" МБ"))
    }
}
