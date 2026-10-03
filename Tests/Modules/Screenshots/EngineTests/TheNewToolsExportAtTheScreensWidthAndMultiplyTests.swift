import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The export draws the new tools the way the screen's geometry says:** a stroke is
/// its points times the display's scale at 1× and 2×, and the marker is multiplied
/// into the picture, so a dark pixel stays dark and a white one takes the tint.
final class TheNewToolsExportAtTheScreensWidthAndMultiplyTests: XCTestCase {

    /// A 100×60-point display at `scale`, black on the left half and white on the right.
    private func freeze(scale: CGFloat) -> Freeze {
        let width = Int(100 * scale), height = Int(60 * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                                                      scale: scale, image: context.makeImage()!))], windows: [])
    }

    /// RGBA of every pixel of column `x`, top to bottom.
    private func column(_ image: CGImage, x: Int) -> [[UInt8]] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<image.height).map { row in (0..<4).map { bytes[row * image.width * 4 + x * 4 + $0] } }
    }

    private func export(_ layer: Annotation, scale: CGFloat, name: String) async throws -> CGImage {
        let rig = Rig(home: scratchDirectory(name))
        let drawn = await rig.session.annotated(freeze(scale: scale), display: DisplayID(1),
                                                local: CGRect(x: 0, y: 0, width: 100, height: 60), layers: [layer])
        return try XCTUnwrap(drawn)
    }

    func testAPencilALineAndAnEllipseAreStrokedAtPointsTimesTheScale() async throws {
        // The thin step of each tool, in the owner's points: the pencil's own 2, the line's and the oval's 3.
        let thin = AnnotationStyle(thickness: .thin)
        let horizontal: [(AnnotationTool, Annotation, Double)] = [
            (.pencil, Annotation(tool: .pencil, start: CGPoint(x: 55, y: 30), end: CGPoint(x: 95, y: 30),
                                 points: [CGPoint(x: 55, y: 30), CGPoint(x: 75, y: 30), CGPoint(x: 95, y: 30)], style: thin), 2),
            (.line, Annotation(tool: .line, start: CGPoint(x: 55, y: 30), end: CGPoint(x: 95, y: 30), style: thin), 3),
            // The top of a circle of radius 20 centred at (75, 30) is the ink at x = 75, y = 10.
            (.ellipse, Annotation(tool: .ellipse, start: CGPoint(x: 55, y: 10), end: CGPoint(x: 95, y: 50), style: thin), 3),
        ]
        for scale in [CGFloat(1), 2] {
            for (tool, layer, points) in horizontal {
                let out = try await export(layer, scale: scale, name: "shots-new-\(tool)-\(Int(scale))")
                // On the white half the ink is the only thing that is not white: its green channel is low.
                let ink = column(out, x: Int(75 * scale)).map { Double(255 - Int($0[1])) / (255 - 41) }
                let rows = tool == .ellipse ? Array(ink[0..<(ink.count / 2)]) : ink
                // The pencil's grain leaves gaps in any one column: its thickness is, row by row, the most ink any
                // column of the stretch 60…90 pt has there, summed (the same measure as `ThePenAndThePencilLeaveTwoStrokesTests`'s
                // thin-step test), so a sub-pixel error shows as it does in a column of a grainless stroke.
                let stretch = tool == .pencil ? (Int(60 * scale)..<Int(90 * scale)).map { column(out, x: $0) } : []
                let thick = tool == .pencil
                    ? (0..<out.height).reduce(0.0) { sum, row in
                        sum + (stretch.map { Double(255 - Int($0[row][1])) / (255 - 41) }.max() ?? 0) }
                    : rows.reduce(0, +)
                XCTAssertEqual(thick, points * Double(scale), accuracy: 0.4,
                               "\(tool) at \(scale)x: the stroke is not \(points) points thick")
            }
        }
    }

    func testTheMarkerMultipliesADarkPixelStaysDarkAndAWhiteOneTakesTheTint() async throws {
        let marker = Annotation(tool: .highlighter, start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30),
                                points: [CGPoint(x: 10, y: 30), CGPoint(x: 50, y: 30), CGPoint(x: 90, y: 30)])
        for scale in [CGFloat(1), 2] {
            let out = try await export(marker, scale: scale, name: "shots-marker-\(Int(scale))")
            let row = Int(30 * scale)
            let dark = column(out, x: Int(30 * scale))[row], white = column(out, x: Int(70 * scale))[row]
            XCTAssertEqual(Int(dark[0]) + Int(dark[1]) + Int(dark[2]), 0, "\(scale)x: the marker lightened black text: \(dark)")
            XCTAssertEqual(white[0], 255, "\(scale)x: multiply by a tint with full red changed red: \(white)")
            XCTAssertLessThan(white[2], 160, "\(scale)x: the white pixel did not take the tint: \(white)")
            XCTAssertGreaterThan(white[1], 200, "\(scale)x: the tint is not the yellow: \(white)")
            // Thickness: the rows of the white half that took the tint.
            let tinted = column(out, x: Int(70 * scale)).filter { $0[2] < 250 }.count
            XCTAssertEqual(Double(tinted), Double(AnnotationThickness.medium.points(for: .highlighter) * scale), accuracy: 2 * Double(scale),
                           "\(scale)x: the marker is not its width times the scale")
            // Outside the stroke nothing changed.
            XCTAssertEqual(column(out, x: Int(70 * scale))[0], [255, 255, 255, 255])
        }
    }
}
