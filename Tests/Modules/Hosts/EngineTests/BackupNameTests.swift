import XCTest
@testable import Module_Hosts_Engine

final class BackupNameTests: XCTestCase {

    /// The clock is an argument, never `Date()`: a test that reads the wall
    /// clock is a test that fails at midnight in one time zone.
    private let noon = Date(timeIntervalSince1970: 1_755_000_000)

    func testANameSortsByTimeAsText() {
        let earlier = BackupName.name(at: noon)
        let later = BackupName.name(at: noon.addingTimeInterval(60))
        XCTAssertLessThan(earlier, later)
    }

    func testANameCarriesNoColonsOrSpaces() {
        let name = BackupName.name(at: noon)
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains(" "))
        XCTAssertTrue(name.hasSuffix(".hosts"))
    }

    /// **The name is read back as a moment, so a menu can say when rather than
    /// what the file is called.** The stamp is UTC and the reader is not, so
    /// this has to come back as a `Date` for `HelmDates` to write in the
    /// reader's own zone and language — «в 12:00» is a claim about the person's
    /// afternoon, and a page that simply chopped the digits out of the name
    /// would be making it in Greenwich.
    ///
    /// To the second, because that is all the name carries.
    func testANameIsReadBackAsTheMomentItWasWrittenFor() {
        let name = BackupName.name(at: noon)
        XCTAssertEqual(BackupName.date(of: name)?.timeIntervalSince1970,
                       noon.timeIntervalSince1970.rounded(.down))
    }

    /// And nothing else is: a file somebody else left in that folder is not a
    /// backup, and half a stamp is not a time.
    func testAnythingThatIsNotOneOfOursHasNoDate() {
        XCTAssertNil(BackupName.date(of: "notes.txt"))
        XCTAssertNil(BackupName.date(of: "hosts.hosts"))
        XCTAssertNil(BackupName.date(of: "2026-13-45T999999Z.hosts"))
        XCTAssertNil(BackupName.date(of: "../2026-08-18T120000Z.hosts"))
    }

    func testTheOldestGoWhenThereAreMoreThanTen() {
        let names = (0..<13).map { BackupName.name(at: noon.addingTimeInterval(Double($0) * 60)) }
        let doomed = BackupName.pruned(names, keeping: 10)
        XCTAssertEqual(doomed, Array(names.prefix(3)))
    }

    /// `FileManager.contentsOfDirectory` promises no order, so the sort inside
    /// `pruned` is what decides which names are the old ones. Every other test
    /// here hands them over already ascending, which makes that sort a no-op
    /// they cannot see: deleting it leaves them all green while the newest ten
    /// backups become the ones thrown away.
    func testTheOrderTheDirectoryHandsThemInDoesNotMatter() {
        let names = (0..<13).map { BackupName.name(at: noon.addingTimeInterval(Double($0) * 60)) }
        XCTAssertEqual(BackupName.pruned(names.reversed(), keeping: 10),
                       Array(names.prefix(3)))
    }

    func testNothingIsPrunedBelowTheLimit() {
        let names = (0..<4).map { BackupName.name(at: noon.addingTimeInterval(Double($0) * 60)) }
        XCTAssertEqual(BackupName.pruned(names, keeping: 10), [])
    }

    /// A directory holding something else entirely is not a reason to delete
    /// it: pruning only ever names files this module made.
    ///
    /// **The foreign name has to sort before ours, and the whole list has to be
    /// asserted.** With `somebody-elses-notes.txt` — the obvious choice — this
    /// test passes with the `hasSuffix` filter deleted: `s` sorts after `2`, so
    /// the stranger lands at the end of the list and `prefix` never reaches it.
    /// Finder's own leftover sorts before every name we make (`.` is 0x2E, `2`
    /// is 0x32) and is the first thing an unfiltered prune would delete. The
    /// count matters too: a stranger counted toward the limit costs one of ours
    /// its life, which asserting only `!contains` cannot see.
    func testAForeignFileIsNeverPruned() {
        let ours = (0..<12).map { BackupName.name(at: noon.addingTimeInterval(Double($0) * 60)) }
        let doomed = BackupName.pruned([".DS_Store"] + ours + ["somebody-elses-notes.txt"],
                                       keeping: 10)
        XCTAssertEqual(doomed, Array(ours.prefix(2)))
    }
}
