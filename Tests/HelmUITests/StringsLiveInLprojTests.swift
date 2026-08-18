import XCTest
@testable import HelmUI

/// Every string belongs in the eight `.lproj` files, and a translation that is
/// its own key is English wearing another language's name.
///
/// CLAUDE.md allows exactly one exception to the first: **only a
/// Swift-interpolated string keeps an inline table, because interpolation runs
/// before the lookup**. Twenty changelog entries carried a table anyway, none of
/// them interpolated — and a table at the call site is outside everything the
/// `.lproj` files are guarded by. `StringsCoverageTests` never saw them, so a
/// language could be missing from one and nothing said so; one entry shipped
/// English to six languages for exactly that reason. Two more outlived that
/// sweep because this test only read `ChangelogData.swift`: `AppStr.authorName`,
/// whose table had one row and six languages simply absent, and
/// `VPNStr.separator`, seven rows of which six only said what English says. It
/// reads the whole of `Sources` now, which is also one fewer hand-written list
/// of files to keep in step with the tree.
///
/// Source-scanned rather than reflected, the way `NoOrphanTranslationsTests`
/// does it: a table is a fact about the text somebody typed, and there is no
/// runtime object to ask.
///
/// (Was `ChangelogStringsLiveInLprojTests`, when the changelog was the only
/// thing it looked at.)
final class StringsLiveInLprojTests: XCTestCase {

    private var swiftSources: [(path: String, text: String)] {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // HelmUITests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // repo
                .appendingPathComponent("Sources")
            var found: [(String, String)] = []
            let walker = try XCTUnwrap(FileManager.default.enumerator(at: root,
                                                                     includingPropertiesForKeys: nil))
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append((url.lastPathComponent,
                              try String(contentsOf: url, encoding: .utf8)))
            }
            return found
        }
    }

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = try XCTUnwrap(Localized.stringsFile(for: language)?.path)
        let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        XCTAssertGreaterThan(table.count, 100, "\(language.rawValue).lproj carries almost nothing")
        return table
    }

    /// Every `L("…")` in a source, with whether a table follows the literal.
    ///
    /// Walked character by character rather than matched with a pattern: the
    /// changelog entries are long, hold quotes of their own, and one of them
    /// carries an escaped `\"` — every shortcut that reads to the next `"`
    /// splits an entry in the middle and then measures the halves.
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
            // A table, not merely a second argument: skip the whitespace after
            // the comma — a long table is written on the next line — and require
            // the bracket that opens one.
            var tail = rest[rest.index(after: index)...]
            var tabled = false
            if tail.first == "," {
                tail = tail.dropFirst().drop(while: \.isWhitespace)
                tabled = tail.first == "["
            }
            found.append((literal, tabled))
            rest = rest[rest.index(after: index)...]
        }
        return found
    }

    /// The scanner's own check, because it decides what every other assertion
    /// here sees. "A comma follows the literal" is not "a table follows the
    /// literal": `L("Connected", language: language)` is the form every
    /// localization test uses to ask about a language other than this
    /// machine's, and it was being read as tabled — so the guard would have
    /// excused a real table at any call site that named its language, and
    /// complained about one that carried none.
    func testACallSiteThatNamesALanguageIsNotATable() {
        let source = """
        let a = L("Connected", language: language)
        let b = L("Connected", [.ru: "Подключено"])
        let c = L("Connected",
                  [.ru: "Подключено"])
        let d = L("Connected")
        """
        XCTAssertEqual(callSites(in: source).map(\.hasTable), [false, true, true, false])
    }

    func testNoStringKeepsAnInlineTableUnlessItIsInterpolated() throws {
        var scanned = 0
        var tabled: [(file: String, literal: String)] = []
        for (path, text) in try swiftSources {
            let sites = callSites(in: text)
            scanned += sites.count
            for site in sites where site.hasTable && !site.literal.contains("\\(") {
                tabled.append((path, site.literal))
            }
        }
        XCTAssertGreaterThan(scanned, 500,
                             "only \(scanned) L() call sites were found in the whole of Sources, "
                             + "so a pass means nothing — the walk or the scanner is wrong")

        XCTAssertTrue(tabled.isEmpty,
                      "\(tabled.count) string(s) carry an inline table with no interpolation to "
                      + "justify it. The eight .lproj files are where they belong, and "
                      + "StringsCoverageTests only guards what is in them:\n"
                      + tabled.map { "  \($0.file): \"\($0.literal.prefix(60))…\"" }
                        .joined(separator: "\n"))
    }

    /// Where a language ships a key back as its own value, on purpose.
    ///
    /// Every entry here is a decision somebody made and can be argued with;
    /// that is the point of writing them down. It replaced a length threshold —
    /// "fail if the key is 20 characters or more" — which did no work at all:
    /// the longest legitimate identity in the tree is `Notification` at twelve,
    /// so the rule fired on none of the fifty-five below, while `Show all`,
    /// `Widget size` and `Close tab` could have shipped untranslated in all
    /// seven and passed. A threshold hides the decision; a list makes it.
    ///
    /// Per language, not per key, because `Notification` is French and German's
    /// own word for it is `Mitteilung`: an identity is legitimate in the
    /// languages that were checked, not everywhere the spelling could occur.
    private static let deliberateIdentities: [String: Set<AppLanguage>] = [
        "1 module": [.fr],
        "App": [.es, .fr, .de, .pt],
        "Apps": [.es, .fr, .de, .pt],
        "Archive": [.fr],
        "Audio": [.es, .fr, .de],
        "Auto": [.fr],
        "Autopilot": [.de],
        "BETA": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Beta": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "BUILD": [.fr, .de, .pt],
        "Caches": [.fr, .de, .pt],
        // German borrowed the word whole; Duden lists «Filter» and nothing else
        // for the sense a list menu means.
        "Filter": [.de],
        "Capsule": [.fr],
        "cask": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Cookies": [.ru, .es, .fr, .de, .pt],
        // The four modifier-key names are macOS's own words, read from
        // AppKit's FunctionKeyNames.loctable rather than translated: ru and zh
        // keep all four in English there; ja keeps three («shift» differs by
        // its case); es keeps «Control», fr keeps «Option», pt keeps «Shift».
        "Command": [.ru, .ja, .zh],
        "Control": [.ru, .es, .ja, .zh],
        "Option": [.ru, .fr, .ja, .zh],
        "Shift": [.ru, .pt, .zh],
        "Cyan": [.fr, .de],
        "DEV": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Dev": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Document": [.fr],
        // The log row's spoken level. Spanish spells it the way English does —
        // «Error» is the RAE's word and the one this file's own «Errors» =
        // «Errores» is the plural of.
        "Error": [.es],
        "Extension": [.fr],
        "General": [.es],
        "h": [.es, .fr, .pt],
        "Hardware": [.es, .de, .pt],
        "Homebrew": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        // The networking sense of «host» is a loanword in these three and takes
        // the English plural in all of them, so the sidebar's short name comes
        // out identical while the module's full name does not — «Hosts &
        // Schlüssel», «Hosts y claves», «Hosts e chaves». French and the four
        // non-Latin scripts have a word of their own and use it.
        "Hosts": [.es, .de, .pt],
        "Image": [.fr],
        "m": [.es, .fr, .pt],
        "Manual": [.es, .pt],
        "MB": [.es, .de, .ja, .zh, .pt],
        // The tunnel strip's unit, and the identity is inherited rather than
        // new: all eight already shipped it inside «Speed, Mbit/s», which
        // splitting that key into a plain label and a unit turned from a
        // sentence into six identities and put in front of this list. macOS
        // spells the same quantity differently and is not the answer —
        // `MeasurementFormatter` over `UnitInformationStorage.megabits` gives
        // «Mb» in seven of the eight and «Мбит» in Russian, with no per-second
        // in any of them.
        "Mbit/s": [.es, .fr, .de, .ja, .zh, .pt],
        "min": [.es, .fr, .pt],
        "Mint": [.de],
        "MODULES": [.fr],
        "Modules": [.fr],
        "Name": [.de],
        "Nature": [.fr],
        "Notification": [.fr],
        "OK": [.fr, .pt],
        "Orange": [.fr, .de],
        "Panel": [.es, .de],
        // es reads «Módulos» now, System Information's own name for the section.
        "Plug-ins": [.de, .pt],
        "Ring": [.de],
        "Rostislav Strelnikov": [.es, .fr, .de, .ja, .zh, .pt],
        "Start": [.de],
        "Style": [.fr],
        "System": [.de],
        "Tab": [.de],
        "Tag": [.fr, .de],
        "Text": [.de],
        "Timer": [.de, .pt],
        "Updates": [.de],
        "VERSION": [.fr, .de],
        "Video": [.de],
        "VPN": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "🌐︎": [.ru, .es, .fr, .de, .ja, .zh, .pt],
    ]

    func testNoTranslationIsJustTheEnglishAgainUnlessItIsMeantTo() throws {
        var untranslated: [(AppLanguage, String)] = []
        for language in AppLanguage.allCases where language != .en {
            for (key, value) in try table(for: language) where key == value {
                guard Self.deliberateIdentities[key]?.contains(language) != true else { continue }
                untranslated.append((language, key))
            }
        }
        XCTAssertTrue(untranslated.isEmpty,
                      "\(untranslated.count) key(s) are shipped as their own English. If a "
                      + "language really does spell one of these the way English does, say so in "
                      + "deliberateIdentities — a decision belongs in writing:\n"
                      + untranslated
                        .map { "  \($0.0.rawValue): \"\($0.1.prefix(60))…\"" }
                        .sorted()
                        .joined(separator: "\n"))
    }

    /// An allowlist rots the moment the string it excuses is translated, and a
    /// stale entry excuses whatever is written there next. Every entry has to
    /// still be doing work.
    func testEveryAllowedIdentityIsStillOne() throws {
        var stale: [String] = []
        for language in AppLanguage.allCases where language != .en {
            let table = try table(for: language)
            for (key, languages) in Self.deliberateIdentities where languages.contains(language) {
                guard let value = table[key] else {
                    stale.append("\(language.rawValue): \"\(key)\" is not in the file at all")
                    continue
                }
                if value != key {
                    stale.append("\(language.rawValue): \"\(key)\" is translated as \"\(value)\"")
                }
            }
        }
        XCTAssertTrue(stale.isEmpty,
                      "\(stale.count) allowlist entr(ies) no longer describe the files:\n"
                      + stale.sorted().joined(separator: "\n"))
    }
}
