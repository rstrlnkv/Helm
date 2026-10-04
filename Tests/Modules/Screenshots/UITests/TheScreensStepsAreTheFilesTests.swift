import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The steps on the screen carry the digits the file carries, through a delete and an undo.** Three steps are clicked into the
/// overlay, the middle one is taken and deleted, then the delete is undone; in each of the three states the layers the
/// overlay holds are composited through a `CARenderer` over the picture and the layers it holds are exported through
/// `CaptureSession`, and every pixel of every step's box is compared, at 1× and 2×. The layer of the step that comes after
/// the deleted one is rebuilt by nothing but its number: a cache keyed by the annotation alone would show a 3 where the file
/// has a 2, which is what this fails on.
///
/// What it would print if it failed totally: a step with no picture leaves the box empty and the file's ink count low; a stale digit
/// differs along the glyph's strokes in the one step after the deleted one.
@MainActor
final class TheScreensStepsAreTheFilesTests: XCTestCase {
    private var rig: ScreenAndFile.Rig?

    override func tearDown() {
        rig?.overlay.close()
        rig = nil
        super.tearDown()
    }

    private func at(_ rig: ScreenAndFile.Rig, _ fraction: CGFloat) -> CGPoint {
        CGPoint(x: 50 + fraction * (rig.points.width - 100), y: 200.3)
    }

    /// Every pixel of every step's box, on the screen and in the file, and the ink the file has in each.
    private func compare(_ made: ScreenAndFile.Rig, _ name: String, steps: Int) throws {
        let scale = made.scale
        let (w, h) = (made.ground.width, made.ground.height)
        XCTAssertEqual(made.view.drawnShapes.count, steps, "\(name): the screen holds \(made.view.drawnShapes.count) layers")
        for shape in made.view.drawnShapes { XCTAssertNotNil(shape.contents, "\(name): a step's layer holds no picture") }
        let layers = made.overlay.editedLayers
        XCTAssertEqual(layers.count, steps, name)
        let file = try ScreenAndFile.rgb(try ScreenAndFile.file(of: layers, made))
        let was = try ScreenAndFile.rgb(made.ground)
        let origin = Int(50 * scale), fileWidth = w - 2 * origin

        var probes: [(x: Int, y: Int)] = []
        var inked = 0
        for (index, layer) in layers.enumerated() {
            let box = layer.frame.insetBy(dx: -2, dy: -2)
            var own = 0
            for y in Int(box.minY * scale)..<Int(box.maxY * scale) {
                for x in Int(box.minX * scale)..<Int(box.maxX * scale) {
                    probes.append((x, y))
                    let inFile = ((y - origin) * fileWidth + (x - origin)) * 4, inPicture = (y * w + x) * 4
                    if (0..<3).contains(where: { file[inFile + $0] != was[inPicture + $0] }) { own += 1 }
                }
            }
            XCTAssertGreaterThan(own, 40, "\(name): step \(index + 1): the file shows no ink in its box")
            inked += own
        }
        // The renderer's texture is bottom-up: the picture's row is `h - 1 - row`.
        let read = try CompositedPixels.read(ScreenAndFile.composite(made), width: w, height: h,
                                             at: probes.map { CGPoint(x: $0.x, y: h - 1 - $0.y) })
        var off = 0, worst = 0
        for (probe, got) in zip(probes, read) {
            let inFile = ((probe.y - origin) * fileWidth + (probe.x - origin)) * 4
            var gap = 0
            for channel in 0..<3 { gap = max(gap, abs(Int(got[channel]) - Int(file[inFile + channel]))) }
            worst = max(worst, gap)
            if gap > 3 { off += 1 }
        }
        XCTAssertEqual(off, 0, "\(name): \(off) of \(probes.count) pixels differ between the screen and the file, the worst by \(worst)")
        XCTAssertGreaterThan(inked, steps * 40, name)
    }

    func testTheScreenAndTheFileHoldTheSameDigitsThroughADeleteAndAnUndo() throws {
        for scale in [CGFloat(1), 2] {
            rig?.overlay.close()
            let made = try ScreenAndFile.rig(scale: scale)
            rig = made
            made.overlay.perform(.tool(.step))
            made.overlay.perform(.thickness(.thick))
            for fraction in [0.2, 0.5, 0.8] as [CGFloat] { ScreenAndFile.click(made, at: at(made, fraction)) }
            XCTAssertEqual(AnnotationStep.numbers(in: made.overlay.editedLayers), [1, 2, 3], "\(scale)x: three clicks are not three steps")
            try compare(made, "\(scale)x one two three", steps: 3)

            // Select the middle one with no tool and delete it: the last is now the second, and its layer is not one the delete touched.
            made.overlay.perform(.select)
            ScreenAndFile.click(made, at: at(made, 0.5))
            made.overlay.perform(.delete)
            XCTAssertEqual(AnnotationStep.numbers(in: made.overlay.editedLayers), [1, 2], "\(scale)x: the list is not one two")
            try compare(made, "\(scale)x one two", steps: 2)

            made.overlay.perform(.undo)
            XCTAssertEqual(AnnotationStep.numbers(in: made.overlay.editedLayers), [1, 2, 3], "\(scale)x: undo did not bring one two three back")
            try compare(made, "\(scale)x one two three again", steps: 3)
        }
    }
}
