import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **What the ruler does with the inputs its first tests did not feed it:** an angle of exactly ±90°, 180° and a million
/// turns, a number that is none, a stroke begun exactly at the reach and a hair past it, at the strip's very end and beyond it,
/// begun outside the area, in an area smaller than the strip, with every step of thickness; and the eraser over a stroke made along it.
///
/// What it would print if it failed totally: a ruler that never wrapped its angle fails `testTheAngleIsHeldInItsHalfCircle`
/// by the input it was fed; one that straightened nothing fails the "lies on the edge" assertions by name.
final class TheRulerIsFedWhatNobodyFedItTests: XCTestCase {
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let level = Ruler(center: CGPoint(x: 400, y: 300))

    private func stroke(_ tool: AnnotationTool, in bounds: CGRect? = nil, from: CGPoint, to: [CGPoint], ruler: Ruler?,
                        style: AnnotationStyle = .standard) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: bounds ?? area)
        _ = editing.press(at: from, tool: tool, style: style, ruler: ruler)
        for point in to { editing.drag(to: point, shift: false) }
        editing.end()
        return editing
    }

    func testTheAngleIsHeldInItsHalfCircle() {
        let cases: [(CGFloat, CGFloat)] = [(90, 90), (-90, 90), (180, 0), (-180, 0), (270, 90), (-270, 90), (360, 0), (91, 90), (-91, 90),
                                           (135, -45), (-135, 45), (30, 30), (-30, -30), (89.9, 90), (-89.9, 90)]
        for (given, held) in cases {
            var ruler = level
            ruler.rotate(to: given)
            XCTAssertEqual(ruler.angle, held, accuracy: 1e-9, "\(given) did not become \(held)")
            XCTAssertTrue(ruler.angle > -90 && ruler.angle <= 90)
            XCTAssertFalse(ruler.angle == 0 && ruler.angle.sign == .minus, "\(given) left a minus zero")
        }
        var many = level
        many.rotate(to: 1_000_000)
        XCTAssertTrue(many.angle > -90 && many.angle <= 90, "a million degrees left the half circle: \(many.angle)")
        for none in [CGFloat.nan, .infinity, -.infinity] {
            var ruler = level
            ruler.rotate(to: 30)
            ruler.rotate(to: none)
            XCTAssertEqual(ruler.angle, 30, "\(none) turned the ruler")
            XCTAssertEqual(Ruler(center: level.center, angle: none).angle, 0, "\(none) at the start turned the ruler")
        }
    }

    func testAnAngleOfNinetyIsOneStripWhicheverWayItWasReached() {
        let up = Ruler(center: level.center, angle: 90), down = Ruler(center: level.center, angle: -90)
        XCTAssertEqual(up, down)
        XCTAssertTrue(up.contains(CGPoint(x: 400, y: 440)))
        XCTAssertFalse(up.contains(CGPoint(x: 440, y: 300)))
        XCTAssertNotNil(up.snap(CGPoint(x: 417 + 12, y: 300)), "a press 12 pt from a vertical edge was not taken")
    }

    func testAPressExactlyAtTheReachIsTakenAndAHairPastItIsNot() {
        for angle in [0, 90] as [CGFloat] {
            let ruler = Ruler(center: CGPoint(x: 400, y: 300), angle: angle)
            let edge = ruler.edges[0]
            let outward = angle == 0 ? CGPoint(x: 0, y: -1) : CGPoint(x: 1, y: 0)
            let along = CGPoint(x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2)
            XCTAssertNotNil(ruler.edge(near: CGPoint(x: along.x + outward.x * Ruler.reach, y: along.y + outward.y * Ruler.reach)),
                            "a press exactly \(Ruler.reach) pt out at \(angle)° was refused")
            XCTAssertNil(ruler.edge(near: CGPoint(x: along.x + outward.x * (Ruler.reach + 0.001), y: along.y + outward.y * (Ruler.reach + 0.001))),
                         "a press a hair past the reach at \(angle)° was taken")
        }
        var turned = level
        turned.rotate(to: 30)
        let edge = turned.edges[0]
        let normal = CGPoint(x: sin(30 * .pi / 180), y: -cos(30 * .pi / 180))
        let middle = CGPoint(x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2)
        XCTAssertNotNil(turned.edge(near: CGPoint(x: middle.x + normal.x * 11.999, y: middle.y + normal.y * 11.999)))
        XCTAssertNil(turned.edge(near: CGPoint(x: middle.x + normal.x * 12.001, y: middle.y + normal.y * 12.001)))
    }

    func testAPressAtTheStripsVeryEndAndBeyondItStartsOnTheEdgesEnd() {
        let upper = level.edges[0]
        XCTAssertEqual(level.snap(upper.to), upper.to)
        XCTAssertEqual(level.snap(CGPoint(x: upper.to.x + 8, y: upper.to.y)), upper.to, "beyond the end the press was not taken to the end")
        XCTAssertNotNil(level.snap(CGPoint(x: upper.to.x + 12, y: upper.to.y)), "exactly the reach past the end was refused")
        XCTAssertNil(level.snap(CGPoint(x: upper.to.x + 12.001, y: upper.to.y)))
        XCTAssertNil(level.snap(CGPoint(x: upper.to.x + 9, y: upper.to.y - 9)), "a press 12.7 pt from the corner was taken")
        XCTAssertNotNil(level.snap(CGPoint(x: upper.to.x + 8, y: upper.to.y - 8)))
    }

    func testAStrokeThatRunsPastTheStripsEndIsKeptAtTheEndOrLeavesNothing() {
        let upper = level.edges[0]
        let none = stroke(.pen, from: CGPoint(x: upper.to.x + 6, y: upper.to.y), to: [CGPoint(x: 650, y: 250)], ruler: level)
        XCTAssertEqual(none.layers, [], "a stroke of no length became a layer")
        XCTAssertFalse(none.canUndo, "a stroke of no length is an undo step")
        let back = stroke(.pencil, from: CGPoint(x: upper.to.x + 6, y: upper.to.y - 3), to: [CGPoint(x: 300, y: 200)], ruler: level)
        XCTAssertEqual(back.layers.count, 1)
        XCTAssertEqual(back.layers.first?.start, upper.to)
        XCTAssertEqual(back.layers.first?.end.y ?? 0, upper.from.y, accuracy: 1e-9)
    }

    func testAStrokeOfEveryFreehandToolAlongTheRulerHasTheFieldsOfOneMadeByHand() throws {
        let upper = level.edges[0]
        for tool in [AnnotationTool.pen, .pencil, .highlighter] {
            for thickness in AnnotationThickness.allCases {
                let style = AnnotationStyle(thickness: thickness)
                let made = try XCTUnwrap(stroke(tool, from: CGPoint(x: 300, y: upper.from.y - 4),
                                                to: [CGPoint(x: 400, y: 200), CGPoint(x: 500, y: 150)], ruler: level, style: style).layers.first)
                let byHand = Annotation(tool: tool, start: CGPoint(x: 300, y: upper.from.y), end: CGPoint(x: 500, y: upper.from.y),
                                        points: [CGPoint(x: 300, y: upper.from.y), CGPoint(x: 500, y: upper.from.y)], style: style, id: made.id)
                XCTAssertEqual(made, byHand, "\(tool) at \(thickness) along the ruler is not the stroke of its pen made by hand")
            }
        }
    }

    func testAStrokeBegunInsideThePictureBesideAnEdgeThatIsOutsideItIsNotLost() throws {
        // The ruler's centre is held at the area's lower edge, so its lower edge is 17 pt below the picture, out of sight.
        var ruler = level
        ruler.move(to: CGPoint(x: 400, y: area.maxY), within: area)
        XCTAssertEqual(ruler.edges[1].from.y, area.maxY + 17, accuracy: 1e-9)
        // A press 5 pt inside the picture and past the strip's end is nearest to the hidden edge's end, 12 pt away or less.
        let made = stroke(.pen, from: CGPoint(x: 560, y: area.maxY - 5), to: [CGPoint(x: 600, y: 450), CGPoint(x: 640, y: 420)], ruler: ruler)
        XCTAssertEqual(made.layers.count, 1, "a stroke begun in the picture beside a hidden edge left no layer")
    }

    func testAPressBelowThePictureBesideTheHiddenEdgeDrawsAsItDoesWithNoRuler() throws {
        var ruler = level
        ruler.move(to: CGPoint(x: 400, y: area.maxY), within: area)
        let way = [CGPoint(x: 330, y: 480), CGPoint(x: 360, y: 440), CGPoint(x: 420, y: 470)]
        let bare = stroke(.pen, from: CGPoint(x: 300, y: area.maxY + 8), to: way, ruler: nil)
        let with = stroke(.pen, from: CGPoint(x: 300, y: area.maxY + 8), to: way, ruler: ruler)
        XCTAssertEqual(bare.layers.count, 1, "the fixture without a ruler drew nothing")
        XCTAssertEqual(with.layers.count, 1, "a press below the picture, beside an edge the picture does not show, drew nothing")
        XCTAssertGreaterThan(with.layers.first?.points.count ?? 0, 2, "that press was straightened along an edge nobody can see")
    }

    func testAnAreaSmallerThanTheStripGivesAShortStripAndNothingBreaks() {
        let tiny = CGRect(x: 100, y: 100, width: 20, height: 20)
        let ruler = Ruler.centred(in: tiny)
        XCTAssertEqual(ruler.length, 16, accuracy: 1e-9)
        XCTAssertEqual(ruler.center, CGPoint(x: 110, y: 110))
        for tool in [AnnotationTool.pen, .pencil, .highlighter] {
            for from in [CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 100), CGPoint(x: 119, y: 119), CGPoint(x: 90, y: 90)] {
                let editing = stroke(tool, in: tiny, from: from, to: [CGPoint(x: 120, y: 105), CGPoint(x: 1_000, y: 1_000)], ruler: ruler)
                for layer in editing.layers {
                    XCTAssertTrue(layer.isUsable)
                    for point in layer.points {
                        XCTAssertTrue(tiny.insetBy(dx: -1e-9, dy: -1e-9).contains(point), "\(tool) from \(from) left the area at \(point)")
                    }
                }
            }
        }
        let empty = Ruler.centred(in: CGRect(x: 100, y: 100, width: 0, height: 0))
        XCTAssertEqual(empty.length, 0)
        XCTAssertNil(empty.edge(near: CGPoint(x: CGFloat.nan, y: 0)))
        _ = empty.snap(CGPoint(x: 100, y: 100))
        _ = empty.contains(CGPoint(x: 100, y: 100))
    }

    func testAKeepWithinTheAreaTakesTheCentreBackWhenTheAreaShrankPastIt() {
        var ruler = level
        ruler.move(to: CGPoint(x: 690, y: 490), within: area)
        ruler.keep(within: CGRect(x: 100, y: 100, width: 50, height: 50))
        XCTAssertEqual(ruler.center, CGPoint(x: 150, y: 150))
        ruler.move(to: CGPoint(x: CGFloat.nan, y: 120), within: area)
        XCTAssertEqual(ruler.center, CGPoint(x: 150, y: 150), "a point that is none moved the ruler")
        ruler.move(to: CGPoint(x: CGFloat.infinity, y: 120), within: area)
        XCTAssertEqual(ruler.center, CGPoint(x: 150, y: 150))
    }

    func testTheEraserTakesAStrokeMadeAlongTheRulerWhereverItsBodyIs() throws {
        let upper = level.edges[0]
        for tool in [AnnotationTool.pen, .pencil, .highlighter] {
            var editing = stroke(tool, from: CGPoint(x: 300, y: upper.from.y - 5), to: [CGPoint(x: 500, y: 200)], ruler: level)
            let layer = try XCTUnwrap(editing.layers.first)
            let half = (layer.stroke?.width ?? 0) / 2
            editing.beginErase(at: CGPoint(x: 400, y: upper.from.y - half - 9 + 2), radius: 9)
            editing.end()
            XCTAssertEqual(editing.layers, [], "the eraser missed a \(tool) stroke along the ruler it was over")
            editing.undo()
            XCTAssertEqual(editing.layers.count, 1, "one undo did not bring the erased \(tool) stroke back")
            editing.beginErase(at: CGPoint(x: 400, y: upper.from.y - half - 9 - 3), radius: 9)
            editing.end()
            XCTAssertEqual(editing.layers.count, 1, "the eraser took a \(tool) stroke it was 3 pt short of")
        }
    }

    // MARK: the eraser at the area's edge

    private func line(_ editing: inout AnnotationEditing, _ tool: AnnotationTool, from: CGPoint, to: CGPoint) {
        editing.begin(tool, at: from)
        editing.drag(to: to, shift: false)
        editing.end()
    }

    func testALayerWhollyInsideTheAreaIsErasedByACircleAtTheAreasVeryEdge() {
        var editing = AnnotationEditing(bounds: area)
        line(&editing, .line, from: CGPoint(x: 200, y: 102), to: CGPoint(x: 400, y: 102))
        let before = editing.layers
        XCTAssertEqual(before.count, 1)
        // On the edge itself, 2 pt from the line.
        editing.beginErase(at: CGPoint(x: 300, y: 100), radius: 9)
        editing.end()
        XCTAssertEqual(editing.layers, [], "a circle on the area's edge missed a line 2 pt inside it")
        editing.undo()
        // Its centre 1 pt outside the area: the circle still covers the picture's first rows.
        editing.beginErase(at: CGPoint(x: 300, y: 99), radius: 9)
        editing.end()
        XCTAssertEqual(editing.layers, [], "a circle whose centre is 1 pt outside the area missed a line 3 pt inside it")
        editing.undo()
        // And one 30 pt out covers none of the picture.
        editing.beginErase(at: CGPoint(x: 300, y: 70), radius: 9)
        editing.end()
        XCTAssertEqual(editing.layers, before, "a circle nowhere near the area took a layer")
        // The same at the corner and on the last column.
        var corner = AnnotationEditing(bounds: area)
        line(&corner, .line, from: CGPoint(x: 699, y: 499), to: CGPoint(x: 699, y: 450))
        corner.beginErase(at: CGPoint(x: 700, y: 500), radius: 9)
        corner.end()
        XCTAssertEqual(corner.layers, [], "a circle at the area's far corner missed a line 1 pt inside it")
    }

    func testALayerWhoseFrameMeetsTheAreaButWhoseVisiblePartIsEmptyIsNotTakenFromTheArea() {
        var editing = AnnotationEditing(bounds: area)
        // A frame that encloses the whole area, and an outline that is all outside it.
        line(&editing, .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 700, y: 500))
        editing.reshape(bounds: CGRect(x: 150, y: 150, width: 300, height: 200))
        let outline = editing.layers
        XCTAssertEqual(outline.count, 1)
        for press in [CGPoint(x: 200, y: 200), CGPoint(x: 151, y: 151), CGPoint(x: 449, y: 349), CGPoint(x: 300, y: 250)] {
            editing.beginErase(at: press, radius: 9)
            editing.end()
            XCTAssertEqual(editing.layers, outline, "a circle at \(press), nowhere near the outline's visible part, took the layer")
        }
        // A line wholly outside the area whose frame reaches the area's corner: a circle at the corner is 7.8 pt from the line,
        // and the part of the picture the area shows has none of its ink.
        var diagonal = AnnotationEditing(bounds: area)
        line(&diagonal, .line, from: CGPoint(x: 250, y: 340), to: CGPoint(x: 340, y: 250))
        diagonal.reshape(bounds: CGRect(x: 300, y: 300, width: 400, height: 200))
        let kept = diagonal.layers
        XCTAssertEqual(kept.count, 1)
        diagonal.beginErase(at: CGPoint(x: 300.5, y: 300.5), radius: 9)
        diagonal.end()
        XCTAssertEqual(diagonal.layers, kept, "a circle over the area took a line none of which the area shows")
        // A fill under the area is the picture's: pressing inside takes it.
        var filled = AnnotationEditing(bounds: area)
        filled.begin(.rectangle, at: CGPoint(x: 100, y: 100), style: AnnotationStyle(filled: true))
        filled.drag(to: CGPoint(x: 700, y: 500), shift: false)
        filled.end()
        filled.reshape(bounds: CGRect(x: 150, y: 150, width: 300, height: 200))
        filled.beginErase(at: CGPoint(x: 300, y: 250), radius: 9)
        filled.end()
        XCTAssertEqual(filled.layers, [], "a filled layer wider than the area was not taken by a circle on the visible fill")
    }

    func testAStrokeOnAVerticalAndOnATurnedRulerIsUndoneAsOneStep() throws {
        for angle in [90, -90, 45, -45, 17] as [CGFloat] {
            let ruler = Ruler(center: CGPoint(x: 400, y: 300), angle: angle)
            let edge = ruler.edges[0]
            let middle = CGPoint(x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2)
            let out = CGPoint(x: (middle.x - 400) / 17 * 4, y: (middle.y - 300) / 17 * 4)
            var editing = stroke(.pen, from: CGPoint(x: middle.x + out.x, y: middle.y + out.y),
                                 to: [CGPoint(x: middle.x + 30, y: middle.y + 30), CGPoint(x: edge.to.x, y: edge.to.y)], ruler: ruler)
            XCTAssertEqual(editing.layers.count, 1, "angle \(angle) left \(editing.layers.count) layers")
            editing.undo()
            XCTAssertEqual(editing.layers, [])
            XCTAssertFalse(editing.canUndo)
        }
    }
}
