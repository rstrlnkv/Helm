import XCTest
@testable import Module_Hosts_Engine

/// Editing one field of one block, and leaving every other byte of the file
/// alone.
///
/// The hazard this exists for is the one `HostsEntryEditingHazardsTests` records
/// next door, arriving through a different door: a value is a **line fragment**,
/// and a fragment that carries a newline is two directives — the second typed by
/// nobody, in somebody's `~/.ssh/config`, with `IdentityFile` pointing wherever
/// the text says. `ssh` reads the first match of a directive per block, so an
/// injected line does not even have to argue with the one above it to win.
final class SSHConfigEditingTests: XCTestCase {

    private let file = """
    # work
    Host build
        HostName build.internal.example
        User rstrlnkv    # the shared account
        Port 2222

    Host attic
        HostName 192.0.2.31

    """

    private func edited(_ text: String, host: Int, field: SSHConfigFile.Field.Name,
                        to value: String) -> (String, Bool) {
        var document = SSHConfigFile.parse(text)
        let ok = SSHConfigFile.set(value, of: field, ofHost: host, in: &document)
        return (SSHConfigFile.render(document), ok)
    }

    func testChangingAPortRewritesThatLineAndNothingElse() {
        let (out, ok) = edited(file, host: 0, field: .port, to: "22")
        XCTAssertTrue(ok)
        XCTAssertEqual(out, file.replacingOccurrences(of: "Port 2222", with: "Port 22"))
    }

    /// The line's own shape is the person's, not the editor's: four spaces of
    /// indent, and a trailing comment that belongs to the line rather than to
    /// the value.
    func testTheIndentAndTheTrailingCommentSurviveAnEdit() {
        let (out, ok) = edited(file, host: 0, field: .user, to: "root")
        XCTAssertTrue(ok)
        XCTAssertTrue(out.contains("    User root    # the shared account"),
                      "the edited line lost its indent or its comment:\n\(out)")
    }

    /// Two blocks can hold the same directive, and an editor that finds it by
    /// name alone edits whichever comes first.
    func testTheSecondBlocksFieldIsTheOneEdited() {
        let (out, ok) = edited(file, host: 1, field: .hostName, to: "attic.example")
        XCTAssertTrue(ok)
        XCTAssertTrue(out.contains("HostName build.internal.example"),
                      "the first block was rewritten:\n\(out)")
        XCTAssertTrue(out.contains("HostName attic.example"),
                      "the second block was not:\n\(out)")
    }

    /// **A newline in a value is refused, and the file is left as it was.**
    /// This is the whole reason a value goes through an editor rather than being
    /// assigned: `IdentityFile ~/.ssh/id\n    ProxyCommand nc evil 22` is two
    /// directives, and the second is a command `ssh` runs.
    func testAValueCarryingANewlineIsRefused() {
        // **`hostName`, not `identityFile`.** The first draft of this test used
        // a field the fixture's block does not have, so every refusal it
        // asserted came from «no such field» and the newline check could be
        // deleted with all seven cases still green — measured, by deleting it.
        // The value under test has to reach the check it is testing.
        for hostile in ["a\nProxyCommand nc evil 22", "a\r\nUser root", "a\rUser root"] {
            let (out, ok) = edited(file, host: 0, field: .hostName, to: hostile)
            XCTAssertFalse(ok, "a value with a line break was accepted: \(hostile.debugDescription)")
            XCTAssertEqual(out, file, "a refused edit still changed the file")
        }
    }

    /// A `#` opens a comment, so a value carrying one comments out whatever
    /// followed it on that line — including the trailing comment the person
    /// wrote. Refused for the same reason as the newline: the value would stop
    /// being a value.
    func testAValueCarryingAHashIsRefused() {
        let (out, ok) = edited(file, host: 0, field: .hostName, to: "example # ok")
        XCTAssertFalse(ok)
        XCTAssertEqual(out, file)
    }

    /// A field the block does not have is not invented: adding a directive is a
    /// different act from editing one, with a different place in the file to
    /// argue about, and this editor does not do it.
    func testAFieldTheBlockDoesNotHaveIsNotAdded() {
        let (out, ok) = edited(file, host: 1, field: .port, to: "2200")
        XCTAssertFalse(ok)
        XCTAssertEqual(out, file)
    }

    /// An empty value is refused too: `ssh` reads `Port` with nothing after it
    /// as a parse error and stops reading the file at that line, so a blank
    /// field would not clear a setting, it would break every block below.
    func testAnEmptyValueIsRefused() {
        let (out, ok) = edited(file, host: 0, field: .port, to: "   ")
        XCTAssertFalse(ok)
        XCTAssertEqual(out, file)
    }
}
