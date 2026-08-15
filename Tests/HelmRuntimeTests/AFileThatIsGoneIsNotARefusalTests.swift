import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A path that went since the scan, reported as «macOS would not move this».
///
/// **Measured by the Disk survey:** `FileManager.trashItem` on a path that has
/// been deleted throws `NSFileNoSuchFileError` — code 4 — and `TrashFailure`
/// had no case for it, so it fell to `.systemRefused`, whose sentence is «macOS
/// would not move this. Show it in the Finder and try from there». That is an
/// instruction to go and look at a file that is not there.
///
/// `HelmTrash.remove`'s own comment says what should happen: "A path that was
/// already gone before any of this started is still a refusal with a reason —
/// the person is looking at a stale list and should be told so." The classifier
/// one file over had no such reason, so they were not told.
///
/// It is the ordinary refusal in Disk, not an exotic one: that module acts on a
/// tree up to 24 h old, and the folders it is interesting about — Caches,
/// DerivedData, Downloads — are exactly the ones that change under it.
final class AFileThatIsGoneIsNotARefusalTests: XCTestCase {

    // MARK: - The classifier

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
    func testAnUnknownCodeIsStillTheGeneralRefusal() {
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

    // MARK: - The batch

    /// End to end: the loop every deleting module goes through, handed a path
    /// that is not there.
    func testAGonePathComesBackFromTheBatchAsGone() {
        let directory = scratchDirectory("trash-missing")
        let gone = directory.appendingPathComponent("was-here.bin").path

        let result = HelmTrash.remove(allowed: [gone], module: "test")

        XCTAssertTrue(result.removed.isEmpty, "precondition: nothing was there to move")
        XCTAssertEqual(result.refused.map(\.path), [gone],
                       "a path that was already gone reached neither list")
        XCTAssertEqual(result.refused.first?.reason, .missing)
    }

}
