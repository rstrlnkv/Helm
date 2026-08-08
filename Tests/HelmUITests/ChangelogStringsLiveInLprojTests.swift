import XCTest
@testable import HelmUI

/// The changelog's strings belong in the eight `.lproj` files like every other
/// string in the app.
///
/// CLAUDE.md allows exactly one exception to that: **only a Swift-interpolated
/// string keeps an inline table, because interpolation runs before the lookup**.
/// Twenty changelog entries carried a table anyway, none of them interpolated —
/// and a table at the call site is outside everything the `.lproj` files are
/// guarded by. `StringsCoverageTests` never saw them, so a language could be
/// missing from one and nothing said so; one entry shipped English to six
/// languages for exactly that reason.
///
/// Source-scanned rather than reflected, the way `NoOrphanTranslationsTests`
/// does it: a table is a fact about the text somebody typed, and there is no
/// runtime object to ask.
final class ChangelogStringsLiveInLprojTests: XCTestCase {

    private var changelogSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // HelmUITests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // repo
                .appendingPathComponent("Sources/HelmApp/ChangelogData.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Every `L("…")` in the file, with whether a table follows the literal.
    ///
    /// Walked character by character rather than matched with a pattern: the
    /// entries are long, hold quotes of their own, and one of them carries an
    /// escaped `\"` — every shortcut that reads to the next `"` splits an entry
    /// in the middle and then measures the halves.
    private func callSites(in source: String) -> [(literal: String, hasTable: Bool)] {
        var found: [(String, Bool)] = []
        var rest = Substring(source)
        while let call = rest.range(of: "L(\"") {
            var index = call.upperBound
            var literal = ""
            while index < rest.endIndex, rest[index] != "\"" {
                if rest[index] == "\\" {
                    literal.append(rest[index])
                    index = rest.index(after: index)
                    guard index < rest.endIndex else { break }
                }
                literal.append(rest[index])
                index = rest.index(after: index)
            }
            guard index < rest.endIndex else { break }
            let after = rest[rest.index(after: index)...].prefix { $0 == "," || $0 == " " }
            found.append((literal, after.contains(",")))
            rest = rest[rest.index(after: index)...]
        }
        return found
    }

    func testNoChangelogEntryKeepsATableUnlessItIsInterpolated() throws {
        let sites = callSites(in: try changelogSource)
        XCTAssertGreaterThan(sites.count, 20,
                             "only \(sites.count) L() call sites were found, so a pass means "
                             + "nothing — the scanner is reading the file wrong")

        let tabled = sites.filter { $0.hasTable && !$0.literal.contains("\\(") }
        XCTAssertTrue(tabled.isEmpty,
                      "\(tabled.count) changelog entr(ies) carry an inline table with no "
                      + "interpolation to justify it. The eight .lproj files are where they "
                      + "belong, and StringsCoverageTests only guards what is in them:\n"
                      + tabled.map { "  \"\($0.literal.prefix(60))…\"" }.joined(separator: "\n"))
    }

    /// The other half, which passes today and has to keep passing: a translation
    /// that is its own key is English wearing another language's name.
    ///
    /// Twenty characters, because the short keys really do coincide — "VPN",
    /// "S", "M", "L", "Homebrew", "Helm" are the same in eight languages, and a
    /// sentence is not.
    func testNoLongTranslationIsJustTheEnglishAgain() throws {
        var untranslated: [(AppLanguage, String)] = []
        for language in AppLanguage.allCases where language != .en {
            let path = try XCTUnwrap(Localized.stringsFile(for: language)?.path)
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
            XCTAssertGreaterThan(table.count, 100, "\(language.rawValue).lproj carries almost nothing")
            for (key, value) in table where key.count >= 20 && key == value {
                untranslated.append((language, key))
            }
        }
        XCTAssertTrue(untranslated.isEmpty,
                      "\(untranslated.count) long key(s) are shipped as their own English:\n"
                      + untranslated
                        .map { "  \($0.0.rawValue): \"\($0.1.prefix(60))…\"" }
                        .joined(separator: "\n"))
    }
}
