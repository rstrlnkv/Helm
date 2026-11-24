import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Duplicates_Engine

/// What the walk does when the filesystem says no.
///
/// Both halves are pinned: the walk carries on past an unreadable directory,
/// and what it could not read is counted rather than swallowed — a subtree
/// skipped in silence leaves a plausible `walked N files` with a hole in it.
///
/// Only an unreadable *directory* reaches this path; a chmod'ed *file* is read
/// past without a directory being refused.
final class DuplicateWalkErrorsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("dup-walk")
    }

    /// Unreadable now, readable again before anything tries to delete it.
    ///
    /// The restore is a teardown block rather than a `tearDown`: teardown blocks
    /// run *before* `tearDown` and are unwound in reverse, so this one, registered
    /// after the scratch directory's, runs before that removal reaches a folder
    /// still at 0o000.
    private func wall(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("wall")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: url.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: url.path)
        return url
    }

    /// One copy of the pair per branch, and an unreadable directory in *both*
    /// branches. A walk that gave up at the first unreadable directory could
    /// lose the other copy: the pair can only be found by a walk that carries on
    /// past the error. Which branch is read first is not promised, and this
    /// does not depend on it.
    private func twoBranchesEachBehindAnUnreadableDirectory() throws {
        for (branch, byte) in [("one", UInt8(7)), ("two", UInt8(7))] {
            let directory = root.appendingPathComponent(branch)
            try write("\(branch)/copy.bin", in: root, bytes: 1_200_000, filler: byte)
            _ = try wall(in: directory)
        }
    }

    func testAnUnreadableDirectoryDoesNotEndTheWalk() throws {
        try twoBranchesEachBehindAnUnreadableDirectory()

        let groups = try XCTUnwrap(DuplicateScanner().find(under: root.path, by: KeepRule(.standard)))

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
        _ = scanner.find(under: root.path, by: KeepRule(.standard))

        XCTAssertEqual(scanner.unreadablePaths, 2)
    }

    /// Nothing to report when there is nothing wrong: a clean folder must not
    /// come back looking partial.
    func testACleanWalkReportsNothingUnreadable() throws {
        try Data(repeating: 3, count: 1_200_000)
            .write(to: root.appendingPathComponent("a.bin"))
        let scanner = DuplicateScanner()
        _ = scanner.find(under: root.path, by: KeepRule(.standard))
        XCTAssertEqual(scanner.unreadablePaths, 0)
    }
}
