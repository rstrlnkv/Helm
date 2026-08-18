import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Hosts_Engine

/// The system ports, pointed at a scratch directory.
///
/// **Nothing here reads `/etc/hosts` and nothing here raises a dialog.** Every
/// port that can be given a path is given one; `SystemPrivileged` is the one
/// that cannot be tested without asking somebody for their password, which is
/// why `PrivilegedRun.outcome(status:output:)` is a seam of its own.
final class SystemHostsFileTests: XCTestCase {

    func testTheFileIsReadAsText() throws {
        let root = scratchDirectory("hosts-read")
        let path = root.appendingPathComponent("hosts").path
        try Data("127.0.0.1\tlocalhost\n".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(SystemHostsFile(path: path).read(), "127.0.0.1\tlocalhost\n")
    }

    func testAFileThatIsNotThereReadsAsNil() {
        let root = scratchDirectory("hosts-missing")
        XCTAssertNil(SystemHostsFile(path: root.appendingPathComponent("nope").path).read())
    }

    /// **The strict decode, with a test under it.** The doc comment on
    /// `SystemHostsFile.read()` promises this, and a promise in prose with no
    /// test under it breaks silently — five modules had one.
    ///
    /// What is at stake is not tidiness. A lossy decode turns every byte that
    /// is not UTF-8 into U+FFFD, the page then shows those, and the next Apply
    /// sends them back over the person's file **as root** — destroying exactly
    /// the part Helm could not read, and destroying it with the one command in
    /// this app that cannot be undone without a backup. Unreadable has to reach
    /// the page as unreadable.
    func testAFileThatIsNotUTF8ReadsAsNilRatherThanAsReplacementCharacters() throws {
        let root = scratchDirectory("hosts-latin1")
        let path = root.appendingPathComponent("hosts").path
        // 0xFF cannot begin, continue or end a UTF-8 sequence.
        try Data([0x31, 0x32, 0x37, 0x09, 0xFF, 0xFE, 0x0A]).write(to: URL(fileURLWithPath: path))
        let read = SystemHostsFile(path: path).read()
        XCTAssertNil(read, "a lossy decode would answer \(read ?? "") and root would write it back")
    }
}

final class SystemBackupsTests: XCTestCase {

    func testACopyIsSavedListedAndReadBack() {
        let backups = SystemBackups(directory: scratchDirectory("hosts-backups"))
        XCTAssertTrue(backups.save("127.0.0.1\tlocalhost\n", name: "2026-08-17T120000Z.hosts"))
        XCTAssertEqual(backups.list(), ["2026-08-17T120000Z.hosts"])
        XCTAssertEqual(backups.read("2026-08-17T120000Z.hosts"), "127.0.0.1\tlocalhost\n")
    }

    /// The folder is somebody's, and the things in it that are not ours are
    /// theirs. `.DS_Store` is the one macOS leaves without being asked — and it
    /// sorts *before* every name `BackupName` generates, which is what makes it
    /// the useful stranger to test with rather than a name chosen for reading
    /// well.
    func testAForeignFileIsNeverListed() throws {
        let root = scratchDirectory("hosts-backups-foreign")
        let backups = SystemBackups(directory: root)
        XCTAssertTrue(backups.save("a", name: "2026-08-17T120000Z.hosts"))
        try Data().write(to: root.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(backups.list(), ["2026-08-17T120000Z.hosts"])
    }

    /// The listing is the history, so its order is load-bearing: `BackupName`
    /// prunes the front of it. `FileManager.contentsOfDirectory` promises no
    /// order at all, so the sort belongs to this port and not to its caller.
    ///
    /// **Twelve names, not three.** Three was written first and was *inert*:
    /// with `.sorted()` deleted the test stayed green, because a listing that
    /// short comes back in name order often enough. Measured 2026-08-18 on this
    /// volume — twelve names, created shuffled, 40 runs: 40 of 40 listings came
    /// back out of order. At twelve the chance of a sorted listing by accident
    /// is 1/12!, so a false green is not a thing that happens; a false *red*
    /// was never possible either way.
    func testTheListingIsOldestFirstWhateverOrderTheyWereWrittenIn() {
        let backups = SystemBackups(directory: scratchDirectory("hosts-backups-order"))
        let names = (0..<12).map { String(format: "2026-08-17T12%04dZ.hosts", $0 * 137) }
        for name in names.shuffled() { XCTAssertTrue(backups.save("x", name: name)) }
        // `names` is ascending by construction, so the expectation is not the
        // same `sorted` call the subject is being asked for.
        XCTAssertEqual(backups.list(), names)
    }

    func testDeletingTakesOnlyTheNamesGiven() {
        let backups = SystemBackups(directory: scratchDirectory("hosts-backups-delete"))
        XCTAssertTrue(backups.save("a", name: "2026-08-17T120000Z.hosts"))
        XCTAssertTrue(backups.save("b", name: "2026-08-17T120100Z.hosts"))
        backups.delete(["2026-08-17T120000Z.hosts"])
        XCTAssertEqual(backups.list(), ["2026-08-17T120100Z.hosts"])
    }

    /// Listed and unreadable is a state this port really reaches — the file
    /// removed between the listing and the restore, or bytes that are not
    /// UTF-8. Same strictness as the hosts file, and for the same reason: what
    /// comes out of here is a candidate to be written back as root.
    func testABackupThatIsNotUTF8ReadsAsNilThoughItIsStillListed() throws {
        let root = scratchDirectory("hosts-backups-latin1")
        let backups = SystemBackups(directory: root)
        try Data([0xFF, 0xFE]).write(to: root.appendingPathComponent("2026-08-17T120000Z.hosts"))
        XCTAssertEqual(backups.list(), ["2026-08-17T120000Z.hosts"])
        XCTAssertNil(backups.read("2026-08-17T120000Z.hosts"))
    }

    /// The names come from a listing this port made, so `read` and `delete`
    /// never build a path out of one that did not. A backup id reaches the
    /// engine from a payload, and `..` in it must not become a directory.
    ///
    /// **The stranger ends in `.hosts` on purpose.** The gate has two halves,
    /// and a name like `../notes.txt` is refused by the *suffix* half — so a
    /// test using one proves nothing about the half it was written for. This
    /// was measured: with the bare-name check deleted, the `.txt` version of
    /// this test stayed green.
    func testAnIdThatClimbsOutOfTheFolderReadsNothing() throws {
        let (backups, outside) = try folderWithSomebodyElsesFileBesideIt("read")
        XCTAssertNil(backups.read("../\(outside.lastPathComponent)"))
    }

    /// And it must not be *deleted* either. `delete` takes a list, so one bad
    /// name in it must not take a neighbour's file with the rest.
    func testAnIdThatClimbsOutOfTheFolderDeletesNothing() throws {
        let (backups, outside) = try folderWithSomebodyElsesFileBesideIt("delete")
        backups.delete(["../\(outside.lastPathComponent)"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    /// A backups folder, and one `..` away from it a file that is not Helm's.
    /// It is removed here rather than by `scratchDirectory`, which only drains
    /// what it made.
    private func folderWithSomebodyElsesFileBesideIt(_ label: String) throws
        -> (SystemBackups, URL) {
        let root = scratchDirectory("hosts-backups-climb-\(label)")
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("helm-hosts-not-yours-\(label).hosts")
        try Data("somebody else's file\n".utf8).write(to: outside)
        addTeardownBlock { try? FileManager.default.removeItem(at: outside) }
        return (SystemBackups(directory: root), outside)
    }
}
