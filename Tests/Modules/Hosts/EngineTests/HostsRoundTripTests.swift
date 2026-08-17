import XCTest
@testable import Module_Hosts_Engine

/// `render(parse(x)) == x`, byte for byte, over everything a real `/etc/hosts`
/// turns out to be. Every case below is a file this parser met and mangled in
/// some earlier shape of itself, or one macOS ships.
///
/// **Byte equality alone cannot fail here**, which is why every case also says
/// how many entries it holds: a parser that reads nothing and keeps every line
/// verbatim reproduces all eight files exactly. Two defects were living behind
/// that — a CRLF file swallowed whole, and aligned columns refused — and both
/// were invisible to the comparison.
final class HostsRoundTripTests: XCTestCase {

    /// What macOS puts there on a fresh install.
    private let appleDefault = """
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    # when the system is booting.  Do not change this entry.
    ##
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    ::1             localhost

    """

    private func assertRoundTrips(_ text: String,
                                  _ what: String,
                                  entries expected: Int,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let document = HostsFile.parse(text)
        XCTAssertEqual(document.entries.count, expected,
                       "\(what) was not read as \(expected) entries",
                       file: file, line: line)
        XCTAssertEqual(HostsFile.render(document), text,
                       "\(what) did not survive the round trip",
                       file: file, line: line)
    }

    func testTheDefaultFileSurvives() {
        assertRoundTrips(appleDefault, "the file macOS ships", entries: 3)
    }

    func testTabsAndRunsOfSpacesSurvive() {
        assertRoundTrips("10.0.0.1\t\tbox.local     box\n", "the original spacing", entries: 1)
    }

    /// Swift makes CRLF one `Character` — a grapheme cluster — so a reader
    /// written to match `"\r"` and peek ahead for `"\n"` matches neither half
    /// and takes the whole file as a single line. Only the count sees that.
    func testCRLFSurvives() {
        assertRoundTrips("127.0.0.1\tlocalhost\r\n10.0.0.1\tbox\r\n",
                         "CRLF line endings", entries: 2)
    }

    func testAFileWithNoTrailingNewlineSurvives() {
        assertRoundTrips("127.0.0.1 localhost", "a file with no trailing newline", entries: 1)
    }

    func testIPv6AndTrailingCommentsSurvive() {
        assertRoundTrips("fe80::1%lo0\tlocalhost  # the link-local one\n",
                         "an IPv6 entry", entries: 1)
    }

    func testBlankLinesAndTheirCountSurvive() {
        assertRoundTrips("127.0.0.1 a\n\n\n\n10.0.0.1 b\n", "four blank lines", entries: 2)
    }

    func testAJunkLineSurvivesUntouched() {
        assertRoundTrips("this is not a hosts line at all\n127.0.0.1 a\n",
                         "a line the parser cannot read", entries: 1)
    }

    /// Aligned columns are how a hand-maintained hosts file looks, and the run
    /// of spaces between two names is the entry's own — a line dropped from the
    /// table for having them is a line nobody can disable.
    func testAlignedNamesAreOneEntryWithBothNames() {
        let entries = HostsFile.parse("10.0.0.1\t\tbox.local     box\n").entries
        XCTAssertEqual(entries.map(\.names), [["box.local", "box"]])
    }

    func testALargeFileSurvives() {
        let big = (0..<5000).map { "10.0.\($0 / 256).\($0 % 256)\thost\($0).local" }
            .joined(separator: "\n") + "\n"
        assertRoundTrips(big, "5000 entries", entries: 5000)
    }
}
