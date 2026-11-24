import XCTest
import HelmTestSupport

/// The other direction of `StringsCoverageTests`.
///
/// That one asks whether every catalog symbol carries its eight languages. This asks whether anything
/// still *wants* the symbol, and whether anything still asks for a word by its English spelling.
final class NoOrphanTranslationsTests: XCTestCase {

    /// **An orphan is a trap for the next person.** One symbol means one thing, so the next `L(.medium)`,
    /// written about something else, would inherit eight translations of an unrelated word, and English
    /// could not show it. Every word is asked for by symbol, so this asks the sources of the catalog's own
    /// target (comments blanked, literals kept) for each `.symbol`: the kit's in `Sources/HelmUI`, a module's
    /// in its `UI`, the host's in `Sources/HelmAppStrings`.
    func testNoCatalogSymbolGoesUnnamed() throws {
        let catalogs = try ModuleCatalogs.all()
        XCTAssertGreaterThanOrEqual(catalogs.count, 13, "only \(catalogs.count) catalog(s) were found, so a pass means nothing")
        XCTAssertTrue(catalogs.contains { $0.module == "HelmUI" }, "the kit's catalog was not read")
        var unnamed: [String] = []
        for catalog in catalogs {
            let directory = (catalog.path as NSString).deletingLastPathComponent
            let swift = try SwiftSource.uncommented(under: directory).map(\.text).joined(separator: "\n")
            XCTAssertFalse(swift.isEmpty, "\(directory) holds no Swift, so a pass means nothing")
            // The changelog catalog's key is the English sentence, and Xcode spells its symbol from the
            // letters and digits of it, so the key and the symbol are compared by those alone.
            let spelled = Set(swift.matches(of: /\.Changelog\.([^\s)]+)/).map { Self.letters(String($0.1)) })
            for symbol in catalog.strings.keys.sorted() {
                let named = catalog.module == "Changelog"
                    ? spelled.contains(Self.letters(symbol))
                    : swift.range(of: #"\.\#(symbol)\b"#, options: .regularExpression) != nil
                if !named { unnamed.append("\(catalog.module).\(symbol)") }
            }
        }
        XCTAssertTrue(unnamed.isEmpty,
                      "\(unnamed.count) catalog symbol(s) are named nowhere in the sources of their target — "
                      + "remove them from the catalog:\n" + unnamed.joined(separator: "\n"))
    }

    private static func letters(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// **No call asks for a word by its English.** `L("Open")` falls back to the key and shows English
    /// in a language whose catalog never got the word; `L(.open)` is a symbol the build refuses when the
    /// catalog lacks it. The raw text is read, comments included, because a comment that shows `L("…")`
    /// teaches a spelling the build would refuse.
    static func englishLookups(in text: String) -> [Int] {
        text.matches(of: /\bL\(\s*"/).map { text[..<$0.range.lowerBound].filter { $0 == "\n" }.count + 1 }
    }

    func testTheReadingFindsAnEnglishLookup() {
        XCTAssertEqual(Self.englishLookups(in: "let a = 1\nlet b = L(\"Off\")"), [2])
        XCTAssertEqual(Self.englishLookups(in: "L( \"Off\", [:])"), [1])
        XCTAssertEqual(Self.englishLookups(in: "L(.off) HelmL(\"x\") FL(\"y\")"), [])
    }

    func testNoCallAndNoCommentLooksAWordUpByItsEnglish() throws {
        let paths = try RepoSource.swiftFiles(under: "Sources")
        XCTAssertGreaterThan(paths.count, 100, "only \(paths.count) source files were found")
        var lines: [String] = []
        for path in paths {
            for line in Self.englishLookups(in: try RepoSource.text(of: path)) { lines.append("  \(path):\(line)") }
        }
        XCTAssertTrue(lines.isEmpty,
                      "\(lines.count) line(s) still show `L(\"…\")` in Sources, in code or in prose:\n"
                      + lines.sorted().prefix(60).joined(separator: "\n"))
    }
}
