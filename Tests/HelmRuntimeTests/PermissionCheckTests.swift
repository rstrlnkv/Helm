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

    // MARK: - The refusals that used to arrive as "macOS refused"

    /// A read-only volume is the one refusal the person can act on without
    /// knowing anything about permissions: it is a disk, and it is locked. It
    /// arrived as `systemRefused`, whose sentence names no cause and no step.
    func testAReadOnlyVolumeSaysSo() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Volumes/Backup/old.dmg",
                                errorCode: 642, hasSystemExtension: false),
            .readOnlyVolume)
    }

    /// A full disk refusing a *move to the Trash* looks absurd until you know
    /// the Trash is a folder on the same volume, so trashing writes. Naming it
    /// is the difference between "macOS refused" and "empty the Trash".
    func testAFullDiskSaysSo() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Movies/big.mov",
                                errorCode: 640, hasSystemExtension: false),
            .diskFull)
    }

    /// Everything else still lands in the general case rather than being
    /// guessed at — a wrong cause sends somebody to fix the wrong thing.
    func testAnUnknownCodeIsStillTheGeneralRefusal() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/thing",
                                errorCode: 99_999, hasSystemExtension: false),
            .systemRefused)
    }

    /// The extension check still wins: it is the only refusal whose fix is in
    /// another pane entirely.
    func testAnActiveExtensionStillWinsOverAReadOnlyVolume() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Volumes/Backup/Thing.app",
                                errorCode: 642, hasSystemExtension: true),
            .activeSystemExtension)
    }
}
