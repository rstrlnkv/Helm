import CoreGraphics
import CoreText
import XCTest
@testable import Module_Screenshots_Engine

/// **A text stands in the file on the pixels the screen laid it on.** The screen's layer is `AnnotationText.tile` put at
/// its pixels over the picture; the file is `CaptureSession.draw`. The same text, in each of the three steps, at 1× and
/// 2×, in Latin, Cyrillic, Japanese and with an emoji, is drawn both ways over one picture and every pixel of the
/// picture is compared. The file is also drawn from a cut that begins elsewhere, which must hold the same pixels
/// of the same picture.
///
/// What it would print if it failed totally: a text drawn nowhere leaves the file equal to the picture (the ink count
/// is zero); a file that draws at a baseline or an origin of its own differs from the tile along every glyph's edge.
final class TheTextLandsWhereTheScreenShowedItTests: XCTestCase {
    private static let texts = ["Hello, Helm 123", "Привет, мир 456", "日本語のテキスト", "Ship it 🚢🎉 ok"]
    private static let origin = CGPoint(x: 20.3, y: 15.6)
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private func picture(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // A ground that is not one colour, so a text that took the ground's own colour cannot hide in it.
        context.setFillColor(CGColor(srgbRed: 0.82, green: 0.86, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: width / 3, y: 0, width: width / 5, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    /// The screen's composite: the picture and the tile over it at the tile's pixels, as a layer is laid.
    private func shown(_ picture: CGImage, _ tile: Pixelate.Tile) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
        context.draw(tile.image, in: CGRect(x: tile.pixels.minX, y: CGFloat(picture.height) - tile.pixels.maxY,
                                            width: tile.pixels.width, height: tile.pixels.height))
        return try XCTUnwrap(context.makeImage())
    }

    func testTheFileAndTheScreensTileHoldTheSamePixelsInEveryStepAndScript() throws {
        for scale in [CGFloat(1), 2] {
            let (width, height) = (Int(420 * scale), Int(90 * scale))
            let ground = try picture(width: width, height: height)
            let was = try bytes(ground)
            for text in Self.texts {
                for step in AnnotationThickness.allCases {
                    let name = "\(Int(scale))x \(step) \(text)"
                    let layer = Annotation(tool: .text, start: Self.origin, end: Self.origin,
                                           style: AnnotationStyle(color: .blue, thickness: step, opacity: 0.85), text: text, id: 1)
                    let tile = try XCTUnwrap(AnnotationText.tile(of: layer, scale: scale), name)
                    let file = try XCTUnwrap(CaptureSession.draw([layer], over: ground, at: .zero, scale: scale, display: ground), name)
                    let fileBytes = try bytes(file), screenBytes = try bytes(try shown(ground, tile))

                    var inked = 0, worst = 0, off = 0, outside = 0
                    let reach = layer.frame.insetBy(dx: -2, dy: -2)
                    for index in 0..<(width * height) {
                        let at = index * 4
                        for channel in 0..<4 {
                            let gap = abs(Int(fileBytes[at + channel]) - Int(screenBytes[at + channel]))
                            worst = max(worst, gap)
                            if gap > 2 { off += 1 }
                        }
                        guard (0..<3).contains(where: { fileBytes[at + $0] != was[at + $0] }) else { continue }
                        inked += 1
                        let point = CGPoint(x: (CGFloat(index % width) + 0.5) / scale, y: (CGFloat(index / width) + 0.5) / scale)
                        if !reach.contains(point) { outside += 1 }
                    }
                    XCTAssertGreaterThan(inked, 40 * Int(scale), "\(name): the file shows no text (\(inked) pixels)")
                    XCTAssertEqual(off, 0, "\(name): \(off) bytes differ between the file and the screen's tile, the worst by \(worst)")
                    // The ink is inside the frame the editor holds the text by, to a pixel of rounding.
                    XCTAssertEqual(outside, 0, "\(name): \(outside) inked pixels are outside the text's frame \(layer.frame)")
                }
            }

            // The same file from a cut that begins at pixel (37, 11): the pixels of the same picture, not of a cut of their own.
            let layer = Annotation(tool: .text, start: Self.origin, end: Self.origin, style: AnnotationStyle(color: .red, thickness: .thick),
                                   text: Self.texts[0], id: 1)
            let whole = try bytes(try XCTUnwrap(CaptureSession.draw([layer], over: ground, at: .zero, scale: scale, display: ground)))
            let cutRect = CGRect(x: 37, y: 11, width: width - 40, height: height - 14)
            let cut = try XCTUnwrap(ground.cropping(to: cutRect))
            let part = try bytes(try XCTUnwrap(CaptureSession.draw([layer], over: cut, at: cutRect.origin, scale: scale, display: ground)))
            var apart = 0
            for y in 0..<cut.height {
                for x in 0..<cut.width {
                    for channel in 0..<4 where part[(y * cut.width + x) * 4 + channel] != whole[((y + 11) * width + x + 37) * 4 + channel] { apart += 1 }
                }
            }
            XCTAssertEqual(apart, 0, "\(Int(scale))x: a cut that begins elsewhere drew \(apart) bytes of the text differently")
        }
    }

    /// The font is the system's, semibold, at 12, 15 and 22 points.
    func testTheFontIsTheSystemsSemiboldAtTheThreeSteps() {
        for (step, size) in zip(AnnotationThickness.allCases, [12, 15, 22]) {
            let font = AnnotationText.font(for: step)
            XCTAssertEqual(CTFontGetSize(font), CGFloat(size))
            let traits = CTFontCopyTraits(font) as NSDictionary
            let weight = (traits[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? -1
            XCTAssertEqual(weight, 0.3, accuracy: 0.05, "\(step): the font's weight is not semibold: \(CTFontCopyPostScriptName(font))")
            XCTAssertTrue((CTFontCopyFamilyName(font) as String).contains("SF") || (CTFontCopyFamilyName(font) as String).hasPrefix("."),
                          "not the system family: \(CTFontCopyFamilyName(font))")
        }
    }
}
