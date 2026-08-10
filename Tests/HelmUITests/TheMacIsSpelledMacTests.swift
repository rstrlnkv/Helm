import XCTest
@testable import HelmUI

/// The machine is called **Mac**, in every language.
///
/// Apple does not transliterate it — not in Russian, where the Cyrillic «мак»
/// is also the word for a poppy and reads as a common noun in the middle of a
/// sentence, and not anywhere else. Helm had drifted: «Как на маке», «на этом
/// маке», «на маках с 🌐︎» — three spellings of a product name in the file
/// whose other twenty-one mentions write `Mac`.
///
/// A rule nobody can see is a rule that comes back, and this one comes back
/// through the easiest door there is: somebody writing a natural Russian
/// sentence.
final class TheMacIsSpelledMacTests: XCTestCase {

    /// Cyrillic «мак» and its declensions, as a whole word. «Макет», «максимум»
    /// and «маркер» are ordinary words and must not be caught — the pattern
    /// ends the match at a word boundary after the endings that exist.
    private let transliterated = try! NSRegularExpression(
        pattern: "\\b[Мм]ак(а|е|ом|и|ах|ов|ам|ами)?\\b")

    func testNoTranslationSpellsTheMacInCyrillic() throws {
        var offenders: [String] = []
        for language in AppLanguage.allCases {
            for (key, value) in try entries(of: language) {
                let range = NSRange(value.startIndex..., in: value)
                guard transliterated.firstMatch(in: value, range: range) != nil else { continue }
                offenders.append("\(language.rawValue): \(key.prefix(48))… → \(value.prefix(64))…")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "the product is called Mac in every language Apple ships, and in "
                      + "Russian the transliteration is also the word for a poppy:\n"
                      + offenders.joined(separator: "\n"))
    }

    /// The control. A guard that finds nothing is indistinguishable from a
    /// guard that cannot look, and this one reads eight files off disk.
    func testTheScanReallyReadsTheTables() throws {
        let russian = try entries(of: .ru)
        XCTAssertGreaterThan(russian.count, 100, "the tables were not read at all")
        XCTAssertTrue(russian.values.contains { $0.contains("Mac") },
                      "no value mentions the Mac, so the check above cannot fail")
    }

    /// …and that the pattern catches what it is for, without catching the
    /// ordinary words that begin the same way.
    func testThePatternCatchesTheTransliterationAndNotOrdinaryWords() {
        for bad in ["Как на маке", "на этом маке", "на маках с 🌐︎", "Мак не спит"] {
            XCTAssertNotNil(transliterated.firstMatch(in: bad, range: NSRange(bad.startIndex..., in: bad)),
                            "missed: \(bad)")
        }
        for fine in ["Макет страницы", "максимум", "маркер", "Mac не спит"] {
            XCTAssertNil(transliterated.firstMatch(in: fine, range: NSRange(fine.startIndex..., in: fine)),
                         "caught an ordinary word: \(fine)")
        }
    }

    private func entries(of language: AppLanguage) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Localizable",
                              withExtension: "strings",
                              subdirectory: nil,
                              localization: language.rawValue),
            "no table for \(language.rawValue)")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }
}
