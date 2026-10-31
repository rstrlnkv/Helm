import XCTest
import HelmTestSupport
@testable import HelmUI

/// Punctuation is terminology: which marks a language quotes with, and which
/// space it puts beside a mark, are looked up in macOS's own bundles rather
/// than remembered — the same rule the units and the pane names follow.
///
/// `Quoted` already carries that ruling for a name it wraps at runtime
/// (`L10n.swift`), and the `.lproj` files went their own way regardless: the
/// 0.8.0 entries quoted Spanish with `“…”` and the 0.9.0 entries with `«…»`,
/// which is one file disagreeing with itself about a language. Counted in
/// Finder's own `.lproj`: es 424 `“…”` against 0 `«…»`, pt-BR 419 against 0.
///
/// Japanese was held out of this for one release, and the exclusion was the
/// reason the file could stay 118/118 on 「…」 while `Quoted` answered “…” for
/// the same language: the filter dropped it from the offender loop *and* from
/// the union, so it neither obeyed the ruling nor made 「…」 foreign to anyone.
/// A held-out language is a guard that cannot fail. All eight are checked now,
/// and the corner brackets stay seeded below because no language's `Quoted`
/// produces them, so nothing else would put them in the union.
///
/// Both predicates below read every catalog through `ModuleCatalogs` — the kit's, each module's, the
/// host's and the changelog's: a value is judged by its marks and its spaces, and does not know or care
/// which file it came out of. There is no inline table left to read.
final class PunctuationIsTerminologyTests: XCTestCase {

    /// Every symbol's value in `language`, named `Module.symbol` — one entry per symbol, so two symbols
    /// that share a placeholder-bearing English are both judged.
    private func values(for language: AppLanguage) throws -> [(name: String, value: String)] {
        let entries = try ModuleCatalogs.entries(for: language)
        XCTAssertGreaterThan(entries.count, 1000, "\(language.rawValue): \(entries.count) value(s) — the catalogs were not read")
        XCTAssertTrue(entries.contains { $0.module == "HelmUI" }, "the kit's catalog was not read")
        return entries.map { ($0.name, $0.value) }
    }

    /// A language's own marks, asked of `Quoted` rather than written down here.
    ///
    /// `Quoted` is the ruling — eight languages, each counted in macOS's
    /// bundles, with the counts in its doc comment — and a second copy of it in
    /// a test is a second thing to keep in step. Wrapping the empty string
    /// leaves exactly the pair, plus French's unbreakable spaces, which are the
    /// other test's subject.
    private func marks(of language: AppLanguage) -> Set<Character> {
        Set(Quoted("", language: language).filter { !$0.isWhitespace })
    }

    /// Every mark `text` carries that is not among `language`'s own.
    private func foreignMarks(in text: String, language: AppLanguage,
                              every: Set<Character>) -> Set<Character> {
        let foreign = every.subtracting(marks(of: language))
        return Set(text.filter { foreign.contains($0) })
    }

    /// Every mark any of the eight writes, plus the corner brackets, which none
    /// of them do — three Chinese values had them, and Japanese had 118.
    private var everyMark: Set<Character> {
        AppLanguage.allCases.reduce(into: Set<Character>(["「", "」"])) { $0.formUnion(marks(of: $1)) }
    }

    func testNoLanguageQuotesWithAnotherLanguagesMarks() throws {
        let every = everyMark
        var offenders: [(AppLanguage, Character, String)] = []
        for language in AppLanguage.allCases {
            for (name, value) in try values(for: language) {
                for mark in foreignMarks(in: value, language: language, every: every) {
                    offenders.append((language, mark, name))
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) value(s) quote with a mark their language does not use:\n"
                      + offenders
                        .map { "  \($0.0.rawValue) \($0.1) in \"\($0.2.prefix(60))…\"" }
                        .sorted()
                        .joined(separator: "\n"))
    }

    /// French's space is a character, and the wrong one breaks the line.
    ///
    /// macOS French is 413 for 413 on the unbreakable space inside guillemets
    /// and writes 129 before a colon and 121 before a question mark with never
    /// an ordinary one. An ordinary space there is not merely the wrong
    /// character: it is a *breaking* one, so the name can end up on the line
    /// below the mark that opened it, and the colon can start a line by itself.
    ///
    /// Cleanly expressible because French is the only language of the eight
    /// that spaces its punctuation at all, and because nothing in the file
    /// quotes an untranslated English label — the one value that names a macOS
    /// setting writes it in French inside French marks. Neither pattern has a
    /// legitimate occurrence to excuse.
    private func frenchSpacingOffences(in value: String) -> [String] {
        let breaking: Character = " "        // U+0020
        let unbreakable: Character = "\u{00A0}"
        var offences: [String] = []
        let characters = Array(value)
        for (index, character) in characters.enumerated() {
            let before = index > 0 ? characters[index - 1] : nil
            let after = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "«", after != unbreakable {
                offences.append("« not followed by U+00A0")
            }
            if character == "»", before != unbreakable {
                offences.append("» not preceded by U+00A0")
            }
            if ":;?!".contains(character), before == breaking {
                offences.append("U+0020 before \(character)")
            }
        }
        return offences
    }

    func testFrenchSpacesItsPunctuationTheWayMacOSDoes() throws {
        var offenders: [String] = []
        for (name, value) in try values(for: .fr) {
            for offence in frenchSpacingOffences(in: value) {
                offenders.append("\(offence) in \(name)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) French value(s) use an ordinary space where macOS "
                      + "uses an unbreakable one:\n"
                      + offenders.sorted().joined(separator: "\n").prefix(4000))
    }

    /// **No module catalog writes «ё».** Russian words in a module's catalog are spelled with «е»
    /// (`Еще`, not `Ещё`), the way the system's own lists spell them; the kit's and the host's catalogs
    /// are not in this guard — their «ё» was shipped before it and stays (the owner's list says
    /// which). `yoOffences` takes catalogs, so the fixture below proves it can fail.
    static func yoOffences(in catalogs: [ModuleCatalogs.Catalog]) -> [String] {
        var out: [String] = []
        for catalog in catalogs where catalog.isModule {
            for (symbol, values) in catalog.strings {
                for (language, value) in values where value.contains(where: { "ёЁ".contains($0) }) {
                    out.append("\(catalog.module).\(symbol) \(language): \(value.prefix(50))")
                }
            }
        }
        return out.sorted()
    }

    func testTheYoReadingFindsOnlyAModuleCatalogsYo() {
        let yo = ["a": ["ru": "Ещё"]]
        let ok = ["a": ["ru": "Еще"]]
        func catalog(_ strings: [String: [String: String]], _ path: String) -> ModuleCatalogs.Catalog {
            .init(module: "X", path: path, strings: strings, states: [:])
        }
        XCTAssertEqual(Self.yoOffences(in: [catalog(yo, "Sources/Modules/X/UI/Localizable.xcstrings")]).count, 1)
        XCTAssertEqual(Self.yoOffences(in: [catalog(ok, "Sources/Modules/X/UI/Localizable.xcstrings")]), [])
        XCTAssertEqual(Self.yoOffences(in: [catalog(yo, ModuleCatalogs.kitPath)]), [],
                       "the kit's catalog is outside this guard")
    }

    func testNoModuleCatalogWritesYo() throws {
        let catalogs = try ModuleCatalogs.all()
        XCTAssertGreaterThanOrEqual(catalogs.filter(\.isModule).count, 10, "the modules' catalogs were not read")
        XCTAssertTrue(catalogs.filter(\.isModule).allSatisfy { $0.strings.values.contains { $0["ru"] != nil } },
                      "a module catalog carries no Russian, so «no ё» is said of nothing")
        let offences = Self.yoOffences(in: catalogs)
        XCTAssertTrue(offences.isEmpty, "\(offences.count) module value(s) write ё:\n" + offences.prefix(20).joined(separator: "\n"))
    }
}
