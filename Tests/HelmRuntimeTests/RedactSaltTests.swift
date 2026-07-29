import XCTest
@testable import HelmRuntime

/// A tag must be stable on this machine and meaningless on any other.
///
/// The tag was an unsalted 16-bit FNV-1a over values drawn from small public
/// lists — bundle ids, VPN providers, Homebrew formulae. Hashing the 104 bundle
/// ids installed on one Mac and inverting the table identified every single
/// one, so the log named the applications after all, and "Copy log" handed that
/// to whoever read the issue.
///
/// Both halves matter, and they pull against each other: salt it per install
/// and the dictionary attack dies; keep it stable across restarts and triage
/// can still ask "the same one as three lines up, and as in yesterday's
/// session?".
final class RedactSaltTests: XCTestCase {
    func testTheSameNameTagsTheSameWayEveryTime() {
        let first = Redact.app("com.acme.tool")
        let second = Redact.app("com.acme.tool")
        XCTAssertEqual(first, second, "a tag that moves between calls cannot be compared at all")
    }

    func testDifferentNamesStillTagDifferently() {
        XCTAssertNotEqual(Redact.app("com.acme.tool"), Redact.app("com.acme.other"))
    }

    func testTheTagIsNotTheUnsaltedHashOfTheName() {
        // What an attacker precomputes: the published algorithm over a name
        // they can guess. If the shipped tag equals it, the salt is not
        // reaching the digest and the dictionary works again.
        func unsalted(_ value: String, prefix: String) -> String {
            var hash: UInt32 = 2_166_136_261
            for byte in value.utf8 {
                hash ^= UInt32(byte)
                hash = hash &* 16_777_619
            }
            return "\(prefix)#" + String(format: "%04x", hash & 0xFFFF)
        }

        // One name would collide by chance once in 65 536; a run of them makes
        // an accidental pass vanishingly unlikely without pinning any value.
        let names = ["com.apple.Safari", "com.acme.tool", "org.mozilla.firefox",
                     "com.microsoft.VSCode", "com.tinyspeck.slackmacgap"]
        let matches = names.filter { Redact.app($0) == unsalted($0, prefix: "app") }
        XCTAssertTrue(matches.count < names.count,
                      "every tag equalled its unsalted hash — the salt is not being mixed in, "
                      + "so anyone holding the log can invert it against a list of bundle ids")
    }

    func testPrefixesStillSeparateTheNamespaces() {
        XCTAssertTrue(Redact.vpn("work").hasPrefix("vpn#"))
        XCTAssertTrue(Redact.app("work").hasPrefix("app#"))
        XCTAssertTrue(Redact.pkg("work").hasPrefix("pkg#"))
        XCTAssertNotEqual(Redact.vpn("work"), Redact.app("work"))
    }
}
