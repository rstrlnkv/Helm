import XCTest
import HelmRuntime
@testable import Module_Disk_Engine

/// Pins the autoreleasepool fix at `DiskScanner.swift`'s directory walk
/// (ARCHITECTURE.md § Memory: "`DiskScanner`'s directory walk had the same
/// defect one framework call further out ... at 1.5 M entries that was most
/// of what looked like the cost of the tree"). Nothing else in the suite
/// measures memory for this walk — `ScanBenchmark` pins its speed, this pins
/// its footprint.
///
/// Scans the real home directory, like `ScanBenchmark` does, because building
/// a synthetic tree of comparable size is itself the slow part (measured:
/// 200k `createFile` calls took under a minute but dwarfs the walk being
/// tested). Bytes-per-file is the number that would explode without the
/// pool — the hashing defect this mirrors went from single-digit MB to
/// tracking the volume read.
///
/// `HELM_BENCH=1 swift test --filter ScanFootprintTests`
final class ScanFootprintTests: XCTestCase {

    private final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _filesSeen = 0
        func record(_ n: Int) { lock.lock(); _filesSeen = n; lock.unlock() }
        var filesSeen: Int { lock.lock(); defer { lock.unlock() }; return _filesSeen }
    }

    func testHomeDirectoryScanCostsItsTreeNotItsVolume() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let box = ProgressBox()
        let before = try XCTUnwrap(MemoryFootprint.current())
        let tree = DiskScanner().scan(root: home, onProgress: { progress in
            box.record(progress.filesSeen)
        })
        let after = try XCTUnwrap(MemoryFootprint.current())

        XCTAssertNotNil(tree)
        let filesSeen = box.filesSeen
        let grewMB = Double(after - before) / 1_048_576
        let bytesPerFile = filesSeen > 0 ? Double(after - before) / Double(filesSeen) : 0
        print(String(format: "walked %d files: footprint grew %.1f MB (%.0f bytes/file)",
                     filesSeen, grewMB, bytesPerFile))

        // Loose on purpose — a real home directory varies machine to machine —
        // but the defect this guards against is not subtle: without the pool
        // the walk tracked bytes read, not bytes kept, and blew past this by
        // an order of magnitude on the incident that found it.
        if filesSeen > 10_000 {
            XCTAssertLessThan(bytesPerFile, 2_000,
                              "footprint is scaling with something other than the tree — "
                              + "check the autoreleasepool in DiskScanner's directory walk")
        }
    }
}
