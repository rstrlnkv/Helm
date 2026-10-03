import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **The lens and the emoji, fed what the stage's own tests did not feed them.** An emoji at a point that is no number, at the area's
/// corners and far past them, of the Large step in an area smaller than itself, while another edit is under the pointer, three hundred of
/// them, and an emoji tool's press that reaches the engine as a drag. A lens of every diameter from nothing to the area's width (the eight
/// points that keep it, and the seven that do not), dragged and pulled by each corner to a grid of pointers that includes the ones
/// past the area and past the opposite corner, and to NaN and infinity; moved by a nudge that is no number; taken by its disc and not
/// by its square; beside the display's edge, over an area cropped away from it, with two lenses on one another, at a scale that is no number.
///
/// What it would print if it failed totally: a lens that is not forced to be a circle comes out of a pull as a wider than tall
/// ellipse (its width and height differ); one that is no longer held inside the area leaves its frame past the area's wall; an emoji
/// at NaN is a layer at NaN and a frame of NaN, which `CGRect` carries on without a word.
final class TheLensAndTheEmojiMeetInputsNobodyFedThemTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let area = CGRect(x: 0, y: 0, width: 200, height: 120)

    private func picture(width: Int, height: Int, scale: CGFloat = 1) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width) * scale, height: CGFloat(height) * scale))
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

    private func dragged(_ editing: inout AnnotationEditing, _ tool: AnnotationTool, _ from: CGPoint, _ to: CGPoint) {
        _ = editing.press(at: from, tool: tool)
        editing.drag(to: to, shift: false)
        editing.end()
    }

    private func isSquare(_ frame: CGRect) -> Bool { abs(frame.width - frame.height) < 0.001 }
    private func inside(_ frame: CGRect, _ bounds: CGRect) -> Bool { bounds.insetBy(dx: -0.001, dy: -0.001).contains(frame) }

    // MARK: The emoji

    func testAPointThatIsNoNumberPlacesNoEmojiAndAFarOneIsHeldInTheArea() {
        for point in [CGPoint(x: CGFloat.nan, y: 5), CGPoint(x: 5, y: CGFloat.nan), CGPoint(x: CGFloat.infinity, y: 5), CGPoint(x: 5, y: -CGFloat.infinity), CGPoint(x: CGFloat.nan, y: CGFloat.nan)] {
            var editing = AnnotationEditing(bounds: area)
            XCTAssertFalse(editing.place(emoji: "👍", at: point), "an emoji at \(point) was placed")
            XCTAssertTrue(editing.layers.isEmpty)
            XCTAssertFalse(editing.canUndo, "a refused emoji left a step")
        }
        for point in [CGPoint(x: 1e300, y: 1e300), CGPoint(x: -1e300, y: -1e300), CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0),
                      CGPoint(x: 1e9, y: -1e9), CGPoint(x: -5000, y: 60)] {
            var editing = AnnotationEditing(bounds: area)
            XCTAssertTrue(editing.place(emoji: "👍", at: point), "an emoji far away at \(point) was refused")
            let frame = editing.layers[0].frame
            XCTAssertTrue(inside(frame, area), "an emoji put at \(point) stands at \(frame), outside \(area)")
        }
    }

    func testEveryEdgeAndCornerHoldsTheWholeEmojiAtEachStep() {
        let points = [(0.0, 0.0), (200, 0), (0, 120), (200, 120), (100, 0), (100, 120), (0, 60), (200, 60), (1, 1), (199, 119), (100, 60)]
        for step in AnnotationThickness.allCases {
            for (x, y) in points {
                var editing = AnnotationEditing(bounds: area)
                XCTAssertTrue(editing.place(emoji: "🇫🇷", at: CGPoint(x: x, y: y), style: AnnotationStyle(thickness: step)))
                let frame = editing.layers[0].frame
                XCTAssertTrue(inside(frame, area), "\(step) at (\(x), \(y)): the frame \(frame) is outside the area")
                XCTAssertEqual(frame.width, CGFloat(step.points(for: .emoji)), accuracy: 40, "\(step): the frame's width \(frame.width) is not near the step's size")
                // Where there is room the middle is the point.
                if (frame.minX > 0.001 && frame.maxX < 199.999), (frame.minY > 0.001 && frame.maxY < 119.999) {
                    XCTAssertEqual(frame.midX, x, accuracy: 0.001)
                    XCTAssertEqual(frame.midY, y, accuracy: 0.001)
                }
            }
        }
    }

    func testTheLargeEmojiInAnAreaSmallerThanItStandsAtItsCornerAndTheFileIsTheCutsSize() throws {
        let tiny = CGRect(x: 50, y: 40, width: 20, height: 20)
        for scale in [CGFloat(1), 2] {
            var editing = AnnotationEditing(bounds: tiny)
            XCTAssertTrue(editing.place(emoji: "✅", at: CGPoint(x: 60, y: 50), style: AnnotationStyle(thickness: .thick)))
            let layer = editing.layers[0]
            XCTAssertGreaterThan(layer.frame.width, tiny.width, "control: the emoji is not larger than the area")
            XCTAssertEqual(layer.frame.origin.x, tiny.minX, accuracy: 0.001, "the emoji bigger than its area starts at the area's own left")
            XCTAssertEqual(layer.frame.origin.y, tiny.minY, accuracy: 0.001)
            let ground = try picture(width: 200, height: 120, scale: scale)
            let rect = CGRect(x: tiny.minX * scale, y: tiny.minY * scale, width: tiny.width * scale, height: tiny.height * scale)
            let cut = try XCTUnwrap(ground.cropping(to: rect))
            let file = try XCTUnwrap(CaptureSession.draw(editing.layers, over: cut, at: rect.origin, scale: scale, display: ground))
            XCTAssertEqual(file.width, cut.width)
            XCTAssertEqual(file.height, cut.height)
            let was = try bytes(cut), now = try bytes(file)
            XCTAssertGreaterThan(zip(was, now).filter { $0 != $1 }.count, 200, "\(Int(scale))x: the part of the emoji in the cut is not drawn")
        }
    }

    func testAnEmojiIsNotPlacedWhileAnotherEditIsUnderThePointer() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertTrue(editing.place(emoji: "👍", at: CGPoint(x: 50, y: 50)))
        // A move is open: pressing the layer with no tool takes it.
        XCTAssertTrue(editing.press(at: CGPoint(x: 50, y: 50), tool: nil))
        XCTAssertFalse(editing.place(emoji: "🔥", at: CGPoint(x: 150, y: 80)), "an emoji was placed in the middle of a move")
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
        // A draft is open.
        XCTAssertTrue(editing.press(at: CGPoint(x: 100, y: 20), tool: .rectangle))
        editing.drag(to: CGPoint(x: 150, y: 70), shift: false)
        XCTAssertFalse(editing.place(emoji: "🔥", at: CGPoint(x: 150, y: 80)), "an emoji was placed in the middle of a drawing")
        editing.end()
        XCTAssertEqual(editing.layers.map(\.tool), [.emoji, .rectangle])
        XCTAssertTrue(editing.place(emoji: "🔥", at: CGPoint(x: 150, y: 100)), "control: with nothing open it is placed")
        editing.undo()
        editing.undo()
        XCTAssertEqual(editing.layers.map(\.tool), [.emoji], "each placement is one step")
    }

    func testTheEmojiToolsPressThatReachesTheEngineAsADragLeavesNoLayerAndNoStep() {
        var editing = AnnotationEditing(bounds: area)
        dragged(&editing, .emoji, CGPoint(x: 20, y: 20), CGPoint(x: 150, y: 90))
        XCTAssertTrue(editing.layers.isEmpty, "a drag of the emoji tool made a layer with no emoji in it")
        XCTAssertFalse(editing.canUndo)
        XCTAssertFalse(editing.isBusy)
        XCTAssertTrue(editing.place(emoji: "👍", at: CGPoint(x: 100, y: 60)), "the tool's draft left the editor busy")
    }

    func testAnEmojiHasNoHandlesIsTakenByItsAreaAndMovesAsOneStepInsideTheArea() {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertTrue(editing.place(emoji: "👍", at: CGPoint(x: 100, y: 60)))
        let layer = editing.layers[0]
        XCTAssertTrue(layer.handles.isEmpty)
        XCTAssertTrue(editing.takes(at: CGPoint(x: layer.frame.minX + 1, y: layer.frame.minY + 1)), "a press in the emoji's frame, on a transparent corner of it, is not the emoji's")
        XCTAssertFalse(editing.takes(at: CGPoint(x: layer.frame.maxX + 10, y: layer.frame.maxY + 10)))
        XCTAssertTrue(editing.press(at: CGPoint(x: 100, y: 60), tool: nil))
        editing.drag(to: CGPoint(x: CGFloat.nan, y: 80), shift: false)
        editing.drag(to: CGPoint(x: CGFloat.infinity, y: CGFloat.infinity), shift: false)
        editing.drag(to: CGPoint(x: 5000, y: 5000), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
        XCTAssertTrue(inside(editing.layers[0].frame, area), "a move past the area left the emoji at \(editing.layers[0].frame)")
        XCTAssertEqual(editing.layers[0].frame.size, layer.frame.size, "a move changed the emoji's size")
        editing.undo()
        XCTAssertEqual(editing.layers[0], layer, "the move is more than one step, or it is none")
        // The ink is not an emoji's: recolouring a selected one is no edit and no step.
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty)
        editing.redo()
        XCTAssertTrue(editing.press(at: CGPoint(x: 100, y: 60), tool: nil))
        editing.end()
        editing.recolor(.purple)
        XCTAssertEqual(editing.layers.count, 1)
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "the recolour was a step of its own: one undo left the emoji")
    }

    func testThreeHundredEmojiAreThreeHundredLayersTheExportDrawsAllInTime() throws {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        for index in 0..<300 {
            XCTAssertTrue(editing.place(emoji: EmojiSet.all[index % EmojiSet.all.count], at: CGPoint(x: 20 + (index % 30) * 25, y: 20 + (index / 30) * 50)))
        }
        XCTAssertEqual(editing.layers.count, 300)
        let ground = try picture(width: 800, height: 600)
        let started = Date()
        let file = try XCTUnwrap(CaptureSession.draw(editing.layers, over: ground, at: .zero, scale: 1, display: ground))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "three hundred emoji took too long to export")
        let now = try bytes(file), was = try bytes(ground)
        XCTAssertGreaterThan(zip(was, now).filter { $0 != $1 }.count, 30_000)
    }

    func testAnOpacityThatIsNoNumberDrawsAndBreaksNothing() throws {
        let ground = try picture(width: 200, height: 120)
        let was = try bytes(ground)
        for opacity in [Double.nan, .infinity, -1, 0, 2, 0.1] {
            let layer = Annotation(tool: .emoji, start: CGPoint(x: 80, y: 40), end: CGPoint(x: 80, y: 40),
                                   style: AnnotationStyle(color: .green, thickness: .medium, opacity: opacity), text: "👍", id: 1)
            let file = try XCTUnwrap(CaptureSession.draw([layer], over: ground, at: .zero, scale: 1, display: ground), "opacity \(opacity)")
            XCTAssertEqual(file.width, 200)
            let changed = zip(was, try bytes(file)).filter { $0 != $1 }.count
            // 0 and below draw nothing and the rest draw something: never a crash, never a layer of NaN in the file.
            // A NaN opacity cannot reach a layer (the overlay and the store both clamp it to full ink), so only that it breaks nothing is asked.
            if opacity.isNaN { continue }
            if opacity <= 0 { XCTAssertEqual(changed, 0, "opacity \(opacity) draws") } else {
                XCTAssertGreaterThan(changed, 0, "opacity \(opacity): the emoji is invisible")
            }
        }
    }

    // MARK: The lens

    func testTheLensKeepsEightPointsAndNotSeven() {
        for side in [0.0, 1, 7, 7.99, 8, 8.01, 9, 100] {
            var editing = AnnotationEditing(bounds: area)
            dragged(&editing, .magnifier, CGPoint(x: 10, y: 10), CGPoint(x: 10 + side, y: 10 + side))
            let kept = editing.layers.count
            XCTAssertEqual(kept, side >= 8 ? 1 : 0, "a lens dragged \(side) points across: \(kept) layers")
            XCTAssertEqual(editing.canUndo, side >= 8, "side \(side)")
            if let lens = editing.layers.first { XCTAssertEqual(lens.frame.width, CGFloat(side), accuracy: 0.001) }
        }
        // A drag past the area's far corner is held inside it, a circle still.
        var past = AnnotationEditing(bounds: area)
        dragged(&past, .magnifier, CGPoint(x: 10, y: 10), CGPoint(x: 209, y: 209))
        XCTAssertEqual(past.layers.first?.frame.width ?? 0, 110, accuracy: 0.001, "a lens dragged past the area's corner is \(String(describing: past.layers.first?.frame))")
        // A drag that is one thin strip is the circle of its longer side, and a strip under the diameter in both is none.
        var strip = AnnotationEditing(bounds: area)
        dragged(&strip, .magnifier, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 17))
        XCTAssertEqual(strip.layers.first?.frame.width ?? 0, 100, accuracy: 0.001, "a strip of 100 by 7 is not the circle of its longer side")
        var thin = AnnotationEditing(bounds: area)
        dragged(&thin, .magnifier, CGPoint(x: 10, y: 10), CGPoint(x: 17, y: 17.5))
        XCTAssertTrue(thin.layers.isEmpty)
    }

    func testEveryDragOfTheLensIsACircleInsideTheArea() {
        let starts = [CGPoint(x: 100, y: 60), CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 120), CGPoint(x: 5, y: 115), CGPoint(x: 195, y: 3)]
        let ends = stride(from: -60.0, through: 260, by: 40).flatMap { x in stride(from: -60.0, through: 180, by: 40).map { CGPoint(x: x, y: $0) } }
            + [CGPoint(x: CGFloat.nan, y: 50), CGPoint(x: 50, y: CGFloat.infinity), CGPoint(x: 1e300, y: -1e300)]
        for start in starts {
            for end in ends {
                var editing = AnnotationEditing(bounds: area)
                dragged(&editing, .magnifier, start, end)
                guard let lens = editing.layers.first else { continue }
                XCTAssertTrue(isSquare(lens.frame), "a lens dragged from \(start) to \(end) is \(lens.frame)")
                XCTAssertTrue(inside(lens.frame, area), "a lens dragged from \(start) to \(end) is \(lens.frame), outside the area")
                XCTAssertGreaterThanOrEqual(lens.frame.width, Magnifier.minimumDiameter - 0.001)
                XCTAssertEqual(editing.layers.count, 1)
            }
        }
    }

    func testEveryPullOfACornerKeepsACircleInsideTheAreaOrKeepsTheLens() {
        let from = CGPoint(x: 80, y: 40), to = CGPoint(x: 160, y: 120)
        let corners = [from, CGPoint(x: to.x, y: from.y), CGPoint(x: from.x, y: to.y), to]
        var pointers = stride(from: -60.0, through: 260, by: 40).flatMap { x in stride(from: -60.0, through: 180, by: 30).map { CGPoint(x: x, y: $0) } }
        pointers += [CGPoint(x: CGFloat.nan, y: 50), CGPoint(x: 50, y: CGFloat.nan), CGPoint(x: CGFloat.infinity, y: 50), CGPoint(x: 50, y: -CGFloat.infinity),
                     CGPoint(x: 1e300, y: 1e300), CGPoint(x: 120, y: 80), CGPoint(x: 83, y: 43), CGPoint(x: 80, y: 40)]
        for corner in corners {
            for pointer in pointers {
                var editing = AnnotationEditing(bounds: area)
                dragged(&editing, .magnifier, from, to)
                let before = editing.layers[0]
                XCTAssertTrue(editing.press(at: CGPoint(x: 120, y: 80), tool: nil), "the lens was not taken")
                editing.end()
                XCTAssertEqual(editing.selected?.id, before.id)
                XCTAssertTrue(editing.press(at: corner, tool: nil))
                editing.drag(to: pointer, shift: false)
                editing.end()
                XCTAssertEqual(editing.layers.count, 1, "corner \(corner) to \(pointer)")
                let lens = editing.layers[0]
                XCTAssertTrue(isSquare(lens.frame), "pulling \(corner) to \(pointer) made \(lens.frame)")
                XCTAssertTrue(inside(lens.frame, area), "pulling \(corner) to \(pointer) left the lens at \(lens.frame)")
                XCTAssertTrue(lens.isUsable, "pulling \(corner) to \(pointer) left an unusable lens \(lens.frame)")
                XCTAssertEqual(lens.id, before.id)
            }
        }
    }

    func testANudgeAndAMoveThatAreNoNumberLeaveTheLensWhereItIs() {
        var editing = AnnotationEditing(bounds: area)
        dragged(&editing, .magnifier, CGPoint(x: 80, y: 40), CGPoint(x: 160, y: 120))
        XCTAssertTrue(editing.press(at: CGPoint(x: 120, y: 80), tool: nil))
        editing.end()
        let before = editing.layers[0]
        for delta in [CGPoint(x: CGFloat.nan, y: 1), CGPoint(x: 1, y: CGFloat.infinity), CGPoint(x: -CGFloat.infinity, y: CGFloat.nan)] {
            _ = editing.nudgeSelected(by: delta)
            XCTAssertEqual(editing.layers[0].frame, before.frame, "a nudge by \(delta) moved the lens")
        }
        _ = editing.nudgeSelected(by: CGPoint(x: 1e300, y: -1e300))
        XCTAssertTrue(inside(editing.layers[0].frame, area), "a nudge of 1e300 took the lens out of the area: \(editing.layers[0].frame)")
        XCTAssertEqual(editing.layers[0].frame.width, before.frame.width, accuracy: 0.001)
    }

    func testTheLensIsTakenByItsDiscAndNotByItsSquare() {
        var editing = AnnotationEditing(bounds: area)
        dragged(&editing, .magnifier, CGPoint(x: 80, y: 40), CGPoint(x: 160, y: 120))
        XCTAssertTrue(editing.takes(at: CGPoint(x: 120, y: 80)), "the middle of the lens is not the lens's")
        XCTAssertTrue(editing.takes(at: CGPoint(x: 90, y: 80)), "the inside of the ring is not the lens's: it is taken by its edge")
        XCTAssertFalse(editing.takes(at: CGPoint(x: 83, y: 43)), "the corner of the lens's square, outside the circle, is the lens's")
        XCTAssertFalse(editing.takes(at: CGPoint(x: 165, y: 80)), "a point beside the lens is the lens's")
        // A mark under the lens is not taken through it; the lens is on top.
        var stacked = AnnotationEditing(bounds: area)
        dragged(&stacked, .rectangle, CGPoint(x: 100, y: 60), CGPoint(x: 140, y: 100))
        dragged(&stacked, .magnifier, CGPoint(x: 80, y: 40), CGPoint(x: 160, y: 120))
        XCTAssertTrue(stacked.press(at: CGPoint(x: 100, y: 80), tool: nil))
        XCTAssertEqual(stacked.selected?.tool, .magnifier, "the press on the lens took the box under it")
    }

    func testALensBesideTheDisplaysEdgeShowsTheSameThingAtTheSameSize() throws {
        for scale in [CGFloat(1), 2] {
            // The lens's centre 5 points from the top-left corner of the display: the half of its disc is off the picture.
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(200 * scale), height: Int(120 * scale), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200 * scale, height: 120 * scale))
            context.translateBy(x: 0, y: 120 * scale)
            context.scaleBy(x: scale, y: -scale)
            for centre in [CGPoint(x: 5, y: 5), CGPoint(x: 195, y: 115), CGPoint(x: 5, y: 115)] {
                context.setFillColor(CGColor(srgbRed: 0, green: 0.2, blue: 1, alpha: 1))
                context.fill(CGRect(x: centre.x + (centre.x > 100 ? -14 : 8), y: centre.y - 4, width: 6, height: 8))
            }
            let ground = try XCTUnwrap(context.makeImage())
            let px = try bytes(ground)
            for (centre, direction) in [(CGPoint(x: 5, y: 5), CGFloat(1)), (CGPoint(x: 195, y: 115), -1), (CGPoint(x: 5, y: 115), 1)] {
                // A layer made by hand: the editor would keep the circle inside the area, and the file is asked about a frame the display cuts.
                let lens = Annotation(tool: .magnifier, start: CGPoint(x: centre.x - 40, y: centre.y - 40), end: CGPoint(x: centre.x + 40, y: centre.y + 40), id: 1)
                let file = try bytes(try XCTUnwrap(CaptureSession.draw([lens], over: ground, at: .zero, scale: scale, display: ground), "\(centre)"))
                // The bar is eight to fourteen points toward the middle of the display: magnified, sixteen to twenty-eight.
                let x = centre.x + direction * 22, y = centre.y
                let at = (Int(y * scale) * ground.width + Int(x * scale)) * 4
                XCTAssertGreaterThan(Int(file[at + 2]) - Int(file[at]), 100, "\(Int(scale))x lens at \(centre): no blue at (\(x), \(y)): \(file[at...(at + 2)])")
                XCTAssertLessThan(abs(Int(file[at]) - Int(px[at])), 255)
                // Off the picture there is nothing to draw and nothing is.
                XCTAssertEqual(file.count, px.count)
            }
        }
    }

    func testALensThatIsNothingToDrawIsNotDrawn() throws {
        let ground = try picture(width: 200, height: 120)
        let was = try bytes(ground)
        let wholly = Annotation(tool: .magnifier, start: CGPoint(x: 500, y: 500), end: CGPoint(x: 600, y: 600), id: 1)
        let small = Annotation(tool: .magnifier, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 54, y: 54), id: 2)
        let nan = Annotation(tool: .magnifier, start: CGPoint(x: CGFloat.nan, y: 0), end: CGPoint(x: 50, y: 50), id: 3)
        let infinite = Annotation(tool: .magnifier, start: CGPoint(x: -CGFloat.infinity, y: 0), end: CGPoint(x: CGFloat.infinity, y: 50), id: 4)
        let huge = Annotation(tool: .magnifier, start: CGPoint(x: -1e9, y: -1e9), end: CGPoint(x: 1e9, y: 1e9), id: 5)
        for layer in [wholly, small, nan, infinite, huge] {
            let file = try XCTUnwrap(CaptureSession.draw([layer], over: ground, at: .zero, scale: 1, display: ground), "layer \(layer.id)")
            XCTAssertEqual(try bytes(file), was, "layer \(layer.id) \(layer.frame) changed the picture")
        }
        let good = Annotation(tool: .magnifier, start: CGPoint(x: 50, y: 30), end: CGPoint(x: 90, y: 70), id: 6)
        for scale in [CGFloat.nan, 0, -1, .infinity] {
            XCTAssertNil(Magnifier.tile(of: good, over: ground, scale: scale), "a tile at scale \(scale)")
        }
        XCTAssertNil(Magnifier.tile(of: Annotation(tool: .rectangle, start: good.start, end: good.end, id: 7), over: ground, scale: 1), "a tile of another tool")
        XCTAssertNotNil(Magnifier.tile(of: good, over: ground, scale: 1))
    }

    func testACropThatLeavesTheLensWhollyOutsideDrawsNothingOfItAndOneThatCutsItDrawsTheSameLens() throws {
        let ground = try picture(width: 200, height: 120)
        var editing = AnnotationEditing(bounds: area)
        dragged(&editing, .magnifier, CGPoint(x: 10, y: 10), CGPoint(x: 70, y: 70))
        // The area pulled in to the right of the lens: it is outside the new area and let go of.
        let right = CGRect(x: 100, y: 0, width: 100, height: 120)
        editing.reshape(bounds: right)
        editing.releaseIfOutside()
        let cut = try XCTUnwrap(ground.cropping(to: right))
        let file = try XCTUnwrap(CaptureSession.draw(editing.layers, over: cut, at: right.origin, scale: 1, display: ground))
        XCTAssertEqual(try bytes(file), try bytes(cut), "a lens outside the cut left ink in it")
        // And a lens across the cut's edge is the lens, cut: the same bytes as the whole file's.
        let across = CGRect(x: 40, y: 0, width: 160, height: 120)
        let whole = try bytes(try XCTUnwrap(CaptureSession.draw(editing.layers, over: ground, at: .zero, scale: 1, display: ground)))
        let part = try bytes(try XCTUnwrap(CaptureSession.draw(editing.layers, over: try XCTUnwrap(ground.cropping(to: across)), at: across.origin, scale: 1, display: ground)))
        var apart = 0
        for y in 0..<120 { for x in 0..<160 { for channel in 0..<4 where part[(y * 160 + x) * 4 + channel] != whole[(y * 200 + x + 40) * 4 + channel] { apart += 1 } } }
        XCTAssertEqual(apart, 0)
    }

    func testTwoLensesOnOneAnotherMagnifyThePictureAndNotEachOther() throws {
        // A picture with a mark on the lens's centre and a lens over a lens over it.
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        context.setFillColor(CGColor(srgbRed: 0, green: 0.2, blue: 1, alpha: 1))
        context.fill(CGRect(x: 100 + 8, y: 40, width: 6, height: 40))
        let ground = try XCTUnwrap(context.makeImage())
        var both = AnnotationEditing(bounds: area), lone = AnnotationEditing(bounds: area)
        dragged(&both, .magnifier, CGPoint(x: 60, y: 20), CGPoint(x: 140, y: 100))
        dragged(&both, .magnifier, CGPoint(x: 70, y: 30), CGPoint(x: 130, y: 90))
        dragged(&lone, .magnifier, CGPoint(x: 70, y: 30), CGPoint(x: 130, y: 90))
        let twice = try bytes(try XCTUnwrap(CaptureSession.draw(both.layers, over: ground, at: .zero, scale: 1, display: ground)))
        let one = try bytes(try XCTUnwrap(CaptureSession.draw(lone.layers, over: ground, at: .zero, scale: 1, display: ground)))
        var gap = 0
        for y in 0..<120 {
            for x in 0..<200 where hypot(CGFloat(x) + 0.5 - 100, CGFloat(y) + 0.5 - 60) < 26 {
                for channel in 0..<3 where twice[(y * 200 + x) * 4 + channel] != one[(y * 200 + x) * 4 + channel] { gap += 1 }
            }
        }
        XCTAssertEqual(gap, 0, "the top lens magnifies the lens under it: \(gap) bytes differ from the lone one")
    }
}
