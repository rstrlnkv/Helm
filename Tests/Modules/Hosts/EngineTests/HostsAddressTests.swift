import XCTest
@testable import Module_Hosts_Engine

/// What the two address predicates vouch for.
///
/// Both are `public`, and between them they stand between a token somebody
/// typed and a line written into `/etc/hosts` with administrator rights, so
/// what each says yes to is a product decision and not a detail of `inet_pton`.
/// They differ deliberately: `isAddress` asks «is this line a row?» and is
/// generous, `isWritableAddress` asks «may Helm write this?» and is strict.
final class HostsAddressTests: XCTestCase {

    /// The forms a hand-written check gets wrong, which is what the predicates
    /// exist for. Both answer yes; all measured against this machine's libc.
    func testTheOrdinaryFormsAreAnsweredAsExpected() {
        for token in ["127.0.0.1", "0.0.0.0", "255.255.255.255", "::1", "::",
                      "FE80::1", "::ffff:127.0.0.1", "fe80::1%lo0"] {
            XCTAssertTrue(HostsFile.isAddress(token), "\(token) is an address")
            XCTAssertTrue(HostsFile.isWritableAddress(token), "\(token) is one Helm may write")
        }
    }

    /// Neither predicate is asked to be clever: these are not addresses to
    /// anybody. `" 1.2.3.4"` is here because `inet_aton` accepts a *trailing*
    /// space (measured), so a predicate built on it alone would vouch for one
    /// token where the line holds two.
    func testTheFormsNeitherPredicateVouchesFor() {
        for token in ["", "localhost", "999.1.1.1", "1.2.3.4.5", "1.2.3.4.",
                      " 1.2.3.4", "1.2.3.4 ", "::ffff:999.1.1.1"] {
            XCTAssertFalse(HostsFile.isAddress(token), "\(token) is not an address")
            XCTAssertFalse(HostsFile.isWritableAddress(token), "\(token) is not writable")
        }
    }

    /// **The mirror of the test below.** `inet_pton` refuses all four and
    /// `inet_aton` reads every one of them as an address — `127.1`,
    /// `2130706433` and `0x7f.1` are all the loopback — so a file can hold one
    /// and the older software that reads the file will honour it. Shown,
    /// therefore, and never written: a row nobody can see is a row nobody can
    /// switch off, and that is the defect this module has already paid for.
    func testTheClassicFormsAreShownButNeverWritten() {
        for token in ["1.1", "127.1", "0x7f.1", "2130706433"] {
            XCTAssertTrue(HostsFile.isAddress(token),
                          "\(token) is a mapping to somebody, so the table must show it")
            XCTAssertFalse(HostsFile.isWritableAddress(token),
                           "\(token) means nothing to inet_pton, so Helm must not write it")
        }
    }

    /// **One token, two addresses, one libc.** Measured on macOS 27,
    /// 2026-08-18: `inet_pton(AF_INET, "010.0.0.1")` yields `10.0.0.1` — it
    /// reads the leading zero as decimal padding — while `inet_aton` on the
    /// same string yields `8.0.0.1`, reading it as octal. `0177.0.0.1` is
    /// `177.0.0.1` to one and `127.0.0.1` to the other, which is the loopback
    /// hiding behind a token that does not look like it.
    ///
    /// Helm cannot know which parser reads the file it writes, so it must not
    /// vouch for a form whose meaning depends on that. If the answer turns out
    /// to be that the *parser* should keep showing such a line — a row nobody
    /// can disable is the defect this module just fixed — then the split is
    /// two predicates, one for reading a file and one for accepting what a
    /// person typed, and this test names the second. It is not "delete the
    /// assertion".
    ///
    /// That is what it became, on 2026-08-18: the assertion is the same one,
    /// asked of `isWritableAddress`. `::ffff:010.0.0.1` is the padded decimal
    /// that hides inside an IPv6 token, which `inet_pton` accepts.
    func testAnAddressWithALeadingZeroIsNotVouchedForInWriting() {
        for token in ["010.0.0.1", "0177.0.0.1", "1.2.3.04", "127.000.000.001",
                      "00.0.0.1", "::ffff:010.0.0.1"] {
            XCTAssertFalse(HostsFile.isWritableAddress(token),
                           "\(token) means two different things to two of libc's own parsers")
        }
    }

    /// And the same tokens are still *shown*. `0177.0.0.1 evil.example` is the
    /// loopback wearing an innocent face — the line a person most needs to find
    /// in the table, and the one a strict parser would hide from them.
    func testALeadingZeroAddressIsStillReadAsARow() throws {
        let entry = try XCTUnwrap(HostsFile.parse("0177.0.0.1\tevil.example\n").entries.first)
        XCTAssertEqual(entry.address, "0177.0.0.1")
        XCTAssertEqual(entry.names, ["evil.example"])
    }

    /// The zone is an interface name, and nothing else may ride along in it —
    /// it is written into the file with the address in front of it.
    func testAZoneIsAnInterfaceNameOrItIsNotWritable() {
        XCTAssertTrue(HostsFile.isWritableAddress("fe80::1%en0"))
        for token in ["fe80::1%", "fe80::1%../../etc", "fe80::1%lo 0"] {
            XCTAssertFalse(HostsFile.isWritableAddress(token), "\(token) carries more than a scope")
        }
    }

    /// `withCString` hands C a buffer that still holds the embedded NUL, and C
    /// stops at it: everything after the NUL is invisible to `inet_pton`, which
    /// then answers about a prefix rather than about the token. A pasted field
    /// or a hosts file with a stray zero byte is all it takes, and the token
    /// Helm would then write back is not the one it checked.
    func testATokenWithAnEmbeddedNulIsNotAnAddress() {
        XCTAssertFalse(HostsFile.isAddress("127.0.0.1\u{0}junk"),
                       "the check stopped at the NUL and answered about the prefix")
        XCTAssertFalse(HostsFile.isAddress("127.0.0.1\u{0}"))
        XCTAssertFalse(HostsFile.isWritableAddress("127.0.0.1\u{0}junk"))
        XCTAssertFalse(HostsFile.isWritableAddress("127.0.0.1\u{0}"))
    }

    /// Whatever the verdict above becomes, the file itself must survive being
    /// read — an entry or a verbatim line, the bytes come back either way. This
    /// is here so a fix to the predicate cannot quietly reformat somebody's
    /// file as a side effect.
    func testALeadingZeroLineSurvivesWhicheverWayItIsRead() {
        let text = "010.0.0.1\tbox.local\n0177.0.0.1\tother.local\n"
        XCTAssertEqual(HostsFile.render(HostsFile.parse(text)), text)
    }
}
