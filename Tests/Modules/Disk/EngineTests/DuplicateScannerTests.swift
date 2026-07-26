import XCTest
@testable import Module_Disk_Engine

/// The scanner against a real directory: the logic is tested dry, so what is
/// left to prove is the walking and hashing — that identical bytes group,
/// different bytes do not, and a hard link is one file.
final class DuplicateScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ byte: UInt8, count: Int = 1_200_000) throws -> String {
        let url = root.appendingPathComponent(name)
        try Data(repeating: byte, count: count).write(to: url)
        return url.path
    }

    func testIdenticalFilesGroupAndDifferentOnesDoNot() throws {
        let a = try write("a.bin", 7)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        let b = try write("sub/b.bin", 7)        // same content, one level down
        _ = try write("c.bin", 9)                // same size, different content
        let groups = DuplicateScanner().find(under: root.path)
        XCTAssertEqual(groups?.count, 1)
        // The enumerator resolves /var to /private/var; compare by tail.
        let tails = Set((groups?.first?.paths ?? []).map { ($0 as NSString).lastPathComponent })
        XCTAssertEqual(tails, ["a.bin", "b.bin"])
        _ = (a, b)
        XCTAssertEqual(groups?.first?.wasted, 1_200_000)
    }

    func testAHardLinkIsNotADuplicate() throws {
        let a = try write("original.bin", 3)
        let linked = root.appendingPathComponent("link.bin").path
        try FileManager.default.linkItem(atPath: a, toPath: linked)
        let groups = DuplicateScanner().find(under: root.path)
        XCTAssertEqual(groups, [])
    }

    func testSmallFilesAreBelowTheFloor() throws {
        _ = try write("small1.bin", 1, count: 10_000)
        _ = try write("small2.bin", 1, count: 10_000)
        let groups = DuplicateScanner().find(under: root.path)
        XCTAssertEqual(groups, [])
    }

    func testCancelReturnsNilNotAPartialAnswer() throws {
        _ = try write("a.bin", 7)
        _ = try write("b.bin", 7)
        let scanner = DuplicateScanner()
        scanner.cancel()
        XCTAssertNil(scanner.find(under: root.path))
    }
}
