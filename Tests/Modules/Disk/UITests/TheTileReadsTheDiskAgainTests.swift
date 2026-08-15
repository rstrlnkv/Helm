import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The panel tile is the module's most-seen surface, and the two numbers on it
/// are the only ones in this app that cost nothing to be right about.
///
/// «This one costs a `statfs`, not a scan», says the tile's own doc, «and they
/// are the two numbers somebody opens a disk tool to see first». It asked for
/// them **once per launch**: `DiskWidget.task` was `if vm.volumes.isEmpty`, and
/// `DiskViewModel.shared(vm:)` lives as long as the app does. A menu-bar app
/// runs for weeks, so «free» was the figure from the first time the panel was
/// ever opened, and `CapacityBar`'s red-over-90 % rule could never fire on a
/// disk that filled up while Helm was running — which is the only way disks
/// fill up.
///
/// This is the family CLAUDE.md names: **a local flag standing in for a live
/// external fact, with no channel from the port that knows.** So both halves
/// are here. The tile re-reads whenever it is shown, and the model hears about
/// a disk arriving or leaving without anybody opening anything — the second is
/// also the cure for an external drive that is plugged in while the page is
/// open and never appears in the picker.
@MainActor
final class TheTileReadsTheDiskAgainTests: XCTestCase {

    private func boot(free: Int) -> VolumeInfo {
        VolumeInfo(name: "Macintosh HD", path: "/", totalBytes: 1_000_000_000_000,
                   freeBytes: free)
    }

    private func model(_ transport: AnsweringTransport) -> DiskViewModel {
        DiskViewModel(vm: ModuleViewModel(transport: transport),
                      store: ScanStore(directory: scratchDirectory("disk-tile")))
    }

    // MARK: - Shown again, read again

    /// The panel builds its widgets every time it is opened, so every opening is
    /// a free chance to be right — and the `isEmpty` condition spent it.
    ///
    /// Through the descriptor, which is how the panel really builds this, and so
    /// through `DiskViewModel.shared(vm:)` — the cache that outlives every panel
    /// opening and is the other half of why one read was ever enough.
    func testEveryShowingOfTheTileAsksTheDiskAgain() async throws {
        let transport = AnsweringTransport(volumes: [boot(free: 120_000_000_000)])
        let vm = ModuleViewModel(transport: transport)
        let dvm = DiskViewModel.shared(vm: vm)
        await dvm.loadVolumes()
        let atLaunch = transport.volumeReads
        XCTAssertEqual(atLaunch, 1, "precondition: the list was read once to begin with")

        for _ in 0..<3 {
            let tile = try XCTUnwrap(DiskDescriptor().panelWidget(.wide, vm))
            let mount = MountedRender(tile, width: 240, height: 120, appearance: .aqua)
            mount.settle(30)
            mount.drop()
        }

        XCTAssertEqual(transport.volumeReads, atLaunch + 3, """
            the tile was shown three times and asked \(transport.volumeReads - atLaunch) times. \
            It is drawing what the disk held the first time the panel was ever opened, and a \
            statfs is the cheapest read in the app.
            """)
    }

    /// And what it draws follows. A count of requests is not the claim — the
    /// claim is the figure on screen, and the reading it replaces was identical
    /// ink over an answer that had changed from 120 GB free to 3 GB.
    func testTheFigureOnTheTileFollowsTheDisk() async throws {
        for appearance in RenderedInk.bothAppearances {
            let transport = AnsweringTransport(volumes: [boot(free: 120_000_000_000)])
            let vm = ModuleViewModel(transport: transport)
            let dvm = DiskViewModel.shared(vm: vm)
            let tile = try XCTUnwrap(DiskDescriptor().panelWidget(.wide, vm))
            let mount = MountedRender(tile, width: 240, height: 120, appearance: appearance)
            defer { mount.drop() }
            mount.settle(30)
            let roomy = try XCTUnwrap(mount.settledInk(), "the tile was not drawn")
            XCTAssertGreaterThan(roomy, 0, "precondition: the tile drew a figure at all")

            transport.answerVolumes(with: [boot(free: 3_000_000_000)])
            await dvm.loadVolumes()
            mount.settle(30)

            XCTAssertNotEqual(try XCTUnwrap(mount.settledInk()), roomy, """
                the tile is drawn identically in \(RenderedInk.label(of: appearance)) for a disk \
                with 120 GB free and one with 3 GB, which is the figure people open this panel \
                to read.
                """)
        }
    }

    // MARK: - The channel from the port that knows

    /// A disk plugged in while Helm is running. Nothing in the module heard
    /// about one: `grep -rn didMountNotification Sources/` was empty, so the
    /// page re-asked on every appearance and the tile did not ask at all.
    func testADiskPluggedInIsNoticedWithoutAnybodyOpeningAnything() async {
        let transport = AnsweringTransport(volumes: [boot(free: 120_000_000_000)])
        let dvm = model(transport)
        await dvm.loadVolumes()
        XCTAssertEqual(dvm.volumes.count, 1, "precondition: one volume to begin with")

        transport.answerVolumes(with: [boot(free: 120_000_000_000),
                                       VolumeInfo(name: "Backup", path: "/Volumes/Backup",
                                                  totalBytes: 500, freeBytes: 200)])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didMountNotification,
                                                   object: nil)
        await untilVolumes(dvm, count: 2)

        XCTAssertEqual(dvm.volumes.map(\.name), ["Macintosh HD", "Backup"],
                       "a disk was mounted and no surface in this module noticed")
    }

    /// And ejected. The same channel, the other direction — a tile still
    /// offering the free space of a disk that is not there is the same wrong
    /// number read the other way round.
    func testADiskEjectedIsNoticedToo() async {
        let transport = AnsweringTransport(volumes: [boot(free: 120_000_000_000),
                                                     VolumeInfo(name: "Backup",
                                                                path: "/Volumes/Backup",
                                                                totalBytes: 500, freeBytes: 200)])
        let dvm = model(transport)
        await dvm.loadVolumes()
        XCTAssertEqual(dvm.volumes.count, 2, "precondition: two volumes to begin with")

        transport.answerVolumes(with: [boot(free: 120_000_000_000)])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didUnmountNotification,
                                                   object: nil)
        await untilVolumes(dvm, count: 1)

        XCTAssertEqual(dvm.volumes.map(\.name), ["Macintosh HD"],
                       "a disk was ejected and the module still offers it")
    }

    /// The observer belongs to the model, so a model nobody holds any more must
    /// not be woken by the next disk somebody plugs in — the state
    /// `ModuleUICache.dropWhenDisabled` puts this object in when the module is
    /// switched off.
    ///
    /// The wait for the object to really go is not politeness: `restoreLastScan`
    /// holds `self` strongly for as long as it runs, so a post sent the instant
    /// the last reference is dropped can land on a model that is still there —
    /// and this test would then be measuring that task's timing rather than the
    /// observer.
    ///
    /// **What it can fail on, exactly.** A capture that is not weak: the model
    /// would then be alive at the post, the `XCTAssertNil` above would fail
    /// first, and a disk read would follow. It cannot fail on `MountWatch.deinit`
    /// forgetting `removeObserver` — with a weak capture the leaked block
    /// resolves to nil and does nothing, so what is lost is one closure per
    /// dropped model and nothing a test can observe. Measured: deleting that
    /// loop leaves all five cases here green. The removal stays because the
    /// leak is real; this test is about the wake-up, not about the leak.
    func testAModelNobodyHoldsIsNotWokenByTheNextDisk() async {
        let transport = AnsweringTransport(volumes: [boot(free: 120_000_000_000)])
        var dvm: DiskViewModel? = model(transport)
        weak let ghost = dvm
        await dvm?.loadVolumes()
        let readsWhileAlive = transport.volumeReads
        dvm = nil
        for _ in 0..<1000 where ghost != nil { await Task.yield() }
        XCTAssertNil(ghost, "the view model outlived its last reference; nothing below is "
                     + "about the observer")

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didMountNotification,
                                                   object: nil)
        await settle()

        XCTAssertEqual(transport.volumeReads, readsWhileAlive,
                       "a dropped view model went on reading the disk when one was plugged in")
    }

    /// The condition rather than a fixed number of yields: the reload is a task
    /// of the model's own.
    private func untilVolumes(_ dvm: DiskViewModel, count: Int) async {
        for _ in 0..<1000 where dvm.volumes.count != count { await Task.yield() }
    }
}
