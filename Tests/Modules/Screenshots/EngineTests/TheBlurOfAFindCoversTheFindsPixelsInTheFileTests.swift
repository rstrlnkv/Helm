import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **A blur that "Blur Emails and Phone Numbers" puts over a find leaves none of the find's pixels in the file.**
/// The geometry tests (`TheRecognizedBoxesLandOnTheFramesPixelsTests`) assert rectangles; this one asserts the
/// file: a picture in which every pixel is its own colour, a reader that finds what it is told to, the whole way
/// through `readText`, `PersonalFinds`, `AnnotationEditing.insert(blurs:)` and `annotated`, and then each pixel the
/// find stood on is compared with the same pixel of the unblurred cut. A pixel the mosaic left as it was is
/// a pixel of the text that survived.
///
/// The pictures are 1×, 1.5× and 2×, the area is never on the mosaic's grid, and the finds sit in the middle, at
/// every edge of the area, in a corner, and larger than the area.
final class TheBlurOfAFindCoversTheFindsPixelsInTheFileTests: XCTestCase {

    /// Every pixel its own colour: three channels from a hash of the position, so no two neighbours are alike and
    /// a mean of a block is never the colour of a pixel in it (the test below proves that of its own picture).
    private func noise(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var h = UInt32(truncatingIfNeeded: x &* 73_856_093 ^ y &* 19_349_663 ^ 0x9E37_79B9)
                h = (h ^ (h >> 15)) &* 2_246_822_519
                h = (h ^ (h >> 13)) &* 3_266_489_917
                let at = (y * width + x) * 4
                bytes[at] = UInt8(truncatingIfNeeded: h)
                bytes[at + 1] = UInt8(truncatingIfNeeded: h >> 8)
                bytes[at + 2] = UInt8(truncatingIfNeeded: h >> 16)
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func makeRig() throws -> Rig {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("helm-find-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return Rig(home: home)
    }

    /// The pixels of the cut that a normalised box stands on, worked out here from the box alone: the lower-left
    /// origin turned over, rounded outward, kept to the cut. Nothing of `RecognizedBoxes` is used.
    private func pixelsOfTheFind(_ box: CGRect, cutWidth: Int, cutHeight: Int) -> (xs: Range<Int>, ys: Range<Int>)? {
        let x0 = max(0, Int((max(0, box.minX) * CGFloat(cutWidth)).rounded(.down)))
        let x1 = min(cutWidth, Int((min(1, box.maxX) * CGFloat(cutWidth)).rounded(.up)))
        let y0 = max(0, Int(((1 - min(1, box.maxY)) * CGFloat(cutHeight)).rounded(.down)))
        let y1 = min(cutHeight, Int(((1 - max(0, box.minY)) * CGFloat(cutHeight)).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        return (x0..<x1, y0..<y1)
    }

    /// What a find may leave of itself: nothing. Returns the pixels of the find that are the same in the file.
    private func survivors(scale: CGFloat, local: CGRect, boxes: [CGRect], kinds: [PrivateKind]? = nil, secondDisplay: Bool = false,
                           file: StaticString = #filePath, line: UInt = #line) async throws -> (left: Int, of: Int, blurs: Int, steps: [AnnotationThickness]) {
        let rig = try makeRig()
        let widthPoints: CGFloat = 400, heightPoints: CGFloat = 300
        let image = noise(width: Int(widthPoints * scale), height: Int(heightPoints * scale))
        // `secondDisplay`: the display read is the second of two, left of the first, at another scale than the first's.
        let id = DisplayID(secondDisplay ? 2 : 1)
        let display = FrozenDisplay(id: id, frame: CGRect(x: secondDisplay ? -widthPoints : 0, y: 0, width: widthPoints, height: heightPoints),
                                    scale: scale, image: image)
        let first = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: scale == 2 ? 1 : 2,
                                  image: makeImage(width: scale == 2 ? 100 : 200, height: scale == 2 ? 50 : 100, red: 9))
        let freeze = Freeze(displays: secondDisplay ? [.image(first), .image(display)] : [.image(display)], windows: [])
        let matches = boxes.enumerated().map { PrivateMatch(kind: kinds?[$0.offset] ?? .emailAddress, box: $0.element) }
        rig.reader.reading = .read(matches.map {
            RecognizedLine(string: "x", box: CGRect(x: 0, y: 0, width: 1, height: 1), matches: [$0])
        })
        guard case .read(let lines, let source) = await rig.session.readText(freeze, display: id, local: local) else {
            XCTFail("the reading did not come back", file: file, line: line)
            return (0, 0, 0, [])
        }
        let finds = PersonalFinds.finds(in: lines, source: source, under: [])
        var editing = AnnotationEditing(bounds: local)
        let added = editing.insert(blurs: finds)
        let cut = try XCTUnwrap(rig.session.crop(freeze, display: id, local: local), file: file, line: line)
        let blurred = await rig.session.annotated(freeze, display: id, local: local, layers: editing.layers)
        let result = try XCTUnwrap(blurred, "the file was refused for \(boxes)", file: file, line: line)
        XCTAssertEqual(result.width, cut.width, file: file, line: line)
        let before = rgba(cut), after = rgba(result)
        var left = 0, total = 0
        for box in boxes {
            guard let found = pixelsOfTheFind(box, cutWidth: cut.width, cutHeight: cut.height) else { continue }
            for y in found.ys {
                for x in found.xs {
                    total += 1
                    let at = (y * cut.width + x) * 4
                    if before[at..<at + 4] == after[at..<at + 4] { left += 1 }
                }
            }
        }
        return (left, total, added, finds.map(\.step))
    }

    /// The control for the picture: a blur drawn by hand over a box leaves no pixel of it, so a survivor below is the find's and not the noise's.
    func testTheNoisePictureShowsEveryPixelOfAMosaicChanged() async throws {
        let rig = try makeRig()
        let display = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 2,
                                    image: noise(width: 800, height: 600))
        let freeze = Freeze(displays: [.image(display)], windows: [])
        let frame = CGRect(x: 40, y: 40, width: 100, height: 40)
        let layer = Annotation(tool: .blur, start: frame.origin, end: CGPoint(x: frame.maxX, y: frame.maxY),
                               style: AnnotationStyle(thickness: .thin), id: 1)
        let local = CGRect(x: 0, y: 0, width: 400, height: 300)
        let cut = try XCTUnwrap(rig.session.crop(freeze, display: DisplayID(1), local: local))
        let annotated = await rig.session.annotated(freeze, display: DisplayID(1), local: local, layers: [layer])
        let out = try XCTUnwrap(annotated)
        let a = rgba(cut), b = rgba(out)
        var same = 0, all = 0
        for y in 80..<160 { for x in 80..<280 { all += 1; let at = (y * 800 + x) * 4; if a[at..<at + 4] == b[at..<at + 4] { same += 1 } } }
        XCTAssertGreaterThan(all, 10_000)
        XCTAssertEqual(same, 0, "the mosaic itself leaves \(same) of \(all) pixels as they were")
        XCTAssertEqual(Array(a[0..<4]), Array(b[0..<4]), "the control of the control: a pixel outside the box is untouched")
    }

    private let areas: [CGRect] = [
        CGRect(x: 13.3, y: 9.7, width: 250.4, height: 140.1),
        CGRect(x: 0, y: 0, width: 400, height: 300),
        CGRect(x: 37, y: 61, width: 211, height: 97),
    ]

    /// In the middle, at each edge, in each corner, and larger than the area — at three scales and three areas.
    func testNoPixelOfAFindSurvivesAtAnyScaleOrAreaOrEdge() async throws {
        let boxes: [CGRect] = [
            CGRect(x: 0.30, y: 0.50, width: 0.30, height: 0.05),
            CGRect(x: 0.00, y: 0.50, width: 0.20, height: 0.05),
            CGRect(x: 0.80, y: 0.50, width: 0.20, height: 0.05),
            CGRect(x: 0.40, y: 0.95, width: 0.20, height: 0.05),
            CGRect(x: 0.40, y: 0.00, width: 0.20, height: 0.05),
            CGRect(x: 0.00, y: 0.00, width: 0.10, height: 0.04),
            CGRect(x: 0.90, y: 0.96, width: 0.10, height: 0.04),
            CGRect(x: -0.2, y: 0.20, width: 1.40, height: 0.08),
        ]
        var checked = 0
        for scale in [CGFloat(1), 1.5, 2] {
            for local in areas {
                for (index, box) in boxes.enumerated() {
                    let out = try await survivors(scale: scale, local: local, boxes: [box])
                    XCTAssertEqual(out.blurs, 1, "scale \(scale) area \(local) box #\(index): one find, one blur")
                    XCTAssertGreaterThan(out.of, 0)
                    XCTAssertEqual(out.left, 0, "scale \(scale) area \(local) box #\(index) \(box): \(out.left) of \(out.of) pixels of the find are in the file as they were")
                    checked += out.of
                }
            }
        }
        XCTAssertGreaterThan(checked, 100_000, "the walk saw too few pixels for a pass to mean anything")
    }

    /// Heights across the three steps and one beyond them: the text's own pixels go, and the step has a block as high as the text.
    func testEveryTextHeightIsCoveredAndItsBlockIsAsHighAsTheText() async throws {
        for scale in [CGFloat(1), 1.5, 2] {
            for heightPoints in [CGFloat(6), 10, 11, 16, 17, 24, 25, 40] {
                let local = CGRect(x: 13.3, y: 9.7, width: 300.4, height: 200.1)
                let normalisedHeight = heightPoints / local.height
                let box = CGRect(x: 0.25, y: 0.40, width: 0.4, height: normalisedHeight)
                let out = try await survivors(scale: scale, local: local, boxes: [box])
                XCTAssertEqual(out.left, 0, "scale \(scale), text \(heightPoints) pt: \(out.left) of \(out.of) pixels survive")
                let step = try XCTUnwrap(out.steps.first)
                let block = CGFloat(Pixelate.block(points: step.points(for: .blur), scale: scale)) / scale
                // The text is as high as the box says, to the pixel; a thickest block that is lower than it is the
                // one case where no block is high enough, and 40 pt is that case.
                if heightPoints <= 24 {
                    XCTAssertGreaterThanOrEqual(block, heightPoints - 1 / scale, "scale \(scale), text \(heightPoints) pt: the block is \(block) pt")
                }
            }
        }
    }

    /// Two finds in one line, side by side and overlapping their padding, and a find of every kind in one box: each is covered, once.
    func testFindsThatShareAPaddingAndKindsThatShareABoxAreCoveredOnce() async throws {
        let local = CGRect(x: 13.3, y: 9.7, width: 250.4, height: 140.1)
        let box = CGRect(x: 0.3, y: 0.5, width: 0.3, height: 0.05)
        let all: [PrivateKind] = [.emailAddress, .phoneNumber, .cardNumber, .link]
        let same = try await survivors(scale: 2, local: local, boxes: Array(repeating: box, count: 4), kinds: all)
        XCTAssertEqual(same.left, 0)
        XCTAssertEqual(same.blurs, 1, "four kinds on one box are one place, and one blur")
        let near = [CGRect(x: 0.10, y: 0.5, width: 0.20, height: 0.05), CGRect(x: 0.31, y: 0.5, width: 0.20, height: 0.05)]
        let two = try await survivors(scale: 1.5, local: local, boxes: near)
        XCTAssertEqual(two.left, 0)
    }

    /// A find of a pixel or two at the very corner of the area, which at 1× is a box of one point.
    func testATinyFindInACornerDoesNotRefuseTheFile() async throws {
        for scale in [CGFloat(1), 2] {
            for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 0.9995, y: 0), CGPoint(x: 0, y: 0.9995), CGPoint(x: 0.9995, y: 0.9995)] {
                let local = CGRect(x: 20, y: 20, width: 200, height: 200)
                let box = CGRect(x: corner.x, y: corner.y, width: 0.0005, height: 0.0005)
                let out = try await survivors(scale: scale, local: local, boxes: [box])
                XCTAssertEqual(out.left, 0, "scale \(scale) corner \(corner)")
            }
        }
    }

    /// The display read is the second of two and has another scale than the first: the blur lands on the display it was read from.
    func testTheSecondDisplayAtAnotherScaleIsCoveredToo() async throws {
        let local = CGRect(x: 13.3, y: 9.7, width: 250.4, height: 140.1)
        for scale in [CGFloat(1), 1.5, 2] {
            let out = try await survivors(scale: scale, local: local, boxes: [CGRect(x: 0.3, y: 0.5, width: 0.3, height: 0.05)], secondDisplay: true)
            XCTAssertEqual(out.blurs, 1, "scale \(scale)")
            XCTAssertGreaterThan(out.of, 0)
            XCTAssertEqual(out.left, 0, "scale \(scale): \(out.left) of \(out.of)")
        }
    }

    /// An area whose far edge is one pixel past a grid line, and a find whose ink lies wholly in the last pixel of both axes: the box the
    /// rounding leaves is one pixel, which the mosaic cannot make (a block of one pixel is its own pixel) and which the file refuses.
    func testAFindInTheLastPixelOfAnAreaThatEndsPastAGridLineDoesNotRefuseTheFile() async throws {
        let local = CGRect(x: 20, y: 20, width: 201, height: 201)
        let out = try await survivors(scale: 1, local: local, boxes: [CGRect(x: 0.9985, y: 0.0, width: 0.0015, height: 0.0015)])
        XCTAssertEqual(out.left, 0)
    }
}
