// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport

/// **Two readings of the same file, and picking the wrong one makes a guard
/// vacuous in either direction.**
///
/// `SwiftSource.code` blanks comments *and* the insides of string literals,
/// which is exactly right for every scan that counts punctuation — a call site,
/// a brace depth, a modifier chain — and exactly wrong for a scan whose subject
/// **is** a string literal. Put the orphan-translation scan on it and
/// `L("Off")` becomes `L("")`: all 1054 keys read as dead at once, which is a
/// guard failing loudly. The other half of that mistake is the one that hides —
/// reading the file **raw**, where a key named only in a comment reads as alive,
/// which is a guard that has quietly stopped being able to fail.
///
/// `Sources/HelmApp/AppStrings.swift` really does say «Not `L("Off")`», so the
/// raw reading really does keep the key «Off» alive by explaining why it is not
/// used there. Measured across the whole tree on 2026-08-21 the difference
/// between the two readings was **0 keys**, so nothing was orphaned by it —
/// this is the hole closed before something falls in it, not after.
///
/// `uncommented` is the third reading: comments blanked, string bodies kept.
/// It cannot be written by a line filter and it cannot be written without
/// parsing strings, because a `//` inside a string is not a comment — which is
/// why it shares `code`'s walk rather than being a second one.
final class ACommentIsNotAUseOfAKeyTests: XCTestCase {

    // MARK: - The reading the orphan scan needs

    /// The exact shape in the tree: a key named in prose to say it is *not*
    /// asked for, above a line that really does ask for another.
    ///
    /// Both halves are asserted, and the order is not decoration. «The comment's
    /// key is gone» alone is satisfied by a reader that returns nothing at all;
    /// asserting the live key first is what says the subject happened.
    func testAKeyNamedOnlyInACommentIsNotAKeyTheSourceAsksFor() {
        let read = SwiftSource.uncommented("""
        // The tick is drawn, not written: not `L("Off")` and never was.
        let label = L("On")
        """)
        XCTAssertTrue(read.contains("L(\"On\")"),
                      "the live key was blanked too — «\(read)»")
        XCTAssertFalse(read.contains("\"Off\""),
                       "a key explained in a comment still reads as asked for — «\(read)»")
    }

    /// The same in a doc comment, which is how this repository writes most of
    /// its prose — and in a block comment, which no line filter can end.
    func testProseIsBlankedWhicheverOfTheThreeWaysItIsWritten() {
        let read = SwiftSource.uncommented("""
        /// `L("Doc")` is named here to be explained.
        /* L("Block")
           still the same comment: L("BlockTwo") */
        let label = L("Real")
        """)
        XCTAssertTrue(read.contains("\"Real\""), "the live key was blanked — «\(read)»")
        for dead in ["Doc", "Block", "BlockTwo"] {
            XCTAssertFalse(read.contains("\"\(dead)\""),
                           "«\(dead)» survived its comment — «\(read)»")
        }
    }

    /// **The trap that makes this need a parser.** A `//` inside a string is not
    /// a comment, so blanking naively swallows the rest of the line — and the
    /// key after it.
    func testASlashInsideAStringDoesNotSwallowTheKeyAfterIt() {
        let read = SwiftSource.uncommented(#"""
        let url = "https://example.com"; let label = L("After")
        """#)
        XCTAssertTrue(read.contains("\"After\""),
                      "a URL's slashes were read as a comment — «\(read)»")
        XCTAssertTrue(read.contains("https://example.com"),
                      "the URL's own body was cut — «\(read)»")
    }

    /// A key quoted inside a `"""` block is still a string, and the block spans
    /// lines — the reading `RepoSource.code` cannot make one line at a time.
    func testAMultilineBlockIsOneStringAndItsContentSurvives() {
        let read = SwiftSource.uncommented(#"""
        let explanation = """
        // not a comment in here
        L("Quoted")
        """
        let label = L("Real")
        """#)
        XCTAssertTrue(read.contains("\"Quoted\""),
                      "a block's own body was blanked — «\(read)»")
        XCTAssertTrue(read.contains("\"Real\""), "the code after the block was lost — «\(read)»")
    }

    /// A raw string keeps its escapes: `#"…\n…"#` has no escape at all, and a
    /// reader that treated `\` as one would end the literal two characters late
    /// and read the code after it as string.
    func testARawStringIsReadToItsOwnDelimiter() {
        let read = SwiftSource.uncommented(#"""
        let pattern = #"\bL\("#
        let label = L("Real")
        """#)
        XCTAssertTrue(read.contains("\"Real\""),
                      "the raw string never ended, so the code after it was swallowed — «\(read)»")
    }

    /// An escaped quote does not end the literal, and comes back **as it was
    /// written**: the orphan scan decodes `\"` itself, after this runs, and a
    /// reader that decoded it first would end four changelog keys early.
    func testAnEscapedQuoteNeitherEndsTheStringNorIsDecoded() {
        let read = SwiftSource.uncommented(#"""
        let label = L("He said \"Date Added\" once") // L("Dead")
        """#)
        XCTAssertTrue(read.contains(#"\"Date Added\""#),
                      "the escape was decoded by the reader — «\(read)»")
        XCTAssertFalse(read.contains("\"Dead\""), "the tail comment survived — «\(read)»")
    }

    /// A finding still names a line, so a comment leaves its newlines where they
    /// were — including a block comment four lines tall.
    func testBlankingACommentKeepsEveryLineWhereItWas() {
        let source = """
        let a = 1
        /* one
           two
           three */
        let b = L("Real")
        """
        let read = SwiftSource.uncommented(source)
        XCTAssertEqual(read.components(separatedBy: "\n").count,
                       source.components(separatedBy: "\n").count,
                       "lines moved — «\(read)»")
        let lines = read.components(separatedBy: "\n")
        XCTAssertTrue(lines[4].contains("\"Real\""),
                      "the key is no longer on line 5 — \(lines)")
    }

    // MARK: - And the other reading still blanks what it always did

    /// The half `code` must keep doing, stated here rather than only inside the
    /// keychain-port guard that happens to use it: a scan that counts
    /// parentheses must not see a literal's.
    func testTheOtherReadingStillBlanksTheInsidesOfStrings() {
        let read = SwiftSource.code(#"let label = L("Off"); let n = f("a) b")"#)
        XCTAssertFalse(read.contains("Off"), "«\(read)»")
        XCTAssertFalse(read.contains("a) b"), "«\(read)»")
        XCTAssertTrue(read.contains("let label = L("), "the code around it went too — «\(read)»")
    }

    /// **The two readings differ, and this file would be worth nothing if they
    /// did not.** A `uncommented` wired to `code` — one line — passes every
    /// assertion above about what is *absent* and fails only here.
    func testTheTwoReadingsAreNotTheSameFunction() {
        let source = #"let label = L("Off") // and L("Dead")"#
        XCTAssertNotEqual(SwiftSource.uncommented(source), SwiftSource.code(source))
        XCTAssertTrue(SwiftSource.uncommented(source).contains("\"Off\""))
        XCTAssertFalse(SwiftSource.code(source).contains("Off"))
    }

    // MARK: - The inputs a tree scan cannot be relied on to contain

    /// Nothing, one character, a literal nobody closed, a comment that runs off
    /// the end, a block comment that is not nested however it looks, CRLF, a
    /// tab, a flag and a family emoji — each of which is one `Character` and
    /// several scalars.
    ///
    /// These were written to make a rewrite of the walk provable, and they stay
    /// because half of them cannot occur in `Sources/` today and every one of
    /// them is a way for an index walk to run off its own array.
    private static let traps: [String] = [
        "", "\n", "//", "// no newline at the end", "/*", "/* never closed\nsecond line",
        "/*/ this is still open */ after", "/* /* not nested */ after",
        "\"", "\"unterminated", "\"\"", "\"\"\"", "\"\"\"\"\"\"", "\"tail escape \\",
        "let a = \"one\\\"two\" // tail", "#\"raw \\ not an escape\"#",
        "#\"\"\"\nraw block // not a comment\n\"\"\"#",
        "\"\"\"\nblock \\\ncontinued\n\"\"\"",
        "let u = \"https://x\"; let v = 1 // c",
        "emoji \"🇷🇺 in a string\" and 👨‍👩‍👧‍👦 outside // 🇩🇪",
        "\r\n// crlf comment\r\nlet a = 1\r\n", "\t// tab-led\n\tlet a = \"b\"\n",
        "let a = \"\\u{2014}\" // \\u{2014}", "/// doc `L(\"Off\")`\nlet b = L(\"On\")",
    ]

    /// **`code` is `uncommented` with the literals taken out, and never the
    /// other way round.** One length comparison, and it is the shape of the
    /// regression the orphan scan is afraid of: `code` starting to keep string
    /// bodies would make that scan pass over a file it can no longer read, and
    /// nothing else in the suite compares the two.
    ///
    /// Over every trap above *and* every Swift file in the repository, so the
    /// claim is about the reader rather than about twenty-four fixtures.
    func testTheBlankingReadingIsNeverTheLongerOfTheTwo() throws {
        var inputs = Self.traps
        var files = try RepoSource.swiftFiles(under: "Sources")
        files += try RepoSource.swiftFiles(under: "Tests")
        XCTAssertGreaterThan(files.count, 400,
                             "only \(files.count) files were walked, so a pass means nothing")
        inputs += try files.map { try RepoSource.text(of: $0) }

        for source in inputs {
            let blanked = SwiftSource.code(source)
            let kept = SwiftSource.uncommented(source)
            XCTAssertLessThanOrEqual(blanked.count, kept.count,
                                     "the blanking reading returned more than the keeping one "
                                     + "for «\(source.prefix(60))»")
            XCTAssertLessThanOrEqual(kept.count, source.count + 1,
                                     "the keeping reading invented characters for "
                                     + "«\(source.prefix(60))»")
        }
    }
}
