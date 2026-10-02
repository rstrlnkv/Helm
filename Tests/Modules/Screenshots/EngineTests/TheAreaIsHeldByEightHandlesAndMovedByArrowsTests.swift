import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The finished area as something to take hold of, and an object moved by the arrows.** The geometry
/// is asked without a window: every handle, an area against the display's edge, one too small to hold
/// eight reaches, the object's handle winning an overlap, a step in pixels at 1x and 2x, and the one
/// undo step a run of arrow presses is.
final class TheAreaIsHeldByEightHandlesAndMovedByArrowsTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    // MARK: Which handle

    func testEveryCornerAndEdgeMiddleIsAHandleAndIsTakenWithinReachAndNotBeyondIt() {
        let places = AreaFrame.handles(of: area)
        XCTAssertEqual(places.map(\.handle), AreaHandle.allCases, "the eight, each once")
        XCTAssertEqual(places.count, 8)
        for place in places {
            XCTAssertEqual(AreaFrame.handle(of: area, at: place.point), place.handle, "\(place.handle) on its centre")
            let near = CGPoint(x: place.point.x + 3, y: place.point.y - 4) // distance 5
            XCTAssertEqual(AreaFrame.handle(of: area, at: near), place.handle, "\(place.handle) 5 points off")
            let far = CGPoint(x: place.point.x + 6, y: place.point.y + 6) // distance 8.5, past the reach
            XCTAssertNil(AreaFrame.handle(of: area, at: far), "\(place.handle) taken from 8.5 points")
        }
        XCTAssertNil(AreaFrame.handle(of: area, at: CGPoint(x: 300, y: 250)), "the middle of the area is the area's")
        XCTAssertNil(AreaFrame.handle(of: area, at: CGPoint(x: CGFloat.nan, y: 100)))
    }

    func testAnAreaAgainstTheDisplaysEdgeStillHasAllEightAndTheEdgeOnesAreTaken() {
        for (name, rect) in [("whole display", bounds), ("top left", CGRect(x: 0, y: 0, width: 300, height: 200)),
                             ("bottom right", CGRect(x: 700, y: 600, width: 300, height: 200))] {
            for place in AreaFrame.handles(of: rect) {
                XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(place.point), "\(name) \(place.handle) is off the display")
                XCTAssertEqual(AreaFrame.handle(of: rect, at: place.point), place.handle, "\(name) \(place.handle)")
            }
        }
        // The last point of the display's own pixels is within reach of the corner it is next to.
        XCTAssertEqual(AreaFrame.handle(of: bounds, at: CGPoint(x: 999.5, y: 799.5)), .bottomRight)
    }

    func testAnAreaTooSmallForEightReachesKeepsItsMiddleAndItsCornersAndNeverTraps() {
        let tiny = CGRect(x: 100, y: 100, width: 9, height: 9)
        XCTAssertEqual(AreaFrame.reach(on: tiny), 3, "a third of the shorter side")
        XCTAssertNil(AreaFrame.handle(of: tiny, at: CGPoint(x: 104.5, y: 104.5)), "the middle of a small area was taken")
        XCTAssertEqual(AreaFrame.handle(of: tiny, at: CGPoint(x: 100, y: 100)), .topLeft)
        XCTAssertEqual(AreaFrame.handle(of: tiny, at: CGPoint(x: 109, y: 109)), .bottomRight)
        XCTAssertNil(AreaFrame.handle(of: tiny, at: CGPoint(x: 104.5, y: 100)), "the middle of a tiny area's edge is not offered, and not drawn")
        for size in [CGFloat(1), 0.5, 0] {
            let sliver = CGRect(x: 10, y: 10, width: size, height: size)
            _ = AreaFrame.handle(of: sliver, at: CGPoint(x: 10, y: 10))
            XCTAssertGreaterThanOrEqual(AreaFrame.reach(on: sliver), 0)
        }
    }

    func testAnObjectsHandleWinsWhereItOverlapsAnAreaHandle() {
        // A rectangle whose corner is the area's corner: the press is the object's.
        let object = Annotation(tool: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 200), id: 1)
        XCTAssertEqual(AreaFrame.handle(of: area, at: CGPoint(x: 100, y: 100)), .topLeft, "no object: the area's")
        XCTAssertNil(AreaFrame.handle(of: area, at: CGPoint(x: 100, y: 100), yieldingTo: object), "the object's corner lost to the area")
        XCTAssertNil(AreaFrame.handle(of: area, at: CGPoint(x: 103, y: 103), yieldingTo: object), "within the object's reach too")
        // Where the object has none, the area's is taken even with the object selected.
        XCTAssertEqual(AreaFrame.handle(of: area, at: CGPoint(x: 300, y: 100), yieldingTo: object), .top)
        XCTAssertNotNil(AnnotationHit.handle(of: object, at: CGPoint(x: 100, y: 100)), "the subject: the object has a handle there")
    }

    // MARK: Reshaping

    func testEachHandleMovesItsOwnEdgesByThePointersTravelAndNoJumpAtThePress() {
        let table: [(AreaHandle, CGRect)] = [
            (.topLeft, CGRect(x: 110, y: 106, width: 390, height: 294)), (.top, CGRect(x: 100, y: 106, width: 400, height: 294)),
            (.topRight, CGRect(x: 100, y: 106, width: 410, height: 294)), (.right, CGRect(x: 100, y: 100, width: 410, height: 300)),
            (.bottomRight, CGRect(x: 100, y: 100, width: 410, height: 306)), (.bottom, CGRect(x: 100, y: 100, width: 400, height: 306)),
            (.bottomLeft, CGRect(x: 110, y: 100, width: 390, height: 306)), (.left, CGRect(x: 110, y: 100, width: 390, height: 300)),
        ]
        for (handle, expected) in table {
            let held = AreaFrame.handles(of: area).first { $0.handle == handle }!.point
            let press = CGPoint(x: held.x + 4, y: held.y - 3) // not on the centre
            let moved = CGPoint(x: press.x + 10, y: press.y + 6)
            XCTAssertEqual(AreaFrame.resized(area, handle, from: press, to: press, within: bounds), area, "\(handle): the press alone moved it")
            XCTAssertEqual(AreaFrame.resized(area, handle, from: press, to: moved, within: bounds), expected, "\(handle)")
        }
    }

    func testADragPastTheOppositeSideMirrorsAndOneToNothingIsRefusedAndTheDisplayHoldsIt() {
        let right = AreaFrame.handles(of: area).first { $0.handle == .right }!.point
        let mirrored = AreaFrame.resized(area, .right, from: right, to: CGPoint(x: 40, y: right.y), within: bounds)
        XCTAssertEqual(mirrored, CGRect(x: 40, y: 100, width: 60, height: 300))
        XCTAssertNil(AreaFrame.resized(area, .right, from: right, to: CGPoint(x: 100.5, y: right.y), within: bounds), "an area under a point wide")
        XCTAssertEqual(AreaFrame.resized(area, .right, from: right, to: CGPoint(x: 5000, y: right.y), within: bounds)?.maxX, 1000)
        let corner = AreaFrame.handles(of: area).first { $0.handle == .bottomLeft }!.point
        XCTAssertEqual(AreaFrame.resized(area, .bottomLeft, from: corner, to: CGPoint(x: -50, y: 900), within: bounds),
                       CGRect(x: 0, y: 100, width: 500, height: 700))
        XCTAssertNil(AreaFrame.resized(area, .right, from: right, to: CGPoint(x: CGFloat.nan, y: 0), within: bounds))
        // A selection against the display's edge pulled outward does not leave the display.
        let whole = AreaFrame.resized(bounds, .topLeft, from: .zero, to: CGPoint(x: -30, y: -30), within: bounds)
        XCTAssertEqual(whole, bounds)
    }

    // MARK: The arrows

    func testAStepIsOnePixelOfTheDisplayAndTenWithShiftAtOneTimesAndTwoTimes() {
        XCTAssertEqual(AreaFrame.step(CGPoint(x: 1, y: 0), pixels: 1, scale: 1), CGPoint(x: 1, y: 0))
        XCTAssertEqual(AreaFrame.step(CGPoint(x: 1, y: 0), pixels: 1, scale: 2), CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(AreaFrame.step(CGPoint(x: 0, y: -1), pixels: 10, scale: 1), CGPoint(x: 0, y: -10))
        XCTAssertEqual(AreaFrame.step(CGPoint(x: 0, y: -1), pixels: 10, scale: 2), CGPoint(x: 0, y: -5))
        for scale in [CGFloat(0), -1, CGFloat.nan, CGFloat.infinity] {
            XCTAssertEqual(AreaFrame.step(CGPoint(x: 1, y: 1), pixels: 10, scale: scale), .zero, "scale \(scale)")
        }
    }

    func testTheAreaNudgedAgainstAnEdgeIsShortenedAndKeepsItsSize() {
        let corner = CGRect(x: 3, y: 2, width: 100, height: 50)
        XCTAssertEqual(AreaFrame.nudged(corner, by: CGPoint(x: -10, y: -10), within: bounds), CGRect(x: 0, y: 0, width: 100, height: 50))
        let far = CGRect(x: 897, y: 748, width: 100, height: 50)
        XCTAssertEqual(AreaFrame.nudged(far, by: CGPoint(x: 10, y: 10), within: bounds), CGRect(x: 900, y: 750, width: 100, height: 50))
        XCTAssertEqual(AreaFrame.nudged(area, by: CGPoint(x: 0.5, y: 0), within: bounds), area.offsetBy(dx: 0.5, dy: 0))
        XCTAssertEqual(AreaFrame.nudged(area, by: CGPoint(x: CGFloat.nan, y: CGFloat.nan), within: bounds), area)
    }

    // MARK: The object under the arrows, and the undo

    /// One rectangle, selected by a click on its edge.
    private func selectedRectangle() -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: area)
        editing.begin(.rectangle, at: CGPoint(x: 200, y: 200), style: .standard)
        editing.drag(to: CGPoint(x: 300, y: 260), shift: false)
        editing.end()
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "nothing was selected, so a nudge below is of nothing")
        return editing
    }

    func testAHeldArrowIsOneUndoStepAndTheLeftoverIsTheDrawingItself() {
        var editing = selectedRectangle()
        let start = editing.selected!.frame
        for _ in 0..<200 { XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 1, y: 0))) }
        XCTAssertEqual(editing.selected!.frame, start.offsetBy(dx: 200, dy: 0), "the run did not carry the object 200 points")
        editing.undo()
        XCTAssertEqual(editing.selected?.frame, start, "200 presses were more than one step")
        XCTAssertEqual(editing.layers.count, 1, "the undo went past the nudge into the drawing")
        editing.redo()
        XCTAssertNotEqual(editing.selected?.frame, start, "redo did not bring the nudge back")
    }

    func testAnyOtherInputBetweenTwoRunsSplitsThemIntoTwoSteps() {
        var editing = selectedRectangle()
        let start = editing.selected!.frame
        for _ in 0..<3 { _ = editing.nudgeSelected(by: CGPoint(x: 1, y: 0)) }
        editing.recolor(.blue) // another input
        for _ in 0..<3 { _ = editing.nudgeSelected(by: CGPoint(x: 1, y: 0)) }
        XCTAssertEqual(editing.selected!.frame, start.offsetBy(dx: 6, dy: 0))
        editing.undo() // the second run
        XCTAssertEqual(editing.selected!.frame, start.offsetBy(dx: 3, dy: 0))
        editing.undo() // the recolour
        editing.undo() // the first run
        XCTAssertEqual(editing.selected!.frame, start)
        XCTAssertEqual(editing.layers.count, 1)
        // Directions are one run: the key is the same input whichever way it points.
        editing.disarm()
        _ = editing.nudgeSelected(by: CGPoint(x: 1, y: 0))
        _ = editing.nudgeSelected(by: CGPoint(x: 0, y: 4))
        editing.undo()
        XCTAssertEqual(editing.selected!.frame, start, "a second direction was a second step")
    }

    func testADragMoveNeverReversesOrLengthensWhatTheAreaLeftOutside() {
        // The rectangle stands at 200...300; the area is pulled in to end at x = 250, so it overhangs.
        var editing = selectedRectangle()
        editing.reshape(bounds: CGRect(x: 100, y: 100, width: 150, height: 300))
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.drag(to: CGPoint(x: 201, y: 230), shift: false)
        XCTAssertEqual(editing.selected!.frame.minX, 201, accuracy: 0.001, "one point asked, one point moved: not thrown into the area")
        editing.drag(to: CGPoint(x: 240, y: 230), shift: false)
        XCTAssertEqual(editing.selected!.frame.minX, 240, accuracy: 0.001, "away from the wall it has crossed the move is as asked")
        editing.drag(to: CGPoint(x: 100, y: 230), shift: false)
        XCTAssertEqual(editing.selected!.frame.minX, 100, accuracy: 0.001, "toward the area, held by the wall it reaches")
        editing.end()
    }

    func testADragMoveOfAnObjectInsideStillStopsAtTheWalls() {
        var editing = selectedRectangle()
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 230), tool: nil))
        editing.drag(to: CGPoint(x: 5000, y: 230), shift: false)
        editing.end()
        XCTAssertEqual(editing.selected!.frame.maxX, area.maxX, accuracy: 0.001)
    }

    func testANudgeAgainstTheWallIsNoStepAndTheObjectStaysInsideTheArea() {
        var editing = selectedRectangle()
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 5000, y: 5000)))
        XCTAssertEqual(editing.selected!.frame.maxX, area.maxX)
        XCTAssertEqual(editing.selected!.frame.maxY, area.maxY)
        let before = editing.layers
        let undoable = editing.canUndo
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 1, y: 1)), "an object at the wall is still the one the arrows are for")
        XCTAssertEqual(editing.layers, before)
        XCTAssertEqual(editing.canUndo, undoable)
        // A press that moved nothing does not open a step: the next one that moves does.
        var fresh = selectedRectangle()
        XCTAssertTrue(fresh.nudgeSelected(by: CGPoint(x: CGFloat.nan, y: 0)))
        XCTAssertEqual(fresh.layers.count, 1)
        fresh.undo()
        XCTAssertEqual(fresh.layers.count, 0, "a nudge that moved nothing took an undo step")
    }

    func testWithNothingSelectedTheArrowsAreTheAreasAndReshapingIsNoUndoStep() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertFalse(editing.nudgeSelected(by: CGPoint(x: 1, y: 0)), "nothing is selected, so the caller moves the area")
        var drawn = selectedRectangle()
        let steps = drawn.canUndo
        let layers = drawn.layers
        drawn.reshape(bounds: CGRect(x: 250, y: 220, width: 40, height: 30))
        XCTAssertEqual(drawn.bounds, CGRect(x: 250, y: 220, width: 40, height: 30))
        XCTAssertEqual(drawn.layers, layers, "the layers moved with the area")
        XCTAssertEqual(drawn.canUndo, steps)
        XCTAssertFalse(drawn.canRedo)
    }

    // MARK: The file

    func testTheFileIsTheReshapedAreaAndALayerOverItsEdgeIsCutByIt() async throws {
        let rig = Rig(home: scratchDirectory("shots-area-reshaped"))
        let image = makeImage(width: 2000, height: 1600, red: 255, green: 255, blue: 255)
        let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: bounds, scale: 2, image: image))], windows: [])
        let held = AreaFrame.handles(of: area).first { $0.handle == .right }!.point
        let narrower = try XCTUnwrap(AreaFrame.resized(area, .right, from: held, to: CGPoint(x: 300, y: held.y), within: bounds))
        XCTAssertEqual(narrower, CGRect(x: 100, y: 100, width: 200, height: 300))
        // A filled box from x = 150 to 450: 150 points of it inside the new area, the rest beyond its edge.
        let box = Annotation(tool: .rectangle, start: CGPoint(x: 150, y: 150), end: CGPoint(x: 450, y: 250),
                             style: AnnotationStyle(filled: true), id: 1)
        let drawn = await rig.session.annotated(freeze, display: DisplayID(1), local: narrower, layers: [box])
        let file = try XCTUnwrap(drawn)
        XCTAssertEqual(file.width, 400, "the file is not the new area's 200 points at 2x")
        XCTAssertEqual(file.height, 600)
        let context = try XCTUnwrap(CGContext(data: nil, width: file.width, height: file.height, bitsPerComponent: 8,
                                              bytesPerRow: file.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(file, in: CGRect(x: 0, y: 0, width: file.width, height: file.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        func green(_ x: Int, _ y: Int) -> UInt8 { bytes[y * file.width * 4 + x * 4 + 1] }
        XCTAssertGreaterThan(green(50, 200), 250, "outside the box: the picture")
        XCTAssertLessThan(green(110, 200), 100, "inside the box: its ink, which is red, has no green")
        XCTAssertLessThan(green(file.width - 1, 200), 100, "the last column of the file is the box, cut where the area ends")
    }
}
