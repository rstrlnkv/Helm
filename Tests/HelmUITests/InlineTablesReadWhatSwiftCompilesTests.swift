import XCTest
import HelmTestSupport
@testable import HelmUI

/// Inputs `InlineTables` and `SwiftSource.literals(in:)` were never fed by
/// their own tests — each one legal Swift a strings file can carry, and each
/// one either dropped without a word or read as something the running app
/// does not show. The reader's promise is "throw, never drop"; every case here
/// breaks it or hands a rule the wrong text.
///
/// Found by the tester against 9b0e1020, where every case below is red.
final class InlineTablesReadWhatSwiftCompilesTests: XCTestCase {

    private let rows = #".ru: "R", .es: "E", .fr: "F : x", .de: "D", .ja: "J", .zh: "Z", .pt: "P""#

    /// `StringsLiveInLprojTests` excuses a table whose key is nil, and the key
    /// walk goes backwards from `[` counting brackets without skipping the
    /// literal it crosses — so a bracket inside the key's own text unbalances
    /// the count, the key reads as nil, and a plain tabled string passes the
    /// rule it breaks. The forward walk this replaced read all four.
    func testAKeyHoldingAnUnbalancedBracketIsStillAKey() throws {
        for key in ["Step 1)", "a (b", "a ]", "{x"] {
            let source = #"L(""# + key + #"", ["# + rows + "])"
            let tables = try InlineTables.tables(in: source, path: "fixture")
            let table = try XCTUnwrap(tables.first, "the table after L(\"\(key)\" was not read at all")
            XCTAssertEqual(table.key, key,
                           "L(\"\(key)\", [ … ]) carries a plain key, and the reader answered "
                           + String(describing: table.key))
        }
    }

    /// A space before each colon is legal Swift and `opensATable` accepts it —
    /// but the file-level fast no looks for `.ru:` with no space, so a file
    /// whose every table is spaced that way answers with no tables, and its
    /// French row reaches no guard.
    func testATableSpacedBeforeItsColonsIsRead() throws {
        let source = #"L("K \(k)", [.ru : "R", .es : "E", .fr : "F : x", .de : "D", .ja : "J", .zh : "Z", .pt : "P"])"#
        let tables = try InlineTables.tables(in: source, path: "fixture")
        XCTAssertEqual(tables.count, 1, "a table spaced before its colons was dropped without a word")
        let french = tables.first?.rows.first(where: { $0.language == .fr })
        XCTAssertEqual(french?.literals.first?.value, "F : x")
    }

    /// A first row that names its type is legal Swift. `opensATable` wants `.`
    /// straight after `[`, so the table is not seen at all, while the same
    /// spelling on a later row throws. Reading it and refusing it are both
    /// answers; returning nothing is the one this reader promises never to give.
    func testATableWhoseFirstRowNamesItsTypeIsReadOrRefused() {
        let source = #"L("K \(k)", [AppLanguage.ru: "R", .es: "E", .fr: "F : x", .de: "D", .ja: "J", .zh: "Z", .pt: "P"])"#
        do {
            let tables = try InlineTables.tables(in: source, path: "fixture")
            XCTAssertEqual(tables.count, 1, "a table whose first row names AppLanguage was dropped without a word")
        } catch {
            // A refusal is loud, which is all this asks.
        }
    }

    /// `\\` is one escaped backslash: `"a\\u{00A0}»"` renders as `a\u{00A0}»`,
    /// with `}` before the mark. `decodingEscapes` never collapses `\\`, so it
    /// decodes the `\u{00A0}` it finds after the first backslash and hands the
    /// French rule an unbreakable space before `»` the rendered string lacks.
    func testAnEscapedBackslashDoesNotStartAnEscape() throws {
        let literals = try SwiftSource.literals(in: #""a\\u{00A0}»""#)
        XCTAssertEqual(literals.map(\.value), [#"a\u{00A0}»"#])
    }

    /// The two literal walks this commit added must agree on where a literal
    /// ends. `InlineTables`' own walk closes `##"…"##` at `"##`; the value walk
    /// knows one `#` only, stops at the first `"#`, and throws an error that
    /// names no file.
    func testTheTwoLiteralWalksAgreeOnADoubleHashRawString() throws {
        let literals = try SwiftSource.literals(in: ###"##"a "# b"##"###)
        XCTAssertEqual(literals.map(\.value), [##"a "# b"##])
    }
}
