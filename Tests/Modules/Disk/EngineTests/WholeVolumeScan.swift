import HelmRuntime
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

        // Which side of a duplicate path wins is a race, so asserting on sizes
        // can pass by luck — it did. Assert on structure instead: the Data-side
        // copies must be absent from the tree, and no path may carry the
        // doubled slash that made the skip set inert.
        // A recursive descent, and not the stack of pending siblings this used to
        // be. `DiskNode` no longer stores its path, so checking one means building
        // it — and a stack would hold a composed string for every node still to
        // visit, which on a real volume is the whole tree. Recursing keeps the
        // live strings down to the depth of the walk.
        var doubled: String?
        var duplicate: String?
        func check(_ node: DiskNode, path: String) {
            if path.hasPrefix("//") { doubled = path }
            if path.hasPrefix("/System/Volumes/Data/Users")
                || path.hasPrefix("/System/Volumes/Data/Applications") {
                duplicate = path
            }
            for child in node.children {
                check(child, path: ScanPath.child(of: path, name: child.name))
            }
        }
        if let tree { check(tree, path: "/") }
        XCTAssertNil(doubled, "path join produced a doubled slash")
        XCTAssertNil(duplicate, "the Data volume was walked a second time")
    }
}
