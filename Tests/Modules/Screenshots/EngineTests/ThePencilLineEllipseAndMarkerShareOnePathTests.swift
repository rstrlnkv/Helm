import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **Every tool's shape is one `outline`, and ⇧ shapes it from the live flag.** Headless:
/// values in, geometry out.
final class ThePencilLineEllipseAndMarkerShareOnePathTests: XCTestCase {

    private let area = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let origin = CGPoint(x: 100, y: 100)

    private func angle(_ end: CGPoint) -> Double {
        Double(atan2(end.y - origin.y, end.x - origin.x)) * 180 / .pi
    }

    private func snapped(degrees: Double, length: CGFloat = 100) -> CGPoint {
        let radians = CGFloat(degrees * .pi / 180)
        return Annotation.constrained(.line, from: origin,
                                      to: CGPoint(x: origin.x + cos(radians) * length, y: origin.y + sin(radians) * length), shift: true)
    }

    func testShiftSnapsALineToMultiplesOfFortyFiveAndKeepsItsLength() {
        for (given, expected) in [(0.0, 0.0), (10, 0), (22.4, 0), (22.6, 45), (44, 45), (67.4, 45), (67.6, 90),
                                  (100, 90), (-30, -45), (170, 180), (-100, -90)] {
            let end = snapped(degrees: given)
            XCTAssertEqual(angle(end), expected, accuracy: 0.001, "\(given)° did not snap to \(expected)°")
            XCTAssertEqual(hypot(end.x - origin.x, end.y - origin.y), 100, accuracy: 0.001, "the snap changed the length")
        }
        // Exactly 22.5° is on the boundary: it goes to a neighbour, never between.
        let boundary = angle(snapped(degrees: 22.5))
        XCTAssertTrue(abs(boundary) < 0.001 || abs(boundary - 45) < 0.001, "22.5° landed at \(boundary)°")
        // The marker snaps the same way, without ⇧ nothing moves.
        let free = CGPoint(x: 230, y: 170)
        XCTAssertEqual(Annotation.constrained(.highlighter, from: origin, to: free, shift: false), free)
        XCTAssertEqual(angle(Annotation.constrained(.highlighter, from: origin, to: free, shift: true)), 45, accuracy: 0.001)
    }

    func testTheHighlighterIsFreehandAndShiftMakesItAStraightStrokeSnappedTo45() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.highlighter, at: origin)
        for step in 1...40 { editing.drag(to: CGPoint(x: 100 + CGFloat(step) * 4, y: 100 + 30 * sin(CGFloat(step) / 4)), shift: false) }
        let free = editing.draft!
        XCTAssertGreaterThan(free.points.count, 40, "the marker did not follow the hand")
        XCTAssertEqual(free.points.last, free.end)
        editing.drag(to: CGPoint(x: 260, y: 130), shift: true)
        let straight = editing.draft!
        XCTAssertEqual(straight.points, [origin, straight.end], "⇧ did not make one straight stroke")
        XCTAssertEqual(angle(straight.end), 0, accuracy: 0.001)
        editing.modifiersChanged(shift: false)
        XCTAssertEqual(editing.draft!.end, CGPoint(x: 260, y: 130), "⇧ released and the marker stayed straight")
        XCTAssertGreaterThan(editing.draft!.points.count, 40, "⇧ released and the trail was lost")
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
    }

    func testShiftMakesABoxASquareAndAnEllipseACircleInTheDirectionOfTheDrag() {
        for tool in [AnnotationTool.rectangle, .ellipse] {
            XCTAssertEqual(Annotation.constrained(tool, from: origin, to: CGPoint(x: 180, y: 220), shift: true),
                           CGPoint(x: 220, y: 220), "\(tool): the longer side did not win")
            XCTAssertEqual(Annotation.constrained(tool, from: origin, to: CGPoint(x: 40, y: 70), shift: true),
                           CGPoint(x: 40, y: 40), "\(tool): the signs were lost")
            XCTAssertEqual(Annotation.constrained(tool, from: origin, to: CGPoint(x: 180, y: 40), shift: true),
                           CGPoint(x: 180, y: 20), "\(tool): a mixed-sign drag was not squared")
            XCTAssertEqual(Annotation.constrained(tool, from: origin, to: CGPoint(x: 180, y: 220), shift: false),
                           CGPoint(x: 180, y: 220))
        }
        let circle = Annotation(tool: .ellipse, start: origin, end: CGPoint(x: 200, y: 200)).outline.boundingBoxOfPath
        XCTAssertEqual(circle, CGRect(x: 100, y: 100, width: 100, height: 100))
        XCTAssertFalse(Annotation(tool: .ellipse, start: origin, end: CGPoint(x: 200, y: 200)).outline.isEmpty)
    }

    func testAConstrainedShapeStaysInsideTheSelection() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.rectangle, at: CGPoint(x: 350, y: 250))
        editing.drag(to: CGPoint(x: 100, y: 240), shift: true)
        let end = editing.draft!.end
        XCTAssertTrue(area.contains(end), "the square left the selection at \(end)")
        XCTAssertEqual(abs(end.x - 350), abs(end.y - 250), accuracy: 0.001, "taken to the edge, it stopped being square")
    }

    func testShiftFollowsTheEventsAndNotThePress() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.line, at: origin)
        editing.drag(to: CGPoint(x: 200, y: 110), shift: true)
        XCTAssertEqual(editing.draft!.end.y, 100, accuracy: 0.001)
        editing.drag(to: CGPoint(x: 200, y: 110), shift: false)
        XCTAssertEqual(editing.draft!.end, CGPoint(x: 200, y: 110), "⇧ released and the line stayed snapped")
        editing.modifiersChanged(shift: true)
        XCTAssertEqual(editing.draft!.end.y, 100, accuracy: 0.001, "⇧ pressed with the pointer still did not reshape")
        editing.modifiersChanged(shift: false)
        XCTAssertEqual(editing.draft!.end, CGPoint(x: 200, y: 110))
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
        editing.modifiersChanged(shift: true)
        XCTAssertNil(editing.draft, "a flags change with no stroke began one")
    }

    func testThePencilIsSmoothedThroughItsPointsAndEndsOnTheLast() {
        let corner = Annotation(tool: .pencil, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 20, y: 20),
                                points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 20)])
        var curves = 0, last = CGPoint.zero
        corner.outline.applyWithBlock { element in
            let e = element.pointee
            if e.type == .addQuadCurveToPoint { curves += 1 }
            if e.type == .addLineToPoint { last = e.points[0] }
        }
        XCTAssertEqual(curves, 1, "the corner was not rounded by a curve")
        XCTAssertEqual(last, CGPoint(x: 20, y: 20))
        XCTAssertTrue(corner.isUsable)
        XCTAssertFalse(Annotation(tool: .pencil, start: origin, end: origin, points: [origin]).isUsable, "a click became a pencil stroke")
        XCTAssertFalse(Annotation(tool: .pencil, start: origin, end: origin, points: [origin, CGPoint(x: CGFloat.nan, y: 1)]).isUsable)
    }

    func testAPencilDragOfAnyLengthKeepsABoundedListAndItsTip() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 50_000, height: 300))
        editing.begin(.pencil, at: .zero)
        for index in 1...20_000 {
            editing.drag(to: CGPoint(x: CGFloat(index) * 3, y: CGFloat(index % 50)), shift: true)
            XCTAssertLessThanOrEqual(editing.draft!.points.count, Annotation.maxPoints)
        }
        XCTAssertGreaterThan(editing.draft!.points.count, 100, "thinning left almost nothing of the stroke")
        XCTAssertEqual(editing.draft!.points.last, CGPoint(x: 50_000, y: 0), "the tip is not the pointer, taken to the edge")
        // A pointer that is not a number adds nothing.
        let before = editing.draft!.points.count
        editing.drag(to: CGPoint(x: CGFloat.nan, y: 1), shift: false)
        XCTAssertEqual(editing.draft!.points.count, before)
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
    }

    func testAZeroSizeLineEllipseMarkerOrPencilNeverBecomesALayer() {
        for tool in [AnnotationTool.line, .ellipse, .highlighter, .pencil] {
            var editing = AnnotationEditing(bounds: area)
            editing.begin(tool, at: origin)
            XCTAssertNotNil(editing.draft)
            editing.drag(to: origin, shift: true)
            editing.end()
            XCTAssertTrue(editing.layers.isEmpty, "\(tool): a click became a layer")
        }
        var flat = AnnotationEditing(bounds: area)
        flat.begin(.ellipse, at: origin); flat.drag(to: CGPoint(x: 200, y: 100), shift: false); flat.end()
        XCTAssertTrue(flat.layers.isEmpty, "an ellipse with no height became a layer")
    }

    func testOnlyTheMarkerMultipliesAndItIsTheWidestStroke() {
        let styles = [AnnotationTool.rectangle, .ellipse, .line, .pencil, .highlighter].map {
            ($0, Annotation(tool: $0, start: .zero, end: CGPoint(x: 5, y: 5)).stroke!)
        }
        XCTAssertEqual(styles.filter(\.1.multiplies).map(\.0), [.highlighter])
        XCTAssertEqual(styles.map(\.1.width).max(), AnnotationThickness.thin.marker)
        XCTAssertNil(Annotation(tool: .arrow, start: .zero, end: CGPoint(x: 5, y: 5)).stroke)
    }
}
