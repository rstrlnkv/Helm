import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The drawing tools under the inputs the task did not name:** ⇧ flipped many times in one drag,
/// a pencil that leaves and re-enters the selection, points on the spacing's edge, the thinning's
/// ends, a selection narrower than the drag, two markers over one another, undo of a marker.
final class TheNewToolsMeetInputsNobodyFedThemTests: XCTestCase {

    private let area = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// `CGRect.contains` excludes the far edges; a point on the selection's edge is inside it.
    private func inside(_ point: CGPoint, _ rect: CGRect) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    func testShiftFlippedAThousandTimesWithThePointerStillLeavesTheDraftAndTheListAlone() {
        for tool in [AnnotationTool.rectangle, .ellipse, .line, .highlighter, .pencil] {
            var editing = AnnotationEditing(bounds: area)
            editing.begin(tool, at: CGPoint(x: 100, y: 100))
            editing.drag(to: CGPoint(x: 180, y: 140), shift: false)
            let before = editing.draft!
            for index in 0..<1000 { editing.modifiersChanged(shift: index % 2 == 0) }
            // The last flip was ⇧ up (index 999): the draft is what it was with ⇧ up.
            XCTAssertEqual(editing.draft, before, "\(tool): 1000 flips changed the draft")
            XCTAssertLessThanOrEqual(editing.draft!.points.count, 2, "\(tool): a flip grew the point list")
        }
    }

    func testAFlipOfShiftRightAfterThePressDoesNotInventAPointOnThePencil() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.pencil, at: CGPoint(x: 10, y: 10))
        editing.modifiersChanged(shift: true)
        XCTAssertEqual(editing.draft!.points, [CGPoint(x: 10, y: 10)], "⇧ with no movement added a duplicate point")
    }

    func testAShiftedShapeIsInsideEverySelectionEdgeOnTheLastBitAndStaysSquareWhereTheRoomAllows() {
        let narrow = CGRect(x: 30, y: 20, width: 7, height: 300)
        var seed: UInt64 = 42
        func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 40) / CGFloat(1 << 24) }
        for bounds in [area, narrow] {
            for tool in [AnnotationTool.rectangle, .ellipse, .line, .highlighter, .arrow] {
                for _ in 0..<500 {
                    var editing = AnnotationEditing(bounds: bounds)
                    editing.begin(tool, at: CGPoint(x: bounds.minX + next() * bounds.width, y: bounds.minY + next() * bounds.height))
                    editing.drag(to: CGPoint(x: -200 + next() * 800, y: -200 + next() * 700), shift: true)
                    let draft = editing.draft!
                    XCTAssertTrue(inside(draft.end, bounds), "\(tool) in \(bounds): end \(draft.end) is outside, shift held")
                    if tool == .rectangle || tool == .ellipse {
                        XCTAssertEqual(abs(draft.end.x - draft.start.x), abs(draft.end.y - draft.start.y), accuracy: 1e-9,
                                       "\(tool): not square at \(draft.start) -> \(draft.end)")
                    }
                }
            }
        }
    }

    func testAShiftedSquareStartedOnTheRightEdgeAndDraggedStraightDownKeepsAUsableSize() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.rectangle, at: CGPoint(x: area.maxX, y: 100))
        editing.drag(to: CGPoint(x: area.maxX, y: 200), shift: true)
        XCTAssertTrue(editing.draft!.isUsable, "the square collapsed: \(editing.draft!.end)")
    }

    func testAPencilThatLeavesAndComesBackStaysInsideAndEndsAtThePointer() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.pencil, at: CGPoint(x: 390, y: 150))
        for x in stride(from: 392.0, through: 900, by: 30) { editing.drag(to: CGPoint(x: x, y: 150), shift: false) }
        for x in stride(from: 900.0, through: 200, by: -30) { editing.drag(to: CGPoint(x: x, y: 150 + (900 - x) / 10), shift: true) }
        let draft = editing.draft!
        XCTAssertTrue(draft.points.allSatisfy { inside($0, area) }, "a point left the selection")
        XCTAssertEqual(draft.points.last, draft.end)
        XCTAssertEqual(draft.points.first, CGPoint(x: 390, y: 150))
        XCTAssertGreaterThan(draft.points.count, 3)
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
    }

    func testAPointAFullSpacingFromTheLastKeptOneIsKeptAndANearerOneIsOnlyTheTip() {
        for tool in [AnnotationTool.pencil, .highlighter] {
            var editing = AnnotationEditing(bounds: area)
            editing.begin(tool, at: CGPoint(x: 10, y: 10))
            editing.drag(to: CGPoint(x: 12, y: 10), shift: false)
            XCTAssertEqual(editing.draft!.points, [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 10)], "\(tool): 2 pt apart must be kept")
            editing.drag(to: CGPoint(x: 13.9, y: 10), shift: false)
            XCTAssertEqual(editing.draft!.points.last, CGPoint(x: 13.9, y: 10), "\(tool): the tip is the pointer")
            XCTAssertEqual(editing.draft!.points.count, 3)
            editing.drag(to: CGPoint(x: 14, y: 10), shift: false)
            XCTAssertEqual(editing.draft!.points.count, 3, "\(tool): exactly 2 pt from the last kept one is kept, not added twice")
            editing.drag(to: CGPoint(x: 15, y: 10), shift: false)
            XCTAssertEqual(editing.draft!.points.count, 4, "\(tool): 1 pt from the kept 14 is a new tip")
        }
    }

    func testThinningKeepsTheFirstPointTheTipTheBoundAndTheOrder() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 20_000, height: 100))
        editing.begin(.pencil, at: CGPoint(x: 0, y: 50))
        for index in 1...6000 { editing.drag(to: CGPoint(x: Double(index) * 3, y: 50 + Double(index % 7)), shift: false) }
        let points = editing.draft!.points
        XCTAssertLessThanOrEqual(points.count, Annotation.maxPoints)
        XCTAssertGreaterThan(points.count, 100, "thinned to nothing")
        XCTAssertEqual(points.first, CGPoint(x: 0, y: 50), "the first point was thinned away")
        XCTAssertEqual(points.last, CGPoint(x: 18_000, y: 50 + 6000 % 7), "the tip was thinned away")
        XCTAssertEqual(points.map(\.x), points.map(\.x).sorted(), "the thinning reordered the path")
    }

    func testASlowPencilDragAtOnePointPerEventStillFollowsTheCurve() {
        var editing = AnnotationEditing(bounds: area)
        let centre = CGPoint(x: 200, y: 150), radius: CGFloat = 80
        editing.begin(.pencil, at: CGPoint(x: centre.x + radius, y: centre.y))
        let steps = Int(2 * .pi * radius)   // about one point of arc per event
        for step in 1...steps {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            editing.drag(to: CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle)), shift: false)
        }
        let points = editing.draft!.points
        XCTAssertGreaterThan(points.count, 40, "a circle drawn slowly kept \(points.count) points")
        XCTAssertLessThanOrEqual(points.count, Annotation.maxPoints)
        let farthest = points.map { abs(hypot($0.x - centre.x, $0.y - centre.y) - radius) }.max()!
        XCTAssertLessThan(farthest, 2)
    }

    func testAMarkerComesBackFromUndoAndRedoWithItsInk() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.highlighter, at: CGPoint(x: 10, y: 10))
        editing.drag(to: CGPoint(x: 200, y: 10), shift: false)
        editing.end()
        let marker = editing.layers[0]
        editing.undo(); editing.undo()
        XCTAssertTrue(editing.layers.isEmpty)
        editing.redo(); editing.redo()
        XCTAssertEqual(editing.layers, [marker])
        XCTAssertEqual(editing.layers[0].stroke?.multiplies, true)
        XCTAssertEqual(editing.layers[0].stroke?.width, AnnotationThickness.medium.points(for: .highlighter))
        editing.undo()
        editing.begin(.line, at: CGPoint(x: 1, y: 1)); editing.drag(to: CGPoint(x: 50, y: 50), shift: false); editing.end()
        XCTAssertFalse(editing.canRedo, "a new layer kept the marker in the redo list")
    }

    func testNonNumbersNeverReachAnyToolsDraft() {
        for tool in [AnnotationTool.pencil, .highlighter, .ellipse, .line] {
            var editing = AnnotationEditing(bounds: area)
            editing.begin(tool, at: CGPoint(x: CGFloat.nan, y: 5))
            XCTAssertNil(editing.draft, "\(tool): began on a NaN")
            editing.begin(tool, at: CGPoint(x: 5, y: 5))
            editing.drag(to: CGPoint(x: CGFloat.infinity, y: CGFloat.nan), shift: true)
            editing.drag(to: CGPoint(x: 50, y: -CGFloat.infinity), shift: true)
            editing.modifiersChanged(shift: true)
            XCTAssertEqual(editing.draft!.end, CGPoint(x: 5, y: 5), "\(tool): a non-number moved the draft")
            XCTAssertTrue(inside(editing.draft!.end, area))
        }
    }

    func testAShiftFlipWithoutADraftNeitherDrawsNorWithdrawsTheEscQuestion() {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.line, at: CGPoint(x: 1, y: 1)); editing.drag(to: CGPoint(x: 50, y: 50), shift: false); editing.end()
        XCTAssertEqual(editing.escape(), .armed)
        editing.modifiersChanged(shift: true)
        XCTAssertNil(editing.draft)
        XCTAssertTrue(editing.isArmed, "a modifier alone is not an input that withdraws the question")
        XCTAssertEqual(editing.escape(), .close)
    }

    // MARK: export

    private func freeze(scale: CGFloat) -> Freeze {
        let width = Int(100 * scale), height = Int(60 * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                                                      scale: scale, image: context.makeImage()!))], windows: [])
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<3).map { Int(bytes[y * image.width * 4 + x * 4 + $0]) }
    }

    func testTwoMarkersOverOneAnotherMultiplyTwiceAtBothScales() async throws {
        let first = Annotation(tool: .highlighter, start: CGPoint(x: 10, y: 30), end: CGPoint(x: 60, y: 30),
                               points: [CGPoint(x: 10, y: 30), CGPoint(x: 35, y: 30), CGPoint(x: 60, y: 30)])
        let second = Annotation(tool: .highlighter, start: CGPoint(x: 40, y: 30), end: CGPoint(x: 90, y: 30),
                                points: [CGPoint(x: 40, y: 30), CGPoint(x: 65, y: 30), CGPoint(x: 90, y: 30)])
        for scale in [CGFloat(1), 2] {
            let rig = Rig(home: scratchDirectory("shots-two-markers-\(Int(scale))"))
            let drawn = await rig.session.annotated(freeze(scale: scale), display: DisplayID(1),
                                                    local: CGRect(x: 0, y: 0, width: 100, height: 60), layers: [first, second])
            let out = try XCTUnwrap(drawn)
            let y = Int(30 * scale)
            let once = pixel(out, x: Int(20 * scale), y: y), twice = pixel(out, x: Int(50 * scale), y: y)
            XCTAssertEqual(once[2], 117, accuracy: 6, "\(scale)x: one marker over white (blue)")
            XCTAssertEqual(twice[2], 54, accuracy: 6, "\(scale)x: two markers must multiply twice, not replace (blue)")
            XCTAssertLessThan(twice[1], once[1], "\(scale)x: the overlap is not darker than one marker")
        }
    }

    func testAnOffsetSelectionAt2xPlacesAPencilStrokeByPointsMinusItsOrigin() async throws {
        let stroke = Annotation(tool: .pencil, start: CGPoint(x: 30, y: 20), end: CGPoint(x: 70, y: 20),
                                points: [CGPoint(x: 30, y: 20), CGPoint(x: 50, y: 20), CGPoint(x: 70, y: 20)])
        let rig = Rig(home: scratchDirectory("shots-offset-pencil"))
        let drawn = await rig.session.annotated(freeze(scale: 2), display: DisplayID(1),
                                                local: CGRect(x: 20, y: 10, width: 60, height: 40), layers: [stroke])
        let out = try XCTUnwrap(drawn)
        XCTAssertEqual(out.width, 120); XCTAssertEqual(out.height, 80)
        // In the crop the line is at y = (20 - 10) * 2 = 20, x from 20 to 100.
        XCTAssertLessThan(pixel(out, x: 60, y: 20)[1], 120, "the stroke is not where points minus origin, times 2, say")
        XCTAssertEqual(pixel(out, x: 60, y: 40), [255, 255, 255])
    }
}
