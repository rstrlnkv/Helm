import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **However many spotlights there are, the dim is one.** Everything of the area that no spotlight covers is dimmed once, 42 %
/// of black, and what any spotlight covers is bright: two spotlights side by side, overlapping, one inside another, and one
/// across the area's edge are drawn into a file and every pixel is judged — bright where the spotlights' union is, dimmed
/// exactly once outside it, so a pixel dimmed twice, or dimmed where another spotlight lights it, is found. The marks are above
/// the dim, wherever the spotlight stands in the list. The screen's own half of this is `TheScreensSpotlightsAreTheFilesTests`.
///
/// What it would print if it failed totally: a spotlight that dims what the others do not cover leaves 0.58² of the ground
/// outside all of them and a dim where the second one lights; no dim at all leaves the ground untouched and fails the
/// count of dimmed pixels.
final class TheSpotlightsShareOneDimTests: XCTestCase {

    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let (width, height) = (300, 200)

    private func ground(scale: CGFloat) throws -> CGImage {
        let (w, h) = (Int(CGFloat(width) * scale), Int(CGFloat(height) * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
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

    private func spotlight(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, id: Int) -> Annotation {
        Annotation(tool: .spotlight, start: CGPoint(x: x0, y: y0), end: CGPoint(x: x1, y: y1), id: id)
    }

    /// Two overlapping, one beside them with a gap, one inside the first, and one across the area's right edge.
    private var lights: [Annotation] {
        [spotlight(20, 20, 120, 90, id: 1), spotlight(90, 60, 190, 150, id: 2), spotlight(200, 20, 240, 60, id: 3),
         spotlight(30, 30, 60, 60, id: 4), spotlight(260, 120, 340, 180, id: 5)]
    }

    /// What the judgement found, by pixel kind.
    private struct Verdict { var bright = 0, dimmed = 0, wrong: [String] = [] }

    /// Every pixel of the file judged against the spotlights' union: bright pixels equal the ground, dimmed ones the ground
    /// under 42 % of black. A pixel within a pixel and a half of the union's edge is not judged: the edge is antialiased.
    private func judge(_ layers: [Annotation], scale: CGFloat, over picture: CGImage, file: CGImage) throws -> Verdict {
        let (was, now) = (try bytes(picture), try bytes(file))
        let holes = layers.filter { $0.tool == .spotlight }.map { Spotlights.outline(of: $0) }
        func lit(_ point: CGPoint) -> Bool { holes.contains { $0.contains(point) } }
        let ground = Double(was[0]), dimmed = ground * (1 - Double(Spotlights.dimAlpha))
        var verdict = Verdict()
        let reach = 1.5 / scale
        for y in 0..<file.height {
            for x in 0..<file.width {
                let centre = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let samples = [CGPoint(x: -reach, y: -reach), CGPoint(x: 0, y: -reach), CGPoint(x: reach, y: -reach),
                               CGPoint(x: -reach, y: 0), .zero, CGPoint(x: reach, y: 0),
                               CGPoint(x: -reach, y: reach), CGPoint(x: 0, y: reach), CGPoint(x: reach, y: reach)]
                    .map { CGPoint(x: centre.x + $0.x, y: centre.y + $0.y) }
                let inside = samples.map(lit)
                let at = (y * file.width + x) * 4
                let got = Double(now[at])
                if inside.allSatisfy({ $0 }) {
                    verdict.bright += 1
                    if abs(got - ground) > 1 { verdict.wrong.append("(\(x),\(y)) lit but \(got), ground \(ground)") }
                } else if inside.allSatisfy({ !$0 }) {
                    verdict.dimmed += 1
                    if abs(got - dimmed) > 2 { verdict.wrong.append("(\(x),\(y)) dark by \(got), once-dimmed is \(dimmed)") }
                }
            }
        }
        return verdict
    }

    func testEveryPixelIsBrightInTheUnionAndDimmedOnceOutsideIt() throws {
        for scale in [CGFloat(1), 2] {
            let picture = try ground(scale: scale)
            let file = try XCTUnwrap(CaptureSession.draw(lights, over: picture, at: .zero, scale: scale, display: picture))
            let verdict = try judge(lights, scale: scale, over: picture, file: file)
            XCTAssertTrue(verdict.wrong.isEmpty, "\(scale)x: \(verdict.wrong.count) pixels with the wrong dim, e.g. \(verdict.wrong.prefix(4))")
            // Both kinds were seen, or the judgement above judged nothing.
            XCTAssertGreaterThan(verdict.bright, 5000 * Int(scale * scale), "\(scale)x: too few lit pixels judged: \(verdict.bright)")
            XCTAssertGreaterThan(verdict.dimmed, 20000 * Int(scale * scale), "\(scale)x: too few dimmed pixels judged: \(verdict.dimmed)")
        }
    }

    func testTheOrderOfTheSpotlightsChangesNothing() throws {
        let picture = try ground(scale: 1)
        let forward = try bytes(try XCTUnwrap(CaptureSession.draw(lights, over: picture, at: .zero, scale: 1, display: picture)))
        let backward = try bytes(try XCTUnwrap(CaptureSession.draw(lights.reversed(), over: picture, at: .zero, scale: 1, display: picture)))
        XCTAssertEqual(forward, backward)
    }

    func testASpotlightAloneDimsTheRestOfTheAreaAndOneThatCoversItDimsNothing() throws {
        let picture = try ground(scale: 1)
        let one = [spotlight(100, 50, 200, 150, id: 1)]
        let file = try XCTUnwrap(CaptureSession.draw(one, over: picture, at: .zero, scale: 1, display: picture))
        let verdict = try judge(one, scale: 1, over: picture, file: file)
        XCTAssertTrue(verdict.wrong.isEmpty, "\(verdict.wrong.prefix(4))")
        XCTAssertGreaterThan(verdict.dimmed, 40000)
        let all = [spotlight(-5, -5, 305, 205, id: 1)]
        let clear = try bytes(try XCTUnwrap(CaptureSession.draw(all, over: picture, at: .zero, scale: 1, display: picture)))
        let was = try bytes(picture)
        // Edge pixels at the box's rounded corners are the only ones that may differ, and the box passes the area's corners.
        XCTAssertEqual(clear, was, "a spotlight over the whole area dimmed something")
    }

    func testACutThatBeginsElsewhereHoldsTheSameDimAsTheWhole() throws {
        let picture = try ground(scale: 2)
        let whole = try bytes(try XCTUnwrap(CaptureSession.draw(lights, over: picture, at: .zero, scale: 2, display: picture)))
        let rect = CGRect(x: 37, y: 11, width: 400, height: 300)
        let cut = try XCTUnwrap(picture.cropping(to: rect))
        let part = try bytes(try XCTUnwrap(CaptureSession.draw(lights, over: cut, at: rect.origin, scale: 2, display: picture)))
        var apart = 0
        for y in 0..<cut.height {
            for x in 0..<cut.width {
                for channel in 0..<4 where part[(y * cut.width + x) * 4 + channel] != whole[((y + 11) * picture.width + x + 37) * 4 + channel] { apart += 1 }
            }
        }
        XCTAssertEqual(apart, 0, "a cut that begins elsewhere dims \(apart) bytes differently")
    }

    func testTheMarksAreAboveTheDimWhereverTheSpotlightStandsInTheList() throws {
        let picture = try ground(scale: 1)
        let pen = Annotation(tool: .rectangle, start: CGPoint(x: 150, y: 100), end: CGPoint(x: 280, y: 190),
                             style: AnnotationStyle(color: .blue, thickness: .thick), id: 9)
        let light = spotlight(20, 20, 120, 90, id: 1)
        let bare = try bytes(try XCTUnwrap(CaptureSession.draw([pen], over: picture, at: .zero, scale: 1, display: picture)))
        for layers in [[light, pen], [pen, light]] {
            let made = try bytes(try XCTUnwrap(CaptureSession.draw(layers, over: picture, at: .zero, scale: 1, display: picture)))
            // The rectangle's stroke is in the dimmed part of the picture, and its pixels are the ones it has with no spotlight.
            for point in [(150, 140), (151, 140), (200, 100), (280, 150)] {
                let at = (point.1 * width + point.0) * 4
                XCTAssertEqual(Array(made[at..<at + 3]), Array(bare[at..<at + 3]), "\(layers.map(\.tool)): the mark at \(point) is not at full ink")
            }
        }
    }

    /// A blur's mosaic is made from the display's own pixels, so the dim does not reach what it covers, and the box is the ground
    /// where the pixels around it are dimmed. The control: with no blur the same pixels are dimmed.
    func testABlurInsideTheDimIsNotDimmed() throws {
        let picture = try ground(scale: 1)
        let light = spotlight(20, 20, 60, 60, id: 1)
        let blur = Annotation(tool: .blur, start: CGPoint(x: 150, y: 100), end: CGPoint(x: 250, y: 180), id: 2)
        func pixel(_ layers: [Annotation], _ x: Int, _ y: Int) throws -> UInt8 {
            try bytes(try XCTUnwrap(CaptureSession.draw(layers, over: picture, at: .zero, scale: 1, display: picture)))[(y * width + x) * 4]
        }
        XCTAssertEqual(Double(try pixel([light], 200, 140)), 204 * 0.58, accuracy: 2, "the control: the picture there is dimmed")
        for layers in [[light, blur], [blur, light]] {
            XCTAssertEqual(try pixel(layers, 200, 140), 204, "\(layers.map(\.tool)): the blur's box is dimmed")
            XCTAssertEqual(Double(try pixel(layers, 100, 140)), 204 * 0.58, accuracy: 2, "\(layers.map(\.tool)): the picture beside the blur is not dimmed")
        }
    }

    // MARK: - Held like a rectangle

    private func drawn(_ boxes: [CGRect]) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
        for box in boxes {
            XCTAssertTrue(editing.press(at: box.origin, tool: .spotlight))
            editing.drag(to: CGPoint(x: box.maxX, y: box.maxY), shift: false)
            editing.end()
        }
        return editing
    }

    func testASpotlightIsTakenByItsEdgeAndAPressInsideItBeginsAnotherOne() {
        var editing = drawn([CGRect(x: 40, y: 40, width: 200, height: 120)])
        XCTAssertEqual(editing.layers.count, 1)
        // Inside, away from the edge, with the spotlight tool: a second spotlight, not a selection of the first.
        XCTAssertTrue(editing.press(at: CGPoint(x: 100, y: 100), tool: .spotlight))
        editing.drag(to: CGPoint(x: 160, y: 140), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.map(\.tool), [.spotlight, .spotlight], "a press inside the first did not begin a second")
        XCTAssertNil(editing.selected)
        // With no tool, the edge takes it (the inside is `testAPressInsideASpotlightWithNoToolSelectsItBelowEveryMark`).
        XCTAssertTrue(editing.press(at: CGPoint(x: 240, y: 100), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[0].id, "a press on the edge did not take the spotlight")
        XCTAssertEqual(editing.selected?.handles.count, 4, "a spotlight is held by four corners")
    }

    /// With no tool a press in the lit part selects the spotlight, below every other layer; the eraser and the text tool's question
    /// ("is there something under this press") still read its edge alone.
    func testAPressInsideASpotlightWithNoToolSelectsItBelowEveryMark() {
        let big = CGRect(x: 40, y: 40, width: 200, height: 120), small = CGRect(x: 100, y: 100, width: 60, height: 40)
        var editing = drawn([big, small])
        XCTAssertEqual(editing.layers.count, 2, "the subject: two spotlights, one inside the other")
        // A rectangle's edge drawn across the big one's lit part, over it in the list.
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 50), tool: .rectangle))
        editing.drag(to: CGPoint(x: 90, y: 80), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.map(\.tool), [.spotlight, .spotlight, .rectangle])
        editing.deselect()
        // Inside the big one only, away from every edge: the big one.
        XCTAssertTrue(editing.press(at: CGPoint(x: 200, y: 60), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[0].id, "a press inside a spotlight selected nothing")
        // Inside both: the one later in the list.
        XCTAssertTrue(editing.press(at: CGPoint(x: 130, y: 120), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[1].id, "of two spotlights the later was not taken")
        // On the rectangle's edge, inside the big one: the mark, which is above.
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 65), tool: nil))
        editing.end()
        XCTAssertEqual(editing.selected?.id, editing.layers[2].id, "a spotlight was taken before a mark drawn over it")
        // Outside both: nothing.
        XCTAssertTrue(editing.press(at: CGPoint(x: 280, y: 180), tool: nil))
        editing.end()
        XCTAssertNil(editing.selected)
        // The text tool's question and the eraser read the edge alone.
        XCTAssertFalse(editing.takes(at: CGPoint(x: 200, y: 60)), "a press inside a spotlight is a press on bare picture for the text tool")
        editing.beginErase(at: CGPoint(x: 200, y: 60), radius: 9)
        editing.end()
        XCTAssertEqual(editing.layers.count, 3, "the eraser took a spotlight by its inside")
        editing.beginErase(at: CGPoint(x: 240, y: 100), radius: 9)
        editing.end()
        XCTAssertEqual(editing.layers.count, 2, "the eraser did not take the spotlight by its edge")
    }

    func testASpotlightMovesAndResizesLikeARectangleEachOneStep() throws {
        var editing = drawn([CGRect(x: 40, y: 40, width: 100, height: 60)])
        XCTAssertTrue(editing.press(at: CGPoint(x: 140, y: 70), tool: nil))
        editing.drag(to: CGPoint(x: 170, y: 90), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 70, y: 60, width: 100, height: 60))
        let corner = try XCTUnwrap(editing.layers[0].handles.first { $0.handle == .bottomRight }).point
        XCTAssertTrue(editing.press(at: corner, tool: nil))
        editing.drag(to: CGPoint(x: 200, y: 150), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 70, y: 60, width: 130, height: 90))
        editing.undo()
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 70, y: 60, width: 100, height: 60))
        editing.undo()
        XCTAssertEqual(editing.layers[0].frame, CGRect(x: 40, y: 40, width: 100, height: 60))
    }

    func testTheLastOneErasedTakesTheDimWithItAndUndoBringsBothBack() {
        var editing = drawn([CGRect(x: 40, y: 40, width: 100, height: 60)])
        let area = CGRect(x: 0, y: 0, width: 300, height: 200)
        editing.beginErase(at: CGPoint(x: 140, y: 70), radius: 9)
        editing.end()
        XCTAssertTrue(editing.layers.isEmpty, "the eraser did not take the spotlight at its edge")
        XCTAssertNil(Spotlights.dim(of: editing.layers, within: area), "a dim is left with no spotlight")
        editing.undo()
        XCTAssertNotNil(Spotlights.dim(of: editing.layers, within: area))
    }

    func testARecolourAndAThicknessStepOfASpotlightAreNoUndoSteps() {
        var editing = drawn([CGRect(x: 40, y: 40, width: 100, height: 60)])
        XCTAssertTrue(editing.press(at: CGPoint(x: 140, y: 70), tool: nil))
        editing.end()
        XCTAssertNotNil(editing.selected)
        editing.recolor(.blue)
        editing.setThickness(.thick)
        editing.setFilled(true)
        XCTAssertEqual(editing.layers.count, 1)
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "the first undo took an edit that is none, not the spotlight")
    }

    func testTheDimIsOnePathAndOneLayerOfTheScreenSeesTheSameHoles() throws {
        let area = CGRect(x: 0, y: 0, width: width, height: height)
        XCTAssertNil(Spotlights.dim(of: [], within: area))
        XCTAssertNil(Spotlights.dim(of: [Annotation(tool: .rectangle, start: .zero, end: CGPoint(x: 50, y: 50), id: 1)], within: area))
        let path = try XCTUnwrap(Spotlights.dim(of: lights, within: area))
        // Even-odd: the point between the two overlapping boxes, in both, is a hole; one in neither is dim; one in the first only is a hole.
        func dims(_ point: CGPoint) -> Bool { path.contains(point, using: .evenOdd) }
        XCTAssertFalse(dims(CGPoint(x: 100, y: 75)), "the overlap of two spotlights is dimmed")
        XCTAssertFalse(dims(CGPoint(x: 50, y: 70)))
        XCTAssertFalse(dims(CGPoint(x: 150, y: 140)))
        XCTAssertTrue(dims(CGPoint(x: 160, y: 30)))
        XCTAssertTrue(dims(CGPoint(x: 5, y: 195)))
        XCTAssertTrue(dims(CGPoint(x: 280, y: 20)), "the area outside every spotlight")
        XCTAssertFalse(dims(CGPoint(x: 280, y: 150)), "the part of a spotlight inside the area")
        // The part of a spotlight beyond the area adds nothing to the dim: the path does not leave the area.
        XCTAssertTrue(area.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingBoxOfPath))
    }
}
