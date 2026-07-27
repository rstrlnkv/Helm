import XCTest
@testable import HelmRuntime

/// "Переместить 3 объектов" is broken Russian, and "Move 1 items" is broken
/// English. Counted nouns need the language's own rules.
final class PluralTests: XCTestCase {
    private func ru(_ n: Int) -> String { Plural.items(n, language: "ru") }

    func testRussianSingularForOneAndOneAfterTen() {
        XCTAssertEqual(ru(1), "1 объект")
        XCTAssertEqual(ru(21), "21 объект")
        XCTAssertEqual(ru(101), "101 объект")
    }

    func testRussianFewForTwoToFour() {
        XCTAssertEqual(ru(2), "2 объекта")
        XCTAssertEqual(ru(4), "4 объекта")
        XCTAssertEqual(ru(22), "22 объекта")
    }

    func testRussianManyForFiveAndUp() {
        XCTAssertEqual(ru(5), "5 объектов")
        XCTAssertEqual(ru(0), "0 объектов")
        XCTAssertEqual(ru(100), "100 объектов")
    }

    /// The teens are the trap: 11–14 take the "many" form despite ending in
    /// 1–4.
    func testRussianTeensTakeTheManyForm() {
        XCTAssertEqual(ru(11), "11 объектов")
        XCTAssertEqual(ru(12), "12 объектов")
        XCTAssertEqual(ru(14), "14 объектов")
        XCTAssertEqual(ru(111), "111 объектов")
    }

    func testEnglishHasTwoForms() {
        XCTAssertEqual(Plural.items(1, language: "en"), "1 item")
        XCTAssertEqual(Plural.items(2, language: "en"), "2 items")
        XCTAssertEqual(Plural.items(0, language: "en"), "0 items")
    }

    /// Languages without a count distinction still read correctly — and take
    /// no space before the counter.
    ///
    /// This assertion used to require one. macOS never writes it: its own
    /// tables say `%@項目`, `30日`, `%@项`, `30天`. The space was Helm's
    /// invention, applied consistently across eight branches, which is why it
    /// looked deliberate.
    func testUncountedLanguagesTakeNoSpaceBeforeTheCounter() {
        XCTAssertEqual(Plural.items(1, language: "ja"), "1項目")
        XCTAssertEqual(Plural.items(5, language: "zh"), "5个项目")
        XCTAssertEqual(Plural.days(30, language: "ja"), "30日")
        XCTAssertEqual(Plural.days(30, language: "zh"), "30天")
    }

    func testUnknownLanguageFallsBackToEnglish() {
        XCTAssertEqual(Plural.items(3, language: "xx"), "3 items")
    }
}
