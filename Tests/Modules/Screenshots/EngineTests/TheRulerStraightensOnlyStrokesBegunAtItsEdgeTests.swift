import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A stroke of the pen, the pencil or the marker that begins within 12 pt of the ruler's edge lies on that edge, and one
/// that begins farther is free; the arrow and the shapes never read the ruler.** Both edges, a level ruler and a turned one,
/// the pointer straying far from the edge once the stroke is down, the angle's sticking at 2°, and the file: a stroke along
/// the ruler exports as the ordinary stroke of its pen, pixel for pixel.
///
/// What it would print if it failed totally: a ruler that straightened nothing fails every "lies on the edge" assertion by
/// name; one that straightened everything fails every "stays free" one.
final class TheRulerStraightensOnlyStrokesBegunAtItsEdgeTests: XCTestCase {
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)
    /// Level at the middle of the area: its edges are y 283 and y 317, from x 250 to x 550.
    private let level = Ruler(center: CGPoint(x: 400, y: 300))

    /// How far `point` is from the infinite line through `edge`.
    private func offLine(_ point: CGPoint, _ edge: Ruler.Edge) -> CGFloat {
        let dx = edge.to.x - edge.from.x, dy = edge.to.y - edge.from.y
        return abs((point.x - edge.from.x) * dy - (point.y - edge.from.y) * dx) / hypot(dx, dy)
    }

    /// A stroke of `tool` pressed at `from` and dragged over the wavy points of `way`, with `ruler`, and the layer it became.
    private func stroke(_ tool: AnnotationTool, from: CGPoint, way: [CGPoint], ruler: Ruler?) throws -> Annotation {
        var editing = AnnotationEditing(bounds: area)
        _ = editing.press(at: from, tool: tool, ruler: ruler)
        for point in way { editing.drag(to: point, shift: false) }
        editing.end()
        return try XCTUnwrap(editing.layers.first, "\(tool) begun at \(from) left no layer")
    }

    private func wave(from: CGPoint, to: CGPoint) -> [CGPoint] {
        (1...40).map { step in
            let t = CGFloat(step) / 40
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t + sin(t * 20) * 6)
        }
    }

    func testAStrokeBegunElevenPointsFromTheUpperEdgeLiesOnItAndOneBegunThirteenAwayIsFree() throws {
        let upper = level.edges[0]
        for tool in [AnnotationTool.pen, .pencil, .highlighter] {
            let near = CGPoint(x: 300, y: upper.from.y - 11)
            let snapped = try stroke(tool, from: near, way: wave(from: near, to: CGPoint(x: 500, y: 240)), ruler: level)
            XCTAssertEqual(snapped.tool, tool)
            for point in [snapped.start, snapped.end] + snapped.points {
                XCTAssertEqual(point.y, upper.from.y, accuracy: 1e-6, "\(tool) begun 11 pt from the edge left the line at \(point)")
            }
            XCTAssertEqual(snapped.start.x, 300, accuracy: 1e-6, "the stroke did not begin where the pointer pressed, along the edge")
            XCTAssertEqual(snapped.end.x, 500, accuracy: 1e-6)

            let far = CGPoint(x: 300, y: upper.from.y - 13)
            let free = try stroke(tool, from: far, way: wave(from: far, to: CGPoint(x: 500, y: 240)), ruler: level)
            XCTAssertEqual(free.start, far, "\(tool) begun 13 pt from the edge was moved")
            XCTAssertGreaterThan(free.points.count, 3, "\(tool) begun 13 pt from the edge lost its freehand points")
            XCTAssertTrue(free.points.contains { abs($0.y - upper.from.y) > 14 }, "\(tool) begun 13 pt from the edge was straightened")
        }
    }

    func testTheLowerEdgeIsTheSameOnItsOtherSide() throws {
        let lower = level.edges[1]
        let near = CGPoint(x: 300, y: lower.from.y + 11)
        let snapped = try stroke(.pen, from: near, way: wave(from: near, to: CGPoint(x: 500, y: 360)), ruler: level)
        for point in [snapped.start, snapped.end] + snapped.points {
            XCTAssertEqual(point.y, lower.from.y, accuracy: 1e-6, "a stroke begun 11 pt below the lower edge left it at \(point)")
        }
        let far = CGPoint(x: 300, y: lower.from.y + 13)
        let free = try stroke(.pen, from: far, way: wave(from: far, to: CGPoint(x: 500, y: 360)), ruler: level)
        XCTAssertEqual(free.start, far)
        XCTAssertTrue(free.points.contains { abs($0.y - lower.from.y) > 14 }, "a stroke begun 13 pt below the lower edge was straightened")
    }

    func testTheNearerEdgeIsTheOneAStrokeBeginsOnWhenBothAreWithinReach() throws {
        // 34 pt across: a point 15 pt from one edge is 19 from the other, and a point in the middle is 17 from both.
        let upper = level.edges[0], lower = level.edges[1]
        let nearUpper = try stroke(.pen, from: CGPoint(x: 400, y: upper.from.y + 4), way: [CGPoint(x: 450, y: 300)], ruler: level)
        XCTAssertEqual(nearUpper.end.y, upper.from.y, accuracy: 1e-6)
        let nearLower = try stroke(.pen, from: CGPoint(x: 400, y: lower.from.y - 4), way: [CGPoint(x: 450, y: 300)], ruler: level)
        XCTAssertEqual(nearLower.end.y, lower.from.y, accuracy: 1e-6)
        XCTAssertNil(level.snap(CGPoint(x: 400, y: 300)), "the middle of the strip is 17 pt from both edges and is free")
    }

    func testATurnedRulerStraightensAlongItsOwnEdge() throws {
        var turned = level
        turned.rotate(to: 30)
        XCTAssertEqual(turned.angle, 30)
        let edge = turned.edges[0]
        let mid = CGPoint(x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2)
        // The edge's normal, away from the strip: the strip's centre is on its other side.
        let toward = hypot(mid.x - turned.center.x, mid.y - turned.center.y)
        let away = CGPoint(x: (mid.x - turned.center.x) / toward, y: (mid.y - turned.center.y) / toward)
        for (gap, straight) in [(11 as CGFloat, true), (13, false)] {
            let press = CGPoint(x: mid.x + away.x * gap, y: mid.y + away.y * gap)
            let way = wave(from: press, to: CGPoint(x: press.x + 120, y: press.y - 60))
            let made = try stroke(.pen, from: press, way: way, ruler: turned)
            let distances = ([made.start, made.end] + made.points).map { offLine($0, edge) }
            if straight {
                XCTAssertLessThan(distances.max() ?? 99, 1e-6, "a stroke begun 11 pt from the turned edge left its line")
            } else {
                XCTAssertGreaterThan(distances.max() ?? 0, 5, "a stroke begun 13 pt from the turned edge was straightened")
                XCTAssertEqual(made.start, press)
            }
        }
    }

    func testTheStrokeIsCutAtTheEndOfTheRulerWhereverThePointerGoes() throws {
        let near = CGPoint(x: 500, y: level.edges[0].from.y - 5)
        let made = try stroke(.pen, from: near, way: [CGPoint(x: 600, y: 200), CGPoint(x: 690, y: 120)], ruler: level)
        XCTAssertEqual(made.end.x, 550, accuracy: 1e-6, "the stroke went on past the ruler's end")
        XCTAssertEqual(made.end.y, level.edges[0].from.y, accuracy: 1e-6)
        // A press beside the strip but beyond its end is 12 pt from the end of the edge, not from the line it is on.
        XCTAssertNil(level.snap(CGPoint(x: 566, y: 283)), "a press 16 pt past the end of the edge took it")
        XCTAssertNotNil(level.snap(CGPoint(x: 558, y: 283)))
    }

    func testTheArrowAndTheShapesDoNotReadTheRuler() throws {
        let near = CGPoint(x: 300, y: level.edges[0].from.y - 5)
        for tool in [AnnotationTool.arrow, .line, .rectangle, .ellipse, .blur] {
            let made = try stroke(tool, from: near, way: [CGPoint(x: 400, y: 200), CGPoint(x: 500, y: 240)], ruler: level)
            XCTAssertEqual(made.start, near, "\(tool) read the ruler")
            XCTAssertEqual(made.end, CGPoint(x: 500, y: 240), "\(tool) read the ruler")
        }
    }

    func testAStrokeIsOrdinaryEveryWayItIsHeld() throws {
        var editing = AnnotationEditing(bounds: area)
        let near = CGPoint(x: 300, y: 272)
        _ = editing.press(at: near, tool: .pen, ruler: level)
        editing.drag(to: CGPoint(x: 500, y: 250), shift: false)
        XCTAssertEqual(editing.draft?.points.count, 2, "the draft under the pointer is not the straight run")
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
        XCTAssertEqual(editing.layers[0].tool, .pen)
        editing.undo()
        XCTAssertEqual(editing.layers, [], "one undo did not take the stroke back")
        editing.redo()
        // The next stroke has no guide left over from the last: a press far from the ruler is free.
        let free = CGPoint(x: 200, y: 450)
        _ = editing.press(at: free, tool: .pen, ruler: level)
        editing.drag(to: CGPoint(x: 260, y: 420), shift: false)
        editing.drag(to: CGPoint(x: 320, y: 470), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.count, 2)
        XCTAssertEqual(editing.layers[1].start, free)
        XCTAssertGreaterThan(editing.layers[1].points.count, 2)
        // And no ruler at all is no straightening.
        let bare = try stroke(.pen, from: near, way: wave(from: near, to: CGPoint(x: 500, y: 240)), ruler: nil)
        XCTAssertEqual(bare.start, near)
        XCTAssertGreaterThan(bare.points.count, 3)
    }

    func testTheAngleSticksToNoughtFortyFiveAndNinetyWithinTwoDegrees() {
        var ruler = level
        let cases: [(asked: CGFloat, held: CGFloat)] = [
            (1.9, 0), (-1.9, 0), (2.1, 2.1), (-2.1, -2.1),
            (43.1, 45), (46.9, 45), (42.9, 42.9), (47.1, 47.1),
            (88.1, 90), (91.9, 90), (87.9, 87.9),
            (-43.1, -45), (-42.9, -42.9),
            (181.9, 0), (225, 45), (-90, 90),
        ]
        for (asked, held) in cases {
            ruler.rotate(to: asked)
            XCTAssertEqual(ruler.angle, held, accuracy: 1e-9, "asked \(asked)°: the strip stands at \(ruler.angle)°")
        }
        ruler.rotate(to: 30)
        ruler.rotate(to: .nan)
        ruler.rotate(to: .infinity)
        XCTAssertEqual(ruler.angle, 30, "an angle that is no number turned the strip")
    }

    func testAMovedRulerStaysInTheAreaAndANumberThatIsNoneMovesNothing() {
        var ruler = level
        ruler.move(to: CGPoint(x: 5000, y: -5000), within: area)
        XCTAssertEqual(ruler.center, CGPoint(x: area.maxX, y: area.minY))
        ruler.move(to: CGPoint(x: CGFloat.nan, y: 200), within: area)
        XCTAssertEqual(ruler.center, CGPoint(x: area.maxX, y: area.minY))
        XCTAssertEqual(Ruler.centred(in: CGRect(x: 0, y: 0, width: 100, height: 50)).length, 80, "a narrow area did not shorten the strip")
        XCTAssertEqual(Ruler.centred(in: area).length, Ruler.standardLength)
        XCTAssertTrue(level.contains(CGPoint(x: 400, y: 300)))
        XCTAssertFalse(level.contains(CGPoint(x: 400, y: 318)))
        XCTAssertFalse(level.contains(CGPoint(x: 551, y: 300)))
    }

    // MARK: the file

    /// A stroke drawn along the ruler is the ordinary stroke of its pen: its pixels are those of the same stroke made by
    /// hand, and none of the strip's is in them.
    func testAStrokeAlongTheRulerExportsAsTheOrdinaryStrokeOfItsPen() async throws {
        let rig = Rig(home: scratchDirectory("ruler-export"))
        let shot = DisplayShot.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60), scale: 2,
                                                   image: makeImage(width: 200, height: 120, red: 255, green: 255, blue: 255)))
        let freeze = Freeze(displays: [shot], windows: [])
        let selection = CGRect(x: 0, y: 0, width: 100, height: 60)
        let ruler = Ruler(center: CGPoint(x: 50, y: 30), length: 60)
        var editing = AnnotationEditing(bounds: selection)
        _ = editing.press(at: CGPoint(x: 30, y: 8), tool: .pen, ruler: ruler)
        editing.drag(to: CGPoint(x: 70, y: 20), shift: false)
        editing.end()
        let along = try XCTUnwrap(editing.layers.first)
        XCTAssertEqual(along.start.y, 13, accuracy: 1e-6, "the fixture's stroke is not on the edge")
        let byHand = Annotation(tool: .pen, start: CGPoint(x: 30, y: 13), end: CGPoint(x: 70, y: 13),
                                points: [CGPoint(x: 30, y: 13), CGPoint(x: 70, y: 13)], id: along.id)
        let firstDrawn = await rig.session.annotated(freeze, display: DisplayID(1), local: selection, layers: [along])
        let first = try XCTUnwrap(firstDrawn)
        let secondDrawn = await rig.session.annotated(freeze, display: DisplayID(1), local: selection, layers: [byHand])
        let second = try XCTUnwrap(secondDrawn)
        XCTAssertEqual(pixels(first), pixels(second), "a stroke along the ruler is not the ordinary stroke of its pen in the file")
        XCTAssertTrue(pixels(first).contains { $0 != 255 }, "the fixture's file holds no ink: the comparison reads nothing")
        // The strip's own place, below the stroke, is as white as the picture was.
        let belowTheEdge = pixels(first, rows: 40..<110)
        XCTAssertFalse(belowTheEdge.contains { $0 != 255 }, "the ruler's strip left something in the file")
    }

    private func pixels(_ image: CGImage, rows: Range<Int>? = nil) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let all = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
        guard let rows else { return all }
        return Array(all[(rows.lowerBound * image.width * 4)..<(rows.upperBound * image.width * 4)])
    }
}
