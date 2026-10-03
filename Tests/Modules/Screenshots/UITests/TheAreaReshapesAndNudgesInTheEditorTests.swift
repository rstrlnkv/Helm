import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The edited area taken by its handles and moved by the arrows, on the overlay itself.** Events go in
/// as the views send them and the answer is read from what the overlay would hand on (`.edited`), what the
/// palette does and what the view draws: every handle reshapes, an object's handle beats an area's, Esc
/// cancels, the palette and the plate follow the area, and the arrows move by pixels of a 1x and a 2x
/// display, by key code. Panels are built and never ordered in.
@MainActor
final class TheAreaReshapesAndNudgesInTheEditorTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private var display = DisplayID(0)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    /// 1000×800 points per real screen at `scale`, an area of 400×300 at (100, 100) selected.
    private func build(scale: CGFloat = 1, area: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300)) throws -> OverlayView {
        let rig = try OverlayRig.overlay(scale: scale, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        display = rig.display
        return rig.view
    }

    private func key(_ code: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = [], repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: repeating, keyCode: code)!
    }
    private let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126, kR: UInt16 = 15

    /// A drag of `handle` of the area as it stands, by `delta`, released.
    private func pull(_ view: OverlayView, _ handle: AreaHandle, by delta: CGPoint, release: Bool = true) throws {
        let at = try XCTUnwrap(view.drawnAreaHandles[AreaHandle.allCases.firstIndex(of: handle)!])
        overlay?.mouseDown(on: display, at: at, flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: at.x + delta.x, y: at.y + delta.y), flags: [])
        if release { overlay?.mouseUp(on: display) }
    }

    /// What the overlay hands on if Return is pressed now.
    private func confirmed() throws -> (local: CGRect, layers: [Annotation]) {
        // With Crop on, Return takes the crop and the next one is the exit.
        if overlay?.isCropping == true { overlay?.perform(.exit(.confirm)) }
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, let local, let layers, _)? = results.last else {
            XCTFail("not an edited area: \(results)")
            throw CancellationError()
        }
        return (local, layers)
    }

    private func drawRectangle(from: CGPoint = CGPoint(x: 200, y: 200), to: CGPoint = CGPoint(x: 300, y: 260)) {
        overlay?.perform(.tool(.rectangle))
        overlay?.mouseDown(on: display, at: from, flags: [])
        overlay?.mouseDragged(on: display, at: to, flags: [])
        overlay?.mouseUp(on: display)
        overlay?.perform(.tool(.rectangle)) // the tool down again: a click selects
    }

    private func selectRectangle(at edge: CGPoint = CGPoint(x: 200, y: 230)) {
        overlay?.mouseDown(on: display, at: edge, flags: [])
        overlay?.mouseUp(on: display)
    }

    // MARK: The handles

    func testTheAreaHasEightRoundDotsAndTheObjectsHandlesAreAnotherLayerAndShape() throws {
        let view = try build()
        XCTAssertEqual(view.drawnAreaHandles.count, 8)
        XCTAssertEqual(view.drawnAreaHandles, AreaFrame.handles(of: CGRect(x: 100, y: 100, width: 400, height: 300)).map(\.point))
        XCTAssertTrue(view.drawnHandles.isEmpty, "no object is selected, so the object's handles are none")
        let areaLayer = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.path != nil && $0.fillColor == NSColor.white.cgColor && $0.strokeColor?.alpha ?? 1 < 1 && $0.lineWidth == 1 && !($0.path!.boundingBoxOfPath.isEmpty) && $0.fillRule != .evenOdd && $0.path!.boundingBoxOfPath.width > 300 })
        // A dot: the path is made of ellipses, whose corner points are not on the box's corners as a square's are.
        var corners = 0
        areaLayer.path!.applyWithBlock { element in if element.pointee.type == .addCurveToPoint { corners += 1 } }
        XCTAssertGreaterThan(corners, 0, "the area's handles are not round")
        drawRectangle()
        selectRectangle()
        XCTAssertEqual(view.drawnHandles.count, 4, "the object's four corners")
        XCTAssertTrue(view.drawnAreaHandles.isEmpty, "the area's handles stayed after the first mark")
        overlay?.perform(.crop)
        XCTAssertEqual(view.drawnAreaHandles.count, 8, "Crop did not bring the area's handles back")
        XCTAssertEqual(view.drawnHandles.count, 4, "Crop let go of the selected object")
    }

    func testEveryHandleReshapesTheAreaAndTheFileCropAndTheRememberedAreaAreTheNewOne() throws {
        let table: [(AreaHandle, CGRect)] = [
            (.topLeft, CGRect(x: 110, y: 106, width: 390, height: 294)), (.top, CGRect(x: 100, y: 106, width: 400, height: 294)),
            (.topRight, CGRect(x: 100, y: 106, width: 410, height: 294)), (.right, CGRect(x: 100, y: 100, width: 410, height: 300)),
            (.bottomRight, CGRect(x: 100, y: 100, width: 410, height: 306)), (.bottom, CGRect(x: 100, y: 100, width: 400, height: 306)),
            (.bottomLeft, CGRect(x: 110, y: 100, width: 390, height: 306)), (.left, CGRect(x: 110, y: 100, width: 390, height: 300)),
        ]
        for (handle, expected) in table {
            results = []
            overlay?.close()
            let view = try build()
            try pull(view, handle, by: CGPoint(x: 10, y: 6))
            XCTAssertEqual(view.drawnAreaHandles, AreaFrame.handles(of: expected).map(\.point), "\(handle): the dots did not follow")
            XCTAssertTrue(results.isEmpty, "\(handle): the reshape finished the overlay")
            XCTAssertEqual(try confirmed().local, expected, "\(handle): what is handed on, and so cropped and remembered, is not the new area")
        }
    }

    func testAHandleIsTakenBeforeADrawAndTheToolDrawsNothingThere() throws {
        let view = try build()
        overlay?.perform(.tool(.rectangle))
        try pull(view, .topRight, by: CGPoint(x: -20, y: 30))
        XCTAssertEqual(view.drawnShapes.count, 0, "a drawing was begun under the handle")
        XCTAssertEqual(try confirmed().local, CGRect(x: 100, y: 130, width: 380, height: 270))
    }

    func testAnObjectsHandleBeatsTheAreasWhereTheyMeetAndTheAreasIsTakenWhereTheyDoNot() throws {
        // A rectangle whose top-left corner, (104, 104), is 5.6 points from the area's own: dragged from
        // inside, because a press that begins a drawing there would be the area's handle.
        func rig() throws -> OverlayView {
            results = []
            overlay?.close()
            let view = try build()
            overlay?.perform(.tool(.rectangle))
            overlay?.mouseDown(on: display, at: CGPoint(x: 220, y: 200), flags: [])
            overlay?.mouseDragged(on: display, at: CGPoint(x: 104, y: 104), flags: [])
            overlay?.mouseUp(on: display)
            overlay?.perform(.tool(.rectangle))
            selectRectangle(at: CGPoint(x: 160, y: 200))
            XCTAssertNotNil(view.drawnHandles.first { $0 == CGPoint(x: 104, y: 104) }, "the subject: the object is held by that corner")
            overlay?.perform(.crop) // over a marked picture the area's handles are offered with Crop on only
            return view
        }
        // On the area's own centre, which is nearer to the area's handle than to the object's: still the object's.
        _ = try rig()
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 140, y: 140), flags: [])
        overlay?.mouseUp(on: display)
        var done = try confirmed()
        XCTAssertEqual(done.local, CGRect(x: 100, y: 100, width: 400, height: 300), "the area was reshaped through the object's handle")
        XCTAssertEqual(done.layers.first?.frame, CGRect(x: 140, y: 140, width: 80, height: 60), "the object was not resized")
        // Out of the object's reach, 9.9 points, and in the area's, 4.2: the area's.
        _ = try rig()
        overlay?.mouseDown(on: display, at: CGPoint(x: 97, y: 97), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 107, y: 107), flags: [])
        overlay?.mouseUp(on: display)
        done = try confirmed()
        XCTAssertEqual(done.local, CGRect(x: 110, y: 110, width: 390, height: 290), "the area's handle was not taken beside the object's")
        XCTAssertEqual(done.layers.first?.frame, CGRect(x: 104, y: 104, width: 116, height: 96), "the object moved with the area's handle")
    }

    // MARK: What the reshape leaves behind, and a tiny area

    func testAnAreaPulledPastTheSelectedObjectLetsItGoAtTheReleaseAndAPartlyInsideOneStaysSelected() throws {
        let view = try build()
        drawRectangle() // (200,200)-(300,260)
        selectRectangle()
        XCTAssertEqual(view.drawnHandles.count, 4, "the subject: the object is selected")
        overlay?.perform(.crop)
        // Partly inside: the left edge to x = 250 cuts the object in two.
        try pull(view, .left, by: CGPoint(x: 150, y: 0))
        XCTAssertEqual(view.drawnHandles.count, 4, "an object partly inside the area was let go of")
        // Wholly outside: held mid-drag it is still selected, and released it is let go of.
        try pull(view, .left, by: CGPoint(x: 100, y: 0), release: false)
        XCTAssertEqual(view.drawnHandles.count, 4, "the object was let go of while the handle was still held")
        overlay?.mouseUp(on: display)
        XCTAssertTrue(view.drawnHandles.isEmpty, "a frame and handles were left in the dim")
        let done = try confirmed()
        XCTAssertEqual(done.local, CGRect(x: 350, y: 100, width: 150, height: 300))
        XCTAssertEqual(done.layers.count, 1, "letting go of the object is not deleting it")
    }

    func testAnEscMidReshapeKeepsTheObjectSelectedWhereTheAreaWentPastIt() throws {
        let view = try build()
        drawRectangle()
        selectRectangle()
        overlay?.perform(.crop)
        try pull(view, .left, by: CGPoint(x: 250, y: 0), release: false)
        overlay?.rightMouseDown() // the other door of Esc
        overlay?.mouseUp(on: display)
        XCTAssertEqual(view.drawnHandles.count, 4)
    }

    func testATinyAreaDrawsFourCornerDotsAndAPressAtAMiddleIsNotAHandle() throws {
        let view = try build(area: CGRect(x: 100, y: 100, width: 26, height: 26))
        XCTAssertEqual(view.drawnAreaHandles, AreaFrame.handles(of: CGRect(x: 100, y: 100, width: 26, height: 26))
            .filter { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains($0.handle) }.map(\.point))
        overlay?.mouseDown(on: display, at: CGPoint(x: 113, y: 100), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 113, y: 140), flags: [])
        overlay?.mouseUp(on: display)
        XCTAssertEqual(try confirmed().local.size, CGSize(width: 26, height: 26), "the top middle took the area")
        let roomy = try { overlay?.close(); results = []; return try build(area: CGRect(x: 100, y: 100, width: 27, height: 27)) }()
        XCTAssertEqual(roomy.drawnAreaHandles.count, 8, "an area of three dot diameters is held by all eight")
    }

    // MARK: What follows the area

    func testThePaletteGoesWhileTheHandleIsHeldAndStandsBesideTheNewAreaAfterwards() throws {
        let view = try build()
        let size = view.paletteSize
        XCTAssertNotNil(overlay?.chrome(on: display))
        try pull(view, .right, by: CGPoint(x: 60, y: 0), release: false)
        XCTAssertNil(overlay?.chrome(on: display), "the palette stayed up under the pointer")
        overlay?.mouseUp(on: display)
        let moved = CGRect(x: 100, y: 100, width: 460, height: 300)
        XCTAssertEqual(overlay?.chrome(on: display), EditorChrome.place(selection: moved, in: CGSize(width: 1000, height: 800),
                                                                         palette: size))
        XCTAssertEqual(try XCTUnwrap(overlay?.chrome(on: display)).palette.midX, moved.midX, accuracy: 0.001, "the palette is not centred on the new area")
    }

    func testTheSizePlateShowsPixelsWhileReshapingOnA2xDisplayAndNoCrosshairOrPlateAfter() throws {
        let view = try build(scale: 2)
        XCTAssertTrue(view.visiblePlates.isEmpty)
        try pull(view, .bottomRight, by: CGPoint(x: 10, y: 5), release: false)
        XCTAssertEqual(view.visiblePlates.count, 1)
        XCTAssertEqual(view.visiblePlates.first?.string, "820 × 610", "the size is in pixels of the display, 2 to the point")
        overlay?.mouseUp(on: display)
        XCTAssertTrue(view.visiblePlates.isEmpty, "a plate stayed after the release")
    }

    func testEscMidReshapeBringsTheAreaBackAndClosesNothing() throws {
        let view = try build()
        try pull(view, .left, by: CGPoint(x: 50, y: 0), release: false)
        XCTAssertEqual(view.drawnAreaHandles[0].x, 150)
        overlay?.rightMouseDown() // the other door of Esc
        XCTAssertTrue(results.isEmpty, "Esc closed the overlay instead of cancelling the reshape")
        XCTAssertEqual(view.drawnAreaHandles[0].x, 100)
        XCTAssertNotNil(overlay?.chrome(on: display))
        overlay?.mouseUp(on: display)
        XCTAssertEqual(try confirmed().local, CGRect(x: 100, y: 100, width: 400, height: 300))
    }

    func testReshapingIsNoUndoStepAndTheLayersKeepTheirPlaceAndAreClippedByTheNewAreaOnScreen() throws {
        let view = try build()
        drawRectangle(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 450, y: 250))
        overlay?.perform(.tool(.rectangle)) // a tool again so the press cannot select
        XCTAssertEqual(view.drawnShapes.count, 1)
        let before = try XCTUnwrap((view.drawnShapes[0] as? CAShapeLayer)?.path).boundingBoxOfPath
        XCTAssertEqual(before.maxX, 450 + 1.5, accuracy: 2, "the subject: the outline reaches x = 450 before the reshape")
        overlay?.perform(.crop) // the handles of a marked picture are Crop's
        try pull(view, .right, by: CGPoint(x: -150, y: 0))
        XCTAssertEqual(view.drawnShapes.count, 1)
        let after = try XCTUnwrap((view.drawnShapes[0] as? CAShapeLayer)?.path).boundingBoxOfPath
        XCTAssertLessThanOrEqual(after.maxX, 350.001, "the outline spills over the new right edge: \(after)")
        XCTAssertEqual(after.minX, before.minX, accuracy: 0.001, "the layer moved with the area")
        // Undo takes the drawing, which is the one step there is; the reshape was none.
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnShapes.count, 0)
        let (local, layers) = try confirmed()
        XCTAssertTrue(layers.isEmpty)
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 250, height: 300), "the undo walked the area back")
    }

    func testTheLayersAreHandedOnWhereTheyWereDrawnWhateverTheNewAreaIs() throws {
        let view = try build()
        drawRectangle(from: CGPoint(x: 150, y: 150), to: CGPoint(x: 450, y: 250))
        overlay?.perform(.crop)
        try pull(view, .topLeft, by: CGPoint(x: 200, y: 200)) // the area now starts at 300, 300
        let (local, layers) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 300, y: 300, width: 200, height: 100))
        XCTAssertEqual(layers.first?.frame, CGRect(x: 150, y: 150, width: 300, height: 100), "the layer was moved by the reshape")
    }

    // MARK: The arrows

    func testAnArrowMovesTheAreaByOnePixelOrTenWithShiftAtOneTimesAndTwoTimesByKeyCode() throws {
        for (scale, one, ten) in [(CGFloat(1), CGFloat(1), CGFloat(10)), (2, 0.5, 5)] {
            overlay?.close()
            results = []
            _ = try build(scale: scale)
            // The characters are what a Russian layout (or none) types; only the code matters.
            overlay?.keyDown(key(right, "\u{F703}"))
            overlay?.keyDown(key(down, "ы", flags: [.shift, .numericPad, .function]))
            overlay?.keyDown(key(left, ""))
            overlay?.keyDown(key(up, "\u{F700}", flags: [.shift]))
            // right +1, down +10, left −1, up −10, in pixels of the display.
            XCTAssertEqual(try confirmed().local, CGRect(x: 100, y: 100, width: 400, height: 300).offsetBy(dx: 0, dy: 0), "\(scale)x: a net move of nothing on both axes")
            results = []
            overlay?.close()
            _ = try build(scale: scale)
            overlay?.keyDown(key(right, ""))
            overlay?.keyDown(key(down, "", flags: [.shift]))
            XCTAssertEqual(try confirmed().local, CGRect(x: 100 + one, y: 100 + ten, width: 400, height: 300), "\(scale)x")
        }
    }

    func testAnArrowUnderCommandOrOptionIsNotANudge() {
        XCTAssertNil(EditorKeys.action(keyCode: 123, flags: [.command]))
        XCTAssertNil(EditorKeys.action(keyCode: 124, flags: [.option]))
        XCTAssertNil(EditorKeys.action(keyCode: 125, flags: [.control, .shift]))
        XCTAssertEqual(EditorKeys.action(keyCode: 126, flags: [.shift, .numericPad, .function]), .nudge(dx: 0, dy: -1, pixels: 10))
        XCTAssertEqual(EditorKeys.action(keyCode: 123, flags: [.numericPad, .function]), .nudge(dx: -1, dy: 0, pixels: 1))
    }

    func testTheAreaAgainstTheDisplaysEdgeIsStoppedByItAndKeepsItsSize() throws {
        _ = try build(area: CGRect(x: 0, y: 0, width: 300, height: 200))
        overlay?.keyDown(key(left, "", flags: [.shift]))
        overlay?.keyDown(key(up, ""))
        XCTAssertEqual(try confirmed().local, CGRect(x: 0, y: 0, width: 300, height: 200), "the area left the display")
        results = []
        overlay?.close()
        _ = try build(area: CGRect(x: 697, y: 595, width: 300, height: 200))
        overlay?.keyDown(key(right, "", flags: [.shift]))
        overlay?.keyDown(key(down, "", flags: [.shift]))
        XCTAssertEqual(try confirmed().local, CGRect(x: 700, y: 600, width: 300, height: 200), "the step was not cut at the display's edge")
    }

    func testAnArrowMovesTheSelectedObjectAndNotTheAreaAndStaysInsideTheArea() throws {
        let view = try build(scale: 2)
        drawRectangle()
        selectRectangle()
        XCTAssertEqual(view.drawnHandles.first, CGPoint(x: 200, y: 200), "the subject: the object is selected")
        overlay?.keyDown(key(right, "ф"))
        overlay?.keyDown(key(down, "", flags: [.shift]))
        XCTAssertEqual(view.drawnHandles.first, CGPoint(x: 200.5, y: 205), "half a point and five at 2x")
        overlay?.keyDown(key(right, "", flags: [.shift]))
        for _ in 0..<100 { overlay?.keyDown(key(right, "", flags: [.shift], repeating: true)) }
        let (local, layers) = try confirmed()
        XCTAssertEqual(local, CGRect(x: 100, y: 100, width: 400, height: 300), "the area moved with an object selected")
        XCTAssertEqual(try XCTUnwrap(layers.first).frame.maxX, 500, accuracy: 0.001, "the object stopped at the area's wall")
    }

    func testAHeldArrowIsOneUndoStepAndAnotherKeyBetweenSplitsIt() throws {
        let view = try build()
        drawRectangle()
        selectRectangle()
        overlay?.keyDown(key(right, ""))
        for _ in 0..<60 { overlay?.keyDown(key(right, "", repeating: true)) }
        XCTAssertEqual(view.drawnHandles.first?.x, 261, "the held key did not move the object")
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnHandles.first?.x, 200, "61 presses were not one step")
        XCTAssertEqual(view.drawnShapes.count, 1, "the undo went on into the drawing")
        // Another key between two runs: two steps.
        overlay?.perform(.redo)
        overlay?.keyDown(key(kR, "к")) // a tool key is another input
        overlay?.keyDown(key(kR, "к")) // and the tool is down again
        overlay?.keyDown(key(right, ""))
        overlay?.keyDown(key(right, ""))
        XCTAssertEqual(view.drawnHandles.first?.x, 263)
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnHandles.first?.x, 261, "the run after the other key was not its own step")
        overlay?.perform(.undo)
        XCTAssertEqual(view.drawnHandles.first?.x, 200)
    }
}
