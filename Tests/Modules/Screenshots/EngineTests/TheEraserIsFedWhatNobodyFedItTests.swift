import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **What the eraser does with the inputs its first tests did not feed it:** a press that never moves, a pen stroke
/// a hair outside the circle, a text and a blur taken by their areas, a layer half outside the area, an erase after a run
/// of nudges, and the cost of one fast drag across a picture full of layers.
///
/// What it would print if it failed totally: the zero-length press taking nothing fails the first test's count; an
/// eraser that took the whole picture fails every "stays" assertion by name.
final class TheEraserIsFedWhatNobodyFedItTests: XCTestCase {
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let radius: CGFloat = 9

    private func line(_ editing: inout AnnotationEditing, from: CGPoint, to: CGPoint, tool: AnnotationTool = .line) {
        editing.begin(tool, at: from)
        editing.drag(to: to, shift: false)
        editing.end()
    }

    private func erase(_ editing: inout AnnotationEditing, _ points: [CGPoint]) {
        editing.beginErase(at: points[0], radius: radius)
        for point in points.dropFirst() { editing.drag(to: point, shift: false) }
        editing.end()
    }

    func testAPressThatNeverMovesTakesTheLayerUnderItAndNothingOnBareGround() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, from: CGPoint(x: 150, y: 200), to: CGPoint(x: 450, y: 200))
        let before = editing.layers
        erase(&editing, [CGPoint(x: 300, y: 300)])
        XCTAssertEqual(editing.layers, before, "a press on bare ground took a layer")
        erase(&editing, [CGPoint(x: 300, y: 205)])
        XCTAssertEqual(editing.layers, [], "a press on a layer did not take it")
        editing.undo()
        XCTAssertEqual(editing.layers, before)
        XCTAssertEqual(editing.layers.first?.id, before.first?.id, "the id changed through undo")
    }

    func testAPenNearButNotWithinTheCircleStaysAndOneWithinGoes() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, from: CGPoint(x: 150, y: 200), to: CGPoint(x: 450, y: 200), tool: .pen)
        let before = editing.layers
        let half = (before[0].stroke?.width ?? 0) / 2
        erase(&editing, [CGPoint(x: 300, y: 200 + half + radius + 3)])
        XCTAssertEqual(editing.layers, before, "a circle clear of the stroke took it")
        erase(&editing, [CGPoint(x: 300, y: 200 + half + radius - 3)])
        XCTAssertEqual(editing.layers, [], "a circle on the stroke did not take it")
    }

    func testATextAndABlurAreTakenByTheirAreas() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertTrue(editing.place(text: "Hello", at: CGPoint(x: 300, y: 300)))
        line(&editing, from: CGPoint(x: 400, y: 150), to: CGPoint(x: 500, y: 250), tool: .blur)
        let before = editing.layers
        XCTAssertEqual(before.count, 2)
        erase(&editing, [CGPoint(x: 450, y: 200)])
        XCTAssertEqual(editing.layers.map(\.id), [before[0].id], "a press in the middle of a blur did not take it")
        let frame = before[0].frame
        erase(&editing, [CGPoint(x: frame.midX, y: frame.midY)])
        XCTAssertEqual(editing.layers, [], "a press in a text's frame did not take it")
    }

    func testAFastDragAcrossManyLayersIsCheap() {
        var editing = AnnotationEditing(bounds: area)
        for index in 0..<60 {
            let base = 120 + CGFloat(index % 20) * 18
            editing.begin(.pen, at: CGPoint(x: 120, y: base))
            for step in 1..<1000 {
                editing.drag(to: CGPoint(x: 120 + CGFloat(step) * 0.5, y: base + sin(CGFloat(step) / 7) * 4), shift: false)
            }
            editing.end()
        }
        XCTAssertGreaterThan(editing.layers.count, 30)
        let clock = ContinuousClock()
        let took = clock.measure {
            editing.beginErase(at: CGPoint(x: 100, y: 99), radius: radius)
            editing.drag(to: CGPoint(x: 700, y: 101), shift: false)
        }
        editing.end()
        XCTAssertLessThan(took, .milliseconds(100), "one pointer event of the eraser took \(took): the drag would stutter")
    }

    func testAFastDragAcrossManyTextsIsCheap() {
        var editing = AnnotationEditing(bounds: area)
        for index in 0..<60 {
            XCTAssertTrue(editing.place(text: "A line of text number \(index)", at: CGPoint(x: 120 + CGFloat(index % 3) * 150, y: 130 + CGFloat(index / 3) * 18)))
        }
        let clock = ContinuousClock()
        let took = clock.measure {
            editing.beginErase(at: CGPoint(x: 100, y: 99), radius: radius)
            editing.drag(to: CGPoint(x: 700, y: 101), shift: false)
        }
        editing.end()
        XCTAssertLessThan(took, .milliseconds(100), "one pointer event of the eraser took \(took) over 60 texts")
    }

    func testALayerHalfOutsideTheAreaIsNotTakenByACircleThatTouchesOnlyItsHiddenHalf() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 300, y: 400))
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 600, height: 200))
        let before = editing.layers
        // The circle's centre is 8 pt below the area's bottom edge (y 300) and 8 pt left of the line: it covers 1 pt of the
        // picture the area shows, where the nearest corner of the line's clipped body is about 9.7 pt away (its centre is 11.3), and
        // meets the line only below the edge.
        erase(&editing, [CGPoint(x: 292, y: 308)])
        XCTAssertEqual(editing.layers, before, "the circle took a layer by the part of it the area does not show")
    }

    func testARunOfNudgesIsNotJoinedAcrossAnEraseThatTookNothing() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, from: CGPoint(x: 150, y: 200), to: CGPoint(x: 250, y: 200))
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 200), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected)
        _ = editing.nudgeSelected(by: CGPoint(x: 5, y: 0))
        erase(&editing, [CGPoint(x: 600, y: 450)])
        _ = editing.nudgeSelected(by: CGPoint(x: 5, y: 0))
        XCTAssertEqual(editing.selected?.start.x, 160)
        editing.undo()
        XCTAssertEqual(editing.selected?.start.x, 155, "the second nudge was joined to the first across the erase")
    }

    func testRedoAndEveryEditWaitWhileTheDragIsOpen() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, from: CGPoint(x: 150, y: 200), to: CGPoint(x: 250, y: 200))
        line(&editing, from: CGPoint(x: 150, y: 400), to: CGPoint(x: 250, y: 400))
        editing.undo()
        XCTAssertTrue(editing.canRedo)
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 200), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected)
        let before = editing.layers
        editing.beginErase(at: CGPoint(x: 600, y: 450), radius: radius)
        editing.redo()
        XCTAssertEqual(editing.layers, before, "a redo in the middle of the drag changed the list")
        XCTAssertFalse(editing.nudgeSelected(by: CGPoint(x: 5, y: 0)), "a nudge in the middle of the drag moved the selected layer")
        XCTAssertEqual(editing.layers, before)
        editing.recolor(.red)
        editing.setThickness(.thick)
        editing.setFilled(true)
        XCTAssertEqual(editing.layers, before, "an edit of the selected object in the middle of the drag changed the list")
        XCTAssertFalse(editing.place(text: "x", at: CGPoint(x: 300, y: 300)), "a text was placed in the middle of the drag")
        editing.end()
        XCTAssertEqual(editing.layers, before, "the release of an empty drag changed the list")
        XCTAssertTrue(editing.canRedo, "the drag that met nothing cleared the redo stack")
    }

    func testErasingTheSelectedObjectLeavesNothingForANudgeToMove() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, from: CGPoint(x: 150, y: 200), to: CGPoint(x: 250, y: 200))
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 200), tool: nil))
        editing.end()
        erase(&editing, [CGPoint(x: 200, y: 200)])
        XCTAssertNil(editing.selected)
        XCTAssertFalse(editing.nudgeSelected(by: CGPoint(x: 5, y: 0)), "a nudge found an object after the eraser took the selected one")
    }

    func testAJumpFartherThanTheCapStillMeetsALayerOnItsLine() {
        var editing = AnnotationEditing(bounds: CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))
        line(&editing, from: CGPoint(x: 0, y: -50), to: CGPoint(x: 0, y: 50))
        erase(&editing, [CGPoint(x: -100_000, y: 0), CGPoint(x: 100_000, y: 0)])
        XCTAssertEqual(editing.layers, [], "a 200 000 pt jump over a line missed it")
    }
}
