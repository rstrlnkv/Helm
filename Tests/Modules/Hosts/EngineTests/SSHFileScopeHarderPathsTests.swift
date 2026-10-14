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
/// being true. The last group asks it about a string that names nothing to the
/// kernel — a `..` after a name it cannot walk through, or after a link — and
/// whose `..` folded by letters leads to a file outside `~/.ssh`.
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

    // MARK: - A spelling the kernel cannot walk, and a `..` that climbs out of a link

    /// The folder every row below is typed against. A scratch folder put
    /// through `URL.resolvingSymlinksInPath()` first, as
    /// `PathCanonical.resolvingAncestors` and `resolvingWholePath` put what
    /// they resolve, so no answer differs from a typed string by a `/private`
    /// in front of `/var`.
    ///
    /// ```
    /// H/.zshrc                  a file outside `.ssh`
    /// H/other/target/x          a file outside `.ssh`
    /// H/.ssh/config             a file
    /// H/.ssh/lnk                a link, absolute, to H/other/target
    /// H/.ssh/a/b                a folder
    /// H/.ssh/deep               a link, relative, to a/b
    /// H/.ssh/dead               a link to nothing
    /// H/.ssh/{missing,x,.zshrc,.ssh}   absent
    /// ```
    private func layout() throws -> (home: URL, ssh: URL) {
        let root = scratchDirectory("ssh-scope-layout").resolvingSymlinksInPath()
        let home = root.appendingPathComponent("H")
        let ssh = home.appendingPathComponent(".ssh")
        try makeDirectory(ssh.appendingPathComponent("a/b"))
        try makeDirectory(home.appendingPathComponent("other/target"))
        try write("Host a\n", to: ssh.appendingPathComponent("config"))
        try write("export PATH\n", to: home.appendingPathComponent(".zshrc"))
        try write("somebody's file\n", to: home.appendingPathComponent("other/target/x"))
        try FileManager.default.createSymbolicLink(
            atPath: ssh.appendingPathComponent("lnk").path,
            withDestinationPath: home.appendingPathComponent("other/target").path)
        try FileManager.default.createSymbolicLink(
            atPath: ssh.appendingPathComponent("deep").path, withDestinationPath: "a/b")
        try FileManager.default.createSymbolicLink(
            atPath: ssh.appendingPathComponent("dead").path,
            withDestinationPath: home.appendingPathComponent("nowhere").path)
        return (home, ssh)
    }

    /// What `lstat` answers for `path`: 0, or the errno.
    private func lstatError(_ path: String) -> Int32 {
        var info = stat()
        return lstat(path, &info) == 0 ? 0 : errno
    }

    /// One string, typed under `~/.ssh` as `relative`: it names nothing to the
    /// kernel (`ENOENT` or `ENOTDIR`) while its `.` and `..` folded by their
    /// letters lead to `landing`, an existing regular file in the home
    /// directory and outside `~/.ssh`. The gate is asked about the string as
    /// typed and has to answer no: a write is the rewrite of a file that was
    /// read, and this spelling names no file the kernel can find.
    ///
    /// The premises come first, each its own assertion, so that an answer of
    /// no is about the string and not about a fixture that was never laid.
    private func assertRefused(_ relative: String, landing: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let (home, ssh) = try layout()
        let typed = ssh.path + "/" + relative

        XCTAssertTrue(FileManager.default.fileExists(atPath: home.path + "/" + landing),
                      "premise: H/\(landing) is the file the letters of `.ssh/\(relative)` lead to",
                      file: file, line: line)
        let error = lstatError(typed)
        XCTAssertTrue(error == ENOENT || error == ENOTDIR,
                      "premise: `.ssh/\(relative)` answers errno \(error) to lstat, not ENOENT or ENOTDIR",
                      file: file, line: line)
        // The control, so that a refusal below is about the string: the same
        // gate over the same layout says yes to the file `~/.ssh` really holds.
        XCTAssertTrue(SSHFileScope.mayWrite(ssh.appendingPathComponent("config"),
                                            home: home, under: ssh),
                      "control: `.ssh/config` is an ordinary file in `.ssh` and was refused",
                      file: file, line: line)

        XCTAssertFalse(SSHFileScope.mayWrite(URL(fileURLWithPath: typed), home: home, under: ssh), """
            `.ssh/\(relative)` names nothing to the kernel, and the gate approved it as a file in \
            `.ssh` — the letters of its `..` lead to H/\(landing), outside `.ssh`.
            """, file: file, line: line)
    }

    /// **A name the kernel cannot walk through, then `..`, then a link.** Folded
    /// by letters, `missing/..` cancels and `lnk/x` is a file in the link's
    /// target; the kernel never gets past `missing`.
    func testADotDotAfterAMissingNameIsRefused() throws {
        try assertRefused("missing/../lnk/x", landing: "other/target/x")
    }

    /// The same after a link to nothing: `dead` is a name the kernel answers
    /// `ENOENT` to when it is walked through.
    func testADotDotAfterADanglingLinkIsRefused() throws {
        try assertRefused("dead/../lnk/x", landing: "other/target/x")
    }

    /// The same after a plain absent name.
    func testADotDotAfterAnAbsentNameIsRefused() throws {
        try assertRefused("x/../lnk/x", landing: "other/target/x")
    }

    /// The same after a regular file, which the kernel answers `ENOTDIR` to.
    func testADotDotAfterARegularFileIsRefused() throws {
        try assertRefused("config/../lnk/x", landing: "other/target/x")
    }

    /// The same after an absent name that is spelled like a file outside `.ssh`.
    func testADotDotAfterAnAbsentDotfileNameIsRefused() throws {
        try assertRefused(".zshrc/../lnk/x", landing: "other/target/x")
    }

    /// The same after an absent name that is spelled like `.ssh` itself.
    func testADotDotAfterAnAbsentNameOfTheSameFolderIsRefused() throws {
        try assertRefused(".ssh/../lnk/x", landing: "other/target/x")
    }

    /// **A `..` after a link climbs out of the link's target, not out of the
    /// folder the link is in.** `deep` leads to `.ssh/a/b`, so the kernel's
    /// `deep/..` is `.ssh/a` and there is no `lnk` there; folded by letters it
    /// is `.ssh`, and `lnk/x` is a file outside it.
    func testADotDotAfterALinkThatClimbsFromItsTargetIsRefused() throws {
        try assertRefused("deep/../lnk/x", landing: "other/target/x")
    }

    /// Two of them: for the kernel `deep/../..` climbs from `.ssh/a/b` to `.ssh/a`
    /// to `.ssh`, and `.zshrc` is then absent there; folded by letters the two
    /// leave `.ssh` and name `H/.zshrc`, a file that runs.
    func testTwoDotDotsAfterALinkReachingTheHomeDirectoryAreRefused() throws {
        try assertRefused("deep/../../.zshrc", landing: ".zshrc")
    }
}
