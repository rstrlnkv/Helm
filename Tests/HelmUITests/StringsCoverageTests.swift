import XCTest
import HelmTestSupport
@testable import HelmUI

/// The guard that used to walk inline tables in the source now reads the eight
/// `.lproj` files as data — those files are the artifact that ships, and a key
/// that never made it out of the migration is exactly the failure worth
/// catching. An inline table has no `.lproj` file to be missing from, so it
/// gets its own coverage test below, read through `InlineTables` rather than
/// reflected.
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

    /// The inline-table half of `testEveryEnglishKeyExistsInEveryOtherLanguage`
    /// — English is not required, since an inline table has no `.en` row to
    /// diff against, but it is still counted for the duplicate check: a
    /// second `.en` row compiles and traps at the dictionary literal's first
    /// read, the same as a second `.ru` would, and excluding it from `seen`
    /// let a table hold `.en` twice and pass.
    func testEveryInlineTableCarriesTheSevenLanguages() throws {
        let tables = try InlineTables.tables(under: "Sources")
        XCTAssertGreaterThanOrEqual(tables.count, InlineTables.floor,
                                    "only \(tables.count) table(s) found — InlineTables is not reading Sources")
        let required = Set(AppLanguage.allCases).subtracting([.en])
        var offenders: [String] = []
        for table in tables {
            var seen: Set<AppLanguage> = []
            for row in table.rows {
                if !seen.insert(row.language).inserted {
                    offenders.append("\(table.path):\(row.line) carries \(row.language.rawValue) twice")
                }
            }
            let missing = required.subtracting(seen)
            guard !missing.isEmpty else { continue }
            offenders.append("\(table.path):\(table.line) is missing "
                            + missing.map(\.rawValue).sorted().joined(separator: ", "))
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) inline table(s) do not carry all seven non-English languages:\n"
                      + offenders.sorted().joined(separator: "\n"))
    }

    /// The inline-table half of `testNoTranslationIsEmpty`. A row's `literals`
    /// can legitimately be `[]` — `.ru: ru` names a variable, not a string —
    /// and that is not the same fact as a row whose literal is there and reads
    /// `""`, which is what this asks about.
    func testNoInlineTableRowIsEmpty() throws {
        let tables = try InlineTables.tables(under: "Sources")
        XCTAssertGreaterThanOrEqual(tables.count, InlineTables.floor,
                                    "only \(tables.count) table(s) found — InlineTables is not reading Sources")
        var offenders: [String] = []
        for table in tables {
            for row in table.rows where !row.literals.isEmpty
                && row.literals.allSatisfy({ $0.value.isEmpty }) {
                offenders.append("\(table.path):\(row.line) \(row.language.rawValue) is empty")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) inline table row(s) are empty:\n"
                      + offenders.sorted().joined(separator: "\n"))
    }
}
