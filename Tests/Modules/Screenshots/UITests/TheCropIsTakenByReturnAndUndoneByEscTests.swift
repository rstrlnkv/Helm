import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Crop, a mode of the overlay.** The handles of a marked picture come back with it; Return takes the area the handles
/// made and Esc gives the area back, and neither is an undo step; Esc does not ask the question the rule asks, so the next
/// press is the first of the rule. A tool, the eraser and Select leave the mode and put the area back, the ruler stays and
/// is brought inside the new area at Return, and the size plate stands at the area's top-left corner. Events go in as the
/// views send them; panels are built and never ordered in.
@MainActor
final class TheCropIsTakenByReturnAndUndoneByEscTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var display = DisplayID(0)
    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    /// A marked picture: the area, and a rectangle drawn in it with the tool put down again.
    private func marked() throws -> OverlayView {
        let rig = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        display = rig.display
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 200), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 300, y: 260), flags: [])
        overlay?.mouseUp(on: display)
        overlay?.perform(.tool(.rectangle))
        return rig.view
    }

    private func pull(_ view: OverlayView, _ handle: AreaHandle, by delta: CGPoint) throws {
        let at = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: handle)!])
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x + delta.x, y: at.y + delta.y), flags: [])
        overlay?.mouseUp(on: display)
    }

    private func edited() throws -> (local: CGRect, layers: [Annotation]) {
        guard case .edited(_, let local, let layers, _)? = results.last else {
            XCTFail("not an edited area: \(results)")
            throw CancellationError()
        }
        return (local, layers)
    }

    private let cut = CGRect(x: 100, y: 100, width: 300, height: 300) // `area` with its right handle pulled 100 points in

    // MARK: The mode

    func testAMarkedPictureOffersNoHandleAndCropBringsThemBack() throws {
        let view = try marked()
        XCTAssertTrue(view.drawnAreaHandles.isEmpty, "the handles were drawn over a marked picture")
        let before = view.drawnAreaHandles
        overlay?.mouseDown(on: display, at: CGPoint(x: area.maxX, y: area.midY), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertEqual(view.drawnAreaHandles, before)
        XCTAssertEqual(try overlayArea(), area, "a press on the edge of a marked picture took the area")
        overlay?.perform(.crop)
        XCTAssertEqual(view.drawnAreaHandles, AreaFrame.handles(of: area).map(\.point), "Crop did not bring the eight handles back")
        XCTAssertTrue(overlay?.isCropping == true)
    }

    func testAPictureWithNoMarkHasItsHandlesWithAndWithoutCrop() throws {
        let rig = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        XCTAssertEqual(rig.view.drawnAreaHandles.count, 8)
        overlay?.perform(.crop)
        XCTAssertEqual(rig.view.drawnAreaHandles.count, 8)
    }

    /// While Crop is on the palette stands under the base area, however the handles have moved the area; after Return, under the new one.
    func testThePaletteStandsUnderTheBaseAreaWhileCropIsOnAndUnderTheNewOneAfterReturn() throws {
        let view = try marked()
        let screen = view.frozen.frame.size
        let under = { (rect: CGRect) in EditorChrome.place(selection: rect, in: screen, palette: view.paletteSize).palette }
        overlay?.perform(.crop)
        try pull(view, .bottom, by: CGPoint(x: 0, y: -100))
        let reshaped = CGRect(x: 100, y: 100, width: 400, height: 200)
        XCTAssertEqual(try overlayArea(), reshaped, "the subject: the handle cut the bottom strip off")
        XCTAssertNotEqual(under(area), under(reshaped), "the subject: the two placements differ")
        XCTAssertEqual(overlay?.chrome(on: display)?.palette, under(area), "the palette did not stand under the base area while Crop was on")
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(overlay?.chrome(on: display)?.palette, under(reshaped), "the palette did not stand under the new area after Return")
    }

    /// The area the editor holds now, without leaving it.
    private func overlayArea() throws -> CGRect { try XCTUnwrap(overlay?.editedArea) }

    // MARK: Return takes

    func testReturnTakesTheAreaTheHandlesMadeAndTheEditorStaysOpenOnIt() throws {
        let view = try marked()
        let layers = try XCTUnwrap(overlay?.editedLayers)
        overlay?.perform(.crop)
        try pull(view, .right, by: CGPoint(x: -100, y: 0))
        XCTAssertEqual(try overlayArea(), cut, "the handle did not reshape the area while Crop was on")
        overlay?.perform(.exit(.confirm))
        XCTAssertTrue(results.isEmpty, "Return finished the overlay instead of taking the crop")
        XCTAssertFalse(overlay?.isCropping == true)
        XCTAssertEqual(try overlayArea(), cut)
        XCTAssertTrue(view.drawnAreaHandles.isEmpty, "the handles stayed after the crop was taken, over a marked picture")
        // The next Return is the editor's own: the file is the cropped area and every layer is where it was on the picture.
        overlay?.perform(.exit(.confirm))
        let done = try edited()
        XCTAssertEqual(done.local, cut)
        XCTAssertEqual(done.layers, layers, "a layer moved with the crop")
    }

    func testTakingTheCropIsNoUndoStepAndUndoLeavesTheNewArea() throws {
        let view = try marked()
        XCTAssertEqual(overlay?.palette.canUndo, true, "the subject: the mark is one step")
        overlay?.perform(.crop)
        try pull(view, .right, by: CGPoint(x: -100, y: 0))
        overlay?.perform(.exit(.confirm))
        overlay?.perform(.undo)
        XCTAssertEqual(overlay?.editedLayers.count, 0, "the first undo took the crop back and not the mark")
        XCTAssertEqual(overlay?.palette.canUndo, false, "the crop left a step behind")
        XCTAssertEqual(try overlayArea(), cut, "undo gave the area back")
        XCTAssertEqual(view.drawnAreaHandles, AreaFrame.handles(of: cut).map(\.point), "an unmarked picture has its handles again")
    }

    func testAnObjectLeftOutsideTheNewAreaIsLetGoOfAtTheReleaseAndStaysOnThePicture() throws {
        let view = try marked()
        overlay?.mouseDown(on: display, at: CGPoint(x: 200, y: 230), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertEqual(view.drawnHandles.count, 4, "the subject: the object is selected")
        overlay?.perform(.crop)
        try pull(view, .left, by: CGPoint(x: 250, y: 0))
        XCTAssertTrue(view.drawnHandles.isEmpty, "a frame and handles were left in the dim")
        overlay?.perform(.exit(.confirm))
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(try edited().layers.count, 1, "an object outside the new area was deleted")
    }

    // MARK: Esc gives back

    func testEscGivesTheAreaBackAndTheNextEscIsTheFirstOfTheRule() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(view, .right, by: CGPoint(x: -100, y: 0))
        overlay?.rightMouseDown() // the other door of Esc
        XCTAssertFalse(overlay?.isCropping == true)
        XCTAssertEqual(try overlayArea(), area, "Esc did not give the area back")
        XCTAssertTrue(results.isEmpty, "Esc left the overlay")
        XCTAssertTrue(view.visiblePlates.isEmpty, "that Esc asked the rule's question")
        XCTAssertEqual(overlay?.palette.canUndo, true, "Esc touched the undo steps")
        XCTAssertEqual(overlay?.editedLayers.count, 1)
        overlay?.rightMouseDown()
        XCTAssertTrue(results.isEmpty, "the Esc after the crop closed the picture: the rule was armed by the one before")
        XCTAssertEqual(view.visiblePlates.count, 1, "the second Esc did not ask")
        overlay?.rightMouseDown()
        guard case .cancelled? = results.last else { return XCTFail("the third Esc did not close: \(results)") }
    }

    func testEscAfterACropTakenAsksAsItAlwaysDid() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(view, .right, by: CGPoint(x: -100, y: 0))
        overlay?.perform(.exit(.confirm))
        overlay?.rightMouseDown()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(view.visiblePlates.count, 1, "Esc over a marked picture asks")
        XCTAssertEqual(try overlayArea(), cut, "Esc took the taken crop back")
    }

    func testEscWhileAHandleIsHeldCancelsThatDragAndStaysInTheMode() throws {
        let view = try marked()
        overlay?.perform(.crop)
        let at = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: .right)!])
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x - 100, y: at.y), flags: [])
        overlay?.rightMouseDown()
        overlay?.mouseUp(on: display)
        XCTAssertEqual(try overlayArea(), area)
        XCTAssertTrue(overlay?.isCropping == true, "the press that cancels a drag also left the mode")
    }

    func testCropAskedAgainIsEscsAndGivesTheAreaBack() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(view, .right, by: CGPoint(x: -100, y: 0))
        overlay?.perform(.crop)
        XCTAssertFalse(overlay?.isCropping == true)
        XCTAssertEqual(try overlayArea(), area)
    }

    // MARK: What puts Crop down

    func testAToolTheEraserAndSelectLeaveTheModeAndGiveTheAreaBack() throws {
        let view = try marked()
        let leavers: [(String, EditorAction)] = [("a tool", .tool(.arrow)), ("the eraser", .erase), ("Select", .select)]
        for (name, action) in leavers {
            overlay?.perform(.crop)
            try pull(view, .right, by: CGPoint(x: -100, y: 0))
            XCTAssertEqual(try overlayArea(), cut, "the subject: the area is pending for \(name)")
            overlay?.perform(action)
            XCTAssertFalse(overlay?.isCropping == true, "\(name) did not leave Crop")
            XCTAssertEqual(try overlayArea(), area, "\(name) kept the pending crop")
            overlay?.perform(.select)
            if overlay?.isErasing == true { overlay?.perform(.erase) }
        }
        XCTAssertTrue(view.drawnAreaHandles.isEmpty)
    }

    func testCropPutsTheEraserAndTheChosenToolDownAndLeavesTheRulerOn() throws {
        _ = try marked()
        overlay?.perform(.tool(.arrow))
        overlay?.perform(.erase)
        overlay?.perform(.toggleRuler)
        XCTAssertTrue(overlay?.isErasing == true)
        overlay?.perform(.crop)
        XCTAssertFalse(overlay?.isErasing == true, "the eraser stayed up under Crop")
        XCTAssertNotNil(overlay?.rulerOnThePicture, "Crop lowered the ruler")
        XCTAssertNil(overlay?.palette.tool, "a tool stayed chosen under Crop, and a press away from a handle would draw")
        XCTAssertTrue(overlay?.palette.cropping == true)
    }

    func testTheRulerIsBroughtInsideTheNewAreaAtReturnAndNotBefore() throws {
        let view = try marked()
        overlay?.perform(.toggleRuler)
        let strip = try XCTUnwrap(overlay?.rulerOnThePicture)
        overlay?.perform(.crop)
        try pull(view, .left, by: CGPoint(x: 280, y: 0)) // the area is x 380...500
        XCTAssertEqual(overlay?.rulerOnThePicture, strip, "the strip moved before the crop was taken")
        overlay?.perform(.exit(.confirm))
        var kept = strip
        kept.keep(within: CGRect(x: 380, y: 100, width: 120, height: 300))
        XCTAssertEqual(overlay?.rulerOnThePicture, kept, "the strip was not brought inside the new area")
    }

    func testEscGivesTheRulerBackWhereItWas() throws {
        let view = try marked()
        overlay?.perform(.toggleRuler)
        let strip = try XCTUnwrap(overlay?.rulerOnThePicture)
        overlay?.perform(.crop)
        try pull(view, .left, by: CGPoint(x: 280, y: 0))
        overlay?.rightMouseDown()
        XCTAssertEqual(overlay?.rulerOnThePicture, strip, "Esc left the strip moved")
    }

    func testAnExitThatIsNoReturnDeliversTheAreaAsTheScreenShowsIt() throws {
        let view = try marked()
        overlay?.perform(.crop)
        try pull(view, .right, by: CGPoint(x: -100, y: 0))
        overlay?.perform(.exit(.copy))
        XCTAssertEqual(try edited().local, cut)
    }

    // MARK: The menu, the badge and the plate

    func testTheMenuChecksCropAndNotSelectAndTheBadgeIsItsSymbol() throws {
        _ = try marked()
        let model = try XCTUnwrap(overlay?.palette)
        func line(_ title: String) -> EditorMenuItem? {
            EditorMenu.items(for: model, pinOffered: false).first {
                if case .tool(let name, _, _, _) = $0 { return name == title }
                return false
            }
        }
        XCTAssertEqual(line(ScStr.crop), .tool(title: ScStr.crop, symbol: "crop", isOn: false, action: .crop))
        overlay?.perform(.crop)
        XCTAssertEqual(line(ScStr.crop), .tool(title: ScStr.crop, symbol: "crop", isOn: true, action: .crop))
        XCTAssertEqual(line(ScStr.select), .tool(title: ScStr.select, symbol: EditorPalette.selectSymbol, isOn: false, action: .select),
                       "Select stayed checked beside Crop")
        XCTAssertEqual(EditorPalette.moreBadge(for: model), "crop")
        XCTAssertEqual(EditorPalette.moreValue(for: model), ScStr.crop)
        overlay?.perform(.select)
        XCTAssertEqual(EditorPalette.moreBadge(for: model), EditorPalette.selectSymbol)
        XCTAssertEqual(EditorMenu.keyEquivalent(of: .crop), "", "Crop has no key in the menu")
    }

    func testTheSizePlateStandsAtTheTopLeftCornerWhileCropIsOn() throws {
        let view = try marked()
        XCTAssertTrue(view.visiblePlates.isEmpty)
        overlay?.perform(.crop)
        var plate = try XCTUnwrap(view.visiblePlates.first)
        XCTAssertEqual(plate.string, "400 × 300")
        XCTAssertEqual(plate.frame.minX, area.minX + 14, accuracy: 0.5)
        XCTAssertEqual(plate.frame.minY, view.bounds.height - area.minY + 12, accuracy: 0.5, "the plate is not 12 points above the top edge")
        try pull(view, .topLeft, by: CGPoint(x: 30, y: 20))
        plate = try XCTUnwrap(view.visiblePlates.first)
        XCTAssertEqual(plate.string, "370 × 280")
        XCTAssertEqual(plate.frame.minX, area.minX + 30 + 14, accuracy: 0.5, "the plate did not follow the corner")
        overlay?.rightMouseDown()
        XCTAssertTrue(view.visiblePlates.isEmpty, "the plate outlived the mode")
    }

    // MARK: The same inputs from another side

    func testAFreshAreaDragWithNoLayerEndsTheMode() throws {
        let rig = try OverlayRig.overlay(scale: 1, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        display = rig.display
        overlay?.perform(.crop)
        overlay?.mouseDown(on: display, at: CGPoint(x: 700, y: 500), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 800, y: 600), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertFalse(overlay?.isCropping == true, "a new area was begun and the old crop was still pending")
        XCTAssertEqual(try overlayArea(), CGRect(x: 700, y: 500, width: 100, height: 100))
    }
}
