import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The lens magnifies the frozen picture and nothing drawn over it.** A picture with two things in it (a blue bar eight to fourteen
/// points right of the lens's centre, a two-point red square on the centre) is under a lens of 40 points' radius. Magnified twice about
/// the centre the bar stands at sixteen to twenty-eight and the square at two to two; so the file has blue where the picture is
/// grey and grey where the picture is blue, and that is read straight off its bytes. Then the layers a person puts under the lens (a
/// filled box, a blur, a spotlight, which dims all but its hole) change nothing inside the lens: its interior is byte for byte the
/// interior of the file made of the lens alone, while the control (the same layers with no lens) differs there. A layer **over** the
/// lens is drawn over it, and the file of a cut that begins elsewhere holds the same pixels of the same lens.
///
/// What it would print if it failed totally: a lens that magnifies what the export has drawn so far shows the red box and the mosaic
/// through itself, and its interior differs from the lone lens by tens of thousands of bytes; a lens that magnifies nothing shows
/// the bar where the picture has it (blue at 11, grey at 22).
final class TheMagnifierShowsTheFrameNotTheLayersTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let width: CGFloat = 240, height: CGFloat = 160
    private let centre = CGPoint(x: 120, y: 80)
    private let radius: CGFloat = 40

    private func picture(scale: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
        // Top-left points.
        context.translateBy(x: 0, y: height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(CGColor(srgbRed: 0, green: 0.2, blue: 1, alpha: 1))
        context.fill(CGRect(x: centre.x + 8, y: centre.y - 30, width: 6, height: 60))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: centre.x - 1, y: centre.y - 1, width: 2, height: 2))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    private let style = AnnotationStyle(color: nil, thickness: .medium, filled: false, opacity: 1)

    /// A layer of `tool` drawn from `from` to `to` through the editor's own entry.
    private func draw(_ editing: inout AnnotationEditing, _ tool: AnnotationTool, _ from: CGPoint, _ to: CGPoint, filled: Bool = false) {
        var look = style
        look.filled = filled
        XCTAssertTrue(editing.press(at: from, tool: tool, style: look))
        editing.drag(to: to, shift: false)
        editing.end()
    }

    private var lensFrom: CGPoint { CGPoint(x: centre.x - radius, y: centre.y - radius) }
    private var lensTo: CGPoint { CGPoint(x: centre.x + radius, y: centre.y + radius) }

    /// The layers under the lens: a filled box over the whole of its square, a blur over the whole of it, and a spotlight away from it.
    private func under(_ editing: inout AnnotationEditing) {
        draw(&editing, .rectangle, CGPoint(x: 70, y: 30), CGPoint(x: 170, y: 130), filled: true)
        draw(&editing, .blur, CGPoint(x: 75, y: 35), CGPoint(x: 165, y: 125))
        draw(&editing, .spotlight, CGPoint(x: 5, y: 5), CGPoint(x: 40, y: 30))
    }

    private struct Made {
        let file: [UInt8]
        let was: [UInt8]
        let scale: CGFloat
        let layers: [Annotation]
        var width: Int { Int(240 * scale) }
        /// The pixel of the file at display-local point (`x`, `y`): red, green, blue.
        func at(_ x: CGFloat, _ y: CGFloat) -> [Int] {
            let index = (Int(y * scale) * width + Int(x * scale)) * 4
            return [Int(file[index]), Int(file[index + 1]), Int(file[index + 2])]
        }
    }

    private func made(_ build: (inout AnnotationEditing) -> Void, scale: CGFloat) throws -> Made {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: width, height: height))
        build(&editing)
        let ground = try picture(scale: scale)
        let file = try XCTUnwrap(CaptureSession.draw(editing.layers, over: ground, at: .zero, scale: scale, display: ground))
        return Made(file: try bytes(file), was: try bytes(ground), scale: scale, layers: editing.layers)
    }

    /// How many bytes of the lens's interior (the disc less the ring and a pixel) differ between two files.
    private func interiorGap(_ a: Made, _ b: Made) -> Int {
        let scale = a.scale
        var gap = 0
        for y in 0..<Int(height * scale) {
            for x in 0..<Int(width * scale) {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                guard hypot(point.x - centre.x, point.y - centre.y) < radius - 4 else { continue }
                let index = (y * a.width + x) * 4
                for channel in 0..<3 where a.file[index + channel] != b.file[index + channel] { gap += 1 }
            }
        }
        return gap
    }

    func testTheLensMagnifiesThePictureTwiceAboutItsCentre() throws {
        for scale in [CGFloat(1), 2] {
            let lens = try made({ draw(&$0, .magnifier, lensFrom, lensTo) }, scale: scale)
            let name = "\(Int(scale))x"
            XCTAssertEqual(lens.layers.count, 1, name)
            // The bar is where it is magnified to (sixteen to twenty-eight points right of the centre) and no longer where the picture has it.
            let magnified = lens.at(centre.x + 22, centre.y), where_ = lens.at(centre.x + 11, centre.y)
            XCTAssertGreaterThan(magnified[2] - magnified[0], 100, "\(name): no blue at 22 points right of the centre: \(magnified)")
            XCTAssertLessThan(abs(where_[0] - where_[2]), 12, "\(name): the bar is still where the picture has it, 11 right of the centre: \(where_)")
            // The red square: two points wide, magnified to four.
            let square = lens.at(centre.x + 1.5, centre.y), beyond = lens.at(centre.x + 3.5, centre.y)
            XCTAssertGreaterThan(square[0] - square[2], 150, "\(name): the centre's square did not grow: \(square)")
            XCTAssertLessThan(abs(beyond[0] - beyond[2]), 12, "\(name): the square is more than twice its size: \(beyond)")
            // The ring is the ink's colour, inside the circle: red 0.92, 0.16, 0.14 at the left edge, and the picture again just outside.
            let ring = lens.at(centre.x - radius + 1.5, centre.y)
            XCTAssertEqual(ring[0], 235, accuracy: 8, "\(name): the ring is not the ink: \(ring)")
            XCTAssertEqual(ring[2], 36, accuracy: 8, "\(name): the ring is not the ink: \(ring)")
            let beside = lens.at(centre.x - radius - 3, centre.y)
            XCTAssertEqual(beside, [204, 204, 204], "\(name): ink outside the circle: \(beside)")
            // The square's corner, which the circle does not reach, is the picture's.
            let corner = lens.at(centre.x + radius - 1, centre.y - radius + 1)
            XCTAssertEqual(corner, [204, 204, 204], "\(name): the lens is a square: \(corner)")
        }
    }

    func testWhatIsUnderTheLensIsNotSeenThroughIt() throws {
        for scale in [CGFloat(1), 2] {
            let name = "\(Int(scale))x"
            let lone = try made({ draw(&$0, .magnifier, lensFrom, lensTo) }, scale: scale)
            let covered = try made({ under(&$0); draw(&$0, .magnifier, lensFrom, lensTo) }, scale: scale)
            let control = try made({ under(&$0) }, scale: scale)
            XCTAssertEqual(covered.layers.map(\.tool), [.rectangle, .blur, .spotlight, .magnifier], name)
            // The control: the layers alone do change the lens's interior, so equality below is not two untouched pictures.
            XCTAssertGreaterThan(interiorGap(control, lone), Int(300 * scale * scale), "\(name): control: the layers under the lens change nothing there")
            XCTAssertEqual(interiorGap(covered, lone), 0, "\(name): the lens shows what is drawn under it")
            let seen = covered.at(centre.x + 22, centre.y)
            XCTAssertGreaterThan(seen[2] - seen[0], 100, "\(name): no blue through the lens over the layers: \(seen)")
        }
    }

    func testALayerOverTheLensIsDrawnOverIt() throws {
        for scale in [CGFloat(1), 2] {
            let lone = try made({ draw(&$0, .magnifier, lensFrom, lensTo) }, scale: scale)
            let over = try made({
                draw(&$0, .magnifier, lensFrom, lensTo)
                draw(&$0, .rectangle, CGPoint(x: 100, y: 60), CGPoint(x: 120, y: 80), filled: true)
            }, scale: scale)
            XCTAssertEqual(over.layers.map(\.tool), [.magnifier, .rectangle])
            let inside = over.at(110, 70)
            XCTAssertGreaterThan(inside[0] - inside[2], 150, "\(Int(scale))x: the box over the lens is not drawn over it: \(inside)")
            // Away from the box the lens is the lens.
            XCTAssertEqual(over.at(centre.x + 22, centre.y), lone.at(centre.x + 22, centre.y))
        }
    }

    func testACutThatBeginsElsewhereHoldsTheSamePixelsOfTheSameLens() throws {
        for scale in [CGFloat(1), 2] {
            var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: width, height: height))
            // No spotlight here: its dim's antialiased hole edge differs by two levels between a cut and the whole (a spotlight's own matter, not the lens's).
            draw(&editing, .rectangle, CGPoint(x: 70, y: 30), CGPoint(x: 170, y: 130), filled: true)
            draw(&editing, .blur, CGPoint(x: 75, y: 35), CGPoint(x: 165, y: 125))
            draw(&editing, .magnifier, lensFrom, lensTo)
            let ground = try picture(scale: scale)
            let whole = try bytes(try XCTUnwrap(CaptureSession.draw(editing.layers, over: ground, at: .zero, scale: scale, display: ground)))
            // A cut that begins at pixel (37, 11) and cuts the lens's own square through.
            let rect = CGRect(x: 37, y: 11, width: ground.width - 60, height: ground.height - 30)
            let cut = try XCTUnwrap(ground.cropping(to: rect))
            let part = try bytes(try XCTUnwrap(CaptureSession.draw(editing.layers, over: cut, at: rect.origin, scale: scale, display: ground)))
            var apart = 0
            for y in 0..<cut.height {
                for x in 0..<cut.width {
                    for channel in 0..<4 where part[(y * cut.width + x) * 4 + channel] != whole[((y + 11) * ground.width + x + 37) * 4 + channel] { apart += 1 }
                }
            }
            XCTAssertEqual(apart, 0, "\(Int(scale))x: a cut that begins elsewhere drew \(apart) bytes of the lens differently")
        }
    }
}
