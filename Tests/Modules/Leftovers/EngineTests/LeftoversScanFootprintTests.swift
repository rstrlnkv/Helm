import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// What one login-items scan costs the process.
///
/// This scan is exactly the shape ARCHITECTURE.md § Memory names — «any loop
/// that reads file contents or asks Foundation for resource values in bulk needs
/// a pool inside it» — and it had no pool anywhere. Three loops qualify:
/// `~/Library/Preferences` is 542 plists on the machine this was written on and
/// asks `FileWeight.allocated` for every one; `plugins()` reads an
/// `Info.plist` per bundle *and* walks each bundle for its size; and
/// `WorkspaceInstalledApps` reads an `Info.plist` for every application in four
/// directories, two levels deep.
///
/// It runs against the real home directory, like `ScanBenchmark` and
/// `ScanFootprintTests` do, because the shape that matters is hundreds of small
/// reads and a handful of large bundle walks — a synthetic tree of the same size
/// costs more to build than the thing being measured. Read-only: the scan opens
/// files and never writes one.
///
///     HELM_BENCH=1 swift test --filter LeftoversScanFootprintTests
final class LeftoversScanFootprintTests: XCTestCase {

    func testAScanCostsItsItemsAndNotWhatItRead() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let scanner = LeftoversScanner(home: FileManager.default.homeDirectoryForCurrentUser,
                                       files: FileSystemLeftovers(),
                                       apps: WorkspaceInstalledApps(),
                                       extensions: ActiveExtensions())

        // The first scan pays for whatever Foundation warms up once — the
        // allocator keeps its tools out, which ARCHITECTURE.md § Memory measured
        // as a peak that falls to nothing by the third round. The reading that
        // answers this question is the second.
        _ = scanner.scan()
        let before = try XCTUnwrap(MemoryFootprint.current())
        let started = Date()
        let items = scanner.scan()
        let after = try XCTUnwrap(MemoryFootprint.current())

        let grew = after - before
        let perItem = items.isEmpty ? 0 : Double(grew) / Double(items.count)
        print(String(format: "scanned %d items in %.2f s: footprint grew %.1f MB (%.0f bytes/item)",
                     items.count, Date().timeIntervalSince(started),
                     Double(grew) / 1_048_576, perItem))

        try XCTSkipIf(items.count < 50, "only \(items.count) items here; nothing to measure")
        // **The threshold is between two measurements, not above one.** On this
        // machine — 566 items, three runs each — the same scan reads
        //
        //     no pool anywhere:      2,0 MB grown, 3647 bytes/item
        //     pool inside each loop: 0,8 MB grown, 1447 bytes/item
        //
        // so 2500 fails on the defect and passes with room for a home directory
        // that is not this one. A ceiling above both figures would have been a
        // check that cannot fail, which is what this file exists not to be.
        XCTAssertLessThan(perItem, 2_500,
                          "footprint is scaling with what the scan read rather than what it "
                          + "kept — check the autoreleasepool inside the scanner's loops")
    }
}
