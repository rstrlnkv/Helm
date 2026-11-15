import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A mosaic in the file of an edited picture is made of the picture's own pixels, wherever on it the blur stands.**
/// `CaptureSession.annotated(_:local:layers:)` draws the layers over a cut and hands `draw` the *whole picture* as `display`:
/// a blur's blocks are cut out of it by pixel (`Pixelate`), and a picture that is not the whole one
/// (a half of it, the cut itself) has no pixels under a layer in the other part, where the mosaic is skipped.
///
/// Measured off the file, on a picture of a gradient (a mosaic differs from it): the pixels under a
/// blur in the lower right of the picture are not the picture's own; the pixels
/// away from the blur are. Total failure of the subject prints a file equal to the picture under the layer.
///
/// Mutant, red here: `annotated` hands `draw` the cut as `display` (red in the case of a part of the picture).
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

    func testABlurInTheLowerRightIsMadeOfThePicturesPixels() throws {
        for (w, h) in [(400, 300), (1200, 700)] {
            let picture = gradient(w, h)
            let shown = try placed(picture)
            let r = shown.rect
            let source = rgbaBytes(picture)
            // The pixels of a rectangle of the display's points on the picture.
            func pixels(_ rect: CGRect) -> CGRect {
                CGRect(x: ((rect.minX - r.minX) / r.width * CGFloat(w)).rounded(), y: ((rect.minY - r.minY) / r.height * CGFloat(h)).rounded(),
                       width: (rect.width / r.width * CGFloat(w)).rounded(), height: (rect.height / r.height * CGFloat(h)).rounded())
            }
            let box = CGRect(x: r.minX + 0.55 * r.width, y: r.minY + 0.55 * r.height, width: 0.3 * r.width, height: 0.3 * r.height)
            let layers: [(String, Annotation, CGRect)] = [
                ("blur", Annotation(tool: .blur, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY)), pixels(box)),
            ]
            for (name, layer, region) in layers {
                XCTAssertTrue(layer.isUsable, "the control: the \(name) is usable")
                let rig = Rig(home: scratchDirectory("shots-export-pixels"))
                let out = try XCTUnwrap(exported(rig.session, shown, local: r, layer: layer), "\(w)×\(h) \(name)")
                XCTAssertEqual(out.width, w)
                XCTAssertEqual(out.height, h)
                let file = rgbaBytes(out)
                XCTAssertGreaterThan(region.width * region.height, 400, "the control: the region has pixels")
                let under = differing(file, source, width: w, in: region)
                XCTAssertGreaterThan(under, 0.5, "\(w)×\(h): the pixels under the \(name) are the picture's own (\(under)): it was not drawn from the picture")
                let away = differing(file, source, width: w, in: CGRect(x: 0, y: 0, width: Double(w) * 0.4, height: Double(h) * 0.4))
                XCTAssertEqual(away, 0, "\(w)×\(h): the \(name) changed pixels far from itself")
            }
        }
    }

    /// The same, with the area a part of the picture: the blur is cut from the whole picture, so its pixels are the
    /// picture's own where the cut has them, and a mosaic made from the cut alone would find no pixel under it.
    func testABlurInAPartOfThePictureIsMadeOfThePicturesPixels() throws {
        let (w, h) = (1200, 700)
        let picture = gradient(w, h)
        let shown = try placed(picture)
        let r = shown.rect
        let part = CGRect(x: r.minX + 0.5 * r.width, y: r.minY + 0.5 * r.height, width: 0.5 * r.width, height: 0.5 * r.height)
        let box = CGRect(x: r.minX + 0.6 * r.width, y: r.minY + 0.6 * r.height, width: 0.3 * r.width, height: 0.3 * r.height)
        let layer = Annotation(tool: .blur, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))
        XCTAssertTrue(layer.isUsable, "the control: the blur is usable")
        let rig = Rig(home: scratchDirectory("shots-export-part"))
        let out = try XCTUnwrap(exported(rig.session, shown, local: part, layer: layer))
        let (offsetX, offsetY) = (w / 2, h / 2)
        XCTAssertEqual(out.width, w - offsetX)
        XCTAssertEqual(out.height, h - offsetY)
        let file = rgbaBytes(out), source = rgbaBytes(picture)
        // The box in the cut's own pixels: 0.6 to 0.9 of the picture is 0.2 to 0.8 of the half that is cut.
        let region = CGRect(x: 0.2 * Double(out.width), y: 0.2 * Double(out.height),
                            width: 0.6 * Double(out.width), height: 0.6 * Double(out.height)).integral
        var different = 0, total = 0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let i = (y * out.width + x) * 4, j = ((y + offsetY) * w + x + offsetX) * 4
                total += 1
                if file[i] != source[j] || file[i + 1] != source[j + 1] || file[i + 2] != source[j + 2] { different += 1 }
            }
        }
        XCTAssertGreaterThan(Double(different) / Double(total), 0.5, "the pixels under the blur are the picture's own: it was not drawn from the picture")
    }

    /// A lens shows the picture twice as large, so under it a gradient is not its own pixels; far from it the file is the picture.
    func testAMagnifierInTheFileShowsThePictureLargerAndTouchesNothingFarFromIt() throws {
        let (w, h) = (1200, 700)
        let picture = gradient(w, h)
        let shown = try placed(picture)
        let r = shown.rect
        let side = 0.3 * r.height
        let box = CGRect(x: r.minX + 0.55 * r.width, y: r.minY + 0.5 * r.height, width: side, height: side)
        let layer = Annotation(tool: .magnifier, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))
        XCTAssertTrue(layer.isUsable, "the control: the magnifier is usable")
        let rig = Rig(home: scratchDirectory("shots-export-lens"))
        let out = try XCTUnwrap(exported(rig.session, shown, local: r, layer: layer))
        let file = rgbaBytes(out), source = rgbaBytes(picture)
        let k = CGFloat(w) / r.width
        let inner = CGRect(x: (box.midX - r.minX) * k - side * k * 0.25, y: (box.midY - r.minY) * k - side * k * 0.25,
                           width: side * k * 0.5, height: side * k * 0.5).integral
        XCTAssertGreaterThan(inner.width * inner.height, 400, "the control: the region has pixels")
        let under = differing(file, source, width: w, in: inner)
        XCTAssertGreaterThan(under, 0.5, "the pixels in the lens are the picture's own (\(under)): the lens was not drawn")
        let away = differing(file, source, width: w, in: CGRect(x: 0, y: 0, width: Double(w) * 0.4, height: Double(h) * 0.4))
        XCTAssertEqual(away, 0, "the lens changed pixels far from itself")
    }

    /// A spotlight is a hole in one dim: under its box the file is the picture; away from it every pixel is darker.
    func testASpotlightInTheFileDimsThePictureAwayFromItAndLeavesItsInsideAlone() throws {
        let (w, h) = (1200, 700)
        let picture = gradient(w, h)
        let shown = try placed(picture)
        let r = shown.rect
        let box = CGRect(x: r.minX + 0.55 * r.width, y: r.minY + 0.5 * r.height, width: 0.3 * r.width, height: 0.3 * r.height)
        let layer = Annotation(tool: .spotlight, start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY))
        XCTAssertTrue(layer.isUsable, "the control: the spotlight is usable")
        let rig = Rig(home: scratchDirectory("shots-export-spotlight"))
        let out = try XCTUnwrap(exported(rig.session, shown, local: r, layer: layer))
        let file = rgbaBytes(out), source = rgbaBytes(picture)
        let k = CGFloat(w) / r.width
        let inner = CGRect(x: (box.minX - r.minX) * k, y: (box.minY - r.minY) * k, width: box.width * k, height: box.height * k)
            .insetBy(dx: 50, dy: 50).integral
        XCTAssertGreaterThan(inner.width * inner.height, 400, "the control: the region has pixels")
        XCTAssertEqual(differing(file, source, width: w, in: inner), 0, "the spotlight dimmed its own inside")
        let away = CGRect(x: 0, y: 0, width: Double(w) * 0.4, height: Double(h) * 0.4)
        var darker = 0, total = 0
        for y in Int(away.minY)..<Int(away.maxY) {
            for x in Int(away.minX)..<Int(away.maxX) {
                let i = (y * w + x) * 4
                guard Int(source[i]) + Int(source[i + 1]) + Int(source[i + 2]) > 30 else { continue }
                total += 1
                if Int(file[i]) + Int(file[i + 1]) + Int(file[i + 2]) < Int(source[i]) + Int(source[i + 1]) + Int(source[i + 2]) { darker += 1 }
            }
        }
        XCTAssertGreaterThan(total, 400, "the control: the region has lit pixels")
        XCTAssertEqual(darker, total, "the pixels away from the spotlight are not all dimmed (\(darker) of \(total)): the dim was not drawn")
    }
}
