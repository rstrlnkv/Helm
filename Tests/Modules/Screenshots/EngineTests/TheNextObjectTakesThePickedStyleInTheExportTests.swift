import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A picked colour, thickness and fill are the next object's and the export's.** The
/// style is a value the object is begun with: the layers already drawn keep theirs, and
/// what the file shows is read back out of the rendered picture, not out of the style.
final class TheNextObjectTakesThePickedStyleInTheExportTests: XCTestCase {

    private let area = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func freeze(scale: CGFloat, color: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> Freeze {
        let image = makeImage(width: Int(100 * scale), height: Int(60 * scale), red: color.0, green: color.1, blue: color.2)
        return Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                                                      scale: scale, image: image))], windows: [])
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<3).map { Int(bytes[y * image.width * 4 + x * 4 + $0]) }
    }

    private func export(_ layers: [Annotation], scale: CGFloat = 1, over: (UInt8, UInt8, UInt8) = (255, 255, 255),
                        name: String) async throws -> CGImage {
        let rig = Rig(home: scratchDirectory(name))
        let drawn = await rig.session.annotated(freeze(scale: scale, color: over), display: DisplayID(1),
                                                local: CGRect(x: 0, y: 0, width: 100, height: 60), layers: layers)
        return try XCTUnwrap(drawn)
    }

    // MARK: the value

    func testTheStyleAtBeginIsTheObjectsAndALaterPickIsTheNextOnes() {
        var editing = AnnotationEditing(bounds: area)
        let blue = AnnotationStyle(color: .blue, thickness: .thick, filled: true)
        editing.begin(.rectangle, at: CGPoint(x: 10, y: 10), style: blue)
        editing.drag(to: CGPoint(x: 90, y: 60), shift: false)
        XCTAssertEqual(editing.draft?.style, blue)
        editing.drag(to: CGPoint(x: 120, y: 80), shift: true)
        XCTAssertEqual(editing.draft?.style, blue, "reshaping the draft dropped its style")
        editing.end()
        editing.begin(.line, at: CGPoint(x: 5, y: 5))
        editing.drag(to: CGPoint(x: 50, y: 50), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.map(\.style), [blue, .standard], "the second object took the first one's style or the first lost it")
    }

    func testEveryToolKeepsItsStyleThroughADragAndAShiftFlip() {
        let style = AnnotationStyle(color: .green, thickness: .medium, filled: false)
        for tool in AnnotationTool.allCases {
            var editing = AnnotationEditing(bounds: area)
            editing.begin(tool, at: CGPoint(x: 10, y: 10), style: style)
            editing.drag(to: CGPoint(x: 90, y: 40), shift: false)
            editing.modifiersChanged(shift: true)
            editing.modifiersChanged(shift: false)
            XCTAssertEqual(editing.draft?.style, style, "\(tool)")
        }
    }

    func testTheInkIsTheToolsOwnUntilAColourIsPickedAndThenEveryTools() {
        let none = AnnotationStyle.standard
        XCTAssertEqual(none.ink(for: .highlighter), .yellow)
        for tool in AnnotationTool.allCases where tool != .highlighter { XCTAssertEqual(none.ink(for: tool), .red, "\(tool)") }
        let blue = AnnotationStyle(color: .blue)
        for tool in AnnotationTool.allCases { XCTAssertEqual(blue.ink(for: tool), .blue, "\(tool)") }
        XCTAssertEqual(Annotation(tool: .highlighter, start: .zero, end: CGPoint(x: 9, y: 9)).stroke?.color,
                       Annotation.markerInk, "the unpicked marker is not yesterday's yellow")
    }

    func testThicknessScalesTheOutlineTheShaftAndTheMarkerTogether() {
        let widths = AnnotationThickness.allCases.map { step in
            AnnotationStyle(thickness: step)
        }.map { style in
            (Annotation(tool: .line, start: .zero, end: CGPoint(x: 9, y: 9), style: style).stroke!.width,
             Annotation(tool: .highlighter, start: .zero, end: CGPoint(x: 9, y: 9), points: [.zero, CGPoint(x: 9, y: 9)], style: style).stroke!.width)
        }
        XCTAssertEqual(widths.map(\.0), [3, 5, 8])
        XCTAssertEqual(widths.map(\.1), [16, 24, 32], "the marker did not scale with its own step")
        XCTAssertEqual(widths[0].0, Annotation.lineWidth)
        XCTAssertEqual(widths[0].1, Annotation.markerWidth)
        let heads = AnnotationThickness.allCases.map {
            Annotation(tool: .arrow, start: .zero, end: CGPoint(x: 200, y: 0), style: AnnotationStyle(thickness: $0)).outline.boundingBox.height
        }
        XCTAssertEqual(heads, AnnotationThickness.allCases.map { $0.shaft * 3 }, "the arrow's head did not follow its step")
    }

    func testOnlyTheBoxesAreEverFilledAndOnlyWhenAsked() {
        for tool in AnnotationTool.allCases {
            let filled = Annotation(tool: tool, start: .zero, end: CGPoint(x: 9, y: 9), style: AnnotationStyle(filled: true))
            XCTAssertEqual(filled.isFilled, [.arrow, .rectangle, .ellipse].contains(tool), "\(tool)")
            XCTAssertEqual(filled.stroke == nil, filled.isFilled, "\(tool): a filled shape is also stroked, or an unfilled one is not")
            let plain = Annotation(tool: tool, start: .zero, end: CGPoint(x: 9, y: 9))
            XCTAssertEqual(plain.isFilled, tool == .arrow, "\(tool)")
        }
    }

    // MARK: the file

    func testAPickedColourIsTheColourInTheFileAndAnOutlineLeavesTheInsideAlone() async throws {
        let box = Annotation(tool: .rectangle, start: CGPoint(x: 20, y: 10), end: CGPoint(x: 80, y: 50),
                             style: AnnotationStyle(color: .blue))
        let out = try await export([box], name: "shots-style-outline")
        let edge = pixel(out, x: 50, y: 10)
        XCTAssertEqual(edge[0], 26, accuracy: 6, "the outline is not the blue's red: \(edge)")
        XCTAssertEqual(edge[2], 242, accuracy: 6, "the outline is not the blue's blue: \(edge)")
        XCTAssertEqual(pixel(out, x: 50, y: 30), [255, 255, 255], "an outline painted its inside")
    }

    func testFillPaintsTheInsideInTheColour() async throws {
        let box = Annotation(tool: .ellipse, start: CGPoint(x: 20, y: 10), end: CGPoint(x: 80, y: 50),
                             style: AnnotationStyle(color: .green, filled: true))
        let out = try await export([box], name: "shots-style-fill")
        let inside = pixel(out, x: 50, y: 30)
        XCTAssertEqual(inside[0], 51, accuracy: 6, "the inside is not the green: \(inside)")
        XCTAssertEqual(inside[1], 199, accuracy: 6, "the inside is not the green: \(inside)")
        XCTAssertEqual(pixel(out, x: 5, y: 5), [255, 255, 255], "the fill left its shape")
        let arrow = Annotation(tool: .arrow, start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30),
                               style: AnnotationStyle(color: .black))
        let drawn = try await export([arrow], name: "shots-style-arrow")
        XCTAssertEqual(pixel(drawn, x: 70, y: 30), [0, 0, 0], "the arrow is not in the picked colour")
    }

    func testThicknessIsPointsTimesTheScaleInTheFile() async throws {
        for scale in [CGFloat(1), 2] {
            for step in AnnotationThickness.allCases {
                let line = Annotation(tool: .line, start: CGPoint(x: 10, y: 30), end: CGPoint(x: 90, y: 30),
                                      style: AnnotationStyle(thickness: step))
                let out = try await export([line], scale: scale, name: "shots-style-thick-\(step.rawValue)-\(Int(scale))")
                var ink = 0
                for y in 0..<out.height where pixel(out, x: Int(50 * scale), y: y)[1] < 128 { ink += 1 }
                XCTAssertEqual(Double(ink), Double(step.line * scale), accuracy: 1.5, "\(step) at \(scale)x")
            }
        }
    }

    func testAPickedColourReachesTheMarkerAndStillMultiplies() async throws {
        let points = [CGPoint(x: 10, y: 30), CGPoint(x: 50, y: 30), CGPoint(x: 90, y: 30)]
        let blue = Annotation(tool: .highlighter, start: points[0], end: points[2], points: points,
                              style: AnnotationStyle(color: .blue))
        let over = try await export([blue], over: (200, 200, 200), name: "shots-style-marker-blue")
        let hit = pixel(over, x: 50, y: 30)
        XCTAssertGreaterThan(hit[2], hit[0] + 40, "the marker is not blue: \(hit)")
        let unpicked = Annotation(tool: .highlighter, start: points[0], end: points[2], points: points)
        let yellow = try await export([unpicked], name: "shots-style-marker-yellow")
        let own = pixel(yellow, x: 50, y: 30)
        XCTAssertEqual(own[0], 255); XCTAssertLessThan(own[2], 160, "the unpicked marker is not its own yellow: \(own)")
    }

    // MARK: the joins

    func testTheMarkerHasRoundJoinsAndButtCapsAndEveryoneElsesAreUnchanged() {
        let marker = Annotation(tool: .highlighter, start: .zero, end: CGPoint(x: 9, y: 9), points: [.zero, CGPoint(x: 9, y: 9)]).stroke!
        XCTAssertEqual(marker.join, .round, "a freehand 16 pt stroke is mitred and spikes at a sharp turn")
        XCTAssertEqual(marker.cap, .butt)
        let shapes = [AnnotationTool.rectangle, .ellipse].map { Annotation(tool: $0, start: .zero, end: CGPoint(x: 9, y: 9)).stroke! }
        XCTAssertTrue(shapes.allSatisfy { $0.cap == .butt && $0.join == .miter })
        let free = [AnnotationTool.line, .pencil].map { Annotation(tool: $0, start: .zero, end: CGPoint(x: 9, y: 9)).stroke! }
        XCTAssertTrue(free.allSatisfy { $0.cap == .round && $0.join == .round })
    }

    func testAMarkerWithNoPointsIsNothingNotAStraightFallback() {
        let bare = Annotation(tool: .highlighter, start: .zero, end: CGPoint(x: 90, y: 0))
        XCTAssertFalse(bare.isUsable, "a marker with no freehand points was drawn as a straight line")
        XCTAssertTrue(bare.outline.isEmpty)
    }
}
