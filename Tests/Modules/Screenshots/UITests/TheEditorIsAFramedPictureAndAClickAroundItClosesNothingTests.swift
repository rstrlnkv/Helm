import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«Edit» is a framed picture on a dimmed screen: a press around the picture closes nothing and leaves the area as it was, and a
/// picture as large as the display stands with room round it for the handles and the palette.** The overlay is opened on a
/// picture the way `CaptureController.edit` opens it (`PictureOnScreen.place`, `CaptureOverlay(freeze:picture:)`), worked by
/// hand with mouse events, and what is read is what it delivered (`onFinish`), whether it is still open, and its area.
/// The ordinary capture, which has no picture, is held as it was by the second half: a usable drag outside the area replaces it,
/// an unusable one keeps it, and neither finishes anything.
///
/// Total failure of the subject prints: an editor that delivers or closes on a press beside the picture, an area that a press
/// or drag started beside the picture has moved or shrunk, a picture that touches the display's edge, or an ordinary capture
/// that lost its new drag.
@MainActor
final class TheEditorIsAFramedPictureAndAClickAroundItClosesNothingTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func solid(_ width: Int, _ height: Int) throws -> CGImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: srgb, components: [0, 0, 1, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// An editor open on a 400×300 picture, over the 1000×800-point display of `OverlayRig`: the picture stands at (300, 250).
    private func openEditor() throws -> (overlay: CaptureOverlay, display: DisplayID, area: CGRect) {
        let frames = try OverlayRig.frames(scale: 1)
        let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
        let first = try XCTUnwrap(frames.first?.id)
        let shown = try XCTUnwrap(PictureOnScreen.place(try solid(400, 300), over: freeze, on: first))
        let built = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(built.build())
        overlay = built
        XCTAssertEqual(built.editedArea, shown.rect, "the control: the editor is up on the picture's own rectangle")
        XCTAssertTrue(shown.rect.width > 0 && shown.rect.minX > 20, "the control: the picture stands clear of the display's left edge")
        return (built, shown.display, shown.rect)
    }

    private func click(_ overlay: CaptureOverlay, _ display: DisplayID, _ point: CGPoint) {
        overlay.mouseDown(on: display, at: point, flags: [])
        overlay.mouseUp(on: display)
    }

    private func drag(_ overlay: CaptureOverlay, _ display: DisplayID, from: CGPoint, to: CGPoint) {
        overlay.mouseDown(on: display, at: from, flags: [])
        overlay.mouseDragged(on: display, at: to, flags: [])
        overlay.mouseUp(on: display)
    }

    /// Points that are on the display and not on the picture, on every side of it.
    private func around(_ area: CGRect) -> [CGPoint] {
        [CGPoint(x: 10, y: 10), CGPoint(x: 990, y: 790), CGPoint(x: area.minX - 15, y: area.midY), CGPoint(x: area.maxX + 15, y: area.midY),
         CGPoint(x: area.midX, y: area.minY - 15), CGPoint(x: area.midX, y: area.maxY + 15)]
    }

    // MARK: A press around the picture closes nothing

    func testAClickAroundThePictureWithNoToolClosesAndDeliversNothingAndLeavesTheArea() throws {
        let (overlay, display, area) = try openEditor()
        for point in around(area) {
            click(overlay, display, point)
            XCTAssertTrue(results.isEmpty, "a click at \(point) beside the picture ended the edit: \(results)")
            XCTAssertTrue(overlay.isOpen, "a click at \(point) beside the picture closed the editor")
            XCTAssertEqual(overlay.editedArea, area, "a click at \(point) beside the picture moved the area")
        }
    }

    func testADragThatStartsBesideThePictureLeavesTheAreaTheWholePictureAndFinishesNothing() throws {
        let (overlay, display, area) = try openEditor()
        for start in around(area) {
            drag(overlay, display, from: start, to: CGPoint(x: area.midX, y: area.midY))
            XCTAssertTrue(results.isEmpty, "a drag from \(start) beside the picture ended the edit: \(results)")
            XCTAssertEqual(overlay.editedArea, area, "a drag from \(start) beside the picture cut the picture's area down to \(String(describing: overlay.editedArea))")
        }
    }

    func testAClickAroundThePictureWithAToolAndALayerClosesNothingAndDrawsNothing() throws {
        let (overlay, display, area) = try openEditor()
        overlay.perform(.tool(.rectangle))
        drag(overlay, display, from: CGPoint(x: area.minX + 50, y: area.minY + 50), to: CGPoint(x: area.minX + 150, y: area.minY + 120))
        XCTAssertEqual(overlay.editedLayers.count, 1, "the control: a rectangle was drawn on the picture")
        for point in around(area) {
            click(overlay, display, point)
            drag(overlay, display, from: point, to: CGPoint(x: point.x + 3, y: point.y + 3))
            XCTAssertTrue(results.isEmpty, "a press at \(point) beside the picture ended the edit: \(results)")
            XCTAssertTrue(overlay.isOpen)
            XCTAssertEqual(overlay.editedArea, area)
            XCTAssertEqual(overlay.editedLayers.count, 1, "a press beside the picture changed the layers")
        }
    }

    /// Through the view with real events, the wiring from the mouse as the running app has it: a left press and release far from
    /// the picture: (5, 5) is read as (5, H − 5) with H the real screen's height, a corner of the view below the rig's 800-pt display.
    func testARealLeftClickInTheCornerThroughTheViewClosesNothing() throws {
        let (overlay, display, area) = try openEditor()
        let view = try XCTUnwrap(overlay.view(for: display))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0,
                                                         windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
        XCTAssertTrue(results.isEmpty, "a real click in the corner ended the edit: \(results)")
        XCTAssertTrue(overlay.isOpen)
        XCTAssertEqual(overlay.editedArea, area)
    }

    /// The way out is still there: Return delivers the whole picture once, after all those clicks.
    func testAfterTheClicksReturnStillDeliversTheWholePictureOnce() throws {
        let (overlay, display, area) = try openEditor()
        for point in around(area) { click(overlay, display, point) }
        overlay.perform(.exit(.confirm))
        guard results.count == 1, case .edited(let shown, let local, _, let exit) = results[0] else { return XCTFail("\(results)") }
        XCTAssertEqual(shown, display)
        XCTAssertEqual(local, area)
        XCTAssertEqual(exit, .confirm)
    }

    // MARK: The ordinary capture is as it was

    /// The ordinary capture is not the editor: with no picture a press outside the drawn area starts a new drag, a usable one replaces
    /// the area, an unusable one keeps it, and neither finishes anything.
    func testTheOrdinaryCaptureStillTakesAPressOutsideTheAreaAsANewDrag() throws {
        var delivered: [OverlayResult] = []
        let rig = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 200, height: 150)) { delivered.append($0) }
        overlay = rig.overlay
        XCTAssertEqual(rig.overlay.editedArea, CGRect(x: 100, y: 100, width: 200, height: 150))
        click(rig.overlay, rig.display, CGPoint(x: 700, y: 600))
        XCTAssertEqual(rig.overlay.editedArea, CGRect(x: 100, y: 100, width: 200, height: 150), "an unusable drag outside replaced the area")
        drag(rig.overlay, rig.display, from: CGPoint(x: 500, y: 400), to: CGPoint(x: 640, y: 520))
        XCTAssertEqual(rig.overlay.editedArea, CGRect(x: 500, y: 400, width: 140, height: 120), "a usable drag outside did not replace the area")
        XCTAssertTrue(delivered.isEmpty, "a press outside finished the ordinary capture: \(delivered)")
        XCTAssertTrue(rig.overlay.isOpen)
    }

    // MARK: The frame itself

    /// The card layer the view draws (a black rectangle with a shadow, masked to what is outside it): on the picture path its path is the
    /// picture's rectangle (the view's y runs up, so the rectangle's y is the view's height less the picture's bottom), on the ordinary
    /// path it has none. Read off the view's layers, since `OverlayScene.card` is built inside the overlay and not kept.
    private func cardPath(of view: NSView) -> CGPath? {
        let cards = (view.layer?.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.filter { $0.shadowOpacity > 0 && $0.mask != nil }
        XCTAssertEqual(cards.count, 1, "the control: the view has one card layer")
        return cards.first?.path
    }

    func testTheEditorStandsTheFramedPictureAsACardAndTheOrdinaryCaptureHasNone() throws {
        let (overlay, display, area) = try openEditor()
        let view = try XCTUnwrap(overlay.view(for: display))
        let path = try XCTUnwrap(cardPath(of: view), "the editor drew no card behind the picture")
        let expected = CGRect(x: area.minX, y: view.bounds.height - area.maxY, width: area.width, height: area.height)
        XCTAssertEqual(path.boundingBox, expected, "the card is not the picture's rectangle")
        XCTAssertGreaterThan(area.width, 0, "the control: there is a picture")

        let rig = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 200, height: 150)) { _ in }
        defer { rig.overlay.close() }
        let plain = try XCTUnwrap(rig.overlay.view(for: rig.display))
        XCTAssertNil(cardPath(of: plain), "the ordinary capture has a card")
    }

    // MARK: A picture as large as the display stands with room round it

    /// What the handles (round dots of radius `AreaFrame.dotRadius`, 4.5 pt, on the area's edge) and the palette (`EditorPalette.height`, above or below the area) need, taken
    /// as the least the test can name: 16 pt at the sides and what `EditorChrome.place` needs at the top and the bottom (the palette, the gap, the margin: 106 pt), where the centred
    /// picture leaves the same on both. The picture is not enlarged and not shifted, so it is also centred.
    func testAPictureAsLargeAsTheDisplayIsPlacedWithRoomRoundItAndCentred() throws {
        for (width, height, scale) in [(1000, 800, CGFloat(1)), (2000, 1600, 2), (3000, 2000, 1), (1000, 800, 2)] {
            let display = CGSize(width: 1000 * scale, height: 800 * scale)
            let image = try OverlayRig.frames(scale: scale)
            let freeze = Freeze(displays: image.map { .image($0) }, windows: [])
            let first = try XCTUnwrap(image.first?.id)
            let big = try solid(width, height)
            let placed = try XCTUnwrap(PictureOnScreen.place(big, over: freeze, on: first), "\(width)×\(height) at \(scale)×")
            let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
            let rect = placed.rect
            XCTAssertEqual(display.width / scale, 1000)
            XCTAssertGreaterThanOrEqual(rect.minX, 16, "\(width)×\(height) at \(scale)×: left margin \(rect.minX) leaves no room for the handles")
            XCTAssertGreaterThanOrEqual(bounds.maxX - rect.maxX, 16, "\(width)×\(height) at \(scale)×: right margin")
            XCTAssertGreaterThanOrEqual(rect.minY, EditorChrome.paletteHeight + EditorChrome.gap + EditorChrome.margin, "\(width)×\(height) at \(scale)×: top margin \(rect.minY) is less than the palette")
            XCTAssertGreaterThanOrEqual(bounds.maxY - rect.maxY, EditorChrome.paletteHeight + EditorChrome.gap + EditorChrome.margin, "\(width)×\(height) at \(scale)×: bottom margin")
            XCTAssertEqual(rect.midX, bounds.midX, accuracy: 1, "not centred across")
            XCTAssertEqual(rect.midY, bounds.midY, accuracy: 1, "not centred down")
            // The export stays at the picture's own size, whatever the margin took off the screen.
            XCTAssertEqual(placed.picture.width, width)
            XCTAssertEqual(placed.picture.height, height)
            XCTAssertEqual(placed.pixelsPerPoint, max(CGFloat(width) / rect.width, CGFloat(height) / rect.height), accuracy: 1e-9)
            XCTAssertGreaterThan(placed.pixelsPerPoint * rect.width, CGFloat(width) - 1.5, "the area does not reach the picture's last column")
            XCTAssertGreaterThan(placed.pixelsPerPoint * rect.height, CGFloat(height) - 1.5, "the area does not reach the picture's last row")
        }
    }

    /// The handles are round dots (`AreaFrame.dotRadius`, 4.5 pt) centred on the area's edge and the palette stands above or below the area: with a picture as large as the
    /// display, read off the model (`editedArea`, `chrome(on:)`), the handles' outer edge (`AreaFrame.dotRadius` beyond the area, read from it and not written as a number) and the whole palette lie
    /// inside the display, and the palette does not stand on the picture. (Whether the room is wide enough for the pop-overs is not here.)
    func testTheHandlesAndThePaletteOfADisplaySizedPictureLieInsideTheDisplay() throws {
        for (width, height, scale) in [(1000, 800, CGFloat(1)), (2000, 1600, 2), (3000, 2000, 1)] {
            let frames = try OverlayRig.frames(scale: scale)
            let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
            let first = try XCTUnwrap(frames.first?.id)
            let shown = try XCTUnwrap(PictureOnScreen.place(try solid(width, height), over: freeze, on: first))
            let built = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil) { [weak self] in self?.results.append($0) }
            XCTAssertTrue(built.build())
            overlay?.close()
            overlay = built
            let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
            let area = try XCTUnwrap(built.editedArea, "\(width)×\(height) at \(scale)×")
            XCTAssertTrue(bounds.contains(area.insetBy(dx: -AreaFrame.dotRadius, dy: -AreaFrame.dotRadius)), "\(width)×\(height) at \(scale)×: the handles on \(area) are cut by the display")
            let chrome = try XCTUnwrap(built.chrome(on: first), "\(width)×\(height) at \(scale)×: no palette")
            XCTAssertGreaterThan(chrome.palette.height, 0, "the control: the palette was measured")
            XCTAssertTrue(bounds.contains(chrome.palette), "\(width)×\(height) at \(scale)×: the palette \(chrome.palette) is cut by the display")
        }
    }

    /// `EditorChrome` puts the palette below or above the area only when its height, `gap` (14) and `margin` (16) fit on that side,
    /// 106 pt for the 76-pt palette, and `PictureOnScreen.margin` keeps that much above and below: so for a display-sized picture the
    /// palette stands outside the picture and not inside it against its bottom edge.
    func testThePaletteOfADisplaySizedPictureDoesNotStandOnThePicture() throws {
        for (width, height, scale) in [(1000, 800, CGFloat(1)), (2000, 1600, 2), (3000, 2000, 1)] {
            let frames = try OverlayRig.frames(scale: scale)
            let freeze = Freeze(displays: frames.map { .image($0) }, windows: [])
            let first = try XCTUnwrap(frames.first?.id)
            let shown = try XCTUnwrap(PictureOnScreen.place(try solid(width, height), over: freeze, on: first))
            let built = CaptureOverlay(freeze: shown.freeze, picture: (shown.display, shown.rect), store: nil) { [weak self] in self?.results.append($0) }
            XCTAssertTrue(built.build())
            overlay?.close()
            overlay = built
            let area = try XCTUnwrap(built.editedArea)
            let chrome = try XCTUnwrap(built.chrome(on: first), "\(width)×\(height) at \(scale)×: no palette")
            XCTAssertGreaterThan(chrome.palette.height, 0, "the control: the palette was measured")
            XCTAssertFalse(chrome.palette.intersects(area), "\(width)×\(height) at \(scale)×: the palette \(chrome.palette) stands on the picture \(area)")
        }
    }

    // MARK: A right click

    /// The right click is Esc's other door (`rightMouseDown()`), and beside the picture it is the ground's: nothing leaves, with no layer
    /// and with one, and the area and the layer stay.
    func testARightClickBesideThePictureFinishesNothingAndLeavesTheEditorUp() throws {
        let (overlay, display, area) = try openEditor()
        for point in around(area) {
            overlay.rightMouseDown(on: display, at: point)
            XCTAssertTrue(results.isEmpty, "a right click at \(point) beside the picture finished the edit: \(results)")
            XCTAssertTrue(overlay.isOpen, "a right click at \(point) beside the picture closed the editor")
            XCTAssertEqual(overlay.editedArea, area)
            XCTAssertTrue(overlay.editedLayers.isEmpty)
        }
        overlay.perform(.tool(.rectangle))
        drag(overlay, display, from: CGPoint(x: area.minX + 50, y: area.minY + 50), to: CGPoint(x: area.minX + 150, y: area.minY + 120))
        XCTAssertEqual(overlay.editedLayers.count, 1, "the control: a rectangle was drawn on the picture")
        for point in around(area) {
            overlay.rightMouseDown(on: display, at: point)
            XCTAssertTrue(results.isEmpty, "a right click at \(point) beside the picture, with a layer, finished the edit: \(results)")
            XCTAssertEqual(overlay.editedLayers.count, 1, "a right click beside the picture took the layer away")
        }
        XCTAssertTrue(overlay.isOpen)
    }

    /// The same through the view with a real `NSEvent`: the point the view reads the event at is what is asked, and a corner is not the picture.
    func testARealRightClickBesideThePictureThroughTheViewFinishesNothing() throws {
        let (overlay, display, area) = try openEditor()
        let view = try XCTUnwrap(overlay.view(for: display))
        // The view is the real screen's size, not the rig's 1000×800 display: the window's corners (x of 5 or 995, y of 5 or the view's height less 5)
        // read as points at the display's left edge and 995 across, and at its top and far below: none of them on the picture (300 to 700 across).
        XCTAssertGreaterThan(view.bounds.height, 400, "the control: the view has a height to turn the event's y over")
        for location in [CGPoint(x: 5, y: 5), CGPoint(x: 995, y: view.bounds.height - 5), CGPoint(x: 5, y: view.bounds.height - 5), CGPoint(x: 995, y: 5)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                                         windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            view.rightMouseDown(with: event)
            XCTAssertTrue(results.isEmpty, "a real right click at \(location) beside the picture finished the edit: \(results)")
            XCTAssertTrue(overlay.isOpen)
            XCTAssertEqual(overlay.editedArea, area)
        }
    }

    /// On the picture it is Esc as it was: with nothing drawn the edit is cancelled, once. Held as it was, not new.
    func testARightClickOnThePictureIsStillEscape() throws {
        let (overlay, display, area) = try openEditor()
        overlay.rightMouseDown(on: display, at: CGPoint(x: area.midX, y: area.midY))
        XCTAssertEqual(results.count, 1, "\(results)")
        guard case .cancelled? = results.first else { return XCTFail("a right click on the picture with nothing drawn did not cancel: \(results)") }
    }

    func testARealRightClickOnThePictureThroughTheViewIsStillEscape() throws {
        let (overlay, display, area) = try openEditor()
        let view = try XCTUnwrap(overlay.view(for: display))
        // The view is the real screen's size and not the frozen display's (the rig's frame is 1000×800), and it turns the event's y over by
        // its own height: the point that reads as the picture's middle, (500, 400) of the display, is at y = height − 400 in the window.
        XCTAssertGreaterThan(view.bounds.height, 400, "the control: the view is tall enough to hold the picture's middle")
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: area.midX, y: view.bounds.height - area.midY), modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.rightMouseDown(with: event)
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    /// No picture: the ordinary capture's right click anywhere is Esc, as it was, at any point.
    func testTheOrdinaryCapturesRightClickIsStillEscapeAnywhere() throws {
        for point in [CGPoint(x: 5, y: 5), CGPoint(x: 150, y: 150), CGPoint(x: 700, y: 600)] {
            var delivered: [OverlayResult] = []
            let rig = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 200, height: 150)) { delivered.append($0) }
            rig.overlay.rightMouseDown(on: rig.display, at: point)
            XCTAssertEqual(delivered.count, 1, "a right click at \(point) on the ordinary capture: \(delivered)")
            guard case .cancelled? = delivered.first else { return XCTFail("\(delivered)") }
            rig.overlay.close()
        }
    }

    /// A picture that already fits with room to spare is not shrunk: the margin is a limit and not a shrink of everything.
    func testASmallPictureIsNotShrunkByTheMargin() throws {
        let image = try OverlayRig.frames(scale: 1)
        let freeze = Freeze(displays: image.map { .image($0) }, windows: [])
        let placed = try XCTUnwrap(PictureOnScreen.place(try solid(400, 300), over: freeze, on: image[0].id))
        XCTAssertEqual(placed.rect.size, CGSize(width: 400, height: 300))
        XCTAssertEqual(placed.rect.origin, CGPoint(x: 300, y: 250))
    }
}
