import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The export is the screen's geometry multiplied by the display's own scale.** A
/// 3-point stroke is three pixels at 1× and six at 2×, the picture is the crop's
/// size in pixels, and the stroke lands on the pixels the selection covers: all
/// read back out of the rendered picture.
final class TheExportDrawsAtNativeResolutionTests: XCTestCase {

    /// A white 100×60-point display at `scale`.
    private func freeze(scale: CGFloat) -> Freeze {
        let width = Int(100 * scale), height = Int(60 * scale)
        let white = makeImage(width: width, height: height, red: 255, green: 255, blue: 255)
        return Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                                                      scale: scale, image: white))], windows: [])
    }

    /// The share of each pixel in column `x` that is ink, top to bottom: white is 0
    /// and the full ink is 1, read off the green channel, which the ink has least of.
    private func inkColumn(_ image: CGImage, x: Int) -> [Double] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let inkGreen = Double(AnnotationColor.red.cgColor.components![1]) * 255
        return (0..<image.height).map { row in
            (255 - Double(bytes[row * image.width * 4 + x * 4 + 1])) / (255 - inkGreen)
        }
    }

    func testTheCutHasTheCropsPixelsAndAStrokeIsPointsTimesTheScale() async throws {
        for scale in [CGFloat(1), 2] {
            let rig = Rig(home: scratchDirectory("shots-export-\(Int(scale))"))
            let selection = CGRect(x: 10, y: 10, width: 60, height: 30)
            // Top edge of the rectangle at y = 20 points: ten points under the selection's top.
            let layer = Annotation(tool: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 35))
            let drawn = await rig.session.annotated(freeze(scale: scale), display: DisplayID(1),
                                                    local: selection, layers: [layer])
            let out = try XCTUnwrap(drawn)
            let crop = try XCTUnwrap(rig.session.crop(freeze(scale: scale), display: DisplayID(1), local: selection))
            XCTAssertEqual(out.width, crop.width, "scale \(scale): the export is not the crop's width")
            XCTAssertEqual(out.height, crop.height)
            XCTAssertEqual(out.width, Int(60 * scale))

            // Column 40 points in, 30 from the selection's left: the top edge crosses it once, in the upper half.
            let column = inkColumn(out, x: Int(30 * scale))
            let upper = column[0..<(column.count / 2)]
            let thickness = upper.reduce(0, +)
            XCTAssertEqual(thickness, 3 * Double(scale), accuracy: 0.3,
                           "scale \(scale): the stroke is \(thickness) pixels thick, not \(3 * scale)")
            let centre = zip(upper.indices, upper).reduce(0.0) { $0 + Double($1.0) * $1.1 } / thickness + 0.5
            XCTAssertEqual(centre, 10 * Double(scale), accuracy: 0.6,
                           "scale \(scale): the stroke is not where the selection's offset puts it")
        }
    }

    func testNoLayersIsTheCropItself() async throws {
        let rig = Rig(home: scratchDirectory("shots-export-none"))
        let freeze = freeze(scale: 2)
        let plain = await rig.session.annotated(freeze, display: DisplayID(1),
                                                local: CGRect(x: 10, y: 10, width: 20, height: 10), layers: [])
        let out = try XCTUnwrap(plain)
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(out.height, 20)
        let missing = await rig.session.annotated(freeze, display: DisplayID(9),
                                                  local: CGRect(x: 10, y: 10, width: 20, height: 10), layers: [])
        XCTAssertNil(missing, "a display that is not in the freeze produced a picture")
    }

    func testACutRoundedOutwardKeepsTheStrokeOnItsPixels() async throws {
        // A selection that starts on a half pixel at 2×: the cut begins on the pixel
        // before it, and a layer at a known point must still be where that point is.
        let rig = Rig(home: scratchDirectory("shots-export-round"))
        let selection = CGRect(x: 10.25, y: 10, width: 40, height: 30)
        let layer = Annotation(tool: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 40, y: 30))
        let drawn = await rig.session.annotated(freeze(scale: 2), display: DisplayID(1),
                                                local: selection, layers: [layer])
        let out = try XCTUnwrap(drawn)
        // 10.25 × 2 = 20.5 → the cut starts at pixel 20; the left edge of the stroke
        // is at 20 points = pixel 40, so column 20 of the cut, in its middle.
        let row = Int((25 - 10) * 2.0)
        let ink = (0..<out.width).map { x in inkColumn(out, x: x)[row] }
        let left = ink[17..<24].reduce(0, +)
        XCTAssertEqual(left, 6, accuracy: 0.4, "the left edge is not 6 pixels thick around pixel 20")
        XCTAssertGreaterThan(ink[20], 0.9)
    }
}
