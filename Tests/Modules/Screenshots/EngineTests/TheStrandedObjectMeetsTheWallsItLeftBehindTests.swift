import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **An object the area was pulled in past, moved by the arrows and by a drag.** The per-axis clamp
/// has to leave a wall the box already lies beyond, hold the opposite one, and never let a repeated
/// outward move leave the finite numbers.
final class TheStrandedObjectMeetsTheWallsItLeftBehindTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func selectedRectangle() -> AnnotationEditing { drawnAndSelectedRectangle(in: area) }

    func testAnObjectStraddlingTheEdgeMovesAsAskedOutwardAndInward() {
        var editing = selectedRectangle() // x 200...300, y 200...260
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 150, height: 300)) // right wall at 250
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 1, y: 0)))
        XCTAssertEqual(editing.selected!.frame.minX, 201, accuracy: 0.001, "outward, the box is beyond the wall: as asked")
        XCTAssertEqual(editing.selected!.frame.minY, 200, accuracy: 0.001)
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(editing.selected!.frame.minX, 200, accuracy: 0.001, "inward is as asked too")
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: -5000, y: 0)))
        XCTAssertEqual(editing.selected!.frame.minX, 100, accuracy: 0.001, "the near wall still holds")
    }

    func testAStrandedObjectDraggedAcrossTheWholeAreaIsHeldByTheFarWall() {
        var editing = selectedRectangle()
        editing.reshape(bounds: CGRect(x: 400, y: 100, width: 100, height: 300)) // the object lies left of it
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.drag(to: CGPoint(x: 420, y: 230), shift: false)
        XCTAssertGreaterThanOrEqual(editing.selected!.frame.minX, 200, "toward the area")
        XCTAssertLessThanOrEqual(editing.selected!.frame.maxX, 500)
        editing.drag(to: CGPoint(x: 5000, y: 230), shift: false)
        editing.end()
        XCTAssertEqual(editing.selected!.frame.maxX, 500, accuracy: 0.001, "held at the far wall")
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 1, y: 0)))
        XCTAssertEqual(editing.selected!.frame.maxX, 500, accuracy: 0.001)
    }

    func testARepeatedOutwardMoveNeverLeavesTheFiniteNumbers() {
        var editing = selectedRectangle()
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 50, height: 50)) // beyond on both axes
        for _ in 0..<5 { _ = editing.nudgeSelected(by: CGPoint(x: 1e308, y: 1e308)) }
        let box = editing.layers.first!.frame // a nudge outward lets go of the selection
        XCTAssertTrue(box.minX.isFinite && box.maxX.isFinite && box.minY.isFinite && box.maxY.isFinite,
                      "an object walked outward went to \(box)")
    }

    func testAnInfiniteDeltaMovesNothingOutOfTheFiniteNumbers() {
        var editing = selectedRectangle()
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        _ = editing.nudgeSelected(by: CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity))
        let box = editing.layers.first!.frame // a nudge outward lets go of the selection
        XCTAssertTrue(box.minX.isFinite && box.maxX.isFinite && box.minY.isFinite && box.maxY.isFinite, "\(box)")
    }

    func testAStrandedObjectDraggedAwayFromTheAreaDoesNotJumpIntoIt() {
        var editing = selectedRectangle() // x 200...300
        editing.reshape(bounds: CGRect(x: 400, y: 100, width: 100, height: 300))
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.drag(to: CGPoint(x: 150, y: 230), shift: false) // the pointer goes left, away from the area
        editing.end()
        XCTAssertLessThanOrEqual(editing.selected!.frame.minX, 200, "dragged left, the object went to \(editing.selected!.frame)")
    }

    /// A nudge ends like a drag's release: an object it leaves wholly outside the area is let go of.
    /// Total failure of the subject (nudge never judges) prints the message "stayed selected" with the selected annotation.
    func testANudgeThatLeavesTheObjectWhollyOutsideLetsGoOfIt() {
        var editing = selectedRectangle() // x 200...300
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 101, height: 300)) // right wall at 201: straddling
        XCTAssertNotNil(editing.selected)
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 10, y: 0)))
        XCTAssertEqual(editing.layers.first!.frame.minX, 210, accuracy: 0.001, "the subject: the object went outward")
        XCTAssertNil(editing.selected, "a nudge left the object wholly outside the area and it stayed selected")
    }

    /// The other side of the same check: a nudge that leaves a part inside keeps the selection.
    func testANudgeThatKeepsAPartOfTheObjectInsideKeepsItSelected() {
        var editing = selectedRectangle()
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 150, height: 300)) // right wall at 250
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 10, y: 0)))
        XCTAssertNotNil(editing.selected, "210...310 still meets 100...250")
    }
}
