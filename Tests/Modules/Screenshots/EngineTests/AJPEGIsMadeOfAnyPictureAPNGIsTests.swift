import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import XCTest
@testable import Module_Screenshots_Engine

/// **Whatever picture the PNG path encodes, the JPEG path encodes too.** The
/// JPEG is drawn onto a white ground first, in a bitmap built from the
/// picture's own colour space when that is an RGB one — and a capture's colour
/// space is the display's, which on a wide-gamut or HDR display is not plain
/// sRGB. A bitmap that cannot be made in that space is a capture refused as
/// "could not be encoded" under JPEG alone, with the PNG of the same pixels
/// fine.
final class AJPEGIsMadeOfAnyPictureAPNGIsTests: XCTestCase {

    private func picture(space: CGColorSpace, bits: Int, info: UInt32) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: bits,
                                              bytesPerRow: 0, space: space, bitmapInfo: info),
                                    "the fixture itself could not be drawn")
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return try XCTUnwrap(context.makeImage())
    }

    func testEveryColourSpaceACaptureCanCarryBecomesAJPEGWhereItBecomesAPNG() throws {
        let premultipliedLast = CGImageAlphaInfo.premultipliedLast.rawValue
        let floats = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue
        let cases: [(String, CGColorSpace, Int, UInt32)] = [
            ("sRGB, 8 bit", CGColorSpace(name: CGColorSpace.sRGB)!, 8, premultipliedLast),
            ("Display P3, 8 bit", CGColorSpace(name: CGColorSpace.displayP3)!, 8, premultipliedLast),
            ("Display P3, 16 bit", CGColorSpace(name: CGColorSpace.displayP3)!, 16, premultipliedLast),
            ("extended sRGB, half float", CGColorSpace(name: CGColorSpace.extendedSRGB)!, 16, floats),
            ("extended linear Display P3, half float", CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!, 16, floats),
            ("device RGB, 8 bit", CGColorSpaceCreateDeviceRGB(), 8, premultipliedLast),
        ]
        var refused: [String] = []
        for (what, space, bits, info) in cases {
            let image = try picture(space: space, bits: bits, info: info)
            XCTAssertNotNil(CaptureSession.encode(image, as: .png), "\(what): not even a PNG, so this case proves nothing")
            if CaptureSession.encode(image, as: .jpeg) == nil { refused.append(what) }
        }
        XCTAssertEqual(refused, [], "a picture a PNG is made of was refused as a JPEG")
    }
}
