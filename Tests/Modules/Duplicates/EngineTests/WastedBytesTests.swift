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
                         module: "test", trashing: { _ in }).freedBytes
    }

    /// And the pre-filter still finds them: a duplicate must not be lost to a
    /// difference in blocks.
    func testTwoIdenticalFilesAreStillFound() throws {
        _ = try write("one.bin", 3)
        _ = try write("two.bin", 3)
        XCTAssertEqual(DuplicateScanner().find(under: root.path, by: KeepRule(.standard))?.count, 1)
    }
}
