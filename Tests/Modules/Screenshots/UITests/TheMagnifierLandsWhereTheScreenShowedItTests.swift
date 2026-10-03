import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The lens on the screen is the lens in the file, pixel for pixel, and both stand where the picture puts them.** A blur is drawn first
/// (so the picture under the lens is a mosaic in the layers and a bar and a square in the frame), then a lens of 100 points over
/// it; the layers the overlay holds are composited through a `CARenderer` over the picture and the same layers are exported through
/// `CaptureSession`, and every pixel of the lens's box is compared, at 1× and 2×. Both are also read against the picture itself, as
/// `TheMagnifierShowsTheFrameNotTheLayersTests` reads the export: blue where the bar is magnified to, grey where it is not, red a
/// point beside the centre, so a lens that is the same wrong thing on the screen and in the file is not a green test. The lens is then pulled
/// by its corner and both are compared again, for a layer the overlay has rebuilt is one a stale cache could keep as it was.
///
/// What it would print if it failed totally: a lens with no picture on the screen leaves the box showing the mosaic and the file
/// differing from it by most of the box; a file that places the lens a pixel off differs along its ring.
@MainActor
final class TheMagnifierLandsWhereTheScreenShowedItTests: XCTestCase {
    private var rig: ScreenAndFile.Rig?
    private let centre = CGPoint(x: 300, y: 250)

    override func tearDown() {
        rig?.overlay.close()
        rig = nil
        super.tearDown()
    }

    private func paint(_ context: CGContext) {
        context.setFillColor(CGColor(srgbRed: 0, green: 0.2, blue: 1, alpha: 1))
        context.fill(CGRect(x: centre.x + 8, y: centre.y - 30, width: 6, height: 60))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: centre.x - 1, y: centre.y - 1, width: 2, height: 2))
    }

    /// Every pixel of the lens's box on the screen and in the file.
    private func compare(_ made: ScreenAndFile.Rig, _ name: String) throws -> [UInt8] {
        let scale = made.scale
        let (w, h) = (made.ground.width, made.ground.height)
        let lenses = made.overlay.editedLayers.filter { $0.tool == .magnifier }
        XCTAssertEqual(lenses.count, 1, "\(name): the overlay holds \(lenses.count) lenses")
        XCTAssertEqual(made.view.drawnShapes.count, made.overlay.editedLayers.count, "\(name): the screen holds \(made.view.drawnShapes.count) layers")
        for shape in made.view.drawnShapes { XCTAssertNotNil(shape.contents, "\(name): a layer holds no picture") }
        let file = try ScreenAndFile.rgb(try ScreenAndFile.file(of: made.overlay.editedLayers, made))
        let origin = Int(50 * scale), fileWidth = w - 2 * origin
        let box = try XCTUnwrap(lenses.first).frame.insetBy(dx: -2, dy: -2)
        var probes: [(x: Int, y: Int)] = []
        for y in Int(box.minY * scale)..<Int(box.maxY * scale) { for x in Int(box.minX * scale)..<Int(box.maxX * scale) { probes.append((x, y)) } }
        let read = try CompositedPixels.read(ScreenAndFile.composite(made), width: w, height: h, at: probes.map { CGPoint(x: $0.x, y: h - 1 - $0.y) })
        var off = 0, worst = 0
        for (probe, got) in zip(probes, read) {
            let inFile = ((probe.y - origin) * fileWidth + (probe.x - origin)) * 4
            var gap = 0
            for channel in 0..<3 { gap = max(gap, abs(Int(got[channel]) - Int(file[inFile + channel]))) }
            worst = max(worst, gap)
            if gap > 3 { off += 1 }
        }
        XCTAssertEqual(off, 0, "\(name): \(off) of \(probes.count) pixels differ between the screen and the file, the worst by \(worst)")
        return file
    }

    private func pixel(_ file: [UInt8], _ made: ScreenAndFile.Rig, _ x: CGFloat, _ y: CGFloat) -> [Int] {
        let scale = made.scale
        let fileWidth = made.ground.width - 100 * Int(scale)
        let index = ((Int(y * scale) - Int(50 * scale)) * fileWidth + (Int(x * scale) - Int(50 * scale))) * 4
        return [Int(file[index]), Int(file[index + 1]), Int(file[index + 2])]
    }

    func testTheScreenAndTheFileHoldTheSameLensOverABlurAndAfterAResize() throws {
        for scale in [CGFloat(1), 2] {
            rig?.overlay.close()
            let made = try ScreenAndFile.rig(scale: scale, paint: paint)
            rig = made
            let name = "\(Int(scale))x"
            made.overlay.perform(.tool(.blur))
            ScreenAndFile.drag(made, from: CGPoint(x: 245, y: 195), to: CGPoint(x: 355, y: 305))
            XCTAssertEqual(made.overlay.editedLayers.map(\.tool), [.blur], name)
            made.overlay.perform(.tool(.magnifier))
            ScreenAndFile.drag(made, from: CGPoint(x: 250, y: 200), to: CGPoint(x: 350, y: 300))
            XCTAssertEqual(made.overlay.editedLayers.map(\.tool), [.blur, .magnifier], "\(name): the lens was not drawn")

            let file = try compare(made, "\(name) lens over a blur")
            let at22 = pixel(file, made, centre.x + 22, centre.y), at11 = pixel(file, made, centre.x + 11, centre.y)
            XCTAssertGreaterThan(at22[2] - at22[0], 100, "\(name): no blue 22 points right of the centre: \(at22)")
            XCTAssertLessThan(abs(at11[0] - at11[2]), 12, "\(name): the bar stands where the picture has it: \(at11)")
            let square = pixel(file, made, centre.x + 1.5, centre.y)
            XCTAssertGreaterThan(square[0] - square[2], 150, "\(name): the square did not grow: \(square)")

            // Take the lens by the inside and pull its top-left corner: a circle again, rebuilt.
            made.overlay.perform(.select)
            ScreenAndFile.click(made, at: CGPoint(x: 300, y: 250))
            XCTAssertNotNil(made.overlay.chrome(on: made.display), name)
            ScreenAndFile.drag(made, from: CGPoint(x: 250, y: 200), to: CGPoint(x: 230, y: 190))
            let lens = try XCTUnwrap(made.overlay.editedLayers.last)
            XCTAssertEqual(lens.tool, .magnifier)
            XCTAssertEqual(lens.frame.width, lens.frame.height, accuracy: 0.001, "\(name): the pulled lens is no circle: \(lens.frame)")
            XCTAssertGreaterThan(lens.frame.width, 105, "\(name): the corner was not pulled: \(lens.frame)")
            _ = try compare(made, "\(name) lens after a resize")
        }
    }
}
