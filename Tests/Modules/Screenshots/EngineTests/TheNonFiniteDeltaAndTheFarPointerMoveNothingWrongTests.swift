import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The guard on a non-finite delta, and a drag whose pointer leaves the display.** The delta of a
/// move comes from the raw pointer; the walls alone decide how far the object may go.
final class TheNonFiniteDeltaAndTheFarPointerMoveNothingWrongTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func selectedRectangle() -> AnnotationEditing { drawnAndSelectedRectangle(in: area) }

    private let bad: [CGPoint] = [
        CGPoint(x: CGFloat.infinity, y: 0), CGPoint(x: 0, y: -CGFloat.infinity), CGPoint(x: CGFloat.nan, y: 0),
        CGPoint(x: 0, y: CGFloat.nan), CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity),
    ]

    /// An object inside the area: with the guard gone, infinity would carry it to the wall (an object
    /// inside the area has no free side), so only the guard keeps the frame where it was.
    func testANonFiniteDeltaMovesNothingAtAll() {
        for delta in bad {
            var editing = selectedRectangle()
            let before = editing.selected!
            let undoBefore = editing.canUndo
            XCTAssertEqual(before.translated(by: delta, within: area), before, "translated by \(delta)")
            XCTAssertTrue(editing.nudgeSelected(by: delta), "\(delta)")
            XCTAssertEqual(editing.selected, before, "nudged by \(delta)")
            XCTAssertEqual(editing.canUndo, undoBefore, "no undo step for \(delta)")
        }
    }

    func testANonFiniteDeltaOnAStrandedObjectMovesNothingAtAll() {
        for delta in bad {
            var editing = selectedRectangle()
            editing.reshape(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
            let before = editing.selected!
            XCTAssertEqual(before.translated(by: delta, within: editing.bounds), before, "\(delta)")
        }
    }

    func testAnInsideObjectDraggedWithThePointerFarOutsideStopsAtTheWall() {
        for far in [CGPoint(x: 1e7, y: 230), CGPoint(x: -1e7, y: 230), CGPoint(x: 200, y: 1e7), CGPoint(x: 200, y: -1e7),
                    CGPoint(x: 1e300, y: -1e300)] {
            var editing = selectedRectangle()
            XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
            editing.drag(to: far, shift: false)
            editing.end()
            let box = editing.selected!.frame
            XCTAssertTrue(area.insetBy(dx: -0.001, dy: -0.001).contains(box), "pointer at \(far): object at \(box)")
            XCTAssertEqual(box.size.width, 100, accuracy: 0.001)
            XCTAssertEqual(box.size.height, 60, accuracy: 0.001)
            // The wall in the direction of the pointer is touched, not overshot or stopped short.
            if far.x > 1e6 { XCTAssertEqual(box.maxX, 500, accuracy: 0.001) }
            if far.x < -1e6 { XCTAssertEqual(box.minX, 100, accuracy: 0.001) }
            if far.y > 1e6 { XCTAssertEqual(box.maxY, 400, accuracy: 0.001) }
            if far.y < -1e6 { XCTAssertEqual(box.minY, 100, accuracy: 0.001) }
        }
    }

    func testThePointerLeavingAndReturningLeavesTheObjectWhereTheDeltaSaysNotWhereItWasHeld() {
        var editing = selectedRectangle() // x 200...300, y 200...260; press at (200, 230)
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.drag(to: CGPoint(x: 9000, y: 230), shift: false)
        XCTAssertEqual(editing.selected!.frame.maxX, 500, accuracy: 0.001, "held at the wall while away")
        editing.drag(to: CGPoint(x: 250, y: 230), shift: false) // back: delta +50 from the press
        XCTAssertEqual(editing.selected!.frame.minX, 250, accuracy: 0.001, "back at the pointer's own delta")
        editing.drag(to: CGPoint(x: -9000, y: 230), shift: false)
        XCTAssertEqual(editing.selected!.frame.minX, 100, accuracy: 0.001)
        editing.drag(to: CGPoint(x: 200, y: 230), shift: false) // delta 0
        editing.end()
        XCTAssertEqual(editing.selected!.frame.minX, 200, accuracy: 0.001, "a return to the press is the start again")
        XCTAssertEqual(editing.selected!.frame.minY, 200, accuracy: 0.001)
        // A gesture that ends where it began records no step: the one undo left is the drawing itself.
        editing.undo()
        XCTAssertEqual(editing.layers.count, 0)
    }

    func testANonFinitePointerMidDragLeavesTheObjectWhereItWas() {
        var editing = selectedRectangle()
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.drag(to: CGPoint(x: 260, y: 230), shift: false)
        let held = editing.selected!
        editing.drag(to: CGPoint(x: CGFloat.nan, y: 230), shift: false)
        editing.drag(to: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity), shift: false)
        editing.end()
        XCTAssertTrue(editing.selected!.frame.minX.isFinite)
        XCTAssertEqual(editing.selected!.frame.minX, held.frame.minX, accuracy: 0.001)
    }
}
