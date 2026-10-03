import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The eraser takes whole objects, and one drag is one undo step.** What its circle meets along the drag goes at the
/// release, every layer whole, by the rule a click selects by (`AnnotationHit.hits`, the radius as its tolerance, repeated in `AnnotationHit.touched` and held to `hits` by the agreement test below, for layers inside the area); undo
/// brings all of them back in their places, and Esc in the middle of the drag takes nothing and records nothing.
///
/// What it would print if it failed totally: an eraser that took nothing leaves four layers after the drag and fails
/// the first assertion of the first test; one that took everything fails the fourth layer's.
final class TheEraserTakesWholeObjectsInOneStepTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let radius: CGFloat = 9

    /// Four lines across the area, at y 150, 200, 250 and 350; the first three are in the way of a vertical drag at x 300
    /// from y 120 to y 270, the fourth is not.
    private func fourLines() -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: area)
        for y in [150, 200, 250, 350] as [CGFloat] {
            editing.begin(.line, at: CGPoint(x: 150, y: y))
            editing.drag(to: CGPoint(x: 450, y: y), shift: false)
            editing.end()
        }
        XCTAssertEqual(editing.layers.count, 4, "the fixture drew fewer than four lines")
        return editing
    }

    private func erase(_ editing: inout AnnotationEditing, through points: [CGPoint]) {
        editing.beginErase(at: points[0], radius: radius)
        for point in points.dropFirst() { editing.drag(to: point, shift: false) }
        editing.end()
    }

    private let wayOfThree = [CGPoint(x: 300, y: 120), CGPoint(x: 300, y: 170), CGPoint(x: 300, y: 220), CGPoint(x: 300, y: 270)]

    func testADragThroughThreeOfFourTakesThemInOneStepAndOneUndoBringsThemBack() {
        var editing = fourLines()
        let before = editing.layers
        erase(&editing, through: wayOfThree)
        XCTAssertEqual(editing.layers.map(\.id), [before[3].id], "the drag did not take exactly the three lines it crossed")
        XCTAssertEqual(editing.layers.first, before[3], "the fourth line was changed")
        editing.undo()
        XCTAssertEqual(editing.layers, before, "one undo did not bring back all three, in their places")
        editing.redo()
        XCTAssertEqual(editing.layers.map(\.id), [before[3].id], "redo did not take the three again")
        editing.undo()
        editing.undo()
        XCTAssertEqual(editing.layers, Array(before.prefix(3)), "the drag was more than one step: the second undo went back past the three")
    }

    func testTheCirclePassesOverALayerBetweenTwoEventsOfTheDrag() {
        var editing = fourLines()
        let before = editing.layers
        erase(&editing, through: [CGPoint(x: 300, y: 120), CGPoint(x: 300, y: 270)])
        XCTAssertEqual(editing.layers.map(\.id), [before[3].id], "one jump of the pointer over three lines took fewer than three")
    }

    func testTheLayersAreStillThereWhileTheDragIsOpenAndTheTouchedOnesAreNamed() {
        var editing = fourLines()
        let before = editing.layers
        editing.beginErase(at: wayOfThree[0], radius: radius)
        XCTAssertTrue(editing.isBusy)
        XCTAssertEqual(editing.erased, [])
        editing.drag(to: wayOfThree[2], shift: false)
        XCTAssertEqual(editing.erased, Set(before.prefix(2).map(\.id)), "the screen is told which layers fade")
        XCTAssertEqual(editing.layers, before, "a layer went before the release")
        editing.end()
        XCTAssertEqual(editing.erased, [], "the touched set outlived the drag")
        XCTAssertFalse(editing.isBusy)
    }

    func testEscMidDragTakesNothingAndRecordsNoStep() {
        var editing = fourLines()
        let before = editing.layers
        editing.beginErase(at: wayOfThree[0], radius: radius)
        editing.drag(to: wayOfThree[3], shift: false)
        XCTAssertEqual(editing.escape(), .dropped)
        XCTAssertEqual(editing.layers, before)
        XCTAssertEqual(editing.erased, [])
        XCTAssertFalse(editing.isBusy)
        editing.end()
        XCTAssertEqual(editing.layers, before, "the release after the Esc took what was met")
        editing.undo()
        XCTAssertEqual(editing.layers, Array(before.prefix(3)), "the cancelled drag left a step: the undo did not take the last line drawn")
    }

    func testADragThatMeetsNothingIsNoStep() {
        var editing = fourLines()
        let before = editing.layers
        erase(&editing, through: [CGPoint(x: 460, y: 300), CGPoint(x: 480, y: 310)])
        XCTAssertEqual(editing.layers, before)
        editing.undo()
        XCTAssertEqual(editing.layers, Array(before.prefix(3)), "an empty drag recorded a step")
        var bare = AnnotationEditing(bounds: area)
        erase(&bare, through: wayOfThree)
        XCTAssertFalse(bare.canUndo, "an eraser on a bare picture recorded a step")
    }

    func testTheAreaAndTheSelectionOutsideThePathAreLeftAlone() {
        var editing = fourLines()
        _ = editing.press(at: CGPoint(x: 300, y: 350), tool: nil)
        editing.end()
        let kept = editing.layers[3].id
        XCTAssertEqual(editing.selectedID, kept, "the fixture selected nothing")
        erase(&editing, through: wayOfThree)
        XCTAssertEqual(editing.selectedID, kept, "an erase let go of a selected object it did not meet")
        XCTAssertEqual(editing.bounds, area)
        var met = fourLines()
        _ = met.press(at: CGPoint(x: 300, y: 200), tool: nil)
        met.end()
        XCTAssertNotNil(met.selectedID)
        erase(&met, through: wayOfThree)
        XCTAssertNil(met.selectedID, "a selected object that was erased is still selected")
    }

    func testTheCircleAndAClickAgreeOnWhereAMarkIs() {
        var editing = AnnotationEditing(bounds: area)
        let shapes: [(AnnotationTool, Bool)] = [(.rectangle, false), (.rectangle, true), (.ellipse, true), (.arrow, false), (.pencil, false)]
        for (tool, filled) in shapes {
            var style = AnnotationStyle.standard
            style.filled = filled
            editing.begin(tool, at: CGPoint(x: 200, y: 200), style: style)
            editing.drag(to: CGPoint(x: 260, y: 240), shift: false)
            editing.drag(to: CGPoint(x: 300, y: 260), shift: false)
            editing.end()
        }
        XCTAssertEqual(editing.layers.count, shapes.count, "the fixture lost a shape")
        var agreed = 0, touched = 0
        for layer in editing.layers {
            for x in stride(from: 150 as CGFloat, to: 350, by: 7) {
                for y in stride(from: 150 as CGFloat, to: 310, by: 7) {
                    let point = CGPoint(x: x, y: y)
                    let meets = AnnotationHit.touched(by: [point], radius: radius, in: [layer]).contains(layer.id)
                    let clicks = AnnotationHit.hits(layer, at: point, tolerance: radius)
                    XCTAssertEqual(meets, clicks, "\(layer.tool) filled \(layer.style.filled) at \(point): the eraser and the click differ")
                    agreed += 1
                    if meets { touched += 1 }
                }
            }
        }
        XCTAssertGreaterThan(touched, 100, "the sweep met almost nothing, so agreeing proves little")
        XCTAssertGreaterThan(agreed - touched, 100, "the sweep met everything, so agreeing proves little")
    }

    func testALayerWhollyOutsideTheAreaIsNotOnTheScreenAndIsNotTaken() {
        var editing = fourLines()
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 400, height: 200))
        let before = editing.layers
        // The area now ends at y 300, so the line at y 350 is not on the screen: a circle at y 300 is 50 points from it, and
        // one at y 345 is farther from the area than its radius reaches.
        erase(&editing, through: [CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 345)])
        XCTAssertEqual(editing.layers, before)
    }

    func testInputsNobodyFedIt() {
        var editing = fourLines()
        let before = editing.layers
        for radius in [0, -3, CGFloat.nan, CGFloat.infinity] {
            editing.beginErase(at: CGPoint(x: 300, y: 200), radius: radius)
            XCTAssertFalse(editing.isBusy, "radius \(radius) began a drag")
        }
        editing.beginErase(at: CGPoint(x: CGFloat.nan, y: 200), radius: radius)
        XCTAssertFalse(editing.isBusy)
        editing.beginErase(at: CGPoint(x: 300, y: 120), radius: radius)
        editing.drag(to: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), shift: false)
        editing.drag(to: CGPoint(x: 300, y: 270), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.map(\.id), [before[3].id], "a point that is no number broke the drag")
        // A pointer at 1e300 is a jump the walk is capped for: the drag must survive it, and takes nothing it passed nowhere near.
        var far = fourLines()
        far.beginErase(at: CGPoint(x: 300, y: 120), radius: radius)
        far.drag(to: CGPoint(x: 1e300, y: -1e300), shift: false)
        far.drag(to: CGPoint(x: 300, y: 120), shift: false)
        far.end()
        XCTAssertEqual(far.layers, before, "a far point took a layer or lost the drag")
        XCTAssertEqual(AnnotationHit.touched(by: [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: 0)], radius: 5, in: []), [])
        // Another edit during the drag waits for its end: the list is the one the step goes back to.
        var open = fourLines()
        open.beginErase(at: CGPoint(x: 300, y: 120), radius: radius)
        open.drag(to: CGPoint(x: 300, y: 270), shift: false)
        open.undo()
        open.deleteSelected()
        XCTAssertEqual(open.layers.count, 4, "an undo or a delete in the middle of the drag changed the list")
        open.end()
        XCTAssertEqual(open.layers.count, 1)
    }

    func testRemoveTakesTheIdsGivenInOneStepAndNothingForIdsThatAreNotThere() {
        var editing = fourLines()
        let before = editing.layers
        editing.remove([before[0].id, before[2].id, 9_999])
        XCTAssertEqual(editing.layers.map(\.id), [before[1].id, before[3].id])
        editing.undo()
        XCTAssertEqual(editing.layers, before)
        editing.remove([9_999])
        editing.undo()
        XCTAssertEqual(editing.layers, Array(before.prefix(3)), "ids that are not on the picture recorded a step")
    }
}
