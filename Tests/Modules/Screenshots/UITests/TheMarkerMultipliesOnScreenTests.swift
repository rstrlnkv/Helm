import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import Metal
import QuartzCore
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

    /// The picture is as large as the display the panel covers, black on the left half and white on the right.
    private func halfBlackPicture(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// The pixels of the layer as the compositor draws them, in 8-bit RGB, at points of a `width` × `height` texture.
    private func composited(_ layer: CALayer, width: Int, height: Int, at points: [CGPoint]) throws -> [[UInt8]] {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal device")
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                   mipmapped: false)
        description.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: description))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = layer
        renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        CATransaction.flush()
        for _ in 0..<1 {
            renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
            // The renderer commits its own work on the queue; a buffer behind it is done when that is.
            let fence = try XCTUnwrap(queue.makeCommandBuffer())
            fence.commit()
            fence.waitUntilCompleted()
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return points.map { point in
            let at = (Int(point.y) * width + Int(point.x)) * 4
            return [bytes[at + 2], bytes[at + 1], bytes[at]]
        }
    }

    func testBlackStaysBlackUnderTheMarkerAndWhiteTakesTheTint() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (w, h) = (Int(screen.frame.width), Int(screen.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: w, height: h), scale: 1,
                                   image: try halfBlackPicture(width: w, height: h))
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
        XCTAssertEqual(view.drawnLayerCount, 1, "nothing was drawn, so the pixels below say nothing")
        let root = try XCTUnwrap(view.layer)
        XCTAssertEqual(root.bounds.size, CGSize(width: w, height: h), "the view is not the display's size")
        let points = [CGPoint(x: left, y: mid), CGPoint(x: right, y: mid), CGPoint(x: right, y: mid + 120)]
        // A renderer's first pass over a layer tree that has never been composited draws only its
        // background; the second, with a renderer of its own, is the picture.
        _ = try composited(root, width: w, height: h, at: points)
        let pixels = try composited(root, width: w, height: h, at: points)
        let (overBlack, overWhite, bare) = (pixels[0], pixels[1], pixels[2])
        XCTAssertTrue(overBlack.allSatisfy { $0 < 40 }, "black under the marker came out \(overBlack): it is not multiplied")
        XCTAssertTrue(overWhite[0] > 200 && overWhite[2] < 140, "white under the marker came out \(overWhite): no tint")
        XCTAssertTrue(bare.allSatisfy { $0 > 240 }, "the control pixel, white and unmarked, came out \(bare)")
    }
}
