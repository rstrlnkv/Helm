import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The pencil's grain on the screen is the grain in the file, pixel for pixel.** The engine's tests hold that the
/// file's grain does not depend on where the cut begins; they cannot reach the overlay's layer, which lays the
/// same function on a `CALayer` as a mask. Whether that mask sits on the same image pixels (top-left against
/// bottom-left origin, the layer's frame, one texel to a pixel) is settled here by drawing one stroke in the
/// overlay, rendering its shape layer at the display's scale through a `CARenderer` (the texture the window
/// server composites), exporting the same stroke through `CaptureSession`, and comparing the pixels.
///
/// What it would print if it failed totally: a mask dropped from the layer is a solid stroke (the compared
/// pixels differ in about a third of the body, and the "grain is there" floor is missed); a flipped or shifted
/// mask is a grain of the right kind on the wrong pixels (the same differing count, with the placement check
/// naming the shift).
@MainActor
final class TheScreensPencilGrainIsTheFilesTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    /// Ink share of each pixel (0 white … 1 black) of a white picture the stroke is drawn on, top row first.
    private struct Ink {
        let width: Int, height: Int
        let values: [Double]
        func at(_ x: Int, _ y: Int) -> Double { values[y * width + x] }
        /// Rows and columns holding any ink above a quarter: the stroke's extent in pixels.
        var extent: (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<height { for x in 0..<width where at(x, y) > 0.25 { xs.append(x); ys.append(y) } }
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
            return (x0...x1, y0...y1)
        }
    }

    private func white(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func read(_ image: CGImage) throws -> Ink {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let values = (0..<(image.width * image.height)).map { (255 - Double(raw[$0 * 4 + 1])) / 255 }
        return Ink(width: image.width, height: image.height, values: values)
    }

    /// The overlay's shape layer for a pencil stroke, rendered at `scale` over white, and the layer the file draws.
    private func screenAndFile(scale: CGFloat, from: CGPoint, to: CGPoint, wobble: CGFloat = 0, ruler: Bool = false) throws
        -> (screen: Ink, file: Ink, layer: Annotation) {
        // The display as the controller freezes it: the screen's own size in points, its picture `scale` pixels to a point.
        let screen0 = try XCTUnwrap(NSScreen.screens.first)
        let number = try XCTUnwrap(screen0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
        let id = DisplayID(number)
        let (pw, ph) = (Int(screen0.frame.width), Int(screen0.frame.height))
        let frozen = FrozenDisplay(id: id, frame: CGRect(x: 0, y: 0, width: pw, height: ph), scale: scale,
                                   image: try white(width: Int(CGFloat(pw) * scale), height: Int(CGFloat(ph) * scale)))
        let built = CaptureOverlay(freeze: Freeze(displays: [.image(frozen)] + TheOtherScreens.blankFrames(besides: id), windows: []),
                                   store: nil) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(built.build())
        overlay = built
        built.mouseDown(on: id, at: CGPoint(x: 50, y: 50), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: CGFloat(pw) - 50, y: CGFloat(ph) - 50), flags: [])
        built.mouseUp(on: id)
        let view = try XCTUnwrap(built.view(for: id))
        built.perform(.tool(.pencil))
        if ruler { built.perform(.toggleRuler) }
        built.mouseDown(on: id, at: from, flags: [])
        let steps = 12
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            built.mouseDragged(on: id, at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t + (step.isMultiple(of: 2) ? wobble : 0)), flags: [])
        }
        built.mouseUp(on: id)
        XCTAssertEqual(view.drawnShapes.count, 1, "nothing was drawn, so the pixels below say nothing")
        let shape = try XCTUnwrap(view.drawnShapes.first)
        XCTAssertNotNil(shape.mask, "the pencil's layer carries no mask: the screen would show a solid stroke")
        let (w, h) = (Int(CGFloat(pw) * scale), Int(CGFloat(ph) * scale))
        XCTAssertEqual(view.bounds.size, CGSize(width: pw, height: ph), "the overlay's view is not the display's size")

        // The shape layer alone, over white, in a tree whose point is `scale` pixels: what the window server draws of it.
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        root.anchorPoint = .zero
        root.position = .zero
        root.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        root.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
        root.addSublayer(shape)
        _ = try CompositedPixels.read(root, width: w, height: h, at: [CGPoint(x: 0, y: 0)])
        // Only the rows round the stroke are read back (the rest of the display is white). The renderer's texture
        // is bottom-up: its row 0 is the display's last row, so the picture's row is `h - 1 - row`.
        let mid = (from.y + to.y) / 2
        let bandTop = h - Int((mid + 30) * scale), bandBottom = h - Int((mid - 30) * scale)
        let band = (bandTop..<bandBottom).flatMap { y in (0..<w).map { CGPoint(x: $0, y: y) } }
        let rendered = try CompositedPixels.read(root, width: w, height: h, at: band)
        var values = [Double](repeating: 0, count: w * h)
        for (index, rgb) in rendered.enumerated() {
            values[(h - 1 - (bandTop + index / w)) * w + index % w] = (255 - Double(rgb[1])) / 255
        }
        let screen = Ink(width: w, height: h, values: values)

        built.perform(.exit(.confirm))
        guard case .edited(_, _, let layers, _)? = results.last, let layer = layers.first else {
            XCTFail("the overlay did not hand the stroke over: \(results)")
            throw CancellationError()
        }
        XCTAssertEqual(layers.count, 1)
        let cut = try white(width: w, height: h)
        let drawn = try XCTUnwrap(CaptureSession.draw([layer], over: cut, at: .zero, scale: scale, display: cut))
        return (screen, try read(drawn), layer)
    }

    /// Pixels well inside a (near) horizontal stroke, from its geometry: 1.5 px off the edge, the caps and the wobble.
    private func body(of layer: Annotation, scale: CGFloat, wobble: CGFloat) throws -> [(x: Int, y: Int)] {
        let width = try XCTUnwrap(layer.stroke).width
        let xs = layer.points.map(\.x), ys = layer.points.map(\.y)
        let half = width * scale / 2 - (scale >= 2 ? 1.5 : 0.75) - wobble * scale
        XCTAssertGreaterThanOrEqual(half, 1, "the probe has no body at \(scale)x")
        let x0 = Int(((xs.min()! + width / 2) * scale + 2).rounded(.up)), x1 = Int(((xs.max()! - width / 2) * scale - 2).rounded(.down))
        let mid = (ys.min()! + ys.max()!) / 2 * scale
        let y0 = Int((mid - half).rounded(.up)), y1 = Int((mid + half - 1).rounded(.down))
        return (y0...y1).flatMap { y in (x0...x1).map { (x: $0, y: y) } }
    }

    func testTheOverlaysLayerAndTheExportGiveTheGrainOnTheSameImagePixels() throws {
        for scale in [CGFloat(1), 2] {
            let (screen, file, layer) = try screenAndFile(scale: scale, from: CGPoint(x: 210.3, y: 300.2), to: CGPoint(x: 740.6, y: 300.2))
            overlay?.close(); overlay = nil; results = []
            XCTAssertEqual(layer.tool, .pencil)
            // Placement first: both put the stroke on the same rows and columns, or the grain comparison is about nothing.
            let (se, fe) = (try XCTUnwrap(screen.extent, "\(scale)x: the layer rendered no ink"), try XCTUnwrap(file.extent, "\(scale)x: the file has no ink"))
            XCTAssertEqual(se.x.lowerBound, fe.x.lowerBound, accuracy: 1, "\(scale)x: the screen's stroke starts at another column than the file's")
            XCTAssertEqual(se.x.upperBound, fe.x.upperBound, accuracy: 1, "\(scale)x: the screen's stroke ends at another column")
            XCTAssertEqual(se.y.lowerBound, fe.y.lowerBound, accuracy: 1, "\(scale)x: the screen's stroke starts at another row (flipped or shifted?)")
            XCTAssertEqual(se.y.upperBound, fe.y.upperBound, accuracy: 1, "\(scale)x: the screen's stroke ends at another row")
            let pixels = try body(of: layer, scale: scale, wobble: 0)
            XCTAssertGreaterThan(pixels.count, 400, "\(scale)x: the body probe is small")
            let gaps = pixels.filter { file.at($0.x, $0.y) < 0.9 }.count
            XCTAssertGreaterThan(Double(gaps) / Double(pixels.count), 0.08, "\(scale)x: the file's stroke has no grain to compare")
            let screenGaps = pixels.filter { screen.at($0.x, $0.y) < 0.9 }.count
            XCTAssertGreaterThan(Double(screenGaps) / Double(pixels.count), 0.08, "\(scale)x: the screen's stroke is solid; the mask does nothing")
            let off = pixels.filter { abs(screen.at($0.x, $0.y) - file.at($0.x, $0.y)) > 0.06 }
            XCTAssertEqual(off.count, 0, "\(scale)x: \(off.count) of \(pixels.count) body pixels differ between the screen and the file (first \(off.prefix(4)))")
            // The check can tell: against a one-pixel shift the same comparison fails widely.
            let wrong = pixels.filter { abs(screen.at($0.x, $0.y) - file.at($0.x + 1, $0.y)) > 0.06 }.count
            XCTAssertGreaterThan(Double(wrong) / Double(pixels.count), 0.05, "\(scale)x: a one-pixel shift passes too: the grain is flat")
        }
    }

    /// A pencil stroke made along the ruler is two points on a level line, and the grain on the screen is still the file's.
    func testAStrokeAlongTheRulerHasTheSameGrainOnTheScreenAndInTheFile() throws {
        let screen0 = try XCTUnwrap(NSScreen.screens.first)
        let edge = screen0.frame.height / 2 - 17
        for scale in [CGFloat(1), 2] {
            let (screen, file, layer) = try screenAndFile(scale: scale, from: CGPoint(x: screen0.frame.width / 2 - 120.3, y: edge - 4.2),
                                                          to: CGPoint(x: screen0.frame.width / 2 + 120.6, y: edge - 4.2), ruler: true)
            overlay?.close(); overlay = nil; results = []
            XCTAssertEqual(layer.points.count, 2, "\(scale)x: the stroke was not made along the ruler")
            XCTAssertEqual(layer.start.y, edge, accuracy: 1e-6)
            let pixels = try body(of: layer, scale: scale, wobble: 0)
            XCTAssertGreaterThan(pixels.count, 400, "\(scale)x: the body probe is small")
            let screenGaps = pixels.filter { screen.at($0.x, $0.y) < 0.9 }.count
            XCTAssertGreaterThan(Double(screenGaps) / Double(pixels.count), 0.08, "\(scale)x: the screen's stroke along the ruler is solid")
            let off = pixels.filter { abs(screen.at($0.x, $0.y) - file.at($0.x, $0.y)) > 0.06 }
            XCTAssertEqual(off.count, 0, "\(scale)x: \(off.count) of \(pixels.count) pixels of a stroke along the ruler differ between the screen and the file")
        }
    }
}
