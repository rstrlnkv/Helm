import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Duplicates_Engine

/// "Wasted" and "freed" are the same number about the same files.
///
/// `DuplicateGroup.wasted` says it is "what deleting all but one copy frees",
/// and it was built from `.fileSizeKey` — the logical length — while
/// `HelmTrash.freedBytes` is built from what the file occupies. One screen, two
/// answers, and the second one arrives right after the person acts on the
/// first.
///
/// The pre-filter keeps the logical size on purpose: it is a *content* test —
/// two identical files always agree on length, and they need not agree on
/// blocks. Grouping by what they occupy would lose duplicates, which is a worse
/// failure than an imprecise total.
final class WastedBytesTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-wasted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ byte: UInt8) throws -> String {
        let url = root.appendingPathComponent(name)
        try Data(repeating: byte, count: 1_200_000).write(to: url)
        return url.path
    }

    func testWastedIsWhatRemovingTheExtrasWouldActuallyFree() throws {
        let first = try write("a.bin", 7)
        let second = try write("b.bin", 7)

        let group = try XCTUnwrap(DuplicateScanner().find(under: root.path)?.first)
        XCTAssertEqual(group.paths.count, 2)

        // What the filesystem says the second copy occupies — the figure the
        // removal will report.
        var seen: Set<UInt64> = []
        let occupied = FileWeight.allocated(of: URL(fileURLWithPath: second),
                                            countingOnce: &seen)
        XCTAssertEqual(group.wasted, occupied,
                       "the screen promises what deleting frees and quotes the logical length")
        _ = first
    }

    /// And the pre-filter still finds them: a duplicate must not be lost to a
    /// difference in blocks.
    func testTwoIdenticalFilesAreStillFound() throws {
        _ = try write("one.bin", 3)
        _ = try write("two.bin", 3)
        XCTAssertEqual(DuplicateScanner().find(under: root.path)?.count, 1)
    }
}
