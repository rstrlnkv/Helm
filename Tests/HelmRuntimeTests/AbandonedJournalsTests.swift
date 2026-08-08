import XCTest
@testable import HelmRuntime

/// The judgement behind the one directory the suite used to leave behind.
///
/// `ScanJournal` sends itself into `$TMPDIR` when XCTest is loaded, so a test
/// run cannot write into the person's real `Application Support`. That part
/// works and is load-bearing — an earlier attempt keyed on
/// `XCTestConfigurationFilePath`, which `swift test` does not set, and read
/// clean while the suite went on writing into their store. What it lacked was
/// an end: one directory per process, kept for ever, **452 of them** by the
/// time anyone counted.
///
/// The sweep that ends it is one `removeItem` and one decision, and the
/// decision is the whole risk: saying "gone" about a process that is running
/// deletes the journal of a suite running beside this one, which on a build
/// machine is the ordinary case. So the decision is pure and tested here, and
/// liveness is asked of the kernel rather than of a timestamp.
final class AbandonedJournalsTests: XCTestCase {

    private let mine = "helm-scan-journal-4242"
    private let theirs = "helm-scan-journal-777"

    func testAJournalWhoseProcessIsGoneIsSwept() {
        let swept = ScanJournal.abandonedTestJournals([mine, theirs]) { _ in false }
        XCTAssertEqual(Set(swept), [mine, theirs])
    }

    func testAJournalWhoseProcessIsRunningIsLeftAlone() {
        let swept = ScanJournal.abandonedTestJournals([mine, theirs]) { $0 == 777 }
        XCTAssertEqual(swept, [mine], "the journal of a live process was swept")
    }

    /// The case that costs somebody a debugging session rather than a file: a
    /// suite running in parallel under another account. `kill` answers `EPERM`
    /// for it, which is "there, and not yours" — still there.
    func testNothingIsSweptWhenEveryProcessIsAlive() {
        XCTAssertTrue(ScanJournal.abandonedTestJournals([mine, theirs]) { _ in true }.isEmpty)
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
}
