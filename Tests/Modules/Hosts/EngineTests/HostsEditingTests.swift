import XCTest
@testable import Module_Hosts_Engine

/// An edit touches its own line and nothing else. The neighbours in every test
/// below are what a person's real file is made of.
final class HostsEditingTests: XCTestCase {

    private let hostsFile = """
    ##
    # Host Database
    ##
    127.0.0.1\tlocalhost
    10.0.0.5\tbuild.local  # the CI box

    """

    /// Runs an editor over the fixture and hands back the file it produced.
    ///
    /// The id check rides along on every case rather than sitting in one test
    /// of its own: `index` is what a `ForEach` row is identified by, and two
    /// rows sharing one is a table that loses a person's caret mid-edit.
    private func edited(_ change: (inout HostsFile.Document) -> Void,
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        var document = HostsFile.parse(hostsFile)
        change(&document)
        XCTAssertEqual(Set(document.entries.map(\.id)).count, document.entries.count,
                       "two entries share an id after the edit", file: file, line: line)
        return HostsFile.render(document)
    }

    // MARK: - Switching a line off and on again

    func testDisablingCommentsTheLineAndKeepsItsComment() {
        let out = edited { _ = HostsFile.setEnabled(false, at: 1, in: &$0) }
        XCTAssertTrue(out.contains("# 10.0.0.5\tbuild.local  # the CI box"),
                      "the entry lost its spacing or its comment:\n\(out)")
    }

    func testDisablingAndEnablingReturnsTheOriginalBytes() {
        let out = edited {
            _ = HostsFile.setEnabled(false, at: 1, in: &$0)
            _ = HostsFile.setEnabled(true, at: 1, in: &$0)
        }
        XCTAssertEqual(Array(out.utf8), Array(hostsFile.utf8))
    }

    /// The other direction, which the case above cannot reach: an entry that
    /// arrived **already commented**, in a spelling that is not `"# "`. Its own
    /// spelling has to come back, or a person who disables and re-enables a
    /// line has silently rewritten it.
    func testAnEntryThatArrivedCommentedKeepsItsOwnSpelling() {
        let original = "#\t10.0.0.5\tbuild.local\n"
        var document = HostsFile.parse(original)
        XCTAssertEqual(document.entries.count, 1)
        XCTAssertFalse(document.entries[0].enabled)
        XCTAssertEqual(HostsFile.setEnabled(true, at: 0, in: &document), .applied)
        XCTAssertEqual(HostsFile.setEnabled(false, at: 0, in: &document), .applied)
        XCTAssertEqual(Array(HostsFile.render(document).utf8), Array(original.utf8))
    }

    func testAReadBackDisabledEntryIsAnEntry() {
        let out = edited { _ = HostsFile.setEnabled(false, at: 1, in: &$0) }
        let entries = HostsFile.parse(out).entries
        XCTAssertEqual(entries.count, 2)
        XCTAssertFalse(entries[1].enabled)
        XCTAssertEqual(entries[1].names, ["build.local"])
    }

    // MARK: - The edits that are allowed

    func testChangingAnAddressLeavesEveryOtherLineAlone() {
        let out = edited { _ = HostsFile.setAddress("10.0.0.9", at: 1, in: &$0) }
        XCTAssertTrue(out.hasPrefix("##\n# Host Database\n##\n127.0.0.1\tlocalhost\n"))
        XCTAssertTrue(out.contains("10.0.0.9\tbuild.local  # the CI box"))
    }

    /// The point of an accepted edit: the file says what the person asked for.
    /// Byte assertions above say the neighbours are untouched; this says the
    /// edited row reads back as the edit.
    func testAnAcceptedEditReadsBackAsWhatWasAsked() {
        let out = edited {
            XCTAssertEqual(HostsFile.setAddress("10.0.0.9", at: 1, in: &$0), .applied)
            XCTAssertEqual(HostsFile.setNames(["ci.local", "ci"], at: 1, in: &$0), .applied)
        }
        let entries = HostsFile.parse(out).entries
        XCTAssertEqual(entries.map(\.address), ["127.0.0.1", "10.0.0.9"])
        XCTAssertEqual(entries.map(\.names), [["localhost"], ["ci.local", "ci"]])
    }

    func testAnAddedEntryLandsAtTheEndWithATab() {
        let out = edited { _ = HostsFile.append(address: "192.168.1.2", names: ["nas"], in: &$0) }
        XCTAssertTrue(out.hasSuffix("192.168.1.2\tnas\n"), out)
    }

    func testAnAddedEntryDoesNotGlueItselfToAFileWithNoTrailingNewline() {
        var document = HostsFile.parse("127.0.0.1 a")
        XCTAssertEqual(HostsFile.append(address: "10.0.0.1", names: ["b"], in: &document), .applied)
        XCTAssertEqual(HostsFile.render(document), "127.0.0.1 a\n10.0.0.1\tb\n")
    }

    func testRemovingAnEntryLeavesTheHeaderAndTheOtherEntry() {
        let out = edited { _ = HostsFile.remove(at: 0, in: &$0) }
        XCTAssertTrue(out.hasPrefix("##\n# Host Database\n##\n"))
        XCTAssertFalse(out.contains("localhost"))
        XCTAssertTrue(out.contains("build.local"))
    }

    /// `index` is the id, so an insert or a remove that does not renumber
    /// leaves two rows answering to one id — the row a `ForEach` rebuilds is
    /// then somebody else's.
    func testIdsAreRenumberedAfterEveryInsertAndRemove() {
        var document = HostsFile.parse(hostsFile)
        func idsAreUnique(_ what: String) {
            XCTAssertEqual(Set(document.entries.map(\.id)).count, document.entries.count, what)
        }
        XCTAssertEqual(HostsFile.append(address: "10.0.0.7", names: ["a"], in: &document), .applied)
        idsAreUnique("after the first append")
        XCTAssertEqual(HostsFile.remove(at: 0, in: &document), .applied)
        idsAreUnique("after the remove")
        XCTAssertEqual(HostsFile.append(address: "10.0.0.8", names: ["b"], in: &document), .applied)
        idsAreUnique("after the second append")
        XCTAssertEqual(document.entries.map(\.id), [0, 1, 2])
    }

    // MARK: - The edits that are refused
    //
    // **This is the gate on the file's grammar, and there is no other one.**
    // Task 4's base64 alphabet is about the shell command that carries the
    // file; a newline inside an edited name produces a perfectly well-formed
    // file that says something the person did not, and it goes to `/etc/hosts`
    // with administrator rights. A refusal, never a quiet repair: a field
    // editor that rewrites what somebody typed has changed a mapping without
    // saying so, which is the same defect wearing a tidier coat.

    /// Every refusal is the same shape — the reason comes back and the
    /// document is byte-for-byte the one that was handed in.
    private func assertRefused(_ why: HostsFile.Refusal,
                               _ change: (inout HostsFile.Document) -> HostsFile.Edit,
                               file: StaticString = #filePath, line: UInt = #line) {
        var document = HostsFile.parse(hostsFile)
        let before = document
        XCTAssertEqual(change(&document), .refused(why), "it was not refused", file: file, line: line)
        XCTAssertEqual(document, before, "the document was edited anyway", file: file, line: line)
        XCTAssertEqual(Array(HostsFile.render(document).utf8), Array(hostsFile.utf8),
                       "the file came back changed", file: file, line: line)
    }

    /// **The sharpest one.** One row asked for, two mappings written, and the
    /// second is `0.0.0.0 bank.example` — a name nobody typed, resolved by
    /// every program on the machine.
    ///
    /// **The line ending has to be the only thing wrong with the first two
    /// payloads**, or this test cannot tell a gate that refuses newlines from
    /// one that refuses the space in `0.0.0.0 bank.example` and lets the
    /// newline past. Measured on 2026-08-18: with `isWritableName` narrowed to
    /// a space, a tab and a `#`, the whole bundle stayed green until these two
    /// cases were added.
    func testANewlineInANameIsRefusedRatherThanWrittenAsASecondMapping() {
        assertRefused(.unwritableName) { HostsFile.setNames(["ok.local\nbank.example"], at: 1, in: &$0) }
        assertRefused(.unwritableName) { HostsFile.setNames(["ok.local\r\nbank.example"], at: 1, in: &$0) }
        assertRefused(.unwritableName) { HostsFile.setNames(["ok.local\rbank.example"], at: 1, in: &$0) }
        assertRefused(.unwritableName) {
            HostsFile.setNames(["ok.local\n0.0.0.0 bank.example"], at: 1, in: &$0)
        }
    }

    func testANewlineInAnAddressIsRefused() {
        assertRefused(.unwritableAddress) {
            HostsFile.setAddress("127.0.0.1 solo\n0.0.0.0", at: 1, in: &$0)
        }
    }

    /// A space in the address is not a second address, it is a first name —
    /// the row maps somewhere else under a name it was never given.
    func testASpaceInsideAnAddressIsRefused() {
        assertRefused(.unwritableAddress) { HostsFile.setAddress("10.0.0.1 sneaky.local", at: 1, in: &$0) }
    }

    /// Whitespace ends a field, so one name in comes back as two names out.
    func testWhitespaceInsideANameIsRefused() {
        assertRefused(.unwritableName) { HostsFile.setNames(["build local"], at: 1, in: &$0) }
        assertRefused(.unwritableName) { HostsFile.setNames(["build\tlocal"], at: 1, in: &$0) }
        assertRefused(.unwritableName) { HostsFile.setNames(["build.local "], at: 1, in: &$0) }
    }

    /// `#` ends the line wherever it sits, so half the name becomes a comment
    /// and the mapping quietly shortens.
    func testAHashInsideANameIsRefused() {
        assertRefused(.unwritableName) { HostsFile.setNames(["build#local"], at: 1, in: &$0) }
    }

    /// A NUL is not whitespace and not a comment, and every C program that
    /// reads this file stops at it — including the resolver. The line Helm
    /// wrote and the line the system obeys would be different lines.
    func testAControlCharacterInsideANameIsRefused() {
        assertRefused(.unwritableName) { HostsFile.setNames(["ok.local\u{0}evil.example"], at: 1, in: &$0) }
    }

    /// A name is a field, and an empty field is not one. `["a", ""]` renders a
    /// trailing separator and reads back as a single name.
    func testAnEmptyNameIsRefused() {
        assertRefused(.unwritableName) { HostsFile.setNames([""], at: 1, in: &$0) }
        assertRefused(.unwritableName) { HostsFile.setNames(["build.local", ""], at: 1, in: &$0) }
    }

    /// **A row emptied of names stops being a row.** The address stays in the
    /// file, the table loses the line, and nothing on screen can reach it
    /// again — a mapping nobody can switch off.
    func testAnEmptyNameListIsRefused() {
        assertRefused(.noNames) { HostsFile.setNames([], at: 1, in: &$0) }
    }

    /// The strict predicate, not the generous one. `isAddress` decides whether
    /// a line somebody else wrote is a row; `isWritableAddress` decides what
    /// Helm may put in the file, and refuses `0177.0.0.1`, which `inet_pton`
    /// and `inet_aton` read as two different addresses.
    func testAnAddressHelmMayNotWriteIsRefused() {
        for token in ["0177.0.0.1", "127.1", "not-an-address", "", "10.0.0.1#x", "999.1.1.1"] {
            assertRefused(.unwritableAddress) { HostsFile.setAddress(token, at: 1, in: &$0) }
        }
    }

    /// `append` builds a line from the same two fields, so it answers to the
    /// same grammar. A new row is where a person types the most.
    func testAppendIsHeldToTheSameGrammar() {
        assertRefused(.unwritableName) {
            HostsFile.append(address: "10.0.0.9", names: ["ok\n0.0.0.0 bank.example"], in: &$0)
        }
        assertRefused(.unwritableAddress) {
            HostsFile.append(address: "10.0.0.9 sneaky.local", names: ["ok"], in: &$0)
        }
        assertRefused(.noNames) { HostsFile.append(address: "10.0.0.9", names: [], in: &$0) }
        assertRefused(.unwritableName) {
            HostsFile.append(address: "10.0.0.9", names: ["ok", "two names"], in: &$0)
        }
    }

    /// **The editors are the only way a line changes, and that is now true by
    /// construction rather than by convention.**
    ///
    /// Measured on 2026-08-18 with a throwaway file compiled inside
    /// `Module_Hosts_UI` — a target that only imports the engine, exactly where
    /// Task 9's view model will live. `Entry.names` and `Document.lines` were
    /// `public var` and `Document.init(lines:)` was public, so those six lines
    /// built the payload below and rendered it without going near an editor:
    /// two live mappings out of one row, the second typed by nobody, on its way
    /// to `/etc/hosts` as root. `public internal(set)` on the entry's fields
    /// and on `Document.lines`, with an internal `Document.init(lines:)`, is
    /// what closed it — outside the engine a document can only come from
    /// `parse` and can only change through the five editors, which is the same
    /// rule as «the engine has the last word on deletion» one file over: a gate
    /// a caller may decline to ask is a gate that eventually goes unasked, and
    /// the shorter path is always two lines shorter at the worst moment.
    ///
    /// **This test cannot prove the setter is gone** — `@testable` sees
    /// internal, so this very file could still assign the field. It holds the
    /// route that remains and names, above, why the other one is not there,
    /// which is the part that stops it coming back.
    func testTheProbesPayloadHasNoRouteIntoTheFileExceptAnEditorThatRefusesIt() {
        var document = HostsFile.parse("127.0.0.1 solo\n")
        XCTAssertEqual(HostsFile.setNames(["ok.local\n0.0.0.0 bank.example"], at: 0, in: &document),
                       .refused(.unwritableName))
        XCTAssertEqual(HostsFile.render(document), "127.0.0.1 solo\n")
        XCTAssertEqual(HostsFile.parse(HostsFile.render(document)).entries.count, 1,
                       "the file holds a mapping nobody typed")
    }

    /// An index no entry answers to is refused too, rather than editing the
    /// nearest thing or dropping the edit without a word. The table addresses
    /// entries; the document holds comments between them, so the two numbers
    /// are not the same and an off-by-one here is somebody else's line.
    func testAnIndexNoEntryAnswersToIsRefused() {
        assertRefused(.noSuchEntry) { HostsFile.setEnabled(false, at: 2, in: &$0) }
        assertRefused(.noSuchEntry) { HostsFile.setAddress("10.0.0.9", at: 9, in: &$0) }
        assertRefused(.noSuchEntry) { HostsFile.setNames(["ok"], at: 9, in: &$0) }
        assertRefused(.noSuchEntry) { HostsFile.remove(at: 2, in: &$0) }
        assertRefused(.noSuchEntry) { HostsFile.setEnabled(false, at: -1, in: &$0) }
    }
}
