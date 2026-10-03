import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The grain mask belongs to the pencil's shape layer and to no other, and a draft's mask is the grain of its own
/// anchor.** Release re-masks a kept draft layer, and a second pencil stroke reuses the first one's whole-display
/// grain when the key says it may; both are ways for a shape to carry a grain that is not its own. Read from the
/// layer's mask, not from pixels sampled in a gap, so that the check does not pass when the sample lands on a bare
/// pixel.
///
/// What it would print if it failed totally: a pen or marker that takes the mask on release is named with its tool
/// and a non-nil mask; two strokes sharing one grain give equal mask bytes for different anchors.
@MainActor
final class ThePencilsGrainStaysOnThePencilsLayerTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func start() throws -> (CaptureOverlay, DisplayID, OverlayView, Int, Int) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (w, h) = (Int(screen.frame.width), Int(screen.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: w, height: h), scale: 1,
                                   image: try CompositedPixels.halfBlackPicture(width: w, height: h))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []), store: nil) { _ in }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: w - 50, y: h - 50), flags: [])
        built.mouseUp(on: id)
        return (built, id, try XCTUnwrap(built.view(for: id)), w, h)
    }

    private func bytes(_ layer: CALayer?) throws -> Data {
        let image = try XCTUnwrap(layer?.contents, "no mask contents") as! CGImage
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }

    func testAReleasedPenAndMarkerCarryNoGrainAndAReleasedPencilDoes() throws {
        for (tool, grained) in [(AnnotationTool.pen, false), (.highlighter, false), (.pencil, true)] {
            let (built, id, view, w, h) = try start()
            built.perform(.tool(tool))
            built.mouseDown(on: id, at: CGPoint(x: CGFloat(w) * 0.3, y: CGFloat(h) / 2), flags: [])
            built.mouseDragged(on: id, at: CGPoint(x: CGFloat(w) * 0.5, y: CGFloat(h) / 2 + 20), flags: [])
            let drafting = try XCTUnwrap(view.drawnShapes.last)
            XCTAssertEqual(drafting.mask != nil, grained, "\(tool) while drawn: mask \(drafting.mask != nil ? "present" : "absent")")
            built.mouseDragged(on: id, at: CGPoint(x: CGFloat(w) * 0.7, y: CGFloat(h) / 2), flags: [])
            built.mouseUp(on: id)
            XCTAssertEqual(view.drawnShapes.count, 1, "\(tool): nothing was drawn")
            let shape = try XCTUnwrap(view.drawnShapes.first)
            XCTAssertEqual(shape.mask != nil, grained, "\(tool) after release: mask \(shape.mask != nil ? "present" : "absent")")
            if grained {
                // Memory: a finished stroke keeps its own box's grain, not the display's.
                let image = try XCTUnwrap(shape.mask?.contents) as! CGImage
                let points = [CGPoint(x: CGFloat(w) * 0.3, y: CGFloat(h) / 2), CGPoint(x: CGFloat(w) * 0.5, y: CGFloat(h) / 2 + 20),
                              CGPoint(x: CGFloat(w) * 0.7, y: CGFloat(h) / 2)]
                XCTAssertLessThan(image.width * image.height, w * h / 4, "the finished stroke's mask is display-sized: \(image.width) x \(image.height)")
                let box = try XCTUnwrap(PencilGrain.box(for: points, width: 3, scale: 1, pixels: CGRect(x: 0, y: 0, width: w, height: h)))
                XCTAssertLessThan(abs(image.width - Int(box.width)), 40, "mask width \(image.width) is not about the stroke's box \(box.width)")
                XCTAssertLessThan(abs(image.height - Int(box.height)), 40, "mask height \(image.height) is not about the stroke's box \(box.height)")
            }
            built.close()
            overlay = nil
        }
    }

    /// A draft dropped by Esc or a right click never reaches the release that clears the kept grain, so the next
    /// stroke, anchored elsewhere, must not be handed the dropped one's.
    func testAStrokeAfterADroppedDraftCarriesTheGrainOfItsOwnAnchor() throws {
        let (built, id, view, w, h) = try start()
        built.perform(.tool(.pencil))
        let first = CGPoint(x: CGFloat(w) * 0.3, y: CGFloat(h) / 2)
        built.mouseDown(on: id, at: first, flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: first.x + 100, y: first.y + 10), flags: [])
        let dropped = try bytes(try XCTUnwrap(view.drawnShapes.last).mask)
        built.rightMouseDown()
        XCTAssertEqual(view.drawnShapes.count, 0, "the right click did not drop the draft")
        let second = CGPoint(x: first.x + 13, y: first.y + 5)
        built.mouseDown(on: id, at: second, flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: second.x + 100, y: second.y + 10), flags: [])
        let now = try bytes(try XCTUnwrap(view.drawnShapes.last).mask)
        let own = try XCTUnwrap(PencilGrain.mask(anchoredAt: second, scale: 1, pixels: CGRect(x: 0, y: 0, width: w, height: h))?.alpha)
        XCTAssertEqual(now, try XCTUnwrap(own.dataProvider?.data as Data?), "the new draft carries a grain that is not its anchor's")
        XCTAssertNotEqual(now, dropped, "the new draft carries the dropped one's grain")
    }

    func testASecondPencilStrokeCarriesTheGrainOfItsOwnAnchor() throws {
        let (built, id, view, w, h) = try start()
        built.perform(.tool(.pencil))
        let anchors = [CGPoint(x: CGFloat(w) * 0.3, y: CGFloat(h) / 2), CGPoint(x: CGFloat(w) * 0.31 + 1, y: CGFloat(h) / 2 + 7)]
        var drafts: [Data] = []
        for anchor in anchors {
            built.mouseDown(on: id, at: anchor, flags: [])
            built.mouseDragged(on: id, at: CGPoint(x: anchor.x + 200, y: anchor.y + 30), flags: [])
            let shape = try XCTUnwrap(view.drawnShapes.last)
            drafts.append(try bytes(shape.mask))
            let own = try XCTUnwrap(PencilGrain.mask(anchoredAt: anchor, scale: 1, pixels: CGRect(x: 0, y: 0, width: w, height: h))?.alpha)
            XCTAssertEqual(drafts.last, try XCTUnwrap(own.dataProvider?.data as Data?), "the draft's grain is not its own anchor's")
            built.mouseUp(on: id)
        }
        XCTAssertNotEqual(drafts[0], drafts[1], "two strokes with different anchors share one grain")
    }
}
