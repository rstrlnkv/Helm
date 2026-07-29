import XCTest
@testable import Module_Disk_Engine

/// Joining a child onto "/" naively yields "//System", and every path below
/// inherits the doubled slash. That silently broke the firmlink skip set —
/// which only ever matters when scanning "/" — because "//System/Volumes/..."
/// never equals "/System/Volumes/...".
final class ScanPathTests: XCTestCase {
    func testChildOfRootHasOneSlash() {
        XCTAssertEqual(ScanPath.child(of: "/", name: "System"), "/System")
    }

    func testChildOfOrdinaryDirectory() {
        XCTAssertEqual(ScanPath.child(of: "/Users/me", name: "Downloads"),
                       "/Users/me/Downloads")
    }

    func testTrailingSlashIsNotDoubled() {
        XCTAssertEqual(ScanPath.child(of: "/Users/me/", name: "Downloads"),
                       "/Users/me/Downloads")
    }
}
