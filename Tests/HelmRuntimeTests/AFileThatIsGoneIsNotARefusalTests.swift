import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A path that went since the scan, reported as «macOS would not move this».
///
/// `FileManager.trashItem` on a deleted path throws `NSFileNoSuchFileError`
/// (code 4). Classified as `.systemRefused`, it would tell the person to look in
/// the Finder for a file that is not there; it is a refusal with its own
/// reason: the list is stale.
///
/// The ordinary refusal in Disk: that module acts on a tree up to 24 h old, and
/// Caches, DerivedData and Downloads change under it.
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
