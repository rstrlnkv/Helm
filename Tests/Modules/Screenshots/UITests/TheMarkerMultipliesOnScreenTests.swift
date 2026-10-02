import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The highlighter multiplies on the screen as it does in the file:** black under the marker stays
/// black and white takes the tint. A layer's `compositingFilter` blends only with what is beneath it in
/// the same parent, so a marker nested in a clipping layer composited as plain alpha and drew black text
/// olive; the layers are children of the view's own layer. `layer.render(in:)` ignores the filter, so the
/// pixels are read through a `CARenderer` onto a Metal texture, which is what the window server composites.
@MainActor
final class TheMarkerMultipliesOnScreenTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    func testBlackStaysBlackUnderTheMarkerAndWhiteTakesTheTint() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (w, h) = (Int(screen.frame.width), Int(screen.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: w, height: h), scale: 1,
                                   image: try CompositedPixels.halfBlackPicture(width: w, height: h))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)], windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        let (left, right, mid) = (CGFloat(w) * 0.4, CGFloat(w) * 0.6, CGFloat(h) / 2)
        built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: w - 50, y: h - 50), flags: [])
        built.mouseUp(on: id)
        built.perform(.tool(.highlighter))
        built.mouseDown(on: id, at: CGPoint(x: CGFloat(w) * 0.3, y: mid), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: CGFloat(w) * 0.7, y: mid), flags: [])
        built.mouseUp(on: id)
        let view = try XCTUnwrap(built.view(for: id))
        XCTAssertEqual(view.drawnShapes.count, 1, "nothing was drawn, so the pixels below say nothing")
        let root = try XCTUnwrap(view.layer)
        XCTAssertEqual(root.bounds.size, CGSize(width: w, height: h), "the view is not the display's size")
        let points = [CGPoint(x: left, y: mid), CGPoint(x: right, y: mid), CGPoint(x: right, y: mid + 120)]
        // A renderer's first pass over a layer tree that has never been composited draws only its
        // background; the second, with a renderer of its own, is the picture.
        _ = try CompositedPixels.read(root, width: w, height: h, at: points)
        let pixels = try CompositedPixels.read(root, width: w, height: h, at: points)
        let (overBlack, overWhite, bare) = (pixels[0], pixels[1], pixels[2])
        XCTAssertTrue(overBlack.allSatisfy { $0 < 40 }, "black under the marker came out \(overBlack): it is not multiplied")
        XCTAssertTrue(overWhite[0] > 200 && overWhite[2] < 140, "white under the marker came out \(overWhite): no tint")
        XCTAssertTrue(bare.allSatisfy { $0 > 240 }, "the control pixel, white and unmarked, came out \(bare)")
    }
}
