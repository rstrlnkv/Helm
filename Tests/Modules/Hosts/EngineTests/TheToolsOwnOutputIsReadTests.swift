import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine

/// **The line `ssh-keygen -l` really prints ends in a newline, and the parser
/// refuses it.**
///
/// `KeyInventory.described` splits on the space character alone and then asks
/// whether the last field ends in `)`. The tool's own last field is
/// `(ED25519)\n` — a newline is not a space, so it stays attached, the suffix
/// test fails and the whole line is refused. `SystemSSHKeys.facts` hands the
/// line over exactly as `HelmProcess.run` returned it, which is with the
/// newline: nothing between the pipe and the parser trims anything.
///
/// What that costs on a real Mac, on every key: no fingerprint, no type badge,
/// no bit count, and the row drawing «the key could not be read» over a key
/// that reads perfectly. And `inAgent` is asked **by fingerprint** — a row
/// whose description did not parse is out of the agent whatever the agent
/// holds — so the «in the agent» badge can never come on, and the control
/// beside it always offers to add a key that is already in.
///
/// **Why every existing test is green.** `FakeSSHKeys` answers
/// `"256 SHA256:abc123 me@mac (ED25519)"` and `WireKeys` the same — a line no
/// tool produces, because both were written by hand from the shape of the
/// output rather than taken from it. A fake tidier than the port cannot fail
/// the way the port does, which is the same defect as a fake simpler than it.
final class TheToolsOwnOutputIsReadTests: XCTestCase {

    private lazy var directory: URL = scratchDirectory("hosts-describe")

    /// The same throwaway public half `ThePrivateHalfIsNeverOpenedTests` uses:
    /// generated once, outside anybody's `~/.ssh`, and written down.
    private let publicHalf = "ssh-ed25519 "
        + "AAAAC3NzaC1lZDI1NTE5AAAAIPlbqyRBNaFZbc+GsF6UwufErw/HBmEowrh05UymPM4o me@mac\n"
    private let fingerprint = "SHA256:4pz7iO0haQXWFjkqkKCLit+YXYqSz1gvnQlLnbAb+gw"

    private func keyring() throws -> SystemSSHKeys {
        try "not a key\n".write(to: directory.appendingPathComponent("id_ed25519"),
                                atomically: true, encoding: .utf8)
        try publicHalf.write(to: directory.appendingPathComponent("id_ed25519.pub"),
                             atomically: true, encoding: .utf8)
        return SystemSSHKeys(directory: directory, deadline: 15)
    }

    private var pair: KeyInventory.Pair {
        KeyInventory.Pair(name: "id_ed25519", hasPublicHalf: true)
    }

    /// The row the page draws, built from the real tool's real output.
    func testTheRowCarriesTheFingerprintTheToolPrinted() throws {
        let port = try keyring()

        let row = KeyRow.row(from: port.facts(for: pair), agent: .unreachable)

        XCTAssertNotNil(row.described, """
            the row has no description at all, over a key `ssh-keygen -l` described without \
            complaint. On the page that is «the key could not be read» drawn on every row of \
            somebody's `~/.ssh`, with no fingerprint to compare and no type badge.
            """)
        XCTAssertEqual(row.described?.fingerprint, fingerprint)
        XCTAssertEqual(row.described?.type, "ED25519")
        XCTAssertEqual(row.described?.bits, 256)
        XCTAssertEqual(row.described?.comment, "me@mac")
    }

    /// The second-order cost, and the one nobody would look for: the badge is
    /// asked by fingerprint, so a description that did not parse takes the
    /// agent's own answer away with it.
    func testAKeyTheAgentIsHoldingWearsItsBadge() throws {
        let port = try keyring()

        let row = KeyRow.row(from: port.facts(for: pair), agent: .holding([fingerprint]))

        XCTAssertTrue(row.inAgent, """
            the agent said it is holding this exact fingerprint and the row says the key is not \
            in the agent. The badge can then never come on, and the control beside it offers to \
            add a key that is already there.
            """)
    }

    /// The parse on its own, against the bytes rather than against a tidied
    /// spelling of them. `\\n` is what the tool writes; `\\r\\n` is what a
    /// future `ssh-keygen` on a different terminal could, and neither is a
    /// field of the line.
    func testALineWithItsOwnEndingIsRead() {
        let line = "256 \(fingerprint) me@mac (ED25519)"
        XCTAssertNotNil(KeyInventory.described(line),
                        "precondition: the line parses at all without its ending")

        XCTAssertEqual(KeyInventory.described(line + "\n")?.type, "ED25519", """
            the line the tool actually prints is refused. `split(separator: " ")` leaves the \
            ending attached to the last field, so `(ED25519)\\n` fails the `)` test and the \
            whole description is thrown away — including the fingerprint, which is the one \
            thing on the row a person came to compare.
            """)
        XCTAssertEqual(KeyInventory.described(line + "\r\n")?.type, "ED25519")
    }

    /// **The fakes are why this was invisible.** They answer a line with no
    /// ending, which is not a line any tool prints — so every test built on one
    /// exercises a parser that never meets the input it has.
    func testTheHandWrittenLineAndTheToolsLineParseAlike() throws {
        let port = try keyring()
        let real = try XCTUnwrap(port.facts(for: pair).describeLine,
                                 "precondition: the tool said something")
        let handWritten = "256 SHA256:abc123 me@mac (ED25519)"

        XCTAssertNotNil(KeyInventory.described(handWritten),
                        "precondition: the fakes' line parses, which is why they are green")
        XCTAssertNotNil(KeyInventory.described(real), """
            the fakes' line parses and the tool's does not, so every keys test in this module \
            is answering a question about a string that only exists inside the tests: \
            <\(real.debugDescription)>
            """)
    }
}
