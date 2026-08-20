import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine

/// **`~/.ssh` holds directories, and this module offers to `chmod 600` them.**
///
/// `KeyInventory` decides what is a key from the names alone, and the list of
/// things it excludes is a list of *names*: `config`, `known_hosts`,
/// `authorized_keys`, anything ending `.old` or `~`, anything beginning with a
/// dot. A folder passes every one of them.
///
/// Folders in `~/.ssh` are ordinary. `ControlPath ~/.ssh/sockets/%r@%h:%p` is
/// the line every guide about multiplexing tells people to add, and
/// `~/.ssh/config.d` is what an `Include` points at. A fresh directory under
/// the usual umask is 0755, which this module reads as «too open» — so the row
/// draws a Fix button, and the fix is `chmod 600` on a directory.
///
/// A directory at 0600 cannot be entered by anybody, its owner included: every
/// multiplexed connection then fails, and so does the `Include` that made the
/// folder in the first place. The row also offers to load it into the agent.
///
/// The name-only decision is right where it is — `KeyInventory` is pure and is
/// handed names — so what is missing is one reading from the port, the way
/// `KeyFacts` already carries four others.
final class AFolderInTheKeyringIsNotAKeyTests: XCTestCase {

    private lazy var directory: URL = scratchDirectory("hosts-folder")

    /// `~/.ssh` as a Mac that multiplexes has it: a key, its public half, and
    /// the socket folder `ControlPath` needs.
    private func keyring() throws -> SystemSSHKeys {
        try "private\n".write(to: directory.appendingPathComponent("id_ed25519"),
                              atomically: true, encoding: .utf8)
        try "ssh-ed25519 AAAA me@mac\n".write(to: directory.appendingPathComponent("id_ed25519.pub"),
                                              atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("sockets"),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        return SystemSSHKeys(directory: directory, deadline: 15)
    }

    func testTheSocketFolderIsNotListedAsAKey() throws {
        let port = try keyring()
        let names = try XCTUnwrap(port.names())
        XCTAssertTrue(names.contains("sockets"), "precondition: the folder is in the listing")

        XCTAssertEqual(KeyInventory.pairs(in: names).map(\.name), ["id_ed25519"], """
            `~/.ssh/sockets` — the folder `ControlPath` writes into — is a row on the keys tab. \
            It is not a key: there is nothing to load into an agent and nothing to `chmod`.
            """)
    }

    /// And what the row would offer to do to it. This is the half that makes
    /// the one above worth fixing rather than tidying: the button is
    /// destructive on a directory.
    func testTheFolderIsNotOfferedAChmodThatWouldSealIt() throws {
        let port = try keyring()
        let facts = port.facts(for: KeyInventory.Pair(name: "sockets", hasPublicHalf: false))

        XCTAssertEqual(facts.mode.map { $0 & 0o777 }, 0o755,
                       "precondition: the folder is at the mode a fresh one gets")
        XCTAssertNotEqual(KeyRow.row(from: facts, agent: .unreachable).permission,
                          .tooOpen(fix: 0o600), """
            the row for a folder carries the verdict for a private key, so the page draws Fix \
            beside it and pressing it runs `chmod 600` on a directory — which nobody, its owner \
            included, can then enter. Every multiplexed connection through it stops working, \
            and so does the `Include` that a `config.d` was made for.
            """)
    }
}
