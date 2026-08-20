import XCTest
@testable import Module_Hosts_Engine

/// **A host pointing at a key that is gone is broken; a host pointing at no key
/// is ordinary.** The two look identical on a row that draws a key name or a
/// blank, and only one of them is worth waking somebody up about — the
/// connection will fail and the file gives no clue why.
///
/// `KeyUsage.Identity` keeps them apart one layer down; this is the same
/// distinction where the row is assembled, because a fold could happen either
/// place and the screen is where it would be believed.
final class HostKeyMissingTests: XCTestCase {

    private let home = "/Users/someone"

    private func identities(_ config: String, keys: [String]) -> [KeyUsage.Identity] {
        SSHHostRows.table(config: SSHConfigFile.parse(config), keys: keys, home: home,
                          known: KnownHostsFile.Document(lines: [])).rows.first?.identities ?? []
    }

    func testAHostNamingAKeyThatIsGoneIsNotAHostNamingNone() {
        let gone = identities("Host b\n  IdentityFile ~/.ssh/deleted\n", keys: ["id_ed25519"])
        let none = identities("Host b\n  HostName b.example\n", keys: ["id_ed25519"])

        XCTAssertEqual(gone, [.missing("deleted")], """
            a host whose key has been deleted carried \(gone) — if that is the empty list, the \
            row draws it exactly like the host below, which names no key at all and is fine
            """)
        XCTAssertEqual(none, [])
        XCTAssertNotEqual(gone, none)
    }

    /// A key outside `~/.ssh` is not missing. This module lists one directory
    /// and says so; marking somebody's key on a stick as gone would be a
    /// warning about a file Helm never looked for.
    func testAKeyOutsideTheFolderIsNotMarkedAsGone() {
        XCTAssertEqual(identities("Host b\n  IdentityFile /Volumes/stick/id_rsa\n",
                                  keys: ["id_ed25519"]),
                       [.elsewhere("/Volumes/stick/id_rsa")])
    }

    /// A block may name several, and one of them being gone does not make the
    /// others gone: the row shows each as it is.
    func testOneMissingKeyAmongSeveralIsMarkedAlone() {
        XCTAssertEqual(identities("""
        Host b
            IdentityFile ~/.ssh/id_ed25519
            IdentityFile ~/.ssh/deleted
        """, keys: ["id_ed25519"]),
                       [.named("id_ed25519"), .missing("deleted")])
    }
}
