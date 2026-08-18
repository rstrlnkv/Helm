import XCTest
@testable import Module_Hosts_Engine

/// What in `~/.ssh` is a key, what `ssh-keygen -l` said about it, and what the
/// agent is doing — the three readings tab 3 is built out of, none of which
/// touches a private key.
final class KeyInventoryTests: XCTestCase {

    private let realDirectory = ["config", "known_hosts", "known_hosts.old",
                                 "id_ed25519", "id_ed25519.pub",
                                 "id_rsa", "id_rsa.pub",
                                 "authorized_keys", ".DS_Store"]

    func testTheFurnitureIsNotCountedAsKeys() {
        XCTAssertEqual(KeyInventory.pairs(in: realDirectory).map(\.name),
                       ["id_ed25519", "id_rsa"])
    }

    /// A private key whose public half was deleted is still a key: `ssh-keygen
    /// -y` regenerates the public one, and hiding the row would hide a key
    /// somebody has.
    func testAKeyWithNoPublicHalfIsStillAKey() {
        let pairs = KeyInventory.pairs(in: ["id_ed25519"])
        XCTAssertEqual(pairs.map(\.name), ["id_ed25519"])
        XCTAssertEqual(pairs.first?.hasPublicHalf, false)
    }

    /// The other way round is **not** a key: a `.pub` whose private half is gone
    /// has nothing to load into an agent and nothing to `chmod`, and a row for
    /// it would offer both.
    func testAnOrphanPublicHalfIsNotAKey() {
        XCTAssertTrue(KeyInventory.pairs(in: ["id_ed25519.pub"]).isEmpty)
    }

    func testTheOrderIsTheSameOnEveryRead() {
        let once = KeyInventory.pairs(in: ["id_rsa", "aaa", "id_ed25519", "zzz"]).map(\.name)
        let again = KeyInventory.pairs(in: ["zzz", "id_ed25519", "aaa", "id_rsa"]).map(\.name)
        XCTAssertEqual(once, again)
        XCTAssertEqual(once, ["aaa", "id_ed25519", "id_rsa", "zzz"])
    }

    // MARK: - `ssh-keygen -l`

    func testAnOrdinaryLineIsRead() {
        let described = KeyInventory.described(
            "256 SHA256:9Xc2m1oQ4RmT8Zg0uJ5b7Wd3Yy1P0Kk8L2N4S6t8V0A user@mac (ED25519)")
        XCTAssertEqual(described?.bits, 256)
        XCTAssertEqual(described?.type, "ED25519")
        XCTAssertEqual(described?.comment, "user@mac")
        XCTAssertEqual(described?.fingerprint,
                       "SHA256:9Xc2m1oQ4RmT8Zg0uJ5b7Wd3Yy1P0Kk8L2N4S6t8V0A")
    }

    /// Comments hold spaces — `-C "работа, старый ноутбук"` is ordinary — so the
    /// comment is a span between two known fields rather than a field of its
    /// own. A parser that took field three would show one word and drop the
    /// rest.
    func testACommentWithSpacesSurvivesWhole() {
        let described = KeyInventory.described("4096 SHA256:abc work laptop, 2019 (RSA)")
        XCTAssertEqual(described?.comment, "work laptop, 2019")
        XCTAssertEqual(described?.type, "RSA")
    }

    /// A key made with `-C ''` has no comment at all, and an empty column is the
    /// honest way to draw that.
    func testAKeyWithNoCommentReadsAsEmptyRatherThanAsTheType() {
        let described = KeyInventory.described("256 SHA256:abc (ED25519)")
        XCTAssertEqual(described?.comment, "")
        XCTAssertEqual(described?.type, "ED25519")
    }

    /// Refused rather than guessed: a fingerprint landing in the comment column
    /// is what an over-eager parser produces, and a person reads it as fact.
    func testALineThisCannotReadIsRefused() {
        XCTAssertNil(KeyInventory.described(""))
        XCTAssertNil(KeyInventory.described("ssh-keygen: /Users/x/.ssh/id_rsa is not a key"))
        XCTAssertNil(KeyInventory.described("256 not-a-fingerprint user (ED25519)"))
        XCTAssertNil(KeyInventory.described("256 SHA256:abc user ED25519"))
    }
}
