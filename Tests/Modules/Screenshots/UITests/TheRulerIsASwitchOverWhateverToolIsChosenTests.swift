import AppKit
import CoreGraphics
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The ruler is a switch, not a tool and not a mode:** its object is raised while it is on the picture, with any tool
/// chosen and with the eraser; U and a second click on the raised object lower it; a press on its strip takes the ruler along and
/// draws nothing, unless the eraser is on, which erases layers and leaves the ruler where it is; a stroke begun at its edge
/// is straightened by the pen and left as the pointer made it by the arrow.
///
/// What it would print if it failed totally: a ruler that was a tool fails `palette.tool`; one that took the press for a
/// stroke fails the layer count after the drag by the strip.
@MainActor
final class TheRulerIsASwitchOverWhateverToolIsChosenTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let middle = CGPoint(x: 400, y: 300)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func opened() throws -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        overlay?.close()
        results = []
        let rig = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        return rig
    }

    private func drag(_ rig: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView), from: CGPoint, to: CGPoint) {
        rig.overlay.mouseDown(on: rig.display, at: from, flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: to, flags: [])
        rig.overlay.mouseUp(on: rig.display)
    }

    func testTheRulerIsRaisedUnderEveryToolAndItsSecondClickAndItsKeyLowerIt() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.pencil))
        rig.overlay.perform(.toggleRuler)
        XCTAssertTrue(rig.overlay.palette.ruler)
        XCTAssertEqual(rig.overlay.palette.tool, .pencil, "the ruler took the tool's place")
        rig.overlay.perform(.tool(.highlighter))
        XCTAssertTrue(rig.overlay.palette.ruler, "choosing a tool lowered the ruler")
        rig.overlay.perform(.erase)
        XCTAssertTrue(rig.overlay.palette.ruler, "the eraser lowered the ruler")
        XCTAssertTrue(rig.overlay.palette.erasing)
        rig.overlay.perform(.select)
        XCTAssertTrue(rig.overlay.palette.ruler, "Select lowered the ruler")
        rig.overlay.perform(EditorKeys.action(keyCode: UInt16(EditorKeys.rulerKeyCode), flags: []))
        XCTAssertFalse(rig.overlay.palette.ruler, "the key did not lower the ruler")
        XCTAssertNil(rig.overlay.rulerOnThePicture)
        rig.overlay.perform(.toggleRuler)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, middle, "the ruler did not come back to the middle")
        // The thickness and opacity pop-over is not the ruler's: a second click on its object only lowers it.
        rig.overlay.perform(.toggleRuler)
        XCTAssertFalse(rig.overlay.popoverIsOpen)
        XCTAssertNil(rig.overlay.rulerOnThePicture)
    }

    func testAPressOnTheStripTakesTheRulerAndDrawsNothingWithAToolAndWithNone() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        let tools: [AnnotationTool?] = [.pen, .line, .text, nil]
        for tool in tools {
            if let tool { rig.overlay.perform(.tool(tool)) } else { rig.overlay.perform(.select) }
            let from = rig.overlay.rulerOnThePicture?.center ?? .zero
            drag(rig, from: from, to: CGPoint(x: from.x + 10, y: from.y + 12))
            XCTAssertEqual(rig.view.drawnShapes.count, 0, "a press on the strip with \(String(describing: tool)) drew")
            XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, CGPoint(x: from.x + 10, y: from.y + 12), "the strip did not follow with \(String(describing: tool))")
            XCTAssertFalse(rig.overlay.palette.canUndo)
        }
    }

    func testTheEraserErasesLayersUnderTheStripAndLeavesTheRulerWhereItIs() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.line))
        drag(rig, from: CGPoint(x: 330, y: 300), to: CGPoint(x: 470, y: 300))
        XCTAssertEqual(rig.view.drawnShapes.count, 1)
        rig.overlay.perform(.toggleRuler)
        rig.overlay.perform(.erase)
        let before = rig.overlay.rulerOnThePicture
        drag(rig, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 420, y: 300))
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "the eraser did not take the layer under the strip")
        XCTAssertEqual(rig.overlay.rulerOnThePicture, before, "the eraser dragged the ruler")
        XCTAssertTrue(rig.overlay.palette.ruler)
        XCTAssertTrue(rig.overlay.palette.erasing)
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "one undo did not bring the erased layer back")
        XCTAssertEqual(rig.overlay.rulerOnThePicture, before, "an undo moved the ruler")
    }

    func testAPenStrokeBegunAtTheEdgeIsStraightAndAnArrowFromTheSamePlaceIsNot() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        let upper = try XCTUnwrap(rig.overlay.rulerOnThePicture).edges[0].from.y
        rig.overlay.perform(.tool(.pen))
        drag(rig, from: CGPoint(x: 330, y: upper - 8), to: CGPoint(x: 470, y: upper - 40))
        rig.overlay.perform(.tool(.arrow))
        drag(rig, from: CGPoint(x: 330, y: upper - 8), to: CGPoint(x: 470, y: upper - 40))
        rig.overlay.perform(.exit(.copy))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("not an edit: \(results)") }
        XCTAssertEqual(layers.map(\.tool), [.pen, .arrow])
        XCTAssertEqual(layers[0].end.y, upper, accuracy: 1e-6, "the pen's stroke is not on the ruler's edge")
        XCTAssertEqual(layers[1].end, CGPoint(x: 470, y: upper - 40), "the arrow read the ruler")
        XCTAssertEqual(layers[1].start, CGPoint(x: 330, y: upper - 8))
    }
}
