import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The journal and its scratch folder, and an entry to put in it; every journal
/// test class inherits them, in this file and in others. It holds no test of its own.
class ScanJournalRig: XCTestCase {

    var directory: URL!
    var journal: ScanJournal!

    override func setUp() {
        super.setUp()
        directory = scratchDirectory("scan-journal")
        journal = ScanJournal(directory: directory)
    }

    func entry(_ bytes: Int, _ count: Int, at seconds: TimeInterval = 0) -> ScanEntry {
        ScanEntry(at: Date(timeIntervalSince1970: 1_785_600_000 + seconds),
                  bytes: bytes, count: count, seconds: 1.5)
    }
}

final class ScanJournalTests: ScanJournalRig {
    func testAModuleThatNeverScannedHasNothing() {
        XCTAssertTrue(journal.entries(module: "duplicates").isEmpty)
        XCTAssertNil(journal.list(module: "duplicates", .current))
        XCTAssertNil(journal.list(module: "duplicates", .previous))
    }

    /// The current list becomes the previous one, and the one before that is
    /// gone — two lists is the whole storage budget.
    func testTheCurrentListBecomesThePrevious() {
        journal.record(entry(1, 1, at: 0), items: [ScanItem(path: "/first", bytes: 1)],
                       module: "disk")
        journal.record(entry(2, 1, at: 60), items: [ScanItem(path: "/second", bytes: 2)],
                       module: "disk")
        XCTAssertEqual(journal.list(module: "disk", .current)?.map(\.path), ["/second"])
        XCTAssertEqual(journal.list(module: "disk", .previous)?.map(\.path), ["/first"])

        journal.record(entry(3, 1, at: 120), items: [ScanItem(path: "/third", bytes: 3)],
                       module: "disk")
        XCTAssertEqual(journal.list(module: "disk", .current)?.map(\.path), ["/third"])
        XCTAssertEqual(journal.list(module: "disk", .previous)?.map(\.path), ["/second"])
    }

    /// Two modules do not share a journal.
    func testModulesAreSeparate() {
        journal.record(entry(1, 1), items: [ScanItem(path: "/a", bytes: 1)], module: "disk")
        XCTAssertTrue(journal.entries(module: "duplicates").isEmpty)
        XCTAssertNil(journal.list(module: "duplicates", .current))
    }

    /// These files name every path a scan found. `0600` inside `0700`, set on
    /// every write — `.atomic` replaces the file, so a mode set on the previous
    /// one says nothing about the new one, and a fresh atomic write in a process
    /// with the ordinary umask lands at `0644`.
    func testTheFilesArePrivate() throws {
        journal.record(entry(1, 1), items: [ScanItem(path: "/a", bytes: 1)], module: "disk")
        for url in [journal.entriesURL(module: "disk"),
                    journal.listURL(module: "disk", .current)] {
            XCTAssertEqual(try mode(of: url), 0o600, url.lastPathComponent)
        }
        XCTAssertEqual(try mode(of: journal.directory(module: "disk")), 0o700)
    }

    /// Written a second time, the mode still holds. This is the assertion that
    /// catches setting the mode once at creation and never again.
    func testTheModeSurvivesASecondWrite() throws {
        journal.record(entry(1, 1), items: [ScanItem(path: "/a", bytes: 1)], module: "disk")
        journal.record(entry(2, 1, at: 60), items: [ScanItem(path: "/b", bytes: 2)],
                       module: "disk")
        XCTAssertEqual(try mode(of: journal.listURL(module: "disk", .current)), 0o600)
    }

    /// A corrupt file costs the journal, never the launch.
    func testGarbageReadsAsEmpty() throws {
        journal.record(entry(1, 1), items: [], module: "disk")
        try Data([0x00, 0x01]).write(to: journal.entriesURL(module: "disk"))
        XCTAssertTrue(journal.entries(module: "disk").isEmpty)
    }

    /// The suite must not write into the developer's own journal. Proven rather
    /// than assumed: the same guard was once written keyed on a variable
    /// `swift test` does not set, and it read clean while the suite kept writing
    /// into the real feed.
    func testTheDefaultDirectoryIsNotApplicationSupportUnderTest() {
        let real = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Helm", isDirectory: true).path
        XCTAssertNotEqual(ScanJournal.defaultDirectory.path, real)
        XCTAssertFalse(ScanJournal.defaultDirectory.path.hasPrefix(real + "/"))
    }
}
