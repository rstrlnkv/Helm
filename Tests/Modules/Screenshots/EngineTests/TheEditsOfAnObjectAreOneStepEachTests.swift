import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **Select, move, resize, recolour and delete are edits of a value, and each is one undo step.**
/// Undo walks snapshots of the layer list, so an edit in place is a step like a new layer is, a
/// drag is one step however many events it had, and every layer keeps its id through all of it.
final class TheEditsOfAnObjectAreOneStepEachTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func draw(_ editing: inout AnnotationEditing, _ tool: AnnotationTool = .rectangle,
                      from: CGPoint = CGPoint(x: 150, y: 150), to: CGPoint = CGPoint(x: 250, y: 220),
                      style: AnnotationStyle = .standard) {
        editing.begin(tool, at: from, style: style)
        editing.drag(to: to, shift: false)
        editing.end()
    }

    /// A rectangle (150,150)-(250,220), drawn and selected by a click on its edge.
    private func selectedRectangle() -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        click(&editing, CGPoint(x: 200, y: 150))
        XCTAssertNotNil(editing.selected, "the click selected nothing, so every edit below is empty")
        return editing
    }

    private func click(_ editing: inout AnnotationEditing, _ point: CGPoint, tool: AnnotationTool? = nil) {
        XCTAssertTrue(editing.press(at: point, tool: tool))
        editing.end()
    }

    private func dragged(_ editing: inout AnnotationEditing, from: CGPoint, through: [CGPoint], tool: AnnotationTool? = nil) {
        XCTAssertTrue(editing.press(at: from, tool: tool))
        for point in through { editing.drag(to: point, shift: false) }
        editing.end()
    }

    // MARK: Click or drag

    func testAClickOnAnObjectSelectsItWithAnyToolAndAddsNothing() {
        // The steps tool is the one exception: its click places a step wherever it lands
        // (`TheStepsAreNumberedByTheirOrderTests.testAClickOutsideTheAreaPlacesNothingAndAClickOnAnotherLayerStillPlaces`).
        for tool in [nil] + AnnotationTool.allCases.filter({ $0 != .step }).map(Optional.some) {
            var editing = AnnotationEditing(bounds: area)
            draw(&editing)
            let id = editing.layers[0].id
            click(&editing, CGPoint(x: 200, y: 150), tool: tool)
            XCTAssertEqual(editing.selectedID, id, "\(String(describing: tool)): the click did not select")
            XCTAssertEqual(editing.layers.count, 1, "\(String(describing: tool)): a click drew")
            XCTAssertNil(editing.draft)
            click(&editing, CGPoint(x: 400, y: 380), tool: tool)
            XCTAssertNil(editing.selectedID, "\(String(describing: tool)): a click on the empty picture kept the selection")
        }
    }

    func testADragWithAToolDrawsEvenFromOnTopOfAnObject() {
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 200, y: 150), through: [CGPoint(x: 300, y: 300)], tool: .line)
        XCTAssertEqual(editing.layers.map(\.tool), [.rectangle, .line], "a drag from an object did not draw")
        XCTAssertEqual(editing.layers[1].start, CGPoint(x: 200, y: 150))
        XCTAssertNil(editing.selectedID, "the drawn object is not selected, so a colour pick is still the next one's")
    }

    func testTheThresholdSplitsAClickFromADrawing() {
        let limit = AnnotationEditing.clickTravel
        for (travel, drawn) in [(limit - 0.5, false), (limit, true)] {
            var editing = AnnotationEditing(bounds: area)
            dragged(&editing, from: CGPoint(x: 300, y: 300), through: [CGPoint(x: 300 + travel, y: 300)], tool: .line)
            XCTAssertEqual(editing.layers.count, drawn ? 1 : 0, "a drag of \(travel) points")
        }
        // The travel is the farthest the pointer went and not where it ended: a box dragged out and back
        // is a drawing with nothing in it, not a click, so it neither draws nor lets go of the selection.
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 300, y: 300), through: [CGPoint(x: 340, y: 300), CGPoint(x: 300, y: 300)], tool: .rectangle)
        XCTAssertEqual(editing.layers.count, 1)
        XCTAssertNotNil(editing.selectedID, "an out-and-back drag was read as a click on the empty picture")
    }

    func testWithNoToolAPressOnTheBodyTakesAndMovesItAndAPressOnNothingLetsGo() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertFalse(editing.press(at: CGPoint(x: 300, y: 300), tool: nil), "no tool and nothing drawn is the caller's own press")
        draw(&editing, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 250, y: 220), style: .standard)
        let id = editing.layers[0].id
        dragged(&editing, from: CGPoint(x: 200, y: 150), through: [CGPoint(x: 230, y: 180)])
        XCTAssertEqual(editing.selectedID, id)
        XCTAssertEqual(editing.layers[0].start, CGPoint(x: 180, y: 180), "the body did not move with the pointer")
        XCTAssertTrue(editing.press(at: CGPoint(x: 450, y: 380), tool: nil), "with layers the press is the editor's")
        editing.end()
        XCTAssertNil(editing.selectedID)
    }

    // MARK: Move

    func testAMoveIsOneStepWhateverItsEventsAndStaysInsideTheSelection() {
        var editing = selectedRectangle()
        let id = editing.layers[0].id, before = editing.layers
        dragged(&editing, from: CGPoint(x: 200, y: 150),
                through: (1...30).map { CGPoint(x: 200 + CGFloat($0) * 4, y: 150 + CGFloat($0)) })
        XCTAssertEqual(editing.layers[0].start, CGPoint(x: 270, y: 180))
        XCTAssertEqual(editing.layers[0].id, id, "a move changed the layer's identity")
        editing.undo()
        XCTAssertEqual(editing.layers, before, "one undo did not undo the whole drag")
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "the drag left more than one step: the second undo took back only part of it")
        XCTAssertFalse(editing.canUndo)
        editing.redo(); editing.redo()
        XCTAssertEqual(editing.layers[0].start, CGPoint(x: 270, y: 180))

        // Far past every edge: held at the selection's, shape intact.
        dragged(&editing, from: CGPoint(x: 320, y: 180), through: [CGPoint(x: 5000, y: 5000)])
        XCTAssertEqual(editing.layers[0].frame.maxX, area.maxX, accuracy: 0.001)
        XCTAssertEqual(editing.layers[0].frame.maxY, area.maxY, accuracy: 0.001)
        XCTAssertEqual(editing.layers[0].frame.size, CGSize(width: 100, height: 70), "a clamped move changed the size")
        dragged(&editing, from: CGPoint(x: 450, y: 330), through: [CGPoint(x: -5000, y: -5000)])
        XCTAssertEqual(editing.layers[0].frame.origin, area.origin, "a move past the corner left the selection")
    }

    func testAPressAndReleaseWithNoTravelIsNoStep() {
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 200, y: 150), through: [])
        XCTAssertEqual(editing.layers.count, 1)
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "the first undo took back the click that moved nothing and not the drawing")
        XCTAssertFalse(editing.canUndo)
    }

    func testAMovedFreehandStrokeKeepsEveryPoint() {
        var editing = AnnotationEditing(bounds: area)
        dragged(&editing, from: CGPoint(x: 150, y: 150), through: (1...20).map { CGPoint(x: 150 + CGFloat($0) * 5, y: 150 + CGFloat($0 % 5) * 3) }, tool: .pencil)
        let drawn = editing.layers[0]
        dragged(&editing, from: CGPoint(x: 200, y: 153), through: [CGPoint(x: 220, y: 173)])
        let moved = editing.layers[0]
        XCTAssertEqual(moved.points.count, drawn.points.count)
        XCTAssertEqual(moved.points.map { CGPoint(x: $0.x - 20, y: $0.y - 20) }, drawn.points)
    }

    // MARK: Resize

    func testABoxIsResizedByACornerAndTheOppositeOneStays() {
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 250, y: 220), through: [CGPoint(x: 300, y: 250), CGPoint(x: 350, y: 300)])
        let box = editing.layers[0].frame
        XCTAssertEqual(box, CGRect(x: 150, y: 150, width: 200, height: 150), "the held corner moved or the dragged one did not arrive")
        editing.undo()
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 150, y: 150, width: 100, height: 70), "a resize was more than one step")
        // Dragged out of the selection: held at its edge.
        editing.redo()
        dragged(&editing, from: CGPoint(x: 350, y: 300), through: [CGPoint(x: 9000, y: 9000)])
        XCTAssertEqual(editing.layers[0].frame.maxX, area.maxX)
        XCTAssertEqual(editing.layers[0].frame.maxY, area.maxY)
        XCTAssertEqual(editing.layers[0].frame.minX, 150, "the held corner moved")
    }

    func testAHandleIsTakenBeforeTheToolDraws() {
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 250, y: 220), through: [CGPoint(x: 300, y: 300)], tool: .line)
        XCTAssertEqual(editing.layers.count, 1, "a drag from a handle drew a line instead of resizing")
        XCTAssertEqual(editing.layers[0].frame.maxX, 300)
    }

    func testADragAcrossTheHeldCornerMirrorsAndACollapseKeepsTheLastUsableShape() {
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 250, y: 220), through: [CGPoint(x: 100, y: 120)])
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 100, y: 120, width: 50, height: 30), "across the held corner is a mirrored box")
        // To the held corner's own column: no width, so not a shape; the object keeps the last one it had.
        dragged(&editing, from: CGPoint(x: 100, y: 120), through: [CGPoint(x: 120, y: 125), CGPoint(x: 150, y: 125)])
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 120, y: 125, width: 30, height: 25))
        XCTAssertTrue(editing.layers[0].isUsable)
    }

    func testAStraightOneIsResizedByItsEnds() {
        for tool in [AnnotationTool.line, .arrow] {
            var editing = AnnotationEditing(bounds: area)
            draw(&editing, tool, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 150))
            click(&editing, CGPoint(x: 225, y: 150))
            XCTAssertNotNil(editing.selected, "\(tool) was not selected")
            XCTAssertEqual(editing.selected?.handles.count, 2)
            dragged(&editing, from: CGPoint(x: 300, y: 150), through: [CGPoint(x: 350, y: 250)])
            XCTAssertEqual(editing.layers[0].end, CGPoint(x: 350, y: 250), "\(tool)")
            XCTAssertEqual(editing.layers[0].start, CGPoint(x: 150, y: 150), "\(tool): the other end moved")
            dragged(&editing, from: CGPoint(x: 150, y: 150), through: [CGPoint(x: 120, y: 140)])
            XCTAssertEqual(editing.layers[0].start, CGPoint(x: 120, y: 140), "\(tool)")
        }
    }

    func testAFreehandStrokeIsScaledInsideItsBoundingBox() throws {
        var editing = AnnotationEditing(bounds: area)
        let trail = (0...20).map { CGPoint(x: 150 + CGFloat($0) * 5, y: 150 + CGFloat($0 % 2) * 20) }
        dragged(&editing, from: trail[0], through: Array(trail.dropFirst()), tool: .pencil)
        // The curve passes through the midpoints of its points, not through the points.
        click(&editing, CGPoint(x: 197.5, y: 160))
        let drawn = try XCTUnwrap(editing.selected)
        XCTAssertEqual(drawn.handles.count, 4, "a freehand stroke is held by its box")
        let box = drawn.frame
        dragged(&editing, from: CGPoint(x: box.maxX, y: box.maxY), through: [CGPoint(x: box.minX + box.width * 2, y: box.minY + box.height * 3)])
        let grown = editing.layers[0]
        XCTAssertEqual(grown.points.count, drawn.points.count, "scaling dropped points")
        XCTAssertEqual(grown.frame.width, box.width * 2, accuracy: 0.001)
        XCTAssertEqual(grown.frame.height, box.height * 3, accuracy: 0.001)
        XCTAssertEqual(grown.frame.origin, box.origin, "the held corner moved")
        XCTAssertEqual(grown.points[5].x, box.minX + (drawn.points[5].x - box.minX) * 2, accuracy: 0.001, "a point was not scaled with the box")
    }

    // MARK: Recolour, thickness, fill, delete

    func testARecolourOfTheSelectedIsOneStepAndLeavesTheOthersAlone() {
        var editing = selectedRectangle()
        draw(&editing, .line, from: CGPoint(x: 150, y: 300), to: CGPoint(x: 300, y: 300))
        click(&editing, CGPoint(x: 200, y: 150))
        let id = editing.layers[0].id
        editing.recolor(.blue)
        XCTAssertEqual(editing.layers[0].style.color, .blue)
        XCTAssertNil(editing.layers[1].style.color, "another object took the colour")
        XCTAssertEqual(editing.layers[0].id, id)
        editing.recolor(.blue)
        editing.undo()
        XCTAssertNil(editing.layers[0].style.color, "one undo did not take the recolour back, so the same colour twice was a step")
        XCTAssertEqual(editing.layers.count, 2, "the undo took more than the recolour")
        editing.redo()
        XCTAssertEqual(editing.layers[0].style.color, .blue)
    }

    func testThicknessAndFillAreEditsAndFillIsTheBoxesOnly() {
        var editing = selectedRectangle()
        editing.setThickness(.thick)
        editing.setFilled(true)
        XCTAssertEqual(editing.layers[0].style, AnnotationStyle(color: nil, thickness: .thick, filled: true))
        editing.undo(); editing.undo()
        XCTAssertEqual(editing.layers[0].style, .standard, "two edits are two steps")
        XCTAssertTrue(editing.canUndo, "the drawing itself is still a step")
        var line = AnnotationEditing(bounds: area)
        draw(&line, .line, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 150))
        click(&line, CGPoint(x: 200, y: 150))
        line.setFilled(true)
        XCTAssertFalse(line.layers[0].style.filled, "a line was filled")
        line.undo()
        XCTAssertTrue(line.layers.isEmpty, "the refused fill was a step")
    }

    func testNothingSelectedMeansTheEditsAreNoStep() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        editing.recolor(.green); editing.setThickness(.thick); editing.setFilled(true); editing.deleteSelected()
        XCTAssertEqual(editing.layers.count, 1)
        XCTAssertEqual(editing.layers[0].style, .standard)
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "an edit with nothing selected was a step of its own")
    }

    func testADeleteIsOneStepAndUndoBringsTheObjectBackInPlaceWithItsId() {
        var editing = AnnotationEditing(bounds: area)
        draw(&editing, .rectangle, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 250, y: 220))
        draw(&editing, .line, from: CGPoint(x: 150, y: 300), to: CGPoint(x: 300, y: 300))
        draw(&editing, .arrow, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 300, y: 350))
        let all = editing.layers
        click(&editing, CGPoint(x: 225, y: 300))
        XCTAssertEqual(editing.selectedID, all[1].id)
        editing.deleteSelected()
        XCTAssertEqual(editing.layers.map(\.id), [all[0].id, all[2].id])
        XCTAssertNil(editing.selectedID)
        editing.undo()
        XCTAssertEqual(editing.layers, all, "undo did not bring the object back whole and in its place")
        editing.redo()
        XCTAssertEqual(editing.layers.count, 2)
    }

    func testIdsAreUniqueAndSurviveEveryEditUndoAndRedo() {
        var editing = AnnotationEditing(bounds: area)
        for index in 0..<4 {
            draw(&editing, .rectangle, from: CGPoint(x: 120 + CGFloat(index) * 60, y: 120), to: CGPoint(x: 160 + CGFloat(index) * 60, y: 200))
        }
        let ids = editing.layers.map(\.id)
        XCTAssertEqual(Set(ids).count, 4, "two layers share an id")
        click(&editing, CGPoint(x: 140, y: 120))
        editing.recolor(.purple)
        dragged(&editing, from: CGPoint(x: 140, y: 120), through: [CGPoint(x: 160, y: 140)])
        dragged(&editing, from: CGPoint(x: 160, y: 220), through: [CGPoint(x: 180, y: 260)])
        let final = editing.layers
        for _ in 0..<3 { editing.undo() } // the second move, the first, the recolour
        XCTAssertEqual(editing.layers.map(\.id), ids, "undo changed an id")
        for _ in 0..<3 { editing.redo() }
        XCTAssertEqual(editing.layers, final)
        XCTAssertEqual(editing.layers.map(\.id), ids)
        XCTAssertNotNil(editing.selected, "the selection did not survive an undo that left its layer alone")
        editing.deleteSelected()
        draw(&editing, .line, from: CGPoint(x: 120, y: 300), to: CGPoint(x: 200, y: 300))
        XCTAssertFalse(ids.contains(editing.layers.last!.id), "a new layer took the id of one that had been deleted")
    }

    func testAnEditClearsWhatCouldHaveBeenRedoneAndUndoingTheSelectedLayerDropsTheSelection() {
        for edit in ["recolor", "move", "delete", "draw"] {
            var editing = selectedRectangle()
            draw(&editing, .line, from: CGPoint(x: 150, y: 300), to: CGPoint(x: 300, y: 300))
            editing.undo()
            XCTAssertTrue(editing.canRedo, "\(edit): the setup has no future")
            click(&editing, CGPoint(x: 200, y: 150))
            XCTAssertTrue(editing.canRedo, "\(edit): a click cleared the future")
            switch edit {
            case "recolor": editing.recolor(.black)
            case "move": dragged(&editing, from: CGPoint(x: 200, y: 150), through: [CGPoint(x: 210, y: 160)])
            case "delete": editing.deleteSelected()
            default: draw(&editing, .line, from: CGPoint(x: 150, y: 350), to: CGPoint(x: 300, y: 350))
            }
            XCTAssertFalse(editing.canRedo, "\(edit) left the old future redoable")
        }
        var editing = AnnotationEditing(bounds: area)
        draw(&editing)
        click(&editing, CGPoint(x: 200, y: 150))
        editing.undo()
        XCTAssertNil(editing.selectedID, "the selection outlived its layer")
        editing.redo()
        XCTAssertNil(editing.selectedID)
    }

    // MARK: Esc

    func testEscLetsGoOfTheSelectionBeforeItAsksAnything() {
        var editing = selectedRectangle()
        XCTAssertEqual(editing.escape(), .deselected)
        XCTAssertNil(editing.selectedID)
        XCTAssertFalse(editing.isArmed, "the press that let go of the selection also asked the question")
        XCTAssertEqual(editing.escape(), .armed)
        click(&editing, CGPoint(x: 200, y: 150))
        XCTAssertFalse(editing.isArmed, "a click did not withdraw the question")
        XCTAssertEqual(editing.escape(), .deselected, "a selection made after the question comes first again")
        XCTAssertEqual(editing.escape(), .armed)
        XCTAssertEqual(editing.escape(), .close)
    }

    // MARK: The file

    func testTheExportDrawsTheEditedListWhereTheEditsPutIt() throws {
        var editing = selectedRectangle()
        dragged(&editing, from: CGPoint(x: 200, y: 150), through: [CGPoint(x: 260, y: 230)])
        editing.recolor(.blue)
        let white = makeImage(width: 400, height: 300, red: 255, green: 255, blue: 255)
        let out = try XCTUnwrap(CaptureSession.draw(editing.layers, over: white, at: .zero, scale: 1, display: white))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let context = CGContext(data: nil, width: out.width, height: out.height, bitsPerComponent: 8, bytesPerRow: out.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(out, in: CGRect(x: 0, y: 0, width: out.width, height: out.height))
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: bytes + (y * out.width + x) * 4, count: 3))
        }
        // The rectangle was (150,150)-(250,220) and is now (210,230)-(310,300), in a cut that starts at 0,0:
        // the middle of its top edge is at (260,230) and was at (200,150).
        let moved = pixel(260, 230), old = pixel(200, 150)
        XCTAssertLessThan(moved[0], 60, "the moved rectangle is not blue where the edit put it: \(moved)")
        XCTAssertGreaterThan(moved[2], 200, "it is not blue: \(moved)")
        XCTAssertEqual(old, [255, 255, 255], "the file still shows the object where it was")
    }
}
