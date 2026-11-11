import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A blur box that clips to one pixel costs the person nothing but itself.** A box dragged to a sliver, or pushed
/// past the edge of the display until one pixel of it is left, has no block to average; `draw` returned nil for the whole
/// export and the shot was lost with every other mark in it. The box is drawn as what it can be (or skipped), and the
/// picture and the other layers come out.
///
/// Total failure of the subject prints: a nil for a picture the person drew a rectangle on, or a file in which the
/// rectangle is not there.
final class ABlurBoxOfOnePixelDoesNotCostTheWholeShotTests: XCTestCase {

    private func picture(width: Int = 80, height: Int = 50) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    private func blur(_ rect: CGRect) -> Annotation {
        Annotation(tool: .blur, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), style: AnnotationStyle())
    }

    private func rectangle() -> Annotation {
        Annotation(tool: .rectangle, start: CGPoint(x: 30, y: 15), end: CGPoint(x: 70, y: 40),
                   style: AnnotationStyle(color: nil, thickness: .thick, filled: true, opacity: 1))
    }

    /// The boxes that are one pixel after the display has clipped them: a box one point square, and a box pushed past
    /// two edges until the corner pixel is all of it that is left. (A box one pixel wide and taller has blocks to average:
    /// the control that the failure is the single pixel and not the edge.)
    private let slivers: [(String, CGRect)] = [
        ("one point square", CGRect(x: 10, y: 10, width: 1, height: 1)),
        ("the top-left corner pixel", CGRect(x: -20, y: -20, width: 21, height: 21)),
        ("the bottom-right corner pixel", CGRect(x: 79, y: 49, width: 30, height: 30)),
    ]

    func testABoxOneThinColumnWideStillBlursAsTheControl() throws {
        let source = try picture()
        XCTAssertNotNil(CaptureSession.draw([blur(CGRect(x: -20, y: 10, width: 21, height: 20))], over: source, at: .zero, scale: 1, display: source))
    }

    func testAShotWithOnlyAOnePixelBoxStillComesOutAsThePicture() throws {
        let source = try picture()
        for (name, box) in slivers {
            let out = CaptureSession.draw([blur(box)], over: source, at: .zero, scale: 1, display: source)
            XCTAssertNotNil(out, "\(name): a box of one pixel made the whole export nil, so no shot is taken")
        }
    }

    func testTheOtherMarksAreInTheFileWhenABoxOfOnePixelIsNextToThem() throws {
        let source = try picture()
        let alone = try XCTUnwrap(CaptureSession.draw([rectangle()], over: source, at: .zero, scale: 1, display: source),
                                  "the control: the rectangle alone draws")
        XCTAssertNotEqual(bytes(alone), bytes(source), "the control: the rectangle changes the picture")
        for (name, box) in slivers {
            let out = CaptureSession.draw([rectangle(), blur(box)], over: source, at: .zero, scale: 1, display: source)
            guard let out else { XCTFail("\(name): the rectangle was lost with the box of one pixel"); continue }
            // The middle of the filled rectangle, far from every sliver.
            let at = (27 * out.width + 50) * 4
            XCTAssertEqual(Array(bytes(out)[at..<(at + 4)]), Array(bytes(alone)[at..<(at + 4)]), "\(name): the rectangle is not drawn")
        }
    }

    /// Through the engine's own entry, the one the controller calls.
    func testTheEngineEntryAnswersAPictureForABoxOfOnePixel() async throws {
        let frame = FrozenDisplay(id: DisplayID(7), frame: CGRect(x: 0, y: 0, width: 80, height: 50), scale: 1, image: try picture())
        let freeze = Freeze(displays: [.image(frame)], windows: [])
        let session = Rig(home: scratchDirectory("blur-sliver")).session
        let image = await session.annotated(freeze, display: DisplayID(7), local: CGRect(x: 0, y: 0, width: 80, height: 50),
                                            layers: [blur(CGRect(x: 10, y: 10, width: 1, height: 1))])
        XCTAssertNotNil(image, "the engine answered nil for a picture whose only mark is a box of one pixel")
    }
}
