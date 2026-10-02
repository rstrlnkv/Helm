import CoreGraphics
import Foundation
import Metal
import QuartzCore
import XCTest

/// The pixels of a layer tree as the window server composites them. `layer.render(in:)` ignores a
/// layer's `compositingFilter` and draws what a `CARenderer` would not, so a test about what a person
/// sees reads a `CARenderer`'s Metal texture instead.
public enum CompositedPixels {

    /// A picture `width` × `height`, black on the left half and white on the right.
    public static func halfBlackPicture(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// The layer's pixels in 8-bit RGB at `points` of a `width` × `height` texture. A renderer's first pass
    /// over a tree never composited draws only its background, so a caller wanting the picture reads twice.
    @MainActor
    public static func read(_ layer: CALayer, width: Int, height: Int, at points: [CGPoint]) throws -> [[UInt8]] {
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
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // The renderer commits its own work on the queue; a buffer behind it is done when that is.
        let fence = try XCTUnwrap(queue.makeCommandBuffer())
        fence.commit()
        fence.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return points.map { point in
            let at = (Int(point.y) * width + Int(point.x)) * 4
            return [bytes[at + 2], bytes[at + 1], bytes[at]]
        }
    }
}
