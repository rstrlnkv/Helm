import XCTest
@testable import HelmRuntime

final class PermissionCheckTests: XCTestCase {
    /// Full Disk Access is detected by READING a protected file. Writing into
    /// ~/Library/Containers fails even when access is granted, which is how the
    /// check ended up reporting "denied" to a user who had granted it.
    func testFullDiskAccessFollowsReadabilityOfAProtectedFile() {
        XCTAssertEqual(PermissionCheck.state(canReadProtectedPath: false), .denied)
        XCTAssertEqual(PermissionCheck.state(canReadProtectedPath: true), .granted)
    }

    /// Classification follows the error macOS actually returned; guessing from
    /// the path alone told users to grant access they already had.
    func testPermissionErrorOnAProtectedPathMeansFullDiskAccess() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Containers/com.a.b",
                                errorCode: 513, hasSystemExtension: false),
            .needsFullDiskAccess)
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Group Containers/g.com.a.b",
                                errorCode: 513, hasSystemExtension: false),
            .needsFullDiskAccess)
    }

    /// Same protected path, but macOS refused for another reason — do not
    /// blame permissions.
    func testOtherErrorsOnProtectedPathsAreNotBlamedOnAccess() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Containers/com.a.b",
                                errorCode: 4, hasSystemExtension: false),
            .systemRefused)
    }

    func testActiveExtensionWinsForItsHostApp() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app",
                                errorCode: 513, hasSystemExtension: true),
            .activeSystemExtension)
    }

    func testPermissionErrorOutsideProtectedAreasReadsAsBusyOrLocked() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app",
                                errorCode: 513, hasSystemExtension: false),
            .noPermission)
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app",
                                errorCode: 0, hasSystemExtension: false),
            .systemRefused)
    }
}
