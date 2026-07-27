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
