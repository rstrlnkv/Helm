import AppKit
import CoreGraphics
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The eraser in the overlay, fed what its first tests did not:** an E in the middle of another tool's drawing drag, a
/// tool key in the middle of an erase drag, an exit with the drag still open, a typed text placed by the very action that
/// raises the eraser, a pop-over open when E comes, a handle of the area and a right click while the eraser is up, a second
/// press with no release between, and a press outside the area.
///
/// What it would print if it failed totally: an eraser that did nothing leaves four shapes after each drag and fails the
/// first count of the erase tests; one that lost the drawing drag fails `testEInTheMiddleOfADrawingDragLosesNoStroke`.
@MainActor
final class TheEraserMeetsInputsNobodyFedItTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)

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

    private func fourLines() throws -> (overlay: CaptureOverlay, display: DisplayID, view: OverlayView) {
        let rig = try opened()
        rig.overlay.perform(.tool(.line))
        for y in [150, 200, 250, 350] as [CGFloat] {
            rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 150, y: y), flags: [])
            rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 450, y: y), flags: [])
            rig.overlay.mouseUp(on: rig.display)
        }
        XCTAssertEqual(rig.view.drawnShapes.count, 4)
        return rig
    }

    func testEInTheMiddleOfADrawingDragLosesNoStroke() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.line))
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 150, y: 200), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 400, y: 200), flags: [])
        rig.overlay.perform(.erase)
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 450, y: 200), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "the stroke under the pointer was lost or doubled")
        XCTAssertTrue(rig.overlay.isErasing)
        // The next press erases it.
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 203), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "a click of the eraser on the stroke did not take it")
    }

    func testAToolKeyInTheMiddleOfAnEraseDragLetsTheDragFinish() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 120), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 300, y: 220), flags: [])
        rig.overlay.perform(.tool(.pen))
        XCTAssertFalse(rig.overlay.isErasing)
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 300, y: 270), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "the drag did not finish as an erase after the tool key")
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 4, "it was more than one step")
        XCTAssertEqual(rig.overlay.palette.tool, .pen)
    }

    func testEInTheMiddleOfAnEraseDragPutsItDownAndTheDragStillFinishes() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 120), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 300, y: 220), flags: [])
        rig.overlay.perform(.erase)
        XCTAssertFalse(rig.overlay.isErasing)
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 2, "the release did not take what the drag met before the E")
    }

    func testAnExitWithTheDragStillOpenHandsOverThePictureWithoutTheLayersItMet() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 120), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 300, y: 270), flags: [])
        XCTAssertEqual(rig.view.drawnShapes.map(\.opacity), [0.3, 0.3, 0.3, 1])
        rig.overlay.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.last else { return XCTFail("nothing handed over: \(results)") }
        XCTAssertEqual(layers.count, 1, "the layers shown fading were delivered whole, or all of them went")
    }

    func testTypedTextIsPlacedByTheActionThatRaisesTheEraserAndThenTheEraserTakesIt() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.text))
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 200, y: 220), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        let field = try XCTUnwrap(rig.view.textField)
        field.insertText("keep", replacementRange: NSRange(location: NSNotFound, length: 0))
        rig.overlay.perform(.erase)
        XCTAssertFalse(rig.overlay.isTyping, "the field stayed open under the eraser")
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "the typed text was not placed")
        XCTAssertNil(rig.view.textField)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 205, y: 215), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "the eraser did not take the text it was raised over")
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 1)
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "the text's placing and its erasing were one step")
    }

    func testAPopoverOpenWhenEComesIsClosedAndTheEraserIsUp() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.line))
        rig.overlay.perform(.thicknessAndOpacity(anchorX: 100))
        XCTAssertTrue(rig.overlay.popoverIsOpen)
        rig.overlay.perform(.erase)
        XCTAssertFalse(rig.overlay.popoverIsOpen)
        XCTAssertTrue(rig.overlay.isErasing)
        rig.overlay.perform(.colours(anchorX: 100))
        XCTAssertTrue(rig.overlay.popoverIsOpen, "the colour wheel does not open under the eraser")
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 300), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertFalse(rig.overlay.popoverIsOpen)
    }

    func testARightClickInTheMiddleOfTheDragDropsItAndLeavesTheEraserUp() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 120), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 300, y: 270), flags: [])
        rig.overlay.rightMouseDown()
        XCTAssertTrue(results.isEmpty, "the right click closed the editor")
        XCTAssertEqual(rig.view.drawnShapes.map(\.opacity), [1, 1, 1, 1])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 4)
        XCTAssertTrue(rig.overlay.isErasing)
    }

    func testASecondPressWithNoReleaseBetweenEndsTheFirstDragAsOneStepAndBeginsAnother() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 148), flags: [])
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: 198), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 2)
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 3, "the two presses were one step")
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 4)
    }

    func testAHandleOfTheAreaStillResizesTheAreaUnderTheEraser() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: area.maxX - 100, y: area.maxY - 100), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 4, "a press on the area's handle erased")
        XCTAssertTrue(rig.overlay.isErasing)
        rig.overlay.perform(.exit(.confirm))
        guard case .edited(_, let local, _, _)? = results.last else { return XCTFail("nothing handed over: \(results)") }
        XCTAssertEqual(local.size, CGSize(width: area.width - 100, height: area.height - 100))
    }

    func testAPressOutsideTheAreaUnderTheEraserTakesNothingAndLeavesTheAreaAlone() throws {
        let rig = try fourLines()
        rig.overlay.perform(.erase)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 900, y: 700), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 950, y: 750), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 4)
        rig.overlay.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, _)? = results.last else { return XCTFail("nothing handed over: \(results)") }
        XCTAssertEqual(local, area)
        XCTAssertEqual(layers.count, 4)
    }

    func testEWithNoAreaYetIsNothing() throws {
        let frames = try OverlayRig.frames()
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        built.perform(.erase)
        XCTAssertFalse(built.isErasing, "the eraser went up with no area to erase in")
    }
}
