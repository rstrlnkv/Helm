import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A blur is held like a rectangle and taken by its area.** It has four corner handles, ⇧ makes it a square, a
/// press inside it lands on it where a press inside an unfilled rectangle lands on the picture, and a colour is
/// not one of its edits: it has no ink, so a recolour must not be an undo step that shows nothing.
final class TheBlurIsABoxTheEditorHoldsByItsAreaTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func drawn(_ tool: AnnotationTool) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: bounds)
        editing.begin(tool, at: CGPoint(x: 100, y: 100), style: .standard)
        editing.drag(to: CGPoint(x: 220, y: 160), shift: false)
        editing.end()
        return editing
    }

    func testAPressInsideTheBoxLandsOnABlurAndNotOnAnUnfilledRectangle() throws {
        let middle = CGPoint(x: 160, y: 130)
        let blur = try XCTUnwrap(drawn(.blur).layers.first, "nothing was drawn, so the press below says nothing")
        let rectangle = try XCTUnwrap(drawn(.rectangle).layers.first)
        XCTAssertTrue(AnnotationHit.hits(blur, at: middle), "the middle of a blur is the blur")
        XCTAssertFalse(AnnotationHit.hits(rectangle, at: middle), "the control: the middle of an unfilled rectangle is the picture")
        XCTAssertFalse(AnnotationHit.hits(blur, at: CGPoint(x: 160, y: 150 + 40)), "a press well outside the blur landed on it")
    }

    func testTheBlurHasTheFourCornersAndShiftMakesItASquare() throws {
        let blur = try XCTUnwrap(drawn(.blur).layers.first)
        XCTAssertEqual(blur.handles.map(\.handle), [.topLeft, .topRight, .bottomLeft, .bottomRight])
        let end = Annotation.constrained(.blur, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 220, y: 160), shift: true)
        XCTAssertEqual(end, CGPoint(x: 220, y: 220))
        XCTAssertNotEqual(Annotation.constrained(.blur, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 220, y: 160), shift: false), end,
                          "the control: with no ⇧ the box is the drag's")
        let resized = try XCTUnwrap(blur.resized(.bottomRight, to: CGPoint(x: 300, y: 200)))
        XCTAssertEqual(resized.frame, CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    func testABoxUnderAPointInAnAxisIsNotUsable() {
        func blur(_ end: CGPoint) -> Annotation { Annotation(tool: .blur, start: CGPoint(x: 10, y: 10), end: end) }
        XCTAssertTrue(blur(CGPoint(x: 11, y: 11)).isUsable)
        XCTAssertFalse(blur(CGPoint(x: 10, y: 50)).isUsable, "a blur with no width is a line of nothing")
        XCTAssertFalse(blur(CGPoint(x: 10.5, y: 50)).isUsable)
    }

    func testARecolourOfABlurIsNoStepAndAThicknessIs() throws {
        var editing = drawn(.blur)
        XCTAssertTrue(editing.press(at: CGPoint(x: 160, y: 130), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "nothing was selected, so the edits below are of nothing")
        XCTAssertTrue(editing.canUndo, "the control: drawing the blur was a step")
        var colour = editing
        colour.recolor(.blue)
        // The drawing is the one step there is; a recolour that changes nothing visible adds none.
        colour.undo()
        XCTAssertTrue(colour.layers.isEmpty, "the recolour was a step of its own")
        var size = editing
        size.setThickness(.thick)
        XCTAssertEqual(size.layers.first?.blockPoints, 24)
        size.undo()
        XCTAssertEqual(size.layers.first?.blockPoints, 16, "the block's size was not an undo step")
    }
}
