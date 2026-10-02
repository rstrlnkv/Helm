import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The overlay draws the frozen frame without the pointer, always.** The live
/// crosshair is drawn over it, and a pointer baked into the picture beneath
/// would be a second one. The frame with the pointer is for the cut alone. The
/// panels are built and never ordered in.
@MainActor
final class TheOverlayNeverDrawsTheCursorFrameTests: XCTestCase {

    private func solid(_ size: CGSize, red: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return try XCTUnwrap(context.makeImage())
    }

    private func firstPixel(_ image: CGImage) -> (UInt8, UInt8, UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return (pixel[0], pixel[1], pixel[2])
    }

    func testEveryViewDrawsTheFrameWithoutThePointer() throws {
        let screens = NSScreen.screens
        XCTAssertFalse(screens.isEmpty, "no screen, so nothing here can be built")
        var frames: [FrozenDisplay] = []
        for (index, screen) in screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let size = CGSize(width: 40, height: 20)
            frames.append(FrozenDisplay(
                id: DisplayID(number),
                frame: CGRect(origin: CGPoint(x: 100_000 * CGFloat(index), y: 0), size: screen.frame.size),
                scale: screen.backingScaleFactor,
                image: try solid(size, red: 1, blue: 0),
                withCursor: try solid(size, red: 0, blue: 1)))
        }
        let overlay = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: [])) { _ in }
        XCTAssertTrue(overlay.build())
        defer { overlay.close() }

        let drawn = overlay.drawnPictures
        XCTAssertEqual(drawn.count, frames.count, "a view had no picture, so nothing was proved about it")
        for frame in frames {
            let picture = try XCTUnwrap(drawn[frame.id])
            let (red, _, blue) = firstPixel(picture)
            XCTAssertEqual(red, 255, "the overlay is not drawing the frame without the pointer")
            XCTAssertEqual(blue, 0, "the overlay drew the frame with the pointer in it")
        }
    }
}
