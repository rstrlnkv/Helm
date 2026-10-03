import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The opacity picked is in the exported pixels, not only on the screen.** Each tool is exported over a
/// grey picture at 100 %, 50 % and 20 % (the marker at 100 %, 50 % and 25 %), and the file is read for the *darkest* pixel of one channel (green, which the red
/// ink takes well below the grey; for the marker, whose multiply darkens blue most, blue): at full ink that is the pure colour, below it the blend the maths gives, and a file that
/// drew the object opaque, or not at all, is neither. The expected numbers are computed here from the ink's
/// own components and the grey the file itself carries in its corner (the colour space moves 100 to 119), not read from the drawing code.
final class TheOpacityReachesTheFileTests: XCTestCase {

    private func export(_ layer: Annotation, scale: CGFloat, name: String) async throws -> CGImage {
        let image = makeImage(width: Int(200 * scale), height: Int(120 * scale), red: 100, green: 100, blue: 100)
        let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                            scale: scale, image: image))], windows: [])
        let rig = Rig(home: scratchDirectory(name))
        let drawn = await rig.session.annotated(freeze, display: DisplayID(1), local: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                layers: [layer])
        return try XCTUnwrap(drawn)
    }

    /// One channel (0 red, 1 green, 2 blue) of every pixel.
    private func channel(_ image: CGImage, _ index: Int) -> [Double] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).map { Double(bytes[$0 * 4 + index]) }
    }

    private func layer(_ tool: AnnotationTool, opacity: Double) -> Annotation {
        let from = CGPoint(x: 20, y: 60), to = CGPoint(x: 170, y: 60)
        let style = AnnotationStyle(color: .red, thickness: .thick, filled: false, opacity: opacity)
        switch tool {
        case .rectangle, .ellipse:
            return Annotation(tool: tool, start: CGPoint(x: 30, y: 25), end: CGPoint(x: 170, y: 95), style: style)
        case .pen, .pencil, .highlighter:
            return Annotation(tool: tool, start: from, end: to, points: [from, CGPoint(x: 95, y: 60), to], style: style)
        default:
            return Annotation(tool: tool, start: from, end: to, style: style)
        }
    }

    func testEveryToolsInkIsBlendedByItsOpacityInTheFile() async throws {
        // Red is (0.92, 0.16, 0.14): channel 1 (green, 0.16) is the one read here, over a grey of 100; its darkest channel is blue.
        let green = 0.16 * 255
        for tool in [AnnotationTool.arrow, .rectangle, .ellipse, .line, .pen, .pencil] {
            for scale in [CGFloat(1), 2] {
                for opacity in [1.0, 0.5, 0.2] {
                    let out = try await export(layer(tool, opacity: opacity), scale: scale,
                                               name: "shots-opacity-\(tool)-\(Int(scale))-\(Int(opacity * 10))")
                    let values = channel(out, 1)
                    let grey = values[0]  // the file's own background, a corner no object reaches
                    XCTAssertGreaterThan(grey, 60, "\(tool): the corner is not the background")
                    let expected = grey * (1 - opacity) + green * opacity
                    let darkest = values.min() ?? 255
                    XCTAssertEqual(darkest, expected, accuracy: 6, "\(tool) \(scale)x at \(opacity): the darkest pixel is \(darkest), the blend is \(expected)")
                    let atIt = values.filter { abs($0 - expected) <= 6 }.count
                    XCTAssertGreaterThan(atIt, 40, "\(tool) \(scale)x at \(opacity): only \(atIt) pixels carry the blend, so one lucky edge passed")
                    XCTAssertEqual(values.filter { $0 < expected - 8 }.count, 0, "\(tool) \(scale)x at \(opacity): ink more opaque than picked")
                }
            }
        }
    }

    func testTheMarkerMultipliesItsFixedTintByTheOpacityPicked() async throws {
        // The marker's own tint is 0.6 of its ink; the opacity multiplies it. Multiplied into grey, blue is the
        // darkest channel of the ink actually used (`layer` gives the marker red; read from `AnnotationColor`, not
        // typed here): grey * (1 - a + a * blue) with a = 0.6 * opacity.
        let inkBlue = Double(try XCTUnwrap(AnnotationColor.red.cgColor.components)[2])
        for scale in [CGFloat(1), 2] {
            for opacity in [1.0, 0.5, 0.25] {
                let out = try await export(layer(.highlighter, opacity: opacity), scale: scale,
                                           name: "shots-opacity-marker-\(Int(scale))-\(Int(opacity * 100))")
                let tint = 0.6 * opacity
                let values = channel(out, 2)
                let grey = values[0]  // the file's own background, a corner no object reaches
                let expected = grey * (1 - tint + tint * inkBlue)
                let darkest = values.min() ?? 255
                XCTAssertEqual(darkest, expected, accuracy: 1.5, "marker \(scale)x at \(opacity): the darkest pixel is \(darkest), the multiply gives \(expected)")
                XCTAssertGreaterThan(values.filter { abs($0 - expected) <= 1.5 }.count, 40, "marker \(scale)x at \(opacity): one lucky edge passed")
            }
        }
    }

    /// What the screen draws and the file draws is one description: the alpha is in the stroke and in the fill.
    func testTheScreensInkCarriesTheSameAlpha() {
        XCTAssertEqual(layer(.pen, opacity: 0.5).stroke?.color.alpha, 0.5)
        XCTAssertEqual(layer(.pencil, opacity: 0.5).stroke?.color.alpha, 0.5)
        XCTAssertEqual(layer(.line, opacity: 0.5).stroke?.color.alpha, 0.5)
        XCTAssertEqual(layer(.rectangle, opacity: 0.5).stroke?.color.alpha, 0.5)
        XCTAssertEqual(layer(.pen, opacity: 1).stroke?.color.alpha, 1)
        XCTAssertEqual(layer(.arrow, opacity: 0.5).fillColor.alpha, 0.5, "the arrow is a fill and its fill ignores the opacity")
        let filledBox = Annotation(tool: .rectangle, start: .zero, end: CGPoint(x: 50, y: 50),
                                   style: AnnotationStyle(color: .red, filled: true, opacity: 0.5))
        XCTAssertEqual(filledBox.fillColor.alpha, 0.5)
        XCTAssertEqual(layer(.highlighter, opacity: 1).stroke?.color.alpha ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(layer(.highlighter, opacity: 0.5).stroke?.color.alpha ?? 0, 0.3, accuracy: 0.001,
                       "the marker's tint and the opacity do not multiply")
        XCTAssertEqual(layer(.highlighter, opacity: 0.5).stroke?.multiplies, true)
    }
}
