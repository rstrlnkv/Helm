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

    /// The other side of `testAKeyThatGenuinelyDiffersPerLanguageReadsCorrectlyEndToEnd`
    /// — proof that a fix lands in the *scalar* a person's Mac renders and not
    /// merely in the source file the guard reads. `HelmBasket.line` carries a
    /// French row with the unbreakable space `LayoutStrings.swift` already
    /// writes at its own French rows.
    func testFrenchInlineTableCarriesTheUnbreakableSpaceEndToEnd() {
        AppLanguage.only(.fr) {
            let rendered = HelmBasket.line(count: 1, size: "1 Ko")
            let scalars = Array(rendered.unicodeScalars)
            guard let colon = scalars.firstIndex(of: ":") else {
                XCTFail("no \":\" in the French render: \(rendered)")
                return
            }
            XCTAssertGreaterThan(colon, 0, "the render starts with \":\"")
            XCTAssertEqual(scalars[colon - 1], Unicode.Scalar(0x00A0)!,
                           "the scalar before \":\" in the French render is not U+00A0: \(rendered)")
        }
    }
}
