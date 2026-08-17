import XCTest
@testable import Module_Hosts_Engine

/// The files nobody writes on purpose. `/etc/hosts` on a real machine has been
/// through installers, VPN clients, ad blockers, a Windows editor and somebody
/// in a hurry — so the parser is handed all of this whether it was designed
/// for it or not, and every one of these must come back unharmed.
final class HostsOddFilesTests: XCTestCase {

    private func assertSurvives(_ text: String, entries: Int, _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let document = HostsFile.parse(text)
        XCTAssertEqual(document.entries.count, entries, "\(what): entry count",
                       file: file, line: line)
        XCTAssertEqual(HostsFile.render(document), text, "\(what): the bytes",
                       file: file, line: line)
    }

    // MARK: - Nothing, and nearly nothing

    func testAnEmptyFileIsAnEmptyDocument() {
        let document = HostsFile.parse("")
        XCTAssertTrue(document.lines.isEmpty)
        XCTAssertEqual(HostsFile.render(document), "")
    }

    func testAFileOfNothingButLineEndingsSurvives() {
        assertSurvives("\n", entries: 0, "one newline")
        assertSurvives("\n\n\n", entries: 0, "three newlines")
        assertSurvives("\r\n\r\n", entries: 0, "two CRLFs")
        assertSurvives("\r", entries: 0, "a lone CR")
    }

    func testAFileOfNothingButBlanksSurvives() {
        assertSurvives("   \n\t\n \t \n", entries: 0, "whitespace-only lines")
        assertSurvives("   ", entries: 0, "blanks with no ending at all")
    }

    // MARK: - Lines that look like entries and are not

    /// No names left after the comment is taken off, so there is no mapping —
    /// and the line is somebody's, so it goes back exactly as it came.
    func testAnAddressWhoseNamesAreAllCommentIsNotAnEntry() {
        assertSurvives("127.0.0.1 #localhost\n", entries: 0, "an address and a comment")
        assertSurvives("127.0.0.1\t# localhost broadcasthost\n", entries: 0, "an address and prose")
    }

    func testAnAddressWithNoNamesAtAllIsNotAnEntry() {
        assertSurvives("127.0.0.1\n", entries: 0, "an address alone")
        assertSurvives("127.0.0.1  \n", entries: 0, "an address and trailing blanks")
        assertSurvives("::1\n", entries: 0, "an IPv6 address alone")
    }

    /// `#` binds tighter than the field split in every `/etc/hosts` reader, so
    /// `127.0.0.1#localhost` is an address with no names — not a host called
    /// `#localhost`.
    func testAHashWithNoSpaceAroundItStillEndsTheLine() {
        assertSurvives("127.0.0.1#localhost\n", entries: 0, "a hash against the address")
        assertSurvives("#\n", entries: 0, "a bare hash")
        assertSurvives("##\n", entries: 0, "Apple's rule line")
        assertSurvives("# 127.0.0.1 # 10.0.0.1 a\n", entries: 0, "a hash that re-opens")
    }

    func testATrailingCommentKeepsTheWhitespaceInFrontOfIt() throws {
        let entry = try XCTUnwrap(HostsFile.parse("127.0.0.1\tlocalhost\t\t # note\n").entries.first)
        XCTAssertEqual(entry.names, ["localhost"])
        XCTAssertEqual(entry.trailing, "\t\t # note")
    }

    // MARK: - Line endings

    /// A file whose lines end three different ways is one people really have,
    /// and each line keeps its own ending — a document that normalises them has
    /// rewritten every line in the file.
    func testMixedLineEndingsEachKeepTheirOwn() {
        let text = "127.0.0.1 a\r\n10.0.0.1 b\n192.168.0.1 c\r10.0.0.2 d"
        assertSurvives(text, entries: 4, "three endings and no final one")
        XCTAssertEqual(HostsFile.parse(text).entries.map(\.ending), ["\r\n", "\n", "\r", ""])
    }

    func testALastLineWithATrailingCRAndNoLFSurvives() {
        assertSurvives("127.0.0.1 a\r", entries: 1, "a line ending in CR at EOF")
    }

    // MARK: - Names people actually have

    func testAwkwardNamesAreKeptWhole() {
        for name in ["мой-хост.local", "🙂.example", ".hidden", "a/b", "a:b", "a\\b",
                     "UPPER.Case", "x".repeated(300), "-", "..", "a%b"] {
            let text = "127.0.0.1\t\(name)\n"
            XCTAssertEqual(HostsFile.parse(text).entries.first?.names, [name],
                           "\(name.debugDescription) was not kept whole")
            XCTAssertEqual(HostsFile.render(HostsFile.parse(text)), text)
        }
    }

    /// **`XCTAssertEqual` on two `String`s is not a byte comparison.** Swift
    /// compares by canonical equivalence, so the corpus's «byte for byte» is
    /// asserted nowhere: a parser that normalised what it read would rewrite
    /// every decomposed name in somebody's file and pass all nine cases. The
    /// two assertions below prove that trap is real before the third one
    /// closes it.
    func testTheBytesComeBackAndNotMerelyAnEquivalentString() {
        XCTAssertEqual("cafe\u{301}", "caf\u{E9}", "Swift's == is canonical equivalence")
        XCTAssertNotEqual(Array("cafe\u{301}".utf8), Array("caf\u{E9}".utf8),
                          "and the two spellings are different files on disk")

        let text = "127.0.0.1\tcafe\u{301}.local\tcafe\u{301}\n# 10.0.0.1\tsu\u{308}d.local\n"
        let rendered = HostsFile.render(HostsFile.parse(text))
        XCTAssertEqual(Array(rendered.utf8), Array(text.utf8),
                       "the file came back re-normalised")
    }

    // MARK: - Sizes

    /// One line, fifty thousand names — a generated block list with no newlines
    /// in it. The scan must stay linear and the line must stay one entry.
    func testOneEnormousLineIsOneEntry() {
        let names = (0..<50_000).map { "host\($0).example" }
        let text = "0.0.0.0\t" + names.joined(separator: " ") + "\n"
        let document = HostsFile.parse(text)
        XCTAssertEqual(document.entries.count, 1)
        XCTAssertEqual(document.entries.first?.names.count, 50_000)
        XCTAssertEqual(document.entries.first?.names.last, "host49999.example")
        XCTAssertEqual(HostsFile.render(document), text)
    }

    /// Every line of a large file disabled — the shape a blocker's file has
    /// when somebody switches it off, and the shape `setEnabled` will produce
    /// ten thousand times over.
    func testALargeFileOfDisabledEntriesIsReadAsDisabled() {
        let text = (0..<10_000).map { "# 0.0.0.0\tad\($0).example" }.joined(separator: "\n") + "\n"
        let document = HostsFile.parse(text)
        XCTAssertEqual(document.entries.count, 10_000)
        XCTAssertTrue(document.entries.allSatisfy { !$0.enabled }, "some line read as live")
        XCTAssertEqual(HostsFile.render(document), text)
    }
}

private extension String {
    func repeated(_ times: Int) -> String { String(repeating: self, count: times) }
}
