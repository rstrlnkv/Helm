import XCTest
@testable import Module_Disk_Engine

/// The frame the drill animation ends on, against the frame that follows it.
///
/// Measured on the running app before this was fixed, one frame apart:
///
///     last frame ring0:  5 arcs 0-267 267-318 318-334 334-350 350-353
///     first frame ring0: 3 arcs 0-288 288-358 358-360
///
/// Five arcs became three, every boundary moved, and the old state did not even
/// close the circle. The cause was that the animation transformed the layout it
/// was leaving while the destination was a layout computed independently:
/// folding into "other" is decided against the parent's total in one and the
/// folder's own total in the other, so the two could not agree.
///
/// The drill lands first now, so the destination is the layout already on
/// screen and the arcs move to where they already are. These are the rules that
/// makes true.
final class RingSeamTests: XCTestCase {

    /// The whole point: at full progress an arc that stays is exactly where its
    /// layout puts it, whatever it was doing a moment earlier.
    func testAnArcThatStaysLandsExactlyOnItsLayoutPosition() {
        let wasSomewhereElse = 0.42
        let layoutSaysHere = 2.71
        XCTAssertEqual(RingUnfold.toward(wasSomewhereElse, layoutSaysHere, progress: 1),
                       layoutSaysHere, accuracy: 1e-12)
    }

    func testAtRestAnArcHasNotMovedAtAll() {
        XCTAssertEqual(RingUnfold.toward(0.42, 2.71, progress: 0), 0.42, accuracy: 1e-12)
    }

    func testProgressOutsideTheAnimationCannotOvershoot() {
        XCTAssertEqual(RingUnfold.toward(1, 2, progress: 1.4), 2, accuracy: 1e-12)
        XCTAssertEqual(RingUnfold.toward(1, 2, progress: -0.3), 1, accuracy: 1e-12)
    }

    /// An arc with no counterpart in the layout being left — the level that was
    /// never drawn, and whatever a different fold produced — arrives from one
    /// ring further out and lands on its own ring.
    func testAnArrivingArcSlidesInFromOneRingFurtherOut() {
        XCTAssertEqual(RingUnfold.arrivingRing(2, progress: 0), 3, accuracy: 1e-12)
        XCTAssertEqual(RingUnfold.arrivingRing(2, progress: 0.5), 2.5, accuracy: 1e-12)
        XCTAssertEqual(RingUnfold.arrivingRing(2, progress: 1), 2, accuracy: 1e-12)
    }

    /// The ring index of an arc that stays is interpolated the same way its
    /// angles are, so it cannot land between two rings.
    func testARingIndexAlsoLandsOnTheLayoutsValue() {
        XCTAssertEqual(RingUnfold.toward(1, 0, progress: 1), 0, accuracy: 1e-12)
        XCTAssertEqual(RingUnfold.toward(2, 1, progress: 0.5), 1.5, accuracy: 1e-12)
    }
}
