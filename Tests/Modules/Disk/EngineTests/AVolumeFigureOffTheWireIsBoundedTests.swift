import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine

/// A `VolumeInfo` that did not come from the engine: decoded off the wire, or
/// built by hand. The engine bounds free space to the capacity before it builds
/// one, but a payload decoded straight from JSON never passes that bound, and
/// `usedBytes` is a subtraction — `0 - Int.min` traps, in release as in debug.
///
/// **Every assertion reads the stored fields before `usedBytes`.** Without the
/// bound the subtraction traps and takes the whole test process with it, which
/// is a result nobody can read; so a negative field fails here by name and the
/// case returns before the trapping read.
final class AVolumeFigureOffTheWireIsBoundedTests: XCTestCase {

    private func decoded(total: Int, free: Int) throws -> VolumeInfo {
        // Written as text, not encoded from a `VolumeInfo`: the encoder would
        // have to be handed a value the initialiser already bounded.
        let json = #"{"name":"Odd","path":"/Volumes/Odd","totalBytes":\#(total),"freeBytes":\#(free)}"#
        return try JSONDecoder().decode(VolumeInfo.self, from: Data(json.utf8))
    }

    private func assertBounded(_ volume: VolumeInfo, _ label: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard volume.totalBytes >= 0, volume.freeBytes >= 0 else {
            XCTFail("""
                \(label): kept total \(volume.totalBytes) and free \(volume.freeBytes); \
                a negative field reaches `usedBytes` unbounded, where `total - free` traps.
                """, file: file, line: line)
            return
        }
        XCTAssertGreaterThanOrEqual(volume.usedBytes, 0, label, file: file, line: line)
        XCTAssertLessThanOrEqual(volume.usedBytes, volume.totalBytes, label, file: file, line: line)
    }

    /// The extremes a writer can put on the wire, decoded.
    func testADecodedPayloadAtEveryExtremeIsBoundedBeforeUsedIsRead() throws {
        let cases: [(Int, Int)] = [
            (0, Int.min), (Int.min, Int.min), (Int.min, 5), (Int.max, Int.min),
            (-1, -1), (0, -1), (Int.max, Int.max), (5, Int.max),
        ]
        for (total, free) in cases {
            assertBounded(try decoded(total: total, free: free), "decoded total \(total) free \(free)")
        }
    }

    /// Negative figures read as nothing, not as their magnitude: a free space of
    /// `-1` is no free space, never a used share past the whole disk.
    func testANegativeDecodedFigureIsZero() throws {
        let volume = try decoded(total: 1_000, free: Int.min)
        XCTAssertEqual(volume.freeBytes, 0)
        XCTAssertEqual(volume.totalBytes, 1_000)
        guard volume.freeBytes >= 0 else { return }
        XCTAssertEqual(volume.usedBytes, 1_000)
        let noCapacity = try decoded(total: Int.min, free: 0)
        XCTAssertEqual(noCapacity.totalBytes, 0)
    }

    /// The same bound through the initialiser a view or a fake calls.
    func testTheInitialiserBoundsTheSameExtremes() {
        for (total, free) in [(0, Int.min), (Int.min, 1), (-5, -5)] {
            assertBounded(VolumeInfo(name: "Odd", path: "/Volumes/Odd",
                                     totalBytes: total, freeBytes: free),
                          "built total \(total) free \(free)")
        }
    }

    /// What a round trip of a bounded value gives back is the value: the hand
    /// written decoder reads every field the synthesised encoder writes.
    func testABoundedValueSurvivesTheWire() throws {
        let volume = VolumeInfo(name: "Macintosh HD", path: "/", totalBytes: 494, freeBytes: 90)
        let back = try JSONDecoder().decode(VolumeInfo.self,
                                            from: JSONEncoder().encode(volume))
        XCTAssertEqual(back, volume)
    }
}
