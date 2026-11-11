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
    /// blame permissions. Code 4 is «there is nothing there», which is a fact
    /// about the list rather than about the grant.
    func testOtherErrorsOnProtectedPathsAreNotBlamedOnAccess() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Containers/com.a.b",
                                errorCode: 4, hasSystemExtension: false),
            .missing)
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Library/Containers/com.a.b",
                                errorCode: 99_999, hasSystemExtension: false),
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

    // MARK: - A file that is gone (`AFileThatIsGoneIsNotARefusalTests` holds the batch half)

    func testTheCodeForAFileThatIsNotThereIsNamed() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/Downloads/installer.dmg",
                                errorCode: 4, hasSystemExtension: false),
            .missing,
            "`NSFileNoSuchFileError` reads as a refusal by macOS, so the screen sends somebody "
            + "to the Finder to look at a file that has gone")
    }

    /// The general refusal is still there for the codes nobody has classified —
    /// a reason invented for an unknown error sends somebody to fix the wrong
    /// thing.
    func testAnUnknownCodeIsStillTheGeneralRefusalBesideTheGoneCode() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Users/x/thing", errorCode: 99_999,
                                hasSystemExtension: false),
            .systemRefused)
    }

    /// **And it outranks the extension.** «Its system extension is still active —
    /// turn it off» is an instruction about a bundle, and this bundle is not on
    /// the disk: the extension check is a test of the path's *shape*, while this
    /// is what macOS answered.
    func testAMissingBundleIsGoneRatherThanBlamedOnItsExtension() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app",
                                errorCode: 4, hasSystemExtension: true),
            .missing)
    }

    /// The refusal that really is about an active extension keeps its own
    /// reason — this is the half that stops the case above from swallowing it.
    func testAnActiveExtensionStillOwnsItsOwnRefusal() {
        XCTAssertEqual(
            TrashFailure.reason(path: "/Applications/Thing.app",
                                errorCode: 513, hasSystemExtension: true),
            .activeSystemExtension)
    }
}
