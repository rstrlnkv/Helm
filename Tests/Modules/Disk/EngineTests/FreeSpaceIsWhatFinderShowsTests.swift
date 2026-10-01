import Foundation
import XCTest
@testable import Module_Disk_Engine

/// The tile said 40 GB free on a disk Finder reported 90 GB free on: the engine
/// read `volumeAvailableCapacity`, which on APFS leaves purgeable space out.
/// These tests hold the choice between the readings, through a fake port that
/// carries every reading the real one does.
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

    func testAFigureOutsideTheCapacityIsBounded() {
        var readout = measured
        readout.importantFree = 900 * gb
        XCTAssertEqual(readout.freeSpace, .important(494 * gb))
        readout.importantFree = -5
        XCTAssertEqual(readout.freeSpace, .important(0))
    }

    func testTheEngineReportsImportantUsageAndUsedFollowsIt() {
        let engine = DiskEngine(capacity: FakeCapacity(volumes: [measured]))
        let volumes = engine.volumes()
        XCTAssertEqual(volumes.count, 1, "the fake's one volume must reach the list")
        XCTAssertEqual(volumes.first?.freeBytes, 90 * gb)
        XCTAssertEqual(volumes.first?.usedBytes, (494 - 90) * gb)
    }

    func testTheEngineUsesTheFallbackWhenTheKeyIsUnreadable() {
        var readout = measured
        readout.importantFree = nil
        let volumes = DiskEngine(capacity: FakeCapacity(volumes: [readout])).volumes()
        XCTAssertEqual(volumes.first?.freeBytes, 39 * gb)
    }

    func testAVolumeWithNoCapacityAnswerIsNotListed() {
        var readout = measured
        readout.importantFree = nil
        readout.plainFree = nil
        XCTAssertTrue(DiskEngine(capacity: FakeCapacity(volumes: [readout])).volumes().isEmpty)
    }

    /// The real port, on the boot volume: the key the fix depends on has to be
    /// one the system answers, or every read silently takes the fallback.
    func testTheSystemPortAnswersTheImportantUsageKeyOnTheBootVolume() throws {
        let readout = try XCTUnwrap(SystemVolumeCapacity().readout(at: "/"))
        let important = try XCTUnwrap(readout.importantFree, "important-usage key unreadable on /")
        let plain = try XCTUnwrap(readout.plainFree)
        XCTAssertGreaterThanOrEqual(important, plain, "purgeable space can only add to free")
        // Read the plain key from Foundation, not through the port: a port that
        // filled both fields from the old key would satisfy `>=` with equality.
        let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let finder = try XCTUnwrap(values.volumeAvailableCapacityForImportantUsage)
        let oldKey = try XCTUnwrap(try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity)
        XCTAssertLessThan(abs(important - Int(finder)), abs(important - oldKey) + 1,
                          "closer to the important-usage key than to the old one")
    }
}

private struct FakeCapacity: VolumeCapacityPort {
    let volumes: [VolumeReadout]
    func mounted() -> [VolumeReadout] { volumes }
    func readout(at path: String) -> VolumeReadout? { volumes.first { $0.path == path } }
}
