import Foundation
import XCTest
@testable import Module_Hosts_Engine

/// **A row is a claim about what `ssh` will do**, and two of the rules it is
/// built on are the wrong way round.
///
/// Both were measured against this Mac's own `ssh -G`, which prints the
/// configuration a connection would actually use, rather than reasoned about
/// from the manual page:
///
/// ```
/// $ printf 'IdentityFile ~/.ssh/preamble_key\n\nHost box\n  HostName box.example\n' > cfg
/// $ ssh -G -F cfg box | grep identityfile
/// identityfile ~/.ssh/preamble_key            ← the only one; it replaces the defaults
///
/// $ printf 'Host box\n  HostName first.example\n  HostName second.example\n
///           Port 22\n  Port 2222\n' > cfg
/// $ ssh -G -F cfg box | grep -E 'hostname|port'
/// hostname first.example
/// port 22                                     ← the first of each, not the last
/// ```
///
/// `SSHConfigFile.Field.host` already carries the first fact in its own
/// documentation — «nil for a field before the first `Host` line — legal, and
/// applied to every connection» — and the join then drops every such field on
/// the floor.
final class TheRowSaysWhatSSHWillDoTests: XCTestCase {

    private let home = "/Users/someone"
    private let keys = ["id_ed25519", "work_rsa", "personal"]

    private func table(_ config: String) -> SSHHostRows.Table {
        SSHHostRows.table(config: SSHConfigFile.parse(config), keys: keys, home: home,
                          known: KnownHostsFile.parse(""))
    }

    // MARK: - The file's preamble applies to everything

    /// A directive before the first `Host` line is not «in no block», it is
    /// «in every block». A key named there is the key `ssh` uses for every
    /// machine in the file — and the row says «not used by anything here»,
    /// which on this page is the sentence that means «safe to delete».
    func testAKeyNamedBeforeTheFirstHostBlockIsUsedByEveryHost() {
        let config = """
        IdentityFile ~/.ssh/work_rsa

        Host box
            HostName box.example

        Host other
            HostName other.example
        """
        XCTAssertEqual(KeyUsage.ofKeys(SSHConfigFile.parse(config), keys: keys, home: home)["work_rsa"],
                       .everyHost, """
            the key the whole file logs in with reads as used by nothing. A `Host *` block is \
            recognised and the preamble — which `ssh` applies to every connection and applies \
            *before* the blocks, so it wins — is not. This is the same fold `KeyUsage` exists \
            to refuse: «named in no block» is not «nothing will reach for it».
            """)
    }

    /// The same fact from the host's side: a block that names no identity of
    /// its own still uses the preamble's key, and the row has to say which key
    /// that is rather than leaving the line blank.
    func testAHostWithNoIdentityOfItsOwnStillShowsThePreamblesKey() {
        let config = """
        IdentityFile ~/.ssh/work_rsa

        Host box
            HostName box.example
        """
        XCTAssertEqual(table(config).rows.first?.identities, [.named("work_rsa")], """
            the row for `box` names no key, and `ssh -G` says `box` uses `work_rsa`. An empty \
            list here draws «this host names no key», which is a different fact from the one \
            the file carries.
            """)
    }

    // MARK: - Inside a block, the first value wins

    /// «For each parameter, the first obtained value will be used» — the
    /// sentence `ssh_config(5)` opens with, and the one thing about that file
    /// that surprises everybody. A second `HostName` in a block is what a
    /// person leaves behind when they change a machine's address and keep the
    /// old line; `ssh` ignores it, and the row draws it.
    func testTheAddressIsTheOneSSHWillConnectTo() {
        let config = """
        Host box
            HostName first.example
            HostName second.example
            User rstrlnkv
            Port 22
            Port 2222
        """
        XCTAssertEqual(table(config).rows.first?.address, "rstrlnkv@first.example:22", """
            the row named the last value of each directive; `ssh` uses the first. So the page \
            says a person connects to a machine and a port they do not, which is precisely the \
            question `user@host:port` is on the row to answer.
            """)
    }

    /// And the editor moves the value the row draws. `SSHConfigFile.set` takes
    /// the **first** field of a name and the row reads the **last**, so on a
    /// block with a repeated directive the two disagree: the control changes
    /// something and the row it lives on does not move.
    func testEditingAFieldMovesTheValueTheRowShows() {
        var document = SSHConfigFile.parse("""
        Host box
            HostName box.example
            Port 22
            Port 2222
        """)
        XCTAssertTrue(SSHConfigFile.set("2200", of: .port, ofHost: 0, in: &document))

        let rows = SSHHostRows.table(config: document, keys: keys, home: home,
                                     known: KnownHostsFile.parse("")).rows
        XCTAssertEqual(rows.first?.address, "box.example:2200", """
            the port was set to 2200 and the row still draws another number. The editor writes \
            the first field of that name and the row reads the last, so one of them is about a \
            line `ssh` will never read — and a control whose row does not move is a control \
            that looks broken.
            """)
    }
}
