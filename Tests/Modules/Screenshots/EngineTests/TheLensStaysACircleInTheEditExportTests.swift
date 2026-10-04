import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A circle drawn on the screen is a circle in the file of an edited picture, whatever the picture's two ratios are.**
/// `Annotation.mapped(_:)` takes a layer's two corners through a transform of two different factors on a thin or a wide
/// picture (the display rectangle is whole display pixels, the picture is not), so the square a lens
/// stands in becomes a rectangle and the circle drawn into it an ellipse. The magnifier is "always a circle"
/// (`AnnotationTool.magnifier`, `Annotation.constrained`), and its ring and its picture are drawn into `frame`.
///
/// Measured off the file: the ring's ink spans as many pixels across as down, and a lens the screen showed is in the file.
/// Total failure of the subject prints a lens that is wider than it is tall (or the reverse) by the ratio of the picture's
/// two axes, or no ink at all.
final class TheLensStaysACircleInTheEditExportTests: XCTestCase {

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private func solid(_ width: Int, _ height: Int, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: srgb, components: [r, g, b, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func placed(_ w: Int, _ h: Int, scale: CGFloat) throws -> PictureOnScreen {
        let display = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60), scale: scale,
                                    image: solid(Int(100 * scale), Int(60 * scale), 1, 0, 0))
        let freeze = Freeze(displays: [.image(display)], windows: [])
        return try XCTUnwrap(PictureOnScreen.place(solid(w, h, 1, 1, 1), over: freeze, on: nil), "\(w)×\(h) not placed")
    }

    /// The first and the last column and row holding ink (a pixel off white), as spans.
    private func spans(_ image: CGImage) -> (across: Int, down: Int)? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                guard min(bytes[i], bytes[i + 1], bytes[i + 2]) < 235 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : (maxX - minX + 1, maxY - minY + 1)
    }

    /// Pictures whose rectangle on the 100 × 60-point display is a narrow strip (the shorter side 9 to 16 points, whole display
    /// pixels at 1×, so the two ratios of the export differ by up to 5 %) and two that fit, as the controls.
    private static let pictures: [(w: Int, h: Int, scale: CGFloat, name: String)] = [
        (1050, 6000, 1, "a tall strip, 10.5 points wide"), (950, 6000, 1, "a tall strip, 9.5 points wide"),
        (6000, 570, 1, "a wide strip, 9.5 points high"), (6000, 950, 1, "a wide strip, 15.8 points high"),
        (1601, 959, 2, "larger than the display"), (100, 60, 1, "as large as the display"),
    ]

    /// A lens of the smallest size a drag keeps (8.2 points) and a larger one, on every picture: the file shows a lens (a layer
    /// that was usable on the screen is not dropped by the mapping) and the lens is as wide as it is tall.
    func testALensIsADrawnCircleInTheFileOnEveryPicture() async throws {
        var measured = 0
        for p in Self.pictures {
            let shown = try placed(p.w, p.h, scale: p.scale)
            let r = shown.rect
            for side in [CGFloat(8.2), 9] {
                guard min(r.width, r.height) >= side else { continue }
                let layer = Annotation(tool: .magnifier, start: CGPoint(x: r.midX - side / 2, y: r.midY - side / 2),
                                       end: CGPoint(x: r.midX + side / 2, y: r.midY + side / 2))
                XCTAssertTrue(layer.isUsable, "the control: a \(side)-point lens is a lens on the screen")
                let rig = Rig(home: scratchDirectory("shots-lens"))
                let exported = await rig.session.annotated(shown, local: shown.rect, layers: [layer])
                let out = try XCTUnwrap(exported, "\(p.name)")
                guard let ink = spans(out) else {
                    XCTFail("\(p.name), \(side)-point lens: nothing of it is in the \(out.width)×\(out.height) file; the screen showed it")
                    continue
                }
                measured += 1
                let tolerance = 2 + 0.005 * Double(max(ink.across, ink.down))
                XCTAssertEqual(Double(ink.across), Double(ink.down), accuracy: tolerance,
                               "\(p.name), \(side)-point lens: drawn a circle, the file has \(ink.across) pixels across and \(ink.down) down")
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 6, "the control: the lens was measured on the controls and on strips")
    }
}
