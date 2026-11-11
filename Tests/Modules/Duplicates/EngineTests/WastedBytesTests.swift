import Foundation
import XCTest
import HelmTestSupport
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
        root = scratchDirectory("wasted")
    }

    /// Over the scanner's own floor, or the file is never a candidate.
    private func write(_ name: String, _ byte: UInt8) throws -> String {
        try write(name, in: root, bytes: 1_200_000, filler: byte).path
    }

    /// **Asked of the removal, not of a second measurement.** This used to compare
    /// `wasted` with `FileWeight.allocated(of:countingOnce:)`, which is the
    /// question "what does this path occupy" — clone-blind on purpose — so on a
    /// fixture of Finder duplicates the assertion would have *demanded* the
    /// doubled figure that `CloneShare` exists to refuse. What the doc above
    /// promises is that one number, so the other side of it is the batch itself.
    func testWastedIsWhatRemovingTheExtrasWouldActuallyFree() throws {
        _ = try write("a.bin", 7)
        _ = try write("b.bin", 7)

        let group = try XCTUnwrap(DuplicateScanner().find(under: root.path, by: KeepRule(.standard))?.first)
        XCTAssertEqual(group.paths.count, 2)

        XCTAssertEqual(group.wasted, freedByRemovingTheExtras(of: group),
                       "the screen promises what deleting frees and quotes something else")
        XCTAssertGreaterThan(group.wasted, 0,
                             "two independently written files: both figures may not be zero")
    }

    /// And the case the whole fold exists for: a clone shares its blocks with the
    /// copy that stays, so neither figure may be its size.
    func testACloneOfTheCopyThatStaysIsNotSpaceInEitherFigure() throws {
        let first = try write("original.bin", 5)
        let clone = root.appendingPathComponent("clone.bin").path
        try XCTSkipUnless(clonefile(first, clone, 0) == 0,
                          "this volume does not clone; the case under test cannot arise")
        let family = try XCTUnwrap(CloneShare.familyID(ofFileAt: first))
        XCTAssertEqual(CloneShare.familyID(ofFileAt: clone), family,
                       "precondition: the fixture is a clone family")

        let group = try XCTUnwrap(DuplicateScanner().find(under: root.path, by: KeepRule(.standard))?.first)
        XCTAssertEqual(group.paths.count, 2, "precondition: the pair was found at all")

        XCTAssertEqual(group.wasted, 0)
        XCTAssertEqual(freedByRemovingTheExtras(of: group), 0,
                       "the removal would report blocks the survivor goes on holding")
    }

    /// What the batch will say it freed, without moving anything: the arithmetic
    /// runs before the move and `trashing` is the parameter that lets a test stop
    /// there.
    private func freedByRemovingTheExtras(of group: DuplicateGroup) -> Int {
        HelmTrash.remove(allowed: Array(group.paths.dropFirst()),
                         sharedWith: [group.paths[0]],
                         module: "test", trashing: { try FileManager.default.removeItem(at: $0) }).freedBytes
    }

    /// And the pre-filter still finds them: a duplicate must not be lost to a
    /// difference in blocks.
    func testTwoIdenticalFilesAreStillFound() throws {
        _ = try write("one.bin", 3)
        _ = try write("two.bin", 3)
        XCTAssertEqual(DuplicateScanner().find(under: root.path, by: KeepRule(.standard))?.count, 1)
    }

    // MARK: - Wasted is the copies that leave
    //
    // `wasted` describes the copies that would be removed, and they are not
    // interchangeable with the one that stays.
    //
    // The group took its size from `identical.first` — the walk order — while its
    // paths came from `SurvivingCopy.order`, two different orderings of the same
    // array, and multiplied that one figure by `count - 1`. Content-identical
    // files need not agree on what they *occupy*: an APFS clone or an
    // HFS-compressed copy takes far less than its logical length, which is why
    // `FileFacts` carries `allocated` separately in the first place. So a pair of
    // [clone, real file] reported nothing wasted or the whole file wasted purely
    // by sort order, and the screen's promise of what removing the extras frees
    // then disagreed with what HelmTrash reported afterwards.

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

        let group = Duplicates.group(files, by: KeepRule(.standard))

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
                                               ("/b-real.bin", 4_000_000)]),
                                        by: KeepRule(.standard))
        let backwards = Duplicates.group(facts([("/b-real.bin", 4_000_000),
                                                ("/a-clone.bin", 0)]),
                                         by: KeepRule(.standard))
        XCTAssertEqual(forwards.paths, backwards.paths)
        XCTAssertEqual(forwards.wasted, backwards.wasted)
    }

    /// And the size shown per row is the copy's own, not the group's average or
    /// its first-reached member.
    func testEachCopyCarriesItsOwnSize() throws {
        let group = Duplicates.group(facts([("/clone.bin", 0), ("/real.bin", 4_000_000)]),
                                     by: KeepRule(.standard))
        let sizes = Dictionary(uniqueKeysWithValues: group.copies.map { ($0.path, $0.bytes) })
        XCTAssertEqual(sizes["/clone.bin"], 0)
        XCTAssertEqual(sizes["/real.bin"], 4_000_000)
    }

    /// What removing some of them leaves behind: the figure has to be rebuilt
    /// from the copies that are still there, not carried over.
    func testAGroupThatLosesACopyRecountsWhatIsLeft() {
        let group = Duplicates.group(facts([("/a.bin", 1_000_000), ("/b.bin", 2_000_000),
                                            ("/c.bin", 3_000_000)]),
                                     by: KeepRule(.standard))
        let survivor = group.paths[0]
        let left = DuplicateGroup(copies: group.copies.filter { $0.path != group.paths[1] })

        XCTAssertEqual(left.paths.count, 2)
        XCTAssertEqual(left.paths.first, survivor, "the survivor changed when a copy left")
        XCTAssertEqual(left.wasted, left.copies[1].bytes)
    }
}
