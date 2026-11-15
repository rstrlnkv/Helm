import Foundation
import XCTest
@testable import Module_Disk_Engine

/// The tile said 40 GB free on a disk Finder reported 90 GB free on: the engine
/// read `volumeAvailableCapacity`, which on APFS leaves purgeable space out.
/// These tests hold the choice between the readings, through a fake port that
/// carries every reading the real one does.
/// Past defect: fixed in commit 4ce355a9.
final class FreeSpaceIsWhatFinderShowsTests: XCTestCase {

    private let gb = 1_000_000_000

    /// The numbers measured on the owner's Mac for "/".
    private var measured: VolumeReadout {
        VolumeReadout(name: "Macintosh HD", path: "/", isBrowsable: true, total: 494 * gb,
                      importantFree: 90 * gb, plainFree: 39 * gb)
    }

    func testImportantUsageWinsOverThePlainReading() {
        XCTAssertEqual(measured.freeSpace, .important(90 * gb))
    }

    func testAnUnreadableImportantReadingFallsBackAndSaysSo() {
        var readout = measured
        readout.importantFree = nil
        XCTAssertEqual(readout.freeSpace, .fallback(39 * gb))
    }

    func testNeitherReadingIsNoFreeSpaceRatherThanZero() {
        var readout = measured
        readout.importantFree = nil
        readout.plainFree = nil
        XCTAssertNil(readout.freeSpace)
    }

    func testTheEngineReportsImportantUsageAndUsedFollowsIt() {
        let engine = DiskEngine(capacity: FakeCapacity(volumes: [measured]), trashing: neverTrashes)
        let volumes = engine.volumes()
        XCTAssertEqual(volumes.count, 1, "the fake's one volume must reach the list")
        XCTAssertEqual(volumes.first?.freeBytes, 90 * gb)
        XCTAssertEqual(volumes.first?.usedBytes, (494 - 90) * gb)
    }

    func testTheEngineUsesTheFallbackWhenTheKeyIsUnreadable() {
        var readout = measured
        readout.importantFree = nil
        let volumes = DiskEngine(capacity: FakeCapacity(volumes: [readout]), trashing: neverTrashes).volumes()
        XCTAssertEqual(volumes.first?.freeBytes, 39 * gb)
    }

    func testAVolumeWithNoCapacityAnswerIsNotListed() {
        var readout = measured
        readout.importantFree = nil
        readout.plainFree = nil
        XCTAssertTrue(DiskEngine(capacity: FakeCapacity(volumes: [readout]), trashing: neverTrashes).volumes().isEmpty)
    }
}

private struct FakeCapacity: VolumeCapacityPort {
    let volumes: [VolumeReadout]
    func mounted() -> [VolumeReadout] { volumes }
    func readout(at path: String) -> VolumeReadout? { volumes.first { $0.path == path } }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject { NSObject() }
}
