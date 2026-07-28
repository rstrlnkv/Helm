import XCTest
@testable import Module_Disk_Engine

/// The level that arrives when you drill.
///
/// The ring shows three levels and a drill promotes each one inward: the wedge
/// becomes the middle, its children take ring 0, its grandchildren take ring 1.
/// Whatever becomes the new outermost ring was therefore never on screen — it
/// had nowhere to slide in from, so it appeared whole the instant the tree
/// swapped, which is what "the third level appears abruptly" was. The layout
/// now carries one level more than is drawn, and that spare enters the way
/// everything else does.
final class RingSpareLevelTests: XCTestCase {

    func testTheSpareLevelIsInvisibleBeforeTheDrillStarts() {
        XCTAssertEqual(RingUnfold.opacity(isPivot: false, isDescendant: true,
                                          isSpare: true, progress: 0), 0)
    }

    func testTheSpareLevelFadesUpWithTheUnfold() {
        XCTAssertEqual(RingUnfold.opacity(isPivot: false, isDescendant: true,
                                          isSpare: true, progress: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RingUnfold.opacity(isPivot: false, isDescendant: true,
                                          isSpare: true, progress: 1), 1)
    }

    /// It arrives at full opacity exactly where the drill lands, so the swap to
    /// the new tree changes nothing that was on screen a frame earlier.
    func testAtTheEndOfTheUnfoldTheSpareMatchesAnOrdinaryDescendant() {
        let spare = RingUnfold.opacity(isPivot: false, isDescendant: true, isSpare: true, progress: 1)
        let ordinary = RingUnfold.opacity(isPivot: false, isDescendant: true, progress: 1)
        XCTAssertEqual(spare, ordinary)
    }

    /// Only the branch being opened has a spare worth drawing: everything
    /// outside it is on its way off the screen.
    func testASpareOutsideTheOpeningBranchIsNeverDrawn() {
        for t in [0.0, 0.25, 0.5, 1.0] {
            XCTAssertEqual(RingUnfold.opacity(isPivot: false, isDescendant: false,
                                              isSpare: true, progress: t), 0)
        }
    }

    func testTheLevelsThatWereAlreadyRightAreUnchanged() {
        XCTAssertEqual(RingUnfold.opacity(isPivot: false, isDescendant: true, progress: 0.5), 1)
        XCTAssertEqual(RingUnfold.opacity(isPivot: true, isDescendant: false, progress: 0), 1)
        XCTAssertEqual(RingUnfold.opacity(isPivot: true, isDescendant: false, progress: 1), 0)
    }

    /// The spare slides from outside the drawn area to the outermost drawn
    /// ring, which is what makes the fade a growth rather than a dissolve.
    func testTheSpareSlidesInFromOutsideTheDrawnArea() {
        let visibleRings = 3
        let spare = Double(visibleRings)
        XCTAssertEqual(RingUnfold.ring(visibleRings, isDescendant: true, progress: 0), spare)
        XCTAssertEqual(RingUnfold.ring(visibleRings, isDescendant: true, progress: 1),
                       spare - 1, "it lands where the outermost drawn ring is")
    }
}
