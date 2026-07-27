import XCTest
@testable import HelmRuntime

/// The trash loop, which four modules used to keep their own copy of — and
/// three of which threw the reason away.
final class HelmTrashTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, bytes: Int = 16) throws -> String {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url.path
    }

    func testItTrashesWhatItIsGivenAndTotalsTheBytes() throws {
        let one = try file("one.txt", bytes: 32)
        let two = try file("two.txt", bytes: 32)

        let result = HelmTrash.remove(allowed: [one, two], module: "test")

        XCTAssertEqual(Set(result.removed), [one, two])
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertGreaterThan(result.freedBytes, 0, "allocated size, not zero")
        XCTAssertFalse(FileManager.default.fileExists(atPath: one))
    }

    /// The gate's refusals arrive with the batch. Reporting them separately is
    /// how a count and a list end up disagreeing on the same screen.
    func testOutOfScopePathsComeBackAsRefusalsNotSilence() throws {
        let allowed = try file("ok.txt")
        let result = HelmTrash.remove(allowed: [allowed],
                                      outOfScope: ["/System/Library/CoreServices"],
                                      module: "test")

        XCTAssertEqual(result.removed, [allowed])
        XCTAssertEqual(result.refused,
                       [.init(path: "/System/Library/CoreServices", reason: .outOfScope)])
        XCTAssertEqual(result.failed, ["/System/Library/CoreServices"])
    }

    /// A path that is not there is a refusal with a reason, not a crash and not
    /// a silent success.
    func testAMissingPathIsRefusedWithAReason() {
        let ghost = root.appendingPathComponent("never-existed").path
        let result = HelmTrash.remove(allowed: [ghost], module: "test")

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.refused.count, 1)
        XCTAssertEqual(result.refused.first?.path, ghost)
        XCTAssertEqual(result.freedBytes, 0)
    }

    /// The one-line summary picks the reason that applies to most of the batch,
    /// so "3 items could not be moved" can say why without listing three.
    func testPrincipalReasonIsTheCommonestOne() {
        let result = HelmTrash.Result(
            removed: [],
            refused: [.init(path: "/a", reason: .outOfScope),
                      .init(path: "/b", reason: .needsFullDiskAccess),
                      .init(path: "/c", reason: .needsFullDiskAccess)],
            freedBytes: 0)
        XCTAssertEqual(result.principalReason, .needsFullDiskAccess)
    }

    func testPrincipalReasonIsNilWhenNothingRefused() {
        XCTAssertNil(HelmTrash.Result(removed: ["/a"], refused: [], freedBytes: 1).principalReason)
    }
}
