import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The spotlights on the screen are one dim, and it is the file's.** Three spotlights are drawn into the overlay with the mouse,
/// two of them overlapping, and a rectangle across the lit and the dimmed part; the layers the overlay holds are composited
/// through a `CARenderer` over the picture and the same annotations are exported through `CaptureSession`. A spotlight has no
/// layer of its own, the dim is one layer under the rectangle's, every sampled pixel of the area is the ground where the union of the
/// spotlights is and the ground dimmed once everywhere else, and the screen's pixels are the file's, at 1× and 2×.
/// A spotlight is taken by its edge and has no steps: a second click on its cell opens nothing.
///
/// What it would print if it failed totally: a layer per spotlight gives `drawnShapes` three entries and a dim that adds up
/// where two meet; a dim that is not the file's fails the pixel comparison; an overlay that draws no dim leaves every
/// sample at the ground and fails the count of dimmed ones.
@MainActor
final class TheScreensSpotlightsAreTheFilesTests: XCTestCase {
    private var rig: ScreenAndFile.Rig?

    override func tearDown() {
        rig?.overlay.close()
        rig = nil
        super.tearDown()
    }

    /// A point of the area by its share of the width and the height: the screens differ in size.
    private func at(_ rig: ScreenAndFile.Rig, _ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: 50 + fx * (rig.points.width - 100), y: 50 + fy * (rig.points.height - 100))
    }

    private func drawn(scale: CGFloat) throws -> ScreenAndFile.Rig {
        rig?.overlay.close()
        let made = try ScreenAndFile.rig(scale: scale)
        rig = made
        made.overlay.perform(.tool(.spotlight))
        ScreenAndFile.drag(made, from: at(made, 0.1, 0.1), to: at(made, 0.45, 0.5))
        ScreenAndFile.drag(made, from: at(made, 0.35, 0.35), to: at(made, 0.7, 0.8))
        ScreenAndFile.drag(made, from: at(made, 0.8, 0.1), to: at(made, 0.95, 0.3))
        return made
    }

    func testASpotlightHasNoLayerOfItsOwnAndTheDimIsOneLayerUnderTheMarks() throws {
        let made = try drawn(scale: 1)
        XCTAssertTrue(made.view.drawnShapes.isEmpty, "a spotlight drew a layer of its own: \(made.view.drawnShapes.count)")
        XCTAssertNotNil(made.view.drawnSpotlightDim.path, "no dim is drawn for three spotlights")
        made.overlay.perform(.tool(.rectangle))
        ScreenAndFile.drag(made, from: at(made, 0.3, 0.3), to: at(made, 0.6, 0.9))
        XCTAssertEqual(made.view.drawnShapes.count, 1)
        let stack = try XCTUnwrap(made.view.layer?.sublayers)
        let dim = try XCTUnwrap(stack.firstIndex { $0 === made.view.drawnSpotlightDim })
        let mark = try XCTUnwrap(stack.firstIndex { $0 === made.view.drawnShapes[0] })
        XCTAssertLessThan(dim, mark, "the spotlights' dim stands over the rectangle")
        // Nothing is dimmed with no spotlight: the layer has no path.
        made.overlay.perform(.undo)
        made.overlay.perform(.undo)
        made.overlay.perform(.undo)
        made.overlay.perform(.undo)
        XCTAssertNil(made.view.drawnSpotlightDim.path, "the dim stays after every spotlight is undone")
    }

    func testASpotlightHasNoStepsAndASecondClickOnItsCellOpensNothing() throws {
        let made = try drawn(scale: 1)
        XCTAssertFalse(made.overlay.popoverIsOpen)
        made.overlay.perform(.thicknessAndOpacity(anchorX: 100))
        XCTAssertFalse(made.overlay.popoverIsOpen, "the pop-over opened for the spotlight, which has no steps")
        made.overlay.perform(.tool(.rectangle))
        made.overlay.perform(.thicknessAndOpacity(anchorX: 100))
        XCTAssertTrue(made.overlay.thicknessIsOpen, "the control: the pop-over opens for a rectangle")
    }

    /// The pixels of the screen and of the file, and each one's verdict against the spotlights.
    func testTheScreenIsOneDimAndItsPixelsAreTheFiles() throws {
        for scale in [CGFloat(1), 2] {
            let made = try drawn(scale: scale)
            made.overlay.perform(.tool(.rectangle))
            made.overlay.perform(.color(.blue))
            ScreenAndFile.drag(made, from: at(made, 0.3, 0.3), to: at(made, 0.6, 0.9))
            let root = ScreenAndFile.composite(made)
            let layers = try ScreenAndFile.confirmed(made)
            XCTAssertEqual(layers.map(\.tool), [.spotlight, .spotlight, .spotlight, .rectangle])
            let file = try ScreenAndFile.rgb(try ScreenAndFile.file(of: layers, made))
            let was = try ScreenAndFile.rgb(made.ground)
            let (w, h) = (made.ground.width, made.ground.height)
            let fileWidth = w - Int(100 * scale)
            let holes = layers.filter { $0.tool == .spotlight }.map(\.outline)
            let ground = Double(was[0]), dimmed = ground * (1 - Double(Spotlights.dimAlpha))

            var probes: [(x: Int, y: Int)] = []
            for y in stride(from: Int(50 * scale), to: h - Int(50 * scale), by: 5) {
                for x in stride(from: Int(50 * scale), to: w - Int(50 * scale), by: 5) { probes.append((x, y)) }
            }
            let read = try CompositedPixels.read(root, width: w, height: h, at: probes.map { CGPoint(x: $0.x, y: h - 1 - $0.y) })
            var off = 0, worst = 0, lit = 0, dim = 0, wrong: [String] = []
            let reach = 1.5 / scale
            for (probe, got) in zip(probes, read) {
                let fileAt = ((probe.y - Int(50 * scale)) * fileWidth + (probe.x - Int(50 * scale))) * 4
                var gap = 0
                for channel in 0..<3 { gap = max(gap, abs(Int(got[channel]) - Int(file[fileAt + channel]))) }
                // The screen's edge and the file's are both antialiased, by two renderers: a pixel on a spotlight's edge may
                // differ by a few levels, and a pixel off it may not.
                let centre = CGPoint(x: (CGFloat(probe.x) + 0.5) / scale, y: (CGFloat(probe.y) + 0.5) / scale)
                let around = [(-reach, -reach), (0, -reach), (reach, -reach), (-reach, 0), (0, 0), (reach, 0), (-reach, reach), (0, reach), (reach, reach)]
                    .map { CGPoint(x: centre.x + $0.0, y: centre.y + $0.1) }
                let inside = around.map { point in holes.contains { $0.contains(point) } }
                let onTheEdge = !inside.allSatisfy { $0 } && !inside.allSatisfy { !$0 }
                worst = max(worst, onTheEdge ? 0 : gap)
                if gap > (onTheEdge ? 16 : 3) { off += 1 }
                // The screen against the spotlights: the ground in the union, the ground dimmed once outside it, and only
                // where the pointer-drawn rectangle's stroke does not stand.
                let blue = got[2] > got[0] + 40
                if blue { continue }
                if inside.allSatisfy({ $0 }) {
                    lit += 1
                    if abs(Double(got[0]) - ground) > 3 { wrong.append("(\(probe.x),\(probe.y)) lit but \(got[0])") }
                } else if inside.allSatisfy({ !$0 }) {
                    dim += 1
                    if abs(Double(got[0]) - dimmed) > 3 { wrong.append("(\(probe.x),\(probe.y)) is \(got[0]), once-dimmed is \(dimmed)") }
                }
            }
            XCTAssertEqual(off, 0, "\(scale)x: \(off) of \(probes.count) pixels differ between the screen and the file, the worst by \(worst)")
            XCTAssertTrue(wrong.isEmpty, "\(scale)x: \(wrong.count) pixels of the screen with the wrong dim, e.g. \(wrong.prefix(4))")
            XCTAssertGreaterThan(lit, 500, "\(scale)x: too few lit samples (\(lit)) for the verdict to mean anything")
            XCTAssertGreaterThan(dim, 2000, "\(scale)x: too few dimmed samples (\(dim))")
        }
    }
}
