import XCTest
@testable import Module_Hosts_Engine

/// What happens to a line when its `names` or `address` are replaced.
///
/// Task 3 adds `setNames`, `setAddress`, `setEnabled`, `append` and `remove`;
/// these tests are about the value underneath them, so they hold before and
/// after that lands. Everything here goes through `Entry`'s own public fields
/// and `render`, which is the same door a view model comes in by.
///
/// **`separators` is deliberately shorter than the names it separates** — a
/// name added to an entry gets a single space rather than a second array to
/// keep in step. The first half of this file is that claim, tried in every
/// direction. The second half is what a field editor can put in the file, and
/// it is where Task 3's refusals have to live: `render` writes whatever the
/// value says, `/etc/hosts` has a grammar, and nothing between them checks.
final class HostsEntryEditingHazardsTests: XCTestCase {

    /// `10.0.0.1␉a␠␠b␉c` — three names, two gaps, neither of them one space.
    private func aligned() throws -> HostsFile.Entry {
        try onlyEntry(of: "10.0.0.1\ta  b\tc\n")
    }

    /// Unwrapped rather than subscripted: a parser that stopped reading should
    /// fail this file's tests, not take the whole bundle's reporting down with
    /// an index out of range.
    private func onlyEntry(of text: String) throws -> HostsFile.Entry {
        try XCTUnwrap(HostsFile.parse(text).entries.first, "nothing was read from \(text.debugDescription)")
    }

    private func rendered(_ entry: HostsFile.Entry) -> String {
        HostsFile.render(HostsFile.Document(lines: [.entry(entry)]))
    }

    private func namesAfterAReadBack(_ entry: HostsFile.Entry) -> [String]? {
        HostsFile.parse(rendered(entry)).entries.first?.names
    }

    // MARK: - The gaps against every edit

    func testAnUntouchedEntryKeepsBothOfItsGaps() throws {
        XCTAssertEqual(rendered(try aligned()), "10.0.0.1\ta  b\tc\n")
    }

    /// A fourth name has no gap of its own, and takes a single space.
    func testANameAddedBeyondTheGapsTakesASingleSpace() throws {
        var entry = try aligned()
        entry.names = ["a", "b", "c", "d"]
        XCTAssertEqual(rendered(entry), "10.0.0.1\ta  b\tc d\n")
        XCTAssertEqual(namesAfterAReadBack(entry), ["a", "b", "c", "d"])
    }

    /// Two names removed leaves two gaps nobody needs. They are ignored, not
    /// applied to the wrong pair and not a crash — `separators[i]` is only
    /// reached inside a bounds check.
    func testNamesRemovedLeaveTheirGapsUnusedRatherThanMisapplied() throws {
        var entry = try aligned()
        entry.names = ["a"]
        XCTAssertEqual(rendered(entry), "10.0.0.1\ta\n")
        entry.names = ["a", "b"]
        XCTAssertEqual(rendered(entry), "10.0.0.1\ta  b\n")
        XCTAssertEqual(namesAfterAReadBack(entry), ["a", "b"])
    }

    /// The gaps belong to the line, not to the names that were in it, so a
    /// wholesale replacement keeps the alignment somebody typed.
    func testNamesReplacedWholesaleKeepTheLinesAlignment() throws {
        var entry = try aligned()
        entry.names = ["one", "two", "three"]
        XCTAssertEqual(rendered(entry), "10.0.0.1\tone  two\tthree\n")
        XCTAssertEqual(namesAfterAReadBack(entry), ["one", "two", "three"])
    }

    func testAnEntryWithOneNameNeverReachesForASeparator() throws {
        var entry = try onlyEntry(of: "127.0.0.1 solo\n")
        XCTAssertTrue(entry.separators.isEmpty)
        entry.names = ["solo", "second", "third"]
        XCTAssertEqual(rendered(entry), "127.0.0.1 solo second third\n")
    }

    /// Fifty names against two gaps, and back down to one. Nothing here may
    /// index past the end of `separators`.
    func testGrowingAndShrinkingRepeatedlyNeverIndexesPastTheGaps() throws {
        var entry = try aligned()
        for count in [50, 1, 7, 3, 1] {
            entry.names = (0..<count).map { "n\($0)" }
            XCTAssertEqual(namesAfterAReadBack(entry)?.count, count)
        }
    }

    // MARK: - What a field editor can put in the file

    /// **A row emptied of names stops being a row.** The address and the
    /// comment stay in the file, the table loses the line, and there is no way
    /// back to it from the table — the same shape as the aligned-columns
    /// defect this module just fixed. Task 3's `setNames` has to refuse an
    /// empty list rather than write this.
    func testAnEntryEmptiedOfNamesLeavesALineTheTableCannotShow() throws {
        var entry = try onlyEntry(of: "10.0.0.5\tbuild.local  # the CI box\n")
        entry.names = []
        let text = rendered(entry)
        XCTAssertTrue(text.contains("10.0.0.5"), "the line was still written: \(text.debugDescription)")
        XCTAssertEqual(HostsFile.parse(text).entries.count, 0,
                       "and it is no longer an entry anybody can see")
    }

    /// A name is a field, and whitespace ends a field. One name in, two names
    /// back — the mapping the person confirmed is not the mapping in the file.
    func testWhitespaceInsideANameSilentlyBecomesTwoNames() throws {
        var entry = try onlyEntry(of: "127.0.0.1 solo\n")
        entry.names = ["build local"]
        XCTAssertEqual(namesAfterAReadBack(entry), ["build", "local"])
        entry.names = ["build\tlocal"]
        XCTAssertEqual(namesAfterAReadBack(entry), ["build", "local"])
    }

    /// `#` ends the line wherever it sits, so half the name becomes a comment
    /// and the mapping quietly shortens.
    func testAHashInsideANameSilentlyTruncatesIt() throws {
        var entry = try onlyEntry(of: "127.0.0.1 solo\n")
        entry.names = ["build#local"]
        XCTAssertEqual(namesAfterAReadBack(entry), ["build"])
    }

    /// **A newline in a field is a second line in `/etc/hosts`.** The file is
    /// written with administrator rights, so a mapping nobody typed and nobody
    /// sees on the way past is the worst thing a field can produce here.
    /// Nothing in `HostsFile` refuses it: Task 3's editors must, and Task 4's
    /// gate is about the shell command, not about this grammar.
    func testANewlineInANameBecomesASecondMappingInTheFile() throws {
        var entry = try onlyEntry(of: "127.0.0.1 solo\n")
        entry.names = ["ok.local\n0.0.0.0 bank.example"]
        let document = HostsFile.parse(rendered(entry))
        XCTAssertEqual(document.entries.count, 2,
                       "one edited row wrote \(document.entries.count) mappings")
        XCTAssertEqual(document.entries.last?.address, "0.0.0.0")
        XCTAssertEqual(document.entries.last?.names, ["bank.example"])
    }

    func testANewlineInAnAddressBecomesASecondMappingInTheFile() throws {
        var entry = try onlyEntry(of: "127.0.0.1 solo\n")
        entry.address = "127.0.0.1 solo\n0.0.0.0"
        XCTAssertEqual(HostsFile.parse(rendered(entry)).entries.count, 2)
    }

    /// A space in the address is not a second address, it is a first name —
    /// and the row now maps somewhere else with a name it was never given.
    func testASpaceInsideAnAddressAddsANameToTheRow() throws {
        var entry = try onlyEntry(of: "127.0.0.1 solo\n")
        entry.address = "10.0.0.1 sneaky.local"
        let read = HostsFile.parse(rendered(entry)).entries.first
        XCTAssertEqual(read?.address, "10.0.0.1")
        XCTAssertEqual(read?.names, ["sneaky.local", "solo"])
    }
}
