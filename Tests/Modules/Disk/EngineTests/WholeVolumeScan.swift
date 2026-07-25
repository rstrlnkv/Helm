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
        for child in (tree?.children ?? []).sorted(by: { $0.bytes > $1.bytes }).prefix(8) {
            print(String(format: "  %-14@ %8.2f GB", child.name as NSString,
                         Double(child.bytes) / 1_073_741_824))
        }

        // The firmlink regression: /Users holds the user's data, and /System
        // must not be inflated by a second walk of the Data volume.
        let users = tree?.children.first { $0.name == "Users" }?.bytes ?? 0
        let system = tree?.children.first { $0.name == "System" }?.bytes ?? 0
        XCTAssertGreaterThan(users, system,
                             "Users lost its bytes to a duplicate walk of the Data volume")
    }
}
