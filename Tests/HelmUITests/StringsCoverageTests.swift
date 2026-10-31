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

    /// **The modules' catalogs, which the `.lproj` tests above cannot see.** A catalog is
    /// `Sources/Modules/<Name>/UI/Localizable.xcstrings`, its symbols are internal to its target and
    /// its keys are identifiers, so the kit's `.lproj` walk has nothing to say about it. This reads
    /// the file: all eight languages, none empty, and none marked anything but `translated` — a
    /// catalog editor writes «needs_review» for a value somebody has not looked at, and the build
    /// ships it all the same.
    func testEveryCatalogSymbolCarriesTheEightLanguages() throws {
        let catalogs = try ModuleCatalogs.all()
        XCTAssertFalse(catalogs.isEmpty, "no module catalog was found — ModuleCatalogs is not reading Sources/Modules")
        var offenders: [String] = []
        var symbols = 0
        for catalog in catalogs {
            XCTAssertFalse(catalog.strings.isEmpty, "\(catalog.path) carries no symbols")
            for (symbol, values) in catalog.strings {
                symbols += 1
                for language in AppLanguage.allCases {
                    guard let value = values[language.rawValue] else {
                        offenders.append("\(catalog.module).\(symbol): no \(language.rawValue)")
                        continue
                    }
                    if value.isEmpty { offenders.append("\(catalog.module).\(symbol): empty \(language.rawValue)") }
                    let state = catalog.states[symbol]?[language.rawValue] ?? ""
                    if state != "translated" {
                        offenders.append("\(catalog.module).\(symbol): \(language.rawValue) is «\(state)»")
                    }
                }
            }
        }
        XCTAssertGreaterThan(symbols, 0)
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) catalog value(s) are missing or unfinished:\n"
                      + offenders.sorted().prefix(40).joined(separator: "\n"))
    }

    /// **A catalog key that holds `%@` holds it in every language.** `testEveryCatalogSymbolCarriesTheEightLanguages`
    /// asks that a value is there, is not empty and is marked `translated`; a translation that lost its `%@` is all three, reads fine, and
    /// drops the timer's value or, for Screenshots' `nameTemplate`, the time from a saved file's name, since `String(format:)` fills what is left from the date on. Each
    /// language's count of `%@` is held to the English value's, and the walk must have met the two
    /// Screenshots keys that carry them, or it saw nothing.
    func testEveryCatalogLanguageKeepsTheEnglishPlaceholders() throws {
        func count(_ text: String) -> Int { text.components(separatedBy: "%@").count - 1 }
        var offenders: [String] = []
        var met: Set<String> = []
        for catalog in try ModuleCatalogs.all() {
            for (symbol, values) in catalog.strings {
                guard let english = values["en"] else { continue }
                let expected = count(english)
                if expected > 0 { met.insert("\(catalog.module).\(symbol)") }
                for language in AppLanguage.allCases {
                    let got = values[language.rawValue].map(count) ?? 0
                    if got != expected {
                        offenders.append("\(catalog.module).\(symbol): \(language.rawValue) has \(got) «%@», en has \(expected)")
                    }
                }
            }
        }
        XCTAssertTrue(met.isSuperset(of: ["Screenshots.timerOn", "Screenshots.nameTemplate"]),
                      "the walk did not meet Screenshots' %@ keys; met: \(met.sorted())")
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) catalog value(s) differ from English in their %@ count:\n"
                      + offenders.sorted().prefix(40).joined(separator: "\n"))
    }

    /// A word in a module's catalog and in the kit's `.lproj` is two translations of one English
    /// text, free to drift apart — and a catalog's symbols are internal, so the other module cannot
    /// reach the catalog's copy. A shared word lives in the kit, and `ModuleCatalogs.tableByEnglish`
    /// refuses the same English in two catalogs.
    func testNoWordLivesInTheKitAndInAModuleCatalog() throws {
        let kit = Set(table(for: .en).keys)
        let both = try ModuleCatalogs.tableByEnglish(for: .en).keys.filter { kit.contains($0) }.sorted()
        XCTAssertTrue(both.isEmpty,
                      "\(both.count) English text(s) are in the kit and in a module catalog: "
                      + both.prefix(10).joined(separator: ", "))
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
