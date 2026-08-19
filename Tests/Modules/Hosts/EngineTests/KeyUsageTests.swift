import XCTest
@testable import Module_Hosts_Engine

/// **Which key opens which host** — the one thing this module reads three files
/// to know and has never said.
///
/// `IdentityFile` names a key and `KeyInventory` names the keys, and the join
/// between them is not a string comparison: the same key is spelled five ways in
/// a config file that `ssh` reads identically, a `Host *` block lends its key to
/// every host in the file, and a key nothing names at all may still be the one a
/// person logs in with, because `ssh` tries the default names without being
/// told. Each of those is a way to answer «used by nothing» about a key somebody
/// depends on, and «you can delete this» is the sentence that answer becomes on
/// screen.
final class KeyUsageTests: XCTestCase {

    private let home = "/Users/someone"
    private let keys = ["id_ed25519", "work_rsa", "personal"]

    private func usage(_ config: String) -> [String: KeyUsage.OfKey] {
        KeyUsage.ofKeys(SSHConfigFile.parse(config), keys: keys, home: home)
    }

    private func identities(_ config: String) -> [Int: [KeyUsage.Identity]] {
        KeyUsage.ofHosts(SSHConfigFile.parse(config), keys: keys, home: home)
    }

    // MARK: - Trap 1: five spellings of one key

    /// `~`, `%d`, an absolute path, a bare name relative to `~/.ssh`, and any of
    /// them in quotes are one key. A comparison of the literal strings answers
    /// «unused» for four of the five.
    func testEverySpellingOfAPathIsTheSameKey() {
        let spellings = [
            "~/.ssh/work_rsa",
            "%d/.ssh/work_rsa",
            "/Users/someone/.ssh/work_rsa",
            "work_rsa",
            "\"~/.ssh/work_rsa\"",
        ]
        for spelling in spellings {
            let found = usage("Host box\n  IdentityFile \(spelling)\n")
            XCTAssertEqual(found["work_rsa"], .namedBy(["box"]),
                           "`IdentityFile \(spelling)` did not reach the key it names")
        }
    }

    /// A path with a space in it, which is why the quotes exist at all.
    func testAQuotedPathWithASpaceIsRead() {
        let found = KeyUsage.ofKeys(SSHConfigFile.parse("Host box\n  IdentityFile \"~/.ssh/my key\"\n"),
                                    keys: ["my key"], home: home)
        XCTAssertEqual(found["my key"], .namedBy(["box"]))
    }

    /// `IdentityFile` pointed at the public half is the same key. `ssh` accepts
    /// it — the private half being in the agent is the ordinary reason to write
    /// it that way — and a row that missed it would call the key unused.
    func testThePublicHalfNamesTheSameKey() {
        XCTAssertEqual(usage("Host box\n  IdentityFile ~/.ssh/work_rsa.pub\n")["work_rsa"],
                       .namedBy(["box"]))
    }

    // MARK: - Trap 2: `Host *` is every host

    func testAKeyNamedInAStarBlockIsUsedByEveryHost() {
        let config = """
        Host *
          IdentityFile ~/.ssh/work_rsa

        Host box
          HostName example.invalid
        """
        XCTAssertEqual(usage(config)["work_rsa"], .everyHost, """
            a key lent to every host in the file read as a key lent to one, or to none — \
            which is the sentence «not used by anything here» over the key the person logs \
            in with everywhere
            """)
    }

    /// And `*` wins over a specific block: a key named both ways is still every
    /// host's, and listing the one block by name would understate it.
    func testAStarBlockOutranksANamedOne() {
        let config = """
        Host box
          IdentityFile ~/.ssh/work_rsa

        Host *
          IdentityFile ~/.ssh/work_rsa
        """
        XCTAssertEqual(usage(config)["work_rsa"], .everyHost)
    }

    // MARK: - Trap 3: a key nothing names may still be in use

    /// `ssh` tries `id_ed25519` and its siblings without being told to. So a
    /// default-named key that appears in no block is **used by default**, and
    /// calling it unused is the difference between «this is safe to delete» and
    /// «this is how you log in».
    func testADefaultNamedKeyNothingMentionsIsUsedByDefault() {
        XCTAssertEqual(usage("Host box\n  HostName example.invalid\n")["id_ed25519"],
                       .byDefaultName)
    }

    /// A key with a name of somebody's own, named nowhere, really is unused —
    /// otherwise the answer above would mean nothing.
    func testAKeyWithItsOwnNameAndNoMentionIsUnused() {
        XCTAssertEqual(usage("Host box\n  HostName example.invalid\n")["personal"], .unused)
    }

    /// Being named beats being default: the row should say where it is used,
    /// not fall back to the weaker sentence.
    func testADefaultNamedKeyThatIsAlsoNamedSaysWhereItIsUsed() {
        XCTAssertEqual(usage("Host box\n  IdentityFile ~/.ssh/id_ed25519\n")["id_ed25519"],
                       .namedBy(["box"]))
    }

    // MARK: - Trap 4: a host may name a key that is not there

    func testAHostNamingAKeyThatIsNotThereIsNotAHostNamingNone() {
        let found = identities("Host box\n  IdentityFile ~/.ssh/deleted_key\n")
        XCTAssertEqual(found[0], [.missing("deleted_key")], """
            a host pointing at a key that is gone read the same as a host that names no key \
            at all — the first is broken and the second is ordinary
            """)
    }

    /// A key outside `~/.ssh` is not this module's to judge. Saying so is not
    /// the same as saying it is missing.
    func testAKeyOutsideTheSSHDirectoryIsNamedButNotJudged() {
        let found = identities("Host box\n  IdentityFile /Volumes/stick/id_rsa\n")
        XCTAssertEqual(found[0], [.elsewhere("/Volumes/stick/id_rsa")])
    }

    /// A host with no `IdentityFile` names nothing, and that is the state the
    /// default names answer for.
    func testAHostWithNoIdentityFileNamesNothing() {
        XCTAssertEqual(identities("Host box\n  HostName example.invalid\n")[0], [])
    }

    // MARK: - Several keys, several hosts

    func testAHostMayNameSeveralKeysAndKeepsTheirOrder() {
        let config = """
        Host box
          IdentityFile ~/.ssh/work_rsa
          IdentityFile ~/.ssh/personal
        """
        XCTAssertEqual(identities(config)[0], [.named("work_rsa"), .named("personal")])
    }

    func testAKeyUsedByTwoHostsNamesBothInFileOrder() {
        let config = """
        Host alpha
          IdentityFile ~/.ssh/work_rsa

        Host beta
          IdentityFile ~/.ssh/work_rsa
        """
        XCTAssertEqual(usage(config)["work_rsa"], .namedBy(["alpha", "beta"]))
    }

    /// A block's pattern list is what the person wrote, and it is what the row
    /// has to show: `Host web1 web2` is one block and two names.
    func testABlockWithSeveralPatternsIsNamedAsItIsWritten() {
        XCTAssertEqual(usage("Host web1 web2\n  IdentityFile ~/.ssh/work_rsa\n")["work_rsa"],
                       .namedBy(["web1 web2"]))
    }

    /// Every key in the inventory gets an answer, including the ones the config
    /// never mentions — a dictionary missing a key is a row with nothing to draw.
    func testEveryKeyInTheInventoryIsAnswered() {
        XCTAssertEqual(Set(usage("Host box\n  HostName example.invalid\n").keys), Set(keys))
    }
}
