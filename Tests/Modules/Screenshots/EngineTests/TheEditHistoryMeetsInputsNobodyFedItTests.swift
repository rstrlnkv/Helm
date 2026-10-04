import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The edits of an object meet what nobody fed them:** a long session of steps, a resize through
/// zero and past the held corner for every kind, a recolour to the ink it already had, a release
/// that never came, and a deleted layer that comes back where it was.
final class TheEditHistoryMeetsInputsNobodyFedItTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func make(_ tool: AnnotationTool) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(tool, at: CGPoint(x: 150, y: 150), style: .standard)
        for step in 1...30 { editing.drag(to: CGPoint(x: 150 + CGFloat(step) * 4, y: 150 + CGFloat(step) * 2 + CGFloat(step % 3) * 5), shift: false) }
        editing.end()
        return editing
    }

    private func select(_ editing: inout AnnotationEditing) {
        let box = editing.layers[0]
        let frame = box.frame
        var found: CGPoint?
        search: for x in stride(from: frame.minX, through: frame.maxX, by: 1) {
            for y in stride(from: frame.minY, through: frame.maxY, by: 1) where AnnotationHit.hits(box, at: CGPoint(x: x, y: y)) {
                found = CGPoint(x: x, y: y); break search
            }
        }
        guard let point = found else { return XCTFail("no point of the layer is a hit") }
        XCTAssertTrue(editing.press(at: point, tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "the click on a handle spot selected nothing")
    }

    private func undoAll(_ editing: inout AnnotationEditing) -> Int {
        var steps = 0
        while editing.canUndo { editing.undo(); steps += 1; if steps > 100_000 { break } }
        return steps
    }

    // MARK: History

    /// CLAUDE.md: bound any record that grows for the life of the app. A move of a 1024-point pencil
    /// copies every point, so each step is kilobytes; 3000 steps must not all be kept.
    func testTheUndoHistoryIsBounded() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.pencil, at: CGPoint(x: 120, y: 120), style: .standard)
        for step in 0..<3000 { editing.drag(to: CGPoint(x: 120 + CGFloat(step % 300), y: 120 + CGFloat(step % 170) + CGFloat(step / 20)), shift: false) }
        editing.end()
        XCTAssertEqual(editing.layers.count, 1, "no pencil, so the history below says nothing")
        XCTAssertGreaterThan(editing.layers[0].points.count, 100)
        for step in 0..<3000 {
            // Each press is on the layer where it is now: the moves alternate, so it stays under the pointer.
            let layer = editing.layers[0]
            let point = layer.points[layer.points.count / 2]
            XCTAssertTrue(editing.press(at: point, tool: nil))
            editing.drag(to: CGPoint(x: point.x + (step.isMultiple(of: 2) ? 5 : -5), y: point.y), shift: false)
            editing.end()
            if editing.selected == nil { break }
        }
        let steps = undoAll(&editing)
        XCTAssertGreaterThan(steps, 10, "the moves were no steps, so the bound below says nothing")
        XCTAssertLessThanOrEqual(steps, 1000, "\(steps) undo steps are kept for one session: the history grows without bound")
    }

    // MARK: Resize meets zero, negative, mirrored — every kind, every handle

    func testAResizeThroughZeroAndPastTheHeldCornerNeverLeavesAnUnusableOrEscapedLayer() {
        let targets: [CGPoint] = [
            CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 400), CGPoint(x: 100, y: 400), CGPoint(x: 500, y: 100),
            CGPoint(x: CGFloat.nan, y: 200), CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity), CGPoint(x: -1e300, y: 1e300),
            CGPoint(x: 150, y: 150), CGPoint(x: 150.4, y: 150.4), CGPoint(x: 0, y: 0),
        ]
        // The text is no drag and has no handle; its own cases are `TheTextIsALineTheEditorHoldsByItsAreaTests`.
        // An emoji is no drag either, and has no handle.
        for tool in AnnotationTool.allCases where tool != .text && tool != .emoji {
            let layer = make(tool).layers[0]
            XCTAssertTrue(layer.isUsable, "\(tool): the setup drew nothing")
            for (index, handle) in layer.handles.enumerated() {
                for target in targets {
                    var editing = make(tool)
                    select(&editing)
                    let original = editing.layers
                    var copy = editing
                    let setupSteps = undoAll(&copy)
                    XCTAssertTrue(editing.press(at: handle.point, tool: nil))
                    editing.drag(to: target, shift: false)
                    for layer in editing.layers {
                        XCTAssertTrue(layer.isUsable, "\(tool) handle \(index) to \(target): an unusable layer is on the picture")
                        XCTAssertEqual(layer.id, original[0].id)
                        let box = layer.frame
                        XCTAssertTrue(area.insetBy(dx: -0.001, dy: -0.001).contains(box), "\(tool) handle \(index) to \(target): left the selection: \(box)")
                    }
                    editing.end()
                    XCTAssertEqual(editing.layers.count, 1)
                    var after = editing
                    let steps = undoAll(&after)
                    XCTAssertTrue(steps == setupSteps || steps == setupSteps + 1, "\(tool) handle \(index) to \(target): \(steps - setupSteps) steps for one drag")
                    if steps == setupSteps + 1 {
                        editing.undo()
                        XCTAssertEqual(editing.layers, original, "\(tool) handle \(index) to \(target): undo did not restore the layer exactly")
                    } else {
                        XCTAssertEqual(editing.layers, original, "\(tool) handle \(index) to \(target): no step but the layer changed")
                    }
                }
            }
        }
    }

    // MARK: Recolour, delete

    func testARecolourThenUndoBringsTheOldInkBackExactly() {
        // The blur has no ink, so its recolour is no step at all (`TheBlurIsABoxTheEditorHoldsByItsAreaTests`).
        // A text is no drag: its recolour is in `TheTextIsALineTheEditorHoldsByItsAreaTests`. The spotlight has no ink either:
        // its recolour is no step (`TheSpotlightsShareOneDimTests`).
        for tool in AnnotationTool.allCases where tool != .blur && tool != .text && tool != .spotlight && tool != .emoji {
            var editing = make(tool)
            select(&editing)
            let before = editing.layers
            XCTAssertNil(before[0].style.color)
            editing.recolor(.blue)
            XCTAssertEqual(editing.layers[0].style.color, .blue)
            editing.recolor(.green)
            editing.undo(); editing.undo()
            XCTAssertEqual(editing.layers, before, "\(tool): undo did not bring the untouched style back (nil stays nil)")
            XCTAssertNil(editing.layers[0].style.color)
        }
    }

    /// Picking the ink the object already shows changes nothing the person can see, so ⌘Z must not
    /// have an invisible step to spend on it. (A default red rectangle has a nil colour, not .red.)
    func testARecolourToTheInkAlreadyShownIsNoStep() {
        var editing = make(.rectangle)
        select(&editing)
        XCTAssertEqual(editing.layers[0].style.ink(for: .rectangle), .red)
        editing.recolor(.red)
        XCTAssertEqual(undoAll(&editing), 1, "a recolour to the ink already shown is an invisible undo step")
    }

    func testADeletedLayerComesBackWithItsIdAtItsPlaceAndRedoDeletesItAgain() {
        for victim in 0..<3 {
            var editing = AnnotationEditing(bounds: area)
            for row in 0..<3 {
                editing.begin(.line, at: CGPoint(x: 120, y: 120 + CGFloat(row) * 60), style: .standard)
                editing.drag(to: CGPoint(x: 400, y: 120 + CGFloat(row) * 60), shift: false)
                editing.end()
            }
            let before = editing.layers
            XCTAssertEqual(before.count, 3)
            XCTAssertTrue(editing.press(at: CGPoint(x: 260, y: 120 + CGFloat(victim) * 60), tool: nil))
            editing.end()
            XCTAssertEqual(editing.selectedID, before[victim].id)
            editing.deleteSelected()
            XCTAssertEqual(editing.layers.map(\.id), before.map(\.id).enumerated().filter { $0.offset != victim }.map(\.element))
            editing.deleteSelected() // nothing selected: nothing, and no step
            editing.undo()
            XCTAssertEqual(editing.layers, before, "victim \(victim): not the same ids at the same z-order")
            editing.redo()
            XCTAssertEqual(editing.layers.count, 2)
            editing.undo()
            XCTAssertEqual(editing.layers, before)
        }
    }

    // MARK: Hidden handles, Esc chain

    func testAPressOnTheBodyOfTheSelectedObjectOverAnotherOnesCornerMovesTheSelectedOneAndNotTheOneUnderIt() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.rectangle, at: CGPoint(x: 150, y: 150), style: .standard)
        editing.drag(to: CGPoint(x: 250, y: 250), shift: false)
        editing.end()
        editing.begin(.rectangle, at: CGPoint(x: 140, y: 140), style: AnnotationStyle(filled: true))
        editing.drag(to: CGPoint(x: 300, y: 300), shift: false)
        editing.end()
        let lower = editing.layers[0], upper = editing.layers[1]
        XCTAssertTrue(editing.press(at: CGPoint(x: 142, y: 142), tool: nil)) // only the upper reaches there
        editing.end()
        XCTAssertEqual(editing.selectedID, upper.id)
        XCTAssertTrue(editing.press(at: CGPoint(x: 150, y: 150), tool: nil)) // the lower's corner, under the upper's body and no handle of the upper
        XCTAssertTrue(editing.isBusy)
        editing.drag(to: CGPoint(x: 260, y: 260), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers[0], lower, "the hidden lower one was edited through the selected upper one")
        XCTAssertEqual(editing.layers.count, 2)
    }

    func testTheEscChainIsDeselectThenAskThenCloseAndAnyInputInBetweenWithdrawsTheQuestion() {
        var editing = make(.rectangle)
        select(&editing)
        XCTAssertEqual(editing.escape(), .deselected)
        XCTAssertEqual(editing.escape(), .armed)
        editing.disarm()
        XCTAssertEqual(editing.escape(), .armed)
        XCTAssertEqual(editing.escape(), .close)
    }

    // MARK: A release that never came

    /// No release is guaranteed (CLAUDE.md). A press while an edit is open, with the old release lost, must not
    /// carry the object away from the new press's own travel, and the keys must not stay dead.
    func testALostReleaseDoesNotLeaveTheNextPressMovingTheOldObjectFromAStaleAnchor() {
        var editing = make(.rectangle)
        let layer = editing.layers[0]
        XCTAssertTrue(editing.press(at: layer.handles[0].point, tool: nil))
        editing.drag(to: CGPoint(x: layer.handles[0].point.x + 1, y: layer.handles[0].point.y + 1), shift: false) // the release never comes
        let held = editing.layers
        // The next press, far away on nothing, and a small drag.
        _ = editing.press(at: CGPoint(x: 480, y: 380), tool: nil)
        editing.drag(to: CGPoint(x: 482, y: 382), shift: false)
        XCTAssertEqual(editing.layers, held, "a drag that began on nothing moved the old object (its anchor was the old press)")
        editing.end()
        editing.undo()
        editing.deleteSelected()
        XCTAssertFalse(editing.isBusy)
    }
}

extension TheEditHistoryMeetsInputsNobodyFedItTests {
    /// Esc during a move cancels it: the object is back where the press took it, no step is left,
    /// and the gesture is over, so the next drag moves nothing.
    func testEscMidMoveCancelsTheMoveAndRestoresTheObject() {
        var editing = make(.rectangle)
        let before = editing.layers
        let steps = { var copy = editing; return self.undoAll(&copy) }()
        let edge = CGPoint(x: before[0].frame.minX, y: before[0].frame.midY)
        XCTAssertTrue(editing.press(at: edge, tool: nil))
        editing.drag(to: CGPoint(x: edge.x + 40, y: edge.y + 30), shift: false)
        XCTAssertNotEqual(editing.layers, before, "the drag moved nothing, so the cancel below says nothing")
        XCTAssertEqual(editing.escape(), .deselected)
        XCTAssertEqual(editing.layers, before)
        XCTAssertFalse(editing.isBusy)
        editing.drag(to: CGPoint(x: edge.x + 80, y: edge.y + 60), shift: false)
        XCTAssertEqual(editing.layers, before, "a drag after Esc went on moving the object")
        editing.end()
        XCTAssertEqual(undoAll(&editing), steps, "the cancelled move left a step")
    }
}
