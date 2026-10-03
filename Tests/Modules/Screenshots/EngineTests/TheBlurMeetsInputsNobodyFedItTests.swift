import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The blur meets the boxes, pictures and orders nobody drew it with.** Every case holds the same things, read off
/// the file's bytes: nothing outside the box moved, no block inside it is two colours, and the mosaic is of the
/// frame's own pixels and never of what was drawn before it.
final class TheBlurMeetsInputsNobodyFedItTests: XCTestCase {
    /// A picture in which every pixel has a colour of its own, in `space` at `bits` a channel.
    private func pattern(width: Int, height: Int, space: CGColorSpace? = nil, bits: Int = 8) -> CGImage {
        let space = space ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setShouldAntialias(false)
        for y in 0..<height { for x in 0..<width {
            let colour = (UInt32(y * width + x) &* 2_654_435_761 &+ 12_345) & 0xFF_FFFF
            context.setFillColor(CGColor(colorSpace: space, components: [CGFloat(colour >> 16) / 255, CGFloat(colour >> 8 & 0xFF) / 255,
                                                                         CGFloat(colour & 0xFF) / 255, 1])!)
            context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
        } }
        return context.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt32] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).map { UInt32(bytes[$0 * 4]) << 16 | UInt32(bytes[$0 * 4 + 1]) << 8 | UInt32(bytes[$0 * 4 + 2]) }
    }

    private func blur(_ rect: CGRect, _ step: AnnotationThickness = .medium) -> Annotation {
        Annotation(tool: .blur, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), style: AnnotationStyle(thickness: step))
    }

    /// The file for `layers` over the whole of `source`, drawn as the editor's export draws it.
    private func file(_ layers: [Annotation], over source: CGImage, scale: CGFloat) throws -> [UInt32] {
        pixels(try XCTUnwrap(CaptureSession.draw(layers, over: source, at: .zero, scale: scale, display: source)))
    }

    /// Nothing outside the box `(x0, y0, x1, y1)` (whole pixels) differs from `base`, and every grid block of `side`
    /// inside it is one colour; returns the number of blocks seen.
    @discardableResult
    private func holds(_ out: [UInt32], _ base: [UInt32], width: Int, box: (Int, Int, Int, Int), side: Int, _ name: String) -> Int {
        var blocks: [[Int]: Set<UInt32>] = [:]
        for y in 0..<(base.count / width) { for x in 0..<width {
            if x >= box.0, x < box.2, y >= box.1, y < box.3 { blocks[[x / side, y / side], default: []].insert(out[y * width + x]) }
            else if out[y * width + x] != base[y * width + x] { XCTFail("\(name): (\(x), \(y)) outside the box changed"); return blocks.count }
        } }
        for (block, colours) in blocks where colours.count != 1 { XCTFail("\(name): block \(block) holds \(colours.count) colours") }
        return blocks.count
    }

    func testBoxesThatAreNotABoxDrawNothingAndDoNotTrap() throws {
        let source = pattern(width: 60, height: 40)
        let base = try file([], over: source, scale: 1)
        let nan = CGFloat.nan, inf = CGFloat.infinity
        let rects: [(String, CGRect)] = [
            ("zero", CGRect(x: 10, y: 10, width: 0, height: 0)), ("no width", CGRect(x: 10, y: 10, width: 0, height: 20)),
            ("NaN origin", CGRect(x: nan, y: 5, width: 20, height: 20)), ("NaN size", CGRect(x: 5, y: 5, width: nan, height: 20)),
            ("infinite", CGRect(x: 0, y: 0, width: inf, height: inf)), ("negative infinite", CGRect(x: -inf, y: -inf, width: inf, height: inf)),
            ("wholly left", CGRect(x: -500, y: 5, width: 100, height: 20)), ("wholly below", CGRect(x: 5, y: 400, width: 20, height: 20)),
            ("past the right", CGRect(x: 60, y: 0, width: 10, height: 40)),
            ("huge and far", CGRect(x: 1e300, y: 1e300, width: 1e300, height: 1e300)),
        ]
        for (name, rect) in rects {
            // The editor refuses an unusable box; the export is fed what it is given.
            let layer = Annotation(tool: .blur, start: rect.origin, end: CGPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height))
            XCTAssertEqual(try file([layer], over: source, scale: 1), base, "\(name): a box with no pixel on the display changed the file")
        }
    }

    func testAHugeBoxIsClippedToTheDisplayAndEveryBlockIsOneColour() throws {
        let source = pattern(width: 60, height: 40)
        let base = try file([], over: source, scale: 1)
        let out = try file([blur(CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))], over: source, scale: 1)
        XCTAssertGreaterThan(holds(out, base, width: 60, box: (0, 0, 60, 40), side: 16, "huge"), 6)
        XCTAssertNotEqual(out, base)
    }

    func testABlockLargerThanTheBoxIsTheBoxsOwnMeanAndABoxOnePixelWideIsStillAMosaic() throws {
        let source = pattern(width: 60, height: 40), was = pixels(source)
        let out = try file([blur(CGRect(x: 5, y: 5, width: 6, height: 6), .thick)], over: source, scale: 1)
        // 24-pt blocks: the box (5...11) is inside the block 0...24 and is the mean of its own 36 pixels.
        var sum = [0, 0, 0]
        for y in 5..<11 { for x in 5..<11 { for (i, shift) in [16, 8, 0].enumerated() { sum[i] += Int(was[y * 60 + x] >> UInt32(shift) & 0xFF) } } }
        let got = out[5 * 60 + 5]
        for (i, shift) in [16, 8, 0].enumerated() {
            XCTAssertLessThanOrEqual(abs(Int(got >> UInt32(shift) & 0xFF) - sum[i] / 36), 1, "channel \(i)")
        }
        for y in 5..<11 { for x in 5..<11 { XCTAssertEqual(out[y * 60 + x], got) } }
        XCTAssertEqual(out[4 * 60 + 5], was[4 * 60 + 5], "the pixel above the box moved")

        // A box a pixel wide at 2x: half a point is one pixel.
        let wide = pattern(width: 120, height: 80)
        let baseWide = try file([], over: wide, scale: 2)
        let thin = try file([blur(CGRect(x: 10, y: 4, width: 0.5, height: 30))], over: wide, scale: 2)
        holds(thin, baseWide, width: 120, box: (20, 8, 21, 68), side: 32, "one pixel wide")
    }

    func testAFractionalScaleKeepsTheGridOnTheDisplaysPixels() throws {
        // 1.5 pixels a point: a 16-pt block is 24 pixels, a 10-pt one 15.
        let source = pattern(width: 150, height: 90)
        let base = try file([], over: source, scale: 1.5)
        for (step, side) in [(AnnotationThickness.thin, 15), (.medium, 24), (.thick, 36)] {
            let out = try file([blur(CGRect(x: 7.3, y: 5.1, width: 60.2, height: 31.9), step)], over: source, scale: 1.5)
            let box = (Int((7.3 * 1.5).rounded(.down)), Int((5.1 * 1.5).rounded(.down)),
                       Int(((7.3 + 60.2) * 1.5).rounded(.up)), Int(((5.1 + 31.9) * 1.5).rounded(.up)))
            XCTAssertGreaterThan(holds(out, base, width: 150, box: box, side: side, "1.5x \(step)"), 1)
            XCTAssertNotEqual(out, base)
        }
    }

    func testTwoOverlappingBlursAreBothOfTheFramesPixelsAndTheSecondDoesNotAverageTheFirst() throws {
        let source = pattern(width: 120, height: 80)
        let first = blur(CGRect(x: 10, y: 10, width: 60, height: 40), .thick)
        let second = blur(CGRect(x: 30, y: 20, width: 70, height: 40), .medium)
        let both = try file([first, second], over: source, scale: 1)
        let onlySecond = try file([second], over: source, scale: 1)
        for y in 20..<60 { for x in 30..<100 where both[y * 120 + x] != onlySecond[y * 120 + x] {
            return XCTFail("(\(x), \(y)) under the second blur holds the first's mosaic and not the frame's")
        } }
        let onlyFirst = try file([first], over: source, scale: 1)
        XCTAssertNotEqual(onlyFirst, both, "the control: the second blur did nothing")
        XCTAssertEqual(both[12 * 120 + 12], onlyFirst[12 * 120 + 12], "where only the first reaches it is the first's")
    }

    func testAShapeOverABlurShowsAndABlurOverAShapeHidesItBecauseTheMosaicIsTheFramesAndNotTheLayersBelow() throws {
        let source = pattern(width: 120, height: 80)
        let box = blur(CGRect(x: 20, y: 20, width: 60, height: 40), .thick)
        let bar = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 40), end: CGPoint(x: 100, y: 44),
                             style: AnnotationStyle(color: .red, thickness: .thick, filled: true))
        let over = try file([box, bar], over: source, scale: 1), under = try file([bar, box], over: source, scale: 1)
        let blurOnly = try file([box], over: source, scale: 1), barOnly = try file([bar], over: source, scale: 1)
        XCTAssertEqual(over[41 * 120 + 50], barOnly[41 * 120 + 50], "the shape over the blur is not the shape")
        XCTAssertNotEqual(over[41 * 120 + 50], blurOnly[41 * 120 + 50], "the control: the shape and the mosaic are one colour here")
        XCTAssertEqual(under[41 * 120 + 50], blurOnly[41 * 120 + 50], "the blur over the shape took the shape into its mean, or left it showing")
        XCTAssertEqual(under[41 * 120 + 15], barOnly[41 * 120 + 15], "outside the blur the shape is still there")
    }

    func testAPictureWithAlphaSixteenBitsOrAnotherSpaceStillHasOneColourABlock() throws {
        let spaces: [(String, CGColorSpace, Int)] = [("P3", CGColorSpace(name: CGColorSpace.displayP3)!, 8),
                                                      ("16-bit sRGB", CGColorSpace(name: CGColorSpace.sRGB)!, 16),
                                                      ("Adobe RGB", CGColorSpace(name: CGColorSpace.adobeRGB1998)!, 8),
                                                      ("linear", CGColorSpace(name: CGColorSpace.linearSRGB)!, 8)]
        for (name, space, bits) in spaces {
            let source = pattern(width: 80, height: 50, space: space, bits: bits)
            let base = try file([], over: source, scale: 1)
            let out = try file([blur(CGRect(x: 9, y: 7, width: 50, height: 30))], over: source, scale: 1)
            XCTAssertGreaterThan(holds(out, base, width: 80, box: (9, 7, 59, 37), side: 16, name), 6, name)
            XCTAssertNotEqual(out, base, name)
        }
        // A grey picture: no RGB model of its own, so the bitmap is sRGB.
        let grey = CGContext(data: nil, width: 80, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        for x in 0..<80 { grey.setFillColor(gray: CGFloat(x % 7) / 7, alpha: 1); grey.fill(CGRect(x: x, y: 0, width: 1, height: 50)) }
        let greyImage = grey.makeImage()!
        let out = try file([blur(CGRect(x: 8, y: 8, width: 32, height: 32))], over: greyImage, scale: 1)
        XCTAssertEqual(Set((16..<32).flatMap { y in (16..<32).map { out[y * 80 + $0] } }).count, 1, "a grey picture's block is not one colour")
        // A half-transparent picture draws, and the box's block is one colour.
        let clear = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        clear.setFillColor(red: 0.5, green: 0, blue: 0, alpha: 0.5); clear.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let clearImage = clear.makeImage()!
        let alpha = try file([blur(CGRect(x: 4, y: 4, width: 30, height: 30))], over: clearImage, scale: 1)
        XCTAssertEqual(Set((4..<16).flatMap { y in (4..<16).map { alpha[y * 40 + $0] } }).count, 1)
    }

    func testACutInsideTheDisplayHoldsTheBlocksOfTheDisplayAndANeighbourDoesNotLeakIn() async throws {
        let source = pattern(width: 200, height: 120)
        let display = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 200, height: 120), scale: 1, image: source)
        let freeze = Freeze(displays: [.image(display)], windows: [])
        let rig = Rig(home: scratchDirectory("shots-blur-cut"))
        // The cut starts off the 16-pixel grid; the box runs out of the cut on every side.
        let cutRect = CGRect(x: 21, y: 13, width: 70, height: 50)
        let layer = blur(CGRect(x: 5, y: 3, width: 150, height: 90))
        let drawnOrNil = await rig.session.annotated(freeze, display: DisplayID(1), local: cutRect, layers: [layer])
        let drawn = try XCTUnwrap(drawnOrNil)
        let whole = try file([layer], over: source, scale: 1)
        let cut = pixels(drawn)
        for y in 0..<50 { for x in 0..<70 where cut[y * 70 + x] != whole[(y + 13) * 200 + x + 21] {
            return XCTFail("the cut differs from the whole display's file at (\(x), \(y))")
        } }
        // A selection wholly off the display, with a blur: nothing, and no trap.
        let off = await rig.session.annotated(freeze, display: DisplayID(1), local: CGRect(x: 500, y: 500, width: 10, height: 10), layers: [layer])
        XCTAssertNil(off)
    }

    func testABoxPastAnImageSmallerThanItsFrameIsClippedToTheImage() throws {
        // The picture is 100 x 60 pixels at 2x: a 50 x 30 point display.
        let source = pattern(width: 100, height: 60)
        let base = try file([], over: source, scale: 2)
        let out = try file([blur(CGRect(x: 10, y: 10, width: 500, height: 500))], over: source, scale: 2)
        holds(out, base, width: 100, box: (20, 20, 100, 60), side: 32, "small image")
    }
}
