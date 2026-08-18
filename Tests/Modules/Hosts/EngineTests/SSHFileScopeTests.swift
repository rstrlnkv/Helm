import XCTest
import HelmTestSupport
@testable import Module_Hosts_Engine

/// The fifth gate. `RemovableScope`, `UserFileScope`, `WatchScope` and
/// `ScanRoot` each answer a different question; this one answers **may Helm
/// write this path?**
///
/// The question is not rhetorical here, because `~/.ssh/config` is very often a
/// symlink into a dotfiles repository — that is legitimate and has to keep
/// working — while a symlink pointing at `/etc/sudoers` is the same shape and
/// must not. So the answer cannot be «the name looks right»: the path is
/// resolved first, and the resolved file is what is judged.
final class SSHFileScopeTests: XCTestCase {

    /// `scratchDirectory` drains and asserts its own teardown, which is the
    /// whole reason it lives in `HelmTestSupport` rather than in each file.
    private lazy var scratch: URL = scratchDirectory("ssh-scope")

    private func write(_ text: String, to name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testAnOrdinaryFileInsideTheHomeDirectoryIsWritable() throws {
        let file = try write("Host a\n", to: "config")
        XCTAssertTrue(SSHFileScope.mayWrite(file, home: scratch))
    }

    /// The case the gate exists to keep working: the file is a link, and what
    /// it points at is an ordinary file that is still inside the home
    /// directory — somebody's dotfiles checkout.
    func testASymlinkIntoTheDotfilesCheckoutIsWritable() throws {
        let real = try write("Host a\n", to: "dotfiles-config")
        let link = scratch.appendingPathComponent("config-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertTrue(SSHFileScope.mayWrite(link, home: scratch))
    }

    /// The same shape, pointing out of the home directory. A gate that reads
    /// the name rather than the destination writes `/etc/sudoers` through it.
    func testASymlinkPointingOutOfTheHomeDirectoryIsRefused() throws {
        let outside = URL(fileURLWithPath: "/etc/hosts")
        let link = scratch.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(SSHFileScope.mayWrite(link, home: scratch))
    }

    /// `..` is the other way out, and it needs no symlink at all.
    func testAPathClimbingOutWithDotDotIsRefused() {
        let climber = scratch.appendingPathComponent("../../etc/hosts")
        XCTAssertFalse(SSHFileScope.mayWrite(climber, home: scratch))
    }

    /// A directory is not a file to write, whatever its name is.
    func testADirectoryIsRefused() {
        XCTAssertFalse(SSHFileScope.mayWrite(scratch, home: scratch))
    }

    /// A path that does not exist yet is refused: every write this module makes
    /// is a rewrite of a file it has read, and «create whatever you were
    /// pointed at» is a different power.
    func testAPathThatIsNotThereIsRefused() {
        XCTAssertFalse(SSHFileScope.mayWrite(scratch.appendingPathComponent("absent"),
                                             home: scratch))
    }

    /// The home directory itself is not a licence: the gate is about `~/.ssh`'s
    /// files, and a file in the home root — `.zshrc`, say — is not one of them.
    func testAFileOutsideTheSSHDirectoryIsRefusedWhenOneIsNamed() throws {
        let sshDirectory = scratch.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let inside = sshDirectory.appendingPathComponent("config")
        try "Host a\n".write(to: inside, atomically: true, encoding: .utf8)
        let outside = try write("export PATH\n", to: ".zshrc")
        XCTAssertTrue(SSHFileScope.mayWrite(inside, home: scratch, under: sshDirectory))
        XCTAssertFalse(SSHFileScope.mayWrite(outside, home: scratch, under: sshDirectory))
    }
}
