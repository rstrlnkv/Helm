import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// `wasted` describes the copies that would be removed, and they are not
/// interchangeable with the one that stays.
///
/// The group took its size from `identical.first` — the walk order — while its
/// paths came from `SurvivingCopy.order`, two different orderings of the same
/// array, and multiplied that one figure by `count - 1`. Content-identical
/// files need not agree on what they *occupy*: an APFS clone or an
/// HFS-compressed copy takes far less than its logical length, which is why
/// `FileFacts` carries `allocated` separately in the first place. So a pair of
/// [clone, real file] reported nothing wasted or the whole file wasted purely
/// by sort order, and the screen's promise of what removing the extras frees
/// then disagreed with what HelmTrash reported afterwards.
final class WastedIsTheCopiesThatLeaveTests: XCTestCase {

    private func facts(_ allocations: [(String, Int)]) -> [FileFacts] {
        allocations.enumerated().map { index, pair in
            FileFacts(path: pair.0, bytes: 4_000_000, fileID: UInt64(index + 1),
                      added: nil, allocated: pair.1)
        }
    }

    /// Three copies of one thing occupying three different amounts. No "one
    /// size × (count - 1)" can produce the right answer for this fixture,
    /// whichever copy the survivor rule picks — which is what stops it passing
    /// by luck.
    func testWastedIsWhatTheRemovedCopiesOccupy() throws {
        let files = facts([("/clone.bin", 0), ("/middle.bin", 1_000_000),
                           ("/real.bin", 4_000_000)])

        let group = Duplicates.group(files)

        let survivor = try XCTUnwrap(group.paths.first)
        let leaving = files.filter { $0.path != survivor }.reduce(0) { $0 + $1.allocated }
        XCTAssertEqual(group.wasted, leaving,
                       "wasted describes the copy that stays, not the ones that go")
        XCTAssertEqual(group.paths.count, 3)
    }

    /// The pair from the report, both ways round: the answer must not depend on
    /// which copy the walk reached first.
    func testACloneAndItsOriginalAgreeWhicheverWayTheyArrive() {
        let forwards = Duplicates.group(facts([("/a-clone.bin", 0),
                                               ("/b-real.bin", 4_000_000)]))
        let backwards = Duplicates.group(facts([("/b-real.bin", 4_000_000),
                                                ("/a-clone.bin", 0)]))
        XCTAssertEqual(forwards.paths, backwards.paths)
        XCTAssertEqual(forwards.wasted, backwards.wasted)
    }

    /// And the size shown per row is the copy's own, not the group's average or
    /// its first-reached member.
    func testEachCopyCarriesItsOwnSize() throws {
        let group = Duplicates.group(facts([("/clone.bin", 0), ("/real.bin", 4_000_000)]))
        let sizes = Dictionary(uniqueKeysWithValues: group.copies.map { ($0.path, $0.bytes) })
        XCTAssertEqual(sizes["/clone.bin"], 0)
        XCTAssertEqual(sizes["/real.bin"], 4_000_000)
    }

    /// What removing some of them leaves behind: the figure has to be rebuilt
    /// from the copies that are still there, not carried over.
    func testAGroupThatLosesACopyRecountsWhatIsLeft() {
        let group = Duplicates.group(facts([("/a.bin", 1_000_000), ("/b.bin", 2_000_000),
                                            ("/c.bin", 3_000_000)]))
        let survivor = group.paths[0]
        let left = DuplicateGroup(copies: group.copies.filter { $0.path != group.paths[1] })

        XCTAssertEqual(left.paths.count, 2)
        XCTAssertEqual(left.paths.first, survivor, "the survivor changed when a copy left")
        XCTAssertEqual(left.wasted, left.copies[1].bytes)
    }
}
