import AppKit
import CoreGraphics
import HelmContract
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The ruler is a guide over the picture and nothing of it is kept: switching it on, moving it, turning it and lowering it
/// are no undo step and no layer, and what leaves the editor is the same with it on the picture as without.** The file is
/// made of the picture and the layers alone (`CaptureSession.annotated`), so two exits that hand over the same layers hand
/// over the same file; the ruler's layer is drawn in the overlay above the annotations and there only.
///
/// What it would print if it failed totally: a ruler that became a layer fails the first count of layers; one that
/// became an undo step fails `canUndo` after the first switch; one never drawn fails the `rulerLayer` visibility line.
@MainActor
final class TheRulerNeverReachesTheFileTests: XCTestCase {
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

    private func stroke(_ rig: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView), from: CGPoint, to: CGPoint, flags: NSEvent.ModifierFlags = []) {
        rig.overlay.mouseDown(on: rig.display, at: from, flags: flags)
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + 8), flags: flags)
        rig.overlay.mouseDragged(on: rig.display, at: to, flags: flags)
        rig.overlay.mouseUp(on: rig.display)
    }

    /// Switches the ruler on, takes it by its strip to the lower right, and turns it by the ⌥-drag and by the gesture.
    private func handleTheRuler(_ rig: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView)) throws {
        rig.overlay.perform(.toggleRuler)
        let middle = CGPoint(x: area.midX, y: area.midY)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, middle, "the ruler did not appear in the middle of the area")
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle, 0, "the ruler did not appear level")
        stroke(rig, from: middle, to: CGPoint(x: 560, y: 420))
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, CGPoint(x: 560, y: 420), "a drag by the strip did not take it along")
        stroke(rig, from: CGPoint(x: 560, y: 420), to: CGPoint(x: 560 + 100, y: 420 + 100), flags: .option)
        XCTAssertEqual(try XCTUnwrap(rig.overlay.rulerOnThePicture).angle, 45, "an ⌥-drag to the diagonal did not turn the strip to 45°")
        rig.overlay.rotateRuler(by: -20, phase: .began)
        rig.overlay.rotateRuler(by: -20, phase: .changed)
        XCTAssertEqual(try XCTUnwrap(rig.overlay.rulerOnThePicture).angle, 85, "two turns of 20° clockwise did not add to the angle")
        rig.overlay.rotateRuler(by: 0, phase: .ended)
    }

    func testSwitchingMovingAndTurningTheRulerAreNoStepAndNoLayer() throws {
        let rig = try opened()
        XCTAssertFalse(rig.overlay.palette.canUndo)
        try handleTheRuler(rig)
        XCTAssertFalse(rig.overlay.palette.canUndo, "the ruler became an undo step")
        XCTAssertFalse(rig.overlay.palette.canRedo)
        XCTAssertTrue(rig.overlay.palette.ruler, "the palette does not show the ruler raised")
        XCTAssertFalse(rig.view.rulerLayer.isHidden, "the ruler is on the picture and is not drawn")
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "the ruler is among the layers")
        rig.overlay.perform(.toggleRuler)
        XCTAssertNil(rig.overlay.rulerOnThePicture)
        XCTAssertTrue(rig.view.rulerLayer.isHidden, "the ruler is lowered and still drawn")
        XCTAssertFalse(rig.overlay.palette.canUndo)
        rig.overlay.perform(.exit(.copy))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("not an edit: \(results)") }
        XCTAssertEqual(layers, [], "the ruler left the editor as a layer")
    }

    func testTheRedoStackSurvivesEveryThingTheRulerDoes() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.pen))
        stroke(rig, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 150))
        rig.overlay.perform(.undo)
        XCTAssertTrue(rig.overlay.palette.canRedo)
        try handleTheRuler(rig)
        XCTAssertTrue(rig.overlay.palette.canRedo, "a move or a turn of the ruler cleared what redo could bring back")
        rig.overlay.perform(.redo)
        XCTAssertEqual(rig.view.drawnShapes.count, 1)
    }

    func testTheSameDrawingLeavesAsTheSameLayersWithTheRulerOnThePictureOrNot() throws {
        func drawn(withRuler: Bool) throws -> OverlayResult {
            let rig = try opened()
            if withRuler { try handleTheRuler(rig) }
            rig.overlay.perform(.tool(.pen))
            stroke(rig, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 160))
            rig.overlay.perform(.exit(.copy))
            return try XCTUnwrap(results.first)
        }
        guard case .edited(let displayA, let areaA, let without, _) = try drawn(withRuler: false),
              case .edited(let displayB, let areaB, let with, _) = try drawn(withRuler: true)
        else { return XCTFail("an exit was not an edit") }
        XCTAssertEqual(without.count, 1, "the fixture drew no stroke")
        XCTAssertEqual(with, without, "the layers differ with the ruler on the picture")
        XCTAssertEqual(areaA, areaB)
        XCTAssertEqual(displayA, displayB)
    }

    func testTheRulersLayerIsAboveTheAnnotationsAndInsideTheArea() throws {
        let rig = try opened()
        rig.overlay.perform(.tool(.pen))
        stroke(rig, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 150))
        rig.overlay.perform(.toggleRuler)
        let sublayers = try XCTUnwrap(rig.view.layer?.sublayers)
        let ruler = try XCTUnwrap(sublayers.firstIndex { $0 === rig.view.rulerLayer })
        let shape = try XCTUnwrap(rig.view.drawnShapes.first.flatMap { shape in sublayers.firstIndex { $0 === shape } })
        XCTAssertGreaterThan(ruler, shape, "the ruler is drawn under the annotations")
        let mask = try XCTUnwrap(rig.view.rulerLayer.mask as? CAShapeLayer)
        let box = try XCTUnwrap(mask.path?.boundingBoxOfPath)
        XCTAssertEqual(box.width, area.width, accuracy: 0.5, "the ruler is not clipped to the area")
        XCTAssertEqual(box.height, area.height, accuracy: 0.5)
    }

    func testTheAngleIsSpeltByTheAppsLanguageAsAWholeNumberWithItsDegreeSign() {
        for degrees in [0, 4, 45, -45, 90] as [CGFloat] {
            let text = RulerLayer.text(degrees: degrees)
            XCTAssertTrue(text.contains("°"), "\(degrees) → \(text) has no degree sign")
            XCTAssertTrue(text.contains(String(Int(abs(degrees)))), "\(degrees) → \(text) lost the number")
        }
        XCTAssertFalse(RulerLayer.text(degrees: -0.3).contains("-"), "a rounding to nothing shows a minus zero")
    }
}
