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

/// **The box round the selected object is an outline, not a plate.** One path holding the box and the
/// handles under the handles' white fill painted the whole box white, so the selected object vanished
/// under its own frame. The pixels are read through a `CARenderer`, as in `TheMarkerMultipliesOnScreenTests`,
/// in both appearances.
@MainActor
final class TheSelectionFrameLeavesTheObjectVisibleTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func selectedFilledRectangle(in appearance: NSAppearance.Name) throws
        -> (view: OverlayView, width: Int, height: Int, box: CGRect) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (w, h) = (Int(screen.frame.width), Int(screen.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: w, height: h), scale: 1,
                                   image: try CompositedPixels.halfBlackPicture(width: w, height: h))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)], windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        let view = try XCTUnwrap(built.view(for: id))
        view.appearance = NSAppearance(named: appearance)
        built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: w - 50, y: h - 50), flags: [])
        built.mouseUp(on: id)
        // Red, filled, centred on the display; the same key again puts the tool down.
        let box = CGRect(x: w / 2 - 100, y: h / 2 - 80, width: 200, height: 160)
        built.perform(.color(.red))
        built.perform(.toggleFill)
        built.perform(.tool(.rectangle))
        built.mouseDown(on: id, at: CGPoint(x: box.minX, y: box.minY), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: box.maxX, y: box.maxY), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.rectangle))
        built.mouseDown(on: id, at: CGPoint(x: box.midX, y: box.midY), flags: [])
        built.mouseUp(on: id)
        XCTAssertEqual(view.drawnShapes.count, 1, "nothing was drawn, so the pixels say nothing")
        XCTAssertEqual(view.drawnHandles.count, 4, "nothing was selected, so there is no frame to look through")
        return (view, w, h, box)
    }

    func testTheSelectedObjectShowsItsOwnColourInsideTheFrameInBothAppearances() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            overlay?.close()
            let (view, w, h, box) = try selectedFilledRectangle(in: appearance)
            let root = try XCTUnwrap(view.layer)
            let centre = CGPoint(x: box.midX, y: box.midY)
            // A handle: its middle is white, and a pixel on its edge, four points from the corner, is not.
            let insideHandle = CGPoint(x: box.minX + 1, y: box.minY + 1)
            let onHandleEdge = CGPoint(x: box.minX - 4, y: box.minY + 1)
            let points = [centre, insideHandle, onHandleEdge]
            _ = try CompositedPixels.read(root, width: w, height: h, at: points)
            let pixels = try CompositedPixels.read(root, width: w, height: h, at: points)
            let red = AnnotationColor.red.cgColor.components!.map { UInt8(($0 * 255).rounded()) }
            for (read, want) in zip(pixels[0], red) {
                XCTAssertEqual(Int(read), Int(want), accuracy: 6, "\(appearance.rawValue): the box's centre came out \(pixels[0]), not the object's \(red)")
            }
            XCTAssertEqual(pixels[1], [255, 255, 255], "\(appearance.rawValue): the handle lost its white fill")
            XCTAssertNotEqual(pixels[2], [255, 255, 255], "\(appearance.rawValue): the handle has no edge")
            XCTAssertNotEqual(pixels[2], pixels[1], "\(appearance.rawValue): the handle's edge reads as its fill")
        }
    }
}
