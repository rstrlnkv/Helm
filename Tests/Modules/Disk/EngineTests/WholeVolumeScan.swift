import XCTest
@testable import Module_Disk_Engine

/// The crash reproducer: scanning "/" walks synthetic volumes whose device
/// ids are negative. Behind HELM_BENCH because it takes real time.
final class WholeVolumeScan: XCTestCase {
    func testRootVolumeScanCompletes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let start = Date()
        let tree = DiskScanner().scan(root: "/")
        XCTAssertNotNil(tree)
        print(String(format: "root: %.1f GB in %.1fs",
                     Double(tree?.bytes ?? 0) / 1_073_741_824,
                     Date().timeIntervalSince(start)))
    }
}
