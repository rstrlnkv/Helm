import XCTest
@testable import Module_Homebrew_Engine

/// `BrewConfigParser.parse` against `brew config`'s real answer.
///
/// The fixture below is captured verbatim from:
///
///     $ /opt/homebrew/bin/brew config > /tmp/cfg.out 2> /tmp/cfg.err; echo "exit=$?"
///     exit=0
///     555 /tmp/cfg.out
///       0 /tmp/cfg.err
///
/// on this machine, Homebrew 7.0.1, 2026-09-15 — eighteen lines, five of whose
/// values carry a colon of their own, and no heading anywhere in it.
final class BrewConfigParserTests: XCTestCase {

    /// Byte-for-byte what `/tmp/cfg.out` held, trailing newline and all.
    /// Reused across cases so a slip while retyping cannot make two tests
    /// disagree about what "real output" is.
    private static let capturedOutput = """
        HOMEBREW_VERSION: 7.0.1
        ORIGIN: https://github.com/Homebrew/brew
        HEAD: b3625f73d3e3574c5789ee32eb7b06627b788ec4
        Last commit: 2 days ago
        Branch: stable
        Core tap: N/A
        Core cask tap: N/A
        HOMEBREW_PREFIX: /opt/homebrew
        Homebrew Ruby: 4.0.6 => /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.6_2/bin/ruby
        CPU: 11-core 64-bit arm_lobos
        Clang: 21.0.0 build 2100
        Git: 2.54.0 => /Applications/Xcode.app/Contents/Developer/usr/bin/git
        Curl: 8.7.1 => /usr/bin/curl
        macOS: 27.0-arm64
        CLT: 27.0.0.0.1788430756
        Xcode: 27.0
        Metal Toolchain: N/A
        Rosetta 2: false

        """

    /// Every key of that capture and the heading it must be drawn under —
    /// **the list the hand-written mapping is checked against**, in the order
    /// brew printed them.
    private static let expectedSections: [(key: String, section: ConfigSection)] = [
        ("HOMEBREW_VERSION", .brew),
        ("ORIGIN", .brew),
        ("HEAD", .brew),
        ("Last commit", .brew),
        ("Branch", .brew),
        ("Core tap", .brew),
        ("Core cask tap", .brew),
        ("HOMEBREW_PREFIX", .brew),
        ("Homebrew Ruby", .brew),
        ("CPU", .machine),
        ("Clang", .tools),
        ("Git", .tools),
        ("Curl", .tools),
        ("macOS", .machine),
        ("CLT", .tools),
        ("Xcode", .tools),
        ("Metal Toolchain", .tools),
        ("Rosetta 2", .machine),
    ]

    /// Every key brew printed reaches a line, in brew's own order, under the
    /// heading the table names for it. Keys are asserted as brew spells them —
    /// `CLT`, `Rosetta 2`, `HOMEBREW_PREFIX` are Homebrew's words for these
    /// things and this module does not re-spell one.
    func testTheCapturedDocumentParsesIntoEveryLineUnderItsOwnHeading() throws {
        let lines = try XCTUnwrap(BrewConfigParser.parse(Self.capturedOutput))

        XCTAssertEqual(lines.map(\.key), Self.expectedSections.map(\.key), """
            the keys brew printed are not the keys that came back — a line was dropped, \
            re-spelled, or read in an order that is not brew's
            """)
        XCTAssertEqual(lines.map(\.section), Self.expectedSections.map(\.section), """
            a key was drawn under the wrong heading: \
            \(zip(lines, Self.expectedSections).filter { $0.0.section != $0.1.section }
                .map { "\($0.0.key) → \($0.0.section.rawValue), wanted \($0.1.section.rawValue)" })
            """)
    }

    /// **The mapping itself, not the parser's answer.** Asserting only on
    /// `parse` above cannot see a `.brew` entry deleted from the table —
    /// `BrewConfigParser.section(of:)` falls back to `.brew`, so nine of the
    /// eighteen would go on reading correctly with nothing in the table at all.
    /// This one asks the table directly, so every key this Mac produced has to
    /// be named in it.
    func testTheHandWrittenTableNamesEveryKeyThisMacProduced() {
        for (key, section) in Self.expectedSections {
            XCTAssertEqual(BrewConfigParser.sections[key], section, """
                `\(key)` is not in `BrewConfigParser.sections` with heading \
                \(section.rawValue) — the table beside the parser has stopped naming a key \
                `brew config` prints on this machine
                """)
        }
    }

    /// A key the table does not know is still drawn, under `.brew`. Homebrew
    /// adds keys between releases — `Core cask tap` and `Metal Toolchain` are
    /// both newer than the capture this feature was designed against — and a
    /// value nobody sees is worse than one under an imperfect heading.
    func testAKeyTheTableDoesNotKnowIsPlacedRatherThanDropped() throws {
        let text = "HOMEBREW_VERSION: 7.0.1\nHOMEBREW_SOMETHING_NEW: yes\n"
        let lines = try XCTUnwrap(BrewConfigParser.parse(text))

        XCTAssertNil(BrewConfigParser.sections["HOMEBREW_SOMETHING_NEW"],
                     "precondition: this key is the one the table does not know")
        XCTAssertEqual(lines.map(\.key), ["HOMEBREW_VERSION", "HOMEBREW_SOMETHING_NEW"], """
            a key with no entry in the table was dropped, so a line `brew config` printed \
            about this Mac appears nowhere at all
            """)
        XCTAssertEqual(lines.last?.section, .brew)
    }

    /// **The first colon, on brew's own lines.**
    ///
    /// `ORIGIN` is the line this case exists for: its value is a URL, so it
    /// holds a second colon, and a scan for the *last* colon reads
    /// `ORIGIN: https` as the key and hands back `//github.com/Homebrew/brew`.
    /// The two `version => /path` values are here beside it because a split
    /// that kept only the last field would still produce a plausible-looking
    /// path and no assertion about a URL would see it.
    ///
    /// Written against `": "` this whole case would be a rule about nothing:
    /// no value on this machine holds a colon followed by a space, so first and
    /// last agree on all eighteen lines and the loosening cannot be seen.
    func testAValueKeepsItsOwnColonsAndItsWholeArrow() throws {
        let lines = try XCTUnwrap(BrewConfigParser.parse(Self.capturedOutput))
        func value(_ key: String) -> String? { lines.first { $0.key == key }?.value }

        XCTAssertEqual(value("ORIGIN"), "https://github.com/Homebrew/brew")
        XCTAssertEqual(
            value("Homebrew Ruby"),
            "4.0.6 => /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.6_2/bin/ruby")
        XCTAssertEqual(value("Git"),
                       "2.54.0 => /Applications/Xcode.app/Contents/Developer/usr/bin/git")
        // Not a colon case, and here on purpose: a parser that stripped
        // everything after the first colon *in the value* would still pass the
        // three above by accident of where their colons sit.
        XCTAssertEqual(value("macOS"), "27.0-arm64")
    }

    /// One space after the colon is the format's and is dropped; a second is
    /// the value's and is kept. Synthetic rather than captured — this Mac
    /// prints exactly one space — and here because the alternative to "drop one
    /// space" is a trim, which would silently eat indentation a value meant to
    /// carry.
    func testOnlyTheFormatsOwnSpaceIsDropped() throws {
        let lines = try XCTUnwrap(BrewConfigParser.parse("A:  two spaces\nB:none\n"))
        XCTAssertEqual(lines.map(\.value), [" two spaces", "none"])
    }

    /// A document cut off mid-line — which is what a run ended at a deadline
    /// leaves — keeps every complete line and drops the partial one. Half a key
    /// under a heading is worse than the line not being there.
    func testATruncatedDocumentKeepsItsCompleteLinesAndDropsThePartialOne() throws {
        let whole = Self.capturedOutput
        // Cut inside `Metal Toolchain`, before its separator: the line that
        // survives the cut is not yet a `key: value`.
        let cut = whole.range(of: "Metal Tool")
        let truncated = String(whole[whole.startIndex..<(cut.map(\.upperBound) ?? whole.endIndex)])
        XCTAssertTrue(truncated.hasSuffix("Metal Tool"), "precondition: the cut is mid-key")

        let lines = try XCTUnwrap(BrewConfigParser.parse(truncated))
        XCTAssertEqual(lines.map(\.key),
                       Array(Self.expectedSections.map(\.key).prefix(16)), """
            the partial last line was read as a configuration key, or a complete line before \
            it was lost with it
            """)
        XCTAssertEqual(lines.last?.key, "Xcode")
        XCTAssertEqual(lines.last?.value, "27.0")
    }

    /// Empty input is nil — the tool said nothing, which is not the claim
    /// «this Mac has no configuration». A refused or never-run query produces
    /// exactly this input.
    func testEmptyInputIsNil() {
        XCTAssertNil(BrewConfigParser.parse(""))
    }

    /// And so is real output in which no line is a `key: value` at all.
    /// `brew config` always prints such lines, so output made of nothing else
    /// is output this build did not understand — not a reading of the machine.
    /// Unlike `DoctorParser`, there is no `[]` answer here to confuse it with.
    func testOutputWithNoKeyValueLineIsNil() {
        XCTAssertNil(BrewConfigParser.parse("==> Downloading\nsomething went wrong\n"))
        XCTAssertNil(BrewConfigParser.parse("\n\n\n"))
        XCTAssertNil(BrewConfigParser.parse("   \n"))
        // A key with nothing before the separator is not a key: the line is
        // passed over, and a document made only of such lines answers nil like
        // any other document with no `key: value` in it.
        XCTAssertNil(BrewConfigParser.parse(": 7.0.1\n"))
    }
}
