import XCTest
@testable import HelmRuntime

final class PermissionCheckTests: XCTestCase {
    func testFullDiskAccessIsRequiredWhenProtectedPathsAreUnreadable() {
        XCTAssertEqual(PermissionCheck.state(canReadProtectedPath: false), .denied)
        XCTAssertEqual(PermissionCheck.state(canReadProtectedPath: true), .granted)
    }

    /// The reason a path refused to move decides what we tell the user.
    func testTrashFailureReasons() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Containers/com.a.b", hasSystemExtension: false),
            .needsFullDiskAccess)
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Group Containers/g.com.a.b", hasSystemExtension: false),
            .needsFullDiskAccess)
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app", hasSystemExtension: true),
            .activeSystemExtension)
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app", hasSystemExtension: false),
            .unknown)
    }
}
