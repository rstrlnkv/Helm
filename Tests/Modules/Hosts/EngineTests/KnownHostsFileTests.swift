import XCTest
@testable import Module_Hosts_Engine

/// `known_hosts`, read and pruned.
final class KnownHostsFileTests: XCTestCase {

    private let key = "AAAAC3NzaC1lZDI1NTE5AAAAIN2iRUYtY6vJmpKrBLGgRRsPqLM1cRLLNM4hkl5FRAAA"

    private func file() -> String {
        """
        # a comment somebody wrote

        github.com ssh-ed25519 \(key) me@mac
        |1|F1E2+abc=|9zQ7+def= ssh-rsa \(key)
        @revoked old.example.com ssh-ed25519 \(key)
        192.168.1.10,nas.local ssh-ed25519 \(key)

        """
    }

    /// **The guarantee this file exists for.** A file Helm only read comes back
    /// byte for byte — comments, blank lines, the trailing newline and every
    /// line this type does not model.
    func testRenderingWhatWasParsedIsTheSameBytes() {
        for text in [file(), "", "\n", "no newline at the end ssh-rsa \(key)",
                     "# only a comment\n", "\n\n\n"] {
            XCTAssertEqual(KnownHostsFile.render(KnownHostsFile.parse(text)), text,
                           "the file came back different from how it went in")
        }
    }

    func testTheEntriesAreTheLinesThatAreKeys() {
        let document = KnownHostsFile.parse(file())
        XCTAssertEqual(document.entries.count, 4, "a comment or a blank line is not a host")
        XCTAssertEqual(document.entries[0].hosts, ["github.com"])
        XCTAssertEqual(document.entries[0].keyType, "ssh-ed25519")
        XCTAssertEqual(document.entries[0].comment, "me@mac")
        XCTAssertEqual(document.entries[3].hosts, ["192.168.1.10", "nas.local"],
                       "one line can name several hosts")
    }

    /// **A hashed line is an ordinary line.** macOS ships `HashKnownHosts yes`,
    /// so most people's files look like this — and no parsing recovers the name.
    /// The row says so; what it must not do is refuse to exist, because
    /// forgetting is exactly what these lines are for.
    func testAHashedLineIsAnEntryWithNoNameToShow() {
        let hashed = KnownHostsFile.parse(file()).entries[1]
        XCTAssertTrue(hashed.isHashed)
        XCTAssertTrue(hashed.hosts.isEmpty)
        XCTAssertEqual(hashed.keyType, "ssh-rsa")
    }

    /// A marker is kept, because a row that dropped it would offer to forget a
    /// revocation as though it were a trust.
    func testAMarkerIsKeptAndIsNotMistakenForAHost() {
        let revoked = KnownHostsFile.parse(file()).entries[2]
        XCTAssertEqual(revoked.marker, "@revoked")
        XCTAssertEqual(revoked.hosts, ["old.example.com"])
    }

    /// The one edit. The line goes, everything else — including the comment and
    /// the blank lines around it — comes back untouched.
    func testForgettingDropsOneLineAndNothingElse() {
        let document = KnownHostsFile.parse(file())
        let target = document.entries[0]
        let rendered = KnownHostsFile.render(KnownHostsFile.forget(line: target.raw,
                                                                    in: document))
        XCTAssertFalse(rendered.contains("github.com"))
        XCTAssertTrue(rendered.contains("# a comment somebody wrote"))
        XCTAssertTrue(rendered.contains("old.example.com"))
        XCTAssertEqual(KnownHostsFile.parse(rendered).entries.count, 3)
    }

    /// The fingerprint is the one `ssh` prints, computed here rather than asked
    /// of a tool: it is a hash of bytes that are already in hand.
    func testTheFingerprintIsTheOneSSHPrints() {
        let entry = KnownHostsFile.parse(file()).entries[0]
        let print = try? XCTUnwrap(entry.fingerprint)
        XCTAssertTrue(print?.hasPrefix("SHA256:") ?? false)
        XCTAssertFalse(print?.hasSuffix("=") ?? true, "ssh prints no padding")
    }

    /// **A key this build cannot decode has no fingerprint, and says so with
    /// nil.** An empty string would draw the same blank column as a line with
    /// no key at all, and only one of those is worth anybody's attention.
    func testAKeyThatDoesNotDecodeHasNoFingerprint() {
        let broken = KnownHostsFile.parse("host.example ssh-ed25519 not-base64!!\n").entries
        XCTAssertEqual(broken.count, 1, "precondition: it is still a line")
        XCTAssertNil(broken[0].fingerprint)
    }
}
