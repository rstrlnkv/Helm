import XCTest
import HelmTestSupport
@testable import HelmUI

/// Two directions in which the eight `.lproj` string tables can fail, and the
/// tests of each.
///
/// What the tables hold. The guard that used to walk inline tables in the
/// source now reads the eight `.lproj` files as data — those files are the
/// artifact that ships, and a key that never made it out of the migration is
/// exactly the failure worth catching. Every English key stands in every other
/// language and no value is empty. An inline table has no `.lproj` file to be
/// missing from, so it gets its own coverage tests below, read through
/// `InlineTables` rather than reflected.
///
/// Read through `Localized.stringsFile(for:)` rather than `Bundle.module`:
/// inside a test target `Bundle.module` resolves to the test's own bundle, not
/// `HelmUI`'s, so it is never the right way to ask what `HelmUI` ships.
///
/// How the tables are laid out. A key added at the last line of a table meets,
/// in eight files at once, every other key added there the same day, so the
/// tables keep one order and `TableOrder`, at the end of this file, is the rule
/// that judges it: keys rise by the unsigned bytes of the key as it is spelled
/// between its quotes, line N holds the same key in all eight tables, from its
/// first entry to its end a table holds entries only, and the reader took as
/// many keys as the system's parser reads from the same bytes. A new key goes
/// to its place in every table and is never appended. The rule is also run on
/// tables written in the test itself, at least one for each kind of finding
/// and for the other comparisons it must not be, because a rule that passes
/// the tree is not shown to be able to fail by the tree.
///
/// The order tests read the tree's files by path through `RepoSource.root`, not
/// through `Localized.stringsFile(for:)`: they name lines of the files a person
/// edits, and the copy the build made of a table is not their subject.
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

    // MARK: - One order for the eight tables, asked of the tree

    /// The eight tables as the tree holds them, English first. Read by path
    /// from the repository's root and not through `Localized.stringsFile(for:)`
    /// as the tests above read them: the order is a rule about the lines
    /// somebody adds a key to, its messages name those lines, and what the
    /// build does to its own copy of a table is not this rule's subject.
    private func tablesOfTheTree() throws -> [TableOrder.Table] {
        try AppLanguage.allCases.map { language in
            let path = "Sources/HelmUI/Resources/\(language.rawValue).lproj/Localizable.strings"
            let data = try Data(contentsOf: RepoSource.root.appendingPathComponent(path))
            return TableOrder.Table(language: language.rawValue, bytes: Array(data))
        }
    }

    /// One of the four rules of `TableOrder`, asked of the eight tables. The
    /// message is the rule's own report: where, how many, and what to do.
    private func assertTheTreeKeeps(_ rule: TableOrder.Rule, line: UInt = #line) throws {
        let findings = TableOrder.findings(in: try tablesOfTheTree())
        XCTAssertTrue(findings.allSatisfy { $0.kind.rule != rule },
                      TableOrder.report(findings, of: rule), line: line)
    }

    /// A key added at the last line of a table meets every other key added
    /// there the same day, in eight files at once. A key whose bytes give it
    /// one place meets only a key that belongs between the same two entries.
    func testEveryTableRisesByTheBytesOfItsKeys() throws {
        try assertTheTreeKeeps(.rising)
    }

    /// A key is found in eight files by one line number, and a table that
    /// lost or gained a line shows up here at the first line that moved.
    func testALineHoldsTheSameKeyInEveryTable() throws {
        try assertTheTreeKeeps(.sameLine)
    }

    /// A comment or a blank line between entries has no place of its own in
    /// an order of keys: it stays where it was written and heads whatever the
    /// order puts under it.
    func testFromItsFirstEntryATableHoldsEntriesOnly() throws {
        try assertTheTreeKeeps(.entriesOnly)
    }

    /// The three tests above judge only what the reader took, so this one
    /// asks whether it took the table: a reader that recognised no entry finds
    /// no key out of order. The printed lines are the figures the other three
    /// rest on, and the last figure says how many of these keys Swift's own
    /// `<` on `String` would put elsewhere than their bytes do; that the two
    /// orders can differ at all is shown on one pair by
    /// `testTheOrderIsOfBytesWhereSwiftsOwnOrderDiffers`.
    func testTheOrderReaderTakesEveryKeyTheSystemReads() throws {
        for table in try tablesOfTheTree() {
            let reading = TableOrder.read(table)
            let keys = reading.entries.map { $0.key }
            let byBytes = keys.sorted { TableOrder.rises($1, above: $0) }
            let bySwift = keys.map { String(decoding: $0, as: UTF8.self) }.sorted().map { Array($0.utf8) }
            let elsewhere = zip(byBytes, bySwift).filter { $0.0 != $0.1 }.count
            let system = reading.systemKeys.map { "\($0)" } ?? "no"
            print("[table order] \(table.language): \(reading.entries.count) entry line(s) in \(reading.lines) "
                  + "line(s), the system's parser reads \(system) key(s); String's own < would put \(elsewhere) "
                  + "of these keys elsewhere than their bytes do")
        }
        try assertTheTreeKeeps(.readWhole)
    }

    // MARK: - The same rule, asked of tables that never existed

    /// What the rule reports for the given tables, a finding a line: its
    /// kind, its language and its line (0 where it is about the whole table).
    private func reported(_ tables: KeyValuePairs<String, String>) -> [String] {
        TableOrder.findings(in: tables.map { TableOrder.Table(language: $0.key, bytes: Array($0.value.utf8)) })
            .map(\.place)
    }

    func testAnUnsortedTableIsReported() {
        XCTAssertEqual(reported(["en": """
            "B" = "v";
            "A" = "v";
            "C" = "v";
            """]), ["descent en:2"])
    }

    /// One key on two lines of one table. The system's parser counts such a
    /// key once, so the count says it as well.
    func testAKeyWrittenTwiceInOneTableIsReported() {
        let apart = TableOrder.findings(in: [TableOrder.Table(language: "en", bytes: Array("""
            "A" = "v";
            "B" = "v";
            "A" = "w";
            """.utf8))])
        XCTAssertEqual(apart.map(\.place), ["repeated en:3", "miscounted en:0"])
        XCTAssertTrue(apart.last?.detail.contains("lines 1 and 3") == true,
                      "the count does not say which key is written twice: \(apart.last?.detail ?? "")")
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            "A" = "w";
            "B" = "v";
            """]), ["repeated en:2", "miscounted en:0"])
    }

    /// One key on line N of one table and line M of another, three ways: a
    /// header one line longer, a key missing from the middle, and another key
    /// on the same line. Each table is sorted and whole by itself.
    func testAKeyOnDifferentLinesOfTwoTablesIsReported() {
        XCTAssertEqual(reported(["en": """
            /* header */
            "A" = "v";
            "B" = "v";
            """, "de": """
            /* header */

            "A" = "v";
            "B" = "v";
            """]), ["otherKey de:2", "otherKey de:3", "otherKey de:4"])
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            "B" = "v";
            "C" = "v";
            """, "de": """
            "A" = "v";
            "C" = "v";
            """]), ["otherKey de:2", "otherKey de:3"])
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            "B" = "v";
            """, "de": """
            "A" = "v";
            "C" = "v";
            """]), ["otherKey de:2"])
    }

    /// Every table after the first is compared with the first, not the second
    /// alone: en and de hold the same keys, fr alone holds another key on
    /// line 2, and the one finding is fr's.
    func testAnotherKeyOnTheSameLineOfAThirdTableIsReported() {
        let agreeing = """
            "A" = "v";
            "B" = "v";
            """
        XCTAssertEqual(reported(["en": agreeing, "de": agreeing, "fr": """
            "A" = "v";
            "C" = "v";
            """]), ["otherKey fr:2"])
    }

    func testACommentBetweenEntriesIsReported() {
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            /* Section */
            "B" = "v";
            """]), ["comment en:2"])
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            // note
            "B" = "v";
            """]), ["comment en:2"])
    }

    /// Between two entries, and after the last one: the end of the file is
    /// the end of the entries.
    func testABlankLineBetweenEntriesIsReported() {
        XCTAssertEqual(reported(["en": """
            "A" = "v";

            "B" = "v";
            """]), ["blank en:2"])
        XCTAssertEqual(reported(["en": "\"A\" = \"v\";\n\n"]), ["blank en:2"])
    }

    /// `sort` over whole lines puts the longer key first, because the space
    /// inside it is a smaller byte than the quote that ends the shorter one.
    func testAPrefixPairInTheOrderOfSortedLinesIsReported() {
        XCTAssertEqual(reported(["en": """
            "Active icon colour" = "v";
            "Active" = "v";
            """]), ["descent en:2"])
    }

    /// A capital is a smaller byte than its small letter, so "BETA" stands
    /// before "Beta"; an order that folds case would call the two equal.
    func testAPairDifferingOnlyByCaseInTheWrongOrderIsReported() {
        XCTAssertEqual(reported(["en": """
            "Beta" = "v";
            "BETA" = "v";
            """]), ["descent en:2"])
    }

    /// Four spellings the system's parser reads, or refuses, and the reader
    /// does not take: a bare word for a key, two entries on a line, a value
    /// over two lines, and an entry without its semicolon.
    func testALineThatIsNeitherEntryNorCommentNorBlankIsReported() {
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            B = "v";
            "C" = "v";
            """]), ["unreadable en:2", "miscounted en:0"])
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            "B" = "v"; "C" = "v";
            "D" = "v";
            """]), ["unreadable en:2", "miscounted en:0"])
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            "B" = "v
            w";
            "D" = "v";
            """]), ["unreadable en:2", "unreadable en:3", "miscounted en:0"])
        XCTAssertEqual(reported(["en": """
            "A" = "v";
            "B" = "v"
            "C" = "v";
            """]), ["unreadable en:2", "miscounted en:0"])
    }

    /// No table, an empty one, and one that holds a comment and no entry. The
    /// system's parser reads that last one as a table of no keys, so a count
    /// that only had to agree with it would pass.
    func testATableWithNoEntryIsReported() {
        XCTAssertEqual(reported([:]), ["noEntry :0"])
        XCTAssertEqual(reported(["en": ""]), ["noEntry en:0"])
        XCTAssertEqual(reported(["en": "/* nothing here */\n"]), ["noEntry en:0"])
    }

    /// A table the system reads whole and the reader cannot: lines ended by
    /// a carriage return and a line feed, UTF-16, and a byte order mark in
    /// front of the first entry.
    func testATableInAnotherSpellingIsReported() {
        XCTAssertEqual(reported(["en": "\"A\" = \"v\";\r\n\"B\" = \"v\";\r\n"]), ["noEntry en:0"])
        let wide: [UInt8] = [0xFF, 0xFE] + "\"A\" = \"v\";\n\"B\" = \"v\";\n".utf16.flatMap {
            [UInt8($0 & 0xFF), UInt8($0 >> 8)]
        }
        XCTAssertEqual(TableOrder.findings(in: [TableOrder.Table(language: "en", bytes: wide)]).map(\.place),
                       ["noEntry en:0"])
        XCTAssertEqual(reported(["en": "\u{FEFF}\"A\" = \"v\";\n\"B\" = \"v\";\n"]), ["miscounted en:0"])
    }

    /// The lines above the first entry the reader took are a header and are
    /// not judged, so an entry it did not take there is seen by the count
    /// alone: here the first line is indented.
    func testAnEntryAboveTheFirstOneTakenIsReported() {
        XCTAssertEqual(reported(["en": "  \"A\" = \"v\";\n\"B\" = \"v\";\n"]), ["miscounted en:0"])
    }

    /// Swift's `<` on `String` compares canonical forms: an "e" followed by
    /// a combining acute accent is the one letter U+00E9 to it, and stands
    /// after "f". By its bytes the same key begins with 0x65 and stands
    /// before "f". The first two assertions are the subject, that the pair
    /// really is one the two orders disagree on; the rest say which the rule
    /// follows.
    func testTheOrderIsOfBytesWhereSwiftsOwnOrderDiffers() {
        let decomposed = "e\u{301}", plain = "f"
        XCTAssertEqual(Array(decomposed.utf8), [0x65, 0xCC, 0x81], "the key is not spelled decomposed")
        XCTAssertTrue(plain < decomposed, "Swift's own < no longer puts \"f\" before the decomposed key")
        XCTAssertTrue(TableOrder.rises(Array(plain.utf8), above: Array(decomposed.utf8)))
        XCTAssertEqual(reported(["en": "\"\(decomposed)\" = \"v\";\n\"\(plain)\" = \"v\";\n"]), [])
        XCTAssertEqual(reported(["en": "\"\(plain)\" = \"v\";\n\"\(decomposed)\" = \"v\";\n"]), ["descent en:2"])
    }

    /// A table as the rule wants it, in two languages, holding pairs that
    /// some other order would report: a key before the longer key it begins,
    /// capitals before small letters, a key spelled with a backslash (0x5C)
    /// after "Z" where its resolved quote (0x22) would stand first of all, a
    /// byte above 0x7F after every ASCII one where a signed byte would stand
    /// first, and U+1F310 after U+FF5E where UTF-16 code units put it before.
    func testATableInTheRightOrderIsNotReported() {
        let table = """
            /* The header: a comment and a blank line. */

            "Active" = "v";
            "Active icon colour" = "v";
            "BETA" = "v";
            "Beta" = "v";
            "Z" = "v";
            "\\\"Date Added\\\"" = "v";
            "a" = "v";
            "\u{E9}" = "v";
            "\u{FF5E}" = "v";
            "\u{1F310}" = "v";

            """
        XCTAssertTrue(table.contains("\"\\\"Date Added\\\"\" = "), "the fixture's backslashes were resolved away")
        XCTAssertEqual(reported(["en": table, "de": table]), [])
        XCTAssertEqual(TableOrder.read(TableOrder.Table(language: "en", bytes: Array(table.utf8))).entries.count, 10,
                       "the right table passed without being read")
    }

    /// The message is read by whoever's change just turned the guard red, so
    /// it names the table, the line, the two keys, the count and what to do,
    /// and it is no longer for four hundred descents than for forty.
    func testTheReportSaysWhereAndWhatToDoAndStaysShort() {
        func falling(_ count: Int) -> [TableOrder.Table] {
            let text = "/* header */\n" + (1...count).reversed()
                .map { "\"K\(String(format: "%03d", $0))\" = \"v\";\n" }.joined()
            return ["en", "de"].map { TableOrder.Table(language: $0, bytes: Array(text.utf8)) }
        }
        let forty = TableOrder.findings(in: falling(40))
        XCTAssertEqual(forty.filter { $0.kind == .descent && $0.language == "en" }.count, 39)
        XCTAssertEqual(forty.count, 78, "the fixture reports more than its descents: \(forty.map(\.place).prefix(5))")
        let report = TableOrder.report(forty, of: .rising)
        for needed in ["en.lproj", "de.lproj", "39 descent", "line 3: \"K039\"", "\"K040\" of line 2",
                       "byte order", "never append"] {
            XCTAssertTrue(report.contains(needed), "the report does not say \"\(needed)\":\n\(report)")
        }
        let long = TableOrder.report(TableOrder.findings(in: falling(400)), of: .rising)
        XCTAssertTrue(long.contains("399 descent"), "the long report lost its count:\n\(long)")
        XCTAssertEqual(long.split(separator: "\n").count, report.split(separator: "\n").count,
                       "the report grows with the number of descents")
    }
}

/// One order for the eight tables, as a rule over the bytes of their text.
///
/// `findings(in:)` reports four things, and `StringsCoverageTests` asks each
/// of the tree in a test of its own:
///
/// 1. Keys rise strictly, by `rises(_:above:)` and by nothing else.
/// 2. Line N holds the same key in every table.
/// 3. From its first entry to its end a table holds entries only. The lines
///    above the first entry are its header and are not judged.
/// 4. The reader took an entry at all, and took as many as
///    `PropertyListSerialization` reads keys from the same bytes.
///
/// An entry is one whole line spelled `"key" = "value";`, which is how every
/// entry of the eight tables is spelled. The system's parser reads more than
/// that (a bare word for a key, two entries on one line, a value that runs
/// over several lines), and the reader takes none of it: such a line is
/// reported, not left out of the order in silence.
private enum TableOrder {

    /// A table by the name of its language folder, and its file as bytes.
    struct Table {
        let language: String
        let bytes: [UInt8]
    }

    /// The four rules, by what each asks.
    enum Rule {
        case rising, sameLine, entriesOnly, readWhole

        /// What is wrong, as the report's first line.
        var broken: String {
            switch self {
            case .rising: return "The string tables are not sorted by key"
            case .sameLine: return "A line does not hold the same key in every string table"
            case .entriesOnly: return "Something that is not an entry stands among the entries of a string table"
            case .readWhole: return "The order reader did not take a string table as the system reads it"
            }
        }

        /// What a table's count is a count of.
        var counted: String {
            switch self {
            case .rising: return "descent(s), keys that do not rise above the entry before them"
            case .sameLine: return "line(s) that do not hold the key the first table holds there"
            case .entriesOnly: return "line(s) after the first entry that are not entries"
            case .readWhole: return "reading(s) that cannot be trusted"
            }
        }

        /// What whoever turned the guard red does next.
        var remedy: String {
            switch self {
            case .rising:
                return "move each whole line to where its key rises, the same in all eight tables. The order "
                    + "is the unsigned byte order of the key as it is spelled between its quotes in the file: "
                    + "escapes as written, no case folding, no language's order, and not the order `sort` gives "
                    + "whole lines (\"BETA\" stands before \"Beta\", \"Active\" before \"Active icon colour\", "
                    + "every ASCII byte before any byte that is not ASCII). A new key goes to its place by "
                    + "that order; never append it at the end of a table."
            case .sameLine:
                return "give each line the same key in all eight tables: a key enters every table at the line "
                    + "the byte order of the key gives it, and the lines above the first entry are as many in "
                    + "each table. A key is never appended at the end of a table."
            case .entriesOnly:
                return "from its first entry to its end a table holds entries only, each one whole line "
                    + "spelled \"key\" = \"value\"; — take the blank line or the comment out (among sorted "
                    + "keys a comment heads nothing) and respell a line the reader cannot take."
            case .readWhole:
                return "an entry is one whole line spelled \"key\" = \"value\"; in UTF-8, ended by a line "
                    + "feed, with nothing before or after it on its line. Respell an entry spelled another "
                    + "way, look for one above the first entry the reader took, where no other rule "
                    + "reports it, and remove a key written twice."
            }
        }
    }

    /// What one finding is, and through `rule` which of the four it breaks.
    enum Kind {
        case descent, repeated, otherKey, blank, comment, unreadable, noEntry, miscounted

        var rule: Rule {
            switch self {
            case .descent, .repeated: return .rising
            case .otherKey: return .sameLine
            case .blank, .comment, .unreadable: return .entriesOnly
            case .noEntry, .miscounted: return .readWhole
            }
        }
    }

    /// One thing wrong at one line of one table; line 0 is the whole table.
    struct Finding {
        let kind: Kind
        let language: String
        let line: Int
        let detail: String

        /// The finding without its sentence, which is what a fixture asserts.
        var place: String { "\(kind) \(language):\(line)" }
    }

    /// An entry line: its number, counted from 1, and its key as spelled.
    struct Entry {
        let line: Int
        let key: [UInt8]
    }

    /// A line after the first entry that is not an entry.
    struct Stray {
        let line: Int
        let kind: Kind
        let text: [UInt8]
    }

    /// One table as the reader took it, beside what the system's parser
    /// reads from the same bytes: nil where it reads no table at all.
    struct Reading {
        var lines = 0
        var entries: [Entry] = []
        var strays: [Stray] = []
        var systemKeys: Int?
    }

    /// How many findings of one table a report spells out.
    static let spelledOutPerTable = 3

    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let separator = Array(" = ".utf8)
    private static let terminator = Array(";".utf8)

    /// The one comparison: unsigned byte order of the key as it is spelled
    /// in the file, a key before any longer key it begins. Not `<` on
    /// `String`, which compares canonical forms and not bytes.
    static func rises(_ key: [UInt8], above previous: [UInt8]) -> Bool {
        previous.lexicographicallyPrecedes(key)
    }

    /// The key of a line that is an entry and nothing else, as its bytes
    /// between the quotes with every escape left as written; nil for any
    /// other line.
    static func key(ofEntry line: ArraySlice<UInt8>) -> [UInt8]? {
        var at = line.startIndex
        func quoted() -> ArraySlice<UInt8>? {
            guard at < line.endIndex, line[at] == quote else { return nil }
            var index = at + 1
            while index < line.endIndex {
                if line[index] == backslash {
                    index += 2
                } else if line[index] == quote {
                    let body = line[(at + 1)..<index]
                    at = index + 1
                    return body
                } else {
                    index += 1
                }
            }
            return nil
        }
        guard let spelled = quoted(), line[at...].starts(with: separator) else { return nil }
        at += separator.count
        guard quoted() != nil, line[at...].elementsEqual(terminator) else { return nil }
        return Array(spelled)
    }

    /// What a line that is not an entry is: blank, a comment by the two
    /// bytes it begins with (a slash and an asterisk, or two slashes), or
    /// neither.
    static func kind(ofStray line: ArraySlice<UInt8>) -> Kind {
        let ink = line.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D })
        if ink.isEmpty { return .blank }
        if ink.starts(with: [0x2F, 0x2A]) || ink.starts(with: [0x2F, 0x2F]) { return .comment }
        return .unreadable
    }

    /// The table split at the line feed byte, each line an entry or not. A
    /// line feed that ends the file ends its last line and begins no other.
    static func read(_ table: Table) -> Reading {
        var reading = Reading()
        var lines = table.bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        reading.lines = lines.count
        for (index, line) in lines.enumerated() {
            if let spelled = key(ofEntry: line) {
                reading.entries.append(Entry(line: index + 1, key: spelled))
            } else if !reading.entries.isEmpty {
                reading.strays.append(Stray(line: index + 1, kind: kind(ofStray: line), text: Array(line)))
            }
        }
        let system = try? PropertyListSerialization.propertyList(from: Data(table.bytes), options: [], format: nil)
        reading.systemKeys = (system as? NSDictionary)?.count
        return reading
    }

    /// Bytes for a message: as text, cut short, a carriage return and a tab
    /// made visible.
    static func shown(_ bytes: [UInt8]) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }

    /// Everything the four rules find in the given tables. The first table
    /// is the one the others are compared with, line by line.
    static func findings(in tables: [Table]) -> [Finding] {
        guard let reference = tables.first else {
            return [Finding(kind: .noEntry, language: "", line: 0, detail: "no table was read")]
        }
        var findings: [Finding] = []
        var keysByLine: [[Int: [UInt8]]] = []
        for table in tables {
            let reading = read(table)
            keysByLine.append(Dictionary(uniqueKeysWithValues: reading.entries.map { ($0.line, $0.key) }))
            let system = reading.systemKeys.map { "reads \($0) key(s)" } ?? "reads no table"
            guard !reading.entries.isEmpty else {
                findings.append(Finding(kind: .noEntry, language: table.language, line: 0,
                                        detail: "the reader took no entry from \(reading.lines) line(s); "
                                            + "the system's parser \(system) from the same bytes"))
                continue
            }

            var firstLine: [[UInt8]: Int] = [:]
            var twice: [String] = []
            var previous: Entry?
            for entry in reading.entries {
                if let first = firstLine[entry.key] {
                    twice.append("\"\(shown(entry.key))\" on lines \(first) and \(entry.line)")
                    findings.append(Finding(kind: .repeated, language: table.language, line: entry.line,
                                            detail: "\"\(shown(entry.key))\" is written a second time; "
                                                + "line \(first) holds it already"))
                } else if let previous, !rises(entry.key, above: previous.key) {
                    findings.append(Finding(kind: .descent, language: table.language, line: entry.line,
                                            detail: "\"\(shown(entry.key))\" does not rise above "
                                                + "\"\(shown(previous.key))\" of line \(previous.line)"))
                }
                firstLine[entry.key] = firstLine[entry.key] ?? entry.line
                previous = entry
            }

            for stray in reading.strays {
                let detail: String
                switch stray.kind {
                case .blank: detail = "a blank line"
                case .comment: detail = "a comment, `\(shown(stray.text))`"
                default: detail = "not an entry the reader can take, `\(shown(stray.text))`"
                }
                findings.append(Finding(kind: stray.kind, language: table.language, line: stray.line,
                                        detail: detail))
            }

            if reading.systemKeys != reading.entries.count {
                let written = twice.isEmpty ? "" : "; written twice: "
                    + twice.prefix(spelledOutPerTable).joined(separator: ", ")
                findings.append(Finding(kind: .miscounted, language: table.language, line: 0,
                                        detail: "the reader took \(reading.entries.count) entry line(s) and "
                                            + "the system's parser \(system) from the same bytes" + written))
            }
        }

        for (table, keys) in zip(tables, keysByLine).dropFirst() {
            for line in Set(keysByLine[0].keys).union(keys.keys).sorted() where keysByLine[0][line] != keys[line] {
                let here = keys[line].map { "\"\(shown($0))\"" } ?? "no entry"
                let there = keysByLine[0][line].map { "\"\(shown($0))\"" } ?? "no entry"
                findings.append(Finding(kind: .otherKey, language: table.language, line: line,
                                        detail: "holds \(here) where \(reference.language).lproj holds \(there)"))
            }
        }
        return findings
    }

    /// The findings of one rule as a message: the count, then for each table
    /// its own count and its first few findings, then what to do. Past those
    /// first few its length does not grow with the number of findings.
    static func report(_ findings: [Finding], of rule: Rule) -> String {
        let mine = findings.filter { $0.kind.rule == rule }
        var languages: [String] = []
        for finding in mine where !languages.contains(finding.language) { languages.append(finding.language) }
        var lines = ["\(rule.broken): \(mine.count) finding(s) in \(languages.count) table(s)."]
        for language in languages {
            let here = mine.filter { $0.language == language }
            lines.append("\(language).lproj/Localizable.strings: \(here.count) \(rule.counted); "
                         + "the first \(min(here.count, spelledOutPerTable)):")
            lines += here.prefix(spelledOutPerTable).map {
                ($0.line > 0 ? "  line \($0.line): " : "  ") + $0.detail
            }
        }
        lines.append("What to do: \(rule.remedy)")
        return lines.joined(separator: "\n")
    }
}
