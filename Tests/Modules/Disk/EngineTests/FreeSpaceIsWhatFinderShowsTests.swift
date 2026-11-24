import Foundation
import XCTest
@testable import Module_Disk_Engine

/// Free space is the figure Finder shows: `volumeAvailableCapacity` leaves
/// purgeable space out on APFS. These tests hold the choice between the
/// readings, through a fake port that carries every reading the real one does.
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

/// The move of a volume-only test: it must never be reached.
let neverTrashes: @Sendable (URL) throws -> Void = { _ in XCTFail("a volume test reached the move") }
