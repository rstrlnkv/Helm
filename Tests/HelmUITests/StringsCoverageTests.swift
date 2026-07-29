import XCTest
@testable import HelmUI

/// The guard that used to walk inline tables in the source now reads the eight
/// `.lproj` files as data — those files are the artifact that ships, and a key
/// that never made it out of the migration is exactly the failure worth
/// catching.
///
/// Read through `Localized.stringsFile(for:)` rather than `Bundle.module`:
/// inside a test target `Bundle.module` resolves to the test's own bundle, not
/// `HelmUI`'s, so it is never the right way to ask what `HelmUI` ships.
final class StringsCoverageTests: XCTestCase {

    private func table(for language: AppLanguage) -> [String: String] {
        guard let path = Localized.stringsFile(for: language)?.path,
              let dict = NSDictionary(contentsOfFile: path) as? [String: String]
        else {
            XCTFail("no Localizable.strings for \(language.rawValue)")
            return [:]
        }
        return dict
    }

    /// `en.lproj` is not consulted at runtime — `L()` never asks it, since
    /// English is the key itself — but it is what a translator diffs against,
    /// and it is the full key set every other language is measured against.
    func testEveryEnglishKeyExistsInEveryOtherLanguage() {
        let english = table(for: .en)
        XCTAssertFalse(english.isEmpty, "en.lproj carries no keys at all")
        for language in AppLanguage.allCases where language != .en {
            let translated = table(for: language)
            let missing = Set(english.keys).subtracting(translated.keys)
            XCTAssertTrue(missing.isEmpty,
                          "\(language.rawValue) is missing \(missing.count) key(s): \(missing.sorted().prefix(5))")
        }
    }

    func testNoTranslationIsEmpty() {
        for language in AppLanguage.allCases {
            for (key, value) in table(for: language) {
                XCTAssertFalse(value.isEmpty, "\(language.rawValue) has an empty value for \(key.prefix(60))")
            }
        }
    }

    /// One key, read end to end through the same lookup `L()` uses, for a key
    /// whose eight languages are genuinely different words rather than the
    /// same one recopied. "When" is the cleanest of the seventeen splits this
    /// migration resolved: German alone tells "Wenn" (conditions) from "Wann"
    /// (timing), and every other language answers it with its own distinct
    /// word — «Когда», "Cuando", "Quand", "条件", "当", "Quando".
    func testAKeyThatGenuinelyDiffersPerLanguageReadsCorrectlyEndToEnd() {
        let expected: [AppLanguage: String] = [
            .en: "When", .ru: "Когда", .es: "Cuando", .fr: "Quand", .de: "Wenn",
            .ja: "条件", .zh: "当", .pt: "Quando",
        ]
        for (language, want) in expected {
            XCTAssertEqual(L("When", language: language), want,
                           "\(language.rawValue) did not read back what the .lproj file carries")
        }
        // Confirm they are not all the same word wearing different bytes.
        XCTAssertEqual(Set(expected.values).count, expected.values.count,
                       "the eight languages should not have collapsed onto fewer distinct words")
    }
}
