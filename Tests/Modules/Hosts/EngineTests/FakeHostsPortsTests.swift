import XCTest
import HelmRuntime
@testable import Module_Hosts_Engine

/// The fakes are the subject of this file, not the convenience another file
/// leans on.
///
/// A fake simpler than the port it stands for cannot fail the way the port can,
/// so every test built on it proves something narrower than it claims — and the
/// narrowing is invisible, because nothing anywhere is red. The fix is to
/// exercise each state here, once, where a capability that quietly stopped
/// working is a failure rather than an unused declaration nobody reads.
final class FakeHostsFileTests: XCTestCase {

    /// `nil` is two real states wearing one face: the file is not there, and
    /// the file is there and is not UTF-8. `SystemHostsFile` decodes strictly
    /// on purpose, so both arrive here — and the engine must not be able to
    /// tell either of them from an empty file by accident.
    func testAFileThatCannotBeReadIsNotAnEmptyFile() {
        XCTAssertNil(FakeHostsFile(nil).read())
        XCTAssertEqual(FakeHostsFile("").read(), "")
    }

    /// `/etc/hosts` is a file any admin program may rewrite, and a VPN client
    /// or an installer doing exactly that while a page is open is an ordinary
    /// afternoon, not a contrived state.
    func testTheFileCanChangeUnderTheApp() {
        let file = FakeHostsFile("127.0.0.1\tlocalhost\n")
        file.changeUnderTheApp(to: "10.0.0.1\tbox\n")
        XCTAssertEqual(file.read(), "10.0.0.1\tbox\n")
    }

    /// And it can stop being readable at all while the app holds it — the file
    /// removed, or rewritten by something that does not write UTF-8.
    func testTheFileCanStopBeingReadableWhileTheAppHoldsIt() {
        let file = FakeHostsFile("127.0.0.1\tlocalhost\n")
        file.changeUnderTheApp(to: nil)
        XCTAssertNil(file.read())
    }
}

final class FakePrivilegedTests: XCTestCase {

    private let text = "10.0.0.1\tbox.local\n"

    /// The command the engine will actually send — built here rather than
    /// spelled by hand, because that is what ties the fake's reading of the
    /// shell sentence to `HostsWrite`'s writing of it. The two are one name
    /// across a boundary otherwise, and only one side would ever be changed.
    private func realCommand(for text: String) throws -> String {
        try XCTUnwrap(HostsWrite.command(base64: HostsWrite.encode(text)))
    }

    /// Succeeding means the file changed. A fake that answers `.done` without
    /// touching anything is the *lie* below, and the two must not be the same
    /// object in a different mood.
    func testSucceedingPutsTheRealCommandsPayloadInTheFile() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.succeed, writingTo: file)
        XCTAssertEqual(privileged.run(try realCommand(for: text)), .done)
        XCTAssertEqual(file.read(), text)
    }

    /// A command whose payload this fake cannot find is a refusal, never a
    /// silent success: a fake that shrugged and answered `.done` would report
    /// the drift between it and `HostsWrite` as a passing test.
    func testACommandWithNoPayloadIsRefusedRatherThanShruggedAt() {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.succeed, writingTo: file)
        XCTAssertEqual(privileged.run("/usr/bin/true"), .failed(1))
        XCTAssertEqual(file.read(), "127.0.0.1\tlocalhost\n")
    }

    /// The *common* answer to a password dialog. Not an edge case.
    func testDecliningLeavesTheFileAlone() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.decline, writingTo: file)
        XCTAssertEqual(privileged.run(try realCommand(for: text)), .declined)
        XCTAssertEqual(file.read(), "127.0.0.1\tlocalhost\n")
    }

    func testFailingCarriesItsOwnStatus() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.fail(3), writingTo: file)
        XCTAssertEqual(privileged.run(try realCommand(for: text)), .failed(3))
        XCTAssertEqual(file.read(), "127.0.0.1\tlocalhost\n")
    }

    /// Root reporting success over a file it never changed. Without this state
    /// the read-back verification in `applyHosts` has nothing behind it and its
    /// test proves an empty thing.
    func testALyingPortReportsSuccessOverAFileItNeverTouched() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.lie, writingTo: file)
        XCTAssertEqual(privileged.run(try realCommand(for: text)), .done)
        XCTAssertEqual(file.read(), "127.0.0.1\tlocalhost\n")
    }

    /// The second lie, and the one `HostsWrite` was written against: root
    /// reports success and the file is **empty**, not unchanged.
    ///
    /// `>` opens and truncates before the pipeline runs, and a pipeline's
    /// status is its last command's — so `/bin/echo` failing to run leaves
    /// `base64 -D` reading EOF, writing nothing and exiting 0. Measured on
    /// macOS 27, 2026-08-18; `HostsWrite`'s doc comment has all three readings.
    /// A fake that can only lie by leaving the file alone cannot represent the
    /// one that destroys it, which is the more expensive of the two.
    func testAPortCanReportSuccessOverAFileItEmptied() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.truncateAndLie, writingTo: file)
        XCTAssertEqual(privileged.run(try realCommand(for: text)), .done)
        XCTAssertEqual(file.read(), "", "the file was meant to be emptied, not left alone")
    }

    /// Whether root was asked at all is the assertion for every refusal that is
    /// supposed to happen *before* the dialog.
    func testEveryCommandIsRecordedInOrder() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.succeed, writingTo: file)
        _ = privileged.run(try realCommand(for: "a\n"))
        _ = privileged.run(try realCommand(for: "b\n"))
        XCTAssertEqual(privileged.commands.count, 2)
        XCTAssertNotEqual(privileged.commands.first, privileged.commands.last)
    }

    /// **A fake that finishes instantly makes a test of a wait vacuous.** The
    /// real dialog sits on screen for as long as the person takes — minutes, if
    /// they went to find their password — and everything the page says about
    /// being busy is about that interval. A fake that has always already
    /// answered lets a busy-state test pass with the busy state deleted.
    ///
    /// Note what this asserts: not that the answer arrives, but that it has
    /// *not* arrived while the dialog is up. The first is true of a port that
    /// never waited at all.
    func testTheDialogCanStillBeUpWhenTheCallerLooks() throws {
        let file = FakeHostsFile()
        let privileged = FakePrivileged(.succeed, writingTo: file)
        privileged.pausesUntilAnswered()
        let command = try realCommand(for: text)

        // A semaphore rather than an `XCTestExpectation` because this has to be
        // asked *twice* — once expecting nothing and once expecting the answer
        // — and an expectation may only be waited on once.
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = privileged.run(command)
            returned.signal()
        }

        XCTAssertTrue(privileged.waitForTheDialog(timeout: 5), "the call never reached the dialog")
        XCTAssertEqual(returned.wait(timeout: .now() + 0.2), .timedOut,
                       "the dialog answered itself, so no test of a wait means anything here")
        XCTAssertNotEqual(file.read(), text,
                          "the file changed while the person was still being asked")

        privileged.answerTheDialog()
        XCTAssertEqual(returned.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(file.read(), text)
    }
}

final class FakeBackupsTests: XCTestCase {

    func testASavedCopyComesBackAndIsListed() {
        let backups = FakeBackups()
        XCTAssertTrue(backups.save("127.0.0.1\tlocalhost\n", name: "2026-08-17T120000Z.hosts"))
        XCTAssertEqual(backups.list(), ["2026-08-17T120000Z.hosts"])
        XCTAssertEqual(backups.read("2026-08-17T120000Z.hosts"), "127.0.0.1\tlocalhost\n")
    }

    /// Twelve, for the reason `SystemBackupsTests` records: the storage under
    /// this is a `Dictionary`, whose key order is arbitrary but is not reliably
    /// *wrong* at three entries — so a three-name version of this test would go
    /// green with the sort deleted.
    func testTheListingIsOldestFirstWhateverOrderTheySavedIn() {
        let backups = FakeBackups()
        let names = (0..<12).map { String(format: "2026-08-17T12%04dZ.hosts", $0 * 137) }
        for name in names.shuffled() { XCTAssertTrue(backups.save("x", name: name)) }
        XCTAssertEqual(backups.list(), names)
    }

    /// A support folder that cannot be written to. The Apply that follows a
    /// backup nobody took believes it has something to go back to.
    func testAFolderThatCannotBeWrittenToIsRepresentable() {
        let backups = FakeBackups()
        backups.refusesToSave = true
        XCTAssertFalse(backups.save("x", name: "2026-08-17T120000Z.hosts"))
        XCTAssertTrue(backups.list().isEmpty)
    }

    func testDeletingTakesTheNamesGiven() {
        let backups = FakeBackups()
        _ = backups.save("a", name: "2026-08-17T120000Z.hosts")
        _ = backups.save("b", name: "2026-08-17T120100Z.hosts")
        backups.delete(["2026-08-17T120000Z.hosts"])
        XCTAssertEqual(backups.list(), ["2026-08-17T120100Z.hosts"])
    }

    /// The folder is a real folder on somebody's disk, so macOS and everybody
    /// else may leave things in it. `SystemBackups.list()` filters by suffix,
    /// so this one must too — a fake that can list a name the port never could
    /// is a fake free to plant a state that is not one, which is the same
    /// defect read from the other side.
    func testSomethingElseInTheFolderIsNeverListed() {
        let backups = FakeBackups()
        backups.plantForeignFile(".DS_Store")
        _ = backups.save("a", name: "2026-08-17T120000Z.hosts")
        XCTAssertEqual(backups.list(), ["2026-08-17T120000Z.hosts"])
    }

    /// Listed and still unreadable: the file was removed behind the app between
    /// the listing and the restore, or it is not UTF-8 and `SystemBackups.read`
    /// decodes as strictly as `SystemHostsFile` does. A restore has a branch
    /// for that, and without this state nothing is behind it.
    func testABackupCanBeListedAndStillNotReadBack() {
        let backups = FakeBackups()
        _ = backups.save("127.0.0.1\tlocalhost\n", name: "2026-08-17T120000Z.hosts")
        backups.makeUnreadable("2026-08-17T120000Z.hosts")
        XCTAssertEqual(backups.list(), ["2026-08-17T120000Z.hosts"])
        XCTAssertNil(backups.read("2026-08-17T120000Z.hosts"))
    }
}
