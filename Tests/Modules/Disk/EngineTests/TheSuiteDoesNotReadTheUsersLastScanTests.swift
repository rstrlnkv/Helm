import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Disk_Engine

/// `~/Library/Application Support/Helm/Disk/last-scan.json` is the person's own
/// index of every file name on their volume, and a suite run reads it.
///
/// `ScanStore()` — the no-argument initializer, which is the one the app uses and
/// therefore the one every rendered page uses — takes its default from
/// `HelmSupport.directory` plus "Disk". That is the one place in `Sources/` that
/// names `.applicationSupportDirectory`, and it asks `TestProcess.isRunning` and
/// sends itself into `$TMPDIR` instead, as the comment at `TestProcess` says it
/// must — "asked by anything that would otherwise write into somebody's real
/// files". This file pins that the store's default never reaches the person's folder.
///
/// **What it costs, measured 2026-08-11.** Without a store parameter, Disk's
/// page has `restoreLastScan()` read that file and — when the saved scan is
/// less than a day old — draw the person's tree on a page the ratchets
/// measure. The file on this Mac was 8 MB, decoded on a detached task, and it
/// raced the harness's settle loop: the page-render harness read Disk at
/// **172 layers at 17:59:50 and 50 layers at 17:59:59**, same commit, same
/// machine, nine seconds apart.
/// The distinct off-ladder corner radius `1.25` — a `RoundedRectangle` whose 6 pt
/// corner is clamped by a bar 2.5 pt wide, so a fact about the *byte
/// distribution* of somebody's disk — was in the first reading and not the
/// second.
///
/// The 24-hour cache lifetime makes it worse rather than better, because it
/// makes the dependence intermittent on a scale nobody connects to a test: the
/// same reading went permanently quiet at 18:00:41 that afternoon, exactly
/// 86 400 seconds after the scan that wrote the file, and would have come back
/// the next time anybody opened Disk.
///
/// **And a read is not the whole of it.** `restoreLastScan` calls
/// `store.clear()` when the saved root no longer exists, which is a suite
/// deleting the person's cache — `AVanishedRootClearsTheCacheTests`
/// beside this one proves that branch really fires, so this is a hazard and not
/// a turn of phrase.
///
/// The seam is `HelmSupport.directory`, which `ScanStore.defaultDirectory` only
/// appends "Disk" to: a per-process directory under `$TMPDIR` when XCTest is loaded, swept the
/// way `TestScratchTests` describes, so the redirection does not trade
/// somebody's file for 452 directories of ours. `init(directory:)` is untouched
/// by that and must stay untouched — nine tests inject through it.
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

    /// Without this the guard below is a test of a rule nobody applies, which
    /// would pass in a process where XCTest is somehow absent — and pass by
    /// measuring nothing, since `TestProcess.isRunning` is the whole hinge.
    func testThisProcessIsResolvedAsATestRun() {
        XCTAssertTrue(TestProcess.isRunning,
                      "XCTest is not loaded, so nothing here is about a test process")
    }

    /// The sibling, so the assertion is about a *difference* between two stores
    /// in one tree rather than about an idea nobody has implemented. If this
    /// ever fails, the redirection has been lost everywhere and the guard below
    /// is no longer the odd one out.
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

    /// The fix must not reach the initializer the module's own tests inject
    /// through. Nine of them hand a scratch directory in, and a redirection that
    /// covered both would silently point all nine at one shared place.
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

    /// Pins `HelmSupport.path(home:)`'s spelling against the literal the store used
    /// before it went through `HelmSupport`: base + "Helm". The app branch of
    /// `HelmSupport.directory` (FileManager + "Helm") is held by reading, not by
    /// this test.
    func testTheAppPathIsTheOneEarlierBuildsWrote() {
        let fixture = "/Users/fixture"
        XCTAssertEqual(HelmSupport.path(home: fixture) + "/Disk/last-scan.json",
                       "/Users/fixture/Library/Application Support/Helm/Disk/last-scan.json")
    }
}
