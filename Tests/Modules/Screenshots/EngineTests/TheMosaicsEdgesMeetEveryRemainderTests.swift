import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A mosaic's blocks are read off its picture, not off the rule that cut them.** `Pixelate.tile` is fed boxes
/// whose end strip is at, one under and one over the merge threshold, on both axes, at three scales and for the three
/// steps, boxes of one pixel in a direction, and boxes cut by the display's far edge. The picture has a colour of its
/// own in every pixel, so the output alone says where its blocks are: a colour that is not the source's,
/// a change of colour only on a grid line of the display, no run of one colour of two blocks, and
/// no block of one pixel. None of it consults `edges`, so a wrong merge rule cannot agree with itself.
final class TheMosaicsEdgesMeetEveryRemainderTests: XCTestCase {
    /// Noise in the low bits, and in the top three bits of red the display's grid column and of green its grid row:
    /// two neighbouring blocks never mean to one colour by chance, so a run of one colour is one block.
    private func pattern(width: Int, height: Int, side: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            // Mixed, not linear in the index: a mean of pixels in an arithmetic progression is the middle one.
            var z = UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ 12_345
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            let colour = UInt32(truncatingIfNeeded: (z ^ (z >> 31)) >> 8) & 0xFF_FFFF
            bytes[index * 4] = UInt8((index % width / side % 8) << 5) | UInt8(colour >> 16 & 0x1F)
            bytes[index * 4 + 1] = UInt8((index / width / side % 8) << 5) | UInt8(colour >> 8 & 0x1F)
            bytes[index * 4 + 2] = UInt8(colour & 0xFF)
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func read(_ image: CGImage) -> [UInt32] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).map {
            UInt32(bytes[$0 * 4]) << 16 | UInt32(bytes[$0 * 4 + 1]) << 8 | UInt32(bytes[$0 * 4 + 2])
        }
    }

    private var checked = 0, refused = 0, merged = 0

    /// One box in whole pixels `x..<x+w`, `y..<y+h` of `display`; the invariants asserted on the tile's bytes alone.
    private func check(_ display: CGImage, source: [UInt32], scale: CGFloat, points: CGFloat,
                       x: Int, y: Int, w: Int, h: Int, _ name: String) {
        let side = Pixelate.block(points: points, scale: scale)
        // A quarter pixel in on every side: the box rounds outward to exactly these pixels.
        let rect = CGRect(x: (CGFloat(x) + 0.25) / scale, y: (CGFloat(y) + 0.25) / scale,
                          width: (CGFloat(w) - 0.5) / scale, height: (CGFloat(h) - 0.5) / scale)
        let tile = Pixelate.tile(of: display, rect: rect, blockPoints: points, scale: scale)
        let cw = min(x + w, display.width) - x, ch = min(y + h, display.height) - y
        guard cw > 0, ch > 0 else { XCTAssertNil(tile, name); return }
        guard cw * ch > 1 else { refused += 1; XCTAssertNil(tile, "\(name): one pixel must give no tile"); return }
        guard let tile else { XCTFail("\(name): no tile for \(cw)x\(ch) pixels"); return }
        checked += 1
        XCTAssertEqual(tile.pixels, CGRect(x: x, y: y, width: cw, height: ch), name)
        let out = read(tile.image)
        XCTAssertEqual(out.count, cw * ch, name)
        guard out.count == cw * ch else { return }
        // Counted: pixels equal to their source's own colour whose colour fills fewer than four pixels of the tile.
        // A rounded mean can equal a source pixel, so a colour filling four or more is not counted; this fixture's
        // pattern is what makes the count zero in the small blocks.
        var size: [UInt32: Int] = [:]
        for colour in out { size[colour, default: 0] += 1 }
        var same = 0
        for j in 0..<ch { for i in 0..<cw where out[j * cw + i] == source[(y + j) * display.width + x + i] && size[out[j * cw + i]]! < 4 { same += 1 } }
        XCTAssertEqual(same, 0, "\(name): \(same) pixels of the source are in a small block as they were")
        // Runs of one colour along a row and along a column: they break only on the display's grid, and none is
        // a pixel long (unless the box is one pixel across) or longer than a block and its end strip.
        func runs(count: Int, length: Int, start: Int, colour: (Int, Int) -> UInt32, _ axis: String) {
            for line in 0..<count {
                var from = 0
                for k in 1...length where k == length || colour(line, k) != colour(line, k - 1) {
                    let run = k - from
                    if k < length { XCTAssertEqual((start + k) % side, 0, "\(name) \(axis) \(line): a block breaks off the grid at \(k)") }
                    if length > 1 { XCTAssertGreaterThan(run, 1, "\(name) \(axis) \(line): a run of \(run) pixel") }
                    XCTAssertLessThan(run, 2 * side, "\(name) \(axis) \(line): a run of \(run) is more than a block and its strip")
                    if run > side { merged += 1 }
                    from = k
                }
            }
        }
        runs(count: ch, length: cw, start: x, colour: { out[$0 * cw + $1] }, "row")
        runs(count: cw, length: ch, start: y, colour: { out[$1 * cw + $0] }, "column")
        // Each block is two pixels or more: its colour is shared by at least two pixels of the tile.
        XCTAssertEqual(size.values.filter { $0 < 2 }.count, 0, "\(name): a block of one pixel")
    }

    func testEveryRemainderAtEveryScaleStepAndEdge() {
        for scale: CGFloat in [1, 1.5, 2] {
            for points: CGFloat in [10, 16, 24] {
                let side = Pixelate.block(points: points, scale: scale)
                let least = max(2, (side + 1) / 2)
                let width = 3 * side + 9, height = 3 * side + 5
                let display = pattern(width: width, height: height, side: side), source = read(display)
                let tag = "\(scale)x \(Int(points))pt"
                // Starts at every offset of interest; lengths so that the end strip is the remainder under, at and over
                // the threshold, from one pixel to a block, with none, one and two whole blocks before it.
                let remainders = Set([1, 2, 3, least - 1, least, least + 1, side - 1, side, side + 1].filter { $0 >= 1 })
                for start in Set([0, 1, 2, side / 2, side - 1, side + 1]) {
                    for remainder in remainders {
                        for blocks in [0, 1, 2] {
                            let length = blocks * side + remainder
                            // Both axes at once, then each axis against an ordinary other.
                            check(display, source: source, scale: scale, points: points, x: start, y: start, w: length, h: length,
                                  "\(tag) both axes start \(start) len \(length)")
                            check(display, source: source, scale: scale, points: points, x: start, y: 3, w: length, h: 2 * side + 1,
                                  "\(tag) x start \(start) len \(length)")
                            check(display, source: source, scale: scale, points: points, x: 3, y: start, w: 2 * side + 1, h: length,
                                  "\(tag) y start \(start) len \(length)")
                        }
                    }
                }
                // A pixel wide and a pixel tall, 1 x 1, 2 x 1, and the starts either side of a grid line.
                for start in [0, side - 1, side, side + 1] {
                    for n in [1, 2, 3, side, side + 1, 2 * side + 1] {
                        check(display, source: source, scale: scale, points: points, x: start, y: start, w: 1, h: n, "\(tag) 1x\(n) at \(start)")
                        check(display, source: source, scale: scale, points: points, x: start, y: start, w: n, h: 1, "\(tag) \(n)x1 at \(start)")
                    }
                }
                // The display's far edges: the box runs past the last pixel and the display cuts its neighbour block.
                for gap in Set([0, 1, 2, least - 1, least, least + 1, side - 1]) {
                    for back in [1, 2, 3, side, side + 1] {
                        check(display, source: source, scale: scale, points: points, x: width - gap - back, y: height - gap - back,
                              w: back + gap + 7, h: back + gap + 7, "\(tag) far corner gap \(gap) back \(back)")
                        check(display, source: source, scale: scale, points: points, x: width - back, y: 2, w: back + 9, h: 2 * side + 1,
                              "\(tag) far right back \(back)")
                        check(display, source: source, scale: scale, points: points, x: 2, y: height - back, w: 2 * side + 1, h: back + 9,
                              "\(tag) far bottom back \(back)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 3000, "the sweep must have happened")
        XCTAssertGreaterThan(refused, 0, "the one-pixel boxes must have happened")
        XCTAssertGreaterThan(merged, 0, "no end strip was ever merged: the sweep never met the rule")
    }
}
