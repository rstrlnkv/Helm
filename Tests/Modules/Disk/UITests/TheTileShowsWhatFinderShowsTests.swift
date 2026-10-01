import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The owner's tile said «40,11 ГБ свободно» on a disk Finder called 90 GB
/// free. The engine tests hold the choice of key; these hold the **surfaces**:
/// the real engine, over the real transport, reading a fake port that carries
/// every reading the system gives, drawn into the tile and the Disk page — and
/// compared, pixel for pixel, with the same surface fed the figure it ought to
/// show. A second reference fed the wrong figure is the control: if the two
/// references drew alike, equality with one of them would prove nothing.
@MainActor
final class TheTileShowsWhatFinderShowsTests: XCTestCase {

    private let gb = 1_000_000_000

    private var boot: VolumeReadout {
        VolumeReadout(name: "Macintosh HD", path: "/", isBrowsable: true, total: 494 * gb,
                      importantFree: 90 * gb, plainFree: 39 * gb)
    }

    /// Measured on an exFAT image under `/Volumes` (see
    /// `FreeSpaceUnderOddInputsTests`): the important-usage key answers 0.
    private var exFAT: VolumeReadout {
        VolumeReadout(name: "Stick", path: "/Volumes/Stick", isBrowsable: true,
                      total: 64 * gb, importantFree: 0, plainFree: 60 * gb)
    }

    private func info(_ readout: VolumeReadout, free: Int) -> VolumeInfo {
        VolumeInfo(name: readout.name ?? "", path: readout.path,
                   totalBytes: readout.total ?? 0, freeBytes: free)
    }

    /// The tile over the real engine, and over a transport answering `volumes`.
    private func tile(engineOver volumes: [VolumeReadout], size: PanelWidgetSize,
                      appearance: NSAppearance.Name) async throws -> (Data, DiskEngine) {
        let transport = LocalTransport()
        let engine = DiskEngine(transport: transport, capacity: MountedCapacity(volumes))
        return (try await tilePixels(ModuleViewModel(transport: transport), size: size,
                                     appearance: appearance), engine)
    }

    private func tile(answering volumes: [VolumeInfo], size: PanelWidgetSize,
                      appearance: NSAppearance.Name) async throws -> Data {
        try await tilePixels(ModuleViewModel(transport: AnsweringTransport(volumes: volumes)),
                             size: size, appearance: appearance)
    }

    private func tilePixels(_ vm: ModuleViewModel, size: PanelWidgetSize,
                            appearance: NSAppearance.Name) async throws -> Data {
        let dvm = DiskViewModel.shared(vm: vm)
        await dvm.loadVolumes()
        XCTAssertFalse(dvm.volumes.isEmpty, "precondition: the volume list arrived")
        let widget = try XCTUnwrap(DiskDescriptor().panelWidget(size, vm))
        let mount = MountedRender(widget, width: 240, height: size == .tall ? 240 : 120,
                                  appearance: appearance)
        defer { mount.drop() }
        mount.settle(30)
        return try XCTUnwrap(mount.pixels(), "the tile was not drawn")
    }

    // MARK: - The boot volume

    func testTheTileDrawsTheImportantUsageFigureAndUsedFromIt() async throws {
        for appearance in RenderedInk.bothAppearances {
            let (engineDrawn, engine) = try await tile(engineOver: [boot], size: .wide,
                                                       appearance: appearance)
            let right = try await tile(answering: [info(boot, free: 90 * gb)], size: .wide,
                                       appearance: appearance)
            let wrong = try await tile(answering: [info(boot, free: 39 * gb)], size: .wide,
                                       appearance: appearance)
            withExtendedLifetime(engine) {}
            let label = RenderedInk.label(of: appearance)
            XCTAssertNotEqual(right, wrong, "control (\(label)): 90 GB and 39 GB free drew alike")
            XCTAssertEqual(engineDrawn, right, """
                the tile in \(label) is not the tile for 90 GB free and 404 GB used: it draws a \
                figure other than Finder's.
                """)
            XCTAssertNotEqual(engineDrawn, wrong,
                              "the tile in \(label) draws the purgeable-blind 39 GB")
        }
    }

    func testTheDiskPageDrawsTheSameFigureAsTheTile() async throws {
        for appearance in RenderedInk.bothAppearances {
            let transport = LocalTransport()
            let engine = DiskEngine(transport: transport, capacity: MountedCapacity([boot]))
            let engineDrawn = try await pagePixels(ModuleViewModel(transport: transport),
                                                   appearance: appearance)
            let right = try await pagePixels(ModuleViewModel(transport: AnsweringTransport(
                volumes: [info(boot, free: 90 * gb)])), appearance: appearance)
            let wrong = try await pagePixels(ModuleViewModel(transport: AnsweringTransport(
                volumes: [info(boot, free: 39 * gb)])), appearance: appearance)
            withExtendedLifetime(engine) {}
            let label = RenderedInk.label(of: appearance)
            XCTAssertNotEqual(right, wrong, "control (\(label)): the page drew 90 and 39 GB alike")
            XCTAssertEqual(engineDrawn, right,
                           "the Disk page in \(label) does not draw 90 GB free, 404 / 494 GB used")
        }
    }

    private func pagePixels(_ vm: ModuleViewModel,
                            appearance: NSAppearance.Name) async throws -> Data {
        let dvm = DiskViewModel.shared(vm: vm)
        await dvm.loadVolumes()
        XCTAssertFalse(dvm.volumes.isEmpty, "precondition: the volume list arrived")
        let mount = mountedDiskPage(vm: vm, width: 900, height: 640, appearance: appearance)
        defer { mount.drop() }
        mount.settle(40)
        return try XCTUnwrap(mount.pixels(), "the page was not drawn")
    }

    // MARK: - An external disk

    /// The tall tile lists every other volume with its free space. An empty exFAT
    /// stick must not be drawn as having none, though the important-usage key
    /// answers 0 on that file system.
    func testTheTallTileDrawsAnExFATDisksFreeSpace() async throws {
        let appearance = NSAppearance.Name.aqua
        let (engineDrawn, engine) = try await tile(engineOver: [boot, exFAT], size: .tall,
                                                   appearance: appearance)
        let right = try await tile(answering: [info(boot, free: 90 * gb),
                                               info(exFAT, free: 60 * gb)],
                                   size: .tall, appearance: appearance)
        let zero = try await tile(answering: [info(boot, free: 90 * gb), info(exFAT, free: 0)],
                                  size: .tall, appearance: appearance)
        withExtendedLifetime(engine) {}
        XCTAssertNotEqual(right, zero, "control: 60 GB and zero free drew alike on the stick's row")
        XCTAssertEqual(engineDrawn, right, """
            the tall tile does not draw the empty exFAT stick as 60 GB free; it is the tile \
            for zero free: \(engineDrawn == zero).
            """)
    }
}

extension TheTileShowsWhatFinderShowsTests {

    /// A whole-volume scan saved before this build carries the old,
    /// purgeable-blind free figure. The page must not open on a pale wedge of
    /// 39 GB beside a tile that says 90: a restored scan is older than the list
    /// that arrives a moment later, so the wedge draws the list's figure.
    func testARestoredRingDrawsTheSameFreeSpaceAsTheTile() async throws {
        let root = scratchDirectory("disk-restored-free")
        let store = ScanStore(directory: scratchDirectory("disk-restored-free-store"))
        store.save(ScanResult(root: folder(root.path, bytes: 404 * gb,
                                           children: [folder(root.path + "/Files",
                                                             bytes: 404 * gb)]),
                              freeBytes: 39 * gb, filesScanned: 12, seconds: 1),
                   at: Date())
        let wire = AnsweringTransport(volumes: [VolumeInfo(name: "Macintosh HD", path: root.path,
                                                           totalBytes: 494 * gb,
                                                           freeBytes: 90 * gb)])
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire), store: store)
        for _ in 0..<1_000 where !dvm.restored || dvm.volumes.isEmpty { await Task.yield() }
        await settle()
        XCTAssertTrue(dvm.restored, "precondition: the saved ring is on screen")
        let wedge = try XCTUnwrap(dvm.segments.first(where: \.isFreeSpace),
                                  "precondition: a restored volume scan draws a free wedge")
        XCTAssertEqual(wedge.bytes, dvm.volumes.first?.freeBytes, """
            the restored ring's free wedge is \(wedge.bytes / gb) GB while the tile and the \
            volume card say \((dvm.volumes.first?.freeBytes ?? 0) / gb) GB for the same volume.
            """)
    }
}

private struct MountedCapacity: VolumeCapacityPort {
    let volumes: [VolumeReadout]
    init(_ volumes: [VolumeReadout]) { self.volumes = volumes }
    func mounted() -> [VolumeReadout] { volumes }
    func readout(at path: String) -> VolumeReadout? {
        volumes.filter { path.hasPrefix($0.path) }.max { $0.path.count < $1.path.count }
    }
}
