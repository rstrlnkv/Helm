import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A mosaic and a lens in the file of an edited picture are made of the picture's own pixels, wherever on it they stand.**
/// `CaptureSession.annotated(_:local:layers:)` draws the layers over a cut and hands `draw` the *whole picture* as `display`:
/// a blur's blocks and a lens's contents are cut out of it by pixel (`Pixelate`, `Magnifier`), and a picture that is not the whole one
/// (a half of it, the cut itself) has no pixels under a layer in the other part, where the mosaic is skipped and the lens shows nothing.
///
/// Measured off the file, on a picture of a gradient (a mosaic and a magnified part both differ from it): the pixels under a
/// blur in the lower right of the picture are not the picture's own, and neither are those inside a lens there; the pixels
/// away from either layer are. Total failure of the subject prints a file equal to the picture under the layer.
final class TheEditExportBlursAndMagnifiesThePictureNotAPartOfItTests: XCTestCase {

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private func gradient(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * context.bytesPerRow + x * 4
                data[i] = UInt8(x % 251); data[i + 1] = UInt8((y * 3) % 253); data[i + 2] = UInt8((x + y * 7) % 241); data[i + 3] = 255
            }
        }
        return context.makeImage()!
    }

    private func placed(_ picture: CGImage) throws -> PictureOnScreen {
        let display = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60), scale: 2,
                                    image: gradient(200, 120))
        return try XCTUnwrap(PictureOnScreen.place(picture, over: Freeze(displays: [.image(display)], windows: []), on: nil))
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        out.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return out
    }

    /// The share of the pixels in `region` (picture pixels) that differ between two pictures of one size.
    private func differing(_ a: [UInt8], _ b: [UInt8], width: Int, in region: CGRect) -> Double {
        var different = 0, total = 0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let i = (y * width + x) * 4
                total += 1
                if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] { different += 1 }
            }
        }
        return total == 0 ? 0 : Double(different) / Double(total)
    }

    /// The export, awaited from the test's own thread. An assertion made after an `await` in an `async` test is recorded by XCTest
    /// only some of the time (measured: the same failing run recorded 2, 1 and 3 of its 4 failing assertions), so every measurement is
    /// taken here and every assertion is made on the thread the test started on.
    private func exported(_ session: CaptureSession, _ shown: PictureOnScreen, local: CGRect, layer: Annotation) -> CGImage? {
        final class Box: @unchecked Sendable {
            var result: CGImage?
            let session: CaptureSession, shown: PictureOnScreen, layer: Annotation
            init(_ session: CaptureSession, _ shown: PictureOnScreen, _ layer: Annotation) { self.session = session; self.shown = shown; self.layer = layer }
        }
        let box = Box(session, shown, layer)
        let done = expectation(description: "export")
        Task.detached { box.result = await box.session.annotated(box.shown, local: local, layers: [box.layer]); done.fulfill() }
        wait(for: [done], timeout: 60)
        return box.result
    }

    func testABlurAndALensInTheLowerRightAreMadeOfThePicturesPixels() throws {
        for (w, h) in [(400, 300), (1200, 700)] {
            let picture = gradient(w, h)
            let shown = try placed(picture)
            let r = shown.rect
            let source = bytes(picture)
            // The pixels of a rectangle of the display's points on the picture.
            func pixels(_ rect: CGRect) -> CGRect {
                CGRect(x: ((rect.minX - r.minX) / r.width * CGFloat(w)).rounded(), y: ((rect.minY - r.minY) / r.height * CGFloat(h)).rounded(),
                       width: (rect.width / r.width * CGFloat(w)).rounded(), height: (rect.height / r.height * CGFloat(h)).rounded())
            }
            let box = CGRect(x: r.minX + 0.55 * r.width, y: r.minY + 0.55 * r.height, width: 0.3 * r.width, height: 0.3 * r.height)
            let side = min(0.35 * r.width, 0.35 * r.height)
            let lensBox = CGRect(x: r.minX + 0.55 * r.width, y: r.minY + 0.55 * r.height, width: side, height: side)
            let layers: [(String, Annotation, CGRect)] = [
                ("blur", Annotation(tool: .blur, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY)), pixels(box)),
                ("lens", Annotation(tool: .magnifier, start: lensBox.origin, end: CGPoint(x: lensBox.maxX, y: lensBox.maxY)),
                 pixels(lensBox.insetBy(dx: side * 0.3, dy: side * 0.3))),   // the inside of the circle, away from its ring
            ]
            for (name, layer, region) in layers {
                XCTAssertTrue(layer.isUsable, "the control: the \(name) is usable")
                let rig = Rig(home: scratchDirectory("shots-export-pixels"))
                let out = try XCTUnwrap(exported(rig.session, shown, local: r, layer: layer), "\(w)×\(h) \(name)")
                XCTAssertEqual(out.width, w)
                XCTAssertEqual(out.height, h)
                let file = bytes(out)
                XCTAssertGreaterThan(region.width * region.height, 400, "the control: the region has pixels")
                let under = differing(file, source, width: w, in: region)
                XCTAssertGreaterThan(under, 0.5, "\(w)×\(h): the pixels under the \(name) are the picture's own (\(under)): it was not drawn from the picture")
                let away = differing(file, source, width: w, in: CGRect(x: 0, y: 0, width: Double(w) * 0.4, height: Double(h) * 0.4))
                XCTAssertEqual(away, 0, "\(w)×\(h): the \(name) changed pixels far from itself")
            }
        }
    }
}
