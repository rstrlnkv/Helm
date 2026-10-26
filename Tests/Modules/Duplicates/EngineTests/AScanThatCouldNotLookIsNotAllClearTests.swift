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
}
