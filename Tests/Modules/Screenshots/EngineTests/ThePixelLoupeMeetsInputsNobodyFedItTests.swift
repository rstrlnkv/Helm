import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The pixel loupe, fed what the task never named:** a frame of one pixel, a scale that is no scale, a frame
/// that is grey or half transparent rather than the opaque RGB a display gives, and a point so far off that
/// converting it would trap. The first family beside it (`ThePixelLoupeReadsTheFrozenPixelTests`) holds the
/// geometry and the colour space; this one holds what must not crash or lie.
final class ThePixelLoupeMeetsInputsNobodyFedItTests: XCTestCase {

    private func filled(width: Int, height: Int, space: CGColorSpace, alpha: CGImageAlphaInfo, _ colour: CGColor) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: alpha.rawValue))
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func display(_ image: CGImage, scale: CGFloat) -> FrozenDisplay {
        FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: CGFloat(image.width) / max(scale, 1),
                                                      height: CGFloat(image.height) / max(scale, 1)),
                      scale: scale, image: image)
    }

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    func testAFrameOfOnePixelIsNineByNineOfThatPixelWhereverThePointIs() throws {
        let image = try filled(width: 1, height: 1, space: srgb, alpha: .premultipliedLast, CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        for scale in [CGFloat(1), 2] {
            for point in [CGPoint.zero, CGPoint(x: 0.2, y: 0.2), CGPoint(x: -40, y: 90), CGPoint(x: 1e9, y: 1e9)] {
                let loupe = try XCTUnwrap(PixelLoupe.around(point, in: display(image, scale: scale)), "\(point) at \(scale)x")
                XCTAssertEqual(loupe.image.width, 9); XCTAssertEqual(loupe.image.height, 9)
                XCTAssertEqual(loupe.pixel.x, 0); XCTAssertEqual(loupe.pixel.y, 0)
                XCTAssertEqual(loupe.hex, "#FF8000", "\(point) at \(scale)x")
            }
        }
    }

    func testAScaleThatIsNoScaleIsNoLoupeAndNotATrap() throws {
        let image = try filled(width: 20, height: 20, space: srgb, alpha: .premultipliedLast, CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let shown = display(image, scale: 1)
        for scale in [CGFloat(0), -1, .nan, .infinity] {
            let broken = FrozenDisplay(id: shown.id, frame: shown.frame, scale: scale, image: image)
            XCTAssertNil(PixelLoupe.around(CGPoint(x: 5, y: 5), in: broken), "scale \(scale)")
        }
        // The control: the same display with a real scale reads.
        XCTAssertNotNil(PixelLoupe.around(CGPoint(x: 5, y: 5), in: shown))
    }

    func testAPointAtTheLargestNumbersIsClampedNotConverted() throws {
        let image = try filled(width: 20, height: 10, space: srgb, alpha: .premultipliedLast, CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        let shown = display(image, scale: 2)
        for value in [CGFloat.greatestFiniteMagnitude, -CGFloat.greatestFiniteMagnitude, 1e300, 9.3e18] {
            let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: value, y: -value), in: shown), "\(value)")
            XCTAssertEqual(loupe.pixel.y, value > 0 ? 0 : 9, "\(value)")
            XCTAssertEqual(loupe.pixel.x, value > 0 ? 19 : 0, "\(value)")
        }
    }

    func testAGreyFrameReadsAsEqualChannels() throws {
        let grey = try filled(width: 30, height: 30, space: CGColorSpaceCreateDeviceGray(), alpha: .none,
                              CGColor(gray: 0.5, alpha: 1))
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 15, y: 15), in: display(grey, scale: 1)))
        XCTAssertEqual(loupe.centre.red, loupe.centre.green)
        XCTAssertEqual(loupe.centre.green, loupe.centre.blue)
        XCTAssertTrue((100...180).contains(Int(loupe.centre.red)), "a mid grey read as \(loupe.hex)")
    }

    /// A frame is opaque in life; this is the input nobody gives it, and the reading must be the pixel's colour
    /// and not a darker one: premultiplied bytes are not a colour.
    func testAHalfTransparentPixelIsReadAsItsColourNotItsPremultipliedBytes() throws {
        let image = try filled(width: 20, height: 20, space: srgb, alpha: .premultipliedLast, CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 10, y: 10), in: display(image, scale: 1)))
        XCTAssertEqual(Int(loupe.centre.red), 255, accuracy: 2, "the red of a half-transparent red: \(loupe.hex)")
        XCTAssertEqual(loupe.centre.green, 0)
    }

    func testAFullyTransparentPixelIsBlackAndNotADivisionByZero() throws {
        let image = try filled(width: 20, height: 20, space: srgb, alpha: .premultipliedLast, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0))
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 10, y: 10), in: display(image, scale: 1)))
        XCTAssertEqual(loupe.hex, "#000000")
    }

    /// A frame that is itself a crop of a bigger image (what a display's capture can be) keeps its own origin.
    func testAFrameThatIsACropOfALargerImageIsReadFromItsOwnCorner() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        // CGContext rows run from the bottom: the image's bottom-right 50×50 is x 50...100, y 0...50 in the context,
        // and it is what the crop below (in the image's own top-left coordinates) takes.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
        let whole = try XCTUnwrap(context.makeImage())
        let crop = try XCTUnwrap(whole.cropping(to: CGRect(x: 50, y: 50, width: 50, height: 50)))
        let loupe = try XCTUnwrap(PixelLoupe.around(.zero, in: display(crop, scale: 1)))
        XCTAssertEqual(loupe.hex, "#0000FF", "the crop's top-left is the blue square's, not the whole image's")
    }
}
