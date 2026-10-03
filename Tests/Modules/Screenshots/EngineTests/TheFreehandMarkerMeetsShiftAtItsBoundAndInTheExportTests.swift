import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The marker now that it is freehand:** ⇧ held in the middle of a stroke and let go again,
/// the trail at its point bound with ⇧ flipping, and the export of a stroke with points at 1× and 2×.
final class TheFreehandMarkerMeetsShiftAtItsBoundAndInTheExportTests: XCTestCase {

    private let area = CGRect(x: 0, y: 0, width: 400, height: 300)

    func testShiftHeldInTheMiddleOfAMarkerStrokeKeepsTheHandsPathForTheRelease() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.highlighter, at: CGPoint(x: 20, y: 100))
        for step in 1...10 { editing.drag(to: CGPoint(x: 20 + CGFloat(step) * 10, y: 100), shift: false) }
        let beforeShift = editing.draft!.points
        // ⇧ down, and the hand goes down and round while it is held.
        let held = (1...10).map { CGPoint(x: 120, y: 100 + CGFloat($0) * 10) }
        for point in held { editing.drag(to: point, shift: true) }
        XCTAssertEqual(editing.draft!.points.count, 2, "⇧ held: one straight stroke")
        XCTAssertEqual(editing.draft!.points.first, CGPoint(x: 20, y: 100))
        editing.modifiersChanged(shift: false)
        let released = editing.draft!.points
        XCTAssertEqual(Array(released.prefix(beforeShift.count)), beforeShift, "the stroke before ⇧ changed")
        for point in held { XCTAssertTrue(released.contains(point), "the hand's point \(point) from the ⇧ period is not in the stroke") }
        XCTAssertEqual(released.last, CGPoint(x: 120, y: 200))
        // And the whole thing again: ⇧ down at the end of the stroke ends a straight layer.
        editing.modifiersChanged(shift: true)
        editing.end()
        XCTAssertEqual(editing.layers.last!.points.count, 2)
        XCTAssertTrue(editing.layers.last!.isUsable)
    }

    func testTheMarkersTrailAtItsBoundStaysBoundedWhileShiftFlips() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 20_000, height: 100))
        editing.begin(.highlighter, at: CGPoint(x: 0, y: 50))
        for index in 1...5000 {
            editing.drag(to: CGPoint(x: Double(index) * 3, y: 50 + Double(index % 5)), shift: index % 7 == 0)
            if index % 3 == 0 { editing.modifiersChanged(shift: index % 2 == 0) }
            XCTAssertLessThanOrEqual(editing.draft!.points.count, Annotation.maxPoints)
        }
        editing.modifiersChanged(shift: false)
        let points = editing.draft!.points
        XCTAssertGreaterThan(points.count, 100)
        XCTAssertLessThanOrEqual(points.count, Annotation.maxPoints)
        XCTAssertEqual(points.first, CGPoint(x: 0, y: 50))
        XCTAssertEqual(points.last, CGPoint(x: 15_000, y: 50))
        XCTAssertEqual(points.map(\.x), points.map(\.x).sorted())
    }

    private func freeze(scale: CGFloat) -> Freeze {
        let width = Int(100 * scale), height = Int(60 * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - height / 6, width: width, height: height / 6))   // black band at the top edge; the context is bottom-up
        return Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                                                      scale: scale, image: context.makeImage()!))], windows: [])
    }

    private func rows(_ image: CGImage, x: Int) -> [[Int]] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<image.height).map { row in (0..<3).map { Int(bytes[row * image.width * 4 + x * 4 + $0]) } }
    }

    func testAFreehandMarkerIsMultipliedAndSixPointsTimesTheScaleWideAtItsThinStep() async throws {
        // A straight run of four points along y = 40 from x = 10 to 70: a column at x = 30 crosses it once.
        let points = [CGPoint(x: 10, y: 40), CGPoint(x: 30, y: 40), CGPoint(x: 50, y: 40), CGPoint(x: 70, y: 40)]
        let layer = Annotation(tool: .highlighter, start: points[0], end: points[3], points: points,
                               style: AnnotationStyle(thickness: .thin))
        for scale in [CGFloat(1), 2] {
            let rig = Rig(home: scratchDirectory("shots-freehand-marker-\(Int(scale))"))
            let drawn = await rig.session.annotated(freeze(scale: scale), display: DisplayID(1),
                                                    local: CGRect(x: 0, y: 0, width: 100, height: 60), layers: [layer])
            let out = try XCTUnwrap(drawn)
            let column = rows(out, x: Int(30 * scale))
            let tinted = column.filter { $0 != [255, 255, 255] && $0 != [0, 0, 0] }.count
            XCTAssertEqual(Double(tinted), Double(6 * scale), accuracy: Double(scale) * 2 + 1, "\(scale)x: marker width in pixels")
            // Multiply: over white the blue falls to the tint's, a black pixel would stay black.
            XCTAssertEqual(column[Int(40 * scale)][2], 117, accuracy: 6, "\(scale)x: over white")
            XCTAssertEqual(rows(out, x: Int(30 * scale))[0], [0, 0, 0], "\(scale)x: the black band outside the stroke is untouched")
        }
        // A freehand stroke over a black band must stay black: the multiply, not a plain paint.
        let band = Annotation(tool: .highlighter, start: CGPoint(x: 10, y: 5), end: CGPoint(x: 70, y: 5),
                              points: [CGPoint(x: 10, y: 5), CGPoint(x: 40, y: 5), CGPoint(x: 70, y: 5)])
        let rig = Rig(home: scratchDirectory("shots-freehand-marker-black"))
        let drawn = await rig.session.annotated(freeze(scale: 2), display: DisplayID(1),
                                                local: CGRect(x: 0, y: 0, width: 100, height: 60), layers: [band])
        XCTAssertEqual(rows(try XCTUnwrap(drawn), x: 80)[10], [0, 0, 0], "a marker over black must stay black")
    }

    /// A freehand marker turns corners: a mitre spikes out of every sharp turn of the stroke,
    /// so its join is round in the value the export and the overlay both read.
    func testTheMarkerStrokeJoinsRound() throws {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 12), CGPoint(x: 12, y: 14)]
        let marker = Annotation(tool: .highlighter, start: points[0], end: points[2], points: points)
        XCTAssertEqual(try XCTUnwrap(marker.stroke).join, .round, "the marker's corners are not round")
    }
}
