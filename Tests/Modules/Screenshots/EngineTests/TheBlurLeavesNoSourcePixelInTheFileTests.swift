import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A blurred box leaves no pixel of the picture in the file, and one colour in each block.** The picture under it is
/// a pattern in which every pixel has a colour of its own, so a pixel that survived (a blur too weak to hide
/// anything, a block that took a corner of its neighbour) is a colour the box's source holds and nothing else does,
/// and a block that is not one colour is read straight off the file's bytes. The grid is the display's pixels at
/// the block's size, so the box's edges cut blocks, and the edge blocks are read the same as the others.
final class TheBlurLeavesNoSourcePixelInTheFileTests: XCTestCase {
    private struct Case {
        let scale: CGFloat
        /// In display points, top-left.
        let rect: CGRect
        let step: AnnotationThickness
        var name: String { "\(Int(scale))x \(step) \(rect)" }
    }

    private static let cases: [Case] = {
        let tall = CGRect(x: 20.25, y: 17.25, width: 120.25, height: 42.5)
        // Twenty points tall under a sixteen-point block: one row of blocks, cut by the box's edge.
        let flat = CGRect(x: 20.25, y: 10, width: 120.75, height: 20)
        // The box's edge passes one pixel beyond a grid line (60 pt is pixel 120 at 2x, the box ends at pixel 121): the
        // corner a grid cut would leave is one pixel, which a mean of one pixel would show as it is. And the same
        // box one pixel wide.
        let corner = CGRect(x: 12, y: 7, width: 48.5, height: 33.5)
        let strip = CGRect(x: 60, y: 7, width: 0.5, height: 60)
        return AnnotationThickness.allCases.map { Case(scale: 2, rect: tall, step: $0) }
            + [Case(scale: 2, rect: corner, step: .thin), Case(scale: 2, rect: strip, step: .thin),
               Case(scale: 2, rect: corner, step: .medium),Case(scale: 1, rect: flat, step: .medium), Case(scale: 2, rect: flat, step: .medium),
               Case(scale: 1, rect: tall, step: .thin)]
    }()

    /// Every pixel its own colour: the index through a multiplier that is odd, so it is a bijection on the 24 bits.
    private func pattern(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let colour = (UInt32(index) &* 2_654_435_761 &+ 12_345) & 0xFF_FFFF
            bytes[index * 4] = UInt8(colour >> 16)
            bytes[index * 4 + 1] = UInt8(colour >> 8 & 0xFF)
            bytes[index * 4 + 2] = UInt8(colour & 0xFF)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt32] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).map { index in
            UInt32(bytes[index * 4]) << 16 | UInt32(bytes[index * 4 + 1]) << 8 | UInt32(bytes[index * 4 + 2])
        }
    }

    /// The grid block of pixel `v` in a run `from..<to`: the display's grid, but an end strip narrower than half a block
    /// belongs to the block beside it (a run inside one grid block is that block).
    private func key(_ v: Int, from: Int, to: Int, side: Int) -> Int {
        let least = max(2, (side + 1) / 2), first = from / side, last = (to - 1) / side, k = v / side
        guard first != last else { return k }
        if k == first, (first + 1) * side - from < least { return k + 1 }
        if k == last, to - last * side < least { return k - 1 }
        return k
    }

    /// A box that is one pixel cannot be hidden by a mean of its pixels: no file is made, and a box off the
    /// display, which hides nothing, does not stop one.
    func testABoxOfOnePixelRefusesTheFileAndABoxOffTheDisplayDoesNot() async throws {
        let source = pattern(width: 400, height: 240)
        let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                            scale: 2, image: source))], windows: [])
        let rig = Rig(home: scratchDirectory("shots-blur-one-pixel"))
        let whole = CGRect(x: 0, y: 0, width: 200, height: 120)
        func blur(_ rect: CGRect) -> Annotation {
            Annotation(tool: .blur, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), style: AnnotationStyle())
        }
        let one = await rig.session.annotated(freeze, display: DisplayID(1), local: whole,
                                              layers: [blur(CGRect(x: 60, y: 40, width: 0.5, height: 0.5))])
        XCTAssertNil(one, "a one-pixel box left a file with its source pixel in it")
        let away = await rig.session.annotated(freeze, display: DisplayID(1), local: whole,
                                               layers: [blur(CGRect(x: 500, y: 40, width: 20, height: 20))])
        XCTAssertNotNil(away, "a box off the display hides nothing and must not refuse the file")
    }

    func testNoPixelOfTheBoxSurvivesAndEveryBlockIsOneColourItsOwnMean() async throws {
        for test in Self.cases {
            let width = Int(200 * test.scale), height = Int(120 * test.scale)
            let source = pattern(width: width, height: height)
            let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                                scale: test.scale, image: source))], windows: [])
            let rig = Rig(home: scratchDirectory("shots-blur-\(Int(test.scale))-\(test.step.rawValue)-\(Int(test.rect.height))"))
            let layer = Annotation(tool: .blur, start: CGPoint(x: test.rect.minX, y: test.rect.minY),
                                   end: CGPoint(x: test.rect.maxX, y: test.rect.maxY), style: AnnotationStyle(thickness: test.step))
            let drawn = await rig.session.annotated(freeze, display: DisplayID(1), local: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                    layers: [layer])
            let out = pixels(try XCTUnwrap(drawn, test.name)), was = pixels(source)
            XCTAssertEqual(out.count, was.count, test.name)

            // The box in whole pixels, rounded outward, and the display's grid at the block's size.
            let x0 = Int((test.rect.minX * test.scale).rounded(.down)), x1 = Int((test.rect.maxX * test.scale).rounded(.up))
            let y0 = Int((test.rect.minY * test.scale).rounded(.down)), y1 = Int((test.rect.maxY * test.scale).rounded(.up))
            let side = Int((test.step.points(for: .blur) * test.scale).rounded())
            var blocks: [[Int]: [Int]] = [:]
            for y in y0..<y1 { for x in x0..<x1 {
                blocks[[key(x, from: x0, to: x1, side: side), key(y, from: y0, to: y1, side: side)], default: []].append(y * width + x)
            } }
            XCTAssertGreaterThan(blocks.count, 3, "\(test.name): too few blocks for the test to see a blur")

            var inside = Set<UInt32>()
            for members in blocks.values { for index in members { inside.insert(was[index]) } }
            XCTAssertEqual(inside.count, (x1 - x0) * (y1 - y0), "\(test.name): the pattern repeats a colour inside the box")
            var shown = Set<UInt32>()
            for (block, members) in blocks {
                XCTAssertGreaterThan(members.count, 1, "\(test.name) \(block): a one-pixel block is its own source")
                let colours = Set(members.map { out[$0] })
                shown.formUnion(colours)
                XCTAssertEqual(colours.count, 1, "\(test.name) block \(block): \(colours.count) colours in one block")
                // The mean of the block's pixels inside the box, channel by channel, to within the one that rounding costs.
                for shift in [16, 8, 0] {
                    let mean = members.map { Int(was[$0] >> UInt32(shift) & 0xFF) }.reduce(0, +) / members.count
                    let got = Int((colours.first ?? 0) >> UInt32(shift) & 0xFF)
                    XCTAssertLessThanOrEqual(abs(got - mean), 1, "\(test.name) block \(block) channel \(shift): \(got) is not the mean \(mean)")
                }
            }
            XCTAssertEqual(shown.intersection(inside).count, 0,
                           "\(test.name): \(shown.intersection(inside).count) source colours of the box are in the file")
            XCTAssertLessThanOrEqual(shown.count, blocks.count, "\(test.name): more colours than blocks")

            // Outside the box not a byte moved.
            var strayed = 0
            for y in 0..<height { for x in 0..<width where !(x0..<x1).contains(x) || !(y0..<y1).contains(y) {
                if out[y * width + x] != was[y * width + x] { strayed += 1 }
            } }
            XCTAssertEqual(strayed, 0, "\(test.name): \(strayed) pixels outside the box changed")
        }
    }
}
