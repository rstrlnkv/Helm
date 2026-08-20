import XCTest
import HelmTestSupport
@testable import Module_Hosts_Engine

/// **The gate lets the dotfiles symlink through; the write must not eat it.**
///
/// `SSHFileScope` is built around one case it names in its own documentation:
/// «`~/.ssh/config` is very often a symlink into a dotfiles checkout —
/// legitimate, and it has to keep working». It resolves the leaf for exactly
/// that reason, so a link into the home directory is approved.
///
/// Approval is only half of «keeps working». The write that follows goes
/// through `PrivateFile.write`, which is `Data.write(options: .atomic)` — and
/// an atomic write is a temporary file `rename`d over the destination. `rename`
/// replaces the **link**, not the file the link points at. So the first Apply
/// on a linked config turns `~/.ssh/config` into an ordinary file, leaves the
/// checkout holding the old text, and disconnects a version-controlled config
/// from `ssh` with nothing said anywhere: the engine's read-back reads the path
/// it just wrote and finds exactly what it sent.
///
/// Both files in this module are written that way, so both are asked here.
/// Nothing below goes near the owner's own `~/.ssh` — every path is inside a
/// `scratchDirectory`, which drains its own teardown.
final class TheDotfilesLinkSurvivesAWriteTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("hosts-dotfiles")

    /// A checkout with the real file in it, and `~/.ssh/<name>` linked to it —
    /// the shape `chezmoi`, `stow` and every hand-rolled dotfiles script leave
    /// behind.
    private func linkedFile(named name: String, saying text: String) throws -> (link: URL,
                                                                               real: URL) {
        let checkout = home.appendingPathComponent("dotfiles")
        let sshDirectory = home.appendingPathComponent(".ssh")
        for directory in [checkout, sshDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let real = checkout.appendingPathComponent(name)
        try text.write(to: real, atomically: true, encoding: .utf8)
        let link = sshDirectory.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (link, real)
    }

    /// `lstat`'s answer, not `stat`'s: whether the *name* is still a link.
    private func isASymlink(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    func testWritingTheConfigKeepsTheLinkAndReachesTheCheckout() throws {
        let (link, real) = try linkedFile(named: "config", saying: "Host old\n")

        // Precondition, and the reason this test is about a case the module
        // means to support: the gate approves the link.
        XCTAssertTrue(SSHFileScope.mayWrite(link, home: home,
                                            under: home.appendingPathComponent(".ssh")),
                      "precondition: the gate no longer admits a dotfiles link, so the write "
                      + "below is not the case this test is about")

        XCTAssertTrue(SystemSSHConfig(url: link).write("Host new\n"))

        XCTAssertTrue(isASymlink(link), """
            `~/.ssh/config` was a symlink into a dotfiles checkout and is an ordinary file now. \
            The atomic write renamed a new inode over the link, so the checkout still holds the \
            old text, `git status` says nothing, and every later edit there stops reaching ssh. \
            The gate went out of its way to admit this file; the write took it away.
            """)
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "Host new\n",
                       "the checkout did not receive the write it was linked for")
    }

    /// The same file next door, written the same way. `known_hosts` is linked
    /// less often than a config and it is linked — and Forget writes the whole
    /// file, so one press is enough to break it.
    func testWritingKnownHostsKeepsTheLinkAndReachesTheCheckout() throws {
        let (link, real) = try linkedFile(named: "known_hosts",
                                          saying: "github.com ssh-ed25519 AAAAB3 me@mac\n")

        XCTAssertTrue(SSHFileScope.mayWrite(link, home: home,
                                            under: home.appendingPathComponent(".ssh")),
                      "precondition: the gate no longer admits a dotfiles link")

        XCTAssertTrue(SystemKnownHosts(url: link).write("old.example ssh-rsa AAAAB3\n"))

        XCTAssertTrue(isASymlink(link), """
            `~/.ssh/known_hosts` was a symlink into a dotfiles checkout and is an ordinary file \
            now — one Forget was enough.
            """)
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8),
                       "old.example ssh-rsa AAAAB3\n",
                       "the checkout did not receive the write it was linked for")
    }

    /// **Why nothing catches it.** The engine's defence against a write that
    /// did not land is to read the path back and compare — and the path reads
    /// back as exactly what was sent, because the new regular file *is* at that
    /// path. A verification that follows the same name it wrote cannot see a
    /// name that changed what it means.
    func testTheReadBackCannotSeeIt() throws {
        let (link, real) = try linkedFile(named: "config", saying: "Host old\n")
        let port = SystemSSHConfig(url: link)

        XCTAssertTrue(port.write("Host new\n"))

        XCTAssertEqual(port.read(), "Host new\n",
                       "precondition: the read-back is satisfied, which is why this is silent")
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "Host new\n", """
            the read-back said the write landed and the file it was pointed at never changed — \
            the two readings disagree because the second one follows the link and the first one \
            no longer has a link to follow
            """)
    }
}
