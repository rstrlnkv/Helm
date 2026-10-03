import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A layer lands in the file on the pixels it was drawn over, whatever the cut.**
/// The neighbouring file rounds a cut outward on one axis of one display; these
/// round both axes, hang the selection off the frame's edge, put a layer outside
/// the selection, and edit the second display of a freeze whose displays differ in
/// scale — each a place where the offset or the scale could come from the wrong
/// source and still pass the single-display, whole-point case.
final class TheExportLandsOnThePixelsTheOverlayShowedTests: XCTestCase {

    private func white(_ id: UInt32, scale: CGFloat, origin: CGFloat = 0) -> DisplayShot {
        .image(FrozenDisplay(id: DisplayID(id), frame: CGRect(x: origin, y: 0, width: 100, height: 60), scale: scale,
                             image: makeImage(width: Int(100 * scale), height: Int(60 * scale),
                                              red: 255, green: 255, blue: 255)))
    }

    /// Ink share per pixel, row-major from the top: 0 is white, 1 the full ink.
    private func ink(_ image: CGImage) -> (width: Int, at: (Int, Int) -> Double) {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let inkGreen = Double(AnnotationColor.red.cgColor.components![1]) * 255
        let width = image.width
        let copy = Array(UnsafeBufferPointer(start: bytes, count: width * image.height * 4))
        return (width, { x, y in (255 - Double(copy[y * width * 4 + x * 4 + 1])) / (255 - inkGreen) })
    }

    /// The centre of the ink along a line of pixels, as a pixel coordinate.
    private func centre(_ values: [Double]) -> Double {
        let total = values.reduce(0, +)
        return zip(values.indices, values).reduce(0.0) { $0 + Double($1.0) * $1.1 } / total + 0.5
    }

    func testACutRoundedOutwardOnBothAxesKeepsTheLayerOnItsPixels() async throws {
        let rig = Rig(home: scratchDirectory("shots-export-both-axes"))
        let freeze = Freeze(displays: [white(1, scale: 2)], windows: [])
        // 10.25 × 2 = 20.5 → the cut starts at pixel 20; 10.75 × 2 = 21.5 → at row 21.
        let selection = CGRect(x: 10.25, y: 10.75, width: 60, height: 40)
        let layer = Annotation(tool: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 50, y: 40),
                               style: AnnotationStyle(thickness: .thin))
        let outDrawn = await rig.session.annotated(freeze, display: DisplayID(1), local: selection,
                                                            layers: [layer])
        let out = try XCTUnwrap(outDrawn)
        let (width, at) = ink(out)
        // The top edge is at 20 points = pixel 40 = row 40 − 21 = 19 of the cut, read at x = 35 points.
        let column = (0..<30).map { at(Int(35 * 2.0) - 20, $0) }
        XCTAssertEqual(column.reduce(0, +), 6, accuracy: 0.4, "the top edge is not 6 pixels thick in the cut")
        XCTAssertEqual(centre(column), 19, accuracy: 0.25, "the top edge is not on the row its point puts it")
        // The left edge is at 20 points = pixel 40 = column 20 of the cut, read at y = 30 points.
        let row = (0..<width).map { at($0, Int(30 * 2.0) - 21) }
        XCTAssertEqual(centre(Array(row[0..<40])), 20, accuracy: 0.25, "the left edge is not on the column its point puts it")
    }

    /// A selection that starts left of the frame is cut from pixel 0, and a layer is
    /// placed from that pixel — not from where the selection said it began.
    func testASelectionHangingOffTheFrameKeepsTheLayerOnItsPixels() async throws {
        let rig = Rig(home: scratchDirectory("shots-export-off-edge"))
        let freeze = Freeze(displays: [white(1, scale: 2)], windows: [])
        let selection = CGRect(x: -5, y: 0, width: 60, height: 40)
        let layer = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 40, y: 30))
        let outDrawn = await rig.session.annotated(freeze, display: DisplayID(1), local: selection,
                                                            layers: [layer])
        let out = try XCTUnwrap(outDrawn)
        XCTAssertEqual(out.width, 110, "the cut is not the part of the selection on the frame")
        let (_, at) = ink(out)
        let row = (0..<40).map { at($0, 40) }
        XCTAssertEqual(centre(row), 20, accuracy: 0.6, "the left edge moved by the part of the selection off the frame")
    }

    /// A layer wholly outside the selection draws nothing into the file; it does not
    /// wrap, shift in, or stain an edge.
    func testALayerOutsideTheSelectionLeavesTheCutUntouched() async throws {
        let rig = Rig(home: scratchDirectory("shots-export-outside"))
        let freeze = Freeze(displays: [white(1, scale: 2)], windows: [])
        let selection = CGRect(x: 10, y: 10, width: 30, height: 20)
        let inside = Annotation(tool: .rectangle, start: CGPoint(x: 15, y: 15), end: CGPoint(x: 30, y: 25))
        let outside = Annotation(tool: .arrow, start: CGPoint(x: 60, y: 45), end: CGPoint(x: 95, y: 55))
        // The control: the same cut with a layer inside it does carry ink.
        let markedDrawn = await rig.session.annotated(freeze, display: DisplayID(1), local: selection,
                                                               layers: [inside])
        let marked = try XCTUnwrap(markedDrawn)
        let (markedWidth, markedAt) = ink(marked)
        let markedInk = (0..<markedWidth).flatMap { x in (0..<marked.height).map { markedAt(x, $0) } }.reduce(0, +)
        XCTAssertGreaterThan(markedInk, 50, "a layer inside drew nothing, so the absence below says nothing")

        let outDrawn = await rig.session.annotated(freeze, display: DisplayID(1), local: selection,
                                                            layers: [outside])
        let out = try XCTUnwrap(outDrawn)
        let (width, at) = ink(out)
        let total = (0..<width).flatMap { x in (0..<out.height).map { at(x, $0) } }.reduce(0, +)
        XCTAssertEqual(total, 0, accuracy: 0.01, "a layer outside the selection left ink in the file")
    }

    /// The scale is the edited display's own. The freeze's first display is 2×, the
    /// edited one 1×, and the other way round: a stroke is 3 pixels on the 1× one and
    /// 6 on the 2× one, whichever comes first.
    func testTheScaleIsTheEditedDisplaysAndNotTheFirsts() async throws {
        for (firstScale, editedScale) in [(CGFloat(2), CGFloat(1)), (1, 2)] {
            let rig = Rig(home: scratchDirectory("shots-export-mixed-\(Int(firstScale))"))
            let freeze = Freeze(displays: [white(1, scale: firstScale), white(2, scale: editedScale, origin: 100)],
                                windows: [])
            let selection = CGRect(x: 0, y: 0, width: 60, height: 40)
            let layer = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 30),
                                   style: AnnotationStyle(thickness: .thin))
            let outDrawn = await rig.session.annotated(freeze, display: DisplayID(2), local: selection,
                                                                layers: [layer])
            let out = try XCTUnwrap(outDrawn)
            XCTAssertEqual(out.width, Int(60 * editedScale), "the cut is not the edited display's pixels")
            let (_, at) = ink(out)
            let column = (0..<Int(20 * editedScale)).map { at(Int(30 * editedScale), $0) }
            XCTAssertEqual(column.reduce(0, +), 3 * Double(editedScale), accuracy: 0.3,
                           "first \(firstScale)×, edited \(editedScale)×: the stroke took another display's scale")
            XCTAssertEqual(centre(column), 10 * Double(editedScale), accuracy: 0.6,
                           "first \(firstScale)×, edited \(editedScale)×: the stroke is off its point")
        }
    }
}
