import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Crop, fed what the stage's own tests did not feed it.** Return with nothing changed, a crop to a single point and a file made of
/// it, a crop that grows back over what an earlier one left outside, Crop begun in the middle of an open pop-over, a field, an erase
/// and a stroke, an exit that is not Return with the crop pending, an undo while it is pending, two crops and one Esc, arrows at
/// the display's wall, Crop before there is an area; and the file of a cropped area against the screen, pixel for pixel, with
/// a step, a rectangle and a spotlight that the crop cuts through. The arrows with a layer on the picture and no Crop are asked too.
///
/// What it would print if it failed totally: a file made from the area as it was before the crop is the old size; a layer that
/// moved with the crop is off the screen's pixel by the crop's offset and fails the comparison at every probe.
@MainActor
final class TheCropMeetsInputsNobodyFedItTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var display = DisplayID(0)
    private var rig: ScreenAndFile.Rig?
    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        rig?.overlay.close()
        rig = nil
        results = []
        super.tearDown()
    }

    private func marked() throws -> OverlayView {
        let made = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = made.overlay
        display = made.display
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 260), flags: [])
        overlay?.mouseUp(on: display)
        overlay?.perform(.tool(.rectangle))
        return made.view
    }

    private func pull(_ handle: AreaHandle, by delta: CGPoint, in view: OverlayView? = nil) throws {
        let handles = try XCTUnwrap((view ?? rig?.view)?.drawnAreaHandles)
        let at = try XCTUnwrap(handles.isEmpty ? nil : handles[AreaHandle.allCases.firstIndex(of: handle)!], "no handles are drawn")
        let over = overlay ?? rig?.overlay
        let id = rig?.display ?? display
        over?.mouseDown(on: id, at: at, flags: [])
        over?.mouseDragged(on: id, at: CGPoint(x: at.x + delta.x, y: at.y + delta.y), flags: [])
        over?.mouseUp(on: id)
    }

    private var held: CaptureOverlay? { overlay ?? rig?.overlay }
    private func areaNow() throws -> CGRect { try XCTUnwrap(held?.editedArea) }

    // MARK: Return, 1 point, growing back

    func testReturnWithNothingChangedTakesNothingAndTheEditorStaysOpen() throws {
        _ = try marked()
        overlay?.perform(.crop)
        overlay?.perform(.exit(.confirm))
        XCTAssertTrue(results.isEmpty, "Return over an unchanged crop finished the overlay")
        XCTAssertFalse(overlay?.isCropping == true)
        XCTAssertEqual(try areaNow(), area)
        XCTAssertEqual(overlay?.editedLayers.count, 1)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(results.count, 1, "the next Return is not the editor's own")
    }

    func testACropToAboutAPointStaysUsableAndItsFileHasTheAreasPixelsAndNoMore() throws {
        for scale in [CGFloat(1), 2] {
            overlay?.close()
            let made = try ScreenAndFile.rig(scale: scale)
            rig = made
            made.overlay.perform(.tool(.step))
            ScreenAndFile.click(made, at: CGPoint(x: 400, y: 300))
            made.overlay.perform(.crop)
            let before = try areaNow()
            // Pull the right and the bottom edges to within a point of the left and the top.
            try pull(.bottomRight, by: CGPoint(x: -(before.width - 1.5), y: -(before.height - 1.5)))
            let cut = try areaNow()
            XCTAssertEqual(cut.width, 1.5, accuracy: 0.01, "\(scale)x: the subject: the crop is not a point and a half wide")
            XCTAssertEqual(cut.height, 1.5, accuracy: 0.01)
            made.overlay.perform(.exit(.confirm))
            XCTAssertEqual(try areaNow(), cut)
            made.overlay.perform(.exit(.confirm))
            guard case .edited(_, let local, let layers, _)? = made.results.all.last else { return XCTFail("\(scale)x: nothing was handed over") }
            let pixels = try XCTUnwrap(ScreenSpace.pixels(ofLocal: local, scale: scale, imageWidth: made.ground.width, imageHeight: made.ground.height))
            let piece = try XCTUnwrap(made.ground.cropping(to: pixels))
            let file = try XCTUnwrap(CaptureSession.draw(layers, over: piece, at: pixels.origin, scale: scale, display: made.ground))
            XCTAssertEqual(file.width, piece.width)
            XCTAssertEqual(file.height, piece.height)
            XCTAssertLessThanOrEqual(file.width, Int(2 * scale), "\(scale)x: a crop of a point and a half made a file \(file.width) wide")
            XCTAssertEqual(layers.count, 1, "the step went with the crop")
        }
    }

    func testACropThatGrowsBackOverWhatAnEarlierOneLeftOutBringsTheLayersBackAsTheyWere() throws {
        let view = try marked()
        let layers = try XCTUnwrap(overlay?.editedLayers)
        overlay?.perform(.crop)
        try pull(.left, by: CGPoint(x: 250, y: 0), in: view)   // the rectangle (x 200...300) is wholly left of the area now
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(overlay?.editedLayers, layers, "the first crop changed a layer")
        overlay?.perform(.crop)
        try pull(.left, by: CGPoint(x: -250, y: 0), in: view)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(try areaNow(), CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(overlay?.editedLayers, layers, "the crop that grew back did not find the layer where it was")
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertEqual(view.drawnHandles.count, 4, "the layer could not be taken again")
    }

    // MARK: What is open when Crop is chosen

    func testCropChosenWithAPopoverOpenClosesItAndTheCropStays() throws {
        _ = try marked()
        overlay?.perform(.tool(.rectangle))
        overlay?.perform(.thicknessAndOpacity(anchorX: 100))
        XCTAssertTrue(overlay?.popoverIsOpen == true, "the subject: the pop-over is open")
        overlay?.perform(.crop)
        XCTAssertTrue(overlay?.isCropping == true)
        XCTAssertFalse(overlay?.popoverIsOpen == true, "the pop-over of a tool stayed open under Crop")
    }

    func testCropChosenWithAFieldOpenPlacesTheTextAndThenCrops() throws {
        let made = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = made.overlay
        display = made.display
        overlay?.perform(.tool(.text))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 220), flags: [])
        overlay?.mouseUp(on: display)
        let field = try XCTUnwrap(made.view.textField, "the subject: no field")
        field.insertText("note", replacementRange: NSRange(location: NSNotFound, length: 0))
        overlay?.perform(.crop)
        XCTAssertFalse(overlay?.isTyping == true, "the field was left open under Crop")
        XCTAssertEqual(overlay?.editedLayers.map(\.tool), [.text])
        XCTAssertTrue(overlay?.isCropping == true)
        XCTAssertNil(made.view.textField)
        XCTAssertEqual(made.view.drawnAreaHandles.count, 8, "the placed text hid the handles of Crop")
    }

    func testCropChosenWhileAnEraseDragIsOpenLetsTheEraseEndAtTheReleaseAsOneStep() throws {
        let view = try marked()
        overlay?.perform(.erase)
        overlay?.mouseDown(on: display, at: CGPoint(x: 150, y: 150), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay?.perform(.crop)
        overlay?.mouseDragged(on: display, at: CGPoint(x: 205, y: 230), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertTrue(overlay?.isCropping == true)
        XCTAssertFalse(overlay?.isErasing == true)
        XCTAssertEqual(overlay?.palette.canUndo, true)
        XCTAssertLessThanOrEqual(overlay?.editedLayers.count ?? 9, 1)
        // Whatever the erase did, nothing is held open: the handles answer and the area is what it was.
        XCTAssertEqual(try areaNow(), area)
        XCTAssertEqual(view.drawnAreaHandles.count, 8)
        try pull(.right, by: CGPoint(x: -50, y: 0), in: view)
        XCTAssertEqual(try areaNow().width, 350, accuracy: 0.01, "a handle did not answer after the erase ended under Crop")
    }

    func testCropChosenWhileAStrokeIsOpenLeavesTheStrokeAndAHandleStillAnswers() throws {
        let view = try marked()
        overlay?.perform(.tool(.line))
        overlay?.mouseDown(on: display, at: CGPoint(x: 150, y: 400), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 250, y: 420), flags: [])
        overlay?.perform(.crop)
        overlay?.mouseDragged(on: display, at: CGPoint(x: 260, y: 420), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertEqual(overlay?.editedLayers.map(\.tool), [.rectangle, .line], "the stroke begun before Crop was lost or doubled")
        XCTAssertTrue(overlay?.isCropping == true)
        XCTAssertNil(overlay?.palette.tool, "the tool came back")
        try pull(.right, by: CGPoint(x: -50, y: 0), in: view)
        XCTAssertEqual(try areaNow().width, 350, accuracy: 0.01)
    }

    // MARK: Exits, undo, twice

    func testASaveWithACropPendingDeliversTheCroppedAreaAndAnEscAfterItDoesNothing() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(.right, by: CGPoint(x: -100, y: 0), in: view)
        overlay?.perform(.exit(.save))
        guard case .edited(_, let local, _, let how)? = results.last else { return XCTFail("nothing was handed over: \(results)") }
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 300, height: 300), "the save did not take the crop pending")
        XCTAssertEqual(how, .save)
        let count = results.count
        overlay?.rightMouseDown()
        XCTAssertEqual(results.count, count, "an Esc after the save handed over another result")
    }

    func testAnUndoWhileACropIsPendingTakesTheStepAndLeavesTheAreaAndEscStillGivesItsBase() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(.right, by: CGPoint(x: -100, y: 0), in: view)
        overlay?.perform(.undo)
        XCTAssertEqual(overlay?.editedLayers.count, 0)
        XCTAssertEqual(try areaNow().width, 300, "the undo gave the pending area back")
        XCTAssertTrue(overlay?.isCropping == true)
        overlay?.perform(.redo)
        XCTAssertEqual(overlay?.editedLayers.count, 1)
        XCTAssertEqual(try areaNow().width, 300)
        overlay?.rightMouseDown()
        XCTAssertEqual(try areaNow(), area)
    }

    func testTwoCropsAndOneEscGiveTheAreaTheSecondFoundAndNotTheFirst() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(.right, by: CGPoint(x: -100, y: 0), in: view)
        overlay?.perform(.exit(.confirm))
        let first = try areaNow()
        overlay?.perform(.crop)
        try pull(.bottom, by: CGPoint(x: 0, y: -100), in: view)
        XCTAssertNotEqual(try areaNow(), first, "the subject: the second crop is pending")
        overlay?.rightMouseDown()
        XCTAssertEqual(try areaNow(), first, "Esc gave the area before the first crop, or something else")
    }

    // MARK: The arrows

    func testArrowsUnderCropStopAtTheDisplaysWallAndEscGivesTheAreaBack() throws {
        _ = try marked()
        overlay?.perform(.crop)
        for _ in 0..<80 { overlay?.perform(.nudge(dx: 1, dy: 0, pixels: 10)) }
        let area = try areaNow()
        XCTAssertEqual(area.maxX, 1000, accuracy: 0.001, "the area did not stop at the display's right wall")
        XCTAssertEqual(area.size, self.area.size, "the area changed size at the wall")
        for _ in 0..<80 { overlay?.perform(.nudge(dx: 0, dy: -1, pixels: 10)) }
        XCTAssertEqual(try areaNow().minY, 0, accuracy: 0.001)
        overlay?.rightMouseDown()
        XCTAssertEqual(try areaNow(), self.area)
    }

    func testArrowsWithALayerOnThePictureAndNoSelectionAndNoCropStillMoveTheArea() throws {
        _ = try marked()
        XCTAssertNil(overlay?.palette.selectedTool)
        let before = try areaNow()
        overlay?.perform(.nudge(dx: 1, dy: 0, pixels: 10))
        XCTAssertEqual(try areaNow(), before.offsetBy(dx: 10, dy: 0), "an arrow with a layer present and no Crop does not move the area")
        XCTAssertFalse(overlay?.isCropping == true)
    }

    func testCropBeforeThereIsAnAreaDoesNothing() throws {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        built.perform(.crop)
        XCTAssertFalse(built.isCropping, "Crop went on with no area to crop")
        XCTAssertNil(built.editedArea)
    }

    // MARK: The file of a cropped area is the screen

    func testTheFileOfACroppedAreaHoldsEveryLayerWhereTheScreenShowedItRelativeToThePicture() throws {
        for scale in [CGFloat(1), 2] {
            rig?.overlay.close()
            let made = try ScreenAndFile.rig(scale: scale)
            rig = made
            let (w, h) = (made.points.width, made.points.height)
            func at(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: 50 + fx * (w - 100), y: 50 + fy * (h - 100)) }
            made.overlay.perform(.tool(.spotlight))
            ScreenAndFile.drag(made, from: at(0.05, 0.1), to: at(0.5, 0.6))   // straddles the crop's left edge
            made.overlay.perform(.tool(.rectangle))
            made.overlay.perform(.color(.blue))
            ScreenAndFile.drag(made, from: at(0.4, 0.3), to: at(0.8, 0.8))
            made.overlay.perform(.tool(.step))
            made.overlay.perform(.color(.red))
            ScreenAndFile.click(made, at: at(0.6, 0.2))
            ScreenAndFile.click(made, at: at(0.25, 0.5))                      // outside the crop's area once it is taken
            made.overlay.perform(.crop)
            let before = try areaNow()
            try pull(.left, by: CGPoint(x: 0.3 * before.width, y: 0))
            try pull(.top, by: CGPoint(x: 0, y: 0.1 * before.height))
            let cut = try areaNow()
            XCTAssertLessThan(cut.width, before.width, "\(scale)x: the crop did not narrow the area")
            made.overlay.perform(.exit(.confirm))
            XCTAssertFalse(made.overlay.isCropping)
            let root = ScreenAndFile.composite(made)
            made.results.all = []
            made.overlay.perform(.exit(.confirm))
            guard case .edited(_, let local, let layers, _)? = made.results.all.last else { return XCTFail("\(scale)x: nothing handed over") }
            XCTAssertEqual(local, cut)
            XCTAssertEqual(layers.map(\.tool), [.spotlight, .rectangle, .step, .step])
            let pixels = try XCTUnwrap(ScreenSpace.pixels(ofLocal: local, scale: scale, imageWidth: made.ground.width, imageHeight: made.ground.height))
            let piece = try XCTUnwrap(made.ground.cropping(to: pixels))
            let file = try XCTUnwrap(CaptureSession.draw(layers, over: piece, at: pixels.origin, scale: scale, display: made.ground))
            let (fw, fh) = (file.width, file.height)
            let (gw, gh) = (made.ground.width, made.ground.height)
            let bytes = try ScreenAndFile.rgb(file), ground = try ScreenAndFile.rgb(made.ground)
            var probes: [(x: Int, y: Int)] = []
            let (ox, oy) = (Int(pixels.minX), Int(pixels.minY))
            for y in stride(from: 0, to: fh, by: 3) { for x in stride(from: 0, to: fw, by: 3) { probes.append((ox + x, oy + y)) } }
            let read = try CompositedPixels.read(root, width: gw, height: gh, at: probes.map { CGPoint(x: $0.x, y: gh - 1 - $0.y) })
            var off = 0, worst = 0, inked = 0, dimmed = 0, bad: [String] = []
            for (probe, got) in zip(probes, read) {
                let (fx, fy) = (probe.x - ox, probe.y - oy)
                // The file's outermost pixels are whole pixels of a fractional area: the screen dims only the part of them inside it.
                if fx < 2 || fy < 2 || fx >= fw - 2 || fy >= fh - 2 { continue }
                let fileAt = (fy * fw + fx) * 4
                var gap = 0
                for channel in 0..<3 { gap = max(gap, abs(Int(got[channel]) - Int(bytes[fileAt + channel]))) }
                worst = max(worst, gap)
                if gap > 16 { off += 1; bad.append("(\(fx),\(fy)) gap \(gap)") }
                if (0..<3).contains(where: { abs(Int(bytes[fileAt + $0]) - Int(ground[(probe.y * gw + probe.x) * 4 + $0])) > 60 }) { inked += 1 }
                if abs(Int(bytes[fileAt]) - Int(Double(ground[0]) * (1 - Double(Spotlights.dimAlpha)))) <= 2 { dimmed += 1 }
            }
            XCTAssertEqual(off, 0, "\(scale)x: \(off) of \(probes.count) pixels of the cropped file are not the screen's (worst gap \(worst)), e.g. \(bad.prefix(6)), file \(fw)x\(fh), layers \(layers.map { "\($0.tool) \($0.start)-\($0.end)" })")
            XCTAssertGreaterThan(inked, 40, "\(scale)x: the file holds no ink of the rectangle or the steps: the comparison proves nothing")
            XCTAssertGreaterThan(dimmed, 100, "\(scale)x: the file holds no dim")
        }
    }
}
