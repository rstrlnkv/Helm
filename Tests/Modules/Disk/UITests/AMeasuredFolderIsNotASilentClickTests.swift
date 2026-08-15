import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmContract
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Clicking past the depth the walk reached starts a real walk of that folder,
/// and the screen said nothing at all about it.
///
/// **Measured by the survey at 810 pt:** while `measuring` is true the header is
/// pixel-for-pixel what it is at rest — no spinner, no Stop, nothing dimmed — and
/// a second click on the same wedge is swallowed by `guard !measuring`. So on a
/// volume scan, past the sixth level (which is `~/Library/…`, the part people
/// drill into) the primary gesture of this module looks exactly like a dead
/// click, with no way to stop what it started.
///
/// The flag was `@Published`, set and cleared correctly, and drawn by nothing —
/// what `periphery`'s `assignOnlyProperty` is for.
///
/// **And drawing Stop is not enough on its own.** `cancel()` read `live` alone to
/// decide whether there was a tree worth keeping, so a Stop pressed during a
/// measurement — `live` false, `measuring` true — fell through to the volume
/// picker and emptied the basket: the button would have thrown away the minute of
/// walking it was drawn beside.
@MainActor
final class AMeasuredFolderIsNotASilentClickTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    // MARK: - Fixtures

    private func result(_ root: DiskEntry, freeBytes: Int = 100) -> ScanResult {
        ScanResult(root: root, freeBytes: freeBytes, filesScanned: 10, seconds: 1)
    }

    /// A volume holding one folder the walk never went inside — which is what a
    /// folder with no children means once the walk has finished.
    private var walked: ScanResult {
        result(folder("/Volumes/Big", bytes: 900,
                      children: [folder("/Volumes/Big/Deep", bytes: 600)]))
    }

    private func model(_ transport: HeldTransport) -> DiskViewModel {
        DiskViewModel(vm: ModuleViewModel(transport: transport),
                      store: ScanStore(directory: scratchDirectory("disk-measuring")))
    }

    /// A finished scan of `walked`, with the measurement of `Deep` parked inside
    /// the transport — the state this whole file is about.
    private func measuring(_ transport: HeldTransport) async -> DiskViewModel {
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: walked)
        await settle()
        XCTAssertEqual(dvm.phase, .result, "precondition: the volume was drawn")
        XCTAssertFalse(dvm.live, "precondition: its walk has finished")

        dvm.drill(into: "/Volumes/Big/Deep")
        await untilParked(transport, count: 1)
        return dvm
    }

    // MARK: - The model says a walk is running

    func testAFolderBeingMeasuredIsAWalkTheHeaderCanDraw() async {
        let transport = HeldTransport()
        let dvm = await measuring(transport)

        XCTAssertTrue(dvm.walking, """
            a folder measurement is running — a real walk of that folder, started by the \
            primary gesture of this module — and nothing on the model says a walk is on, so \
            the header draws the resting state over it.
            """)

        transport.release(0, with: result(folder("/Volumes/Big/Deep", bytes: 600)))
        await settle()
        XCTAssertFalse(dvm.walking, "the spinner outlived the measurement it was about")
    }

    /// The other half: at rest, nothing claims a walk. A flag that is always true
    /// draws a spinner over a finished tree for ever.
    func testAFinishedTreeIsNotAWalk() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: walked)
        await settle()

        XCTAssertFalse(dvm.walking, "a finished tree reports a walk in flight")
    }

    /// And the walk the pair already drew still counts as one.
    func testTheVolumeWalkIsStillAWalk() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        XCTAssertTrue(dvm.live, "precondition: the volume walk is running")
        XCTAssertTrue(dvm.walking, "the state the spinner has always been drawn in stopped counting")

        transport.release(0, with: nil)
        await settle()
    }

    // MARK: - Stop keeps what it was pressed over

    /// Stop during a measurement stops the measurement. What it must not do is
    /// take the tree away: `cancel()` judged "is there anything worth keeping" by
    /// `live` alone, and during a measurement `live` is false.
    func testStopDuringAMeasurementKeepsTheTreeAndTheBasket() async {
        let transport = HeldTransport()
        let dvm = await measuring(transport)
        dvm.toggleBasket(folder("/Volumes/Big/Deep", bytes: 600))
        XCTAssertEqual(dvm.basket.count, 1, "precondition: something is marked for removal")

        dvm.cancel()
        await settle()

        XCTAssertEqual(dvm.phase, .result, """
            Stop pressed over a folder measurement put the module back on the volume picker, \
            so the minute of walking behind the ring went with a press on a button that says \
            it stops one folder.
            """)
        XCTAssertNotNil(dvm.result, "and the tree itself was dropped")
        XCTAssertEqual(dvm.basket.count, 1, "and the basket was emptied by it")
        XCTAssertFalse(dvm.walking, "and the spinner it was pressed under is still turning")
        XCTAssertFalse(dvm.stopped, """
            a measurement that was stopped marked the tree as a stopped walk, whose every \
            folder figure is a floor — the volume walk finished, and it is what the numbers \
            on screen come from.
            """)
    }

    /// A second click on the same wedge is swallowed while the first measurement
    /// runs, which is the reason the spinner has to exist at all — and it must
    /// still be swallowed after the fix.
    func testASecondClickStartsNoSecondMeasurement() async {
        let transport = HeldTransport()
        let dvm = await measuring(transport)

        dvm.drill(into: "/Volumes/Big/Deep")
        await settle()

        XCTAssertEqual(transport.parkedCount, 1, "a second walk of the same folder was started")
        transport.release(0, with: result(folder("/Volumes/Big/Deep", bytes: 600)))
        await settle()
    }

    // MARK: - And it is on the screen

    /// The flag has to be *drawn*, and the survey's whole finding is that it was
    /// not: `measuring` was published, correct, and read by nothing in the UI.
    ///
    /// Measured as the spinner AppKit really puts in the tree, in both
    /// appearances — and the live walk is read first, in the same instrument, so
    /// a render that finds no spinner anywhere fails as a broken measurement
    /// rather than passing as an absence.
    func testTheHeaderDrawsTheSpinnerForAMeasuredFolderAsWellAsForAWalk() async {
        for appearance in RenderedInk.bothAppearances {
            let transport = HeldTransport()
            let vm = ModuleViewModel(transport: transport)
            let dvm = DiskViewModel.shared(vm: vm)
            let mount = mountedDiskPage(vm: vm, width: 810, height: 600,
                                        appearance: appearance)
            renders.append(mount)

            Task { await dvm.scan(path: "/Volumes/Big") }
            await untilParked(transport, count: 1)
            transport.emitPartial(scan: transport.scanID(0), result: walked)
            await settle()
            mount.settle(20)
            XCTAssertTrue(Self.hasSpinner(mount.host), """
                the header draws no spinner during the walk it has always drawn one for \
                (\(RenderedInk.label(of: appearance))) — this reading is of something else, \
                and the assertion below would pass over any drawing at all.
                """)

            transport.release(0, with: walked)
            await settle()
            mount.settle(20)
            XCTAssertFalse(Self.hasSpinner(mount.host),
                           "precondition: the finished tree draws no spinner "
                           + "(\(RenderedInk.label(of: appearance)))")

            dvm.drill(into: "/Volumes/Big/Deep")
            await untilParked(transport, count: 1)
            mount.settle(20)

            XCTAssertTrue(Self.hasSpinner(mount.host), """
                a folder is being walked and the header is what it is at rest \
                (\(RenderedInk.label(of: appearance))): the click looks dead, the ring changes \
                under the person when it lands, and there is nothing to press to stop it.
                """)

            transport.release(0, with: result(folder("/Volumes/Big/Deep", bytes: 600)))
            await settle()
        }
    }

    /// What SwiftUI's `ProgressView().controlSize(.small)` becomes on macOS.
    private static func hasSpinner(_ host: NSView) -> Bool {
        var found = false
        func walk(_ view: NSView) {
            if view is NSProgressIndicator { found = true }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
    }
}
