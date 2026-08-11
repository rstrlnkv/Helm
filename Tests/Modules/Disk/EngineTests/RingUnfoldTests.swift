import XCTest
@testable import Module_Disk_Engine

/// The transform runs on every arc of every frame, and its two ends are the
/// only states anyone sees standing still: at rest it must be exactly the
/// layout, and at the end exactly a full circle. Everything between is judged
/// by eye, so what is pinned here is the arithmetic that eyes cannot check.
final class RingUnfoldTests: XCTestCase {
    private let top = RingUnfold.top
    private let full = RingUnfold.full

    /// A quarter wedge, from 12 o'clock to 3 o'clock.
    private let start = -Double.pi / 2
    private let span = Double.pi / 2

    private func angle(_ a: Double, _ t: Double) -> Double {
        RingUnfold.angle(a, pivotStart: start, span: span, progress: t)
    }

    func testAtRestTheTransformChangesNothing() {
        for a in stride(from: -Double.pi, through: Double.pi, by: 0.37) {
            XCTAssertEqual(angle(a, 0), a, accuracy: 1e-12, "\(a)")
        }
    }

    /// The whole point: at the end the pivot starts at 12 o'clock and ends a
    /// full turn later, whatever it was before.
    func testAtTheEndThePivotIsTheWholeRing() {
        XCTAssertEqual(angle(start, 1), top, accuracy: 1e-12)
        XCTAssertEqual(angle(start + span, 1), top + full, accuracy: 1e-12)
    }

    /// True for any wedge, not just the tidy quarter above — including the last
    /// wedge of the ring, whose start is nowhere near 12 o'clock.
    func testAnyWedgeEndsAsTheWholeRing() {
        for (s, sp) in [(top, full), (top + 0.1, 0.2), (top + full - 0.5, 0.5), (0.0, 1.0)] {
            let a0 = RingUnfold.angle(s, pivotStart: s, span: sp, progress: 1)
            let a1 = RingUnfold.angle(s + sp, pivotStart: s, span: sp, progress: 1)
            XCTAssertEqual(a0, top, accuracy: 1e-9, "start \(s) span \(sp)")
            XCTAssertEqual(a1, top + full, accuracy: 1e-9, "start \(s) span \(sp)")
        }
    }

    /// Order is what makes it read as one wedge opening rather than a reshuffle:
    /// arcs that were clockwise of each other stay that way at every step.
    func testTheTransformIsMonotonic() {
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            var previous = -Double.infinity
            for a in stride(from: top, through: top + full, by: 0.19) {
                let mapped = angle(a, t)
                XCTAssertGreaterThan(mapped, previous, "t=\(t) a=\(a)")
                previous = mapped
            }
        }
    }

    /// A sliver would otherwise ask for a scale near infinity and take every
    /// other angle off the screen with it.
    func testAZeroWidthWedgeStaysFinite() {
        for span in [0.0, -0.0, 1e-18] {
            let k = RingUnfold.scale(span: span, progress: 1)
            XCTAssertTrue(k.isFinite, "\(span)")
            let mapped = RingUnfold.angle(top, pivotStart: top, span: span, progress: 1)
            XCTAssertTrue(mapped.isFinite)
        }
    }

    /// The children of the wedge move inward to where they will live after the
    /// drill; nothing else moves rings at all.
    func testOnlyDescendantsChangeRing() {
        XCTAssertEqual(RingUnfold.ring(1, isDescendant: true, progress: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(RingUnfold.ring(1, isDescendant: true, progress: 1), 0, accuracy: 1e-12)
        XCTAssertEqual(RingUnfold.ring(2, isDescendant: false, progress: 1), 2, accuracy: 1e-12)
    }

    /// The descendants are what the user is about to look at, so they never
    /// fade; the pivot and the other branches are leaving.
    func testDescendantsNeverFade() {
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            XCTAssertEqual(RingUnfold.opacity(isDescendant: true, progress: t), 1)
        }
        XCTAssertEqual(RingUnfold.opacity(isDescendant: false, progress: 1), 0)
        XCTAssertEqual(RingUnfold.opacity(isDescendant: false, progress: 0), 1)
    }

    /// Pushed past a full turn, an arc would wrap back over the ring it just
    /// made way for.
    func testArcsPushedPastTheCircleAreDropped() {
        XCTAssertTrue(RingUnfold.isVisible(start: top, end: top + 0.2))
        XCTAssertFalse(RingUnfold.isVisible(start: top + full + 0.1, end: top + full + 0.4))
        XCTAssertFalse(RingUnfold.isVisible(start: top - 0.4, end: top - 0.1))
    }
}
