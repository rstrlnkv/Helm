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
