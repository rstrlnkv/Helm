import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Duplicates_Engine

/// The scanner against a real directory: the logic is tested dry, so what is
/// left to prove is the walking and hashing — that identical bytes group,
/// different bytes do not, and a hard link is one file.
final class DuplicateScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("dup")
    }

    /// Over the scanner's own floor by default, or the file is never a
    /// candidate — which is this module's number, not the harness's.
    private func write(_ name: String, _ byte: UInt8, count: Int = 1_200_000) throws -> String {
        try write(name, in: root, bytes: count, filler: byte).path
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
        // Asked of the filesystem, not written down: `wasted` promises what
        // removing the extra copy frees, which is what it occupies and not how
        // long it is. The two differ by the tail of a block.
        var seen: Set<UInt64> = []
        XCTAssertEqual(groups?.first?.wasted,
                       FileWeight.allocated(of: URL(fileURLWithPath: b), countingOnce: &seen))
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

extension DuplicateScannerTests {
    /// A file that cannot be read must leave the running, not join a group.
    ///
    /// The trap the pinning test exists for: hashing broke out of its read
    /// loop on failure and returned the digest of whatever it had — for a
    /// first-slice failure, the digest of nothing, which is the same digest
    /// for every unreadable file. Two same-size unreadable files grouped as
    /// duplicates and the sheet offered to trash content nobody had read.
    func testUnreadableFilesNeverGroupTogether() throws {
        let a = try write("locked-a.bin", 4)
        let b = try write("locked-b.bin", 5)   // same size, different content
        // Same size, and unreadable: if the hash answered for them anyway,
        // they would answer identically.
        for path in [a, b] {
            try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                                  ofItemAtPath: path)
        }
        defer {
            for path in [a, b] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                       ofItemAtPath: path)
            }
        }
        XCTAssertEqual(DuplicateScanner().find(under: root.path), [])
    }
}

/// Which copy the module offers to keep, through the scanner the engine
/// actually calls.
///
/// There are two assembly lines: `Duplicates.groups`, which the unit tests
/// drive, and `DuplicateScanner.find`, which the engine drives. `SurvivingCopy`
/// was wired into the first and not the second, so the page explained the
/// date-added rule in its tooltip while the app went on keeping whichever path
/// sorted first. The suite stayed green because the only test through the real
/// scanner compared the paths as a `Set`, where order cannot be observed.
///
/// So these assert the *first* path, and they run through `find`.
final class SurvivorThroughTheScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("survivor")
    }

    @discardableResult
    /// Over the scanner's own floor, or the file is never a candidate.
    private func write(_ relative: String, _ byte: UInt8) throws -> String {
        try write(relative, in: root, bytes: 1_200_000, filler: byte).path
    }

    /// The structural one, and the one that cannot pass by luck: whatever the
    /// rule decides, the scanner must decide it the same way. A value assertion
    /// could be satisfied by alphabet, depth or date agreeing by accident on
    /// one fixture; this cannot be satisfied by anything except the production
    /// line calling the rule.
    func testTheScannerOrdersEachGroupByTheSurvivorRule() throws {
        try write("zebra.bin", 7)
        try write("archive/2019/alpha.bin", 7)
        try write("middle/beta.bin", 7)

        let group = try XCTUnwrap(DuplicateScanner().find(under: root.path)?.first)
        let facts = group.paths.map { path -> FileFacts in
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
            return FileFacts(path: path, bytes: 1_200_000, fileID: 0,
                             added: values?.addedToDirectoryDate)
        }
        XCTAssertEqual(group.paths, SurvivingCopy.order(facts),
                       "the scanner the engine calls is not using the survivor rule")
    }

    /// And the case the rule exists for, when the volume records dates at all:
    /// the filed original outranks the copy whose path happens to sort first.
    func testTheOlderFiledCopySurvivesTheOneThatSortsFirst() throws {
        let original = try write("archive/2019/photo.bin", 9)
        Thread.sleep(forTimeInterval: 1.1)          // a distinguishable second
        let copy = try write("desktop-photo.bin", 9)

        let dates = [original, copy].map {
            try? URL(fileURLWithPath: $0)
                .resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
        }
        try XCTSkipIf(dates.contains(where: { $0 == nil || $0 == .some(nil) }),
                      "this volume does not record when a file was added")

        let group = try XCTUnwrap(DuplicateScanner().find(under: root.path)?.first)
        XCTAssertEqual((group.paths.first! as NSString).lastPathComponent, "photo.bin",
                       "the copy on top won because its path sorts first")
    }
}
