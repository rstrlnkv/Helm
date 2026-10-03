import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A step's number is its place among the steps, and nothing is stored.** Three steps are 1, 2 and 3; the second one
/// taken away by Delete or by the eraser leaves 1 and 2, and an undo brings 1, 2 and 3 back, in the list and in the file,
/// with no code that renumbers. Layers of other tools between the steps are not counted. A click places a step, one undo
/// step each; a click outside the area, or Esc in the middle of one, places none. The count goes on past 99 and the digit
/// shrinks to stay in its circle (from 99 in the two thinner circles, from 100 in the thickest; 10 is at the full size in all three): three digits are still legible in the thinnest one, more are specks that stay inside.
///
/// What it would print if it failed totally: a number kept on the layer reads 1, 2, 3 after the delete (and 3 is not 2 in the
/// file); numbers decided in the drawing and not in the list make the file's second step the same pixels as its third.
final class TheStepsAreNumberedByTheirOrderTests: XCTestCase {

    private let area = CGRect(x: 0, y: 0, width: 300, height: 200)
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private func place(_ editing: inout AnnotationEditing, at point: CGPoint, style: AnnotationStyle = .standard) {
        XCTAssertTrue(editing.press(at: point, tool: .step, style: style))
        editing.end()
    }

    /// Three steps at x 60, 150 and 240 on one row.
    private func three() -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: area)
        for x in [60, 150, 240] as [CGFloat] { place(&editing, at: CGPoint(x: x, y: 100)) }
        XCTAssertEqual(editing.layers.count, 3, "the fixture placed fewer than three steps")
        return editing
    }

    private func numbers(_ editing: AnnotationEditing) -> [Int] {
        AnnotationStep.numbers(in: editing.layers).compactMap { $0 }
    }

    func testTheNumbersAreThePlacesAmongTheStepsOnly() {
        let mark = { (tool: AnnotationTool, id: Int) in
            Annotation(tool: tool, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 40, y: 30), id: id)
        }
        let layers = [mark(.rectangle, 1), mark(.step, 2), mark(.arrow, 3), mark(.step, 4), mark(.spotlight, 5), mark(.step, 6)]
        XCTAssertEqual(AnnotationStep.numbers(in: layers), [nil, 1, nil, 2, nil, 3])
        XCTAssertEqual(AnnotationStep.numbers(in: []), [])
        // Two steps made by hand with the same id are still 1 and 2: the place decides, not the id.
        XCTAssertEqual(AnnotationStep.numbers(in: [mark(.step, 0), mark(.step, 0)]), [1, 2])
    }

    func testAClickPlacesAStepAndEachIsOneUndoStep() {
        var editing = three()
        XCTAssertEqual(numbers(editing), [1, 2, 3])
        XCTAssertEqual(editing.layers.map(\.start.x), [60, 150, 240])
        editing.undo()
        XCTAssertEqual(numbers(editing), [1, 2], "one undo did not take exactly the last step")
        editing.redo()
        XCTAssertEqual(numbers(editing), [1, 2, 3])
    }

    func testDeletingTheMiddleOneLeavesOneAndTwoAndUndoBringsBackOneTwoThree() {
        var editing = three()
        let before = editing.layers
        XCTAssertTrue(editing.press(at: CGPoint(x: 150, y: 100), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, before[1].id, "the press did not take the middle step")
        editing.deleteSelected()
        XCTAssertEqual(numbers(editing), [1, 2], "after the delete the steps are not 1 and 2")
        XCTAssertEqual(editing.layers.map(\.id), [before[0].id, before[2].id])
        // The third step is the very value it was: its number is read from its place, so nothing was rewritten.
        XCTAssertEqual(editing.layers[1], before[2])
        editing.undo()
        XCTAssertEqual(editing.layers, before)
        XCTAssertEqual(numbers(editing), [1, 2, 3], "undo did not bring 1 2 3 back")
        editing.redo()
        XCTAssertEqual(numbers(editing), [1, 2])
    }

    func testTheEraserTakesTheMiddleOneAndTheRestAreRenumbered() {
        var editing = three()
        let before = editing.layers
        editing.beginErase(at: CGPoint(x: 150, y: 100), radius: 9)
        editing.end()
        XCTAssertEqual(editing.layers.map(\.id), [before[0].id, before[2].id])
        XCTAssertEqual(numbers(editing), [1, 2])
        editing.undo()
        XCTAssertEqual(numbers(editing), [1, 2, 3])
    }

    func testStepsMixedWithOtherLayersAreCountedAmongThemselves() {
        var editing = AnnotationEditing(bounds: area)
        place(&editing, at: CGPoint(x: 40, y: 40))
        editing.begin(.rectangle, at: CGPoint(x: 80, y: 20))
        editing.drag(to: CGPoint(x: 160, y: 90), shift: false)
        editing.end()
        place(&editing, at: CGPoint(x: 200, y: 40))
        editing.begin(.arrow, at: CGPoint(x: 20, y: 150))
        editing.drag(to: CGPoint(x: 120, y: 160), shift: false)
        editing.end()
        place(&editing, at: CGPoint(x: 250, y: 150))
        XCTAssertEqual(AnnotationStep.numbers(in: editing.layers), [1, nil, 2, nil, 3])
        // The rectangle and the arrow going changes no number; a step going changes the ones after it.
        editing.remove([editing.layers[1].id, editing.layers[3].id])
        XCTAssertEqual(AnnotationStep.numbers(in: editing.layers), [1, 2, 3])
        editing.remove([editing.layers[0].id])
        XCTAssertEqual(AnnotationStep.numbers(in: editing.layers), [1, 2])
    }

    func testAStepIsTakenByItsAreaAndMovedWithItsCircleInsideTheArea() {
        var editing = three()
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 104), tool: nil), "a press inside the circle did not take it")
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[0].id)
        XCTAssertTrue(editing.selected?.handles.isEmpty == true, "a step has no handles")
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: -500, y: 0)))
        let radius = AnnotationThickness.medium.points(for: .step) / 2
        XCTAssertEqual(editing.layers[0].start.x, radius, accuracy: 0.001, "the move did not stop with the circle at the area's wall")
        XCTAssertEqual(editing.layers[0].frame.minX, 0, accuracy: 0.001)
    }

    func testAClickOutsideTheAreaPlacesNothingAndAClickOnAnotherLayerStillPlaces() {
        var editing = AnnotationEditing(bounds: CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 150), tool: .step))
        editing.end()
        XCTAssertTrue(editing.layers.isEmpty, "a click outside the area placed a step on its edge")
        XCTAssertFalse(editing.canUndo)
        editing.begin(.rectangle, at: CGPoint(x: 120, y: 120))
        editing.drag(to: CGPoint(x: 260, y: 180), shift: false)
        editing.end()
        // On the rectangle's edge: with a tool a click on a layer is a step, where for the other tools it is a selection.
        place(&editing, at: CGPoint(x: 120, y: 150))
        XCTAssertEqual(editing.layers.map(\.tool), [.rectangle, .step])
    }

    func testTheCircleFollowsThePointerUntilTheReleaseAndEscDropsIt() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 50), tool: .step))
        editing.drag(to: CGPoint(x: 120, y: 90), shift: false)
        XCTAssertEqual(editing.draft?.start, CGPoint(x: 120, y: 90))
        editing.drag(to: CGPoint(x: 400, y: -20), shift: false)
        XCTAssertEqual(editing.draft?.start, CGPoint(x: 300, y: 0), "the circle left the area")
        XCTAssertEqual(editing.escape(), .dropped)
        XCTAssertTrue(editing.layers.isEmpty)
        XCTAssertFalse(editing.canUndo, "a dropped step left an undo step")
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 50), tool: .step))
        editing.drag(to: CGPoint(x: 120, y: 90), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.map(\.start), [CGPoint(x: 120, y: 90)])
    }

    // MARK: - The file

    private func ground(_ width: Int, _ height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.82, green: 0.86, blue: 0.9, alpha: 1))
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

    /// The pixels of `box` (points, top-left) of the file made from `layers`.
    private func file(_ layers: [Annotation], scale: CGFloat, box: CGRect) throws -> [UInt8] {
        let (width, height) = (Int(300 * scale), Int(200 * scale))
        let picture = try ground(width, height)
        let made = try XCTUnwrap(CaptureSession.draw(layers, over: picture, at: .zero, scale: scale, display: picture))
        let all = try bytes(made)
        var part: [UInt8] = []
        for y in Int(box.minY * scale)..<Int(box.maxY * scale) {
            for x in Int(box.minX * scale)..<Int(box.maxX * scale) { part += all[(y * width + x) * 4..<(y * width + x) * 4 + 4] }
        }
        return part
    }

    func testTheFileDrawsTheDigitThePlaceDecidesAndNotTheOneTheLayerWasPlacedAs() throws {
        let editing = three()
        let (first, middle, last) = (editing.layers[0], editing.layers[1], editing.layers[2])
        let box = last.frame.insetBy(dx: -3, dy: -3)
        let far = Annotation(tool: .step, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 30, y: 30), id: 40)
        for scale in [CGFloat(1), 2] {
            let third = try file([first, middle, last], scale: scale, box: box)
            let second = try file([first, last], scale: scale, box: box)
            let alsoSecond = try file([far, last], scale: scale, box: box)
            let only = try file([last], scale: scale, box: box)
            XCTAssertNotEqual(third, second, "\(scale)x: the last step reads the same as a third and as a second")
            XCTAssertEqual(second, alsoSecond, "\(scale)x: the digit depends on which step goes before it, not on how many")
            XCTAssertNotEqual(second, only, "\(scale)x: the last step reads the same as a second and as a first")
            XCTAssertNotEqual(third, only)
        }
    }

    /// A tile of step `number` in each thickness: nothing of it is outside its circle, and a digit is in it.
    func testPastNinetyNineTheCountGoesOnAndTheDigitStaysInsideItsCircle() throws {
        for scale in [CGFloat(1), 2] {
            for step in AnnotationThickness.allCases {
                for number in [1, 9, 10, 99, 100, 123, 999, 1000, 54321] {
                    let name = "\(Int(scale))x \(step) number \(number)"
                    let layer = Annotation(tool: .step, start: CGPoint(x: 40.3, y: 30.6), end: CGPoint(x: 40.3, y: 30.6),
                                           style: AnnotationStyle(color: .red, thickness: step), id: 1)
                    let tile = try XCTUnwrap(AnnotationStep.tile(of: layer, number: number, scale: scale), name)
                    let image = tile.image
                    let data = try bytes(image)
                    let circle = layer.frame
                    var outside = 0, light = 0
                    for y in 0..<image.height {
                        for x in 0..<image.width {
                            let at = (y * image.width + x) * 4
                            let point = CGPoint(x: (tile.pixels.minX + CGFloat(x) + 0.5) / scale, y: (tile.pixels.minY + CGFloat(y) + 0.5) / scale)
                            let away = hypot(point.x - circle.midX, point.y - circle.midY)
                            if away > circle.width / 2 + 1 / scale, data[at + 3] != 0 { outside += 1 }
                            // The digit is white on the red: a pixel that is bright in the blue channel, well inside the circle.
                            if away < circle.width / 2 - 1, data[at + 2] > 200, data[at + 3] == 255 { light += 1 }
                        }
                    }
                    XCTAssertEqual(outside, 0, "\(name): \(outside) pixels of ink outside the circle")
                    // Up to three digits the digit is there to read; four and five in the thinnest circle are specks, and stay in it.
                    if number < 1000 { XCTAssertGreaterThan(light, 4, "\(name): no digit in the circle (\(light) light pixels)") }
                }
            }
        }
    }

    /// The font size the drawing uses, measured: 9 and 10 are at 0.6 of the diameter in every circle (so the 20 pt circle of the frame
    /// shows a two-digit number at 12 pt), 99 is set a little smaller in the 16 and 20 pt circles and not in the 28 pt one, and 100 is
    /// set smaller in all three.
    func testTheDigitIsSetSmallerFromNinetyNineInTheThinnerCirclesAndFromAHundredInTheThickest() {
        let smaller: [AnnotationThickness: [Int]] = [.thin: [99, 100], .medium: [99, 100], .thick: [100]]
        XCTAssertEqual(Set(smaller.keys), Set(AnnotationThickness.allCases), "a thickness step is not measured here")
        for (step, expected) in smaller {
            let diameter = step.points(for: .step)
            let size = { AnnotationStep.digitSize(of: $0, diameter: diameter) }
            for number in [9, 10, 99, 100] {
                if expected.contains(number) {
                    XCTAssertLessThan(size(number), diameter * 0.6, "\(step): \(number) is not set smaller than 0.6 of the diameter")
                } else {
                    XCTAssertEqual(size(number), diameter * 0.6, accuracy: 0.0001, "\(step): \(number) is not at 0.6 of the diameter")
                }
            }
            XCTAssertLessThan(size(100), size(99), "\(step): 100 is not set smaller than 99")
        }
    }

    func testTheDigitIsWhiteOrBlackByWhichReadsOnTheInk() {
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        for ink in [AnnotationColor.red, .blue, .purple, .black] { XCTAssertEqual(AnnotationStep.digitColor(on: ink), white, "\(ink)") }
        for ink in [AnnotationColor.orange, .yellow, .green, .white] { XCTAssertEqual(AnnotationStep.digitColor(on: ink), black, "\(ink)") }
    }

    func testTheCirclesSizeIsTheThicknessStepsAndItsDigitStaysCentred() throws {
        for (step, diameter) in zip(AnnotationThickness.allCases, [16, 20, 28] as [CGFloat]) {
            let layer = Annotation(tool: .step, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 100),
                                   style: AnnotationStyle(color: .red, thickness: step), id: 1)
            XCTAssertEqual(layer.frame, CGRect(x: 100 - diameter / 2, y: 100 - diameter / 2, width: diameter, height: diameter))
            let tile = try XCTUnwrap(AnnotationStep.tile(of: layer, number: 8, scale: 2))
            let data = try bytes(tile.image)
            // The light pixels' box is centred on the circle's centre to a pixel.
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<tile.image.height { for x in 0..<tile.image.width where data[(y * tile.image.width + x) * 4 + 2] > 200 && data[(y * tile.image.width + x) * 4 + 3] == 255 {
                xs.append(x); ys.append(y)
            } }
            let midX = (CGFloat(xs.min()! + xs.max()! + 1) / 2 + tile.pixels.minX) / 2, midY = (CGFloat(ys.min()! + ys.max()! + 1) / 2 + tile.pixels.minY) / 2
            XCTAssertEqual(midX, 100, accuracy: 0.5, "\(step): the digit is not centred across")
            XCTAssertEqual(midY, 100, accuracy: 0.5, "\(step): the digit is not centred down")
        }
    }
}
