import Foundation
import XCTest
@testable import Module_Hosts_Engine

/// The join, against the configs people actually have.
///
/// `KeyUsageTests` covers the five spellings of a path, the `*` block and the
/// default names. What it does not cover is the rest of `ssh_config`: `Match`
/// blocks, `Include`, a host named twice, a file that came from a Windows
/// machine, and a `#` inside a value. Each answer here becomes one of two
/// sentences on the row — «used by …» or «not used by anything here» — and the
/// second one is read as «safe to delete».
final class KeyUsageHarderConfigsTests: XCTestCase {

    private let home = "/Users/someone"
    private let keys = ["id_ed25519", "work_rsa", "personal"]

    private func usage(_ config: String) -> [String: KeyUsage.OfKey] {
        KeyUsage.ofKeys(SSHConfigFile.parse(config), keys: keys, home: home)
    }

    private func identities(_ config: String) -> [Int: [KeyUsage.Identity]] {
        KeyUsage.ofHosts(SSHConfigFile.parse(config), keys: keys, home: home)
    }

    // MARK: - `Match`

    /// **A `Match` block's key belongs to nobody, and above all not to the
    /// block above it.** `Match` closes the preceding `Host`, so a row that
    /// swept its `IdentityFile` up into the host before it would tell somebody
    /// that `build` uses a key it only uses when the match condition holds —
    /// and the condition is a thing this module cannot show.
    func testAnIdentityUnderAMatchIsNotTheHostsAbove() {
        let config = """
        Host build
            HostName build.example
            IdentityFile ~/.ssh/work_rsa

        Match host build exec "true"
            IdentityFile ~/.ssh/personal
        """
        XCTAssertEqual(identities(config)[0], [.named("work_rsa")],
                       "the `Match` block's key was attributed to the `Host` block above it")
        // **This read `.unused` until 2026-08-20, and that was the wrong half of
        // a right decision.** Belonging to no `Host` is correct — the assertion
        // above — but «belongs to no host row» became «used by nothing», which
        // `HostsStr.usage(of:)` spells «Not used by anything here» and this
        // file's own header calls the sentence read as «safe to delete». `ssh`
        // offers this key every time the condition holds. The block is in the
        // file Helm read; what Helm cannot read is the condition, which is
        // «cannot say» — the same answer `Include` gets one section down, for
        // the same reason (`AMatchBlocksKeyIsNotSafeToDeleteTests`).
        XCTAssertEqual(usage(config)["personal"], .cannotSay(.matchCondition))
    }

    /// A `Host` after a `Match` opens a block again — which is what `ssh` does,
    /// and a parser that kept the match open would lose every block below it.
    func testAHostAfterAMatchIsAHostAgain() {
        let config = """
        Match host anything
            User root

        Host later
            IdentityFile ~/.ssh/work_rsa
        """
        XCTAssertEqual(SSHConfigFile.parse(config).hosts.map(\.patterns), ["later"])
        XCTAssertEqual(usage(config)["work_rsa"], .namedBy(["later"]))
    }

    // MARK: - `Include`

    /// **The limit that is not written down.** `KeyUsage` names one — that
    /// `IdentitiesOnly yes` is not parsed — and says overstating use is the safe
    /// direction, «the wrong answer is a key kept, not a key deleted». `Include`
    /// is the same limit pointing the other way: the block naming the key is in
    /// a file this module never opened, so the key reads as used by nothing and
    /// the row says so.
    ///
    /// This is the module's own `PowerSource.supply()` rule — «named nowhere»
    /// and «not used» are different facts — applied to a case that was missed:
    /// a config carrying an `Include` cannot support the claim that anything in
    /// it is unused.
    func testAKeyUsedOnlyByAnIncludedFileDoesNotReadAsUnused() {
        let config = """
        Include ~/.ssh/config.d/*

        Host box
            HostName box.example
        """
        XCTAssertNotEqual(usage(config)["work_rsa"], .unused, """
            the config hands part of itself to files this module has not read, and the row still \
            says «not used by anything here» about a key one of them may name. «Nothing names \
            it» is a claim about what was read; here what was read is admittedly incomplete, \
            and the two must not arrive as one answer.
            """)
    }

    // MARK: - The same host named twice

    /// Two blocks with the same patterns are ordinary — people keep a second
    /// `Host box` for an override — and the row must not say «Used by box, box».
    func testAHostNamedTwiceIsNamedOnce() {
        let config = """
        Host box
            IdentityFile ~/.ssh/work_rsa

        Host box
            IdentityFile ~/.ssh/work_rsa
        """
        XCTAssertEqual(usage(config)["work_rsa"], .namedBy(["box"]), """
            the same block name was listed once per line that mentions the key, so the sentence \
            on the row repeats it. What the row is for is «which hosts», and a host is not two \
            hosts because its file says so twice.
            """)
    }

    // MARK: - A file that is not LF-and-nothing-else

    /// CRLF, which is what a config edited on a Windows machine or fetched
    /// through a badly configured checkout carries. The parser keeps line
    /// endings as they are for the round trip; the join must read the same
    /// values through them.
    func testAConfigWithWindowsLineEndingsJoinsTheSameWay() {
        let config = "Host box\r\n    IdentityFile ~/.ssh/work_rsa\r\n"
        XCTAssertEqual(usage(config)["work_rsa"], .namedBy(["box"]),
                       "a CRLF file read as a config naming no key")
        XCTAssertEqual(identities(config)[0], [.named("work_rsa")])
    }

    /// A path with a `#` in it. **Measured against this Mac's own `ssh`**, not
    /// reasoned about:
    ///
    /// ```
    /// $ printf 'Host box\n  IdentityFile ~/.ssh/my#key\n' > cfg; ssh -G -F cfg box
    /// identityfile ~/.ssh/my#key
    /// $ printf 'Host box\n  IdentityFile ~/.ssh/plain # note\n' > cfg; ssh -G -F cfg box
    /// identityfile ~/.ssh/plain
    /// ```
    ///
    /// So a `#` opens a comment where a *token* begins and is an ordinary
    /// character inside one — the trailing-comment half of `split(value:)` is
    /// right and the cut is one condition short.
    ///
    /// Both halves of that are wrong on screen at once: the host's row marks a
    /// key that is gone (there is no `my`), and the key that is really used
    /// reads «not used by anything here».
    func testAKeyWhoseNameCarriesAHashIsStillTheKeyInUse() {
        let found = KeyUsage.ofKeys(SSHConfigFile.parse("Host box\n  IdentityFile ~/.ssh/my#key\n"),
                                    keys: ["my#key"], home: home)
        XCTAssertEqual(found["my#key"], .namedBy(["box"]), """
            the value was cut at the `#`, so the key `ssh` will actually use reads as used by \
            nothing, and the host's row points at a key called `my` that does not exist. `ssh` \
            takes a comment only where a keyword would be.
            """)
    }

    // MARK: - Where the home is not known

    /// A payload from before the join shipped carries no home, and `HostsState`
    /// decodes it as `""` — with a comment saying that resolves no `~` and
    /// draws the key as not used here. It does not: `~/.ssh/k` becomes
    /// `/.ssh/k`, whose directory is `/.ssh`, which is exactly what an empty
    /// home makes of `~/.ssh` — so the tilde form still joins, and only the
    /// absolute form stops.
    ///
    /// The behaviour is the better of the two and the comment is the part that
    /// is wrong; this pins the behaviour so the comment is what gets fixed.
    func testAnEmptyHomeStillJoinsTheTildeForm() {
        let found = KeyUsage.ofKeys(SSHConfigFile.parse("Host box\n  IdentityFile ~/.ssh/work_rsa\n"),
                                    keys: keys, home: "")
        XCTAssertEqual(found["work_rsa"], .namedBy(["box"]))

        let absolute = KeyUsage.ofHosts(
            SSHConfigFile.parse("Host box\n  IdentityFile /Users/someone/.ssh/work_rsa\n"),
            keys: keys, home: "")
        XCTAssertEqual(absolute[0], [.elsewhere("/Users/someone/.ssh/work_rsa")],
                       "with no home, an absolute path is somebody else's directory")
    }

    /// `~otheruser/.ssh/id_rsa` is a path `ssh` expands against **that user's**
    /// home. Whatever this module makes of it, it must not make it one of this
    /// person's keys: a row saying `id_ed25519` is used by that block would be
    /// naming the wrong key.
    func testAnotherUsersTildePathIsNotThisUsersKey() {
        let found = KeyUsage.ofHosts(
            SSHConfigFile.parse("Host box\n  IdentityFile ~bob/.ssh/id_ed25519\n"),
            keys: keys, home: home)
        guard case .elsewhere = found[0]?.first else {
            return XCTFail("`~bob/.ssh/id_ed25519` was read as \(String(describing: found[0]))")
        }
        XCTAssertEqual(KeyUsage.ofKeys(
            SSHConfigFile.parse("Host box\n  IdentityFile ~bob/.ssh/id_ed25519\n"),
            keys: keys, home: home)["id_ed25519"], .byDefaultName,
            "another user's key was counted as this person's")
    }
}
