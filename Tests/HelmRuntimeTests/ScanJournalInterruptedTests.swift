import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What the journal does when the world does not cooperate: the app quits
/// between two of `record`'s three filesystem steps, or the clock the entries
/// are sorted by was wrong yesterday.
///
/// `ScanJournalTests` covers the happy rotation. These cover the states the
/// rotation can be *found* in, which is a different list.
final class ScanJournalInterruptedTests: XCTestCase {

    private var directory: URL!
    private var journal: ScanJournal!

    override func setUp() {
        super.setUp()
        directory = scratchDirectory("scan-journal-broken")
        journal = ScanJournal(directory: directory)
    }

    private func entry(_ bytes: Int, at seconds: TimeInterval = 0) -> ScanEntry {
        ScanEntry(at: Date(timeIntervalSince1970: 1_785_600_000 + seconds),
                  bytes: bytes, count: 1, seconds: 1.5, startedByHand: false)
    }

    private func item(_ path: String, _ bytes: Int) -> ScanItem {
        ScanItem(path: path, bytes: bytes)
    }

    // MARK: - A rotation interrupted between the move and the write

    /// `record` is three filesystem calls with no transaction around them:
    /// remove `previous`, move `current` onto `previous`, write the new
    /// `current`. Quit the app — or fill the disk — between the second and the
    /// third and `previous.json` is left on disk with no `current.json` beside
    /// it.
    ///
    /// `change` then reads the missing current as `?? []`, which is exactly the
    /// nil-versus-empty confusion `ScanReport`'s own doc forbids one layer up:
    /// "a scan whose root was refused … must not come back as 'we looked and it
    /// was clean'". Here the whole previous list is reported as **gone** — a
    /// page drawing that says the person freed every byte the last scan found,
    /// on the strength of a file that was never written.
    func testAnInterruptedRotationDoesNotReportTheWholeListAsFreed() {
        let found = [item("/a", 10), item("/b", 20)]
        journal.record(entry(30, at: 0), items: found, module: "disk")
        journal.record(entry(30, at: 60), items: found, module: "disk")

        // The crash: `current` was moved onto `previous`, the new one never landed.
        try? FileManager.default.removeItem(at: journal.listURL(module: "disk", .current))
        XCTAssertNotNil(journal.list(module: "disk", .previous),
                        "fixture: previous must survive the interruption")

        let change = journal.change(module: "disk")
        XCTAssertTrue(change.went.isEmpty,
                      "a current list that is not on disk was read as a scan that found nothing")
        XCTAssertEqual(change.wentBytes, 0)
    }

    /// The same hole, arrived at the other way: `current.json` is on disk but
    /// unreadable — a truncated write, a file a crash left half-flushed. `list`
    /// answers nil for a decode failure exactly as it does for a missing file,
    /// and `change` turns both into an empty scan.
    func testACorruptCurrentListIsNotAScanThatFoundNothing() throws {
        journal.record(entry(30, at: 0), items: [item("/a", 10)], module: "disk")
        journal.record(entry(30, at: 60), items: [item("/a", 10)], module: "disk")
        try Data([0x7b, 0x00, 0xff]).write(to: journal.listURL(module: "disk", .current))

        let change = journal.change(module: "disk")
        XCTAssertTrue(change.went.isEmpty,
                      "an unreadable current list was reported as everything having gone")
    }

    // MARK: - The entry the journal was asked to keep

    /// A Mac whose clock was a day fast yesterday leaves the journal full of
    /// entries stamped in the future. The clock is corrected; the next scan
    /// runs; its entry is the oldest of thirty-one and `prefix(30)` drops it.
    ///
    /// The two halves of `record` then disagree about whether that scan
    /// happened: `current.json` was rotated and written — the page will draw a
    /// delta from it — while the row explaining where the delta came from is
    /// not there. `record` must not silently discard the one thing it was
    /// called to store.
    func testTheEntryJustRecordedIsNeverTheOneDropped() {
        for i in 0..<ScanJournal.limit {
            journal.record(entry(i, at: 86_400 + TimeInterval(i) * 60), items: [],
                           module: "disk")
        }
        let afterTheClockWasFixed = entry(999, at: 0)
        journal.record(afterTheClockWasFixed, items: [item("/a", 1)], module: "disk")

        XCTAssertNotNil(journal.list(module: "disk", .current),
                        "fixture: the list half of the record did happen")
        XCTAssertTrue(journal.entries(module: "disk").contains(afterTheClockWasFixed),
                      "the scan that just ran is missing from its own journal")
    }

    /// `Array.sort` is documented as **not guaranteed stable**, and `record`
    /// sorts by `at` alone. Thirty entries sharing a timestamp — a restored
    /// journal, a clock pinned by a bad NTP answer, a fixture — leave the cap
    /// with no defined answer about which of the thirty-one to drop, and the
    /// one it drops is the newest.
    ///
    /// Ties are not exotic here: `ScanEntry.at` is the only ordering key the
    /// type has, so any two scans that agree on it are indistinguishable to
    /// this code however far apart they really ran.
    func testAnEntryIsNotDroppedForTyingOnItsTimestamp() {
        for i in 0..<ScanJournal.limit {
            journal.record(entry(i, at: 0), items: [], module: "disk")
        }
        let newest = entry(4242, at: 0)
        journal.record(newest, items: [], module: "disk")
        XCTAssertTrue(journal.entries(module: "disk").contains(newest),
                      "the newest of a set of tied timestamps was the one dropped")
    }
}
