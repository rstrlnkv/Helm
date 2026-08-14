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

    // MARK: - The counts, off a real walk

    /// The engine's reply carries what the scanner knows, or the page is being
    /// asked to draw a fact nobody sent it.
    func testTheReplyCarriesWhatTheWalkCouldNotRead() async throws {
        let root = scratchDirectory("dup-empty")
        try write("a.bin", in: root, bytes: 1_200_000, filler: 3)
        let wall = root.appendingPathComponent("wall")
        try FileManager.default.createDirectory(at: wall, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: wall.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: wall.path)

        let reply = await DuplicatesEngine().find(under: root.path)
        let found = try XCTUnwrap(reply)

        XCTAssertTrue(found.groups.isEmpty, "precondition: this fixture has no duplicates")
        XCTAssertEqual(found.unreadable, 1,
                       "the refusal reached the log and stopped there")
        XCTAssertEqual(DuplicatesEmpty.reason(groups: found.groups.count,
                                              unreadable: found.unreadable,
                                              librariesSkipped: found.librariesSkipped),
                       .notEverythingRead(1))
    }

    /// And a walk that read everything says nothing of the sort — the half that
    /// stops the note standing over every clean folder for ever.
    func testACleanWalkCarriesNoExcuses() async throws {
        let root = scratchDirectory("dup-empty-clean")
        try write("a.bin", in: root, bytes: 1_200_000, filler: 3)

        let reply = await DuplicatesEngine().find(under: root.path)
        let found = try XCTUnwrap(reply)

        XCTAssertEqual(found.unreadable, 0)
        XCTAssertEqual(found.librariesSkipped, 0)
        XCTAssertEqual(DuplicatesEmpty.reason(groups: found.groups.count,
                                              unreadable: found.unreadable,
                                              librariesSkipped: found.librariesSkipped),
                       .nothingFound)
    }

    /// **The other half of the same count, and it had none of its own.** A
    /// directory the walk was refused and a file whose digest failed are two
    /// different counters on the scanner; the reply adds them, and with the
    /// second dropped from the sum the whole suite stayed green. This is the
    /// commoner of the two on a Mac without Full Disk Access, where the folders
    /// list fine and the files will not open.
    ///
    /// A file that cannot be read leaves the running by design — unknown is not
    /// identical — so it is silently *absent* from the answer, which is the
    /// reason it has to be counted.
    func testAFileWhoseDigestFailedIsAHoleToo() async throws {
        let root = scratchDirectory("dup-empty-digest")
        let locked = try write("locked.bin", in: root, bytes: 1_200_000, filler: 6)
        // Its twin, so both are candidates: a size with one file in it never
        // reaches the hashing pass at all.
        try write("twin.bin", in: root, bytes: 1_200_000, filler: 6)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: locked.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: locked.path)

        let reply = await DuplicatesEngine().find(under: root.path)
        let found = try XCTUnwrap(reply)

        XCTAssertTrue(found.groups.isEmpty, """
            precondition: the unreadable file left the running rather than being grouped with \
            its twin — a digest nobody could take is not a match
            """)
        XCTAssertGreaterThan(found.unreadable, 0,
                             "a file Helm could not read is missing from the answer in silence")
        XCTAssertEqual(DuplicatesEmpty.reason(groups: 0, unreadable: found.unreadable,
                                              librariesSkipped: found.librariesSkipped),
                       .notEverythingRead(found.unreadable))
    }

    /// An application's own library is stepped over on purpose, and counted:
    /// somebody who points this at `~/Pictures` is told «one of a kind» about a
    /// folder whose largest contents were never opened.
    func testAnApplicationLibraryIsCountedAsAHole() async throws {
        let root = scratchDirectory("dup-empty-library")
        let library = root.appendingPathComponent("Family.photoslibrary")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try write("Family.photoslibrary/one.bin", in: root, bytes: 1_200_000, filler: 9)
        try write("Family.photoslibrary/two.bin", in: root, bytes: 1_200_000, filler: 9)

        let reply = await DuplicatesEngine().find(under: root.path)
        let found = try XCTUnwrap(reply)

        XCTAssertTrue(found.groups.isEmpty,
                      "precondition: the pair inside the library was not offered")
        XCTAssertEqual(found.librariesSkipped, 1)
        XCTAssertEqual(DuplicatesEmpty.reason(groups: found.groups.count,
                                              unreadable: found.unreadable,
                                              librariesSkipped: found.librariesSkipped),
                       .librariesNotOpened(1))
    }
}
