import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Duplicates_Engine

/// The scan must cost its slice, not its volume.
///
/// `DuplicateScanner.hash` streams a megabyte at a time so a video never becomes
/// a `Data` the size of the video — and for a long time that was true of the
/// slice and false of the process: `FileHandle.read` hands back an autoreleased
/// `Data`, `concurrentPerform` drains no pool per iteration, and so every slice
/// ever read stayed alive until the whole parallel block finished. A user
/// watched the app reach 48 GB on a folder of ordinary size.
///
/// This test reads far more than it may keep. The bound is deliberately loose —
/// a memory figure is noisy and this one has a scan's own structures inside it —
/// but the defect it guards against is not subtle: without the pool the
/// footprint tracks the bytes read, which is an order of magnitude past the
/// bound whatever else is going on.
final class HashingFootprintTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = scratchDirectory("hash-footprint")
    }

    func testTheScanCostsItsSliceRatherThanTheVolumeItReads() throws {
        // Pairs, so every byte is read twice: once for the prefix pass and once
        // for the full one. Distinct content per pair, or they would collapse
        // into one group and the second pass would have nothing to do.
        let pairs = 8
        let megabytesEach = 12
        for pair in 0..<pairs {
            var block = Data(count: 1024 * 1024)
            block[0] = UInt8(pair)
            let body = Data(repeating: UInt8(pair &+ 1), count: 1024 * 1024)
            var content = Data()
            content.append(block)
            for _ in 1..<megabytesEach { content.append(body) }
            for copy in 0..<2 {
                try content.write(to: folder.appendingPathComponent("f\(pair)-\(copy).bin"))
            }
        }
        let volumeRead = pairs * 2 * megabytesEach * 2   // both passes, both copies
        XCTAssertGreaterThan(volumeRead, 300, "the fixture has to read enough to show the defect")

        let before = try XCTUnwrap(MemoryFootprint.current())
        let groups = DuplicateScanner().find(under: folder.path, by: KeepRule(.standard))
        let after = try XCTUnwrap(MemoryFootprint.current())

        XCTAssertEqual(groups?.count, pairs, "each pair is a group, or the fixture is wrong")

        let grewMB = (after - before) / (1024 * 1024)
        XCTAssertLessThan(grewMB, 100,
                          "footprint grew \(grewMB) MB while reading about \(volumeRead) MB — "
                          + "the read loop is accumulating what it reads")
    }
}
