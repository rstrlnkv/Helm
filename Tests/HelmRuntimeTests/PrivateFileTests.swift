import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// Files that name somebody's files are written at 0600, every time.
///
/// **The mode is not a property of the file, it is a property of each write.**
/// `.atomic` writes a temporary file and renames it over the target, so the mode
/// comes from the process umask on a fresh write and from the *replaced* file on
/// a rewrite. Measured in a plain process: 0644 either way. Get it wrong once in
/// a file holding an index of every filename on the volume and the privacy of
/// that list becomes an accident of the environment.
final class PrivateFileTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = scratchDirectory("private-file")
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    func testAFreshWriteIsPrivate() throws {
        let url = directory.appendingPathComponent("fresh.json")
        XCTAssertTrue(PrivateFile.write(["a", "b"], to: url))
        XCTAssertEqual(try mode(of: url), 0o600)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)),
                       ["a", "b"])
    }

    /// The case the three hand-written copies existed for: a file that is
    /// already readable stays readable through an atomic rewrite unless the mode
    /// is set again.
    func testARewriteOverALooseFileIsMadePrivate() throws {
        let url = directory.appendingPathComponent("loose.json")
        FileManager.default.createFile(atPath: url.path, contents: Data("[]".utf8),
                                       attributes: [.posixPermissions: 0o644])
        XCTAssertEqual(try mode(of: url), 0o644)
        XCTAssertTrue(PrivateFile.write(["later"], to: url))
        XCTAssertEqual(try mode(of: url), 0o600)
    }

    func testRawDataIsWrittenTheSameWay() throws {
        let url = directory.appendingPathComponent("salt.bin")
        FileManager.default.createFile(atPath: url.path, contents: Data([0]),
                                       attributes: [.posixPermissions: 0o644])
        XCTAssertTrue(PrivateFile.write(Data([1, 2, 3]), to: url))
        XCTAssertEqual(try mode(of: url), 0o600)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }

    func testANewDirectoryIsPrivate() throws {
        let url = directory.appendingPathComponent("new/deeper")
        XCTAssertTrue(PrivateFile.directory(at: url))
        XCTAssertEqual(try mode(of: url), 0o700)
    }

    /// `attributes:` covers only the directories the call itself creates, so a
    /// looser one left by an earlier build would keep its mode for ever.
    func testAnExistingLooseDirectoryIsTightened() throws {
        let url = directory.appendingPathComponent("old")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(try mode(of: url), 0o755)
        XCTAssertTrue(PrivateFile.directory(at: url))
        XCTAssertEqual(try mode(of: url), 0o700)
    }

    /// A file this app appends to rather than rewrites never passes through
    /// `write`, so its mode is whatever the umask gave it on the day it was
    /// created — `~/Library/Logs/Helm/helm.log` is 0644 on the machine this was
    /// measured on, in a 0700 folder
    /// (ARCHITECTURE.md § Diagnostics log). Tightening it is a separate call because it is a separate
    /// moment: once at launch, not once a line.
    func testAnExistingLooseFileIsTightened() throws {
        let url = directory.appendingPathComponent("appended.log")
        FileManager.default.createFile(atPath: url.path, contents: Data("line\n".utf8),
                                       attributes: [.posixPermissions: 0o644])
        XCTAssertEqual(try mode(of: url), 0o644)

        XCTAssertTrue(PrivateFile.harden(at: url))

        XCTAssertEqual(try mode(of: url), 0o600)
        XCTAssertEqual(try Data(contentsOf: url), Data("line\n".utf8),
                       "tightening the mode rewrote the file")
    }

    /// And a file that is not there is not an error: the log is hardened at
    /// launch, before anything has been written.
    func testTighteningWhatIsNotThereIsNotAnError() {
        XCTAssertFalse(PrivateFile.harden(at: directory.appendingPathComponent("absent.log")))
    }

    /// A write that cannot happen is never a reason to fail the work that asked
    /// for it — these files are caches, journals and salts — so it reports
    /// rather than throws, and the caller decides.
    func testAWriteThatCannotHappenSaysSo() {
        let url = directory.appendingPathComponent("nowhere/at/all.json")
        XCTAssertFalse(PrivateFile.write(["x"], to: url))
        XCTAssertTrue(PrivateFile.write(["x"], to: directory.appendingPathComponent("fine.json")))
    }

    // MARK: - A write that keeps the link

    /// What `lstat` says the name is, without following it.
    private func isALink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    /// A link to a file that is not there yet, in a folder that is, and
    /// `.whatItLeadsTo` promises the link survives. A resolver that answers a
    /// dangling link with the link's own name sends the rename onto the link,
    /// which then stops being one.
    func testALinkToAFileNotThereYetSurvivesAndTheTargetReceivesTheBytes() throws {
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: target.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path),
                       "the arrangement is wrong: the target is already there")

        let landed = PrivateFile.write(Data([7, 8, 9]), to: link, destination: .whatItLeadsTo)

        XCTAssertTrue(landed, "a write whose target can be made was refused")
        XCTAssertTrue(isALink(link), "the write replaced the link with a regular file")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       target.path, "the link now points somewhere else")
        XCTAssertEqual(try? Data(contentsOf: target), Data([7, 8, 9]),
                       "the bytes did not arrive at the link's target")
        XCTAssertEqual(try mode(of: target), 0o600)
        XCTAssertEqual(try names(in: directory), ["link.json", "target.json"],
                       "something else was left in the folder")
    }

    /// The same, for a link spelled relative to its own folder: where it leads is
    /// read from the folder the link lives in, not from the process's.
    func testARelativeLinkToAFileNotThereYetSurvives() throws {
        let real = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: "real/target.json")

        let landed = PrivateFile.write(Data([1, 2]), to: link, destination: .whatItLeadsTo)

        XCTAssertTrue(landed)
        XCTAssertTrue(isALink(link), "the write replaced the link with a regular file")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       "real/target.json")
        XCTAssertEqual(try? Data(contentsOf: real.appendingPathComponent("target.json")),
                       Data([1, 2]))
        XCTAssertEqual(try names(in: directory), ["link.json", "real"])
        XCTAssertEqual(try names(in: real), ["target.json"])
    }

    /// Two links that lead to each other lead nowhere: there is no place for the
    /// bytes, so nothing is written and neither name is touched.
    func testTwoLinksLeadingToEachOtherRefuseTheWrite() throws {
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        try FileManager.default.createSymbolicLink(atPath: first.path,
                                                   withDestinationPath: second.path)
        try FileManager.default.createSymbolicLink(atPath: second.path,
                                                   withDestinationPath: first.path)

        let landed = PrivateFile.write(Data([1]), to: first, destination: .whatItLeadsTo)

        XCTAssertFalse(landed, "a write was answered for a name that leads nowhere")
        XCTAssertTrue(isALink(first), "the first name stopped being a link")
        XCTAssertTrue(isALink(second), "the second name stopped being a link")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: first.path),
                       second.path)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: second.path),
                       first.path)
        XCTAssertEqual(try names(in: directory), ["first", "second"],
                       "a file was left beside the loop")
    }

    /// A link that leads to itself is the shortest loop.
    func testALinkLeadingToItselfRefusesTheWrite() throws {
        let link = directory.appendingPathComponent("self")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: link.path)

        let landed = PrivateFile.write(Data([1]), to: link, destination: .whatItLeadsTo)

        XCTAssertFalse(landed, "a write was answered for a name that leads nowhere")
        XCTAssertTrue(isALink(link), "the name stopped being a link")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       link.path)
        XCTAssertEqual(try names(in: directory), ["self"], "a file was left beside the loop")
    }

    /// A link into a folder that does not exist has nowhere to put the bytes, and
    /// the write is not allowed to make one up by replacing the link: it says no,
    /// and the link and the folder around it are as they were.
    func testALinkIntoAFolderThatIsNotThereRefusesTheWrite() throws {
        let target = directory.appendingPathComponent("missing/target.json")
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: target.path)

        let landed = PrivateFile.write(Data([1]), to: link, destination: .whatItLeadsTo)

        XCTAssertFalse(landed, "a write was answered for a target whose folder is not there")
        XCTAssertTrue(isALink(link), "the write replaced the link with a regular file")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                       target.path)
        XCTAssertEqual(try names(in: directory), ["link.json"],
                       "something was created beside the link")
    }

    /// Three links in a loop lead nowhere, as two do: nothing is written and
    /// each of the three is still a link. A walk that answers the name it
    /// stopped at when it runs out of hops, rather than nothing, sends the
    /// rename onto one of the links.
    func testThreeLinksInALoopRefuseTheWrite() throws {
        let names3 = ["one", "two", "three"]
        for (index, name) in names3.enumerated() {
            try FileManager.default.createSymbolicLink(
                atPath: directory.appendingPathComponent(name).path,
                withDestinationPath: directory.appendingPathComponent(
                    names3[(index + 1) % names3.count]).path)
        }

        let landed = PrivateFile.write(Data([1]), to: directory.appendingPathComponent("one"),
                                       destination: .whatItLeadsTo)

        XCTAssertFalse(landed, "a write was answered for a name that leads nowhere")
        for name in names3 {
            XCTAssertTrue(isALink(directory.appendingPathComponent(name)),
                          "\(name) stopped being a link")
        }
        XCTAssertEqual(try names(in: directory), names3.sorted(),
                       "a file was left beside the loop")
    }

    /// A name that is no link at all is written to as it is: the bytes replace
    /// what was there, at 0600, and nothing else is left in the folder.
    func testANameThatIsNoLinkIsWrittenToAsItIs() throws {
        let url = directory.appendingPathComponent("plain.json")
        FileManager.default.createFile(atPath: url.path, contents: Data([0]),
                                       attributes: [.posixPermissions: 0o644])

        XCTAssertTrue(PrivateFile.write(Data([4, 5]), to: url, destination: .whatItLeadsTo))

        XCTAssertFalse(isALink(url))
        XCTAssertEqual(try? Data(contentsOf: url), Data([4, 5]))
        XCTAssertEqual(try mode(of: url), 0o600)
        XCTAssertEqual(try names(in: directory), ["plain.json"])
    }

    /// The scratch inode is born in the folder of the file the link leads to, so
    /// a link that sits in a folder nobody can add to still receives the bytes
    /// when the checkout it leads to can be written.
    func testALinkInAFolderThatCannotBeWrittenReachesAFolderThatCan() throws {
        let checkout = directory.appendingPathComponent("checkout")
        let home = directory.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let target = checkout.appendingPathComponent("config")
        let link = home.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: target.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: home.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: home.path)
        // The arrangement has to hold: this process cannot add a name to `home`.
        XCTAssertFalse(FileManager.default.createFile(
            atPath: home.appendingPathComponent("probe").path, contents: nil),
                       "the arrangement is wrong: the link's folder can be written")

        let landed = PrivateFile.write(Data([6]), to: link, destination: .whatItLeadsTo)

        XCTAssertTrue(landed, "the scratch was born beside the link, not beside its target")
        XCTAssertTrue(isALink(link))
        XCTAssertEqual(try? Data(contentsOf: target), Data([6]))
    }

    // MARK: - A name that ends nowhere, a folder that is not there, a chain of links

    /// A link whose text ends in `.`, `..` or a slash leads to a folder, and a
    /// folder is no place for the bytes: the write is refused, the links are as
    /// they were and nothing is left in the folder or beside the links. Taking
    /// out the walk's own check of these endings leaves the row green, because
    /// the rename onto a folder is refused as well: the row holds the answer,
    /// not which check gave it.
    func testALinkThatEndsInADotOrASlashRefusesTheWrite() throws {
        let fm = FileManager.default
        let folder = directory.appendingPathComponent("folder")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let texts = ["toDot": "folder/.", "toDotDot": "folder/..", "toSlash": "folder/"]
        for (name, text) in texts {
            try fm.createSymbolicLink(atPath: directory.appendingPathComponent(name).path,
                                      withDestinationPath: text)
        }

        for (name, text) in texts.sorted(by: { $0.key < $1.key }) {
            let link = directory.appendingPathComponent(name)
            let landed = PrivateFile.write(Data([1]), to: link, destination: .whatItLeadsTo)

            XCTAssertFalse(landed, "a write was answered for a link that ends in \(text)")
            XCTAssertTrue(isALink(link), "\(name) stopped being a link")
            XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), text)
        }
        XCTAssertEqual(try names(in: directory), ["folder", "toDot", "toDotDot", "toSlash"],
                       "something was left beside the links")
        XCTAssertEqual(try names(in: folder), [], "something was put in the folder")
    }

    /// A folder above the name that is a link to nothing, reached by its path and
    /// through the text of a link, has no place to put a scratch inode in: the
    /// write is refused and neither link is touched. Answering the name as it
    /// stands when the folder cannot be read leaves the row green, because the
    /// scratch is then made through the same path and cannot be: the row holds
    /// the answer, not which check gave it.
    func testAFolderThatIsALinkToNothingRefusesTheWrite() throws {
        let fm = FileManager.default
        let dangling = directory.appendingPathComponent("dangling")
        try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: "missing")
        let through = directory.appendingPathComponent("through.json")
        try fm.createSymbolicLink(atPath: through.path, withDestinationPath: "dangling/x.json")
        XCTAssertFalse(fm.fileExists(atPath: dangling.path),
                       "the arrangement is wrong: the folder is there")

        let byItsPath = PrivateFile.write(Data([1]), to: dangling.appendingPathComponent("x.json"),
                                          destination: .whatItLeadsTo)
        let byALink = PrivateFile.write(Data([1]), to: through, destination: .whatItLeadsTo)

        XCTAssertFalse(byItsPath, "a write was answered for a folder that leads nowhere")
        XCTAssertFalse(byALink, "a write was answered through a link into a folder that leads nowhere")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: dangling.path), "missing")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: through.path), "dangling/x.json")
        XCTAssertEqual(try names(in: directory), ["dangling", "through.json"],
                       "something was made where the folder should have been")
    }

    /// `count` links one after the other, the last one leading to a file that is
    /// there.
    private func aChainOfLinks(_ count: Int) throws -> (first: URL, end: URL) {
        // The folder is spelled without the links that lead to it (`/var` is
        // one, and `resolvingSymlinksInPath` leaves it), so that the kernel
        // counts the links of the chain and no others.
        let real = try XCTUnwrap(realpath(directory.path, nil))
        defer { free(real) }
        let base = URL(fileURLWithPath: String(cString: real))
        let end = base.appendingPathComponent("end.json")
        try Data([0]).write(to: end)
        for index in 1...count {
            let next = index == count ? end.path
                                      : base.appendingPathComponent("link-\(index + 1)").path
            try FileManager.default.createSymbolicLink(
                atPath: base.appendingPathComponent("link-\(index)").path,
                withDestinationPath: next)
        }
        return (base.appendingPathComponent("link-1"), end)
    }

    /// The longest chain the kernel itself follows (`open` is asked first, with
    /// the folder spelled without links of its own) is followed to its end: the
    /// file there receives the bytes and the first link stays a link.
    func testAChainOfThirtyTwoLinksIsFollowedToItsEnd() throws {
        let chain = try aChainOfLinks(32)
        let kernel = open(chain.first.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(kernel, 0, "the arrangement is wrong: the kernel does not follow 32 links")
        close(kernel)

        let landed = PrivateFile.write(Data([9]), to: chain.first, destination: .whatItLeadsTo)

        XCTAssertTrue(landed, "a chain the kernel follows was refused")
        XCTAssertEqual(try? Data(contentsOf: chain.end), Data([9]))
        XCTAssertTrue(isALink(chain.first), "the first link stopped being one")
        XCTAssertEqual(try names(in: directory).count, 33, "something was left beside the chain")
    }

    /// One link more than the kernel follows (`open` answers `ELOOP`) is refused,
    /// with the file at its end as it was and the first link still a link.
    func testAChainOfThirtyThreeLinksRefusesTheWrite() throws {
        let chain = try aChainOfLinks(33)
        errno = 0
        XCTAssertLessThan(open(chain.first.path, O_RDONLY), 0)
        XCTAssertEqual(errno, ELOOP, "the arrangement is wrong: the kernel follows 33 links")

        let landed = PrivateFile.write(Data([9]), to: chain.first, destination: .whatItLeadsTo)

        XCTAssertFalse(landed, "a chain the kernel refuses was written through")
        XCTAssertEqual(try? Data(contentsOf: chain.end), Data([0]))
        XCTAssertTrue(isALink(chain.first), "the first link stopped being one")
        XCTAssertEqual(try names(in: directory).count, 34, "something was left beside the chain")
    }

    /// A relative text is read from the folder of the link that carries it, which
    /// is not the folder the walk began in once it has gone through a link. The
    /// file the kernel reaches is not there yet; a different one sits where a
    /// text read from the first folder would end.
    func testARelativeLinkInASecondFolderIsReadFromThatFolder() throws {
        let fm = FileManager.default
        let first = directory.appendingPathComponent("a")
        let second = directory.appendingPathComponent("b")
        try fm.createDirectory(at: first, withIntermediateDirectories: true)
        try fm.createDirectory(at: second, withIntermediateDirectories: true)
        let start = first.appendingPathComponent("first")
        try fm.createSymbolicLink(atPath: start.path, withDestinationPath: "../b/second")
        try fm.createSymbolicLink(atPath: second.appendingPathComponent("second").path,
                                  withDestinationPath: "third.json")
        let decoy = first.appendingPathComponent("third.json")
        try Data([2, 2]).write(to: decoy)
        XCTAssertFalse(fm.fileExists(atPath: start.path),
                       "the arrangement is wrong: the chain does not end in a file that is not there")

        let landed = PrivateFile.write(Data([9]), to: start, destination: .whatItLeadsTo)

        XCTAssertTrue(landed, "a chain whose end can be made was refused")
        XCTAssertEqual(try? Data(contentsOf: decoy), Data([2, 2]),
                       "the bytes went to the file beside the first link")
        XCTAssertEqual(try? Data(contentsOf: second.appendingPathComponent("third.json")), Data([9]))
        XCTAssertTrue(isALink(start))
        XCTAssertTrue(isALink(second.appendingPathComponent("second")))
        XCTAssertEqual(try names(in: first), ["first", "third.json"])
        XCTAssertEqual(try names(in: second), ["second", "third.json"])
    }

    // MARK: - A link whose text steps up out of another link

    /// `name` leads to `d/../t.json` and `d` leads to `p/q`. The kernel follows
    /// `d` before it takes the `..` that comes after it, so it lands in
    /// `p/t.json`; read by its letters the same text names `t.json` in the
    /// folder the links sit in. Both places are inside the scratch folder.
    private struct SteppedUp {
        let link: URL
        let kernel: URL
        let letters: URL
        let linkedFolder: URL
        let deeper: URL
        let parent: URL
    }

    private func linkThatStepsUpOutOfALink() throws -> SteppedUp {
        let fm = FileManager.default
        let deeper = directory.appendingPathComponent("p/q")
        try fm.createDirectory(at: deeper, withIntermediateDirectories: true)
        let linkedFolder = directory.appendingPathComponent("d")
        try fm.createSymbolicLink(atPath: linkedFolder.path, withDestinationPath: "p/q")
        let link = directory.appendingPathComponent("name")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "d/../t.json")
        return SteppedUp(link: link,
                         kernel: directory.appendingPathComponent("p/t.json"),
                         letters: directory.appendingPathComponent("t.json"),
                         linkedFolder: linkedFolder, deeper: deeper,
                         parent: directory.appendingPathComponent("p"))
    }

    /// Nothing but the arranged names is in any of the three folders: no scratch
    /// inode was left, no file was made anywhere the row did not put one.
    private func assertNothingElseWasLeft(_ layout: SteppedUp, in folders: [String: [String]],
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try names(in: directory), folders["scratch"], "in the scratch folder",
                       file: file, line: line)
        XCTAssertEqual(try names(in: layout.parent), folders["p"], "in p", file: file, line: line)
        XCTAssertEqual(try names(in: layout.deeper), [], "in p/q", file: file, line: line)
    }

    /// The bytes land where the kernel follows the link, or the write is
    /// refused; never at the place only the letters of the text reach. The file
    /// the kernel reaches is there, and so is a different one at the letters'
    /// place.
    func testALinkThatStepsUpOutOfALinkedFolderWritesWhereTheKernelLandsOrRefuses() throws {
        let layout = try linkThatStepsUpOutOfALink()
        try Data([1, 1]).write(to: layout.kernel)
        try Data([2, 2]).write(to: layout.letters)
        // The arrangement: the kernel itself says which of the two files the link is.
        XCTAssertEqual(try? Data(contentsOf: layout.link), Data([1, 1]),
                       "the arrangement is wrong: the kernel does not land in p/t.json")

        let landed = PrivateFile.write(Data([9]), to: layout.link, destination: .whatItLeadsTo)

        XCTAssertEqual(try? Data(contentsOf: layout.letters), Data([2, 2]),
                       "the bytes went to the place only the letters of the link reach")
        XCTAssertFalse(isALink(layout.letters))
        XCTAssertTrue(isALink(layout.link), "the link stopped being one")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: layout.link.path),
                       "d/../t.json")
        XCTAssertTrue(isALink(layout.linkedFolder), "the linked folder stopped being a link")
        XCTAssertEqual(try? Data(contentsOf: layout.kernel), landed ? Data([9]) : Data([1, 1]),
                       landed ? "the write answered true and the kernel's file does not hold it"
                              : "the write was refused and still touched the kernel's file")
        try assertNothingElseWasLeft(layout, in: ["scratch": ["d", "name", "p", "t.json"],
                                                  "p": ["q", "t.json"]])
    }

    /// The same text with the file the kernel leads to not there yet. The kernel
    /// would make it in `p`, which is a folder that exists; a different file sits
    /// at the letters' place, so that a rename onto it shows as changed bytes.
    func testTheSameLinkWithTheKernelsFileNotThereYetLeavesTheLettersFileAlone() throws {
        let layout = try linkThatStepsUpOutOfALink()
        try Data([2, 2]).write(to: layout.letters)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.link.path),
                       "the arrangement is wrong: the link does not dangle")
        // The arrangement: let the kernel make the file the link leads to, see
        // where it appears, and take it away again. Without `O_EXCL`, which
        // refuses to go through a link that dangles.
        let probe = open(layout.link.path, O_WRONLY | O_CREAT, 0o600)
        XCTAssertGreaterThanOrEqual(probe, 0)
        close(probe)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.kernel.path),
                      "the arrangement is wrong: the kernel did not make p/t.json")
        XCTAssertEqual(try? Data(contentsOf: layout.letters), Data([2, 2]),
                       "the arrangement is wrong: the kernel changed the letters' file")
        try FileManager.default.removeItem(at: layout.kernel)

        let landed = PrivateFile.write(Data([9]), to: layout.link, destination: .whatItLeadsTo)

        XCTAssertEqual(try? Data(contentsOf: layout.letters), Data([2, 2]),
                       "the bytes went to the place only the letters of the link reach")
        XCTAssertFalse(isALink(layout.letters))
        XCTAssertTrue(isALink(layout.link), "the link stopped being one")
        XCTAssertEqual(try? Data(contentsOf: layout.kernel), landed ? Data([9]) : nil,
                       landed ? "the write answered true and the kernel's file does not hold it"
                              : "the write was refused and still made the kernel's file")
        try assertNothingElseWasLeft(layout, in: ["scratch": ["d", "name", "p", "t.json"],
                                                  "p": landed ? ["q", "t.json"] : ["q"]])
    }
}
