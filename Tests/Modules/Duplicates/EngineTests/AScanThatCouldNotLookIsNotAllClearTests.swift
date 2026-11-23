import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Duplicates_Engine

/// «No duplicates here. Every large file under this folder is one of a kind.» is
/// an assertion about somebody's Mac, and the scan draws it identically whether
/// it read the whole tree or was refused every directory in it.
///
/// The counts existed and went to the log only: `unreadablePaths` from the
/// enumerator's error handler, the digest failures from the hashing passes, and
/// the application libraries the walk steps over by policy. `find` answered a
/// bare array and there was nowhere in that type to put them, so the page could
/// not have known. Leftovers had exactly this and it was repaired four commits
/// ago; this is the same repair.
///
/// Guards a past defect: f0e00ef3 fix(duplicates): the banner counts what the disk gives back, and the page reaches the screen at all.
final class AScanThatCouldNotLookIsNotAllClearTests: XCTestCase {

    // MARK: - The rule

    func testAResultWithGroupsHasNothingToExplain() {
        XCTAssertNil(DuplicatesEmpty.reason(groups: 2, unreadable: 3, librariesSkipped: 1),
                     "a list is its own answer")
    }

    func testAWholeWalkThatFoundNothingSaysSo() {
        XCTAssertEqual(DuplicatesEmpty.reason(groups: 0, unreadable: 0, librariesSkipped: 0),
                       .nothingFound)
    }

    /// The claim this cannot back. One refused directory is enough: the answer
    /// «every large file here is one of a kind» is about a tree that was not
    /// read.
    func testAWalkThatWasRefusedDoesNotClaimACleanFolder() {
        XCTAssertEqual(DuplicatesEmpty.reason(groups: 0, unreadable: 1, librariesSkipped: 0),
                       .notEverythingRead(1))
    }

    /// And it outranks the libraries: being refused is a fault, and stepping over
    /// a photo library is a policy. The person who was refused has something to
    /// do about it.
    func testARefusalOutranksTheLibrariesItAlsoSkipped() {
        XCTAssertEqual(DuplicatesEmpty.reason(groups: 0, unreadable: 2, librariesSkipped: 5),
                       .notEverythingRead(2))
    }

    func testLibrariesSteppedOverAreStillAHoleInTheAnswer() {
        XCTAssertEqual(DuplicatesEmpty.reason(groups: 0, unreadable: 0, librariesSkipped: 3),
                       .librariesNotOpened(3))
    }

    // MARK: - The count itself

    /// Two same-size files the scan may list but not read, made unreadable and
    /// given back before the scratch sweep deletes them (teardown blocks unwind
    /// in reverse, so the restore registered here runs first).
    private func unreadablePair(in root: URL) throws -> [URL] {
        let urls = ["a.bin", "b.bin"].map { root.appendingPathComponent($0) }
        for url in urls {
            try Data(repeating: 0x41, count: DuplicateScanner.minBytes + 1).write(to: url)
            addTeardownBlock { Self.setMode(0o644, url) }
            Self.setMode(0o000, url)
        }
        return urls
    }

    private static func setMode(_ mode: Int, _ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    /// The scanner's digest failures reach the finding the page reads. Both
    /// files fail their prefix hash, so the answer is exactly two.
    func testTwoFilesThatCannotBeReadAreCountedInTheFinding() async throws {
        let root = scratchDirectory("dup-unreadable")
        _ = try unreadablePair(in: root)
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: root.appendingPathComponent("a.bin").path),
                      "this process reads past file modes (root)")
        let engine = DuplicatesEngine(settings: suiteSealGuard(), trashing: neverTrashes,
                                      verifying: { { _, _ in fatalError("a scan verifies nothing") } })
        let found = await engine.find(under: root.path, keeping: .standard, progress: nil)
        let findings = try XCTUnwrap(found)
        XCTAssertTrue(findings.groups.isEmpty, "unreadable files must not be grouped")
        XCTAssertEqual(findings.unreadable, 2)
    }

    /// One scanner searched twice: the second answer is about the second search.
    func testTheCountOfOneSearchIsNotCarriedIntoTheNext() throws {
        let root = scratchDirectory("dup-unreadable-twice")
        let urls = try unreadablePair(in: root)
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: urls[0].path),
                      "this process reads past file modes (root)")
        let scanner = DuplicateScanner()
        _ = scanner.find(under: root.path, by: KeepRule(.standard))
        XCTAssertEqual(scanner.unreadableFiles, 2, "precondition: the first search counted both")
        urls.forEach { Self.setMode(0o644, $0) }
        let groups = try XCTUnwrap(scanner.find(under: root.path, by: KeepRule(.standard)))
        XCTAssertEqual(groups.count, 1, "precondition: the second search could read the pair")
        XCTAssertEqual(scanner.unreadableFiles, 0)
    }
}
