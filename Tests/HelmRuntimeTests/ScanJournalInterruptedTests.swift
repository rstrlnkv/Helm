import XCTest
@testable import HelmRuntime

/// What the journal does when the world does not cooperate: the app quits
/// between two of `record`'s three filesystem steps, or the clock the entries
/// are sorted by was wrong yesterday.
///
/// `ScanJournalTests` covers the happy rotation. These cover the states the
/// rotation can be *found* in, which is a different list.
final class ScanJournalInterruptedTests: ScanJournalRig {

    // MARK: - A rotation interrupted between the move and the write

    /// `record` is three filesystem calls with no transaction around them:
    /// remove `previous`, move `current` onto `previous`, write the new
    /// `current`. Quit the app — or fill the disk — between the second and the
    /// third and `previous.json` is left on disk with no `current.json` beside
    /// it.
    ///
    /// A missing current is not an empty scan (the nil-versus-empty rule
    /// `ScanReport` states): read as `[]`, the whole previous list would be
    /// reported as gone, every byte "freed" on the strength of a file that was
    /// never written.
    func testAnInterruptedRotationDoesNotReportTheWholeListAsFreed() {
        let found = [item("/a", 10), item("/b", 20)]
        journal.record(entry(30, 1, at: 0), items: found, module: "disk")
        journal.record(entry(30, 1, at: 60), items: found, module: "disk")

        // The crash: `current` was moved onto `previous`, the new one never landed.
        try? FileManager.default.removeItem(at: journal.listURL(module: "disk", .current))
        XCTAssertNotNil(journal.list(module: "disk", .previous),
                        "fixture: previous must survive the interruption")

        let change = journal.change(module: "disk")
        XCTAssertTrue(change.went.isEmpty,
                      "a current list that is not on disk was read as a scan that found nothing")
    }

    /// The same hole, arrived at the other way: `current.json` is on disk but
    /// unreadable — a truncated write, a file a crash left half-flushed. `list`
    /// answers nil for a decode failure exactly as it does for a missing file,
    /// and `change` turns both into an empty scan.
    func testACorruptCurrentListIsNotAScanThatFoundNothing() throws {
        journal.record(entry(30, 1, at: 0), items: [item("/a", 10)], module: "disk")
        journal.record(entry(30, 1, at: 60), items: [item("/a", 10)], module: "disk")
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
    /// `record` must not discard the one thing it was called to store, or
    /// `current.json` draws a delta whose row is not there.
    func testTheEntryJustRecordedIsNeverTheOneDropped() {
        for i in 0..<ScanJournal.limit {
            journal.record(entry(i, 1, at: 86_400 + TimeInterval(i) * 60), items: [],
                           module: "disk")
        }
        let afterTheClockWasFixed = entry(999, 1, at: 0)
        journal.record(afterTheClockWasFixed, items: [item("/a", 1)], module: "disk")

        XCTAssertNotNil(journal.list(module: "disk", .current),
                        "fixture: the list half of the record did happen")
        XCTAssertTrue(journal.entries(module: "disk").contains(afterTheClockWasFixed),
                      "the scan that just ran is missing from its own journal")
    }

    /// `Array.sort` is not guaranteed stable, and `ScanEntry.at` is the only
    /// ordering key. Entries sharing a timestamp (a restored journal, a clock
    /// pinned by a bad NTP answer) must not lose the newest to the cap.
    func testAnEntryIsNotDroppedForTyingOnItsTimestamp() {
        for i in 0..<ScanJournal.limit {
            journal.record(entry(i, 1, at: 0), items: [], module: "disk")
        }
        let newest = entry(4242, 1, at: 0)
        journal.record(newest, items: [], module: "disk")
        XCTAssertTrue(journal.entries(module: "disk").contains(newest),
                      "the newest of a set of tied timestamps was the one dropped")
    }
}
