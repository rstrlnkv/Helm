import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Disk_Engine
import XCTest
@testable import Module_Disk_UI

/// **`DiskEntry.byteCeiling` is applied to every decode, the live wire's
/// included**, so it is a bound on what a volume may honestly report and not
/// only on a planted file. A volume reporting more than a pebibyte free (a
/// network or FUSE mount reporting an «unlimited» capacity) draws the tile from
/// the list and the ring's wedge from the scan, and the two then disagree.
///
/// **A documented gap (D4), skipped, not fixed.** The way to run a known gap is
/// `HELM_KNOWN_GAPS=1` (ARCHITECTURE.md § What makes a check), so the case skips
/// unless it is set, with the id in the reason, and keeps its reproduction below
/// the skip.
/// If the ceiling on the wire is decided to be intended, delete the case.
@MainActor
final class AVolumeOverAPebibyteTests: XCTestCase {

    func testAScanOfAVolumeOverThePebibyteDrawsWhatTheTileDraws() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1", "Known gap D4: the byte ceiling also applies to a live volume's free space")
        let pib = DiskEntry.byteCeiling
        let gb = 1_000_000_000
        let root = "/Volumes/Big"
        let wire = AnsweringTransport(volumes: [VolumeInfo(name: "Big", path: root,
                                                           totalBytes: 4 * pib, freeBytes: 2 * pib)])
        wire.answer(root, with: ScanResult(root: folder(root, bytes: 100 * gb,
                                                        children: [folder(root + "/Files", bytes: 100 * gb)]),
                                           freeBytes: 2 * pib, filesScanned: 1, seconds: 1))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire),
                                store: ScanStore(directory: scratchDirectory("disk-pebibyte-store")))
        await dvm.loadVolumes()
        await dvm.scan(path: root)
        let tile = try XCTUnwrap(dvm.volumes.first?.freeBytes, "precondition: the list was read")
        XCTAssertEqual(tile, 2 * pib, "precondition: the list keeps the volume's figure")
        let wedge = try XCTUnwrap(dvm.segments.first(where: \.isFreeSpace)?.bytes,
                                  "precondition: the scanned volume draws a free wedge")
        XCTAssertEqual(wedge, tile, """
            the ring draws \(wedge / pib) PiB free beside a tile that says \(tile / pib) PiB: the \
            scan's figure was cut to the ceiling on the wire
            """)
    }
}
