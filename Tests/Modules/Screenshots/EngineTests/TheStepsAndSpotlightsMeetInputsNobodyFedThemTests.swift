import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Steps and spotlights, fed what the stage's own tests did not feed them.** A thousand steps, steps among undone layers of other
/// tools, a step restyled and erased and brought back twice, two on one point, a point that is no number; spotlights with no box,
/// a box that is no number, one outside the area, one over the whole of it, two that abut on a whole and a half point, two hundred
/// of them. Each is a layer list judged by what a person reads off it: the numbers in the list, the pixels of the file, and
/// what the editing does with a press.
///
/// What it would print if it failed totally: a number kept on a layer reads 1 2 3 after an undo of a neighbour; a dim that draws
/// each spotlight on its own leaves a line of 0.58² where two abut; a dim that is built from the unusable boxes darkens the area
/// for a spotlight nobody can see.
final class TheStepsAndSpotlightsMeetInputsNobodyFedThemTests: XCTestCase {

    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let area = CGRect(x: 0, y: 0, width: 300, height: 200)

    private func place(_ editing: inout AnnotationEditing, at point: CGPoint, tool: AnnotationTool = .step,
                       style: AnnotationStyle = .standard) {
        XCTAssertTrue(editing.press(at: point, tool: tool, style: style))
        editing.end()
    }

    private func numbers(_ editing: AnnotationEditing) -> [Int] { AnnotationStep.numbers(in: editing.layers).compactMap { $0 } }

    private func ground(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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

    private func light(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, id: Int = 1) -> Annotation {
        Annotation(tool: .spotlight, start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), id: id)
    }

    // MARK: Steps

    func testAThousandStepsAreNumberedOneToAThousandAndTheExportDrawsThemAll() throws {
        let big = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var editing = AnnotationEditing(bounds: big)
        for index in 0..<1000 { place(&editing, at: CGPoint(x: 10 + (index % 90) * 10, y: 10 + (index / 90) * 20)) }
        XCTAssertEqual(numbers(editing), Array(1...1000), "a thousand clicks are not a thousand numbered steps")
        let picture = try ground(width: 1000, height: 800)
        let started = Date()
        let file = try XCTUnwrap(CaptureSession.draw(editing.layers, over: picture, at: .zero, scale: 1, display: picture))
        let took = Date().timeIntervalSince(started)
        XCTAssertLessThan(took, 5, "exporting a thousand steps took \(took) s")
        let was = try bytes(picture), now = try bytes(file)
        XCTAssertNotEqual(was, now, "a thousand steps left the picture as it was")
        // The thousandth, four digits in a 20 pt circle, has ink inside its own circle and none outside its box.
        let last = AnnotationStep.frame(of: editing.layers[999])
        var inside = 0
        for y in Int(last.minY)..<Int(last.maxY) {
            for x in Int(last.minX)..<Int(last.maxX) where (0..<3).contains(where: { now[(y * 1000 + x) * 4 + $0] != was[(y * 1000 + x) * 4 + $0] }) { inside += 1 }
        }
        XCTAssertGreaterThan(inside, 100, "the thousandth step left no ink in its box")
    }

    func testAnUndoOfAnotherToolsLayerBetweenStepsChangesNoNumberOfAStep() {
        var editing = AnnotationEditing(bounds: area)
        place(&editing, at: CGPoint(x: 40, y: 40))
        editing.begin(.rectangle, at: CGPoint(x: 100, y: 60))
        editing.drag(to: CGPoint(x: 200, y: 120), shift: false)
        editing.end()
        place(&editing, at: CGPoint(x: 250, y: 160))
        XCTAssertEqual(numbers(editing), [1, 2])
        editing.undo()
        XCTAssertEqual(numbers(editing), [1], "the undo took the second step")
        editing.undo()
        XCTAssertEqual(editing.layers.map(\.tool), [.step])
        XCTAssertEqual(numbers(editing), [1], "the rectangle undone renumbered a step")
        editing.redo()
        editing.redo()
        XCTAssertEqual(editing.layers.map(\.tool), [.step, .rectangle, .step])
        XCTAssertEqual(numbers(editing), [1, 2])
    }

    func testAStepMadeThickerKeepsItsNumberAndItsPlaceAndUndoGivesTheOldSizeBack() {
        var editing = AnnotationEditing(bounds: area)
        place(&editing, at: CGPoint(x: 60, y: 100))
        place(&editing, at: CGPoint(x: 150, y: 100))
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 100), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[0].id)
        let before = editing.layers[0]
        editing.setThickness(.thick)
        XCTAssertEqual(AnnotationStep.frame(of: editing.layers[0]).width, 28)
        XCTAssertEqual(editing.layers[0].start, before.start, "the step moved with its size")
        XCTAssertEqual(numbers(editing), [1, 2])
        XCTAssertTrue(editing.canUndo)
        editing.undo()
        XCTAssertEqual(editing.layers[0], before)
        XCTAssertEqual(AnnotationStep.frame(of: editing.layers[0]).width, 20)
        editing.undo()
        XCTAssertEqual(numbers(editing), [1], "the second undo did not take the second step")
    }

    func testAStepErasedAndUndoneTwiceLeavesTheRightOnes() {
        var editing = AnnotationEditing(bounds: area)
        for x in [60, 150, 240] as [CGFloat] { place(&editing, at: CGPoint(x: x, y: 100)) }
        let three = editing.layers
        editing.beginErase(at: CGPoint(x: 150, y: 100), radius: 9)
        editing.end()
        XCTAssertEqual(numbers(editing), [1, 2])
        editing.undo()
        XCTAssertEqual(editing.layers, three, "the first undo did not bring the erased step back")
        editing.undo()
        XCTAssertEqual(editing.layers, Array(three.prefix(2)), "the second undo took something else than the third step")
        XCTAssertEqual(numbers(editing), [1, 2])
        editing.redo()
        editing.redo()
        XCTAssertEqual(numbers(editing), [1, 2], "the redos did not end in the erased state")
    }

    func testTwoStepsOnOnePointAreOneAndTwoAndAPressTakesTheUpperOne() {
        var editing = AnnotationEditing(bounds: area)
        place(&editing, at: CGPoint(x: 100, y: 100))
        place(&editing, at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(numbers(editing), [1, 2])
        XCTAssertNotEqual(editing.layers[0].id, editing.layers[1].id)
        XCTAssertTrue(editing.press(at: CGPoint(x: 100, y: 100), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[1].id, "the press took the lower of two steps")
        editing.deleteSelected()
        XCTAssertEqual(numbers(editing), [1])
        XCTAssertTrue(editing.press(at: CGPoint(x: 100, y: 100), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "the remaining step is not there to be taken")
    }

    func testAPressThatIsNoNumberPlacesNoStepAndLeavesNothingOpen() {
        var editing = AnnotationEditing(bounds: area)
        for point in [CGPoint(x: CGFloat.nan, y: 10), CGPoint(x: 10, y: CGFloat.infinity), CGPoint(x: -CGFloat.infinity, y: CGFloat.nan)] {
            XCTAssertTrue(editing.press(at: point, tool: .step))
            editing.end()
        }
        XCTAssertTrue(editing.layers.isEmpty)
        XCTAssertFalse(editing.canUndo)
        XCTAssertFalse(editing.isBusy)
        // A drag whose pointer is no number goes nowhere either.
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 50), tool: .step))
        editing.drag(to: CGPoint(x: CGFloat.nan, y: .nan), shift: false)
        editing.end()
        for layer in editing.layers {
            XCTAssertTrue(layer.start.x.isFinite && layer.start.y.isFinite, "a step stands where no number is: \(layer.start)")
            XCTAssertTrue(area.contains(layer.start), "a step's centre is outside the area: \(layer.start)")
        }
    }

    // MARK: Spotlights

    func testABoxThatIsNoBoxLeavesNoDimAndNoLayer() {
        var editing = AnnotationEditing(bounds: area)
        // Zero width, zero height, one point and a NaN corner: none is a spotlight.
        for (from, to) in [(CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 150)), (CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50)),
                           (CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50)), (CGPoint(x: 50, y: 50), CGPoint(x: CGFloat.nan, y: 90)),
                           (CGPoint(x: 50, y: 50), CGPoint(x: 50.4, y: 150))] {
            XCTAssertTrue(editing.press(at: from, tool: .spotlight))
            editing.drag(to: to, shift: false)
            editing.end()
        }
        XCTAssertTrue(editing.layers.filter { $0.tool == .spotlight }.isEmpty, "a box with no area became a spotlight: \(editing.layers)")
        XCTAssertNil(Spotlights.dim(of: editing.layers, within: area))
        let broken = [light(0, 0, CGFloat.nan, 50), light(10, 10, 10, 90), light(10, 10, 40, 10.4), light(CGFloat.infinity, 0, 20, 20)]
        XCTAssertNil(Spotlights.dim(of: broken, within: area), "a box that is no box made a dim")
    }

    func testASpotlightWhollyOutsideTheAreaDimsTheAreaOnceAndTheFileHasNoSeam() throws {
        let layers = [light(400, 10, 500, 90)]
        let picture = try ground(width: 300, height: 200)
        let file = try XCTUnwrap(CaptureSession.draw(layers, over: picture, at: .zero, scale: 1, display: picture))
        let now = try bytes(file)
        let dimmed = 0.8 * 255 * (1 - Double(Spotlights.dimAlpha))
        for (x, y) in [(0, 0), (150, 100), (299, 199), (10, 190)] {
            XCTAssertEqual(Double(now[(y * 300 + x) * 4]), dimmed, accuracy: 2, "(\(x),\(y)) is not dimmed once")
        }
    }

    func testASpotlightOverTheWholeAreaDimsNothingAndIsStillOneThatCanBePickedAndDeleted() throws {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertTrue(editing.press(at: CGPoint(x: 0, y: 0), tool: .spotlight))
        editing.drag(to: CGPoint(x: 300, y: 200), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.filter { $0.tool == .spotlight }.count, 1)
        let picture = try ground(width: 300, height: 200)
        let file = try XCTUnwrap(CaptureSession.draw(editing.layers, over: picture, at: .zero, scale: 1, display: picture))
        let (was, now) = (try bytes(picture), try bytes(file))
        var changed = 0
        for y in 12..<188 { for x in 12..<288 where now[(y * 300 + x) * 4] != was[(y * 300 + x) * 4] { changed += 1 } }
        XCTAssertEqual(changed, 0, "a spotlight over the whole area dimmed \(changed) pixels inside it")
        // Taken by its edge, which is the area's: the press on the wall takes it, and Delete takes it away.
        XCTAssertTrue(editing.press(at: CGPoint(x: 0, y: 100), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected, "a spotlight over the whole area cannot be picked by its edge")
        editing.deleteSelected()
        XCTAssertTrue(editing.layers.isEmpty)
    }

    func testTwoSpotlightsThatAbutOnAWholeAndOnAHalfPointLeaveNoSeamInTheFile() throws {
        for scale in [CGFloat(1), 2] {
            for seam in [150, 150.5, 150.25] as [CGFloat] {
                let layers = [light(40, 40, seam, 160, id: 1), light(seam, 40, 260, 160, id: 2)]
                let picture = try ground(width: Int(300 * scale), height: Int(200 * scale))
                let file = try XCTUnwrap(CaptureSession.draw(layers, over: picture, at: .zero, scale: scale, display: picture))
                let (was, now) = (try bytes(picture), try bytes(file))
                // The columns across the seam, in the rows well away from the round corners.
                var worst = 0
                var where_ = ""
                for y in Int(70 * scale)..<Int(130 * scale) {
                    for x in Int((seam - 3) * scale)...Int((seam + 3) * scale) {
                        let gap = abs(Int(now[(y * file.width + x) * 4]) - Int(was[(y * file.width + x) * 4]))
                        if gap > worst { worst = gap; where_ = "(\(x),\(y))" }
                    }
                }
                XCTAssertLessThanOrEqual(worst, 1, "\(scale)x seam at \(seam): a line of dim \(worst) at \(where_) between two abutting spotlights")
            }
        }
    }

    func testTwoHundredSpotlightsMakeOneDimInTimeAndEveryPointOfTheirUnionIsBright() throws {
        let big = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var lights: [Annotation] = []
        for index in 0..<200 {
            let (x, y) = (CGFloat((index * 37) % 900), CGFloat((index * 53) % 700))
            lights.append(light(x, y, x + 120, y + 90, id: index))
        }
        let started = Date()
        let dim = try XCTUnwrap(Spotlights.dim(of: lights, within: big))
        let took = Date().timeIntervalSince(started)
        XCTAssertLessThan(took, 2, "the dim of two hundred spotlights took \(took) s")
        // The centre of every spotlight is lit: not in the dim's even-odd fill.
        for layer in lights {
            let centre = CGPoint(x: (layer.start.x + layer.end.x) / 2, y: (layer.start.y + layer.end.y) / 2)
            XCTAssertFalse(dim.contains(centre, using: .evenOdd), "the middle of spotlight \(layer.id) is dimmed")
        }
    }

    func testASpotlightLeftOutsideByACropIsTakenByNothingAndThePressThatMissesLeavesNoGestureOpen() {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertTrue(editing.press(at: CGPoint(x: 20, y: 20), tool: .spotlight))
        editing.drag(to: CGPoint(x: 120, y: 100), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
        editing.reshape(bounds: CGRect(x: 200, y: 100, width: 100, height: 100))
        // The spotlight is wholly outside the new area: the dim is the whole area and no press can reach the layer to take it away.
        XCTAssertNotNil(Spotlights.dim(of: editing.layers, within: CGRect(x: 200, y: 100, width: 100, height: 100)))
        XCTAssertTrue(editing.press(at: CGPoint(x: 20, y: 60), tool: nil))
        editing.end()
        XCTAssertFalse(editing.isBusy)
    }
}
