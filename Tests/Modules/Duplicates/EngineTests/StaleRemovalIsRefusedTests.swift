import XCTest
import HelmRuntime
@testable import Module_Duplicates_Engine

/// The engine reads the pair again before it moves anything, and a pair that
/// stopped matching is refused rather than trashed.
///
/// `DuplicateVerificationTests` proves the reading. This proves the engine acts
/// on it — that the verdict reaches the removal instead of being computed and
/// discarded, which is how a guard becomes decoration.
final class StaleRemovalIsRefusedTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Under the home, because `UserFileScope` refuses everything else and
        // the scope gate runs before the verification. In `/tmp` every case
        // below would be refused for the wrong reason and still look green.
        directory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("helm-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    @discardableResult
    private func write(_ name: String, _ contents: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    /// The case this whole path exists for: the search said identical, the file
    /// was edited afterwards, and nothing may be removed on the old reading.
    func testAChangedFileIsRefusedAndStaysOnDisk() async throws {
        let keep = try write("keep.bin", "original content")
        let remove = try write("remove.bin", "edited since the scan")

        let result = await DuplicatesEngine().trash([
            DuplicatePlan(remove: remove, keep: keep),
        ])

        XCTAssertTrue(result.removed.isEmpty, "a changed file was trashed")
        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan])
        XCTAssertTrue(FileManager.default.fileExists(atPath: remove),
                      "the file this refused to trash is gone anyway")
    }

    /// A pair that still matches goes through, so the guard is not simply
    /// refusing everything — a test that only proves refusals would pass on an
    /// engine that never removes anything at all.
    func testAnUnchangedPairIsStillRemoved() async throws {
        let keep = try write("keep.bin", "the same bytes")
        let remove = try write("remove.bin", "the same bytes")

        let result = await DuplicatesEngine().trash([
            DuplicatePlan(remove: remove, keep: keep),
        ])

        XCTAssertEqual(result.removed, [remove])
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: remove))
    }

    /// One bad pair in a batch costs that pair and nothing else. Refusing the
    /// whole batch would make one edited file undo a selection of fifty.
    func testOneStalePairDoesNotTakeTheBatchWithIt() async throws {
        let keep = try write("keep.bin", "shared")
        let good = try write("good.bin", "shared")
        let stale = try write("stale.bin", "different now")

        let result = await DuplicatesEngine().trash([
            DuplicatePlan(remove: good, keep: keep),
            DuplicatePlan(remove: stale, keep: keep),
        ])

        XCTAssertEqual(result.removed, [good])
        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale))
    }
}
