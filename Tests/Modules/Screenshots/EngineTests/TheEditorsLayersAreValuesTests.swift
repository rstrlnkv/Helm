import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The editor's layers are a value, and every rule of it is a function of what was
/// done.** No keyboard, no timer, no clock.
final class TheEditorsLayersAreValuesTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func draw(_ editing: inout AnnotationEditing, _ tool: AnnotationTool = .arrow,
                      from: CGPoint = CGPoint(x: 120, y: 120), to: CGPoint = CGPoint(x: 220, y: 180)) {
        editing.begin(tool, at: from)
        editing.drag(to: to, shift: false)
        editing.end()
    }

    func testADrawnLayerIsKeptAndUndoAndRedoWalkTheList() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        draw(&editing, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 300))
        XCTAssertEqual(editing.layers.map(\.tool), [.arrow, .rectangle])
        editing.undo()
        XCTAssertEqual(editing.layers.map(\.tool), [.arrow])
        XCTAssertTrue(editing.canRedo)
        editing.redo()
        XCTAssertEqual(editing.layers.map(\.tool), [.arrow, .rectangle], "redo did not bring the layer back in its place")
        editing.undo(); editing.undo(); editing.undo()
        XCTAssertTrue(editing.layers.isEmpty)
        XCTAssertFalse(editing.canUndo)
        editing.redo(); editing.redo(); editing.redo()
        XCTAssertEqual(editing.layers.count, 2, "redo past the end invented a layer")
    }

    func testANewLayerClearsWhatCouldHaveBeenRedone() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        editing.undo()
        XCTAssertTrue(editing.canRedo)
        draw(&editing, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 300))
        XCTAssertFalse(editing.canRedo, "a new layer left the old future redoable")
        editing.redo()
        XCTAssertEqual(editing.layers.map(\.tool), [.rectangle])
    }

    func testAZeroSizeDraftNeverBecomesALayer() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.arrow, at: CGPoint(x: 200, y: 200))
        XCTAssertNotNil(editing.draft, "the draft did not exist, so the claim below is empty")
        editing.end()
        XCTAssertTrue(editing.layers.isEmpty, "a click became an arrow")
        XCTAssertNil(editing.draft)
        // A rectangle with a width and no height is a line nobody asked for.
        draw(&editing, .rectangle, from: CGPoint(x: 150, y: 200), to: CGPoint(x: 300, y: 200))
        XCTAssertTrue(editing.layers.isEmpty, "a rectangle with no height became a layer")
        // A layer that does not come does not clear the future either.
        draw(&editing)
        editing.undo()
        editing.begin(.arrow, at: CGPoint(x: 200, y: 200)); editing.end()
        XCTAssertTrue(editing.canRedo, "an empty draft cleared redo")
    }

    func testAPointThatIsNotANumberIsDroppedAndOneOutsideIsTakenToTheEdge() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.arrow, at: CGPoint(x: CGFloat.nan, y: 120))
        XCTAssertNil(editing.draft, "a draft began on a point that is not a number")
        editing.begin(.arrow, at: CGPoint(x: 120, y: 120))
        editing.drag(to: CGPoint(x: CGFloat.infinity, y: 150), shift: false)
        XCTAssertEqual(editing.draft?.end, CGPoint(x: 120, y: 120), "a point that is not finite moved the draft")
        editing.drag(to: CGPoint(x: 9_999, y: -50), shift: false)
        XCTAssertEqual(editing.draft?.end, CGPoint(x: 500, y: 100), "a point outside the selection was not taken to its edge")
    }

    // MARK: The Esc rule

    func testEscWithNothingOnThePictureClosesAtOnce() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertEqual(editing.escape(), .close)
    }

    func testEscWithLayersArmsAndASecondCloses() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        XCTAssertEqual(editing.escape(), .armed)
        XCTAssertTrue(editing.isArmed)
        XCTAssertEqual(editing.escape(), .close)
    }

    /// The question has no clock: the value keeps it asked until an input
    /// withdraws it, so a second press after any interval closes.
    func testTheQuestionStaysAskedUntilAnotherInputWithdrawsIt() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        XCTAssertEqual(editing.escape(), .armed)
        XCTAssertTrue(editing.isArmed, "the plate the person is looking at is not the question being asked")
        XCTAssertEqual(editing.escape(), .close, "a second press, however late, only asked again")
    }

    func testAnyOtherInputWithdrawsTheQuestion() {
        for input in ["draw", "undo", "redo", "disarm"] {
            var editing = AnnotationEditing(bounds: area)
            draw(&editing); draw(&editing, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 300))
            editing.undo()
            XCTAssertEqual(editing.escape(), .armed)
            switch input {
            case "draw": editing.begin(.arrow, at: CGPoint(x: 200, y: 200))
            case "undo": editing.undo(); editing.redo()
            case "redo": editing.redo()
            default: editing.disarm()
            }
            XCTAssertFalse(editing.isArmed, "\(input) left the question standing")
        }
    }

    func testUndoBackToEmptyRestoresTheImmediateClose() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        XCTAssertEqual(editing.escape(), .armed)
        editing.undo()
        XCTAssertEqual(editing.escape(), .close, "an empty picture still asked a question")
    }

    // MARK: The shapes

    func testTheArrowIsAFilledTaperedPolygonThatEndsAtTheTip() {
        let arrow = Annotation(tool: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        XCTAssertTrue(arrow.isFilled)
        let box = arrow.outline.boundingBoxOfPath
        XCTAssertEqual(box.maxX, 100, accuracy: 0.001, "the tip is not at the end")
        XCTAssertEqual(box.minX, 0, accuracy: 0.001)
        XCTAssertEqual(box.height, Annotation.shaft * 3, accuracy: 0.001, "the head is not three shafts wide")
        XCTAssertFalse(Annotation(tool: .rectangle, start: .zero, end: CGPoint(x: 9, y: 9)).isFilled)
    }
}
