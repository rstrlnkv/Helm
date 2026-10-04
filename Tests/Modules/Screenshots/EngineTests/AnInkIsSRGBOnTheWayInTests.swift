import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **Every way into an ink ends at three sRGB numbers in 0…1: a colour of another space is converted and not read raw, its alpha is
/// dropped, and a number that is not a number is no ink.** The colour panel hands over a colour in whatever space it was picked in
/// (Display P3 on this Mac's own displays), and the file is drawn in sRGB: the raw numbers of a P3 red are a different red there.
/// The reference is the system's own conversion, asked here by a route the type does not take (a bitmap of one pixel drawn in
/// sRGB), so the type's conversion is compared with something that is not itself.
final class AnInkIsSRGBOnTheWayInTests: XCTestCase {

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// What a single pixel of `colour` reads as when drawn into an sRGB bitmap, 0…1 a channel.
    private func drawn(_ colour: CGColor) throws -> [Double] {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 16, bytesPerRow: 0, space: srgb,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt16.self)
        return (0..<3).map { Double(bytes[$0]) / 65535 }
    }

    func testADisplayP3ColourIsConvertedAndNotReadRaw() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let colour = try XCTUnwrap(CGColor(colorSpace: p3, components: [0.9, 0.3, 0.2, 1]))
        let ink = try XCTUnwrap(AnnotationInk(colour))
        let want = try drawn(colour)
        for (got, expected) in zip([ink.red, ink.green, ink.blue], want) { XCTAssertEqual(got, expected, accuracy: 1.0 / 255) }
        XCTAssertGreaterThan(abs(ink.red - 0.9) + abs(ink.green - 0.3) + abs(ink.blue - 0.2), 0.05, "control: P3 and sRGB differ here, so raw is not the answer")
        // A saturated P3 colour is outside sRGB: it lands on the edge and is clamped, never above 1 and never a failure.
        let outside = try XCTUnwrap(AnnotationInk(try XCTUnwrap(CGColor(colorSpace: p3, components: [0, 1, 0, 1]))))
        XCTAssertTrue((0...1).contains(outside.red) && (0...1).contains(outside.green) && (0...1).contains(outside.blue), "\(outside)")
    }

    func testAGreyIsThreeEqualNumbers() throws {
        let grey = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let ink = try XCTUnwrap(AnnotationInk(try XCTUnwrap(CGColor(colorSpace: grey, components: [0.5, 1]))))
        XCTAssertEqual(ink.red, ink.green, accuracy: 1e-6)
        XCTAssertEqual(ink.green, ink.blue, accuracy: 1e-6)
        XCTAssertEqual(ink.red, 0.5, accuracy: 0.01, "a gamma 2.2 grey of 0.5 is about 0.5 in sRGB")
        XCTAssertEqual(AnnotationInk(CGColor(gray: 1, alpha: 1)), .white)
        XCTAssertEqual(AnnotationInk(CGColor(gray: 0, alpha: 1)), .black)
    }

    func testAlphaIsDropped() throws {
        let half = try XCTUnwrap(AnnotationInk(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.25)))
        let whole = try XCTUnwrap(AnnotationInk(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)))
        XCTAssertEqual(half, whole, "the opacity is the style's, not the ink's")
        XCTAssertEqual(half.red, 0.2, accuracy: 1e-6, "and the colour was not premultiplied by it")
        XCTAssertEqual(half.cgColor.alpha, 1)
    }

    func testANumberThatIsNoneIsNoInk() throws {
        XCTAssertNil(AnnotationInk(red: .nan, green: 0, blue: 0))
        XCTAssertNil(AnnotationInk(red: 0, green: .infinity, blue: 0))
        XCTAssertNil(AnnotationInk(red: 0, green: 0, blue: -.infinity))
        XCTAssertNil(AnnotationInk(CGColor(srgbRed: .nan, green: 0.5, blue: 0.5, alpha: 1)), "a colour with a NaN channel")
        XCTAssertNotNil(AnnotationInk(red: 0, green: 0.5, blue: 1), "control: finite numbers are an ink")
        let big = try XCTUnwrap(AnnotationInk(red: 5, green: -5, blue: 0.5))
        XCTAssertEqual([big.red, big.green, big.blue], [1, 0, 0.5], "out of range is the nearest, not nil")
    }

    func testTheSwatchNamesEachOfTheEightAndNothingElse() throws {
        XCTAssertEqual(AnnotationColor.allCases.count, 8)
        for color in AnnotationColor.allCases {
            XCTAssertEqual(AnnotationInk(color).swatch, color, "\(color)")
        }
        XCTAssertEqual(AnnotationInk(.red), AnnotationInk.red)
        XCTAssertEqual(AnnotationInk(.white), AnnotationInk.white)
        XCTAssertEqual(Set(AnnotationColor.allCases.map { AnnotationInk($0) }).count, 8, "eight inks, no two the same")
        let foreign = try XCTUnwrap(AnnotationInk(red: 0.123, green: 0.456, blue: 0.789))
        XCTAssertNil(foreign.swatch)
        let nearRed = try XCTUnwrap(AnnotationInk(red: AnnotationInk.red.red, green: AnnotationInk.red.green + 0.01, blue: AnnotationInk.red.blue))
        XCTAssertNil(nearRed.swatch, "a red a hundredth off is a picked ink and not the swatch")
    }

    func testAPickedPixelIsItsBytesOver255() throws {
        let colour = try XCTUnwrap(CGColor(colorSpace: srgb, components: [10.0 / 255, 128.0 / 255, 255.0 / 255, 1]))
        let ink = try XCTUnwrap(AnnotationInk(colour))
        XCTAssertEqual(ink.red, 10.0 / 255, accuracy: 1e-4)
        XCTAssertEqual(ink.green, 128.0 / 255, accuracy: 1e-4)
        XCTAssertEqual(ink.blue, 1, accuracy: 1e-4)
        XCTAssertEqual(AnnotationInk(ink.cgColor), ink, "through a CGColor and back")
    }
}
