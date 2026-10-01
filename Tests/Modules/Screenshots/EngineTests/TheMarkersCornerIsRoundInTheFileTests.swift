import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A sharp turn of the marker is round in the exported pixels, not only in its declared
/// join.** The turn is a real cusp (a point given twice, so the smoothed path has a corner
/// there) and the file is read for ink beyond what a round-joined stroke of the same path
/// covers: a mitre throws a spike past it.
final class TheMarkersCornerIsRoundInTheFileTests: XCTestCase {

    private func ink(_ image: CGImage) -> [(x: Int, y: Int)] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var found: [(Int, Int)] = []
        for y in 0..<image.height {
            for x in 0..<image.width where bytes[y * image.width * 4 + x * 4 + 2] < 250 { found.append((x, y)) }
        }
        return found
    }

    private func export(_ layer: Annotation, scale: CGFloat, name: String) async throws -> CGImage {
        let image = makeImage(width: Int(200 * scale), height: Int(120 * scale), red: 255, green: 255, blue: 255)
        let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                            scale: scale, image: image))], windows: [])
        let rig = Rig(home: scratchDirectory(name))
        let drawn = await rig.session.annotated(freeze, display: DisplayID(1), local: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                layers: [layer])
        return try XCTUnwrap(drawn)
    }

    func testASharpTurnLeavesNoInkBeyondARoundJoinedStrokeOfTheSamePath() async throws {
        let corner = CGPoint(x: 150, y: 60)
        let points = [CGPoint(x: 20, y: 60), corner, corner, CGPoint(x: 20, y: 80)]
        for step in AnnotationThickness.allCases {
            for scale in [CGFloat(1), 2] {
                let layer = Annotation(tool: .highlighter, start: points[0], end: points[3], points: points,
                                       style: AnnotationStyle(thickness: step))
                let out = try await export(layer, scale: scale, name: "shots-corner-\(step.rawValue)-\(Int(scale))")
                let width = step.marker
                let round = layer.outline.copy(strokingWithWidth: width + 3, lineCap: .round, lineJoin: .round, miterLimit: 10)
                let found = ink(out)
                XCTAssertGreaterThan(found.count, Int(width * 100 * scale * scale / 2), "\(step) \(scale)x: the marker left no ink, so the test saw nothing")
                let spikes = found.filter { !round.contains(CGPoint(x: (CGFloat($0.x) + 0.5) / scale, y: (CGFloat($0.y) + 0.5) / scale)) }
                XCTAssertTrue(spikes.isEmpty, "\(step) \(scale)x: \(spikes.count) pixels of a spike past the round join, first \(spikes.first.map { "\($0)" } ?? "")")
                // The far end of a miter on this turn is beyond the corner by several widths; the rounded corner reaches half a width.
                XCTAssertTrue(found.allSatisfy { CGFloat($0.x) / scale <= corner.x + width / 2 + 2 },
                              "\(step) \(scale)x: ink past the corner's round")
            }
        }
    }
}
