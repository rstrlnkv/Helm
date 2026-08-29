import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// The two halves of where the count lives.
///
/// **It outlives a launch** — that is the whole reason the file exists, and the
/// defect `DailyCount` could not fix.
///
/// **And it leaves nothing behind when nobody asked for a file.** Both wrong
/// answers were tried on the way here: keyed to the process id, every test in
/// the suite shared one ledger and a case asserting «one word counted» read
/// five; keyed per instance, a single run left 91 directories in `$TMPDIR`,
/// which is how this repository once accumulated 7621 of them.
final class TheLedgerOutlivesALaunchAndLeavesNothingTests: XCTestCase {

    func testACountWrittenByOneStoreIsReadByTheNext() {
        let directory = scratchDirectory("ledger-relaunch")
        let first = LedgerStore(directory: directory)
        first.record(characters: 6, on: Date())
        // The write is on the store's own queue; `totals` goes through the same
        // one, so asking is also waiting for it.
        XCTAssertEqual(first.totals(now: Date()).today.words, 1)

        // A second store over the same directory is the next launch.
        let second = LedgerStore(directory: directory)
        XCTAssertEqual(second.totals(now: Date()).today.words, 1,
                       "the count did not survive — this is the whole reason the file exists")
        XCTAssertEqual(second.totals(now: Date()).today.characters, 6)
    }

    /// A selection is several words, and the ledger has to hear that: counting
    /// a fixed sentence as one word understates the estimate by exactly the
    /// number of layout switches the person did not have to make.
    func testASentenceIsCountedAsItsWords() {
        let store = LedgerStore(directory: scratchDirectory("ledger-sentence"))
        store.record(words: 3, characters: 12, on: Date())
        let today = store.totals(now: Date()).today
        XCTAssertEqual(today.words, 3)
        XCTAssertEqual(today.characters, 12)
    }

    /// **Nobody named a directory, so nothing is written.** Outside the app the
    /// count is kept in memory and dies with the process — which is what makes
    /// a suite of these leave the disk exactly as it found it.
    func testWithNoDirectoryNamedNothingReachesTheDisk() throws {
        let before = try namesUnder(NSTemporaryDirectory())
        let store = LedgerStore()
        store.record(characters: 8, on: Date())
        XCTAssertEqual(store.totals(now: Date()).today.words, 1,
                       "the count still has to work — in memory is not «switched off»")

        XCTAssertEqual(try namesUnder(NSTemporaryDirectory()).subtracting(before), [],
                       "a ledger nobody asked to persist put something in the temporary directory")
    }

    /// And two of them do not share it, whatever else they share.
    func testTwoStoresWithNoDirectoryDoNotCountForEachOther() {
        let one = LedgerStore()
        let other = LedgerStore()
        one.record(characters: 5, on: Date())
        XCTAssertEqual(one.totals(now: Date()).today.words, 1)
        XCTAssertEqual(other.totals(now: Date()).today.words, 0,
                       "one store's count reached another — the suite would read its neighbours' words")
    }

    private func namesUnder(_ path: String) throws -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
    }
}
