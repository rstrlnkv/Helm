import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The loupe reads the frame the person sees: the pixel under the point, nine by nine, in sRGB, and
/// never the one with the pointer drawn in.** Every pixel of the fixture carries its own place in its
/// colour (red is its column, green its row), so a window that is off by one, a flipped row or a scale
/// that was not applied reads as the wrong number and not as a plausible one.
final class ThePixelLoupeReadsTheFrozenPixelTests: XCTestCase {

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An opaque image whose pixel (x, y) is (x, y, blue) in `space`.
    private func addressed(width: Int, height: Int, blue: UInt8 = 0, space: CGColorSpace? = nil) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space ?? srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let at = y * context.bytesPerRow + x * 4
                bytes[at] = UInt8(x); bytes[at + 1] = UInt8(y); bytes[at + 2] = blue; bytes[at + 3] = 255
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func display(_ image: CGImage, scale: CGFloat, withCursor: CGImage? = nil) -> FrozenDisplay {
        FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale,
                                                      height: CGFloat(image.height) / scale),
                      scale: scale, image: image, withCursor: withCursor)
    }

    /// The loupe's own picture as (red, green) per cell, row-major from the top.
    private func cells(_ loupe: PixelLoupe) throws -> [[(UInt8, UInt8)]] {
        XCTAssertEqual(loupe.image.width, 9); XCTAssertEqual(loupe.image.height, 9)
        let context = try XCTUnwrap(CGContext(data: nil, width: 9, height: 9, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(loupe.image, in: CGRect(x: 0, y: 0, width: 9, height: 9))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<9).map { y in (0..<9).map { x in (bytes[y * context.bytesPerRow + x * 4], bytes[y * context.bytesPerRow + x * 4 + 1]) } }
    }

    func testTheNineByNineAroundAnInteriorPointIsThePixelsAroundIt() throws {
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 50.5, y: 30.5), in: display(try addressed(width: 100, height: 80), scale: 1)))
        XCTAssertEqual(loupe.pixel.x, 50); XCTAssertEqual(loupe.pixel.y, 30)
        let grid = try cells(loupe)
        for row in 0..<9 {
            for column in 0..<9 {
                XCTAssertEqual(grid[row][column].0, UInt8(46 + column), "column \(column) of row \(row)")
                XCTAssertEqual(grid[row][column].1, UInt8(26 + row), "row \(row) is not the display's row \(26 + row)")
            }
        }
        XCTAssertEqual(loupe.hex, "#321E00", "the middle is (50, 30, 0)")
    }

    func testThePointIsInPointsAndTheScaleTurnsItIntoPixels() throws {
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 20.4, y: 10.9), in: display(try addressed(width: 200, height: 120), scale: 2)))
        XCTAssertEqual(loupe.pixel.x, 40, "20.4 pt at 2x is pixel 40")
        XCTAssertEqual(loupe.pixel.y, 21, "10.9 pt at 2x is pixel 21, rounded down and not to the nearest")
        XCTAssertEqual(loupe.hex, "#281500")
    }

    func testAtAnEdgeTheNineByNineIsStillNineByNineAndItsMiddleIsThePixelUnderThePoint() throws {
        let image = try addressed(width: 100, height: 80)
        let corner = try XCTUnwrap(PixelLoupe.around(.zero, in: display(image, scale: 1)))
        let top = try cells(corner)
        XCTAssertEqual(corner.hex, "#000000")
        for row in 0..<9 {
            for column in 0..<9 {
                XCTAssertEqual(top[row][column].0, UInt8(max(0, column - 4)), "the left edge repeats its own column (\(column), \(row))")
                XCTAssertEqual(top[row][column].1, UInt8(max(0, row - 4)), "the top edge repeats its own row (\(column), \(row))")
            }
        }
        let far = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 99.9, y: 79.9), in: display(image, scale: 1)))
        XCTAssertEqual(far.pixel.x, 99); XCTAssertEqual(far.pixel.y, 79)
        let bottom = try cells(far)
        XCTAssertEqual(bottom[8][8].0, 99, "the last column is repeated, not left empty"); XCTAssertEqual(bottom[8][8].1, 79)
        XCTAssertEqual(bottom[4][4].0, 99); XCTAssertEqual(bottom[4][4].1, 79)
        XCTAssertEqual(bottom[0][0].0, 95); XCTAssertEqual(bottom[0][0].1, 75)
    }

    func testAPointOffTheDisplayIsClampedToItAndNoNumberIsNoLoupe() throws {
        let shown = display(try addressed(width: 100, height: 80), scale: 1)
        XCTAssertEqual(PixelLoupe.around(CGPoint(x: -500, y: 1e12), in: shown)?.pixel.x, 0)
        XCTAssertEqual(PixelLoupe.around(CGPoint(x: -500, y: 1e12), in: shown)?.pixel.y, 79)
        XCTAssertNil(PixelLoupe.around(CGPoint(x: CGFloat.nan, y: 3), in: shown))
        XCTAssertNil(PixelLoupe.around(CGPoint(x: 3, y: CGFloat.infinity), in: shown))
    }

    /// The control for "reads the frame without the pointer": the frame with it is blue everywhere, the other is not.
    func testItReadsTheFrameWithoutThePointerAndNotTheOneWithIt() throws {
        let plain = try addressed(width: 100, height: 80)
        let withPointer = try addressed(width: 100, height: 80, blue: 255)
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 10, y: 10), in: display(plain, scale: 1, withCursor: withPointer)))
        XCTAssertEqual(loupe.hex, "#0A0A00", "the pointer's frame was read")
    }

    /// A display's own space is not sRGB, and the hex is what a colour meter would read in sRGB.
    func testAWideGamutPixelIsReadInSRGBAndNotByItsRawBytes() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colour = CGColor(colorSpace: p3, components: [0.9, 0.3, 0.2, 1])!
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 10, y: 10), in: display(try XCTUnwrap(context.makeImage()), scale: 1)))
        let expected = try XCTUnwrap(colour.converted(to: srgb, intent: .defaultIntent, options: nil)?.components)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        XCTAssertEqual(Int(loupe.centre.red), byte(expected[0]), accuracy: 1)
        XCTAssertEqual(Int(loupe.centre.green), byte(expected[1]), accuracy: 1)
        XCTAssertEqual(Int(loupe.centre.blue), byte(expected[2]), accuracy: 1)
        XCTAssertNotEqual(Int(loupe.centre.red), byte(0.9), "the raw P3 bytes were read as sRGB")
    }

    func testTheHexIsSixUpperCaseDigitsWithAHash() throws {
        let loupe = try XCTUnwrap(PixelLoupe.around(CGPoint(x: 171, y: 205), in: display(try addressed(width: 256, height: 256, blue: 15), scale: 1)))
        XCTAssertEqual(loupe.hex, "#ABCD0F")
    }
}
