import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import QuartzCore
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Where an area's dot and a selected object's square coincide, the square is what is drawn.** A press
/// there goes to the object, so the screen shows the handle the press takes. Read through a `CARenderer`.
@MainActor
final class TheObjectsHandleIsDrawnOverTheAreasTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    func testTheObjectsSquareEdgeIsVisibleWhereTheAreasRightMiddleDotWouldCoverIt() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (w, h) = (Int(screen.frame.width), Int(screen.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: w, height: h), scale: 1,
                                   image: try CompositedPixels.halfBlackPicture(width: w, height: h))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        let view = try XCTUnwrap(built.view(for: id))
        // The area's right middle is (450, 150); the rectangle's corner is there too.
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 450, y: 200), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.rectangle))
        built.mouseDown(on: id, at: CGPoint(x: 350, y: 190), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 450, y: 150), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.rectangle))
        built.mouseDown(on: id, at: CGPoint(x: 400, y: 150), flags: [])
        built.mouseUp(on: id)
        XCTAssertNotNil(view.drawnHandles.first { $0 == CGPoint(x: 450, y: 150) }, "the subject: the object is held at that point")
        built.perform(.crop) // the area's dots over a marked picture are Crop's
        XCTAssertNotNil(view.drawnAreaHandles.first { $0 == CGPoint(x: 450, y: 150) }, "the subject: the area has a dot there")
        let root = try XCTUnwrap(view.layer)
        // The edge is the accent, a dot's fill is white to within a rounding. Three points inside the area's dot (radius 4.5) and on the square's edge (x 454 ± 0.75).
        // The texture's rows run from the bottom, the layers' coordinates are read as the view lays them out.
        let points = [150, 148, 152].map { CGPoint(x: 453, y: h - $0) }
        _ = try CompositedPixels.read(root, width: w, height: h, at: [.zero]) // a first pass draws only the background
        // The subject: the object's own square is drawn here at all, white inside it, the dimmed picture outside it.
        let inside = try CompositedPixels.read(root, width: w, height: h, at: [CGPoint(x: 449, y: h - 150), CGPoint(x: 460, y: h - 150)])
        XCTAssertEqual(inside[0], [255, 255, 255], "the square's white middle is not where it was drawn")
        XCTAssertNotEqual(inside[1], [255, 255, 255], "the picture beside the handle is white, so the read is not at the point")
        for (point, pixel) in zip(points, try CompositedPixels.read(root, width: w, height: h, at: points)) {
            XCTAssertLessThan(Int(pixel.min()!), 200, "\(point): the area's white dot is over the object's square: \(pixel)")
        }
    }
}
