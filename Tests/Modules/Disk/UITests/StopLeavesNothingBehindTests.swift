import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// What Stop leaves on the screen.
///
/// The ring is drawn from partial snapshots while the walk is still running, so
/// everything the result screen offers is available mid-scan — including ticking
/// folders into the basket. Stop then takes the ring away: `cancel()` moves the
/// scan name on, drops `live` and puts the phase back to `.start`, which is the
/// volume picker.
///
/// It does not touch the basket. Every other way out of a tree does —
/// `newScan()` and `rescan()` both clear it, and `newScan()` clears it *after*
/// calling `cancel()`, which is where the intent is legible — so the invariant
/// the module keeps everywhere else is that the basket only ever holds entries
/// from the tree currently on screen. Stop is the one door that breaks it, and
/// `DiskSettingsPage` draws the basket bar outside the `switch dvm.phase`:
///
/// ```swift
/// switch dvm.phase { … }
/// if !dvm.basket.isEmpty || dvm.banner != nil { … basketBar }
/// ```
///
/// So the screen is the volume picker with a basket bar under it, listing
/// folders from a scan that is gone, above a Trash button — and nothing on that
/// screen can show what those paths are part of.
///
/// The transport answers immediately: these tests are about what the view model
/// keeps across a transition, not about interleaving, which
/// `DiskScanRaceTests` already covers with a parked transport.
@MainActor
final class StopLeavesNothingBehindTests: XCTestCase {

    // MARK: - Fixtures

    private let big = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                 totalBytes: 1000, freeBytes: 100)
    private let small = VolumeInfo(name: "Small", path: "/Volumes/Small",
                                   totalBytes: 500, freeBytes: 50)

    private func transport() -> AnsweringTransport {
        let transport = AnsweringTransport(volumes: [big, small])
        let onBig = folder("/Volumes/Big", bytes: 900,
                           children: [folder("/Volumes/Big/Sub", bytes: 600)])
        let onSmall = folder("/Volumes/Small", bytes: 400,
                             children: [folder("/Volumes/Small/Other", bytes: 200)])
        transport.answer("/Volumes/Big",
                         with: ScanResult(root: onBig, freeBytes: 100,
                                          filesScanned: 10, seconds: 1))
        transport.answer("/Volumes/Small",
                         with: ScanResult(root: onSmall, freeBytes: 50,
                                          filesScanned: 5, seconds: 1))
        return transport
    }

    private func model(_ transport: AnsweringTransport) -> DiskViewModel {
        // A store of its own: the module's real one is the person's last scan,
        // and a harness must leave nothing behind.
        let directory = temporaryStoreDirectory("disk-stop")
        return DiskViewModel(vm: ModuleViewModel(transport: transport),
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
        let dvm = model(transport())
        await scannedWithABasketedFolder(dvm)

        dvm.cancel()                    // the Stop button

        XCTAssertEqual(dvm.phase, .start, "precondition: Stop shows the volume picker")
        XCTAssertTrue(dvm.basket.isEmpty,
                      "the volume picker is drawn over a basket bar listing "
                      + "\(dvm.basket.map(\.path)) — folders of a tree that is no longer "
                      + "on screen, above a Trash button")
    }

    /// The same screen from the other side. Trash something mid-scan and the
    /// bar stops being a basket and becomes a report — and the report is not
    /// the basket, so emptying the basket does not take it away. `cancel()`
    /// clears what it knows about and the bar's own condition is
    /// `!basket.isEmpty || banner != nil`, so Stop drew the removal report over
    /// the volume picker: a sentence about a tree that is no longer on screen,
    /// with the failures of a scan nobody can look at any more.
    func testStopDoesNotLeaveTheRemovalReportOverTheVolumePicker() async {
        let transport = transport()
        transport.answerTrash(with: DiskRemoval(
            removed: ["/Volumes/Big/Sub"],
            refused: [HelmTrash.Refusal(path: "/Volumes/Big/Locked", reason: .noPermission)],
            freedBytes: 600))
        let dvm = model(transport)
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

    /// And the bar the assertion above names is the one the page draws — the
    /// condition lives on the view model precisely so a test cannot pass
    /// against a copy of it that has drifted.
    func testTheBarIsShownForABasketAndForAReport() async {
        let transport = transport()
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let dvm = model(transport)
        XCTAssertFalse(dvm.showsRemovalBar, "nothing selected, nothing removed")
        await scannedWithABasketedFolder(dvm)
        XCTAssertTrue(dvm.showsRemovalBar, "something is marked for removal")
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.showsRemovalBar, "and the report of what happened stays up")
    }

    /// The arithmetic that state turns into.
    ///
    /// Stop, pick a different volume, and the basket bar is still there. Empty
    /// it and `emptyBasket` credits the freed bytes to `result.freeBytes` — the
    /// free space of the volume now on screen, which is not the volume those
    /// bytes came off. The ring's dim sector then reports a figure that belongs
    /// to no disk.
    ///
    /// Asserted as "the volume's own free space, unchanged", not as a
    /// difference: the free space shown for a volume is a fact about that
    /// volume.
    ///
    /// Both halves of that had to be fixed, and this test only ever sees the
    /// first: once Stop empties the basket there is nothing left to remove, so
    /// `emptyBasket` returns before it computes anything and this passes
    /// whatever the arithmetic says. `TrashIsNotFreedSpaceTests` pins the
    /// arithmetic itself, on one volume, where the removal actually runs.
    func testFreeingSpaceOnOneVolumeIsNotCreditedToAnother() async {
        let transport = transport()
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let dvm = model(transport)
        await scannedWithABasketedFolder(dvm)

        dvm.cancel()
        await dvm.scan(path: "/Volumes/Small")
        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Small", "precondition: the small one")
        XCTAssertEqual(dvm.result?.freeBytes, 50,
                       "600 bytes freed on Big were added to Small's free space")
    }

    // MARK: - The doors that already close

    /// `newScan()` clears the basket — after calling `cancel()`, which is where
    /// the missing line above is legible.
    func testStartingOverClearsTheBasket() async {
        let dvm = model(transport())
        await scannedWithABasketedFolder(dvm)

        dvm.newScan()

        XCTAssertTrue(dvm.basket.isEmpty)
    }

    /// And `rescan()` does too, because the tree it comes back with is a new
    /// measurement of the same place.
    func testScanningAgainClearsTheBasket() async {
        let dvm = model(transport())
        await scannedWithABasketedFolder(dvm)

        await dvm.rescan()

        XCTAssertTrue(dvm.basket.isEmpty)
        XCTAssertEqual(dvm.phase, .result, "and it is still the same volume on screen")
    }

    /// The control: nothing above may be satisfied by a basket that never
    /// holds anything.
    func testTheBasketStillHoldsWhatWasTickedOnTheScreenItBelongsTo() async {
        let dvm = model(transport())
        await scannedWithABasketedFolder(dvm)

        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"])
        XCTAssertEqual(dvm.basketBytes, 600)
    }
}
