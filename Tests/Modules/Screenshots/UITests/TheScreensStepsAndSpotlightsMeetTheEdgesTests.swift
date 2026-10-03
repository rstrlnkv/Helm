import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The screen and the file agree where the stage's own tests did not look.** A step in the yellow whose digit is black, a step
/// on the area's corner with half its circle outside, a pen stroke over the dim of a spotlight (the mark stays bright and the dim
/// stays under it), and the eraser over a spotlight: its edge takes it and its inside does not, and with the last one gone no dim
/// layer is left. Each picture is composited by the overlay's own layers and made again by the export, at 1× and 2×.
///
/// What it would print if it failed totally: a screen that numbers a step by the layer's id and a file by its place fail the digit
/// comparison; a dim above the marks darkens the stroke and the count of ink pixels differs; an eraser that takes a spotlight by its
/// inside erases the one the person is only crossing.
@MainActor
final class TheScreensStepsAndSpotlightsMeetTheEdgesTests: XCTestCase {
    private var rig: ScreenAndFile.Rig?
    /// The layers the last `compare` handed over.
    private var handed: [Annotation] = []

    override func tearDown() {
        rig?.overlay.close()
        rig = nil
        super.tearDown()
    }

    private func at(_ rig: ScreenAndFile.Rig, _ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: 50 + fx * (rig.points.width - 100), y: 50 + fy * (rig.points.height - 100))
    }

    /// The screen's pixels of the area against the file's, every third pixel in from the area's edge, and what they held.
    private func compare(_ made: ScreenAndFile.Rig, _ name: String) throws -> (off: Int, ink: Int, samples: Int, bad: [String]) {
        let scale = made.scale
        let root = ScreenAndFile.composite(made)
        let layers = try ScreenAndFile.confirmed(made)
        handed = layers
        let file = try ScreenAndFile.rgb(try ScreenAndFile.file(of: layers, made))
        let was = try ScreenAndFile.rgb(made.ground)
        let (w, h) = (made.ground.width, made.ground.height)
        let origin = Int(50 * scale), fileWidth = w - 2 * origin
        var probes: [(x: Int, y: Int)] = []
        for y in stride(from: origin + 2, to: h - origin - 2, by: 3) { for x in stride(from: origin + 2, to: w - origin - 2, by: 3) { probes.append((x, y)) } }
        let read = try CompositedPixels.read(root, width: w, height: h, at: probes.map { CGPoint(x: $0.x, y: h - 1 - $0.y) })
        var off = 0, ink = 0
        var bad: [String] = []
        for (probe, got) in zip(probes, read) {
            let inFile = ((probe.y - origin) * fileWidth + (probe.x - origin)) * 4, inPicture = (probe.y * w + probe.x) * 4
            var gap = 0
            for channel in 0..<3 { gap = max(gap, abs(Int(got[channel]) - Int(file[inFile + channel]))) }
            if gap > 16 { off += 1; bad.append("(\(probe.x),\(probe.y)) screen \(got.prefix(3)) file \(file[inFile..<inFile + 3])") }
            if (0..<3).contains(where: { abs(Int(file[inFile + $0]) - Int(was[inPicture + $0])) > 90 }) { ink += 1 }
        }
        return (off, ink, probes.count, bad)
    }

    func testAYellowStepHasABlackDigitOnTheScreenAndInTheFile() throws {
        for scale in [CGFloat(1), 2] {
            rig?.overlay.close()
            let made = try ScreenAndFile.rig(scale: scale)
            rig = made
            made.overlay.perform(.tool(.step))
            made.overlay.perform(.thickness(.thick))
            made.overlay.perform(.color(.yellow))
            ScreenAndFile.click(made, at: at(made, 0.3, 0.4))
            ScreenAndFile.click(made, at: at(made, 0.6, 0.4))
            let result = try compare(made, "yellow")
            XCTAssertEqual(result.off, 0, "\(scale)x: \(result.off) of \(result.samples) pixels differ, e.g. \(result.bad.prefix(3))")
            // The circle is yellow, so the digit is the dark pixels in it: both steps hold some in the file.
            let layers = handed
            let file = try ScreenAndFile.rgb(try ScreenAndFile.file(of: layers, made))
            let fileWidth = made.ground.width - Int(100 * scale)
            for layer in layers {
                let box = AnnotationStep.frame(of: layer)
                var dark = 0
                for y in Int((box.minY - 50) * scale)..<Int((box.maxY - 50) * scale) {
                    for x in Int((box.minX - 50) * scale)..<Int((box.maxX - 50) * scale) where file[(y * fileWidth + x) * 4 + 2] < 60 && file[(y * fileWidth + x) * 4] < 90 { dark += 1 }
                }
                XCTAssertGreaterThan(dark, Int(8 * scale), "\(scale)x: no black digit on the yellow circle")
            }
            XCTAssertGreaterThan(result.ink, 20)
        }
    }

    func testAStepOnTheAreasCornerIsTheSameOnTheScreenAndInTheFileWithHalfItsCircleOutside() throws {
        for scale in [CGFloat(1), 2] {
            rig?.overlay.close()
            let made = try ScreenAndFile.rig(scale: scale)
            rig = made
            made.overlay.perform(.tool(.step))
            made.overlay.perform(.thickness(.thick))
            // The first mark of a picture is taken by an area handle within its reach, so a step stands in the middle first.
            ScreenAndFile.click(made, at: at(made, 0.5, 0.5))
            ScreenAndFile.click(made, at: CGPoint(x: 50, y: 50))
            ScreenAndFile.click(made, at: CGPoint(x: made.points.width - 51, y: made.points.height - 51))
            XCTAssertEqual(made.overlay.editedLayers.count, 3, "\(scale)x: the subject: a step and two on the corners")
            let result = try compare(made, "corner")
            XCTAssertEqual(result.off, 0, "\(scale)x: \(result.off) of \(result.samples) pixels differ, e.g. \(result.bad.prefix(3))")
        }
    }

    func testAMarkOverTheDimStaysBrightOnTheScreenAndInTheFile() throws {
        for scale in [CGFloat(1), 2] {
            rig?.overlay.close()
            let made = try ScreenAndFile.rig(scale: scale)
            rig = made
            made.overlay.perform(.tool(.spotlight))
            ScreenAndFile.drag(made, from: at(made, 0.1, 0.1), to: at(made, 0.4, 0.5))
            made.overlay.perform(.tool(.pen))
            made.overlay.perform(.color(.blue))
            ScreenAndFile.drag(made, from: at(made, 0.5, 0.2), to: at(made, 0.9, 0.7)) // in the dim, off the spotlight
            made.overlay.perform(.tool(.rectangle))
            ScreenAndFile.drag(made, from: at(made, 0.05, 0.3), to: at(made, 0.7, 0.35)) // across the lit and the dimmed
            let result = try compare(made, "marks")
            XCTAssertEqual(result.off, 0, "\(scale)x: \(result.off) of \(result.samples) pixels differ, e.g. \(result.bad.prefix(3))")
            XCTAssertGreaterThan(result.ink, 60, "\(scale)x: too few inked pixels for the comparison to mean anything")
            // The ink in the dim: the stroke's pixel is full blue, not blue under 42 % of black.
            let layers = handed
            let pen = try XCTUnwrap(layers.first { $0.tool == .pen })
            let file = try ScreenAndFile.rgb(try ScreenAndFile.file(of: layers, made))
            let fileWidth = made.ground.width - Int(100 * scale)
            let mid = pen.points[pen.points.count / 2]
            let (fx, fy) = (Int((mid.x - 50) * scale), Int((mid.y - 50) * scale))
            var brightest = 0
            for dy in -3...3 { for dx in -3...3 { brightest = max(brightest, Int(file[((fy + dy) * fileWidth + fx + dx) * 4 + 2])) } }
            XCTAssertGreaterThan(brightest, 200, "\(scale)x: the pen over the dim is dimmed in the file: blue \(brightest)")
        }
    }

    func testTheEraserTakesASpotlightByItsEdgeAndNotByItsInsideAndTheLastOneTakesTheDimWithIt() throws {
        let made = try ScreenAndFile.rig(scale: 1)
        rig = made
        made.overlay.perform(.tool(.spotlight))
        let (from, to) = (at(made, 0.2, 0.2), at(made, 0.7, 0.7))
        ScreenAndFile.drag(made, from: from, to: to)
        XCTAssertNotNil(made.view.drawnSpotlightDim.path)
        made.overlay.perform(.erase)
        // Across the inside, well away from every edge: nothing is taken.
        let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        ScreenAndFile.drag(made, from: CGPoint(x: middle.x - 20, y: middle.y), to: CGPoint(x: middle.x + 20, y: middle.y))
        XCTAssertEqual(made.overlay.editedLayers.count, 1, "the eraser took a spotlight by its inside")
        XCTAssertNotNil(made.view.drawnSpotlightDim.path)
        // Over the edge: taken, and the dim goes with it.
        ScreenAndFile.drag(made, from: CGPoint(x: from.x - 5, y: middle.y), to: CGPoint(x: from.x + 5, y: middle.y))
        XCTAssertEqual(made.overlay.editedLayers.count, 0, "the eraser did not take a spotlight by its edge")
        XCTAssertNil(made.view.drawnSpotlightDim.path, "a dim was left with no spotlight")
        made.overlay.perform(.undo)
        XCTAssertEqual(made.overlay.editedLayers.count, 1)
        XCTAssertNotNil(made.view.drawnSpotlightDim.path, "the undo did not bring the dim back")
    }

    /// A click on the area's own right or bottom edge, the one line `CGRect.contains` leaves out, places no step, where the left and the
    /// top edge place one. Pinned as it stands.
    func testAClickOnTheRightEdgeOfTheAreaPlacesNoStepWhereTheLeftEdgeDoes() throws {
        let made = try ScreenAndFile.rig(scale: 1)
        rig = made
        made.overlay.perform(.tool(.step))
        ScreenAndFile.click(made, at: CGPoint(x: made.points.width / 2, y: made.points.height / 2))
        ScreenAndFile.click(made, at: CGPoint(x: made.points.width - 50, y: made.points.height / 2))
        XCTAssertEqual(made.overlay.editedLayers.count, 1, "the click on the right edge placed a step: the pin below is stale")
        ScreenAndFile.click(made, at: CGPoint(x: 50, y: made.points.height / 2))
        XCTAssertEqual(made.overlay.editedLayers.count, 2, "the click on the left edge placed no step")
    }

    /// The first step, with the area unmarked, within the handles' reach of the area's corner: the press is the handle's, as for every
    /// tool, and no step is placed. Pinned as it stands; whether a step's click should reach past a handle is the owner's to say.
    func testTheFirstStepOnAnAreaHandleIsTheHandlesAndPlacesNoStep() throws {
        let made = try ScreenAndFile.rig(scale: 1)
        rig = made
        made.overlay.perform(.tool(.step))
        let before = try XCTUnwrap(made.overlay.editedArea)
        ScreenAndFile.click(made, at: CGPoint(x: 50, y: 50))
        XCTAssertEqual(made.overlay.editedLayers.count, 0)
        XCTAssertEqual(made.overlay.editedArea, before, "a click on a handle moved the area")
        ScreenAndFile.click(made, at: CGPoint(x: 80, y: 80))
        XCTAssertEqual(made.overlay.editedLayers.count, 1, "the click away from the handle placed no step")
    }
}
