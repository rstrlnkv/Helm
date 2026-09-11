import XCTest
import HelmTestSupport
@testable import HelmUI

/// `InlineTables`'s own guard — the reader every other check in this file's
/// neighbours now points at, rather than a fresh walk of `Sources` each.
///
/// One spelling per test, because a walk that silently stopped matching one of
/// them would otherwise hide behind the others still passing. The tree-wide
/// canary at the end is the other half: the fixtures prove each spelling is
/// read correctly in isolation, and the canary proves the walk still finds all
/// of them at once, in the actual tree, rather than in a shape nobody writes.
final class AnInlineTableIsReadInEverySpellingTests: XCTestCase {

    // MARK: - One spelling each

    func testAOneLineTableIsRead() throws {
        let source = """
        func line() -> String {
            L("Key", [.ru: "Р", .es: "E", .fr: "F", .de: "D", .ja: "J", .zh: "Z", .pt: "P"])
        }
        """
        let tables = try InlineTables.tables(in: source, path: "fixture")
        XCTAssertEqual(tables.count, 1)
        let table = try XCTUnwrap(tables.first)
        XCTAssertEqual(table.line, table.closingLine, "a one-line table opens and closes on one line")
        XCTAssertEqual(table.key, "Key")
        XCTAssertEqual(table.rows.map(\.language), [.ru, .es, .fr, .de, .ja, .zh, .pt])
        XCTAssertTrue(table.rows.allSatisfy { $0.line == table.line },
                      "a one-line table puts every row on the table's own line")
    }

    func testAMultiLineTableIsRead() throws {
        let source = """
        func line() -> String {
            L("Key", [
                .ru: "Р",
                .es: "E",
                .fr: "F",
                .de: "D",
                .ja: "J",
                .zh: "Z",
                .pt: "P",
            ])
        }
        """
        let tables = try InlineTables.tables(in: source, path: "fixture")
        let table = try XCTUnwrap(tables.first)
        XCTAssertNotEqual(table.line, table.closingLine)
        XCTAssertEqual(table.key, "Key")
        let ru = try XCTUnwrap(table.rows.first { $0.language == .ru })
        let pt = try XCTUnwrap(table.rows.first { $0.language == .pt })
        XCTAssertLessThan(ru.line, pt.line, "each row of a multi-line table keeps its own line")
    }

    /// The guard `StringsLiveInLprojTests` used to carry on its own scanner:
    /// naming a language is not a table, and a scanner that read "a comma
    /// follows the literal" as "a table follows it" would excuse a real table
    /// at any site that also named its language and complain about a call that
    /// carried none.
    func testACallSiteThatNamesALanguageIsNotATable() throws {
        let source = """
        let a = L("Connected", language: language)
        let b = L("Connected", [.ru: "Подключено", .es: "E", .fr: "F", .de: "D", .ja: "J", .zh: "Z", .pt: "P"])
        let d = L("Connected")
        """
        let tables = try InlineTables.tables(in: source, path: "fixture")
        XCTAssertEqual(tables.count, 1, "only the call that actually carries a table counts as one")
        XCTAssertEqual(tables.first?.key, "Connected")
    }

    func testALetBindingCarriesNoKey() throws {
        let source = """
        let names: [AppLanguage: String] = [
            .ru: "Р", .es: "E", .fr: "F", .de: "D", .ja: "J", .zh: "Z", .pt: "P",
        ]
        """
        let tables = try InlineTables.tables(in: source, path: "fixture")
        XCTAssertEqual(try XCTUnwrap(tables.first).key, nil,
                       "a let-bound table names no L() call to read a key from")
    }

    func testAReturnCarriesNoKey() throws {
        let source = """
        func table() -> [AppLanguage: String] {
            return [
                .ru: "Р", .es: "E", .fr: "F", .de: "D", .ja: "J", .zh: "Z", .pt: "P",
            ]
        }
        """
        let tables = try InlineTables.tables(in: source, path: "fixture")
        XCTAssertEqual(try XCTUnwrap(tables.first).key, nil)
    }

    /// The first argument is a whole expression rather than a single literal —
    /// so there is no key text to ask "does this name an interpolation" of, and
    /// this reader must not guess one out of the ternary's own literals.
    func testATernaryFirstArgumentCarriesNoKey() throws {
        let source = """
        func table(_ n: Int) -> String {
            L(n == 1 ? "One" : "Many", [.ru: "Р", .es: "E", .fr: "F", .de: "D", .ja: "J", .zh: "Z", .pt: "P"])
        }
        """
        let tables = try InlineTables.tables(in: source, path: "fixture")
        XCTAssertEqual(try XCTUnwrap(tables.first).key, nil)
    }

    /// `\(items("fr"))` nests a literal inside the interpolation of another —
    /// the reason `SwiftSource.literals(in:)` has to be interpolation-aware at
    /// all, rather than ending a row's own literal at the first quote it meets.
    func testANestedLiteralInsideAnInterpolationDoesNotEndTheRow() throws {
        let source = #"""
        func table() -> String {
            L("Key", [.ru: "Р", .es: "E", .fr: "Avant \(items("fr")) après", .de: "D", .ja: "J", .zh: "Z", .pt: "P"])
        }
        """#
        let tables = try InlineTables.tables(in: source, path: "fixture")
        let fr = try XCTUnwrap(try XCTUnwrap(tables.first).rows.first { $0.language == .fr })
        XCTAssertEqual(fr.literals.count, 1, "one literal, not cut short at the nested quote")
        XCTAssertEqual(fr.literals[0].value, "Avant \(SwiftSource.interpolation) après")
    }

    /// `SwiftSource.uncommented(under:)` is what closes this: read raw, the
    /// comment's own comma would split the row it sits inside.
    func testACommentWithACommaInsideATableIsNotARow() throws {
        let raw = """
        func table() -> String {
            let table: [AppLanguage: String] = [
                .ru: "Р",
                // a note, with a comma in it
                .es: "E", .fr: "F", .de: "D", .ja: "J", .zh: "Z", .pt: "P",
            ]
            return table["\\(0)"] ?? ""
        }
        """
        let tables = try InlineTables.tables(in: SwiftSource.uncommented(raw), path: "fixture")
        XCTAssertEqual(try XCTUnwrap(tables.first).rows.count, 7)
    }

    func testAnEscapedQuoteAndALowercaseUnicodeEscapeDecodeInAValue() throws {
        let source = #"""
        func table() -> String {
            L("Key", [.ru: "Р", .es: "E", .fr: "Dit \"bonjour\"\u{00a0}: oui", .de: "D", .ja: "J", .zh: "Z", .pt: "P"])
        }
        """#
        let tables = try InlineTables.tables(in: source, path: "fixture")
        let fr = try XCTUnwrap(try XCTUnwrap(tables.first).rows.first { $0.language == .fr })
        XCTAssertEqual(fr.literals.first?.value, "Dit \"bonjour\"\u{00A0}: oui",
                       "\\\" and a lower-case \\u{…} both decode")
    }

    func testAnUnknownLanguageRowThrows() {
        let source = """
        func table() -> String {
            L("Key", [.ru: "Р", .xx: "X"])
        }
        """
        XCTAssertThrowsError(try InlineTables.tables(in: source, path: "fixture")) { error in
            XCTAssertTrue("\(error)".contains("xx"), "the error should name the bad case: \(error)")
        }
    }

    func testAnUnclosedTableThrows() {
        let source = #"L("Key", [.ru: "Р", .es: "E""#
        XCTAssertThrowsError(try InlineTables.tables(in: source, path: "fixture"))
    }

    // MARK: - The canary over the whole tree

    /// Both floors below sit under the counts measured on the real tree —
    /// margin against a table added or reworded, never against the walk
    /// quietly stopping. If either drops to zero, the walk has stopped seeing
    /// that spelling rather than the tree having lost every example of it.
    func testTheTreeCarriesTablesInEveryReadableSpelling() throws {
        let tables = try InlineTables.tables(under: "Sources")
        XCTAssertGreaterThanOrEqual(tables.count, InlineTables.floor,
                                    "only \(tables.count) table(s) found — the walk is not reading Sources")

        let oneLine = tables.filter { $0.line == $0.closingLine }
        let multiLine = tables.filter { $0.line != $0.closingLine }
        let keyless = tables.filter { $0.key == nil }
        XCTAssertGreaterThanOrEqual(oneLine.count, 40,
                                    "only \(oneLine.count) one-line table(s) — the one-line spelling stopped matching")
        XCTAssertGreaterThanOrEqual(multiLine.count, 45,
                                    "only \(multiLine.count) multi-line table(s) — the multi-line spelling stopped matching")
        XCTAssertGreaterThanOrEqual(keyless.count, 15,
                                    "only \(keyless.count) key-less table(s) — a let binding, a return or a "
                                    + "non-literal first argument stopped being recognised")
    }

    /// The reader's own fast no, over a directory that holds no Swift at all —
    /// a wrong directory must fail the floor above rather than read as a tree
    /// with nothing to translate.
    func testADirectoryWithNoSwiftFindsNoTables() throws {
        let tables = try InlineTables.tables(under: "Resources/HelmApp")
        XCTAssertTrue(tables.isEmpty)
    }
}
