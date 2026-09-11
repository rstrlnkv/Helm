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
/// Both predicates below also read every inline table (CLAUDE.md's one
/// exception to "every string lives in `.lproj`") — a French value written at
/// a call site is still a French value, and the mark and spacing rules do not
/// know or care which file it came out of.
final class PunctuationIsTerminologyTests: XCTestCase {

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = try XCTUnwrap(Localized.stringsFile(for: language)?.path,
                                 "no Localizable.strings for \(language.rawValue)")
        let dict = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String],
                                 "\(language.rawValue).lproj did not parse")
        XCTAssertGreaterThan(dict.count, 100, "\(language.rawValue).lproj carries almost nothing")
        return dict
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

    /// Every mark `text` carries that is not among `language`'s own — the
    /// predicate both the `.lproj` test and the inline-table test apply.
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
            for (key, value) in try table(for: language) {
                for mark in foreignMarks(in: value, language: language, every: every) {
                    offenders.append((language, mark, key))
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

    /// The same rule read off every inline table's literals instead of the
    /// `.lproj` files — the key, when there is one, stands in as `.en` because
    /// it is the same English the `.lproj` test reads as a value elsewhere.
    func testNoInlineTableQuotesWithAnotherLanguagesMarks() throws {
        let every = everyMark
        let tables = try InlineTables.tables(under: "Sources")
        XCTAssertGreaterThanOrEqual(tables.count, InlineTables.floor,
                                    "only \(tables.count) table(s) found — InlineTables is not reading Sources")
        var offenders: [(String, AppLanguage, Character, String)] = []
        for table in tables {
            if let key = table.key {
                for mark in foreignMarks(in: key, language: .en, every: every) {
                    offenders.append((table.path, .en, mark, key))
                }
            }
            for row in table.rows {
                for literal in row.literals {
                    for mark in foreignMarks(in: literal.value, language: row.language, every: every) {
                        offenders.append(("\(table.path):\(row.line)", row.language, mark, literal.value))
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) inline value(s) quote with a mark their language does not use:\n"
                      + offenders
                        .map { "  \($0.0) \($0.1.rawValue) \($0.2) in \"\($0.3.prefix(60))…\"" }
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
        for (key, value) in try table(for: .fr) {
            for offence in frenchSpacingOffences(in: value) {
                offenders.append("\(offence) in \"\(key.prefix(50))…\"")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) French value(s) use an ordinary space where macOS "
                      + "uses an unbreakable one:\n"
                      + offenders.sorted().joined(separator: "\n").prefix(4000))
    }

    /// The same rule read off every inline table's French row.
    func testFrenchInlineTablesSpaceTheirPunctuationTheWayMacOSDoes() throws {
        let tables = try InlineTables.tables(under: "Sources")
        let frenchRows = tables.flatMap { $0.rows }.filter { $0.language == .fr }
        XCTAssertGreaterThanOrEqual(frenchRows.count, InlineTables.floor,
                                    "only \(frenchRows.count) French row(s) found — InlineTables is not "
                                    + "reading Sources")
        var offenders: [String] = []
        for table in tables {
            for row in table.rows where row.language == .fr {
                for literal in row.literals {
                    for offence in frenchSpacingOffences(in: literal.value) {
                        offenders.append("\(table.path):\(row.line) \(offence) in "
                                        + "\"\(literal.value.prefix(50))…\"")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) French inline value(s) use an ordinary space where macOS "
                      + "uses an unbreakable one:\n"
                      + offenders.sorted().joined(separator: "\n").prefix(4000))
    }
}
