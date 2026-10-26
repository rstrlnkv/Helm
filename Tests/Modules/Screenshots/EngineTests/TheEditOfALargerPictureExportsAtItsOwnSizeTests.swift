import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A picture the editor shows reduced is saved at its own size.** «Edit» lays a finished picture over a fresh freeze
/// (`PictureOnScreen`), one pixel of it to one pixel of the display while it fits and reduced to fit when it does not,
/// and the export draws over the picture itself. A save that wrote what the screen showed would replace a 4000-pixel
/// screenshot with a 1000-pixel one.
///
/// Everything is read back out of the rendered picture. Display 100×60 points, at the scale each case says.
///
/// Total failure of the subject prints: a file the size of the screen.
final class TheEditOfALargerPictureExportsAtItsOwnSizeTests: XCTestCase {

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

    /// A display of `points` (100×60 unless said): that one is smaller than the room `PictureOnScreen.margin` keeps clear.
    private func freeze(scale: CGFloat, ids: [UInt32] = [1], points: CGSize = CGSize(width: 100, height: 60)) -> Freeze {
        let width = Int(points.width * scale), height = Int(points.height * scale)
        return Freeze(displays: ids.enumerated().map { index, id in
            .image(FrozenDisplay(id: DisplayID(id), frame: CGRect(x: 1000 * CGFloat(index), y: 0, width: points.width, height: points.height), scale: scale,
                                 image: solid(width, height, 1, 0, 0)))
        }, windows: [])
    }

    private func white(_ width: Int, _ height: Int) -> CGImage { solid(width, height, 1, 1, 1) }

    private func session() -> CaptureSession { Rig(home: scratchDirectory("shots-larger")).session }

    private func placed(_ picture: CGImage, scale: CGFloat, points: CGSize = CGSize(width: 100, height: 60),
                        file: StaticString = #filePath, line: UInt = #line) throws -> PictureOnScreen {
        try XCTUnwrap(PictureOnScreen.place(picture, over: freeze(scale: scale, points: points), on: nil), "the picture was not placed", file: file, line: line)
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
    /// how many of them the export does not return at their own size. The arithmetic of `PictureOnScreen.frame` with no inset (the bare fit: `place` passes the margin)
    /// and of the cut, on no image. It stays here because what it guards is the cut's size, which does not depend on the inset.
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

    // MARK: The opening

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
