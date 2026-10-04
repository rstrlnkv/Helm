import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A picture the editor shows reduced is saved at its own size, and the marks land where they were drawn.** «Edit»
/// lays a finished picture over a fresh freeze (`PictureOnScreen`), one pixel of it to one pixel of the display
/// while it fits and reduced to fit when it does not, and the export draws the layers over the picture itself with
/// their points moved by the ratio of each axis (`CaptureSession.annotated(_:local:layers:)`, `Annotation.mapped(_:)`) and
/// their strokes as thick as `pixelsPerPoint` says. A save that wrote what
/// the screen showed would replace a 4000-pixel screenshot with a 1000-pixel one.
///
/// Everything is read back out of the rendered picture: its size, where the ink of a stroke is and how thick, which
/// pixels of the display are the picture and which are the ground. Display 100×60 points, at the scale each case says.
///
/// Total failure of the subject prints: a file the size of the screen, a mark drawn off the place it was put, a stroke
/// as thin as on the reduced picture, or a picture off the middle of the display.
final class TheEditOfALargerPictureExportsAtItsOwnSizeTests: XCTestCase {

    private let ground = (red: UInt8(255), green: UInt8(0), blue: UInt8(0))

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A picture of one colour in sRGB, which is the space a composition draws in: a picture in the device's generic
    /// space is converted on the way and no longer reads as the colour it was made as.
    private func solid(_ width: Int, _ height: Int, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: srgb, components: [r, g, b, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Left half red, right half blue, in sRGB.
    private func split(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: srgb, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(colorSpace: srgb, components: [0, 0, 1, 1])!)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    private func freeze(scale: CGFloat, ids: [UInt32] = [1]) -> Freeze {
        let width = Int(100 * scale), height = Int(60 * scale)
        return Freeze(displays: ids.enumerated().map { index, id in
            .image(FrozenDisplay(id: DisplayID(id), frame: CGRect(x: 1000 * CGFloat(index), y: 0, width: 100, height: 60), scale: scale,
                                 image: solid(width, height, 1, 0, 0)))
        }, windows: [])
    }

    private func white(_ width: Int, _ height: Int) -> CGImage { solid(width, height, 1, 1, 1) }

    private func session() -> CaptureSession { Rig(home: scratchDirectory("shots-larger")).session }

    private func placed(_ picture: CGImage, scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws -> PictureOnScreen {
        try XCTUnwrap(PictureOnScreen.place(picture, over: freeze(scale: scale), on: nil), "the picture was not placed", file: file, line: line)
    }

    /// One pixel of a picture as red, green, blue, read at (x, y) from the top left, in the picture's own colour space:
    /// reading it in another converts it, and a ground that was composed in sRGB would read as a stranger to itself.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (bytes[0], bytes[1], bytes[2])
    }

    /// The share of each pixel in column `x`, top to bottom, that is the red ink on white.
    private func inkColumn(_ image: CGImage, x: Int) -> [Double] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let inkGreen = Double(AnnotationColor.red.cgColor.components![1]) * 255
        return (0..<image.height).map { row in (255 - Double(bytes[row * image.width * 4 + x * 4 + 1])) / (255 - inkGreen) }
    }

    /// A rectangle whose top edge is 20 % down the picture and whose bottom edge is 60 % down, in the points of the display.
    private func marks(on shown: PictureOnScreen) -> [Annotation] {
        let r = shown.rect
        return [Annotation(tool: .rectangle, start: CGPoint(x: r.minX + 0.2 * r.width, y: r.minY + 0.2 * r.height),
                           end: CGPoint(x: r.minX + 0.8 * r.width, y: r.minY + 0.6 * r.height),
                           style: AnnotationStyle(thickness: .thin))]
    }


    /// The export of the area, read as a picture: a refusal to make one is a failure here and not a nil.
    private func cut(_ shown: PictureOnScreen, _ rect: CGRect, _ layers: [Annotation], _ what: String = "",
                     file: StaticString = #filePath, line: UInt = #line) async throws -> CGImage {
        let image = await session().annotated(shown, local: rect, layers: layers)
        return try XCTUnwrap(image, what, file: file, line: line)
    }

    // MARK: The size

    func testThePictureIsExportedAtItsOwnSizeWhateverTheDisplayIs() async throws {
        let sizes: [(Int, Int)] = [(400, 240), (200, 120), (80, 40), (1, 1), (333, 77), (1000, 1000), (4000, 2400), (201, 121)]
        for scale in [CGFloat(1), 2, 3] {
            for (width, height) in sizes {
                let shown = try placed(white(width, height), scale: scale)
                let out = try await cut(shown, shown.rect, marks(on: shown), "\(width)×\(height) at \(scale)×")
                XCTAssertEqual(out.width, width, "\(width)×\(height) at \(scale)×: the export is not the picture's width")
                XCTAssertEqual(out.height, height, "\(width)×\(height) at \(scale)×: the export is not the picture's height")
                let plain = try await cut(shown, shown.rect, [])
                XCTAssertEqual(plain.width, width)
                XCTAssertEqual(plain.height, height)
            }
        }
    }


    /// **The whole picture comes back, to its last row and column, from a picture reduced to fit.** Both sides of the
    /// reduced picture are whole pixels of the display, so the two ratios differ (12 × 250 at 2× is 6 × 120 pixels: 4.0
    /// across and 4.17 down), and a cut sized by the smaller one loses the last rows (`60 pt × 4.0 = 240` of 250): a
    /// replacement would then save a picture smaller than the original and put the original in the Trash. `pixelsPerPoint`
    /// is the larger ratio, and the area is cut by each axis's own. A wide picture is the same case turned: 900 × 300 on a
    /// 100 × 60-point display at 1× is 100 × 33, 9 across and 9.09 down.
    func testAPictureLargerThanItsDisplayIsNotCroppedByTheRoundingOfItsReducedSize() async throws {
        for (width, height, scale) in [(12, 250, CGFloat(2)), (7, 900, 1), (1, 5000, 2), (28, 3000, 2), (900, 300, 1), (6000, 40, 2)] {
            let shown = try placed(white(width, height), scale: scale)
            let out = try await cut(shown, shown.rect, [], "\(width)×\(height) at \(scale)×")
            XCTAssertEqual(out.width, width, "\(width)×\(height) at \(scale)×: the file would be \(out.width)×\(out.height)")
            XCTAssertEqual(out.height, height, "\(width)×\(height) at \(scale)×: the file would be \(out.width)×\(out.height), \(width - out.width) columns and \(height - out.height) rows lost")
        }
    }

    /// The same defect over the sizes of real pictures on real displays (1440 × 900 points at 2×, and 1920 × 1080 at 1×):
    /// how many of them the export does not return at their own size. The arithmetic of `PictureOnScreen` and of the cut,
    /// on no image.
    func testHowManyRealSizesComeBackAtTheirOwnSizeOnRealDisplays() {
        var wrong: [String] = [], total = 0
        for (display, scale) in [(CGSize(width: 2880, height: 1800), CGFloat(2)), (CGSize(width: 1920, height: 1080), 1)] {
            for width in stride(from: 1500, through: 9000, by: 61) {
                for height in stride(from: 60, through: 5000, by: 47) {
                    guard width > Int(display.width) || height > Int(display.height) else { continue }
                    total += 1
                    guard let rect = PictureOnScreen.frame(pixels: CGSize(width: width, height: height), on: display, scale: scale) else { continue }
                    let perPoint = CGFloat(width) / rect.width
                    guard let cut = ScreenSpace.pixels(ofLocal: CGRect(origin: .zero, size: rect.size), scale: perPoint,
                                                       imageWidth: width, imageHeight: height) else { continue }
                    if Int(cut.width) != width || Int(cut.height) != height {
                        wrong.append("\(width)×\(height) on \(Int(display.width))×\(Int(display.height)) → \(Int(cut.width))×\(Int(cut.height))")
                    }
                }
            }
        }
        XCTAssertGreaterThan(total, 1000, "the control: the sweep covers sizes")
        XCTAssertTrue(wrong.isEmpty, "\(wrong.count) of \(total) pictures larger than the display lose pixels in an edit, e.g. \(wrong.prefix(4))")
    }

    // MARK: The marks

    /// The stroke is three points on the screen and three points of the display, which is `pixelsPerPoint` pixels of
    /// the picture, and it is centred where the layer was drawn.
    func testAStrokeIsAsThickAndWhereItWasDrawnAgainstThePictureNotAgainstTheScreen() async throws {
        let cases: [(scale: CGFloat, width: Int, height: Int, label: String)] = [
            (2, 400, 240, "twice the display"), (2, 800, 480, "four times"), (1, 300, 180, "three times at 1×"),
            (2, 200, 120, "the display's own size"), (2, 80, 40, "smaller than the display"), (3, 301, 201, "not a whole ratio"),
            (2, 1000, 400, "wide"), (2, 400, 1000, "tall"),
        ]
        for c in cases {
            let shown = try placed(white(c.width, c.height), scale: c.scale)
            let out = try await cut(shown, shown.rect, marks(on: shown), c.label)
            XCTAssertEqual(out.width, c.width, c.label)
            let perPoint = shown.pixelsPerPoint
            let column = inkColumn(out, x: out.width / 2)
            let upper = Array(column[0..<(column.count * 2 / 5)])
            let thickness = upper.reduce(0, +)
            XCTAssertEqual(thickness, 3 * Double(perPoint), accuracy: max(0.4, 0.03 * Double(perPoint)),
                           "\(c.label): a 3-point stroke is \(thickness) pixels of the picture, not \(3 * perPoint)")
            let centre = zip(upper.indices, upper).reduce(0.0) { $0 + Double($1.0) * $1.1 } / thickness + 0.5
            XCTAssertEqual(centre, 0.2 * Double(c.height), accuracy: max(1.0, 0.012 * Double(c.height)),
                           "\(c.label): the top edge was drawn 20 % down and is at \(centre / Double(c.height)) of the picture")
            let lower = Array(column[(column.count / 2)...])
            let lowerThickness = lower.reduce(0, +)
            let lowerCentre = zip(lower.indices, lower).reduce(0.0) { $0 + Double($1.0) * $1.1 } / lowerThickness + Double(column.count / 2) + 0.5
            XCTAssertEqual(lowerCentre, 0.6 * Double(c.height), accuracy: max(1.0, 0.012 * Double(c.height)), "\(c.label): the bottom edge")
        }
    }

    /// Inside the rectangle and outside it the picture is as it was: a mark changes its own pixels and no others.
    func testThePicturesOwnPixelsAreUntouchedAwayFromTheMark() async throws {
        let shown = try placed(split(400, 240), scale: 2)
        let out = try await cut(shown, shown.rect, marks(on: shown))
        for (x, y) in [(5, 5), (5, 235), (150, 120), (395, 5), (395, 235)] {
            let want = x < 200 ? (UInt8(255), UInt8(0), UInt8(0)) : (0, 0, 255)
            let got = pixel(out, x, y)
            XCTAssertTrue(got == want, "pixel (\(x), \(y)) is \(got), the picture's was \(want)")
        }
    }

    // MARK: The marks at the four edges of a picture reduced to fit

    /// The share of each pixel in row `y` of the picture, left to right, that is the red ink on white.
    private func inkRow(_ image: CGImage, y: Int) -> [Double] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let inkGreen = Double(AnnotationColor.red.cgColor.components![1]) * 255
        return (0..<image.width).map { column in (255 - Double(bytes[y * image.width * 4 + column * 4 + 1])) / (255 - inkGreen) }
    }

    /// Centre of the ink in `share[range]`, in pixels from the start of `share`, or nil when there is none.
    private func centre(_ share: [Double], _ range: Range<Int>) -> Double? {
        let mass = range.reduce(0.0) { $0 + share[$1] }
        guard mass > 0.5 else { return nil }
        return range.reduce(0.0) { $0 + Double($1) * share[$1] } / mass + 0.5
    }

    /// **The reduced picture's two ratios differ** (`PictureOnScreen.frame` rounds the side that does not decide, so that
    /// `pixelsPerPoint`, the larger, reaches the last row), and a layer is multiplied by that one number on both axes: a
    /// mark far from the origin is placed `distance × (pixelsPerPoint − own ratio of that side)` off the place it was
    /// drawn at, measured against where the same fraction of the picture is. Four edges of a rectangle are drawn at 10 % and
    /// 90 % of the picture's rectangle and the centre of their ink is read back out of the file; the shift is stated and
    /// must stay within one DISPLAY pixel, `pixelsPerPoint / scale` pixels of the picture, which is how far a mark can be
    /// meant to be from a pixel it sits on. A case whose stroke is too thick against the picture to be told from its
    /// edge is not measured, and the count of those that were is asserted.
    func testTheMarksAtTheFourEdgesLandWithinOneDisplayPixelOfWhereTheyWereDrawn() async throws {
        let cases: [(w: Int, h: Int, scale: CGFloat)] = [
            (4000, 2400, 2), (4001, 2399, 2), (3001, 1999, 2), (6000, 1500, 2), (5000, 3001, 1), (1500, 4000, 2),
            (900, 300, 1), (301, 900, 1), (4800, 4799, 3), (2881, 1801, 2), (7000, 2000, 2),
        ]
        var measured = 0, worst = 0.0, report: [String] = []
        for c in cases {
            let shown = try placed(white(c.w, c.h), scale: c.scale)
            let r = shown.rect
            let rectangle = Annotation(tool: .rectangle,
                                       start: CGPoint(x: r.minX + 0.1 * r.width, y: r.minY + 0.1 * r.height),
                                       end: CGPoint(x: r.minX + 0.9 * r.width, y: r.minY + 0.9 * r.height),
                                       style: AnnotationStyle(thickness: .thin))
            let out = try await cut(shown, r, [rectangle], "\(c.w)×\(c.h)")
            XCTAssertEqual(out.width, c.w)
            XCTAssertEqual(out.height, c.h)
            let ppp = Double(shown.pixelsPerPoint)
            let half = 0.75 * ppp
            let tolerance = ppp / Double(c.scale)
            // Drawn at 10 % and 90 % of the rectangle; the same fractions of the picture are where an ideal export puts them.
            for axis in ["vertical", "horizontal"] {
                let size = axis == "vertical" ? c.h : c.w
                guard half < 0.05 * Double(size) else { continue }
                let share = axis == "vertical" ? inkColumn(out, x: out.width / 2) : inkRow(out, y: out.height / 2)
                guard let low = centre(share, 0..<(size / 2)), let high = centre(share, (size / 2)..<size) else {
                    XCTFail("\(c.w)×\(c.h): no ink at an \(axis) edge"); continue
                }
                measured += 1
                for (found, fraction, name) in [(low, 0.1, "first"), (high, 0.9, "last")] {
                    let shift = found - fraction * Double(size)
                    worst = max(worst, abs(shift))
                    report.append("\(c.w)×\(c.h)@\(Int(c.scale)) \(axis) \(name): \(String(format: "%+.2f", shift)) px of \(tolerance.formatted(.number.precision(.fractionLength(2))))")
                    XCTAssertEqual(shift, 0, accuracy: tolerance + 1,
                                   "\(c.w)×\(c.h) at \(c.scale)×: the \(name) \(axis) edge is \(shift) picture pixels off the drawn place")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 14, "the control: too few edges were measurable\n\(report.joined(separator: "\n"))")
        print("MARK SHIFTS worst \(worst)\n" + report.joined(separator: "\n"))
    }

    /// A mark centred on the very edge of the picture's rectangle leaves ink in the last row and the last column of the file:
    /// the area reaches the picture's end, the marks do not stop short of it.
    func testAMarkOnTheLastDisplayPixelReachesTheLastRowAndColumnOfTheFile() async throws {
        for (w, h, scale) in [(4000, 2400, CGFloat(2)), (4001, 2399, 2), (900, 300, 1), (6000, 40, 2), (301, 900, 1)] {
            let shown = try placed(white(w, h), scale: scale)
            let r = shown.rect
            let bottom = Annotation(tool: .rectangle, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.maxY),
                                    style: AnnotationStyle(thickness: .thin))
            let out = try await cut(shown, r, [bottom], "\(w)×\(h)")
            XCTAssertEqual(out.height, h)
            let column = inkColumn(out, x: out.width / 2)
            XCTAssertGreaterThan(column[h - 1], 0.5, "\(w)×\(h) at \(scale)×: no ink in the last row")
            let right = Annotation(tool: .rectangle, start: CGPoint(x: r.maxX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY),
                                   style: AnnotationStyle(thickness: .thin))
            let across = try await cut(shown, r, [right], "\(w)×\(h)")
            let row = inkRow(across, y: across.height / 2)
            XCTAssertGreaterThan(row[w - 1], 0.5, "\(w)×\(h) at \(scale)×: no ink in the last column")
        }
    }

    /// **A thin picture keeps its marks where they were drawn on the axis that is long.** `pixelsPerPoint` is one number, the
    /// larger ratio, and `frame` rounds the side that does not decide the reduction to a whole pixel of the display, down
    /// for the width of a tall picture: 49 × 3000 at 2× is 1.96 pixels wide and is made 1, so the width's ratio is 98 where the
    /// height's is 50, and 2001 × 5003 loses one pixel of 47.99. A mark moved by one number on both axes would land at 98 % of
    /// the file's height with a line drawn across the middle, and off the file with one at the bottom edge; the export moves
    /// each axis by its own ratio (`CaptureSession.annotated(_:local:layers:)`). The line is drawn across the middle of
    /// the picture's rectangle; it must be within one display pixel of the middle of the file, and the line along the bottom
    /// edge must leave ink in the file's last row.
    func testAThinTallPictureKeepsItsMarksWhereTheyWereDrawn() async throws {
        for (w, h, scale) in [(2001, 5003, CGFloat(2)), (49, 3000, 2), (28, 3000, 2), (12, 250, 2)] {
            let shown = try placed(white(w, h), scale: scale)
            let r = shown.rect
            let middle = Annotation(tool: .rectangle, start: CGPoint(x: r.minX, y: r.midY), end: CGPoint(x: r.maxX, y: r.midY),
                                    style: AnnotationStyle(thickness: .thin))
            let out = try await cut(shown, r, [middle], "\(w)×\(h)")
            XCTAssertEqual(out.height, h)
            let column = inkColumn(out, x: out.width / 2)
            let tolerance = Double(shown.pixelsPerPoint) / Double(scale)
            guard let found = centre(column, 0..<h) else { XCTFail("\(w)×\(h) at \(scale)×: the middle line is not in the file"); continue }
            XCTAssertEqual(found, Double(h) / 2, accuracy: tolerance,
                           "\(w)×\(h) at \(scale)×: the middle line is at \(found / Double(h)) of the file's height, within \(tolerance) pixels wanted")
            let bottom = Annotation(tool: .rectangle, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.maxY),
                                    style: AnnotationStyle(thickness: .thin))
            let edge = inkColumn(try await cut(shown, r, [bottom], "\(w)×\(h)"), x: out.width / 2)
            XCTAssertGreaterThan(edge[h - 1], 0.5, "\(w)×\(h) at \(scale)×: no ink in the last row from a line at the bottom edge")
        }
    }

    // MARK: The area

    func testAnAreaLargerThanThePictureExportsThePictureAndNoMoreAndOffItNothing() async throws {
        let shown = try placed(white(400, 240), scale: 2)
        // The whole display: the picture is all there is of it.
        let whole = try await cut(shown, CGRect(x: 0, y: 0, width: 100, height: 60), [])
        XCTAssertEqual(whole.width, 400)
        XCTAssertEqual(whole.height, 240)
        // Far outside the display, and a rectangle with no area on it.
        let away = await session().annotated(shown, local: CGRect(x: 5000, y: 5000, width: 10, height: 10), layers: [])
        XCTAssertNil(away)
        // A picture smaller than the display, the whole display as the area: the ground round it is not in the file.
        let small = try placed(white(80, 40), scale: 2)
        let ground = await session().annotated(small, local: CGRect(x: 0, y: 0, width: 100, height: 60), layers: [])
        XCTAssertEqual(ground?.width, 80, "the display's ground is in the file")
        XCTAssertEqual(ground?.height, 40)
    }

    /// A narrowed area is a crop of the picture at its own resolution: a half of it is half the pixels.
    func testANarrowedAreaIsACropAtThePicturesOwnResolution() async throws {
        let shown = try placed(split(400, 240), scale: 2)
        let left = CGRect(x: shown.rect.minX, y: shown.rect.minY, width: shown.rect.width / 2, height: shown.rect.height)
        let half = try await cut(shown, left, [])
        XCTAssertEqual(half.width, 200)
        XCTAssertEqual(half.height, 240)
        XCTAssertTrue(pixel(half, 199, 10) == (255, 0, 0), "the left half of the picture holds the right half's pixels")
        let right = CGRect(x: shown.rect.midX, y: shown.rect.minY, width: shown.rect.width / 2, height: shown.rect.height)
        let other = try await cut(shown, right, marks(on: shown))
        XCTAssertEqual(other.width, 200)
        XCTAssertTrue(pixel(other, 100, 200) == (0, 0, 255))
    }

    // MARK: Where the picture stands

    func testThePictureStandsInTheMiddleOfItsDisplayOnWholePixels() throws {
        let shown = try placed(solid(80, 40, 0, 0, 1), scale: 2)
        XCTAssertEqual(shown.rect, CGRect(x: 30, y: 20, width: 40, height: 20), "80×40 pixels at 2× in a 100×60-point display")
        XCTAssertEqual(shown.pixelsPerPoint, 2)
        let composed = try XCTUnwrap(shown.freeze.frames.first?.image)
        XCTAssertEqual(composed.width, 200)
        XCTAssertEqual(composed.height, 120)
        XCTAssertTrue(pixel(composed, 2, 2) == (255, 0, 0), "a corner is the ground")
        XCTAssertTrue(pixel(composed, 100, 60) == (0, 0, 255), "the middle is the picture")
        XCTAssertTrue(pixel(composed, 59, 60) == (255, 0, 0), "one pixel left of the picture is the ground")
        XCTAssertTrue(pixel(composed, 60, 60) == (0, 0, 255), "the picture's first column")
        XCTAssertTrue(pixel(composed, 139, 60) == (0, 0, 255), "the picture's last column")
        XCTAssertTrue(pixel(composed, 140, 60) == (255, 0, 0))
    }

    func testAPictureTwiceTheDisplayIsReducedToFitAndKeepsItsProportions() throws {
        let shown = try placed(solid(800, 400, 0, 0, 1), scale: 2)
        XCTAssertEqual(shown.rect, CGRect(x: 0, y: 5, width: 100, height: 50), "400 pixels wide at 4 pixels to a point would be 200 points")
        XCTAssertEqual(shown.pixelsPerPoint, 8)
        XCTAssertEqual(shown.picture.width, 800)
        let tall = try placed(solid(100, 600, 0, 0, 1), scale: 2)
        XCTAssertEqual(tall.rect.height, 60)
        XCTAssertEqual(tall.rect.width, 10, accuracy: 0.5)
        XCTAssertEqual(tall.rect.midX, 50, accuracy: 0.5)
    }

    func testTheFrameOfANonPictureIsNil() {
        let display = CGSize(width: 200, height: 120)
        for size in [CGSize(width: 0, height: 10), CGSize(width: 10, height: 0), CGSize(width: -5, height: 10),
                     CGSize(width: CGFloat.nan, height: 10), CGSize(width: 10, height: CGFloat.infinity), CGSize(width: 0.5, height: 0.5)] {
            XCTAssertNil(PictureOnScreen.frame(pixels: size, on: display, scale: 2), "\(size)")
        }
        for scale in [CGFloat(0), CGFloat(-1), CGFloat.nan, CGFloat.infinity] {
            XCTAssertNil(PictureOnScreen.frame(pixels: CGSize(width: 10, height: 10), on: display, scale: scale), "scale \(scale)")
        }
        for onto in [CGSize(width: 0, height: 120), CGSize(width: 200, height: 0), CGSize(width: CGFloat.nan, height: 1)] {
            XCTAssertNil(PictureOnScreen.frame(pixels: CGSize(width: 10, height: 10), on: onto, scale: 2), "display \(onto)")
        }
    }

    /// A picture that is 1 pixel on a side, or a hair of a line, still opens, still fits and is still saved at its own size.
    func testAPictureOfOnePixelOrOfAHairlineOpensAndExportsAtItsOwnSize() async throws {
        for (width, height) in [(1, 1), (6000, 1), (10_000, 3)] {
            let shown = try placed(white(width, height), scale: 2)
            let r = shown.rect
            XCTAssertTrue(r.width > 0 && r.height > 0 && r.maxX <= 100.0001 && r.maxY <= 60.0001, "\(width)×\(height): \(r)")
            XCTAssertTrue(shown.pixelsPerPoint.isFinite && shown.pixelsPerPoint > 0)
            let out = try await cut(shown, r, marks(on: shown), "\(width)×\(height)")
            XCTAssertEqual(out.width, width)
            XCTAssertEqual(out.height, height)
        }
    }

    // MARK: The display it lands on

    func testThePictureLandsOnTheDisplayAskedForAndTheOthersAreLeftAsTheyWere() throws {
        let freeze = self.freeze(scale: 2, ids: [1, 2, 3])
        let picture = solid(80, 40, 0, 0, 1)
        let shown = try XCTUnwrap(PictureOnScreen.place(picture, over: freeze, on: DisplayID(2)))
        XCTAssertEqual(shown.display, DisplayID(2))
        for frame in shown.freeze.frames {
            let middle = pixel(frame.image, 100, 60)
            XCTAssertTrue(middle == (frame.id == DisplayID(2) ? (0, 0, 255) : (255, 0, 0)), "display \(frame.id): \(middle)")
        }
        XCTAssertEqual(shown.freeze.frames.map(\.id), freeze.frames.map(\.id), "a display went missing or moved")
        // A display that is not in the freeze: the first one takes it, and nothing is made up.
        let elsewhere = try XCTUnwrap(PictureOnScreen.place(picture, over: freeze, on: DisplayID(99)))
        XCTAssertEqual(elsewhere.display, DisplayID(1))
        let none = try XCTUnwrap(PictureOnScreen.place(picture, over: freeze, on: nil))
        XCTAssertEqual(none.display, DisplayID(1))
        XCTAssertTrue(shown.freeze.windows.isEmpty, "the windows of the old freeze were carried into an edit")
    }

    func testAFreezeWithNoDisplayPlacesNothing() throws {
        let nothing = Freeze(displays: [.gone(DisplayID(1))], windows: [])
        XCTAssertNil(PictureOnScreen.place(makeImage(width: 4, height: 4), over: nothing, on: nil))
        XCTAssertNil(PictureOnScreen.place(makeImage(width: 4, height: 4), over: Freeze(displays: [], windows: []), on: DisplayID(1)))
    }

    /// The opening asks for the freeze and answers a refusal when there is none: the grant, the display, the capture.
    func testTheOpeningOfAnEditRefusesWhatTheFreezeRefuses() async throws {
        let capture = FakeCapture()
        let session = CaptureSession(capture: capture, writer: FakeWriter(), trash: FakeTrash(folder: FakeWriter()), pasteboard: FakePasteboard(),
                                     preferences: FakePreferences(), shutter: FakeShutter(), textReader: FakeTextReader(), settings: { .defaults })
        let held = makeImage(width: 40, height: 30, blue: 255)
        capture.grant = .denied
        guard case .refused(.noPermission) = await session.openEdit(of: nil, held: held, on: nil) else { return XCTFail("opened without the grant") }
        XCTAssertEqual(capture.freezeCalls, 0, "a press without the grant froze the screen")
        capture.grant = .granted
        capture.outcome = .failed
        guard case .refused(.captureFailed) = await session.openEdit(of: nil, held: held, on: nil) else { return XCTFail("opened on a failed capture") }
        capture.outcome = .denied
        guard case .refused(.noPermission) = await session.openEdit(of: nil, held: held, on: nil) else { return XCTFail("opened on a withdrawn grant") }
        capture.outcome = .frozen(Freeze(displays: [.gone(DisplayID(1))], windows: []))
        guard case .refused(.captureFailed) = await session.openEdit(of: nil, held: held, on: nil) else { return XCTFail("opened with no display") }
    }
}
