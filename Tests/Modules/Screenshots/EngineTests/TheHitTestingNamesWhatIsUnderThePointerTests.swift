import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **What a press lands on is a pure function of the layers and a point.** A stroke is hit by its
/// outline and a filled shape by its area, each with a few points of tolerance, the topmost first;
/// no window, no pointer, no clock.
final class TheHitTestingNamesWhatIsUnderThePointerTests: XCTestCase {

    private func shape(_ tool: AnnotationTool, _ from: CGPoint, _ to: CGPoint, filled: Bool = false,
                       thickness: AnnotationThickness = .thin, id: Int = 1) -> Annotation {
        Annotation(tool: tool, start: from, end: to, style: AnnotationStyle(thickness: thickness, filled: filled), id: id)
    }

    private func hits(_ annotation: Annotation, _ x: CGFloat, _ y: CGFloat) -> Bool {
        AnnotationHit.hits(annotation, at: CGPoint(x: x, y: y))
    }

    func testALineIsItsStrokeAndAFewPointsAroundIt() {
        let line = shape(.line, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100))
        XCTAssertTrue(hits(line, 200, 100), "the line's own pixel is not on it")
        // The thin stroke is 3 points: 1.5 each side, and the tolerance is 4 more.
        XCTAssertTrue(hits(line, 200, 105), "5 points off a 3-point line is inside the tolerance")
        XCTAssertFalse(hits(line, 200, 108), "8 points off is outside it")
        XCTAssertFalse(hits(line, 200, 92))
        XCTAssertFalse(hits(line, 50, 100), "the line was hit beyond its end")
        XCTAssertFalse(AnnotationHit.hits(line, at: CGPoint(x: 200, y: 103), tolerance: 0), "a tolerance of none still had one")
    }

    func testAnUnfilledBoxIsItsEdgeAndNotItsInside() {
        for tool in [AnnotationTool.rectangle, .ellipse] {
            let box = shape(tool, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
            XCTAssertTrue(hits(box, 200, 100), "\(tool): the top edge is not on it")
            XCTAssertTrue(hits(box, 200, 103), "\(tool): just inside the edge is the edge's tolerance")
            XCTAssertFalse(hits(box, 200, 150), "\(tool): the inside of an outline was a hit, so it swallows the picture's clicks")
            XCTAssertFalse(hits(box, 200, 60), "\(tool): above the box")
        }
    }

    func testAFilledBoxIsItsArea() {
        for tool in [AnnotationTool.rectangle, .ellipse] {
            let box = shape(tool, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200), filled: true)
            XCTAssertTrue(hits(box, 200, 150), "\(tool): the inside of a filled box is not on it")
            XCTAssertFalse(hits(box, 200, 220), "\(tool): below the box")
        }
        // The ellipse's corner is outside the ellipse, though inside its box.
        let oval = shape(.ellipse, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200), filled: true)
        XCTAssertFalse(hits(oval, 105, 105), "the box's corner was a hit on the oval")
    }

    func testAnArrowIsItsWholeBody() {
        let arrow = shape(.arrow, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), thickness: .thick)
        XCTAssertTrue(hits(arrow, 250, 100), "the head")
        XCTAssertTrue(hits(arrow, 150, 100), "the shaft")
        XCTAssertTrue(hits(arrow, 150, 103), "beside the tail, within the tolerance of a tail about 7 points wide")
        XCTAssertFalse(hits(arrow, 150, 120))
    }

    func testAFreehandStrokeIsItsPathAndTheMarkerIsItsWiderBand() {
        let points = (0...20).map { CGPoint(x: 100 + CGFloat($0) * 10, y: 100 + CGFloat($0 % 2) * 4) }
        let pencil = Annotation(tool: .pencil, start: points[0], end: points[20], points: points, id: 1)
        XCTAssertTrue(hits(pencil, 200, 102))
        XCTAssertFalse(hits(pencil, 200, 120))
        let marker = Annotation(tool: .highlighter, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 300, y: 100),
                                points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100)], id: 2)
        // 16 points wide: 8 each side and 4 of tolerance.
        XCTAssertTrue(hits(marker, 200, 111), "11 points off a 16-point marker is on it")
        XCTAssertFalse(hits(marker, 200, 113), "13 points off is not")
    }

    func testTheTopmostLayerWinsWhereTwoOverlapAndANonNumberHitsNothing() {
        let under = shape(.rectangle, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300), filled: true, id: 7)
        let over = shape(.rectangle, CGPoint(x: 200, y: 200), CGPoint(x: 400, y: 400), filled: true, id: 9)
        let point = CGPoint(x: 250, y: 250)
        XCTAssertEqual(AnnotationHit.topmost(in: [under, over], at: point), 9)
        XCTAssertEqual(AnnotationHit.topmost(in: [over, under], at: point), 7, "the order of the list is the order of the stack")
        XCTAssertEqual(AnnotationHit.topmost(in: [under, over], at: CGPoint(x: 150, y: 150)), 7, "where only the lower one is")
        XCTAssertNil(AnnotationHit.topmost(in: [under, over], at: CGPoint(x: 500, y: 500)))
        XCTAssertNil(AnnotationHit.topmost(in: [under, over], at: CGPoint(x: CGFloat.nan, y: 250)))
        XCTAssertNil(AnnotationHit.topmost(in: [], at: point))
    }

    func testAHandleIsTakenWithinItsRadiusAndTheNearestWins() {
        let box = shape(.rectangle, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        XCTAssertEqual(AnnotationHit.handle(of: box, at: CGPoint(x: 303, y: 204)), .bottomRight)
        XCTAssertEqual(AnnotationHit.handle(of: box, at: CGPoint(x: 100, y: 100)), .topLeft)
        XCTAssertNil(AnnotationHit.handle(of: box, at: CGPoint(x: 200, y: 150)), "the middle is the body, not a handle")
        XCTAssertNil(AnnotationHit.handle(of: box, at: CGPoint(x: 312, y: 200)))
        let line = shape(.line, CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        XCTAssertEqual(AnnotationHit.handle(of: line, at: CGPoint(x: 99, y: 101)), .start)
        XCTAssertEqual(AnnotationHit.handle(of: line, at: CGPoint(x: 300, y: 197)), .end)
        // Two ends nearer than a radius each: the nearer is taken, not the first.
        let short = shape(.line, CGPoint(x: 100, y: 100), CGPoint(x: 106, y: 100))
        XCTAssertEqual(AnnotationHit.handle(of: short, at: CGPoint(x: 105, y: 100)), .end)
    }
}
