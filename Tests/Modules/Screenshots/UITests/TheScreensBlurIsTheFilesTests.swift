import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The blur on the screen is the blur in the file, pixel for pixel, edges included.** The engine's test holds the
/// file's mosaic; this one draws a blur in the overlay over a picture in which every pixel has a colour of its
/// own, renders its layer at the display's scale through a `CARenderer` (the texture the window server composites),
/// exports the same layer through `CaptureSession`, and compares the pixels the box covers: the interior and its four
/// outermost lines, for boxes between pixels at both scales and one that meets the selection's edge.
///
/// What it would print if it failed totally: a layer that never got the mosaic is the picture itself (every probe
/// differs from the file's); a mosaic laid one pixel off, or upside down, differs along the edges and in every
/// block of a pattern with no two neighbours alike.
@MainActor
final class TheScreensBlurIsTheFilesTests: XCTestCase {
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func pattern(width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let colour = (UInt32(truncatingIfNeeded: index) &* 2_654_435_761 &+ 12_345) & 0xFF_FFFF
            bytes[index * 4] = UInt8(colour >> 16)
            bytes[index * 4 + 1] = UInt8(colour >> 8 & 0xFF)
            bytes[index * 4 + 2] = UInt8(colour & 0xFF)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func rgb(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    func testTheLayerOnTheScreenAndTheFileHoldTheSamePixels() throws {
        let screen0 = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (pw, ph) = (Int(screen0.frame.width), Int(screen0.frame.height))
        // The box starts and ends between pixels; the last one is dragged past the selection's edge and held at it.
        let drags: [(scale: CGFloat, from: CGPoint, to: CGPoint)] = [
            (2, CGPoint(x: 80.3, y: 90.6), CGPoint(x: 210.7, y: 140.2)),
            (1, CGPoint(x: 80.3, y: 90.6), CGPoint(x: 210.7, y: 111)),
            (2, CGPoint(x: CGFloat(pw) - 130.4, y: 70.5), CGPoint(x: CGFloat(pw) + 40, y: 150)),
        ]
        for drag in drags {
            let scale = drag.scale
            let (w, h) = (Int(CGFloat(pw) * scale), Int(CGFloat(ph) * scale))
            let picture = try pattern(width: w, height: h)
            let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: pw, height: ph), scale: scale, image: picture)
            results = []
            let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []),
                                       store: nil) { [weak self] in self?.results.append($0) }
            XCTAssertTrue(built.build())
            overlay = built
            built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
            built.mouseDragged(on: id, at: CGPoint(x: CGFloat(pw) - 50, y: CGFloat(ph) - 50), flags: [])
            built.mouseUp(on: id)
            let view = try XCTUnwrap(built.view(for: id))
            built.perform(.tool(.blur))
            built.mouseDown(on: id, at: drag.from, flags: [])
            built.mouseDragged(on: id, at: drag.to, flags: [])
            built.mouseUp(on: id)
            XCTAssertEqual(view.drawnShapes.count, 1, "\(scale)x: nothing was drawn, so the pixels below say nothing")
            let shape = try XCTUnwrap(view.drawnShapes.first)
            XCTAssertNotNil(shape.contents, "\(scale)x: the blur's layer holds no picture")

            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            root.anchorPoint = .zero
            root.position = .zero
            root.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            root.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
            root.addSublayer(shape)

            built.perform(.exit(.confirm))
            guard case .edited(_, _, let layers, _)? = results.last, let layer = layers.first else {
                return XCTFail("\(scale)x: the overlay did not hand the blur over: \(results)")
            }
            let box = try XCTUnwrap(Pixelate.pixels(of: layer.frame, scale: scale, width: w, height: h))
            // The file's pixels: the whole display cut, so the probes need no offset.
            let drawn = try XCTUnwrap(CaptureSession.draw([layer], over: picture, at: .zero, scale: scale, display: picture))
            let file = try rgb(drawn), source = try rgb(picture)

            let area = CGRect(x: 50 * scale, y: 50 * scale, width: CGFloat(pw - 100) * scale, height: CGFloat(ph - 100) * scale)
            let covered = box.intersection(area)
            XCTAssertGreaterThan(covered.width * covered.height, 400, "\(scale)x: the box is too small to see")
            var probes: [(x: Int, y: Int)] = []
            for y in stride(from: Int(covered.minY), to: Int(covered.maxY), by: 5) {
                for x in stride(from: Int(covered.minX), to: Int(covered.maxX), by: 5) { probes.append((x, y)) }
            }
            for x in Int(covered.minX)..<Int(covered.maxX) { probes += [(x, Int(covered.minY)), (x, Int(covered.maxY) - 1)] }
            for y in Int(covered.minY)..<Int(covered.maxY) { probes += [(Int(covered.minX), y), (Int(covered.maxX) - 1, y)] }
            // The renderer's texture is bottom-up: the picture's row is `h - 1 - row`.
            let read = try CompositedPixels.read(root, width: w, height: h, at: probes.map { CGPoint(x: $0.x, y: h - 1 - $0.y) })
            var off = 0, same = 0
            for (probe, got) in zip(probes, read) {
                let at = (probe.y * w + probe.x) * 4
                if (0..<3).contains(where: { abs(Int(got[$0]) - Int(file[at + $0])) > 3 }) { off += 1 }
                if (0..<3).allSatisfy({ file[at + $0] == source[at + $0] }) { same += 1 }
            }
            XCTAssertEqual(off, 0, "\(scale)x: \(off) of \(probes.count) pixels differ between the screen and the file")
            XCTAssertLessThan(same, probes.count / 20, "\(scale)x: the file shows the picture in \(same) of \(probes.count) probes")
        }
    }
}
