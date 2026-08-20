import XCTest
@testable import Module_Hosts_Engine

/// The rows tab 2 draws, assembled once for the whole tab.
///
/// Three files meet here — the config's blocks, the keys in `~/.ssh` and the
/// fingerprints in `known_hosts` — and the meeting is arithmetic, not drawing.
/// It is computed once for the tab rather than per row, which is the shape
/// `ScanCoordinator.Conditions` exists to keep: one tick, one reading, one
/// verdict, instead of three rows judging three readings of the same file.
final class SSHHostRowsTests: XCTestCase {

    private let home = "/Users/someone"
    private let keys = ["id_ed25519", "work_rsa"]

    private func table(_ config: String, known: String = "") -> SSHHostRows.Table {
        SSHHostRows.table(config: SSHConfigFile.parse(config), keys: keys, home: home,
                          known: KnownHostsFile.parse(known))
    }

    // MARK: - The address line

    /// The three parts, each left out when the block does not set it. A row
    /// that wrote `@` or `:` over a value nobody typed would be showing a
    /// setting the file does not carry.
    func testTheAddressIsUserAtHostAndPortWhenAllThreeAreSet() {
        let rows = table("""
        Host build
            HostName build.example
            User rstrlnkv
            Port 2222
        """).rows
        XCTAssertEqual(rows.map(\.address), ["rstrlnkv@build.example:2222"])
    }

    func testAnAddressWithoutAUserIsJustTheHostAndPort() {
        XCTAssertEqual(table("Host b\n  HostName b.example\n  Port 2222\n").rows.first?.address,
                       "b.example:2222")
    }

    func testAnAddressWithoutAPortIsJustTheUserAndHost() {
        XCTAssertEqual(table("Host b\n  HostName b.example\n  User me\n").rows.first?.address,
                       "me@b.example")
    }

    /// **`ssh` uses the alias as the host name when no `HostName` says
    /// otherwise**, so a block with nothing but a name is a working host and
    /// its row says where it goes.
    func testABlockWithNoHostNameConnectsToItsOwnAlias() {
        XCTAssertEqual(table("Host b.example\n  User me\n").rows.first?.address, "me@b.example")
    }

    /// And a pattern is not a host name. `Host *` and `Host web1 web2` name no
    /// single machine, so the row shows the patterns and no address rather than
    /// inventing a host called `*`.
    func testAPatternIsNotAHostName() {
        XCTAssertEqual(table("Host *\n  User me\n").rows.first?.address, "")
        XCTAssertEqual(table("Host web1 web2\n  User me\n").rows.first?.address, "")
        XCTAssertEqual(table("Host web?\n  User me\n").rows.first?.address, "")
    }

    /// The patterns themselves are what the row is titled with, written as the
    /// person wrote them.
    func testTheRowIsTitledWithThePatternsAsWritten() {
        XCTAssertEqual(table("Host web1 web2\n  User me\n").rows.map(\.patterns), ["web1 web2"])
    }

    // MARK: - The key each host uses

    func testAHostNamingAKeyCarriesTheKeyItNames() {
        XCTAssertEqual(table("Host b\n  IdentityFile ~/.ssh/work_rsa\n").rows.first?.identities,
                       [.named("work_rsa")])
    }

    /// **A host naming no key at all is ordinary**, and its row carries nothing
    /// to mark — the empty list, never a `missing` standing in for silence.
    func testAHostNamingNoKeyCarriesNothing() {
        XCTAssertEqual(table("Host b\n  HostName b.example\n").rows.first?.identities, [])
    }

    // MARK: - The fingerprints already trusted

    func testAnEntryForTheBlocksHostNameLandsOnItsRow() {
        let found = table("Host b\n  HostName b.example\n",
                          known: "b.example ssh-ed25519 AAAA me@mac\n")
        XCTAssertEqual(found.rows.first?.trusted.map(\.index), [0])
        XCTAssertTrue(found.other.isEmpty, "an entry drawn on a row was drawn again under «other»")
    }

    /// `known_hosts` writes a non-default port as `[host]:port`, which is the
    /// spelling a plain comparison misses — and the miss reads as «this host
    /// has never been trusted» beside a host that has.
    func testABracketedPortSpellingReachesTheHostItNames() {
        let found = table("Host b\n  HostName b.example\n  Port 2222\n",
                          known: "[b.example]:2222 ssh-ed25519 AAAA me@mac\n")
        XCTAssertEqual(found.rows.first?.trusted.map(\.index), [0])
    }

    /// Host names are not case-sensitive, and `known_hosts` records whatever
    /// was typed on the command line.
    func testTheMatchIgnoresCase() {
        let found = table("Host b\n  HostName Build.Example\n",
                          known: "build.example ssh-ed25519 AAAA me@mac\n")
        XCTAssertEqual(found.rows.first?.trusted.map(\.index), [0])
    }

    /// One line can name several hosts, and the row that matches any of them
    /// gets it.
    func testALineNamingSeveralHostsReachesEachOfThem() {
        let found = table("""
        Host a
            HostName a.example

        Host b
            HostName b.example
        """, known: "a.example,b.example ssh-ed25519 AAAA me@mac\n")
        XCTAssertEqual(found.rows.map { $0.trusted.map(\.index) }, [[0], [0]])
        XCTAssertTrue(found.other.isEmpty)
    }

    /// **A hashed line names nothing**, and macOS ships `HashKnownHosts yes`.
    /// It cannot be matched to a host by anybody, so it goes under «other»
    /// rather than being quietly dropped — it is still a trust somebody may
    /// want to forget.
    func testAHashedLineIsUnderOtherAndNotLost() {
        let found = table("Host b\n  HostName b.example\n",
                          known: "|1|c2FsdA==|aGFzaA== ssh-ed25519 AAAA me@mac\n")
        XCTAssertTrue(found.rows.first?.trusted.isEmpty ?? false)
        XCTAssertEqual(found.other.map(\.index), [0])
    }

    /// An entry for a host this config never mentions is the ordinary case —
    /// most of `known_hosts` is machines nobody wrote a block for.
    func testAnEntryMatchingNoBlockIsUnderOther() {
        let found = table("Host b\n  HostName b.example\n",
                          known: "github.com ssh-ed25519 AAAA me@mac\n")
        XCTAssertEqual(found.other.map(\.index), [0])
    }

    /// Comments and blank lines are not entries, and «other» is a list of
    /// trusts rather than of lines.
    func testCommentsAreNotTrusts() {
        XCTAssertTrue(table("Host b\n", known: "# a comment\n\n").other.isEmpty)
    }

    /// The whole tab is one reading. Every block gets a row, in file order, so
    /// nothing on screen is drawn from a second look at the same document.
    func testEveryBlockGetsARowInFileOrder() {
        let rows = table("Host a\nHost b\nHost c\n").rows
        XCTAssertEqual(rows.map(\.patterns), ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.index), [0, 1, 2])
    }
}
