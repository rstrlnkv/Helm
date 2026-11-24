import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The directory a store of the person's redirects itself into while XCTest is
/// loaded, and the sweep that keeps one per dead process from accumulating.
///
/// The judgement (which names belong to processes that have gone) is held
/// first, under the journal's spelling of it; the rest holds that two processes
/// get two directories, and that the sweep actually removes one.
///
/// The cases that make a directory use a base directory of their own, not
/// `$TMPDIR`, so nothing here can sweep the journal of a suite running beside
/// it.
final class TestScratchTests: XCTestCase {

    private let scratch = TestScratch(prefix: "helm-scratch-probe-")
    private var mine: Int32 { ProcessInfo.processInfo.processIdentifier }

    // MARK: - Which names belong to processes that have gone
    //
    // `ScanJournal` sends itself into `$TMPDIR` when XCTest is loaded, one
    // directory per process. The sweep is one `removeItem` and one decision,
    // and the decision is the whole risk: "gone" said of a running process
    // deletes the journal of a suite running beside this one. So the decision
    // is pure and tested here, and liveness is asked of the kernel, not of a
    // timestamp.

    private let myJournal = "helm-scan-journal-4242"
    private let theirs = "helm-scan-journal-777"

    func testAJournalWhoseProcessIsGoneIsSwept() {
        let swept = ScanJournal.abandonedTestJournals([myJournal, theirs]) { _ in false }
        XCTAssertEqual(Set(swept), [myJournal, theirs])
    }

    func testAJournalWhoseProcessIsRunningIsLeftAlone() {
        let swept = ScanJournal.abandonedTestJournals([myJournal, theirs]) { $0 == 777 }
        XCTAssertEqual(swept, [myJournal], "the journal of a live process was swept")
    }

    /// A suite running in parallel under another account: `kill` answers
    /// `EPERM`, which is "there, and not yours", still alive.
    func testNothingIsSweptWhenEveryProcessIsAlive() {
        XCTAssertTrue(ScanJournal.abandonedTestJournals([myJournal, theirs]) { _ in true }.isEmpty)
    }

    /// `$TMPDIR` is shared with everything else on the machine, and this walks
    /// all of it. Anything that is not a journal is not this function's to
    /// judge, whatever its name looks like.
    func testItOnlyEverJudgesItsOwnDirectories() {
        let strangers = ["com.apple.something", "helm-disk-stop-ABC", "helm-scan-journal",
                         "helm-scan-journal-", "helm-scan-journal-notanumber",
                         "helm-scan-journal-12-34", "TemporaryItems", ".DS_Store"]
        XCTAssertTrue(ScanJournal.abandonedTestJournals(strangers) { _ in false }.isEmpty,
                      "something that is not a per-process journal was marked for removal")
    }

    /// A pid is a number and a directory name is a string, so the string can say
    /// things a pid cannot be. Nothing here may be read as "sweep it".
    func testANonsensicalProcessNumberIsNotSwept() {
        let odd = ["helm-scan-journal-0", "helm-scan-journal--1",
                   "helm-scan-journal-99999999999999999999"]
        XCTAssertTrue(ScanJournal.abandonedTestJournals(odd) { _ in false }.isEmpty,
                      "a name that is not a real pid was swept: \(odd)")
    }

    // MARK: - One directory per process

    func testTheDirectoryIsThisProcessesOwn() {
        XCTAssertEqual(scratch.directory(in: scratchDirectory("scratch-base")).lastPathComponent,
                       "helm-scratch-probe-\(mine)")
    }

    /// Not one directory shared across runs, as the log has: two suites run
    /// side by side, and a store slot read by one process and written by
    /// another is the nondeterminism the redirection exists to end.
    func testItIsNotTheBaseItself() {
        let base = scratchDirectory("scratch-base")
        XCTAssertNotEqual(scratch.directory(in: base).path, base.path)
    }

    // MARK: - And an end to them

    func testItTakesBackWhatADeadProcessLeft() throws {
        let base = scratchDirectory("scratch-sweep")
        let abandoned = try made("helm-scratch-probe-4242", in: base)

        _ = scratch.directory(in: base, isAlive: { _ in false })

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path),
                       "a directory whose process has gone was kept, which is how 452 of them "
                       + "accumulate")
    }

    /// The suite running beside this one keeps its directory.
    func testItLeavesALivingProcessesDirectoryAlone() throws {
        let base = scratchDirectory("scratch-sweep")
        let live = try made("helm-scratch-probe-777", in: base)

        _ = scratch.directory(in: base, isAlive: { $0 == 777 })

        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path),
                      "the directory of a running process was swept")
    }

    /// `$TMPDIR` belongs to everything on the machine. A name not of this family
    /// is not the sweep's to judge, asked here of the removal, because a sweep
    /// that ignored the decision would pass every case above.
    func testItLeavesAStrangerAlone() throws {
        let base = scratchDirectory("scratch-sweep")
        let stranger = try made("com.apple.something", in: base)

        _ = scratch.directory(in: base, isAlive: { _ in false })

        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path),
                      "something belonging to nobody here was removed")
    }

    /// A directory the sweep is meant to see, asserted into existence: a test of
    /// a removal passes for free when there was nothing there to remove.
    private func made(_ name: String, in base: URL) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "the fixture is not on disk, so nothing below is a test")
        return url
    }
}
