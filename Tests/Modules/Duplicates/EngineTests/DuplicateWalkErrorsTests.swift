import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// What the walk does when the filesystem says no.
///
/// The walk used the error-handler-less `enumerator` overload, and the report
/// against it said such an enumerator stops at the first error. Measured on
/// this OS it does not: an unreadable directory is walked past and the rest of
/// the tree still arrives. What it does do is walk past it *silently* — a whole
/// subtree missing from "what is duplicated", with the log printing a plausible
/// `walked N files` and no hint that the answer has a hole in it.
///
/// So both halves are pinned here: that the walk carries on (now by a handler
/// that says so, rather than by a default that could change under us), and that
/// what it could not read is counted rather than swallowed.
///
/// The existing fixtures chmod individual *files*, which the walk reads past
/// without the enumerator ever failing; only an unreadable *directory* reaches
/// this path.
final class DuplicateWalkErrorsTests: XCTestCase {
    private var root: URL!
    private var blocked: [URL] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-dup-walk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for url in blocked {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: url.path)
        }
        blocked = []
        try? FileManager.default.removeItem(at: root)
    }

    /// One copy of the pair per branch, and an unreadable directory in *both*
    /// branches. The enumerator is depth-first, so whichever branch it walks
    /// first it meets that branch's unreadable directory before it reaches the
    /// other copy: the pair can only be found by a walk that carries on past
    /// the error. Which branch comes first is a filesystem detail, and this
    /// does not depend on it.
    private func twoBranchesEachBehindAnUnreadableDirectory() throws {
        for (branch, byte) in [("one", UInt8(7)), ("two", UInt8(7))] {
            let directory = root.appendingPathComponent(branch)
            let wall = directory.appendingPathComponent("wall")
            try FileManager.default.createDirectory(at: wall, withIntermediateDirectories: true)
            try Data(repeating: byte, count: 1_200_000)
                .write(to: directory.appendingPathComponent("copy.bin"))
            try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                                  ofItemAtPath: wall.path)
            blocked.append(wall)
        }
    }

    func testAnUnreadableDirectoryDoesNotEndTheWalk() throws {
        try twoBranchesEachBehindAnUnreadableDirectory()

        let groups = try XCTUnwrap(DuplicateScanner().find(under: root.path))

        XCTAssertEqual(groups.count, 1, "the walk ended at the first unreadable directory")
        XCTAssertEqual(Set(groups[0].paths.map { ($0 as NSString).lastPathComponent }),
                       ["copy.bin"])
        XCTAssertEqual(groups[0].paths.count, 2)
    }

    /// And it says so. A folder skipped in silence is indistinguishable from a
    /// folder with nothing in it — the count is what tells a triage session
    /// which of the two "no duplicates" meant.
    func testTheWalkReportsThePathsItCouldNotRead() throws {
        try twoBranchesEachBehindAnUnreadableDirectory()

        let scanner = DuplicateScanner()
        _ = scanner.find(under: root.path)

        XCTAssertEqual(scanner.unreadablePaths, 2)
    }

    /// Nothing to report when there is nothing wrong: a clean folder must not
    /// come back looking partial.
    func testACleanWalkReportsNothingUnreadable() throws {
        try Data(repeating: 3, count: 1_200_000)
            .write(to: root.appendingPathComponent("a.bin"))
        let scanner = DuplicateScanner()
        _ = scanner.find(under: root.path)
        XCTAssertEqual(scanner.unreadablePaths, 0)
    }
}
