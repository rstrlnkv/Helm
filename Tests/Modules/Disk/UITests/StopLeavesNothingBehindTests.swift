import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// What Stop leaves on the screen when it lands on the volume picker.
///
/// The basket holds only entries from the tree on screen, and
/// `DiskSettingsPage` draws the basket bar outside the `switch dvm.phase`, so a
/// basket or a removal report kept past the picker would name a tree that is
/// gone. `StopKeepsWhatItMeasuredTests` holds a Stop mid-walk, which keeps both.
///
/// The work answers immediately: these tests are about what the view model
/// keeps across a transition; `DiskScanRaceTests` covers interleaving.
@MainActor
final class StopLeavesNothingBehindTests: XCTestCase {

    // MARK: - Fixtures

    private let big = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                 totalBytes: 1000, freeBytes: 100)
    private let small = VolumeInfo(name: "Small", path: "/Volumes/Small",
                                   totalBytes: 500, freeBytes: 50)

    private func work() -> AnsweringWork {
        let work = AnsweringWork(volumes: [big, small])
        let onBig = folder("/Volumes/Big", bytes: 900,
                           children: [folder("/Volumes/Big/Sub", bytes: 600)])
        let onSmall = folder("/Volumes/Small", bytes: 400,
                             children: [folder("/Volumes/Small/Other", bytes: 200)])
        work.answer("/Volumes/Big",
                         with: ScanResult(root: onBig, freeBytes: 100,
                                          filesScanned: 10, seconds: 1))
        work.answer("/Volumes/Small",
                         with: ScanResult(root: onSmall, freeBytes: 50,
                                          filesScanned: 5, seconds: 1))
        return work
    }

    private func model(_ work: AnsweringWork) -> DiskViewModel {
        // A store of its own: the module's real one is the person's last scan,
        // and a harness must leave nothing behind.
        let directory = scratchDirectory("disk-stop")
        return DiskViewModel(work: work,
                             store: ScanStore(directory: directory))
    }

    /// A scanned volume with one of its folders ticked into the basket.
    private func scannedWithABasketedFolder(_ dvm: DiskViewModel) async {
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        XCTAssertEqual(dvm.phase, .result, "precondition: the ring is on screen")
        dvm.toggleBasket(DiskEntry(name: "Sub", path: "/Volumes/Big/Sub", bytes: 600,
                                   isDirectory: true, noAccess: false, children: []))
        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"],
                       "precondition: the folder is in the basket")
    }

    // MARK: - The screen Stop draws

    /// The volume picker, with a basket bar under it holding folders from the
    /// scan that was just abandoned.
    func testStopDoesNotLeaveTheAbandonedScansFoldersInTheBasket() async {
        let dvm = model(work())
        await scannedWithABasketedFolder(dvm)

        dvm.cancel()                    // the Stop button

        XCTAssertEqual(dvm.phase, .start, "precondition: Stop shows the volume picker")
        XCTAssertTrue(dvm.basket.isEmpty,
                      "the volume picker is drawn over a basket bar listing "
                      + "\(dvm.basket.map(\.path)) — folders of a tree that is no longer "
                      + "on screen, above a Trash button")
    }

    /// The same screen from the other side: after a removal mid-scan the bar is
    /// a report, not a basket, and Stop must clear the report and its failures
    /// too, since the bar shows for `!basket.isEmpty || banner != nil`.
    func testStopDoesNotLeaveTheRemovalReportOverTheVolumePicker() async {
        let work = work()
        work.answerTrash(with: DiskRemoval(
            removed: ["/Volumes/Big/Sub"],
            refused: [HelmTrash.Refusal(path: "/Volumes/Big/Locked", reason: .noPermission)],
            freedBytes: 600))
        let dvm = model(work)
        await scannedWithABasketedFolder(dvm)
        await dvm.emptyBasket()
        XCTAssertNotNil(dvm.banner, "precondition: the bar is showing a removal report")
        XCTAssertFalse(dvm.failures.isEmpty, "precondition: with what macOS refused")

        dvm.cancel()                    // the Stop button

        XCTAssertFalse(dvm.showsRemovalBar,
                       "the volume picker is drawn over a removal report: "
                       + "banner \(String(describing: dvm.banner)), "
                       + "\(dvm.failures.count) failures")
    }

    /// The bar's condition lives on the view model, so the page and these tests
    /// read the same one.
    func testTheBarIsShownForABasketAndForAReport() async {
        let work = work()
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let dvm = model(work)
        XCTAssertFalse(dvm.showsRemovalBar, "nothing selected, nothing removed")
        await scannedWithABasketedFolder(dvm)
        XCTAssertTrue(dvm.showsRemovalBar, "something is marked for removal")
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.showsRemovalBar, "and the report of what happened stays up")
    }

    /// A basket kept across Stop and a new volume would credit its freed bytes
    /// to the free space of the volume now on screen, not the one they came off.
    /// Asserted as that volume's own free space, unchanged.
    ///
    /// Since Stop empties the basket, `emptyBasket` returns here before any
    /// arithmetic; `TrashIsNotFreedSpaceTests` holds the arithmetic itself.
    func testFreeingSpaceOnOneVolumeIsNotCreditedToAnother() async {
        let work = work()
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let dvm = model(work)
        await scannedWithABasketedFolder(dvm)

        dvm.cancel()
        await dvm.scan(path: "/Volumes/Small")
        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Small", "precondition: the small one")
        XCTAssertEqual(dvm.result?.freeBytes, 50,
                       "600 bytes freed on Big were added to Small's free space")
    }

    // MARK: - The doors that already close

    /// `newScan()` clears the basket.
    func testStartingOverClearsTheBasket() async {
        let dvm = model(work())
        await scannedWithABasketedFolder(dvm)

        dvm.newScan()

        XCTAssertTrue(dvm.basket.isEmpty)
    }

    /// And `rescan()` does too, because the tree it comes back with is a new
    /// measurement of the same place.
    func testScanningAgainClearsTheBasket() async {
        let dvm = model(work())
        await scannedWithABasketedFolder(dvm)

        await dvm.rescan()

        XCTAssertTrue(dvm.basket.isEmpty)
        XCTAssertEqual(dvm.phase, .result, "and it is still the same volume on screen")
    }

    /// The control: nothing above may be satisfied by a basket that never
    /// holds anything.
    func testTheBasketStillHoldsWhatWasTickedOnTheScreenItBelongsTo() async {
        let dvm = model(work())
        await scannedWithABasketedFolder(dvm)

        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"])
        XCTAssertEqual(dvm.basketBytes, 600)
    }
}
