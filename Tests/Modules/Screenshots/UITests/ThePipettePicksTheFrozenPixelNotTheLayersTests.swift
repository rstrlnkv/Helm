import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The eyedropper picks the pixel of the frozen frame under the click, in sRGB, and nothing drawn over it: not the shot with the
/// pointer in it, not the colour of an object laid on the point, not the raw numbers of a Display P3 frame.** A press on the picture
/// ends it, on the area or off it (a press on the palette is the palette's: its actions end the mode, its bare background does not);
/// Esc and the right button put it down and leave the editor; and the pick is the next object's colour.
///
/// The frame here is Display P3 (230, 77, 51), the shot with the pointer solid blue and a filled green rectangle lies over the point,
/// so each wrong source is a different, plain colour. Run in-process: the overlay's own entry points, no real click.
@MainActor
final class ThePipettePicksTheFrozenPixelNotTheLayersTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
    private let area = CGRect(x: 300, y: 100, width: 400, height: 300)
    private let point = CGPoint(x: 400, y: 200)
    /// Display P3 (230, 77, 51) as the frame's own bytes hold it: the one colour the pick is judged against.
    private var frameColour: CGColor { CGColor(colorSpace: p3, components: [230.0 / 255, 77.0 / 255, 51.0 / 255, 1])! }
    private var expected: AnnotationInk { AnnotationInk(frameColour)! }

    private func picture(width: Int, height: Int, in space: CGColorSpace? = nil, _ paint: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space ?? p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        paint(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func solid(_ colour: CGColor, width: Int = 1000, height: Int = 800, in space: CGColorSpace? = nil) throws -> CGImage {
        try picture(width: width, height: height, in: space) { $0.setFillColor(colour); $0.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    }

    /// Builds an overlay over every real screen with `shape` given the display at `index` (its image, scale and shot) and the area
    /// released on it; returns that display's id.
    private func build(display index: Int = 0, scale: CGFloat = 1, image: CGImage? = nil, withCursor: CGImage? = nil,
                       area: CGRect? = nil, release: Bool = true, panel: ColourPanelOpening = FakeColourPanel(),
                       store: NamespacedStore? = nil) throws -> DisplayID {
        var frames = try OverlayRig.frames(scale: 1)
        let base = frames[index]
        let width = Int(1000 * scale), height = Int(800 * scale)
        frames[index] = FrozenDisplay(id: base.id, frame: base.frame, scale: scale,
                                      image: try image ?? solid(frameColour, width: width, height: height),
                                      withCursor: try withCursor ?? solid(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), width: width, height: height))
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store, colourPanel: panel) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        if release {
            let rect = area ?? self.area
            built.mouseDown(on: base.id, at: rect.origin, flags: [])
            built.mouseDragged(on: base.id, at: CGPoint(x: rect.maxX, y: rect.maxY), flags: [])
            built.mouseUp(on: base.id)
        }
        return base.id
    }

    private func click(_ id: DisplayID, _ at: CGPoint) {
        overlay?.mouseDown(on: id, at: at, flags: [])
        overlay?.mouseUp(on: id)
    }

    private func drag(_ id: DisplayID, from: CGPoint, to: CGPoint) {
        overlay?.mouseDown(on: id, at: from, flags: [])
        overlay?.mouseDragged(on: id, at: to, flags: [])
        overlay?.mouseUp(on: id)
    }

    private func esc() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    private func assertNear(_ got: AnnotationInk?, _ want: AnnotationInk, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let got else { return XCTFail("\(message): no colour", file: file, line: line) }
        for (a, b) in zip([got.red, got.green, got.blue], [want.red, want.green, want.blue]) {
            XCTAssertEqual(a, b, accuracy: 2.0 / 255, "\(message): got \(got), wanted \(want)", file: file, line: line)
        }
    }

    private var colour: AnnotationInk? { overlay?.palette.style.color }

    /// A rectangle in the first style the editor has, filled green, over `point`.
    private func laySomethingGreenOverThePoint(_ id: DisplayID) {
        overlay?.perform(.tool(.rectangle))
        overlay?.perform(.color(.green))
        overlay?.perform(.toggleFill)
        drag(id, from: CGPoint(x: 350, y: 150), to: CGPoint(x: 450, y: 250))
    }

    // MARK: the pick

    func testThePickIsTheFramesPixelInSRGBAndNotTheShotTheLayerOrTheRawBytes() throws {
        let id = try build()
        laySomethingGreenOverThePoint(id)
        XCTAssertEqual(colour, .green, "control: the object is green and green is the colour")
        overlay?.perform(.eyedropper)
        click(id, point)
        assertNear(colour, expected, "the pick")
        let raw = AnnotationInk(red: 230.0 / 255, green: 77.0 / 255, blue: 51.0 / 255)!
        XCTAssertGreaterThan(abs(expected.red - raw.red) + abs(expected.green - raw.green) + abs(expected.blue - raw.blue), 0.05,
                             "control: the conversion moves this colour, so the raw bytes are told from it")
        XCTAssertNotEqual(colour, .green, "the colour of the layer on the point")
        XCTAssertNotEqual(colour, .blue, "the shot with the pointer in it")
        XCTAssertGreaterThan(abs((colour?.red ?? 0) - raw.red) + abs((colour?.green ?? 0) - raw.green) + abs((colour?.blue ?? 0) - raw.blue), 0.05,
                             "the frame's raw Display P3 bytes were taken as sRGB")
    }

    func testTheNextObjectIsDrawnInThePickedColourAndTheOneBeforeKeepsItsOwn() throws {
        let id = try build()
        laySomethingGreenOverThePoint(id)
        overlay?.perform(.eyedropper)
        click(id, point)
        drag(id, from: CGPoint(x: 500, y: 150), to: CGPoint(x: 600, y: 250))
        overlay?.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers.first?.style.color, .green, "the object drawn before the pick was recoloured")
        assertNear(layers.last?.style.color, expected, "the next object")
    }

    func testTheFramesScaleIsAppliedAndThePixelIsTheOneUnderThePoint() throws {
        // 2x frame: pixels left of x = 800 (points 400) are one colour, from there on another, so a scale that was not applied,
        // or a point rounded up, reads the neighbour.
        let left = CGColor(colorSpace: p3, components: [230.0 / 255, 77.0 / 255, 51.0 / 255, 1])!
        let right = CGColor(colorSpace: p3, components: [20.0 / 255, 200.0 / 255, 90.0 / 255, 1])!
        let image = try picture(width: 2000, height: 1600) {
            $0.setFillColor(left); $0.fill(CGRect(x: 0, y: 0, width: 800, height: 1600))
            $0.setFillColor(right); $0.fill(CGRect(x: 800, y: 0, width: 1200, height: 1600))
        }
        let id = try build(scale: 2, image: image, withCursor: try solid(.black, width: 2000, height: 1600))
        overlay?.perform(.eyedropper)
        click(id, CGPoint(x: 399.75, y: 200))
        assertNear(colour, AnnotationInk(left)!, "a point in the last left-hand pixel")
        overlay?.perform(.eyedropper)
        click(id, CGPoint(x: 400.25, y: 200))
        assertNear(colour, AnnotationInk(right)!, "a point in the first right-hand pixel")
    }

    func testTheCornerPixelsOfTheDisplayArePickedAtTheirEdges() throws {
        let corner = CGColor(colorSpace: p3, components: [20.0 / 255, 200.0 / 255, 90.0 / 255, 1])!
        let image = try picture(width: 1000, height: 800) {
            $0.setFillColor(frameColour); $0.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
            $0.setFillColor(corner)
            $0.fill(CGRect(x: 0, y: 800 - 1, width: 1, height: 1))     // top-left pixel (CGContext's origin is bottom-left)
            $0.fill(CGRect(x: 999, y: 0, width: 1, height: 1))         // bottom-right pixel
        }
        let id = try build(image: image, area: CGRect(x: 0, y: 0, width: 600, height: 500))
        overlay?.perform(.eyedropper)
        click(id, CGPoint(x: 0, y: 0))
        assertNear(colour, AnnotationInk(corner)!, "the display's first pixel, at the area's own corner")
        overlay?.perform(.eyedropper)
        click(id, CGPoint(x: 100, y: 100))
        assertNear(colour, expected, "control: an interior point is the frame's colour, so the corner was read for itself")
        // The bottom-right pixel of the display, with the area reaching it.
        overlay?.close()
        let second = try build(image: image, area: CGRect(x: 400, y: 300, width: 600, height: 500))
        let chrome = overlay?.chrome(on: second)
        let edge = CGPoint(x: 999.75, y: 799.75)
        XCTAssertNotEqual(chrome?.covers(edge), true, "control: the palette is not over the corner, so the press is the picture's")
        overlay?.perform(.eyedropper)
        click(second, edge)
        assertNear(colour, AnnotationInk(corner)!, "the display's last pixel")
    }

    func testAPickOnTheSecondDisplayReadsThatDisplaysFrameNotTheFirst() throws {
        guard NSScreen.screens.count > 1 else { throw XCTSkip("one screen on this Mac: the second display's frame cannot be built") }
        var frames = try OverlayRig.frames(scale: 1)
        let other = CGColor(colorSpace: p3, components: [20.0 / 255, 200.0 / 255, 90.0 / 255, 1])!
        let secondID = frames[1].id
        frames[0] = FrozenDisplay(id: frames[0].id, frame: frames[0].frame, scale: 1, image: try solid(frameColour), withCursor: nil)
        frames[1] = FrozenDisplay(id: secondID, frame: frames[1].frame, scale: 1, image: try solid(other), withCursor: try solid(.black))
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), colourPanel: FakeColourPanel()) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: secondID, at: area.origin, flags: [])
        built.mouseDragged(on: secondID, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: secondID)
        built.perform(.eyedropper)
        click(secondID, point)
        assertNear(colour, AnnotationInk(other)!, "the second display's pixel")
        // And a press on the first display, with the area on the second, picks nothing and puts the mode down.
        overlay?.perform(.color(.red))
        overlay?.perform(.eyedropper)
        click(frames[0].id, point)
        XCTAssertEqual(colour, .red, "a click on another display than the area's picked a colour")
    }

    // MARK: the loupe and the mode

    func testTheLoupeFollowsThePointerOverTheAreaWhileSamplingAndIsGoneAfter() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.mouseMoved(on: id, at: point)
        XCTAssertNil(view.loupeReading, "the loupe is up before the eyedropper is on")
        overlay?.perform(.eyedropper)
        overlay?.mouseMoved(on: id, at: point)
        let reading = try XCTUnwrap(view.loupeReading, "sampling, the pointer is on the area, and no loupe")
        XCTAssertTrue(reading.contains("#"), "the plate does not read a colour: \(reading)")
        XCTAssertNotNil(view.loupeDisc)
        overlay?.mouseMoved(on: id, at: CGPoint(x: 50, y: 50))
        XCTAssertNil(view.loupeReading, "the pointer is off the area and the loupe stays")
        overlay?.mouseMoved(on: id, at: point)
        XCTAssertNotNil(view.loupeReading, "control: back on the area it shows again")
        click(id, point)
        XCTAssertNil(view.loupeReading, "the pick ended the mode and the loupe stays")
        overlay?.mouseMoved(on: id, at: CGPoint(x: 410, y: 210))
        XCTAssertNil(view.loupeReading, "a move after the pick brought the loupe back")
    }

    func testTheModeHasItsCursorOnEveryDisplayFromTheFirstMomentToItsEnd() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        let others = try OverlayRig.frames(scale: 1).dropFirst().compactMap { overlay?.view(for: $0.id) }
        XCTAssertTrue(view.askedCursor === NSCursor.crosshair, "control: the crosshair before the mode")
        overlay?.perform(.eyedropper)
        XCTAssertTrue(view.askedCursor === OverlayView.eyedropperCursor, "the mode is on and the cursor is not its own")
        overlay?.mouseMoved(on: id, at: CGPoint(x: 50, y: 50))
        XCTAssertTrue(view.askedCursor === OverlayView.eyedropperCursor, "off the area the cursor is not the eyedropper's")
        // Another display than the area's, where the rig has one: its view asks for the symbol too.
        for other in others { XCTAssertTrue(other.askedCursor === OverlayView.eyedropperCursor, "another display keeps the crosshair") }
        click(id, point)
        XCTAssertTrue(view.askedCursor === NSCursor.crosshair, "the pick ended the mode and the cursor stays")
        for other in others { XCTAssertTrue(other.askedCursor === NSCursor.crosshair, "the pick ended the mode and another display's cursor stays") }
    }

    /// Each way the mode ends hands the cursor back, the way the pick does: Esc, the right button, a click off the area,
    /// another palette action. The mode is asserted on first, so a cursor that never changed cannot pass.
    func testEveryOtherEndOfTheModeHandsTheCrosshairBack() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        let ends: [(String, () -> Void)] = [
            ("Esc", { self.overlay?.keyDown(self.esc()) }),
            ("the right button", { self.overlay?.rightMouseDown() }),
            ("a click off the area", { self.click(id, CGPoint(x: 50, y: 50)) }),
            ("a tool", { self.overlay?.perform(.tool(.pen)) }),
            ("the colours", { self.overlay?.perform(.colours(anchorX: 100)) }),
            ("the thickness", { self.overlay?.perform(.thicknessAndOpacity(anchorX: 100)) }),
            ("a colour", { self.overlay?.perform(.color(.red)) }),
            ("the ruler", { self.overlay?.perform(.toggleRuler) }),
        ]
        for (name, end) in ends {
            overlay?.perform(.eyedropper)
            XCTAssertTrue(view.askedCursor === OverlayView.eyedropperCursor, "control: before \(name) the mode is on")
            end()
            XCTAssertTrue(view.askedCursor === NSCursor.crosshair, "\(name) ended the mode and the cursor stayed the eyedropper's")
            // Put the state back for the next end: no tool, no ruler.
            overlay?.perform(.select)
            if overlay?.rulerOnThePicture != nil { overlay?.perform(.toggleRuler) }
        }
    }

    /// With the eraser on and the eyedropper asked for, the cursor is the eyedropper's (the next press is a pick, not an erase), and the
    /// eraser's circle comes back when the mode ends; the eyedropper's own cursor is never what the view keeps once the mode is over.
    /// With the eyedropper on and the eraser asked for, the eraser's action ends the mode and is itself the toggle it is without it.
    func testTheEraserCursorComesBackWhenTheModeEnds() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.perform(.erase)
        XCTAssertTrue(view.askedCursor === OverlayView.eraserCursor, "control: the eraser's circle")
        overlay?.perform(.eyedropper)
        XCTAssertTrue(view.askedCursor === OverlayView.eyedropperCursor, "the eraser is on and the eyedropper asked, and the circle is the cursor of a press that picks")
        overlay?.keyDown(esc())
        XCTAssertTrue(view.askedCursor === OverlayView.eraserCursor, "Esc ended the eyedropper and the eraser's circle did not come back")
        overlay?.perform(.eyedropper)
        click(id, point)
        XCTAssertTrue(view.askedCursor === OverlayView.eraserCursor, "the pick ended the eyedropper and the eraser's circle did not come back")
        // The eraser is still on here. The eyedropper first, then the eraser: the action ends the mode and, being the eraser's key, puts the
        // eraser down (a toggle); with it down, the same two put it up.
        overlay?.perform(.eyedropper)
        overlay?.perform(.erase)
        XCTAssertTrue(view.askedCursor === NSCursor.crosshair, "the eraser's action under the eyedropper left the mode on or the eraser on")
        overlay?.perform(.eyedropper)
        overlay?.perform(.erase)
        XCTAssertTrue(view.askedCursor === OverlayView.eraserCursor, "with the mode over, the eraser asked for is on and its circle is the cursor")
    }

    func testTheCameraStaysTheCursorOfTheWindowModeAndIsDrawnAsBefore() throws {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), mode: .window, colourPanel: FakeColourPanel()) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let view = try XCTUnwrap(built.view(for: try XCTUnwrap(frames.first).id))
        let camera = view.askedCursor
        XCTAssertFalse(camera === NSCursor.crosshair, "the window mode asks the crosshair")
        XCTAssertFalse(camera === OverlayView.eyedropperCursor || camera === OverlayView.eraserCursor)
        // The construction the refactor took the camera's from: 28 by 24, the hot spot in the middle.
        XCTAssertEqual(camera.image.size, NSSize(width: 28, height: 24))
        XCTAssertEqual(camera.hotSpot, NSPoint(x: 14, y: 12))
        XCTAssertEqual(OverlayView.eyedropperCursor.image.size, NSSize(width: 24, height: 24))
        XCTAssertEqual(OverlayView.eyedropperCursor.hotSpot, NSPoint(x: 3, y: 21))
    }

    func testTheLoupeReadsTheFrameNotTheShotWithThePointer() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.perform(.eyedropper)
        overlay?.mouseMoved(on: id, at: point)
        let reading = try XCTUnwrap(view.loupeReading)
        XCTAssertFalse(reading.uppercased().contains("0000FF"), "the plate reads the shot with the pointer: \(reading)")
    }

    func testASecondClickPicksNothing() throws {
        let id = try build()
        overlay?.perform(.eyedropper)
        click(id, point)
        overlay?.perform(.color(.red))
        click(id, point)
        XCTAssertEqual(colour, .red, "the mode stayed on after one pick")
        overlay?.perform(.eyedropper)
        click(id, point)
        assertNear(colour, expected, "control: asked for again, it picks again")
    }

    func testEscPutsItDownAndLeavesTheEditorAndThenPicksNothing() throws {
        let id = try build()
        laySomethingGreenOverThePoint(id)
        overlay?.perform(.eyedropper)
        overlay?.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "Esc closed the editor")
        click(id, point)
        XCTAssertEqual(colour, .green, "Esc did not put the eyedropper down")
        overlay?.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "the Esc that put the eyedropper down was also the rule's first press, and the layer's second one closed")
        overlay?.keyDown(esc())
        overlay?.keyDown(esc())
        XCTAssertEqual(results.count, 1, "control: the rule's own presses still close the editor")
    }

    func testAClickOutsideTheAreaPicksNothingAndPutsItDown() throws {
        let id = try build()
        overlay?.perform(.color(.red))
        overlay?.perform(.eyedropper)
        click(id, CGPoint(x: 50, y: 50))
        XCTAssertEqual(colour, .red, "a click outside the area picked")
        click(id, point)
        XCTAssertEqual(colour, .red, "the click outside did not end the mode")
        XCTAssertTrue(results.isEmpty)
        // A click on the area's own rim from outside, one point short of it.
        overlay?.perform(.eyedropper)
        click(id, CGPoint(x: area.minX - 1, y: area.midY))
        XCTAssertEqual(colour, .red, "a click one point outside the area picked")
    }

    func testTheRightButtonPutsItDownPicksNothingAndLeavesTheEditor() throws {
        let id = try build()
        overlay?.perform(.color(.red))
        overlay?.perform(.eyedropper)
        overlay?.rightMouseDown()
        XCTAssertTrue(results.isEmpty, "the right button that put the eyedropper down closed the editor")
        XCTAssertEqual(colour, .red)
        click(id, point)
        XCTAssertEqual(colour, .red, "the right button left the mode on")
    }

    func testAnyOtherPaletteActionPutsItDown() throws {
        let id = try build()
        for other in [EditorAction.tool(.pen), .colours(anchorX: 100), .thicknessAndOpacity(anchorX: 100), .erase, .toggleRuler, .color(.red)] {
            overlay?.perform(.color(.red))
            overlay?.perform(.eyedropper)
            overlay?.perform(other)
            if case .color = other {} else { overlay?.perform(.color(.red)) }
            click(id, CGPoint(x: 650, y: 350))
            XCTAssertEqual(colour, .red, "\(other) left the eyedropper on")
        }
    }

    // MARK: inputs nobody fed it

    func testWithNoAreaTheEyedropperIsNothingAndDoesNotWaitForTheNextArea() throws {
        let id = try build(release: false)
        overlay?.perform(.eyedropper)
        // The area released afterwards: the mode was not left armed for it.
        drag(id, from: area.origin, to: CGPoint(x: area.maxX, y: area.maxY))
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.mouseMoved(on: id, at: point)
        XCTAssertNil(view.loupeReading, "an eyedropper asked for with no edit open was on when the area came")
        overlay?.perform(.color(.red))
        click(id, point)
        XCTAssertEqual(colour, .red)
    }

    func testAskedForWhileOnItStaysOn() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.perform(.eyedropper)
        overlay?.perform(.eyedropper)
        overlay?.perform(.eyedropper, isRepeat: true)
        overlay?.mouseMoved(on: id, at: point)
        XCTAssertNotNil(view.loupeReading, "asked again, the mode went off")
    }

    func testPressedFromTheOpenColoursPopoverItClosesTheOneAndOpensTheOther() throws {
        let id = try build()
        let view = try XCTUnwrap(overlay?.view(for: id))
        overlay?.perform(.colours(anchorX: 100))
        XCTAssertTrue(overlay?.coloursAreOpen == true, "control: the pop-over is open")
        overlay?.perform(.eyedropper)
        XCTAssertFalse(overlay?.popoverIsOpen == true, "the pop-over stayed over the area the eyedropper is to read")
        overlay?.mouseMoved(on: id, at: point)
        XCTAssertNotNil(view.loupeReading)
        click(id, point)
        assertNear(colour, expected, "the pick")
    }

    func testAClickWhileAPopoverIsOpenClosesItAndPicksNothing() throws {
        let id = try build()
        overlay?.perform(.tool(.pen))
        overlay?.perform(.color(.red))
        overlay?.perform(.eyedropper)
        overlay?.perform(.thicknessAndOpacity(anchorX: 100))
        XCTAssertTrue(overlay?.popoverIsOpen == true, "control: open")
        click(id, point)
        XCTAssertEqual(colour, .red, "the click that closed the pop-over picked")
        XCTAssertFalse(overlay?.popoverIsOpen == true)
    }

    func testAnEditorLeftWithItOnIsNotOnInTheNextOne() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let id = try build(store: store)
        overlay?.perform(.eyedropper)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(results.count, 1)
        results = []
        let next = try build(store: store)
        overlay?.perform(.color(.red))
        let view = try XCTUnwrap(overlay?.view(for: next))
        overlay?.mouseMoved(on: next, at: point)
        XCTAssertNil(view.loupeReading)
        click(next, point)
        XCTAssertEqual(colour, .red)
        _ = id
    }
}
