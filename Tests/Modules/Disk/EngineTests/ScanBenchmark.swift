import XCTest
@testable import Module_Disk_Engine

/// Not a correctness test — a timing probe, skipped unless HELM_BENCH=1.
/// Kept in the suite so the scan speed can be re-measured after any change to
/// the walk (that is what caught the single-threaded version being unusable).
final class ScanBenchmark: XCTestCase {
    func testHomeDirectoryScanSpeed() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let start = Date()
        let tree = DiskScanner().scan(root: home)
        let elapsed = Date().timeIntervalSince(start)
        let gb = Double(tree?.bytes ?? 0) / 1_073_741_824
        print(String(format: "home: %.1f GB in %.2fs", gb, elapsed))
    }
}
