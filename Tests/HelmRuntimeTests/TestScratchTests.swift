import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The directory a store of the person's redirects itself into while XCTest is
/// loaded, and the sweep that keeps it from becoming 452 of them.
///
/// The *judgement* — which of these names belong to processes that have gone —
/// is held first, under the journal's own spelling of it. The rest holds the two
/// halves that judgement does not reach: that two processes are handed two
/// directories, and that the sweep beside them actually removes one. The 452
/// were never a wrong judgement; they were a judgement nobody called.
///
/// The five cases that make a directory run against a base directory of their
/// own rather than `$TMPDIR`; the other five judge a list of names
/// (`ScanJournal.abandonedTestJournals`) and take no directory. So nothing here
/// can sweep the journal of a suite running beside it.
final class TestScratchTests: XCTestCase {

    private let scratch = TestScratch(prefix: "helm-scratch-probe-")
    private var mine: Int32 { ProcessInfo.processInfo.processIdentifier }

    // MARK: - Which names belong to processes that have gone
    //
    // The judgement behind the one directory the suite used to leave behind.
    //
    // `ScanJournal` sends itself into `$TMPDIR` when XCTest is loaded, so a test
    // run cannot write into the person's real `Application Support`. That part
    // works and is load-bearing — an earlier attempt keyed on
    // `XCTestConfigurationFilePath`, which `swift test` does not set, and read
    // clean while the suite went on writing into their store. What it lacked was
    // an end: one directory per process, kept for ever, **452 of them** by the
    // time anyone counted.
    //
    // The sweep that ends it is one `removeItem` and one decision, and the
    // decision is the whole risk: saying "gone" about a process that is running
    // deletes the journal of a suite running beside this one, which on a build
    // machine is the ordinary case. So the decision is pure and tested here, and
    // liveness is asked of the kernel rather than of a timestamp.

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

    /// The case that costs somebody a debugging session rather than a file: a
    /// suite running in parallel under another account. `kill` answers `EPERM`
    /// for it, which is "there, and not yours" — still there.
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

    /// Sharing one directory across runs is the other shape available here — the
    /// log takes it — and it is wrong for a store: two suites run side by side on
    /// a build machine, a store holds one slot, and a slot read by one process
    /// and written by another is the nondeterminism the redirection exists to
    /// end.
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

    /// The case that costs somebody a debugging session rather than a directory:
    /// the suite running beside this one.
    func testItLeavesALivingProcessesDirectoryAlone() throws {
        let base = scratchDirectory("scratch-sweep")
        let live = try made("helm-scratch-probe-777", in: base)

        _ = scratch.directory(in: base, isAlive: { $0 == 777 })

        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path),
                      "the directory of a running process was swept")
    }

    /// `$TMPDIR` belongs to everything on the machine, and the sweep walks all of
    /// it. A name that is not this family's is not the sweep's to judge — asked
    /// here of the removal rather than of the decision, because a sweep that
    /// ignored the decision would pass every case above.
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
