import XCTest
@testable import Module_Hosts_Engine

/// `Entry.id` is what `ForEach` draws rows from, and `enabled` is the one field
/// the table exists to change. Neither is touched by `render(parse(x)) == x`:
/// a document nobody edited cannot disagree with itself.
final class HostsEntryIdentityTests: XCTestCase {

    /// Two byte-identical lines are two mappings and must be two rows. A
    /// `ForEach` handed the same id twice draws one of them and animates the
    /// other in and out of existence.
    func testIdenticalLinesKeepDistinctIdentities() {
        let document = HostsFile.parse("127.0.0.1\ta\n127.0.0.1\ta\n127.0.0.1\ta\n")
        XCTAssertEqual(document.entries.count, 3)
        XCTAssertEqual(Set(document.entries.map(\.id)).count, 3,
                       "three identical lines collapsed to \(Set(document.entries.map(\.id)).count) rows")
    }

    /// The same invariant over a file whose entries differ in every other way,
    /// so a fix that makes the id *only* the content still has to pass this.
    func testEveryRowOfAMixedFileHasItsOwnIdentity() {
        let document = HostsFile.parse("""
        127.0.0.1\tlocalhost
        # 10.0.0.5\tbuild.local
        ::1             localhost
        10.0.0.1\t\tbox.local     box

        """)
        XCTAssertEqual(Set(document.entries.map(\.id)).count, document.entries.count)
    }

    /// **An id that is a copy of the content is not an identity.** SwiftUI
    /// destroys and rebuilds a row whose id changed, taking `@FocusState` and
    /// the in-flight text with it — so a table binding a field to `address`
    /// loses the caret after the first character typed. The row is the same row
    /// before and after the edit; only what it says changed.
    func testARowKeepsItsIdentityWhenItsAddressIsEdited() throws {
        var entry = try XCTUnwrap(HostsFile.parse("127.0.0.1\tbox.local\n").entries.first)
        let before = entry.id
        entry.address = "127.0.0."           // one keystroke into an edit
        XCTAssertEqual(entry.id, before,
                       "the row was replaced mid-edit rather than redrawn")
    }

    func testARowKeepsItsIdentityWhenItsNamesAreEdited() throws {
        var entry = try XCTUnwrap(HostsFile.parse("127.0.0.1\tbox.local\n").entries.first)
        let before = entry.id
        entry.names = ["box.local", "box"]
        XCTAssertEqual(entry.id, before,
                       "adding a name replaced the row instead of updating it")
    }

    /// A disabled entry is one the person switched off, and the switch is the
    /// whole point of the tab. `render` reads `leading` and never asks
    /// `enabled`, so an entry the model calls disabled is written live — the
    /// safe direction would be the other one.
    ///
    /// Asserted through `parse`, not by looking for a `#`, so the fix is free
    /// to choose how a disabled line is spelled.
    func testAnEntryTheModelCallsDisabledIsNotWrittenLive() {
        let document = HostsFile.Document(lines: [
            .entry(.init(index: 0, address: "127.0.0.1", names: ["blocked.example"], enabled: false)),
        ])
        let text = HostsFile.render(document)
        XCTAssertEqual(HostsFile.parse(text).entries.first?.enabled, false,
                       "a disabled entry was written as a live mapping: \(text.debugDescription)")
    }
}
