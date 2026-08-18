import XCTest
@testable import Module_Hosts_Engine

/// **The third assertion the corpus needs.** `render(parse(x)) == x` says
/// nothing was reformatted and the entry count says something was read;
/// neither says *what*. `render` is a concatenation of the pieces the parser
/// cut the line into, so any cut that joins back up satisfies both.
///
/// Four mutations were planted in `HostsFile.swift` on 2026-08-18 and left the
/// whole of `HostsRoundTripTests` **green** — the file came back byte for byte
/// with the right number of entries in it, and every one of them is wrong:
///
/// - the trailing comment left unsplit, so `# the link-local one` reads as four
///   more names of the host;
/// - `separators` written in reverse — invisible until an entry has two gaps
///   that differ, and no case in the corpus has two;
/// - `enabled` nailed to `true`; likewise a commented mapping refused as an
///   entry. The corpus holds no disabled entry at all, and the switch is what
///   the tab is for;
/// - the line split on `Character.isNewline`, which answers `true` for U+0085,
///   U+2028, U+2029, VT and FF. The separator becomes the first line's ending
///   and the rest a verbatim line, so the bytes *and* the count both survive.
///
/// Two more — `spacing` left on the front of the first name, and the names
/// never split at all — are caught by the corpus, and by exactly one assertion
/// in it: `testAlignedNamesAreOneEntryWithBothNames`, the one case that looks
/// at content. That is the assertion this file generalises to every case.
final class HostsParseStructureTests: XCTestCase {

    /// One parsed entry, reduced to what a person would read off the table.
    private struct Row: Equatable, CustomStringConvertible {
        var address: String
        var names: [String]
        var enabled = true
        var trailing = ""

        var description: String {
            "\(enabled ? "" : "«off» ")\(address) → \(names)"
                + (trailing.isEmpty ? "" : " ⟨\(trailing)⟩")
        }
    }

    private func rows(of text: String) -> [Row] {
        HostsFile.parse(text).entries.map {
            Row(address: $0.address, names: $0.names, enabled: $0.enabled, trailing: $0.trailing)
        }
    }

    /// Asserts the structure *and* the bytes, because a structure assertion on
    /// its own would let a parser that reads correctly and writes badly through.
    private func assertReads(_ text: String, as expected: [Row],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rows(of: text), expected, file: file, line: line)
        XCTAssertEqual(HostsFile.render(HostsFile.parse(text)), text,
                       "the bytes did not survive", file: file, line: line)
    }

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

    func testTheDefaultFileIsReadAsThreeNamedMappings() {
        assertReads(appleDefault, as: [
            Row(address: "127.0.0.1", names: ["localhost"]),
            Row(address: "255.255.255.255", names: ["broadcasthost"]),
            Row(address: "::1", names: ["localhost"]),
        ])
    }

    /// Apple's header is six lines of prose and it stays six lines of prose:
    /// `# localhost is used to configure…` begins with a word that is not an
    /// address, and nothing in it may become a row somebody can switch on.
    func testTheHeaderStaysVerbatimAndInPlace() {
        let lines = HostsFile.parse(appleDefault).lines
        let kinds = lines.map { if case .entry = $0 { return "e" } else { return "v" } }
        XCTAssertEqual(kinds.joined(), "vvvvvveee")
    }

    func testAnAlignedLineIsTwoNamesAndNotOneNameWithSpacesInIt() {
        assertReads("10.0.0.1\t\tbox.local     box\n", as: [
            Row(address: "10.0.0.1", names: ["box.local", "box"]),
        ])
    }

    /// The gaps are kept in the order they were read. An entry with two names
    /// has one gap and cannot tell a reversal from the truth — no case in the
    /// corpus has more — so this one has three names and two unequal gaps.
    func testTheGapsBetweenNamesAreKeptInOrder() throws {
        let text = "10.0.0.1\ta  b\tc\n"
        let entry = try XCTUnwrap(HostsFile.parse(text).entries.first)
        XCTAssertEqual(entry.names, ["a", "b", "c"])
        XCTAssertEqual(entry.separators, ["  ", "\t"])
        XCTAssertEqual(HostsFile.render(HostsFile.parse(text)), text)
    }

    /// The comment is the comment. Left unsplit it becomes four more names of
    /// the host, and the file still comes back byte for byte with one entry in
    /// it — so only this assertion sees it.
    func testATrailingCommentIsNotReadAsMoreNames() {
        assertReads("fe80::1%lo0\tlocalhost  # the link-local one\n", as: [
            Row(address: "fe80::1%lo0", names: ["localhost"], trailing: "  # the link-local one"),
        ])
    }

    /// **The corpus has no disabled entry, and disabling is what the tab does.**
    /// A commented mapping is an entry that is switched off; refused, it is a
    /// row nobody can switch back on, and read as enabled it is a switch that
    /// draws the wrong way round.
    func testACommentedMappingIsADisabledEntryAndKeepsItsComment() {
        assertReads("# 10.0.0.5\tbuild.local  # the CI box\n", as: [
            Row(address: "10.0.0.5", names: ["build.local"],
                enabled: false, trailing: "  # the CI box"),
        ])
    }

    func testADisabledEntryIsReadWithOrWithoutASpaceAfterTheHash() {
        assertReads("#10.0.0.5\tbuild.local\n#\t10.0.0.6\tother.local\n", as: [
            Row(address: "10.0.0.5", names: ["build.local"], enabled: false),
            Row(address: "10.0.0.6", names: ["other.local"], enabled: false),
        ])
    }

    /// `/etc/hosts` ends a line at `\n` (and, for a file that came from
    /// Windows, at `\r\n`). Swift's `Character.isNewline` also answers `true`
    /// for NEL, LS, PS, VT and FF — so a reader written on it splits a line the
    /// system does not, and *the bytes and the count both survive that*: the
    /// separator becomes the first line's ending and the remainder a verbatim
    /// line, leaving one entry either way.
    func testAnExoticSeparatorInsideALineIsPartOfTheNameNotALineBreak() {
        for scalar in ["\u{85}", "\u{2028}", "\u{2029}", "\u{0B}", "\u{0C}"] {
            let text = "127.0.0.1\ta\(scalar)b\n"
            XCTAssertEqual(rows(of: text),
                           [Row(address: "127.0.0.1", names: ["a\(scalar)b"])],
                           "U+\(String(format: "%04X", scalar.unicodeScalars.first!.value)) split a line")
            XCTAssertEqual(HostsFile.render(HostsFile.parse(text)), text)
        }
    }

    func testCRLFIsTwoEntriesAndNotOneLongName() {
        assertReads("127.0.0.1\tlocalhost\r\n10.0.0.1\tbox\r\n", as: [
            Row(address: "127.0.0.1", names: ["localhost"]),
            Row(address: "10.0.0.1", names: ["box"]),
        ])
    }

    func testAJunkLineContributesNoEntryAndTheRealOneIsStillRead() {
        assertReads("this is not a hosts line at all\n127.0.0.1 a\n", as: [
            Row(address: "127.0.0.1", names: ["a"]),
        ])
    }
}
