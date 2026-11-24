import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// `~/Library/Application Support/Helm/Disk/last-scan.json` is the person's own
/// index of every file name on their volume, and a suite run must not reach it.
///
/// `ScanStore()`, the initializer the app and every rendered page use, takes its
/// default from `HelmSupport.directory` plus "Disk", and that directory answers a
/// per-process folder under `$TMPDIR` when `TestProcess.isRunning`. Reached, the
/// file would let `restoreLastScan()` draw the person's tree on a page the
/// ratchets measure, so a reading would depend on this Mac and on the 24-hour
/// age limit; and `restoreLastScan` calls `store.clear()` when the saved root has
/// gone (`AVanishedRootClearsTheCacheTests`), which would delete the person's cache.
///
/// `init(directory:)` keeps the directory it is handed: the module's tests inject
/// through it.
final class TheSuiteDoesNotReadTheUsersLastScanTests: XCTestCase {

    /// Spelled out rather than read off `ScanStore`, which is the thing on
    /// trial: taking the path from the subject makes every assertion below agree
    /// with whatever the subject decided, including "the person's own file".
    /// `TheSuiteDoesNotWriteTheUsersLogTests` states the same rule for the log.
    private var personsLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    // MARK: - The mechanism is on, and is applied next door

    /// `TestProcess.isRunning` is the whole hinge; without it the guard below
    /// would pass by measuring nothing.
    func testThisProcessIsResolvedAsATestRun() {
        XCTAssertTrue(TestProcess.isRunning,
                      "XCTest is not loaded, so nothing here is about a test process")
    }

    /// The sibling store is redirected too; if this fails, the redirection is
    /// lost everywhere, not only for `ScanStore`.
    func testTheScanJournalNextDoorIsAlreadyRedirected() {
        XCTAssertFalse(ScanJournal.defaultDirectory.path.hasPrefix(personsLibrary.path),
                       "ScanJournal writes into \(personsLibrary.path) under test")
    }

    // MARK: - The guard

    func testTheDefaultStoreIsNotThePersonsOwnFile() {
        let store = ScanStore()
        XCTAssertFalse(store.fileURL.path.hasPrefix(personsLibrary.path), """
            a test process resolves ScanStore() to \(store.fileURL.path), which is the person's \
            own last scan — an 8 MB index of their file names. Any test that renders Disk's page \
            reads it, so what the page draws is a fact about this Mac and about a 24-hour clock; \
            and restoreLastScan deletes it when the root it names has gone.
            """)
    }

    /// The redirection must not reach the initializer the module's tests inject
    /// through, or they would all share one folder.
    func testAStoreHandedADirectoryStillUsesIt() {
        let directory = scratchDirectory("store-seam")
        XCTAssertEqual(ScanStore(directory: directory).fileURL,
                       directory.appendingPathComponent("last-scan.json"))
    }

    /// The store follows the one folder every durable writer uses, so a test run
    /// gets that folder's own scratch and no second sweep exists for this store.
    /// The relative layout is pinned whole, so the subfolder name and the file name
    /// are both held against the real code.
    func testTheDefaultStoreSitsUnderHelmSupport() {
        let expected = HelmSupport.directory
            .appendingPathComponent("Disk/last-scan.json").standardizedFileURL.path
        XCTAssertEqual(ScanStore().fileURL.standardizedFileURL.path, expected)
    }

    /// Pins `HelmSupport.path(home:folder:)`'s spelling to the path saved scans
    /// already sit at. The app branch of `HelmSupport.directory` is held by
    /// reading, not by this test.
    func testTheAppPathIsTheOneEarlierBuildsWrote() {
        let fixture = "/Users/fixture"
        XCTAssertEqual(HelmSupport.path(home: fixture, folder: .helm) + "/Disk/last-scan.json",
                       "/Users/fixture/Library/Application Support/Helm/Disk/last-scan.json")
    }
}
