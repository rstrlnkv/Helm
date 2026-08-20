import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine

/// The fifth gate, against the shapes `SSHFileScopeTests` does not have.
///
/// That file asks about a link *at the leaf* — `~/.ssh/config` pointing
/// somewhere. This one asks about the directory: a `~/.ssh` that is itself a
/// link, which is what a dotfiles manager leaves when it links the folder
/// rather than the files in it; the same thing pointing out of the home
/// directory; and a `..` that needs no link at all. It also asks the question
/// no path resolution can answer — a hard link — and pins the reason the answer
/// does not matter today, because that reason is one edit away from stopping
/// being true.
///
/// Every path is inside a `scratchDirectory`, which drains its own teardown.
/// Nothing here reads or writes the owner's `~/.ssh`.
final class SSHFileScopeHarderPathsTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("ssh-scope-harder")
    /// Somewhere that is not inside the home above — the other side of every
    /// escape below.
    private lazy var elsewhere: URL = scratchDirectory("ssh-scope-outside")

    private var sshDirectory: URL { home.appendingPathComponent(".ssh") }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    private func write(_ text: String, to url: URL) throws -> URL {
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// **The folder is the link, not the file.** `ln -s ~/dotfiles/ssh ~/.ssh`
    /// is a setup people really have, and every file under it is an ordinary
    /// file inside the home directory. It has to keep working — the gate is
    /// asked `under: ~/.ssh`, and both sides of that comparison have to be
    /// resolved or the ordinary case is refused.
    func testASSHDirectoryThatIsItselfALinkInsideTheHomeIsWritable() throws {
        let real = home.appendingPathComponent("dotfiles/ssh")
        try makeDirectory(real)
        try FileManager.default.createSymbolicLink(at: sshDirectory, withDestinationURL: real)
        let config = try write("Host a\n", to: sshDirectory.appendingPathComponent("config"))

        XCTAssertTrue(SSHFileScope.mayWrite(config, home: home, under: sshDirectory), """
            `~/.ssh` is a link into a checkout in the same home directory and the gate refused \
            the config inside it. That is the ordinary dotfiles setup, and refusing it takes \
            Apply off the page for somebody whose file is perfectly writable.
            """)
    }

    /// The same shape pointing out of the home directory. The `under:` check
    /// cannot catch this one — the asked path really is inside the directory it
    /// was told to work in — so what has to refuse it is the resolution of the
    /// whole path against the home.
    func testASSHDirectoryLinkedOutOfTheHomeIsRefused() throws {
        let outside = elsewhere.appendingPathComponent("ssh")
        try makeDirectory(outside)
        try FileManager.default.createSymbolicLink(at: sshDirectory, withDestinationURL: outside)
        let config = try write("Host a\n", to: sshDirectory.appendingPathComponent("config"))

        XCTAssertFalse(SSHFileScope.mayWrite(config, home: home, under: sshDirectory), """
            `~/.ssh` is a link out of the home directory and the gate approved a write into it. \
            The `under:` half is satisfied by construction here — the path is inside the \
            directory it was told to use — so the whole-path resolution is the only thing \
            standing there.
            """)
    }

    /// `..` inside the directory it was told to work in. No link, no
    /// permissions, nothing but a spelling — and `.zshrc` is a file that runs.
    func testAPathClimbingOutOfTheSSHDirectoryIsRefused() throws {
        try makeDirectory(sshDirectory)
        try write("export PATH\n", to: home.appendingPathComponent(".zshrc"))
        let climber = sshDirectory.appendingPathComponent("../.zshrc")

        XCTAssertFalse(SSHFileScope.mayWrite(climber, home: home, under: sshDirectory),
                       "`~/.ssh/../.zshrc` was approved as a file inside `~/.ssh`")
    }

    /// A link at the leaf pointing at a **directory** inside the home. The
    /// resolution lands somewhere real and inside, and the answer still has to
    /// be no: what the gate admits is a regular file that was read.
    func testALinkToADirectoryInsideTheHomeIsRefused() throws {
        try makeDirectory(sshDirectory)
        let folder = home.appendingPathComponent("somewhere")
        try makeDirectory(folder)
        let link = sshDirectory.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

        XCTAssertFalse(SSHFileScope.mayWrite(link, home: home, under: sshDirectory))
    }

    /// One place, several spellings. `~/.ssh//config` and `~/.ssh/./config` are
    /// the file the module reads every time it starts; a gate that refused them
    /// would take Apply away on a path composed one separator differently.
    func testTheSameFileSpelledOddlyIsStillTheSameFile() throws {
        try makeDirectory(sshDirectory)
        try write("Host a\n", to: sshDirectory.appendingPathComponent("config"))

        for spelling in ["/.ssh//config", "/.ssh/./config"] {
            let url = URL(fileURLWithPath: home.path + spelling)
            XCTAssertTrue(SSHFileScope.mayWrite(url, home: home, under: sshDirectory),
                          "\(spelling) is the same file and was refused")
        }
    }

    /// **A hard link is the escape no resolution can see** — the inode is
    /// inside the home directory *and* outside it, and `realpath` has one
    /// answer. The gate says yes, and what saves the file at the other end is
    /// not the gate at all: `PrivateFile.write` is atomic, so it renames a new
    /// inode over the name and leaves the linked file alone.
    ///
    /// Both halves are asserted together on purpose. The day somebody makes
    /// that write non-atomic — which is one plausible way to fix a symlinked
    /// `~/.ssh/config` being replaced by a regular file — this test says what
    /// it costs, in the same breath as the reason it was safe.
    func testAHardLinkOutOfTheHomeIsNotWrittenThrough() throws {
        try makeDirectory(sshDirectory)
        let outside = try write("somebody else's file\n",
                                to: elsewhere.appendingPathComponent("target"))
        let inside = sshDirectory.appendingPathComponent("known_hosts")
        try FileManager.default.linkItem(at: outside, to: inside)

        XCTAssertTrue(SSHFileScope.mayWrite(inside, home: home, under: sshDirectory),
                      "precondition: the gate cannot see a hard link, and does not")

        XCTAssertTrue(SystemKnownHosts(url: inside).write("box.example ssh-rsa AAAAB3\n"))

        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8),
                       "somebody else's file\n", """
            a write through a hard link reached a file outside the home directory. The gate \
            approved the path — it cannot do otherwise, both names are the same inode — so the \
            atomic write was the whole defence, and it is not there any more.
            """)
    }
}
